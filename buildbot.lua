--[[

 A build bot for popular Lua projects.

 Author: Peter Odding <peter@peterodding.com>
 Last Change: September 11, 2011
 Homepage: http://peterodding.com/code/lua/buildbot
 License: MIT

 This Lua script implements a build bot to automatically build the latest
 releases of Lua, LuaJIT 1 and LuaJIT 2. When I start this build bot on my
 Ubuntu Linux installation, it starts a headless virtual machine using
 VirtualBox. Inside the virtual machine, this script is set to launch
 automatically when the virtual machine is booted. When this script is executed
 on Windows it performs the following steps for each project:

  - Find latest available release from homepage
  - Download archive (if not already downloaded)
  - Unpack and build project
  - Copy files to be released (binaries & headers)

]]

local version = '0.2.1'

-- You may have to change this.
local sdk_setenv_tool = [[C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.Cmd]]
local scp_target = 'vps:/home/peterodding.com/public/files/code/lua/buildbot/downloads'

-- Load the Lua/APR binding.
local apr = require 'apr'

-- Find absolute path of build bot's root directory.
local root = apr.filepath_parent(apr.filepath_merge('.', arg[0], 'true-name'))

-- Define absolute paths of intermediate directories.
local archives = apr.filepath_merge(root, 'archives')
local binaries = apr.filepath_merge(root, 'binaries')
local builds = apr.filepath_merge(root, 'builds')
local buildlog = apr.filepath_merge(root, 'buildbot.log')

-- Generic build bot functionality. {{{1

local function message(fmt, ...)
  io.stderr:write(fmt:format(...), '\n')
end

local function download(url) -- {{{2
  local components = assert(apr.uri_parse(url))
  assert(components.scheme == 'http', "invalid protocol!")
  local port = assert(components.port or apr.uri_port_of_scheme(components.scheme))
  local socket = assert(apr.socket_create())
  assert(socket:connect(components.hostname, port))
  local pathinfo = assert(apr.uri_unparse(components, 'pathinfo'))
  assert(socket:write('GET ', pathinfo, ' HTTP/1.0\r\n',
                      'Host: ', components.hostname, '\r\n',
                      '\r\n'))
  local statusline = assert(socket:read(), 'HTTP response missing status line!')
  local _, statuscode, reason = assert(statusline:match '^(%S+)%s+(%S+)%s+(.-)$')
  local redirect = statuscode:find '^30[123]$'
  for line in socket:lines() do
    local name, value = line:match '^(%S+):%s+(.-)\r?$'
    if name and value then
      if redirect and name:lower() == 'location' then
        return download(value)
      end
    else
      return (assert(socket:read '*a', 'HTTP response missing body?!'))
    end
  end
  if statuscode ~= '200' then error(reason) end
end

local function write_file(path, data, binary) -- {{{2
  local handle = assert(io.open(path, binary and 'wb' or 'w'))
  assert(handle:write(data))
  assert(handle:close())
end

local function unpack_archive(archive) -- {{{2

  -- Get the base name of the source code archive.
  local basename = archive
      :gsub('%.gz$', '')
      :gsub('%.tar$', '')
      :gsub('%.zip$', '')
  local builddir = apr.filepath_merge(builds, apr.filepath_name(basename))
  message("Unpacking %s to %s", archive, builddir)

  -- The tar.exe included in my UnxUtils installation doesn't seem to support
  -- gzip compressed archives, so we uncompress archives manually.
  if archive:find '%.gz$' then
    message("Uncompressing %s", archive)
    local backup = archive .. '.tmp'
    apr.file_copy(archive, backup)
    os.execute('gunzip -f ' .. archive)
    apr.file_rename(backup, archive)
    archive = archive:gsub('%.gz$', '')
  end

  if archive:find '%.zip$' then
    -- Unpack ZIP archives using the unzip command included in UnxUtils.
    message("Unpacking ZIP archive %s", archive)
    apr.filepath_set(builds)
    assert(os.execute('unzip -qo ' .. archive) == 0)
  elseif archive:find '%.tar$' then
    -- Unpack TAR archives using the tar command included in UnxUtils.
    message("Unpacking TAR archive %s", archive)
    apr.filepath_set(builds)
    assert(os.execute('tar xf ' .. archive) == 0)
  else
    error("Unsupported archive type!")
  end

  return builddir

end

local function download_archive(url) -- {{{2
  local name = apr.filepath_name(url)
  local path = apr.filepath_merge(archives, name)
  if apr.stat(path, 'type') ~= 'file' then
    message("Downloading %s to %s", url, path)
    write_file(path, download(url), true)
  end
  return unpack_archive(path)
end

local function copy_binary(oldfile, newfile) -- {{{2
  -- Automatically create target directory.
  local directory = apr.filepath_parent(newfile)
  if apr.stat(directory, 'type') ~= 'directory' then
    assert(apr.dir_make_recursive(directory))
  end
  -- Copy file.
  message("Copying %s -> %s", oldfile, newfile)
  assert(apr.file_copy(oldfile, newfile))
end

local function string_gsplit(string, pattern, capture) -- {{{2
 string = string and tostring(string) or ''
 pattern = pattern and tostring(pattern) or '%s+'
 if (''):find(pattern) then
  error('pattern matches empty string!', 2)
 end
 return coroutine.wrap(function()
  local index = 1
  repeat
   local first, last = string:find(pattern, index)
   if first and last then
    if index < first then coroutine.yield(string:sub(index, first - 1)) end
    if capture then coroutine.yield(string:sub(first, last)) end
    index = last + 1
   else
    if index <= #string then coroutine.yield(string:sub(index)) end
    break
   end
  until index > #string
 end)
end

local function version_sort(strings, strip_extensions) -- {{{2
  local function tokenize(s)
    local parts = {}
    if strip_extensions then
      s = s:gsub('%.gz$', '')
      s = s:gsub('%.tar$', '')
      s = s:gsub('%.tgz$', '')
      s = s:gsub('%.zip$', '')
    end
    for p in string_gsplit(s, '%d+', true) do
      table.insert(parts, tonumber(p) or p)
    end
    return parts
  end
  table.sort(strings, function(left, right)
    local left_tokens = tokenize(left)
    local right_tokens = tokenize(right)
    for i = 1, math.max(#left_tokens, #right_tokens) do
      local left_value = left_tokens[i] or '!'
      local right_value = right_tokens[i] or '!'
      if type(left_value) ~= type(right_value) then
        left_value, right_value = tostring(left_value), tostring(right_value)
      end
      if left_value < right_value then return true end
      if left_value > right_value then return false end
    end
  end)
  return strings
end

local function run_build(project, directory, command) -- {{{2
  local batchfile = apr.filepath_merge(root, 'build-' .. project .. '.cmd')
  assert(apr.filepath_set(directory))
  write_file(batchfile, string.format([[
CALL "%s" /release /x86
%s
]], sdk_setenv_tool, command))
  assert(os.execute(batchfile) == 0)
  os.remove(batchfile)
end

-- Build instructions for specific projects. {{{1

local function copy_lua_files(builddir, release, variant) -- {{{2
  local files = {
    'src/lauxlib.h', 'src/lua.h', 'src/lua51.dll',
    'src/lua51.lib', 'src/luaconf.h', 'src/lualib.h',
    variant:find 'luajit' and 'src/luajit.exe' or 'src/lua.exe',
    variant:find 'luajit2' and 'src/lua.hpp' or 'etc/lua.hpp',
    (not variant:find 'luajit') and 'src/luac.exe' or nil,
  }
  for _, filename in ipairs(files) do
    local basename = apr.filepath_name(filename)
    copy_binary(apr.filepath_merge(builddir, filename), apr.filepath_merge(binaries, release .. '/' .. basename))
  end
end

-- Lua reference implementation from http://lua.org. {{{2

local function find_lua_release() -- {{{3
  local page = assert(download 'http://www.lua.org/ftp/')
  local releases = {}
  for archive in page:gmatch 'HREF="(lua%-%d[^"]-%.tar%.gz)"' do
    local url = 'http://www.lua.org/ftp/' .. archive
    table.insert(releases, url)
  end
  return table.remove(version_sort(releases, true))
end

local function build_lua(builddir) -- {{{3
  local release = apr.filepath_name(builddir)
  run_build(release, builddir, [[CALL etc\luavs.bat]])
  copy_lua_files(builddir, release, 'lua')
end

-- LuaJIT 1 & 2 from http://luajit.org. {{{2

local function find_luajit_releases() -- {{{3
  local page = download 'http://luajit.org/download.html'
  local lj1_releases = {}
  local lj2_releases = {}
  for path, name in page:gmatch 'href="([^"]-)([^"/]-%.zip)"' do
    local url = 'http://luajit.org/' .. path .. name
    if name:find '^LuaJIT%-1' then
      table.insert(lj1_releases, url)
    elseif name:find '^LuaJIT%-2' then
      table.insert(lj2_releases, url)
    else
      error("Failed to classify download: " .. url)
    end
  end
  local lj1_latest = table.remove(version_sort(lj1_releases, true))
  local lj2_latest = table.remove(version_sort(lj2_releases, true))
  return lj1_latest, lj2_latest
end

local function build_luajit1(builddir) -- {{{3
  local release = apr.filepath_name(builddir)
  run_build(release, builddir, 'etc\\luavs.bat')
  copy_lua_files(builddir, release, 'luajit1')
end

local function build_luajit2(builddir) -- {{{3
  local release = apr.filepath_name(builddir)
  run_build(release, apr.filepath_merge(builddir, 'src'), 'msvcbuild.bat')
  copy_lua_files(builddir, release, 'luajit2')
end

local function main() -- {{{1

  -- Create the top level directories.
  apr.dir_make(archives)
  apr.dir_make(binaries)
  apr.dir_make(builds)

  if apr.platform_get() == 'UNIX' then

    -- Start from a clean slate.
    assert(apr.dir_remove_recursive(builds))
    assert(apr.dir_make(builds))
    assert(apr.dir_remove_recursive(binaries))
    assert(apr.dir_make(binaries))

    -- Run build bot in dedicated, headless Windows XP virtual machine.
    write_file(buildlog, '', false)
    os.execute('tail -fn0 ' .. buildlog .. ' &')
    assert(os.execute "VBoxHeadless -startvm 'Lua build bot'" == 0)

    -- Check that the expected files were created.
    local files = {
      { 'Lua 5.1.4', {
        'lua-5.1.4/lauxlib.h',
        'lua-5.1.4/lua.exe',
        'lua-5.1.4/lua.h',
        'lua-5.1.4/lua.hpp',
        'lua-5.1.4/lua51.dll',
        'lua-5.1.4/lua51.lib',
        'lua-5.1.4/luac.exe',
        'lua-5.1.4/luaconf.h',
        'lua-5.1.4/lualib.h',
      }},
      { 'LuaJIT 1.1.7', {
        'LuaJIT-1.1.7/lauxlib.h',
        'LuaJIT-1.1.7/luajit.exe',
        'LuaJIT-1.1.7/lua.h',
        'LuaJIT-1.1.7/lua.hpp',
        'LuaJIT-1.1.7/lua51.dll',
        'LuaJIT-1.1.7/lua51.lib',
        'LuaJIT-1.1.7/luaconf.h',
        'LuaJIT-1.1.7/lualib.h',
      }},
      { 'LuaJIT 2.0.0-beta8', {
        'LuaJIT-2.0.0-beta8/lauxlib.h',
        'LuaJIT-2.0.0-beta8/luajit.exe',
        'LuaJIT-2.0.0-beta8/lua.h',
        'LuaJIT-2.0.0-beta8/lua.hpp',
        'LuaJIT-2.0.0-beta8/lua51.dll',
        'LuaJIT-2.0.0-beta8/lua51.lib',
        'LuaJIT-2.0.0-beta8/luaconf.h',
        'LuaJIT-2.0.0-beta8/lualib.h',
      }},
    }

    local success = true
    for _, project in ipairs(files) do
      for _, filename in ipairs(project[2]) do
        local pathname = apr.filepath_merge(binaries, filename)
        if apr.stat(pathname, 'type') ~= 'file' then
          message("Missing expected file: %s", pathname)
          success = false
        end
      end
    end

    if success then
      for directory in apr.dir_open(binaries):entries('path') do
        local archive = apr.filepath_name(directory) .. '.zip'
        message("Generating %s ..", archive)
        assert(apr.filepath_set(directory))
        assert(os.execute(string.format('zip -r ../%s .', archive)) == 0)
        message("Uploading %s ..", archive)
        assert(os.execute(string.format('scp ../%s %s/%s', archive, scp_target, archive)))
      end
    end

    os.exit(success and 0 or 1)

  elseif apr.platform_get() == 'WIN32' then

    -- We're inside the virtual machine! (this script is started automatically after boot)

    -- Build the most recent release of the Lua reference implementation.
    lua_latest = find_lua_release()
    build_lua(download_archive(lua_latest))

    -- Build the most recent releases of LuaJIT 1 and 2.
    lj1_latest, lj2_latest = find_luajit_releases()
    build_luajit1(download_archive(lj1_latest))
    build_luajit2(download_archive(lj2_latest))

    -- Shutdown the Windows virtual machine after building all packages (only
    -- when the build bot was started automatically). This returns control back
    -- to the UNIX section above (VBoxHeadless blocks while the VM is running).
    if arg[1] == 'auto' then
      assert(os.execute 'shutdown -s -t 0' == 0)
    end

  else
    error "Platform unsupported!"
  end
end

-- }}}1

main()

-- vim: ts=2 sw=2 et fdm=marker

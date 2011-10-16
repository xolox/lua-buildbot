--[[

 A build bot for popular Lua projects.

 Author: Peter Odding <peter@peterodding.com>
 Last Change: October 16, 2011
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

local version = '0.4'

-- When I run the build bot it automatically uploads generated binaries to my
-- website. This will obviously not work for anyone else, so if you leave the
-- variable undefined / set it to nil the build bot will just skip the step
-- that uploads generated binaries without complaining.
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

-- Forward declaration for location of Windows SDK.
local windows_sdk_folder, sdk_setenv_tool

-- Generic build bot functionality. {{{1

local function message(fmt, ...)
  io.stdout:write(fmt:format(...), '\n')
  io.stdout:flush()
end

local function write_file(path, data, binary) -- {{{2
  local handle = assert(io.open(path, binary and 'wb' or 'w'))
  assert(handle:write(data))
  assert(handle:close())
end

local function absolute_url(url, defaults) -- {{{2
  url = assert(apr.uri_parse(url))
  defaults = assert(apr.uri_parse(defaults))
  for key, value in pairs(defaults) do
    if not url[key] then
      url[key] = value
    end
  end
  return apr.uri_unparse(url)
end

local function download(url) -- {{{2
  local components = assert(apr.uri_parse(url))
  if components.scheme == 'http' then
    -- Download over HTTP using a Lua module (in this case my Lua/APR binding).
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
  else
    -- Download over HTTPS (SSL) using an external program (wget from UnxUtils).
    local tempfile = os.tmpname()
    assert(os.execute(string.format('wget -q "-O%s" "%s"', tempfile, url)) == 0, "Failed to download over HTTPS using wget!")
    local handle = assert(io.open(tempfile, 'rb'), "Failed to open temporary file written by wget!")
    local data = assert(handle:read('*a'), "Failed to read temporary file written by wget!")
    assert(handle:close())
    assert(os.remove(tempfile))
    return data
  end
end

local function stripext(filename) -- {{{2
  return filename
    :gsub('%.gz$', '')
    :gsub('%.tar$', '')
    :gsub('%.tgz$', '')
    :gsub('%.zip$', '')
end

local function context_from_url(url, file)
  local file = apr.filepath_name(file or url):lower()
  local basename = stripext(file)
  return {
    url = url,
    release = basename,
    archive = apr.filepath_merge(archives, file),
    build = apr.filepath_merge(builds, basename),
    binaries = apr.filepath_merge(binaries, basename),
  }
end

local function listdir(path)
  local entries = {}
  for name in apr.dir_open(path):entries 'name' do
    table.insert(entries, name)
  end
  table.sort(entries)
  return entries
end

local function unpack_archive(context) -- {{{2

  -- Get the base name of the source code archive.
  local archive = context.archive
  message("Unpacking %s to %s", archive, context.build)

  -- Remember which files were in the top level build directory before we
  -- unpacked the release archive, so that we know which files are new.
  local entries_before = listdir(builds)

  -- The tar.exe included in my UnxUtils installation doesn't seem to support
  -- gzip compressed archives, so we uncompress those archives manually.
  local delete_uncompressed
  if archive:find '%.gz$' then
    message("Uncompressing %s", archive)
    local backup = archive .. '.tmp'
    apr.file_copy(archive, backup)
    os.execute('gunzip -f ' .. archive)
    apr.file_rename(backup, archive)
    archive = archive:gsub('%.gz$', '')
    delete_uncompressed = archive
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
    error "Unsupported archive type!"
  end

  -- Cleanup previously uncompressed archives.
  if delete_uncompressed then
    os.remove(delete_uncompressed)
  end

  -- Find where the file(s) that we just unpacked were saved by looking for the
  -- difference between the before/after directory listings and make sure the
  -- files are where we expect them to be.
  local entries_after = listdir(builds)
  local num_differences = 0
  local unpacked_directory
  for i = 1, #entries_after do
    if entries_before[i] ~= entries_after[i] then
      unpacked_directory = table.remove(entries_after, i)
      num_differences = num_differences + 1
    end
  end
  assert(num_differences == 1)
  if unpacked_directory ~= context.release then
    message("Renaming unpacked directory %s -> %s", unpacked_directory, context.release)
    assert(apr.file_rename(unpacked_directory, context.release))
  end

end

local function download_archive(context) -- {{{2
  if apr.stat(context.archive, 'type') == 'file' then
    message("The archive %s was previously downloaded", context.archive)
  else
    message("Downloading %s to %s", context.url, context.archive)
    write_file(context.archive, download(context.url), true)
  end
  unpack_archive(context)
  return context
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
  local function tokenize(str)
    local tokens = {}
    if strip_extensions then
      str = stripext(str)
    end
    for token in string_gsplit(str, '%d+', true) do
      table.insert(tokens, tonumber(token) or token)
    end
    return tokens
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

local function find_sdk_helper(root)
  local command = [[REG QUERY "%s\SOFTWARE\Microsoft\Microsoft SDKs\Windows" /v CurrentInstallFolder 2>NUL]]
  local pipe = io.popen(command:format(root))
  local install_folder
  for line in pipe:lines() do
    install_folder = line:match '^%s*CurrentInstallFolder%s+REG_SZ%s+(.+)%s*$'
    if install_folder then break end
  end
  pipe:close()
  return install_folder
end

local function run_build(project, directory, command) -- {{{2
  message("Building %s ..", project)
  local batch_commands = string.format([[
    @CALL "%s" /x86 /release >NUL 2>&1
    @CD %s
    %s
  ]], sdk_setenv_tool, directory, command)
  local batch_file = os.tmpname() .. '.cmd'
  write_file(batch_file, batch_commands, false)
  local shell = assert(apr.proc_create 'cmd')
  assert(shell:cmdtype_set 'program/env/path')
  assert(shell:dir_set(directory))
  assert(shell:exec { '/c', batch_file })
  return function()
    assert(shell:wait(true))
    os.remove(batch_file)
    message("Finished %s build!", project)
  end
end

-- Build instructions for specific projects. {{{1

local function auto_create_dir(path, parent)
  if parent then
    path = apr.filepath_parent(path)
  end
  if apr.stat(path, 'type') ~= 'directory' then
    apr.dir_make_recursive(path)
    assert(apr.stat(path, 'type') == 'directory')
  end
end

local function copy_recursive(source, target)
  for type, entry in apr.dir_open(source):entries('type', 'name') do
    local source_entry = apr.filepath_merge(source, entry)
    local target_entry = apr.filepath_merge(target, entry)
    if type == 'directory' then
      copy_recursive(source_entry, target_entry)
    elseif type == 'file' then
      message("Copying %s -> %s", source_entry, target_entry)
      auto_create_dir(target_entry, true)
      assert(apr.file_copy(source_entry, target_entry))
    end
  end
end

local function copy_files(sourcedir, targetdir, files)
  -- This function got kind of complicated because it
  -- supports renaming, optional files and recursive copying.
  for line in files:gmatch '[^\n]+' do
    local source, target = line:match '^(.-)%->(.-)$'
    if not (source and target) then
      source = line:match '^%s*(.-)%s*$'
      target = source
    end
    if source ~= '' and target ~= '' then
      source = apr.filepath_merge(sourcedir, source:match '^%s*(.-)%s*$')
      target = apr.filepath_merge(targetdir, target:match '^%s*(.-)%s*$')
      local kind = apr.stat(source, 'type')
      if kind then
        if kind == 'directory' then
          copy_recursive(source, target)
        elseif kind == 'file' then
          auto_create_dir(target, true)
          message("Copying %s -> %s", source, target)
          assert(apr.file_copy(source, target))
        end
      end
    end
  end
end

local function copy_lua_files(context) -- {{{2
  -- This handles Lua 5.1, LuaJIT 1 and LuaJIT 2.
  copy_files(context.build, context.binaries, [[
    COPYRIGHT -> COPYRIGHT.txt
    HISTORY -> HISTORY.txt
    INSTALL -> INSTALL.txt
    README -> README.txt
    doc/
    etc/lua.hpp
    etc/lua.ico
    etc/luajit.ico
    etc/strict.lua
    jit/
    lib/ -> jit/
    jitdoc/
    src/lauxlib.h
    src/lua.exe -> lua.exe
    src/lua.h
    src/lua.hpp -> etc/lua.hpp
    src/lua51.dll -> lua51.dll
    src/lua51.lib
    src/luac.exe -> luac.exe
    src/luaconf.h
    src/luajit.exe -> luajit.exe
    src/lualib.h
    test/
  ]])
end

-- Lua reference implementation from http://lua.org. {{{2

local function find_lua_release() -- {{{3
  local page = assert(download 'http://www.lua.org/ftp/')
  local releases = {}
  for archive in page:gmatch 'HREF="(lua%-%d[^"]-%.tar%.gz)"' do
    local url = 'http://www.lua.org/ftp/' .. archive
    table.insert(releases, url)
  end
  assert(#releases >= 1, "Failed to find any Lua releases!")
  local sorted_releases = version_sort(releases, true)
  local latest_release = table.remove(sorted_releases)
  return context_from_url(latest_release)
end

local function build_lua(context) -- {{{3
  local wait_for_build = run_build(context.release, context.build, [[CALL etc\luavs.bat]])
  return function()
    wait_for_build()
    copy_lua_files(context)
  end
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
  return context_from_url(lj1_latest), context_from_url(lj2_latest)
end

local function build_luajit1(context) -- {{{3
  local wait_for_build = run_build(context.release, context.build, 'etc\\luavs.bat')
  return function()
    wait_for_build()
    copy_lua_files(context)
  end
end

local function build_luajit2(context) -- {{{3
  local wait_for_build = run_build(context.release, apr.filepath_merge(context.build, 'src'), 'msvcbuild.bat')
  return function()
    wait_for_build()
    copy_lua_files(context)
  end
end

-- LPeg. {{{2

local function find_lpeg_release()
  local url = 'http://www.inf.puc-rio.br/~roberto/lpeg/'
  local page = download(url)
  for target in page:gmatch '<[Aa]%s+[Hh][Rr][Ee][Ff]="(.-)"' do
    if target:find 'lpeg%-[0-9.]-%.tar%.gz$' then
      -- TODO Right now the LPeg homepage only contains a link to the latest release, still this is kind of a hack...
      return context_from_url(absolute_url(target, url))
    end
  end
  error "Failed to find LPeg release online!"
end

local function build_lpeg(lpeg_release, lua_release)
  -- Start the build using a custom command (LPeg doesn't come with a Windows makefile or batch script).
  local command = 'CL.EXE /nologo /I"%s/src" lpeg.c /link /dll /out:lpeg.dll /export:luaopen_lpeg "/libpath:%s/src" lua51.lib'
  local wait_for_build = run_build(lpeg_release.release, lpeg_release.build, command:format(lua_release.binaries, lua_release.binaries))
  return function()
    -- Wait for the build to finish and copy the resulting files.
    wait_for_build()
    copy_files(lpeg_release.build, lpeg_release.binaries, [[
      HISTORY -> HISTORY.txt
      lpeg-128.gif -> doc/lpeg-128.gif
      lpeg.dll
      lpeg.h -> src/lpeg.h
      lpeg.html -> doc/lpeg.html
      lpeg.lib -> src/lpeg.lib
      re.html -> doc/re.html
      re.lua
      test.lua -> test/test.lua
    ]])
  end
end

-- LuaSocket. {{{2

local function find_luasocket_release()
  local url = 'http://files.luaforge.net/releases/luasocket/luasocket'
  local page = download(url)
  local releases = {}
  for _, target in page:gmatch '<[Aa]%s+[Hh][Rr][Ee][Ff]=(["\'])(.-)%1' do
    if target:find 'luasocket%-[0-9.]-$' then
      table.insert(releases, absolute_url(target, url))
    end
  end
  if #releases >= 1 then
    local latest_release = table.remove(version_sort(releases, true))
    local basename = apr.filepath_name(latest_release)
    return context_from_url(latest_release .. '/' .. basename .. '.tar.gz')
  else
    error "Failed to find LuaSocket release online!"
  end
end

local function build_luasocket(luasocket_release, lua_release)
  -- Start the build using a custom batch script (the msbuild stuff included
  -- with LuaSocket doesn't work on my machine and I want the build bot to work
  -- on unmodified releases).
  local command = [[
    CL.EXE /nologo /MD /D"WIN32" /D"LUASOCKET_EXPORTS" ^
      /D"LUASOCKET_API=__declspec(dllexport)" /D"LUASOCKET_DEBUG" ^
      /I"%s/src" src/auxiliar.c src/buffer.c src/except.c src/inet.c src/io.c src/luasocket.c ^
      src/options.c src/select.c src/tcp.c src/timeout.c src/udp.c src/wsocket.c ^
      /link /dll /out:socket.dll "/libpath:%s/src" lua51.lib ws2_32.lib
    IF EXIST socket.dll.manifest MT -nologo -manifest socket.dll.manifest -outputresource:socket.dll;2
    CL.EXE /nologo /MD /D"WIN32" /I"%s/src" src/mime.c /link /dll /out:mime.dll "/libpath:%s/src" lua51.lib
    IF EXIST mime.dll.manifest MT -nologo -manifest mime.dll.manifest -outputresource:mime.dll;2
  ]]
  local wait_for_build = run_build(luasocket_release.release, luasocket_release.build,
      command:format(lua_release.binaries, lua_release.binaries, lua_release.binaries, lua_release.binaries))
  return function()
    -- Wait for the build to finish and copy the resulting files.
    wait_for_build()
    copy_files(luasocket_release.build, luasocket_release.binaries, [[
      README
      LICENSE
      doc
      etc
      samples
      test
      src/socket.lua
      src/mime.lua
      src/ltn12.lua
      src/ftp.lua -> src/socket/ftp.lua
      src/http.lua -> src/socket/http.lua
      src/smtp.lua -> src/socket/smtp.lua
      src/tp.lua -> src/socket/tp.lua
      src/url.lua -> src/socket/url.lua
      socket.dll -> src/socket/core.dll
      mime.dll -> src/mime/core.dll
    ]])
  end
end

-- LuaFileSystem. {{{2

local function find_tags_on_github(project)
  local json = require 'json'
  local url = 'http://github.com/api/v2/json/repos/show/' .. project .. '/tags'
  local data = assert(download(url))
  local response = assert(json.decode(data))
  return assert(response.tags, "Unexpected GitHub API response!")
end

local function find_releases_on_github(project, sortkey)
  local list, map = {}, {}
  for tag, hash in pairs(find_tags_on_github(project)) do
    local key = sortkey(tag)
    if key then
      table.insert(list, key)
      map[key] = tag
    end
  end
  version_sort(list, false)
  for i, key in ipairs(list) do
    list[i] = 'https://github.com/' .. project .. '/zipball/' .. map[key]
  end
  return list
end

local function find_luafilesystem_release()
  local releases = find_releases_on_github('keplerproject/luafilesystem', function(tag)
    -- For some reason all but the most recent tags of LuaFileSystem have
    -- underscores instead of dots to delimit the digits in the version number
    -- and of course this completely breaks the version sort :-(
    return (tag:find '^v' and tag:gsub('_', '.'))
  end)
  assert(#releases >= 1, "Failed to find any releases of LuaFileSystem!")
  local url = table.remove(releases)
  local version = apr.filepath_name(url):gsub('^v', '')
  return context_from_url(url, 'luafilesystem-' .. version .. '.zip')
end

local function build_luafilesystem(lfs_release, lua_release)
  local command = 'CL.EXE /nologo /I"%s/src" src/lfs.c /link /dll /out:lfs.dll /export:luaopen_lfs "/libpath:%s/src" lua51.lib'
  local wait_for_build = run_build(lfs_release.release, lfs_release.build, command:format(lua_release.binaries, lua_release.binaries))
  return function()
    -- Wait for the build to finish and copy the resulting files.
    wait_for_build()
    copy_files(lfs_release.build, lfs_release.binaries, [[
      README
      doc
      tests
      lfs.dll
    ]])
  end
end

local function clean() -- {{{1
  apr.dir_remove_recursive(builds)
  apr.dir_remove_recursive(binaries)
  apr.dir_make(archives)
  apr.dir_make(builds)
  apr.dir_make(binaries)
end

local function main() -- {{{1

  if apr.platform_get() == 'UNIX' then

    -- Start from a clean slate.
    clean()

    -- Run build bot in dedicated, headless Windows XP virtual machine.
    write_file(buildlog, '', false)
    os.execute('(tail -fn0 ' .. buildlog .. ' 2>/dev/null | cat -s) &')
    message "Booting headless Windows VM to run the build bot, this might take a while .."
    assert(os.execute "VBoxHeadless -startvm 'Lua build bot' >/dev/null" == 0,
        "Failed to start VirtualBox! Is the VM already running?")

    -- Check that the expected files were created.
    local files = {
      { 'Lua 5.1.4', {
        'lua-5.1.4/etc/lua.hpp',
        'lua-5.1.4/lua.exe',
        'lua-5.1.4/lua51.dll',
        'lua-5.1.4/luac.exe',
        'lua-5.1.4/src/lauxlib.h',
        'lua-5.1.4/src/lua.h',
        'lua-5.1.4/src/lua51.lib',
        'lua-5.1.4/src/luaconf.h',
        'lua-5.1.4/src/lualib.h',
      }},
      { 'LuaJIT 1.1.7', {
        'luajit-1.1.7/etc/lua.hpp',
        'luajit-1.1.7/lua51.dll',
        'luajit-1.1.7/luajit.exe',
        'luajit-1.1.7/jit/opt.lua',
        'luajit-1.1.7/src/lauxlib.h',
        'luajit-1.1.7/src/lua.h',
        'luajit-1.1.7/src/lua51.lib',
        'luajit-1.1.7/src/luaconf.h',
        'luajit-1.1.7/src/lualib.h',
      }},
      { 'LuaJIT 2.0.0-beta8', {
        'luajit-2.0.0-beta8/etc/lua.hpp',
        'luajit-2.0.0-beta8/lua51.dll',
        'luajit-2.0.0-beta8/luajit.exe',
        'luajit-2.0.0-beta8/jit/dis_x86.lua',
        'luajit-2.0.0-beta8/src/lauxlib.h',
        'luajit-2.0.0-beta8/src/lua.h',
        'luajit-2.0.0-beta8/src/lua51.lib',
        'luajit-2.0.0-beta8/src/luaconf.h',
        'luajit-2.0.0-beta8/src/lualib.h',
      }},
      { 'LPeg 0.10.2', {
        'lpeg-0.10.2/lpeg.dll',
        'lpeg-0.10.2/re.lua',
        'lpeg-0.10.2/src/lpeg.h',
        'lpeg-0.10.2/src/lpeg.lib',
      }},
      { 'LuaSocket 2.0.2', {
        'luasocket-2.0.2/src/mime.lua',
        'luasocket-2.0.2/src/mime/core.dll',
        'luasocket-2.0.2/src/socket.lua',
        'luasocket-2.0.2/src/socket/core.dll',
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
        if scp_target then
          assert(os.execute(string.format('scp ../%s %s/%s', archive, scp_target, archive)))
        end
      end
    end

    os.exit(success and 0 or 1)

  elseif apr.platform_get() == 'WIN32' then

    windows_sdk_folder = assert(find_sdk_helper 'HKCU' or find_sdk_helper 'HKLM', "Failed to locate Windows SDK")
    sdk_setenv_tool = apr.filepath_merge(windows_sdk_folder, [[Bin\SetEnv.Cmd]], 'true-name', 'native')

    -- We're inside the virtual machine! (this script is started automatically after boot)
    clean()
    local children = {}

    -- Build the most recent release of the Lua reference implementation.
    local lua_release = find_lua_release()
    local wait_for_lua = build_lua(download_archive(lua_release))

    -- Build the most recent releases of LuaJIT 1 and 2.
    local lj1_release, lj2_release = find_luajit_releases()
    table.insert(children, build_luajit1(download_archive(lj1_release)))
    table.insert(children, build_luajit2(download_archive(lj2_release)))

    -- Lua modules need to be linked with lua51.dll using lua51.lib which isn't
    -- available until the Lua build is finished, so we wait for it.
    wait_for_lua()

    -- Build the most recent release of LPeg.
    local lpeg_release = find_lpeg_release()
    table.insert(children, build_lpeg(download_archive(lpeg_release), lua_release))

    -- Build the most recent release of LuaSocket.
    local luasocket_release = find_luasocket_release()
    table.insert(children, build_luasocket(download_archive(luasocket_release), lua_release))

    -- Build the most recent release of LuaFileSystem.
    local lfs_release = find_luafilesystem_release()
    table.insert(children, build_luafilesystem(download_archive(lfs_release), lua_release))

    -- Wait for all builds to finish.
    for i = 1, #children do children[i]() end

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

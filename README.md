# A build bot for popular Lua projects

Lots of [Lua](http://lua.org/) projects (including Lua itself and [LuaJIT](http://luajit.org/)) only release source code archives and expect users to build the project. On UNIX this is not really a problem but on Windows this can pose a significant hurdle for potential users. My Lua build bot is an attempt to solve this problem. While developing this build bot I took the following points into consideration:

 * I've had bad experiences with cross compilation so I prefer to build Windows binaries on Windows
 * I don't actually have any Windows machines and don't feel like setting one up just for this build bot
 * I want to be able to run the build bot from a cron job so it can automatically build all projects once a week

## Status

### Project discontinued

I'm sorry to say that this project has been discontinued. My reasons for this are as follows (the below points are my opinions, I don't necessarily expect anyone to agree with them):

 * **I stopped using Windows, in fact I abandoned the complete Microsoft software stack**

   * One reason for this is that I consider the Microsoft stack very unfriendly to developers who are (like me) oriented toward command line automation.

   * Another reason is the fact that quite a few of Microsoft's build tools are commercially licensed and have restrictions on redistribution of software built using them.

   * I switched away from Microsoft Windows for personal use years ago and paying for a new license with every Microsoft Windows release just to keep this Lua build bot running feels absurd to me.

   * As a more general point, I don't like where the development of Microsoft and Windows have been heading in the past couple of years.

 * **I more or less stopped using Lua for personal projects :-(**

   * When I originally fell in love with Lua the language I quickly got frustrated by the surrounding ecosystem because I wanted to use Lua as a general purpose language (admittedly not its original purpose).

     * Out of frustration I started working on [Lua/APR] [lua_apr] to provide myself with a more generally useful "standard library" of operating system interfaces.

     * When I started developing Lua/APR I seriously underestimated my knowledge of [low level systems programming] [c], this is why it took me years to get the project to a state where I could be proud of it.

     * In the end I did get quite far with Lua/APR, eventually presenting it at the [Lua Workshop 2011] [workshop] and having it [included in Debian] [debian].

   * Having Lua/APR available for operating system interfacing was nice, but what I really wanted from my favorite programming language was a rich ecosystem of bindings and packages. Even after creating Lua/APR I still regularly fell into the trap of wanting and not finding bindings to shared libraries. Creating such bindings for every project you want to work on quickly gets tiresome.

   * Starting from 2011 I got a full time job working as a software engineer and later system administrator (DevOps) working on Python projects and this slowly but surely pulled me away from the world of Lua. If you look at [my GitHub profile] [github_profile] now (in 2015) you'll see what I mean :-).

For now, given this extensive explanation, I will keep the repository online, maybe it can serve as inspiration to others. Or who knows, maybe I'll find a way to run Windows legally without paying for licenses and I can find a way to revive the build bot (no promises though). I still love Lua the language, so there's one thing :-).

### To-do list

The following stuff has not yet been implemented but is on the to-do list:

 * Make the build bot **test the binaries** using a test suite of some sort; if everything is going to be automated I have to know that the binaries I'm publishing actually work
 * Deploy the build bot and virtual machine to one of my servers and **run the build bot from a daily cron job**?
 * **Use LuaRocks to build Lua modules**: currently the build bot uses custom batch scripts to build Lua modules, but of course a generic solution is preferable!
    * While adding support for the LuaSocket module I was curious enough to try if `luarocks install luasocket` would work in my environment but it doesn't; `msbuild` complains that the project files are incompatible
 * **Support for Mac binaries?** This requires someone to run the build bot periodically on their Mac, because I don't have access to any Mac machines

## Downloads

The following packages have been built by the Lua build bot:

### Implementations of Lua

<table cellpadding=5>
 <tr><th>Release</th><th>Size</th><th>SHA1 hash</th></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/lua-5.1.4.zip">Lua 5.1.4</a></td><td>234K</td><td><code>b312a0f67fae85d0969edcccee3df3bb27b6c228</code></td></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/luajit-1.1.7.zip">LuaJIT 1.1.7</a></td><td>255K</td><td><code>f58c039e0a890601d44f7026f36ed7e9a9de0990</code></td></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/luajit-2.0.0-beta8.zip">LuaJIT 2.0.0 beta 8</a></td><td>269K</td><td><code>7b3f8a8c4788e67c737137e69c9bbe39ba183410</code></td></tr>
</table>

### Lua modules

<table cellpadding=5>
 <tr><th>Release</th><th>Size</th><th>SHA1 hash</th></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/lpeg-0.10.2.zip">LPeg 0.10.2</a></td><td>89K</td><td><code>159a31446cc4c0f3a28e892c2c61d4bac52f25ee</code></td></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/luasocket-2.0.2.zip">LuaSocket 2.0.2</a></td><td>126K</td><td><code>a6a8fe0763cd21160c4cde2f6da8df5095851c36</code></td></tr>
 <tr><td><a href="http://peterodding.com/code/lua/buildbot/downloads/luafilesystem-1.5.0.zip">LuaFileSystem 1.5.0</a></td><td>70K</td><td><code>9c482f761d4e7624215b62e0b807a59ff44a3309</code></td></tr>
</table>

## How it works

Right now the build bot is meant to be run on my machine because it works in a very specific way, however I'm planning to make it more generally useful (and with a bit of persistence it should already be possible for other folks to get it running). At the moment I run the build bot as follows:

 * I start the build bot script from a terminal on my [Ubuntu Linux](http://www.ubuntu.com/) installation
 * The build bot starts a headless virtual machine running Windows using [VirtualBox](http://www.virtualbox.org/)
    * The virtual machine has been specifically setup for the build bot (see below)
    * When the virtual machine boots it automatically launches the build bot
 * When the build bot is executed on Windows it performs the following steps for each project:
    * Find latest available release from homepage
    * Download archive (if not already downloaded)
    * Unpack and build project
    * Copy files to be released (binaries & headers)
 * When the build bot was executed automatically on Windows, it will shut the virtual machine down

As I mentioned above the plan is to run the build bot from a cron job on a server, this is still a work in progress.

## Dependencies in the VM

In order to run the build bot on Windows I installed the following software in the virtual machine:

 * Windows XP SP3
 * The latest [Windows Platform SDK](http://www.microsoft.com/download/en/details.aspx?id=8279) (7.1)
 * [Lua For Windows](http://code.google.com/p/luaforwindows/) (v5.1.4-45)
 * My [Lua/APR binding](http://peterodding.com/code/lua/apr) (0.20)
 * `gunzip`, `tar`, `wget` and `unzip` from [UnxUtils](http://unxutils.sourceforge.net/)

I'm not publishing the virtual machine image because it was registered with my serial number and of course it's quite big (more than 2 GB). However it's not hard to create the virtual machine, it just takes a bit of time. Apart from installing the software mentioned above, there are only two things to configure in the virtual machine:

 * Inside the virtual machine I've mounted a shared folder as a network drive, this enables the two build bots to easily exchange files
 * After creating the network drive I added `buildbot.cmd` to my Start → Programs → Startup menu so that the build bot runs automatically after the VM is started and shuts down the VM after building all projects

## Contact

If you have questions, bug reports, suggestions, etc. the author can be contacted at <peter@peterodding.com>. The latest version is available at <http://peterodding.com/code/lua/buildbot> and <http://github.com/xolox/lua-buildbot>.

## License

This software is licensed under the [MIT license](http://en.wikipedia.org/wiki/MIT_License).  
© 2011 Peter Odding &lt;<peter@peterodding.com>&gt;.

### Disclaimers

 * This license only applies to the build bot itself -- I don't have any affiliation with the projects supported by the build bot, I'm just a happy user
 * Should the original authors have objections against this build bot, let me know and I will remove support for the project in question
 * I don't give any guarantees as to the published binaries. They're generated in a dedicated machine so it's very unlikely that a virus could sneak in, but you never know until you've [scanned the binaries yourself](http://www.virustotal.com/)...

[c]: http://en.wikipedia.org/wiki/C_(programming_language)
[debian]: https://packages.debian.org/lua-apr
[github_profile]: https://github.com/xolox/
[lua_apr]: https://github.com/xolox/lua-apr
[workshop]: http://www.lua.org/wshop11/Lua-APR.pdf

# A build bot for popular Lua projects

Lots of [Lua](http://lua.org/) projects (including Lua itself and [LuaJIT](http://luajit.org/)) only release source code archives and expect users to build the project. On UNIX this is not really a problem but on Windows this can pose a significant hurdle for potential users. My Lua build bot is an attempt to solve this problem. While developing this build bot I took the following points into consideration:

 * I've had bad experiences with cross compilation so I prefer to build Windows binaries on Windows
 * I don't actually have any Windows machines and don't feel like setting one up just for this build bot
 * I want to be able to run the build bot from a cron job so it can automatically build all projects once a week

## Downloads

The following packages have been built by the Lua build bot:

 * [Lua 5.1.4](http://peterodding.com/code/lua/buildbot/downloads/lua-5.1.4.zip) (234K)
 * [LuaJIT 1.1.7](http://peterodding.com/code/lua/buildbot/downloads/LuaJIT-1.1.7.zip) (255K)
 * [LuaJIT 2.0.0-beta8](http://peterodding.com/code/lua/buildbot/downloads/LuaJIT-2.0.0-beta8.zip) (269K)
 * [LPeg 0.10.2](http://peterodding.com/code/lua/buildbot/downloads/lpeg-0.10.2.zip) (89K)
 * [LuaSocket 2.0.2](http://peterodding.com/code/lua/buildbot/downloads/luasocket-2.0.2.zip) (126K)

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

## Status

The following stuff has not yet been implemented but is on the to-do list:

 * Make the build bot **test the binaries** using a test suite of some sort; if everything is going to be automated I have to know that the binaries I'm publishing actually work
 * Deploy the build bot and virtual machine to one of my servers and **run the build bot from a daily cron job**?
 * Support for popular / easy to build Lua modules such as **[LuaSocket](http://w3.impa.br/~diego/software/luasocket/)**
 * **Support for Mac binaries?** This requires someone to run the build bot periodically on their Mac, because I don't have access to any Mac machines

## Dependencies in the VM

In order to run the build bot on Windows I installed the following software in the virtual machine:

 * Windows XP SP3
 * The latest [Windows Platform SDK](http://www.microsoft.com/download/en/details.aspx?id=8279) (7.1)
 * [Lua For Windows](http://code.google.com/p/luaforwindows/) (v5.1.4-45)
 * My [Lua/APR binding](http://peterodding.com/code/lua/apr) (0.20)
 * `unzip.exe`, `gunzip.exe` and `tar.exe` from [UnxUtils](http://unxutils.sourceforge.net/)

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

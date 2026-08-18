<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood"></a>
</p>

<p align="center">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
    <img src="https://img.shields.io/static/v1?label=stable&message=v1&color=orange" alt="Version">
</p>

MACOS-UTILS
===========
Custom macOS App
----------------

Wrap any shell script into a real `.app` bundle — double-clickable, pinnable to
the Dock, launchable from Spotlight.

The typical use case: an app started from Finder inherits the **GUI**
environment, not your login shell. SourceTree calling `php`, a git hook calling
`node`, anything shelling out then picks the system binary instead of your
brew/asdf/nvm one — and breaks. Launching the real app *through* a shell script
fixes its environment once and for all.

Requirements
------------

* **macOS**

Sources
-------

| File | Role |
| --- | --- |
| [appify.sh](/data/sources/appify.sh) | the wrapper — turns a `.sh` into a `.app` |
| [custom_macos_app.sh](/data/sources/custom_macos_app.sh) | payload template to copy and adapt |
| [custom_sourcetree.app.zip](/data/sources/custom_sourcetree.app.zip) | a finished example, icon included |

`appify.sh` is vendored from [Thomas Aylott's original gist](https://gist.github.com/subtleGradient/674099)
so nothing else needs cloning.

Usage
-----

Copy the template and rename it to your needs:

```shell
cp data/sources/custom_macos_app.sh ~/Desktop/custom_sourcetree.sh
```

Edit its two sections — the environment to load, and what the app should do —
then wrap it:

```shell
sh data/sources/appify.sh ~/Desktop/custom_sourcetree.sh "Custom SourceTree"
mv "Custom SourceTree.app" /Applications/
```

You now have a new application in `/Applications`. Right-click → *Show Package
Contents* to inspect it, add resources, tweak the script in place.

What you get
------------

```
Custom SourceTree.app
└── Contents
    └── MacOS
        └── Custom SourceTree   ← your script, chmod +x
```

That is the whole bundle. macOS is happy with this minimum: a directory ending
in `.app` containing `Contents/MacOS/<same name as the bundle>`, executable.

Anatomy of the payload
----------------------

```bash
#!/usr/bin/env bash

# 1. Load the same environment your terminal gets
[ -f "${HOME}/.bash_profile" ] && . "${HOME}/.bash_profile";
[ -f "${HOME}/.zprofile" ] && . "${HOME}/.zprofile";

# 2. Do the thing — here, launch the real binary with that environment
open /Applications/SourceTree.app/Contents/MacOS/SourceTree;
```

Section 1 is the reason the whole trick exists. Section 2 is anything you want:
launching a binary, running a build, opening a tunnel, starting a docker stack.

Custom icon
-----------

Follow [these instructions](https://9to5mac.com/2020/12/01/change-mac-icons/),
but **drag and drop** the icon onto the Get Info window rather than pasting it.

Going further
-------------

This bundle has no `Info.plist`, so macOS falls back on defaults: generic icon,
bundle name derived from the folder, app visible in the Dock. Add a
`Contents/Info.plist` to control all of it — see
[Awake's Info.plist](/data/sources/awake/Info.plist) for a complete one, and
[its build script](/data/sources/awake/build.sh) for the same bundle-by-hand
approach applied to a compiled Swift app.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)

<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood" width="400"></a>
</p>

<p align="left">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
    <img src="https://img.shields.io/static/v1?label=stable&message=v1&color=0ea5e9" alt="Version">
</p>

MACOS-UTILS
===========
Some Stuff
----------

A small collection of macOS utilities and the documentation to build and install
them yourself. Every one of them ships as source you assemble locally — no
installer, no notarized DMG to trust.

Requirements
------------

* **macOS** (13+ for Awake)
* **Command Line Tools** for the compiled utilities — `xcode-select --install`

Installation
------------

```shell
git clone https://github.com/jul6art/macos-utils.git
cd macos-utils
```

Then follow the doc of the utility you want.

Utilities
---------

| Utility | What it does | Doc |
| --- | --- | --- |
| **Custom macOS App** | Wraps any shell script into a real `.app` — the fix for GUI apps that miss your shell environment (i.e. SourceTree failing on the wrong PHP version) | [APPIFY.md](/data/doc/APPIFY.md) |
| **Awake** | Native menu bar app that keeps the Mac and its screen awake, with durations and launch-at-login | [AWAKE.md](/data/doc/AWAKE.md) |

### Custom macOS App

```shell
cp data/sources/custom_macos_app.sh ~/Desktop/my_app.sh
# edit it, then:
sh data/sources/appify.sh ~/Desktop/my_app.sh "My App"
mv "My App.app" /Applications/
```

→ [full documentation](data/doc/APPIFY.md)

### Awake

```shell
sh data/sources/awake/build.sh --install
```

→ [full documentation](data/doc/AWAKE.md)

Layout
------

```
data/
├── doc/
│   ├── APPIFY.md                   # custom macOS app, step by step
│   └── AWAKE.md                    # Awake, build & install
└── sources/
    ├── appify.sh                   # shell script → .app wrapper
    ├── custom_macos_app.sh         # payload template to adapt
    ├── custom_sourcetree.app.zip   # finished example
    └── awake/                      # Swift sources + Info.plist + build.sh
```

Contributing
------------

New utility? Keep the same shape — sources under `data/sources/<name>/`, a doc
under `data/doc/<NAME>.md` following the existing layout (requirements, sources
table, installation, usage), and a row in the table above.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)

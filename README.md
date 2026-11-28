<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood" width="400"></a>
</p>

MACOS-UTILS
===========

<p align="left">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
</p>

A small collection of macOS utilities and the documentation to build and install
them yourself. Every one of them ships as source you can read end to end and
assemble locally — and the three apps also come ready-made, for convenience.

Requirements
------------

* **macOS** (13+ for Awake and Siphon, 15+ for Visage)
* **Command Line Tools** for the compiled utilities — `xcode-select --install`
* **yt-dlp** and **ffmpeg** for Siphon — `brew install yt-dlp ffmpeg`
* **Claude Desktop**, the **ChatGPT** app, **Siri** or **Claude Code** for Visage — it gives a face to their voice

Installation
------------

```shell
git clone https://github.com/jul6art/macos-utils.git
cd macos-utils
```

Then follow the doc of the utility you want.

Source or ready-made
--------------------

The source is the reference: each doc explains how to build its utility with the
Command Line Tools alone. The three apps also have a **ready-made build** on the
[Releases](https://github.com/jul6art/macos-utils/releases) page, one universal
archive each, for Apple silicon and Intel:

| App | Ready-made | From source |
| --- | --- | --- |
| **Awake** | [Awake 1.0.0](https://github.com/jul6art/macos-utils/releases/tag/awake-v1.0.0) | `sh data/sources/awake/build.sh --install` |
| **Siphon** | [Siphon 1.0.0](https://github.com/jul6art/macos-utils/releases/tag/siphon-v1.0.0) | `sh data/sources/siphon/build.sh --install` |
| **Visage** | [Visage 0.2.0](https://github.com/jul6art/macos-utils/releases/tag/visage-v0.2.0) | `sh data/sources/visage/build.sh --install` |

The ready-made builds are made from the same source, signed ad hoc and **not
notarized**: macOS blocks each one the first time you open it. Allow it once in
System Settings → Privacy & Security → **Open Anyway**.

Each archive is **reproducible**. Check out its tag and run
`sh data/sources/release.sh <app>`: with the same Command Line Tools, you get the
same archive, byte for byte, and the checksum published next to it.

Utilities
---------

| Utility | What it does | Doc |
| --- | --- | --- |
| **Custom macOS App** | Wraps any shell script into a real `.app` — the fix for GUI apps that miss your shell environment (e.g. SourceTree failing on the wrong PHP version) | [APPIFY.md](/data/doc/APPIFY.md) |
| **Awake** | Native menu bar app that keeps the Mac and its screen awake, with durations and launch-at-login | [AWAKE.md](/data/doc/AWAKE.md) |
| **Siphon** | Native window on top of yt-dlp: paste a link, get an MP3, M4A or MP4 — whole or just a passage — with its cover art and tags | [SIPHON.md](/data/doc/SIPHON.md) |
| **Visage** | A hologram face for the voice of Claude, ChatGPT or Siri, and a voice and a face for Claude Code: lips in sync, alive between sentences, and nothing leaves the Mac | [VISAGE.md](/data/doc/VISAGE.md) |

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

### Siphon

```shell
brew install yt-dlp ffmpeg
sh data/sources/siphon/build.sh --install
```

→ [full documentation](data/doc/SIPHON.md)

### Visage

```shell
sh data/sources/visage/build.sh --install
```

Then open Visage, pick Claude, allow system audio, and start Claude's voice mode.
To talk to Claude Code instead, install Visage's plugin in it:

```shell
/plugin install visage --marketplace jul6art/macos-utils
```

→ [full documentation](data/doc/VISAGE.md)

Layout
------

```
data/
├── doc/
│   ├── APPIFY.md                   # custom macOS app, step by step
│   ├── AWAKE.md                    # Awake, build & install
│   ├── SIPHON.md                   # Siphon, build & install
│   ├── VISAGE.md                   # Visage, build, first launch & settings
│   └── images/visage/              # its screenshots, made by tools/doc-images.sh
└── sources/
    ├── appify.sh                   # shell script → .app wrapper
    ├── release.sh                  # an app's release archive, reproducible
    ├── custom_macos_app.sh         # payload template to adapt
    ├── awake/                      # Swift sources + Info.plist + build.sh + icon/
    ├── siphon/                     # Swift sources + Info.plist + build.sh + icon/
    └── visage/                     # Swift modules + tests + faces + brand kit + build.sh + check.sh
```

Contributing
------------

New utility? Keep the same shape — sources under `data/sources/<name>/`, a doc
under `data/doc/<NAME>.md` following the existing layout (requirements, sources
table, installation, usage), and a row in the table above.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
Visage's faces are made of CC0 assets and two CC-BY hairstyles by Elvaerwyn,
credited in [VISAGE.md](data/doc/VISAGE.md#the-faces).

&copy; 2026 [jul6art](https://devinthehood.com)

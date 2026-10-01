<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood"></a>
</p>

<p align="center">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
    <img src="https://img.shields.io/static/v1?label=stable&message=v1&color=orange" alt="Version">
</p>

MACOS-UTILS
===========
Siphon
------

A small native window on top of [yt-dlp](https://github.com/yt-dlp/yt-dlp): paste
a link, pick MP3, M4A or MP4, and the file lands in your folder — with its cover
art and tags.

yt-dlp does the work and stays the one Homebrew keeps up to date. Siphon only
builds the command line, runs it, and shows what it says. No bundled copy of
yt-dlp, no updater, no account, no network access of its own.

Requirements
------------

* **macOS 13+** (Ventura — the SwiftUI APIs used are 13.0 ones)
* **Command Line Tools** (`xcode-select --install`) — Xcode is optional
* **yt-dlp** and **ffmpeg**, from Homebrew:

```shell
brew install yt-dlp ffmpeg
```

Homebrew's yt-dlp pulls **deno** along with it: yt-dlp needs a JavaScript
runtime to read YouTube pages, and only looks for deno.

Sources
-------

| File | Role |
| --- | --- |
| [SiphonApp.swift](/data/sources/siphon/SiphonApp.swift) | Single-window scene, quit confirmation while downloads run |
| [ContentView.swift](/data/sources/siphon/ContentView.swift) | The window: input, settings, queue, tool status |
| [DownloadQueue.swift](/data/sources/siphon/DownloadQueue.swift) | Queue, two downloads at a time, saved settings |
| [DownloadJob.swift](/data/sources/siphon/DownloadJob.swift) | One link, one `yt-dlp` process: output, progress, cancel |
| [YtDlp.swift](/data/sources/siphon/YtDlp.swift) | Locating the tools, the exact arguments, parsing the output |
| [Info.plist](/data/sources/siphon/Info.plist) | Bundle metadata, folder access messages |
| [icon/AppIcon.swift](/data/sources/siphon/icon/AppIcon.swift) | Draws the app icon — see *The icon* |
| [build.sh](/data/sources/siphon/build.sh) | Builds `Siphon.app` without Xcode |

Everything Siphon passes to yt-dlp is in `YtDlp.arguments` — read that function
and you know what runs.

Installation
------------

### Option A — build script (no Xcode needed)

```shell
cd data/sources/siphon
sh build.sh --install
```

The app lands in `/Applications/Siphon.app`. The script ends with a note if
yt-dlp, ffmpeg or deno cannot be found.

Flags:

| Flag | Effect |
| --- | --- |
| *(none)* | builds `build/Siphon.app` for the current architecture |
| `--universal` | builds a fat binary (arm64 + x86_64) |
| `--install` | moves the result to `/Applications` |

Same as [Awake](/data/doc/AWAKE.md): `swiftc`, a bundle assembled by hand, an
ad-hoc signature. If Siphon is running, `--install` asks it to quit first — and
stops if it refuses because a download is still going, rather than killing it.

### Option B — Xcode project

1. Xcode → New Project → macOS → **App**
2. Product Name: `Siphon`
3. Interface: **SwiftUI**, Language: **Swift**
4. Deployment Target: **macOS 13.0**
5. Replace the generated `SiphonApp.swift` and `ContentView.swift` with
   [the ones from this repo](/data/sources/siphon/)
6. Add `DownloadQueue.swift`, `DownloadJob.swift` and `YtDlp.swift` to the target
7. Target → Signing & Capabilities → remove **App Sandbox**
8. Build & Run

Step 7 matters: a sandboxed app may not launch `/opt/homebrew/bin/yt-dlp`.

Usage
-----

**Adding links** — three ways, any number of links at once:

* paste into the field and press **Télécharger** (or Return)
* **Coller** takes the clipboard as it is
* drag a link from the browser onto the window

Any text works: Siphon picks out every `http(s)://` address in it and skips the
ones already waiting or downloading.

**Format** — applies to the links added *after* you change it:

| Choice | Result | yt-dlp options |
| --- | --- | --- |
| **MP3** | MP3 320 kbps | `--extract-audio --audio-format mp3 --audio-quality 320K` |
| **M4A** | the original AAC stream, not re-encoded | `--format "ba[ext=m4a]/ba" --extract-audio --audio-format m4a` |
| **Vidéo MP4** | video and sound in one MP4 | `--format-sort <quality> --merge-output-format mp4` |

All three get `--embed-thumbnail --embed-metadata`: cover art, title and artist
are inside the file.

**Qualité** (MP4 only):

| Choice | Format sort | Plays in QuickTime |
| --- | --- | --- |
| 720p | `vcodec:h264,res:720,acodec:aac` | yes |
| 1080p *(default)* | `vcodec:h264,res:1080,acodec:aac` | yes |
| Maximale (4K…) | `res,vcodec:av01,acodec:aac` | AV1: on recent Macs only |

Up to 1080p H.264 is preferred, because it plays and imports everywhere. Past
1080p YouTube only serves VP9 and AV1, so *Maximale* takes the highest resolution
and prefers AV1 — VP9 in an MP4 does not play in QuickTime at all.

**Playlist entière** — for a link to a video that belongs to a playlist (the
`&list=` kind). Off, only that video is downloaded. On, the whole playlist goes
into a subfolder named after it, files numbered in playlist order:

```
~/Downloads/
├── Me at the zoo.mp3                 # a lone video, playlist off or on
└── Uploads from jawed/               # a playlist, playlist on
    └── 1 - Me at the zoo.mp3
```

**The queue** — two downloads run at a time, the rest wait. Each row shows the
title, the progress, the speed and the time left, then:

| State | Buttons |
| --- | --- |
| waiting, downloading, converting | ⏹ stop |
| done | 🔍 show in Finder · ✕ remove from the list |
| failed, stopped | ↻ retry with the same settings · ✕ remove from the list |

Removing a row never deletes the file. The Dock icon shows how many links are
not finished yet.

**The footer** shows which of yt-dlp, ffmpeg and deno were found, with yt-dlp's
version. If yt-dlp or ffmpeg is missing, a banner says what to install, and
**Vérifier à nouveau** picks it up without relaunching — links added meanwhile
just wait.

**Quitting** while something downloads asks first, then stops the downloads:
yt-dlp runs as a separate process and would otherwise go on alone.

How it works
------------

For each link, Siphon runs one `yt-dlp` process. For an MP3 with the playlist
off, the command is — progress template shortened:

```shell
yt-dlp --ignore-config --newline --no-colors --no-mtime \
  --paths ~/Downloads --output "%(title)s.%(ext)s" --no-playlist \
  --progress-template "download:[siphon] %(progress._percent_str)s|…|%(info.title)s" \
  --print "after_move:[siphon-file] %(filepath)s" --no-quiet \
  --ffmpeg-location /opt/homebrew/bin \
  --extract-audio --audio-format mp3 --audio-quality 320K \
  --embed-thumbnail --embed-metadata \
  -- "https://…"
```

* **`--ignore-config`** — a personal `~/.config/yt-dlp/config` would change the
  output Siphon reads. What you set in the window is all that applies.
* **`--progress-template`** and **`--print after_move:`** — yt-dlp writes lines
  tagged `[siphon]` for the progress and `[siphon-file]` for the final path.
  Siphon reads those, the `ERROR:` lines, and the post-processor tags
  (`[ExtractAudio]`, `[Merger]`…) that mean ffmpeg's turn has come. The rest of
  the output is ignored.
* **`--no-quiet`** — `--print` implies `--quiet`, which would also hide the
  progress lines.
* **`--`** — whatever was pasted is never read as an option.

### The PATH problem, again

An app launched from the Finder gets launchd's `PATH` —
`/usr/bin:/bin:/usr/sbin:/sbin` — not your shell's, the very problem
[appify](/data/doc/APPIFY.md) exists for. So Siphon looks for the tools by hand
in `/opt/homebrew/bin`, `/usr/local/bin` and `~/.local/bin`, then hands yt-dlp a
`PATH` with those directories in front. ffmpeg is passed explicitly; deno can
only be found through `PATH`. Without it, YouTube extraction warns
`No supported JavaScript runtime could be found` and formats go missing.

### Stopping a download

⏹ sends **SIGINT**, what Ctrl-C does in a terminal: yt-dlp winds down on its own
and keeps its `.part` file, so adding the same link again resumes where it
stopped. A process still running three seconds later gets a SIGTERM.

What it touches on the machine
------------------------------

| What | Where |
| --- | --- |
| Downloaded files | the folder chosen in the window — `~/Downloads` by default — and nowhere else |
| Unfinished downloads | `*.part` files in that same folder |
| Settings | preference domain `com.devinthehood.siphon`: `siphon.format`, `siphon.videoQuality`, `siphon.wholePlaylist`, `siphon.destination` |
| Folder access | the macOS prompt *"Siphon souhaite accéder au dossier…"* the first time you save to Downloads, Desktop or Documents |

No login item, no `LaunchAgents` entry, nothing running once the window is
closed — closing it quits the app.

**Network.** Siphon itself contacts nothing. yt-dlp contacts the site of the
link you gave and the servers that site sends the media from; on YouTube it
runs the page's JavaScript challenge locally in deno. Siphon never passes
`--remote-components`, so yt-dlp does not fetch solver code from GitHub either.

Download only what you have the right to: Siphon does not change the terms of
the sites you use, nor the rights of the people who made what is on them.

Removing it
-----------

```shell
rm -rf /Applications/Siphon.app
defaults delete com.devinthehood.siphon
tccutil reset All com.devinthehood.siphon    # forget the folder access, if granted
```

Your downloaded files stay where they are. Leftover `*.part` files are only
there if a download was stopped — delete them by hand.

The icon
--------

Siphon's icon — a sound wave whose middle bar becomes a download arrow — is
drawn by [icon/AppIcon.swift](/data/sources/siphon/icon/AppIcon.swift), exactly
like [Awake's](/data/doc/AWAKE.md#the-icon): `build.sh` renders it at build time,
so the repository holds code, not an image. To use your own, drop an
`AppIcon.icns` next to the sources and rebuild; it wins over the drawn one.

Gatekeeper
----------

The build is ad-hoc signed, not notarized. On the machine that built it, it just
runs. If you copy the `.app` to another Mac, macOS will quarantine it — clear the
flag there:

```shell
xattr -dr com.apple.quarantine /Applications/Siphon.app
```

Troubleshooting
---------------

| Symptom | Fix |
| --- | --- |
| Banner *"yt-dlp introuvable"* or *"ffmpeg introuvable"* | `brew install yt-dlp ffmpeg`, then **Vérifier à nouveau** |
| Footer shows deno ✗, YouTube formats missing | `brew install deno` (Homebrew's yt-dlp normally brings it) |
| YouTube fails with `HTTP Error 403`, `Sign in to confirm you're not a bot`, or *"Requested format is not available"* | YouTube changed something: `brew upgrade yt-dlp` — fixes usually ship within days |
| `CERTIFICATE_VERIFY_FAILED` | a firewall on your network intercepts HTTPS (common on company networks). yt-dlp uses its own certificate bundle, not the macOS keychain, so it refuses the substitute certificate. Try another network, or ask whoever runs that firewall |
| A *Maximale* MP4 does not play in QuickTime | it is AV1 and this Mac cannot decode it: use 1080p, or play it in IINA or VLC |
| A playlist link only downloaded one video | **Playlist entière** was off |
| Dropping a file from the Finder does nothing | by design — only web links are accepted |
| `swiftc: command not found` | `xcode-select --install` |
| `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` | a source uses `@State`: since the macOS 27 SDK it is a macro whose plugin ships with Xcode only. Siphon keeps view state in an `ObservableObject` for that reason — keep it that way, or build with Xcode |

To see exactly what yt-dlp says for a link, run the command from *How it works*
in a terminal: it is the same one, without the window.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)

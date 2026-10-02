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
a link, pick MP3, M4A or MP4 — the whole thing or just a passage — and the file
lands in your folder, with its cover art and tags.

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
| [SiphonApp.swift](/data/sources/siphon/SiphonApp.swift) | Single-window scene, Settings window, quit confirmation while downloads run |
| [ContentView.swift](/data/sources/siphon/ContentView.swift) | The window: input, settings, queue, tool status — and the Settings window |
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

* paste into the field and press **Download** (or Return)
* **Paste** takes the clipboard as it is
* drag a link from the browser onto the window

Any text works: Siphon picks out every `http(s)://` address in it and skips the
ones already waiting or downloading with the same *From / to* times.

**Format** — applies to the links added *after* you change it:

| Choice | Result | yt-dlp options |
| --- | --- | --- |
| **MP3** | MP3 320 kbps | `--extract-audio --audio-format mp3 --audio-quality 320K` |
| **M4A** | the original AAC stream, not re-encoded | `--format "ba[ext=m4a]/ba" --extract-audio --audio-format m4a` |
| **MP4 video** | video and sound in one MP4 | `--format-sort <quality> --merge-output-format mp4` |

All three get `--embed-thumbnail --embed-metadata`: cover art, title and artist
are inside the file.

**Quality** (MP4 only):

| Choice | Format sort | Plays in QuickTime |
| --- | --- | --- |
| 720p | `vcodec:h264,res:720,acodec:aac` | yes |
| 1080p *(default)* | `vcodec:h264,res:1080,acodec:aac` | yes |
| Best (4K…) | `res,vcodec:av01,acodec:aac` | AV1: on recent Macs only |

Up to 1080p H.264 is preferred, because it plays and imports everywhere. Past
1080p YouTube only serves VP9 and AV1, so *Best* takes the highest resolution
and prefers AV1 — VP9 in an MP4 does not play in QuickTime at all.

**Whole playlist** — for a link to a video that belongs to a playlist (the
`&list=` kind). Off, only that video is downloaded. On, the whole playlist goes
into a subfolder named after it, files numbered in playlist order:

```
~/Downloads/
├── Me at the zoo.mp3                 # a lone video, playlist off or on
└── Uploads from jawed/               # a playlist, playlist on
    └── 1 - Me at the zoo.mp3
```

**From / to** — keeps only a passage, in any of the three formats. Type a start,
an end, or both, as `9:45`, `1:02:03` or a number of seconds (`585`); an empty
field means from the very start, or to the very end. Both empty: the whole file.

| Typed | Kept | File name |
| --- | --- | --- |
| `9:45` → `12:03` | 9:45 to 12:03 | `Title (9m45s-12m03s).mp4` |
| `9:45` → *(empty)* | 9:45 to the end | `Title (9m45s-end).mp4` |
| *(empty)* → `12:03` | the start to 12:03 | `Title (0m00s-12m03s).mp4` |

The times go with the links added next, then the fields empty themselves: they
belong to one video, and the link after it starts whole. Paste several links at
once to cut them all the same way — with **Whole playlist** on, every video of
the playlist is cut. The times are in the name, so a passage never overwrites the
whole file nor another passage of the same video, and the queue shows them next to
the format (`1080p · 9:45–12:03`).

Only that passage is downloaded, and it is cut where you said, to the frame:
ffmpeg re-encodes it rather than copying, so a clip takes longer than its length
suggests — much longer on *Best (4K…)*, which also comes out as H.264 — and an
M4A clip is no longer the untouched AAC stream.

**The queue** — two downloads run at a time, the rest wait. Each row shows the
title, the progress, the speed and the time left, then:

| State | Buttons |
| --- | --- |
| waiting, downloading, converting | ⏹ stop |
| done | 🔍 show in Finder · ✕ remove from the list |
| failed, stopped | ↻ retry with the same settings · ✕ remove from the list |

Removing a row never deletes the file. The Dock icon shows how many links are
not finished yet.

**Refused downloads** — now and then the site refuses the stream (HTTP 403):
YouTube does it more often to clips, which ffmpeg reads straight from its servers.
Siphon does not show it: it tries again 2 seconds later, then 5 seconds after
that, each time reading the link afresh, while the row stays in progress and
keeps its place in the queue. Only the last refusal — the third, by default —
shows *Refused by YouTube (HTTP 403), 3 times in a row*, or the site's name for
another site. Any other error shows at once: trying again would not change it.

**Settings** (*Siphon → Settings…*, ⌘,) — how many attempts in all, from 1 to 10:

| Attempts | Waits between them | Longest before the error shows |
| --- | --- | --- |
| 1 | — | the refusal shows at once |
| 3 *(default)* | 2 s, 5 s | 7 s |
| 5 | 2 s, 5 s, 10 s, 20 s | 37 s |
| 10 | 2 s, 5 s, 10 s, 20 s, then 30 s each | 3 min 7 s |

The waits do not count the attempts themselves: each one starts the download over,
and for a clip that means the whole re-encoding again. Three is the default
because a passing refusal rarely comes twice in a row, while three in a row is
usually a real block — an outdated yt-dlp, or an address YouTube has flagged —
that more attempts would only report later. Raise it on an unreliable
connection. A change applies to the downloads that have not started yet.

**The footer** shows which of yt-dlp, ffmpeg and deno were found, with yt-dlp's
version. If yt-dlp or ffmpeg is missing, a banner says what to install, and
**Check again** picks it up without relaunching — links added meanwhile
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

With **From / to** filled in, the name gets the times (`"%(title)s (9m45s-12m03s).%(ext)s"`)
and two options come before `--embed-thumbnail`:

```shell
  --download-sections "*585-723" --force-keyframes-at-cuts
```

`--download-sections` hands the download to ffmpeg, which reads only that range
of the stream; an open end is `inf`. Copying it as is would start on the keyframe
— or, for audio, the block — before the start, seconds too early:
`--force-keyframes-at-cuts` re-encodes it instead. ffmpeg then prints its own
progress (`size=… time=00:01:12.40 …`) rather than yt-dlp's, and Siphon measures
that `time=` against the length of the passage for the progress bar.

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
stopped. A process still running three seconds later gets a SIGTERM. Between two
attempts after a refusal nothing runs, so ⏹ just drops the next attempt.

### Telling a refusal from the rest

The 403 does not always look the same: yt-dlp's own downloader writes
`ERROR: unable to download video data: HTTP Error 403: Forbidden`, while for a
clip yt-dlp only reports `ERROR: ffmpeg exited with code 8`. That 8 is ffmpeg's
`AVERROR_HTTP_FORBIDDEN` cut down to the 8 bits of an exit status. Siphon retries
on either, and on nothing else.

What it touches on the machine
------------------------------

| What | Where |
| --- | --- |
| Downloaded files | the folder chosen in the window — `~/Downloads` by default — and nowhere else |
| Unfinished downloads | `*.part` files in that same folder |
| Settings | preference domain `com.devinthehood.siphon`: `siphon.format`, `siphon.videoQuality`, `siphon.wholePlaylist`, `siphon.destination`, `siphon.attempts` |
| Folder access | the macOS prompt asking whether *Siphon* may access the folder, the first time you save to Downloads, Desktop or Documents |

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
| Banner *"yt-dlp not found"* or *"ffmpeg not found"* | `brew install yt-dlp ffmpeg`, then **Check again** |
| Footer shows deno ✗, YouTube formats missing | `brew install deno` (Homebrew's yt-dlp normally brings it) |
| *"Refused by YouTube (HTTP 403), 3 times in a row"* | Siphon already tried as many times as *Settings* says: try again in a few minutes. If it lasts, YouTube changed something — `brew upgrade yt-dlp` |
| YouTube fails with `Sign in to confirm you're not a bot` or *"Requested format is not available"* | YouTube changed something: `brew upgrade yt-dlp` — fixes usually ship within days |
| `CERTIFICATE_VERIFY_FAILED` | a firewall on your network intercepts HTTPS (common on company networks). yt-dlp uses its own certificate bundle, not the macOS keychain, so it refuses the substitute certificate. Try another network, or ask whoever runs that firewall |
| A *Best* MP4 does not play in QuickTime | it is AV1 and this Mac cannot decode it: use 1080p, or play it in IINA or VLC |
| A playlist link only downloaded one video | **Whole playlist** was off |
| *"… is not a time"* or *"The end must come after the start"* | **From / to** takes `9:45`, `1:02:03` or seconds (`585`) — whole seconds, no `9:45.5` nor `9m45` |
| A clip is slow to download | it is re-encoded to be cut to the frame: expected, more so in 4K |
| A link with no times got cut | the times apply to the links added right after them — check the badge in the queue |
| Dropping a file from the Finder does nothing | by design — only web links are accepted |
| `swiftc: command not found` | `xcode-select --install` |
| `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` | a source uses `@State`: since the macOS 27 SDK it is a macro whose plugin ships with Xcode only. Siphon keeps view state in an `ObservableObject` for that reason — keep it that way, or build with Xcode |

To see exactly what yt-dlp says for a link, run the command from *How it works*
in a terminal: it is the same one, without the window.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)

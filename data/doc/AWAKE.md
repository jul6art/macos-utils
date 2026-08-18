<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton-generator/blob/master/public/img/logo.png?raw=true" alt="logo dev in the hood"></a>
</p>

<p align="center">
    <a href="https://opensource.org/licenses/MIT" target="_blank"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
    <img src="https://img.shields.io/static/v1?label=stable&message=v1&color=orange" alt="Version">
</p>

MACOS-UTILS
===========
Awake
-----

A tiny native menu bar app that keeps your Mac awake — the `caffeinate` idea,
with a UI and a timer.

It sits in the menu bar as a ☕ icon, holds an IOKit power assertion while
active, and releases it automatically when the timer expires. No shell command,
no external process, no daemon.

Requirements
------------

* **macOS 13+** (Ventura — `MenuBarExtra` and `SMAppService` are 13.0 APIs)
* **Command Line Tools** (`xcode-select --install`) — Xcode is optional

Sources
-------

| File | Role |
| --- | --- |
| [AwakeApp.swift](/data/sources/awake/AwakeApp.swift) | `MenuBarExtra` scene and the SwiftUI menu |
| [AwakeModel.swift](/data/sources/awake/AwakeModel.swift) | State, durations, countdown timer |
| [SleepPreventer.swift](/data/sources/awake/SleepPreventer.swift) | `IOPMAssertionCreateWithName` wrapper |
| [LaunchAtLogin.swift](/data/sources/awake/LaunchAtLogin.swift) | `SMAppService` login item toggle |
| [Info.plist](/data/sources/awake/Info.plist) | Bundle metadata, `LSUIElement` |
| [build.sh](/data/sources/awake/build.sh) | Builds `Awake.app` without Xcode |

Installation
------------

### Option A — build script (no Xcode needed)

```shell
cd data/sources/awake
sh build.sh --install
```

The app lands in `/Applications/Awake.app`. Open it, the ☕ icon appears in the
menu bar.

Flags:

| Flag | Effect |
| --- | --- |
| *(none)* | builds `build/Awake.app` for the current architecture |
| `--universal` | builds a fat binary (arm64 + x86_64) |
| `--install` | moves the result to `/Applications` |

What the script does: compiles the Swift files with `swiftc`, assembles the
`.app` bundle by hand (`Contents/MacOS`, `Contents/Info.plist`, `PkgInfo`), then
ad-hoc signs it with `codesign --sign -`. Same spirit as
[appify](/data/doc/APPIFY.md), one level up.

### Option B — Xcode project

Prefer a real project if you want to iterate on the UI, add an icon catalog or
notarize a build.

1. Xcode → New Project → macOS → **App**
2. Product Name: `Awake`
3. Interface: **SwiftUI**, Language: **Swift**
4. Deployment Target: **macOS 13.0**
5. Replace the generated `AwakeApp.swift` with [the one from this repo](/data/sources/awake/AwakeApp.swift)
6. Add `AwakeModel.swift`, `SleepPreventer.swift` and `LaunchAtLogin.swift` to the target
7. Target → Info → add `Application is agent (UIElement)` = `YES`
8. Build & Run

Step 7 is what keeps Awake out of the Dock and out of the ⌘-Tab switcher. In the
raw bundle it is the `LSUIElement` key of [Info.plist](/data/sources/awake/Info.plist).

Usage
-----

Click the ☕ icon:

* **Empêcher la mise en veille** — toggles the power assertion
* **Garder l'écran allumé** — see *How it works*; on by default
* **Durée** — 30 minutes / 1 heure / 2 heures / Illimité
* **Lancer au démarrage** — registers the app as a login item
* **Quitter** — releases the assertion and exits

The icon is a ☕ (`cup.and.saucer.fill`) while sleep is prevented and a 💤
(`moon.zzz`) when it is not — two distinct glyphs on purpose, a filled versus
hollow cup is unreadable at menu bar size. When a duration is set, the remaining
time is displayed live and the assertion is released on its own once it reaches
zero.

State survives a relaunch. Quitting the app, updating it or logging back in
restores the previous state: an unlimited session resumes, a timed one resumes
only if its deadline is still ahead — otherwise it comes back off. Without this,
a relaunch silently dropped the assertion while the menu bar icon stayed put.

How it works
------------

Awake takes an IOKit power assertion. **Which one depends on "Garder l'écran
allumé", and the difference matters a lot.**

| Toggle | Assertion | Equivalent | Effect |
| --- | --- | --- | --- |
| on *(default)* | `PreventUserIdleDisplaySleep` | `caffeinate -d` | screen stays on, and the Mac cannot idle-sleep either |
| off | `PreventUserIdleSystemSleep` | `caffeinate -i` | the Mac keeps running, but **the screen still turns off and locks** |

The second one surprises people: the machine is genuinely awake — downloads
finish, builds keep going — yet the screen goes dark on its own schedule and
reads as "my Mac went to sleep anyway". If that is what you are fighting, you
want the toggle on.

Keeping the display on covers system sleep for free: macOS will not idle-sleep a
Mac whose display is lit, so `powerd` holds its own system assertion for as long
as yours holds the display.

In every mode this is *idle* sleep only:

* closing the lid still sleeps the Mac
* the Apple menu → Sleep still works

Check what is actually held from a terminal:

```shell
pmset -g assertions | grep -i awake
pmset -g | grep -E '^ sleep|displaysleep'
```

The second command is the honest one — macOS names the culprit itself:

```
 sleep         1 (sleep prevented by powerd)
 displaysleep  1 (display sleep prevented by Awake)
```

Adding an icon
--------------

Drop an `AppIcon.icns` next to the sources and rebuild — `build.sh` copies it
into `Contents/Resources` and `Info.plist` already points at it:

```shell
mkdir AppIcon.iconset
sips -z 512 512 icon.png --out AppIcon.iconset/icon_512x512.png
iconutil -c icns AppIcon.iconset -o data/sources/awake/AppIcon.icns
```

Gatekeeper
----------

The build is ad-hoc signed, not notarized. On the machine that built it, it just
runs. If you copy the `.app` to another Mac, macOS will quarantine it — clear the
flag there:

```shell
xattr -dr com.apple.quarantine /Applications/Awake.app
```

Troubleshooting
---------------

| Symptom | Fix |
| --- | --- |
| `swiftc: command not found` | `xcode-select --install` |
| No icon in the menu bar | the menu bar is full — quit another item, or check the app is running with `pgrep Awake` |
| "Lancer au démarrage" reverts to off | `SMAppService` needs a signed bundle in `/Applications`; build with `--install` |
| The Mac still sleeps | lid closed or manual sleep — Awake only blocks *idle* sleep |
| The screen turns off / locks anyway | "Garder l'écran allumé" is off — that mode only keeps the *machine* running |
| The Mac sleeps *while Awake looks active* | check the assertion is really held, see below |

### The Mac slept anyway

Two things to check, in order.

**1. Is the right assertion held?**

```shell
pmset -g assertions | grep -i Awake
pmset -g | grep -E '^ sleep|displaysleep'
```

If Awake owns a `PreventUserIdleSystemSleep` but your *screen* is what keeps
going dark, that is the wrong assertion for what you want — turn "Garder l'écran
allumé" on and it becomes `PreventUserIdleDisplaySleep`. If Awake appears
nowhere, the app is running but its toggle is off.

**2. How aggressive are your sleep settings?**

```shell
pmset -g | grep -E 'displaysleep|^ sleep'
```

A value of `1` means the Mac sleeps after **one minute** idle. At that setting
any gap in the assertion — an app relaunch, a crash, a toggle left off — puts
the machine to sleep almost immediately. Adjust in System Settings → Battery /
Energy.

**Reading the history.** `pmset` keeps a log of every assertion and every sleep,
which is the fastest way to find out what really happened:

```shell
pmset -g log | grep -E 'PID [0-9]+\(Awake\)'      # Awake taking/releasing
pmset -g log | grep 'Entering Sleep state'         # sleeps and their cause
```

A sleep logged as `Entering Sleep state due to 'Idle Sleep'` right after a
`[System: No Assertions]` line means nothing was holding the machine awake at
that moment.

License
-------

The MacOS Utils is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2026 [jul6art](https://devinthehood.com)

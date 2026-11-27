# Visage — pilot (lot 0)

> **Status**: done on 2026-11-26. Five measurements, with the sound on and Claude Desktop installed (§ 4).
> **Verdict: go** (§ 5). Visage captures Claude's voice, plays it back delayed without damage, and the mouth
> follows it.

The pilot answered one question before any of the app was written: can a Mac app capture another app's
sound, play it back a little later, and drive a mouth from what it has not played yet?

## 1. What the pilot holds

| File | Role |
|---|---|
| `pilot/TapSession.swift` | The Core Audio tap, muted at the output; the aggregate device that joins it to the default output; a single `IOProc`: capture into a ring buffer, playback delayed by D, a level every 10 ms. |
| `pilot/PilotModel.swift`, `PilotApp.swift` | The window: target, mode (processes or bundle IDs), delay, anticipation, and a rough mouth that follows the level of the sound about to be heard. |
| `pilot/ProcessCatalog.swift` | The system's audio processes, its public taps, and their destruction. |
| `pilot/MicProbe.swift` | The pilot's ear: the microphone's level, to tell whether a voice comes out of the speakers. |
| `pilot/standin/` | A stand-in voice with a real bundle ID, to quit and relaunch. |
| `pilot/run-tests.sh` | All the measurements, in one go (§ 4). |

Build: `sh pilot/build.sh`, with the Command Line Tools only. Log: `~/Library/Logs/VisagePilot/`
(`pilot.log`, `status.json`, times in UTC).

## 2. First results

### 2.1 Capture and playback work

First try, on `afplay` reading a synthetic French voice:

| Measurement | Value |
|---|---|
| Time to the first capture | 6 s, permission included |
| Tap format | 48 kHz, 2 channels, interleaved 32-bit float |
| Aggregate (built-in speakers) | 44.1 kHz, 512-frame buffer, about 82 cycles a second |
| Reported output latency | 743 frames, 16.8 ms |
| Captured level | −22.8 dBFS during the voice |
| `IOProc` overloads | 0 |

The 48 kHz tap and the 44.1 kHz output live together in the aggregate (drift compensation).

### 2.2 Crash (R3): a public tap outlives its process

Killed by `kill -9`, the pilot leaves its **public** tap behind: still listed by the system more than a
minute later. Another process can destroy it (`VisagePilot --destroy-tap <UID>`).

Does the target's sound come back? `CATapMutedWhenTapped` mutes only while a client reads the tap, and the
aggregate and its `IOProc` die with the process: tests 2 and 3 of § 4 measure it at the microphone, for a
private tap and for a public one.

### 2.3 The permission blocks the start

Until the permission to record system audio is given, `AudioDeviceStart` stays blocked (90 s observed),
then returns without a single audio cycle ever running: no silence, nothing.

### 2.4 Drawing in SwiftUI is expensive

The pilot's window, with a `Canvas` redrawn every frame, takes 10 to 14 % of a core on its own, audio
stopped. The app renders with Metal, at a frame rate capped at rest (specification, § 7.2).

### 2.5 No SwiftUI macros without Xcode

`@State` is, in this SDK, a macro whose plugin ships with Xcode only: compiling fails with the Command
Line Tools alone. `@Observable` (Observation) compiles. The pilot holds its model by a plain reference.

### 2.6 macOS 26 can tap an app by its bundle ID

The macOS 26 SDK adds `bundleIDs` (tap an app by its identifier) and `processRestoreEnabled` (find the app
again when it restarts) to `CATapDescription`. Test 4 confirms them: Visage no longer has to follow the
processes of an Electron app by hand on macOS 26 (R2).

## 3. What changed in the design

1. **A private tap**, always. At launch, Visage destroys any public tap named "Visage" left by a version
   that crashed.
2. **The capture starts off the main thread**, and the interface says it is waiting for the permission.
3. **A missing permission is detected**, though not as first thought: the app has been playing for six
   seconds and nothing non-zero came from it since connecting (§ 4). Three seconds without an audio cycle
   proved nothing: on macOS 26, a capture by bundle ID does not run while the app is silent.
4. **If the permission goes inert** (§ 4): `tccutil reset AudioCapture <bundle ID>`, then a new request.
   A stable signature first looked necessary (`VISAGE_SIGN_IDENTITY`, specification § 10.2), lest every
   build lose the permission; Visage, signed ad hoc and rebuilt several times, kept it.
5. **No SwiftUI macros** that need Xcode (`@State`, `#Preview`): an `@Observable` model held by reference.
6. **macOS 15 minimum**: test 4 confirms `bundleIDs` and `processRestoreEnabled` on macOS 26, which Visage
   takes when it finds them; on macOS 15 it follows the processes itself. Requiring macOS 26 would leave
   out nearly every Intel Mac: only four models get it.

## 4. The measurements

Built-in speakers, the built-in microphone as the ear.

| Test | Measurement | Result |
|---|---|---|
| 1 · capture by process | voice captured at −17 dB; through the pilot, the voice comes out at −30.7 dB, as loud as direct (−29 dB); lead 175 ms; 0 frame mismatch, 0 overload | **passed** |
| 2 · crash, private tap | after `kill -9`, the voice comes back at once (−31.9 dB) | **passed** |
| 3 · crash, public tap | the voice comes back (−30.7 dB); the orphan tap stays listed, and can be destroyed | **passed** |
| 4 · by bundle ID, then restart | captured (−27.5 dB), then found again on its own after the app restarted (a single connection in the log) | **passed** |
| 5 · Claude Desktop | reading aloud comes out of "Claude Helper" (`com.anthropic.claudefordesktop.helper`); captured from −17 to −24 dB, dips to −70/−80 dB between sentences; lead 174 to 184 ms; to the eye, the mouth starts with the sound; to the ear, the replayed voice is normal | **passed** |

What the measurements taught:

- **Dictation is not the voice mode.** Test 5 used Claude Desktop's dictation (the microphone button, which
  fills the text field) and "Read aloud" on the answer: the face speaks when Claude reads. Claude Desktop's
  hands-free voice mode opens with the sound-wave button at the bottom right of its window. Tried later
  with Visage, on speakers and with the 150 ms delay, it showed no echo: Claude does not hear itself (R1
  lifted for Claude). It remains to be checked with ChatGPT's voice mode.
- **R2, the bundle IDs**: the app is `com.anthropic.claudefordesktop`, its voice comes from a `….helper`.
  Connecting by bundle ID prefix takes both.
- **Once, the pilot's permission went inert, silently**: macOS kept the checkbox ticked in System
  Settings, but the tap no longer muted the app and delivered only zeros. It took
  `tccutil reset AudioCapture com.devinthehood.visage.pilot` and a new request. The cause is not
  established: rebuilding was suspected first, but Visage kept its permission across every rebuild.
- **The false missing-permission alert**: the Visage app said the permission was missing for as long as
  Claude stayed silent (§ 3, point 3); fixed since.
- **The measurements got in each other's way**: a copy of the pilot left from an earlier run muted the test
  voice, and the 19 s test voice sometimes ended before the last measurement, delayed by the permission
  request. `run-tests.sh` now closes leftover copies first and loops the voice.
- **Once, the pilot's state froze** five seconds after connecting, with no crash and no report; not
  reproduced. To watch for in Visage.
- **The pilot takes about 20 % of the processor**, SwiftUI window included; Visage is measured on its own.

## 5. Verdict: go

Capture, delayed playback and sync hold on Claude's real voice, with no audible damage; a crash gives the
voice back. The pilot has no other role now than replaying these measurements. The rest happens in the app
(specification, § 13).

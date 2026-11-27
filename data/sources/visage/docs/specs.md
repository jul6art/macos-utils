# Visage — specification

> **Status**: written on 2026-11-26, the app built from it the same day. The questions it started from are
> settled (§ 0); the pilot lifted the risks that could stop it (§ 12).
> **In one sentence**: a free Mac app that gives a hologram face, moving to the rhythm of its voice, to the
> AI you already talk to (Claude, ChatGPT, Siri, or Claude Code, given a voice), for nothing more than
> your subscription.
> The app is given away as open source, in `macos-utils`.

---

## 0. Decisions of 2026-11-26

| # | Question | Decision |
|---|---|---|
| Q1 | Where do the heads come from? | **MakeHuman**, through its Blender extension **MPFB2** and the **faceunits01** pack (52 ARKit shapes): CC0 licence, an active community, the same mesh for every head (§ 8.1). |
| Q2 | How many faces? | **10**: 5 men and 5 women, invented, of various ages and origins. |
| Q3 | Which window? | **Two modes**: floating (the default) and classic (§ 9.1). There were three at first; the one transparent among the other windows went on 2026-11-26: on the first try, the face slipped behind Claude at the first click. |
| Q4 | Which repository? | **Public, under the MIT licence**: a gift. Visage joins **`macos-utils`** (public, MIT), in `data/sources/visage/` (§ 10.1). |
| Q5 | A browser mode? | **No**: the official app only. |
| Q6 | Which identity? | **C4 "Poussière"** (dust): a face of dots that comes apart into dust, in ember light. Charter in `docs/charter.md`, files in `brand/`. |
| Q8 | Siri? (2026-11-27) | **Yes, a card shown from the settings** ("Siri among the AIs", off at first): Siri speaks only once its voice responses are on. Its voice plays as it is, neither muted nor played back (§ 4.5). |
| Q7 | Talking with Claude Code, which acts on the Mac? (2026-11-27) | **Yes, through a plugin**: Claude Code listens (`/voice`) but never speaks. Visage's plugin has the Mac's voice read a sentence written for the ear at the end of each reply, and Visage taps that voice like an app's (§ 4.4). Visage does not drive Claude Code itself (§ 4.4). |

## 1. The goal

When you talk to Claude (or ChatGPT) in voice mode on the Mac, a hologram face floats on the desktop and
speaks with its voice. It is accurate enough that **you believe it is the one speaking**. You pick it among
10 faces, 5 men and 5 women.

## 2. Principles

| Principle | What it demands |
|---|---|
| **Free to run** | No paid API, no server. Visage uses the voice mode of the official app, included in the subscription. |
| **As few dependencies as possible** | No third-party package: Swift and Apple's frameworks only. The gate's tools come with Swift. Blender only rebuilds the faces, never the app. |
| **Nothing leaves the Mac** | Visage opens no network connection. It sees no credential, no token, no text: only the sound of the chosen app. Claude Code's voice, the helper its plugin runs, reads only the sentence Claude Code's hook hands it (§ 4.4). |
| **You believe it** | The sync, the lips' anticipation and the face's life come before everything else (§ 7). |
| **A real hologram** | An effect built in layers, not a plain blue filter (§ 8.2). |
| **A gift** | Code under MIT in `macos-utils`, faces made from CC0 assets and two CC-BY hairstyles. Everything Visage adds to the repository can be redistributed freely, with the credit those two require (`data/doc/VISAGE.md`). |
| **Claude, ChatGPT, Claude Code** | One mechanism for all: Visage follows a sound, not an interface. Claude Code's sound is the Mac's voice, which its plugin has read its replies (§ 4.4). |

## 3. How it works

```
 Official app (Claude Desktop or ChatGPT), voice mode
        │ that app's sound only, muted at the output while captured (Core Audio "tap")
        ▼
 ┌──────────────────────── Visage ─────────────────────────┐
 │  ring buffer, fixed delay D ≈ 150 ms                    │
 │      │                                    │             │
 │      ▼ analysis "ahead"                   ▼             │
 │  energy, pitch, formants,           playback of the     │
 │  fricatives, closures               sound, delayed by D │
 │      │                                    │             │
 │      ▼                                    │             │
 │  animation: 52 ARKit shapes,              │ speakers    │
 │  head, gaze, states                       │ or headset  │
 │      │                                    │             │
 │      ▼                                    │             │
 │  Metal hologram rendering ◀── one clock ──┘             │
 └─────────────────────────────────────────────────────────┘
```

**The key**: Visage mutes the AI app's sound and plays it back itself about 150 ms later. Meanwhile, the
analysis already sees what comes next. The mouth can therefore **anticipate** the sound, as a human's does,
instead of always trailing it, which the brain notices at once. In a conversation, 150 ms more before the
answer go unheard.

## 4. "Connect my AI"

### 4.1 Why not a real connection to the account

- An API key would be **paid**, per minute of conversation.
- Anthropic does not allow a third-party app to offer the claude.ai sign-in or to use a subscription's limits
  (terms recalled in the Claude Agent SDK documentation).
- Each app's voice mode is already well made (voice, interruption, choice of model): it is not redone.

"Connect my AI" is therefore **plugging into the official app**, already signed in to your account.

### 4.2 The path

1. On the first launch, **the welcome** opens large and in front, in the charter's colours, the animated
   logo at the top. Four steps on one page: the AI, the face (grid, realism gauge, size, next to a preview),
   where it shows, and where to find Visage in the menu bar; then "Start". The AI step shows two cards,
   **Claude** and **ChatGPT**, which say whether the app is installed and open, and "Another app" lists the
   apps playing sound. Without a welcome, Visage started as a mere sign in the menu bar, which nobody saw.
2. Click on **Claude**: if the app is not installed, the card leads to its official download page.
   Otherwise, Visage opens it.
3. macOS asks, once, for the permission to record system audio.
4. Visage connects. Its state becomes **"Connected to Claude"**, and the head materialises (§ 8.2), then
   moves at rest (breathing, blinks).
5. In Claude Desktop, the **voice mode** opens with the sound-wave button at the bottom right of the window
   (Anthropic's documentation): hands-free, Claude listens and answers aloud, and the face listens, thinks,
   then speaks (§ 7.2). It is not **dictation** (the microphone), which only fills the input field: on the
   first try, dictation was taken for it, with "Read aloud" on the answer, and the face speaks that way too
   (pilot, § 4). Visage's state says it: "Connected to Claude. Start its voice mode: the sound-wave button,
   at the bottom right of its window." ChatGPT's voice mode holds a conversation too.

The choices are remembered: on the next launches, Visage shows nothing more, reconnects on its own and puts
the face back as it was left (shown or hidden, same mode, same size). It also reconnects when the AI app
restarts.

### 4.3 The sources

| Source | Voice mode on the Mac | Worth knowing |
|---|---|---|
| **Claude Desktop** (the main source) | Yes, in beta, on every plan | Languages other than English are in beta. Voice counts in the subscription's usage limits. Not every model is available in voice mode. |
| **ChatGPT** (Mac app) | Yes | Both bundle IDs are recognised, the current app's and the former one's. |
| **Siri** (shown from the settings) | Yes, once its voice responses are on (System Settings, Siri) | Its voice plays as it is: the face follows it live, without the lead (§ 4.5). |
| **Claude Code** (the terminal, the native installer or Homebrew) | No: it listens (`/voice`), Visage's plugin has the Mac's voice answer | It acts on the Mac, with its own permissions; § 4.4. |
| **Another app** | Depends on the app | Any app that plays sound: same mechanism, no guarantee. |

Apps only: no browser mode (Q5).

### 4.4 Claude Code (2026-11-27)

Claude Code acts on the Mac (files, commands, apps) and listens: its dictation, `/voice`, writes what you say
into the prompt, in French among other languages, and its tap mode sends it on its own. It never speaks.
Visage gives it a voice, then a face:

```
 you speak ──/voice──▶ Claude Code ── works, asks for its approvals in the terminal ──▶ reply … 🔊 a sentence
                            │ hooks of Visage's plugin (claude-code/)
     UserPromptSubmit ──────┤ visage-voice prompt: wakes the voice, tells Claude Code about the 🔊 line
     Stop ──────────────────┘ visage-voice stop: hands the 🔊 line to the voice
                            ▼
 visage-voice serve (com.devinthehood.visage.voice) ── the Mac's voice ──▶ tapped by Visage (§ 5)
```

- **The plugin**, `claude-code/`, listed by the repository's marketplace (`.claude-plugin/marketplace.json`
  at its root): `/plugin install visage --marketplace jul6art/macos-utils`. Its hooks run `bin/visage-hook`,
  which runs the helper of the Visage running now, wherever it is installed; without Visage, nothing.
- **A sentence for the ear**: Claude Code writes for a terminal (lists, code, paths), which sounds wrong
  read out. While Visage listens to Claude Code, each prompt carries a short context, worded as facts
  (Claude Code's hooks documentation warns that imperative wording can trip its defences against prompt
  injection): Visage reads aloud the line of the final reply that starts with 🔊, one or two sentences in
  the conversation's language, written to be heard, and only that line. A short reply without it (280
  characters, no code) is read whole. Tried on 2026-11-27: « Il y a quarante-six fichiers Swift dans les
  sources de Visage, dont dix-neuf dans le dossier de l'application. »
- **The voice**, `visage-voice` in `Visage.app/Contents/Helpers`, its bundle ID embedded in the executable:
  Visage taps it like an app and never sees the text. It speaks with the best voice installed for the
  sentence's language, of the face's gender when one is installed, premium before enhanced. A new prompt
  hushes it; a permission prompt has it say that Claude Code waits for an answer in the terminal.
- **One process, alive while Visage listens**: a helper born with each reply was caught late, as a tap by
  bundle ID missed it, then stayed blocked once it was gone (2026-11-27). The prompt therefore wakes the
  voice, which opens the sound output once, so that Core Audio lists it, and waits 2.5 seconds before its
  first sentence; the hooks hand it the sentences through a socket in the user's temporary folder. It
  leaves once Visage no longer listens to Claude Code, or after 30 minutes without a sentence. Visage
  follows its process, as on macOS 15, even on macOS 26: measured, it plays the voice back 0.22 s after
  its first sound, the delay D included.
- **The face listens**: the dictation records in the `claude` process
  (`~/.local/share/claude/versions/<version>` for the native installer), whose open microphone is the AI
  listening (§ 7.2).
- **Visage does not drive Claude Code.** It could have run `claude -p` itself, with its own speech
  recognition: Anthropic does not allow a third-party app to use a claude.ai subscription (Agent SDK
  documentation), and an API key is paid (§ 2, "Free to run"). The plugin leaves Claude Code as it is,
  permissions included: nothing runs on the Mac without the user's approval in the terminal.

### 4.5 Siri (2026-11-27)

- **Its voice** comes from `com.apple.sirittsd`, Siri's speech service, a launch agent started on demand:
  the same process carried two answers twenty seconds apart (seen on macOS 27). With the keyboard, or its
  voice responses off, Siri only writes: nothing to give a face to. "Siri among the AIs", in the
  conversation's settings, shows its card; off at first.
- **Visage waits for its first answer**, then taps it by its bundle ID: a tap by bundle ID made before the
  service exists blocked (seen with Claude Code's voice, § 4.4).
- **Passed through, not played back**: Siri lowers every other sound while it speaks, Visage's playback
  with it. Muted then played back 150 ms later, its voice was not heard at all; the face moved alone. Its
  voice therefore plays as it is, unmuted (`CATapDescription` `.unmuted`), and Visage plays nothing: the
  face follows the last frame analysed, without the lead that the delay D gives (§ 3), a few tens of
  milliseconds late. Tried on 2026-11-27: the voice heard as usual, the lips with it.
- **Listening**: no process of Siri's opens the microphone when it listens, only `corespeechd`, which
  listens all the time for "Hey Siri": the face does not know when Siri listens.

## 5. Capturing and playing back the sound

- **API**: Core Audio's per-process "taps" (macOS 14.2 and later). A `CATapDescription` on the AI app's
  audio processes, with `muteBehavior` set to `.mutedWhenTapped`, then an aggregate device that carries the
  tap, and a callback (`IOProc`) that reads 32-bit float frames. The tap is **private**: a public tap
  outlives the process that created it (pilot, § 2.2).
- **Finding the right process**: the list `kAudioHardwarePropertyProcessObjectList`, filtered by bundle ID
  (`kAudioProcessPropertyBundleID`). Claude Desktop is an Electron app whose sound comes from a helper
  process: the filter is a bundle ID prefix and the responsible PID. The exact identifiers of both apps
  were taken from the pilot (lot 0), not guessed. On macOS 26, Core Audio follows exactly the identifiers
  given to the tap: a helper born after connecting (Claude's audio service, which carries its voice and its
  microphone) makes the tap be redone.
- **Mute without loss**: while the tap is active, the AI app's sound no longer reaches the speakers, and
  Visage plays it back. Siri alone passes through, unmuted and not played back (§ 4.5).
- **Buffer**: a lock-free ring buffer (one producer: the `IOProc`; one consumer: the playback). The delay
  **D is 150 ms by default, adjustable from 80 to 300 ms**. No allocation and no lock on the real-time
  thread.
- **Playback**: in the same `IOProc`, on the output of the aggregate, whose main device is the default
  output: capture and playback share a clock, with no drift (validated by the pilot). When the default
  output changes (headphones plugged in, AirPods), Visage rebuilds the aggregate.
- **Starting off the main thread**: until the permission is given, `AudioDeviceStart` stays blocked (90 s
  in the pilot). The interface says it is waiting for the permission.
- **Missing permission**: the app has been playing for six seconds, and nothing non-zero came from it since
  connecting. Visage then offers the *Screen & System Audio Recording* pane of System Settings. Neither the
  app's silence nor the absence of audio cycles proves anything: on macOS 26, a capture by bundle ID does
  not run while the app is silent. A sound heard proves the permission. A tap inert despite the permission
  being ticked, nothing muted and zeros, was seen once with the pilot; its cause is not established (pilot,
  § 4).
- **One clock**: everything is timed in host time (`mHostTime`): capture, playback, displayed frame.
- **Safety**: if Visage quits or crashes, the AI's sound must come back on its own: the mute lasts only
  while the tap is read, and the aggregate dies with the process. **Blocking** (criterion 6, § 11.3):
  measured at the microphone by the pilot (tests 2 and 3). At launch, Visage destroys any public tap named
  "Visage" left by a version that crashed.
- **The AI app's microphone**: Core Audio says, without any permission, when a process of the app has its
  microphone open (`kAudioProcessPropertyIsRunningInput`), never what it hears. Visage reads it four times
  a second: its voice mode or its dictation is listening (§ 7.2).
- **Microphone (option)**: only while the AI app holds its own open, Visage opens the microphone, measures
  each buffer of 1,024 frames (root mean square) and drops it; it closes it three seconds after the app. A
  voice is 12 dB above the room (the lowest level of the last three seconds) and at least −55 dBFS, held
  250 ms through the gaps between syllables. Nothing is recorded or sent.

## 6. Analysing the voice

### 6.1 V1: no model, signal processing

Windows of 25 ms, a hop of 10 ms (100 frames a second), all in Accelerate (`vDSP`):

| Measure | Method | Drives |
|---|---|---|
| Energy, voicing | RMS in dB, zero-crossing rate | speaking or silent, the jaw's opening |
| Intonation (F0) | YIN | brows, nods, questions |
| Vowels, continuously | formants F1, F2, F3 by LPC (Levinson-Durbin), peaks of the envelope | F1 gives the opening; F2 front or back (lips spread or rounded); a lowered F3 the rounding (French "u" and "eu") |
| Fricatives | spectral centroid, energy above 4 kHz | "s/z" lips spread and teeth; "sh/zh" lips forward; "f/v" lower lip under the teeth |
| Closures | an energy drop followed by a burst; nasal murmur (strong lows, weak highs) | "b/p": lips shut before the sound; "m": lips shut |

**Automatic normalisation**: Visage learns the range of F0, F1 and F2 of the voice during the first minute
(sliding percentiles), then remembers it per source and per voice. No manual calibration.

**Why no model first**: no dependency, no heavy file, independent of the language (French works as well as
English), and a few percent of one core are enough.

**Lips or tongue?** It is not the height of F2 that tells p, b, m from t, d, n, k, g: it is its motion. It
falls into a lip closure and rises out of it; the tongue pulls it up, or leaves it flat. Visage weighs both
slopes (a drift under 60 Hz does not count), then the height of F2 at the edges. It guesses on entering the
closure, and confirms 60 ms after leaving it, still within the lead the delay gives. Its traps, met and
settled:

- F1 and F2 merge when they come close (an "a" before a "p"): the next peak is then F3. No vowel has both a
  high F1 and a high F2: such a pair is a merge;
- the frame next to a closure overlaps the silence: its formants lie, it is set aside;
- the voicing bar of a "b" flickers between murmur and vowel: the closure is stitched back together;
- a vowel fading at the end of a sentence is not a murmur: its level falls too fast.

**Measured on 2026-11-26**, on macOS's French synthetic voices (`say`, files only, no sound played), with
`Visage --analyse`:

| Measure | Result |
|---|---|
| Pitch (YIN) | Jacques 127 Hz, Eddy 112 Hz, Flo 243 Hz: plausible; within 3 % on synthetic signals |
| Formants of synthesised a, i, u | F1 within 15–20 %, F2 within 12–20 %; a opens, i spreads, u rounds |
| Closures: lips or tongue | **46 out of 48** (16 VCV syllables — apa, aba, ata… amma, anna — × 3 voices), against 41 before the tuning above. Left: Flo's "m" and one of Eddy's "ibi" |

These settings were tuned on macOS voices; Claude's own voice was then tried through the pilot (§ 4 of its
report) and in the app.

### 6.2 V2, only if V1 misses the criteria of § 11.3

A multilingual phoneme recognition model (the wav2vec2 family), converted once to Core ML outside the app
and run on the Neural Engine. It is a model file, not a code dependency. Its licence must allow
redistribution in an MIT repository. The output stays the same (§ 7): the rest of the app does not change.

## 7. Animation: what makes you believe it

At every frame, the animation produces **the 52 ARKit weights**, the **head's pose** (three rotations) and
the **gaze** (the eyes' rotation).

### 7.1 While it speaks

1. **Anticipation**: the mouth's shape at time *t* comes from the analysis of *t* + 60 ms (adjustable). The
   lips form before the sound, never after.
2. **Jaw and lips apart**: the jaw follows the energy and F1; the lips follow F2, F3, the fricatives and the
   closures.
3. **Smooth transitions**: a damped spring per channel, a fast attack and a slower release. No jump from
   one shape to the next.
4. **Closures first**: on "b", "p" and "m", the lips' closure wins over the jaw for 40 to 80 ms. That is
   what the eye checks.
5. **The voice moves the whole face**: a rising intonation lifts the brows; a stressed syllable (a peak of
   energy and F0) gives a small nod; at the end of a sentence, the head settles and a blink becomes likely.
6. **Four states**: *speaking* (this § 7.1), *listening*, *thinking* and *waiting*, detailed in § 7.2.
7. **Gaze**: towards the camera by default. As an option, Vision finds your face in the camera's image, and
   the gaze, then the head, follow you. Nothing is recorded.
8. **Never mechanical**: coherent noise (simplex), drawn at random at every launch. Two blinks never fall at
   the same interval.
9. **Sync to the display**: each frame is computed for the sample that will be **heard** at the moment the
   frame is **displayed**. That moment is the display time (macOS 14's `CADisplayLink`), plus the device's
   output latency (Core Audio), plus a **"lip offset"** setting from −100 to 300 ms, for Bluetooth
   headphones.

### 7.2 At rest: alive, even when it does not speak

A frozen face gives the machine away at once. At rest, Visage stays alive on three layers that add up: the
face, the moment of the conversation, and the hologram. Everything is drawn at random (coherent noise,
random intervals), so that nothing repeats.

**The face**

| Movement | Rhythm | Detail |
|---|---|---|
| Breathing | 12 to 16 a minute | the head barely rises and falls, the nostrils open a little |
| Blinks | every 2 to 6 s | 100 to 150 ms; sometimes double; more frequent just after a sentence |
| Micro-saccades | every 0.5 to 2 s | tiny jumps of the gaze, which keep the eye from looking painted |
| The gaze wanders | every 5 to 15 s | it rests elsewhere for a second or two, then comes back to you (or to the camera) |
| Head drift | continuous | slow, a few degrees, never periodic |
| Micro-expressions | every 20 to 60 s | the start of a smile, a moving brow, pressed lips; never two at once |

**The moment of the conversation**

- *listening* (the AI app has its microphone open, § 5): the gaze stays on you, without wandering; with the
  microphone option, the head often nods at the pauses in your sentence (after 0.5 s of voice and 0.2 s of
  silence, never while you speak), without it now and then. Brows that follow your intonation will wait: it
  would take analysing your voice, not only its level;
- *thinking* (between the end of your sentence and its answer): the gaze rises or moves aside, the head
  tilts slightly, the lips press together. Your sentence is over after 0.7 s of silence, if you spoke for
  0.3 s at least (microphone option); a dictation is over when the app closes its microphone after 1 to
  90 s (longer, it was a voice mode being closed). With no answer, thinking stops after 15 s;
- *speaking*: the AI's voice, its pauses under 0.8 s included. For 0.4 s more, the microphone hears its
  voice through the speakers: that is not you;
- *waiting* (nobody speaks): the movements of the table, alone.

**The hologram**

- a glow lower than when speaking (about −30 %), a slow flicker;
- the scanlines always scroll, but the scan band passes only every 6 to 12 s;
- dust floats in the projector's beam;
- a very rare glitch, at most once a minute;
- in halftone rendering, the light falling on the face turns very slowly: the screen breathes.

**The transitions**

- *rest → speech*: the mouth opens slightly before the first sound (anticipation, § 7.1), the glow rises in
  150 ms;
- *speech → rest*: back in 300 to 500 ms, the mouth closes, a blink becomes likely;
- *standby*: after 5 minutes without a voice (adjustable), the eyelids grow heavy, the light dims, and the
  face comes apart into dust down to a cloud of points that breathes. It forms again as soon as the voice
  returns, or when the mouse hovers over it;
- *signal lost* (the AI app is closed, or the capture dropped): the face freezes into an unlit cloud of
  points, and the menu bar icon says so.

**Economy**: 30 frames a second at rest, 15 in standby, no rendering while the window is hidden.

## 8. Faces and hologram rendering

### 8.1 The faces: MakeHuman (MPFB2)

**The choice.** Three sources were compared:

| | **MakeHuman (MPFB2)** | MetaHuman (Epic) | Rocketbox (Microsoft) |
|---|---|---|---|
| Licence | **CC0**: free redistribution, no attribution; the community's packs add CC0 skins, irises and hair materials, and hairstyles under CC-BY (attribution) | Unreal Engine's licence. Usable outside Unreal since 2025, but the files stay under Epic's licence: they cannot be put under MIT, and redistributing them raw in a public repository is not clearly allowed. A moving licence: an AI clause added in June 2025, lifted in October 2026. | MIT |
| Community | active: official Blender extension, MPFB 2.0.16 in June 2026 | huge | repository archived on 2026-10-02 |
| Realism | good for shapes, average for skin | the best | low (2010s, few polygons) |
| 52 ARKit shapes | **native** (faceunits01 pack) | to bake from the ARKit mapping pose, in Unreal | yes (added in 2022) |
| Same mesh for every head | yes | yes | yes |
| Tool | Blender (free) | Unreal Engine (heavy) | Maya or Unity |

**Verdict: MakeHuman.** It is the only source both realistic enough and possible to give away. MetaHuman
would make finer faces, but they cannot be given. And in a hologram, skin nearly disappears: realism comes
from the **shapes**, the **eyes** and the **motion**. MakeHuman holds the shapes, the animation (§ 7) does
the rest.

**The 10 faces**: 5 men and 5 women, from 20 to 65 years old, of various origins, all **invented**
(synthetic people, in the image of no real person). They are picked in a grid, and the face can be changed
live, with a fade, even while it speaks.

**What pushes the realism**:
- separate eyes that turn with the gaze; eyelashes and brows, laid softly over the skin;
- skins, irises and hair from the community's packs: MakeHuman's own skins are smooth and pale at the lips,
  its irises flat, its hair a helmet with a hard edge on the forehead. Freckled or warmer skins (`skins01`,
  `skins02`), finer irises (`system_eye_materials01`), finer materials for MakeHuman's short and long
  styles (`system_hair_materials01` and `02`), all CC0; and two styles by Elvaerwyn that fall naturally,
  Léa's and Inès's (`hair02`, CC-BY, credited in `data/doc/VISAGE.md`). Other styles of the pack were
  tried and left: a fringe of separate strands that falls over the eyes goes whole when the hair is tidied, and the
  forehead is left bare;
- hair rendered as hologram strands;
- teeth and a tongue that follow the jaw: each faceunits01 shape is refitted on them and saved as a shape of
  their own, so they move like the head;
- per-face settings in `presets.json`: MakeHuman's weighted targets (`features`), `proportions`, the
  `skin`, the irises (`eyes`), the hair and its material (`hair`, `hairMaterial`), and the colours of the
  hair and the brows;
- at rest, relaxed eyelids and a hint of a smile.

Not done yet, to be judged on the blind test (R6) first: subdivision at export, a normal map taken from a
CC0 skin, the cornea and its wet reflection. The pack's textures serve the realistic end of the gauge
(§ 8.3).

**The build chain**:

```
tools/faces/
  presets.json         the 10 faces: MakeHuman settings (gender, age, origins, weight, muscle),
                       weighted targets, proportions, skin, irises, hair and its material, brows,
                       lashes, colours
  build_faces.py       Blender with no interface (blender -b -P): creates each face with MPFB2, bakes its
                       morphology, adds eyes, brows, lashes, teeth, tongue and hair, loads the 52 shapes,
                       saves them on each object, keeps the head and the neck (25 cm), removes the hidden
                       faces, exports a .glb, then writes one texture per part next to it
                       (<face>.<part>.jpg or .png, § 8.3)
  build.sh             runs it (every face, or the ones named) and copies presets.json
Resources/Faces/       the generated files, committed: building the app needs no Blender
```

**Hidden faces are removed at build time.** The hologram's light is additive: it goes through everything.
The inside of the mouth and the back of the eye sockets, behind the eyeballs, showed through the face: two
rings around the eyes, like glasses, and a third around the mouth. A face is kept if, from one millimetre
above its centre, a ray towards one of 120 viewpoints (up to 70° to the side, 35° up or down) meets neither
the head nor the eyes. The millimetre matters: the centre of a non-planar quad sinks under its own surface
where the skin bulges, and the ray hit the face itself. Those faces were wrongly removed, holes invisible as
points that riddled the skin as a surface. About 1,200 faces out of 8,500 go, the back of the skull
included: it is never seen.

**The hair is tidied at build time.** It never covers the face below the brows: a strand of the `bob01` cut
crossed Mei's from temple to chin. And nothing hangs behind a neck that no longer exists: Inès's ponytail
showed under her chin.

**Every vertex is a point of light.** MakeHuman's mesh follows the features of the face: its loops draw the
eyelids, the lips, the wings of the nose, and the hologram shows them. Sampling the surface uniformly was
tried and dropped: the random grain drowned the modelling, and the face shrank to its outline. Vertices do
crowd around the eyes, the mouth and the ears; each point there gives up a share of its light according to
the number of its neighbours (within 4 mm), enough for those areas not to shine more than the rest without
erasing the features. Of the eyeball, only the part visible between the eyelids lights up: the iris more
than the white, the pupil dark.

**What each `.glb` holds** (glTF 2.0): the 52 ARKit shapes named after the standard (`jawOpen`,
`mouthClose`, `mouthFunnel`…) in `extras.targetNames`, as sparse targets, and the texture coordinates; no
material and no image (the textures sit next to it). The same naming for all, hence one shared animation;
the mesh itself varies from face to face once the hidden faces are removed. Every clone of `macos-utils`
downloads them, so each `.glb` must stay **under 3 MB** and each face's textures under 2.5 MB, and fewer
than 40,000 points. A test checks it (§ 11.2).

**A home-made glTF loader** (positions, normals, texture coordinates, triangles, dense or sparse morph
targets): about 200 lines, no library. A vertex on a texture seam is exported once per side, at the same
place: drawn twice, it would make the seams shine; its twin serves the surface only.

**Choosing the face**: a grid of thumbnails in the settings (each face at rest, made the first time the
window opens, off the main thread), a list of names in the menu; the charter's point head besides the ten.
The new face is read off the main thread, then replaces the old one with a 0.6 s fade after a brief glitch,
even while it speaks.

### 8.2 The rendering: a real hologram

A **home-made Metal** renderer: a single head to draw, a tailor-made effect, and no tie to SceneKit
(deprecated in 2025) nor to RealityKit. The **shaders are compiled at launch** from their source
(`makeLibrary(source:)`): Xcode's Metal toolchain is not needed. Morphing runs on the processor,
position = base + Σ (weight × delta) over the vertices of each sparse target only: a few tens of thousands
of points, a fraction of a millisecond.

The effect is built in layers, each adjustable:

1. **The projector**: a discreet plinth under the head, a cone-shaped beam of light (additive gradient) and
   dust floating in the beam. It can be hidden.
2. **The head's light**:
   - additive transparency, with a depth pre-pass: the skin and the eyeballs, drawn first into the depth
     buffer only, hide what is behind them from every angle (the hair at the back, the teeth behind closed
     lips, the eye under a closing eyelid). Points are tested 1.5 mm forward there, so that the skin does
     not hide its own points. The inside of the head is also removed at build time (§ 8.1), and the points
     turned backwards go dark;
   - a glowing outline (Fresnel);
   - a luminance taken from the skin, so that the eyes, the brows and the lips stay readable;
   - the mesh's edges, barely visible.
3. **The signal**:
   - scrolling scanlines, interlacing (every other line a little darker, alternating at each frame) and
     grain;
   - a slight flicker;
   - a rare glitch: shifted horizontal slices and chromatic aberration.
4. **The voice in the light**: the glow and the flicker follow the voice's energy. The face lights up when
   it speaks.
5. **The appearance**: on connecting, a scan band sweeps down and builds the head line by line. On
   disconnecting, it dissolves.
6. **The halo**: a two-pass bloom.
7. **Parallax** (camera option): Vision follows where your head is, and the rendering camera moves with it
   (off-axis projection). The head seems to have a real volume behind the screen: that is what makes a flat
   screen pass for a hologram.
8. **The colour**: the charter's braise (`#FFC978`) by default, with a palette to choose from; a point cloud
   mode as an option, the mark's.

The style stays that of a generic science-fiction hologram: it imitates no work in particular. The target
is 60 frames a second (120 on a ProMotion display) while it speaks, 30 at rest.

### 8.3 The realism gauge

A "Realism" slider in the settings, under the grid of faces: from 0 %, the hologram of points, to 100 %, the
face as real as MakeHuman allows.

- **The surface**: the triangles of each part, textured (skin, iris, hair, brows, lashes, teeth, tongue:
  the packs' textures, reduced; the skin, a whole-body texture, cropped to the head), lit by a key light
  at the top left, a fill light on the right and a rim. The skin is a little warm in the shadows, the eye
  has a sharp highlight. Hair, brows and lashes are cut out where their texture is transparent.
- **The blend**: the surface rises with the gauge, first tinted with the hologram's colour, then in its true
  colours; the points fade as much; the halo, the scanlines, the flicker, the band and the plinth fade
  away. A depth pass of the surfaces precedes their colour: translucent, the face shows only its nearest
  layer, not the inside of the skull. The cut neck fades out instead of ending in a jagged edge.
- **The mouth**: ARKit's `mouthClose` closes the lips over an open jaw, and beyond `jawOpen` they pass
  through each other (a bump under the nose on "p", "b" and "m", invisible as points). The animator's says
  how closed the lips are: `MeshHead` translates it by multiplying it by the jaw's opening. And a mouth at
  rest is closed: the few hundredths of jaw that breathing adds no longer part the lips.
- **The limits, said plainly**: 100 % means MakeHuman's level, a game character convincing from a distance,
  not a filmed person. In close-up, the uncanny valley lurks: slightly doll-like eyes, smooth skin, brows
  drawn as strokes. The hologram forgives lip sync without phonemes, the real face less so: the gauge lets
  everyone choose. Photorealism would need MetaHuman (not redistributable) or a model that animates a photo
  (heavy, and too close to a deepfake): out of scope.

`Visage --render … --realism <0-100>` films at a given level, or sliding the gauge (`--realism 0-100`);
`--snapshot` adds the sheet of the ten faces at 100 % (`faces-real.png`).

## 9. Window and settings

### 9.1 Two window modes

| Mode | The window | What for |
|---|---|---|
| **Floating** (the default) | No frame, invisible background and shadow: only the head floats, above every window, on every desktop and above full-screen apps. It is moved by dragging the head. | The hologram effect, always in sight. |
| **Classic** | A normal window with a title bar and a dark background. | Screen sharing, video recording, a "showcase". |

A third mode, transparent among the other windows, was removed on 2026-11-26: the face went behind Claude
as soon as Claude was clicked. A setting saved with it reads as "floating". The mode changes live, from the
menu bar or the settings.

### 9.2 Menu bar and settings

- **The menu bar icon** gives the state (connected to Claude, waiting), shows or hides the face, picks the
  face and the window mode, opens the settings, and quits.
- **Its windows open in front**: with no icon in the Dock, macOS never brings Visage to the front, and its
  windows opened behind the others. While the welcome, the connection or the settings are open, Visage
  becomes an ordinary app, in front, with an icon in the Dock; it goes back to the menu bar when they close.
- **The settings**, in their own window in the charter's colours, the animated logo at the top: on the
  left, the preview of the face at rest, as the choices make it; on the right, in cards, the face (grid,
  realism gauge, size from 50 to 200 %), the hologram (colour, halo, scanlines, plinth and beam, flicker and
  glitches), the conversation (is the AI listening? the microphone option, Siri among the AIs), the camera,
  the window (the two modes, explained), the sync (delay, anticipation, lip offset).

## 10. Technical architecture

### 10.1 In `macos-utils`

Visage is one more utility of `macos-utils` (public, MIT), laid out like the others:

```
macos-utils/
  README.md               one more row in the utilities table, and its requirements
  data/doc/VISAGE.md      the user documentation, in English: requirements, sources, installation, usage
  data/sources/visage/    Visage's sources (§ 10.2), including docs/specs.md, this specification
  .claude-plugin/         the repository's Claude Code marketplace: Visage's plugin (§ 4.4)
```

Visage follows the repository's conventions:

- a `build.sh` that builds without Xcode (the Command Line Tools are enough), with `--install` and
  `--universal`;
- the identifier `com.devinthehood.visage` and an ad hoc signature (`codesign --sign -`): no notarized
  DMG, a source you assemble yourself. For convenience, `data/sources/release.sh` also packs that source
  into a universal archive for GitHub's releases page, reproducible byte for byte, so that a download can
  be checked against its tag;
- an interface in English, like Awake and Siphon, translated into French (`Localizable.strings` in en and
  fr, following the system's language), in the system font: the app embeds no font (charter, § 4);
- an app icon drawn by code at build time (`brand/generate.sh --iconset`): no bitmap in the repository;
- commit messages in French, like the rest of the repository; code, comments and documentation in English.

Two adaptations of the repository, at lot 1:

- **`CONTRIBUTING.md`** described a "deliberately small" collection, one you can read end to end before
  running it. Visage is much bigger than Awake or Siphon. The rule evolves: each utility stays readable and
  free of third-party packages, and Visage documents its modules so that it can be read piece by piece.
- **The weight**: `macos-utils` weighed about 1.7 MB on 2026-11-26, and every clone carries every utility.
  The 10 faces are therefore limited to 3 MB each for the mesh. They are rebuilt only when needed, because
  every rebuild adds to the history. The `.gitignore` leaves out Visage's `build/`.

### 10.2 The code

**Swift 6, compiled by `swiftc` like the other utilities of `macos-utils`, macOS 15 at least** (the atomic
counters of the `Synchronization` module). The pilot confirmed macOS 26's capture by bundle ID
(`bundleIDs`, `processRestoreEnabled`: pilot, § 2.6 and § 4): Visage takes it when it finds it, and follows
the processes itself on macOS 15. The minimum therefore stays macOS 15, which keeps the Intel Macs from 2018
on; macOS 26 reaches only four Intel models. The app is built for Intel too (`x86_64`,
`build.sh --universal`). It is developed on macOS 27.

**No SwiftPM.** With the Command Line Tools at hand (Swift 6.4.2), SwiftPM could not even link the manifest
of a blank package: its `PackageDescription` library does not match the compiler (seen on 2026-11-26).
`build.sh` therefore compiles each module of `Sources/` into a static library, in dependency order, then
links the app: fewer moving parts, and the repository's convention. Contents of `data/sources/visage/`:

```
Sources/
  VisageApp/       SwiftUI + AppKit: the face's window (2 modes), menu bar, settings, "Connect my AI"
  AudioSource/     process discovery, Core Audio tap, ring buffer, delayed playback
  VoiceAnalysis/   frames, energy, F0, LPC and formants, fricatives, closures, normalisation
  FaceAnimation/   mapping to ARKit, anticipation, springs, prosody, states, gaze
  HoloRenderer/    glTF loader, morphing, the hologram's layers and shaders, halo, parallax
  Shared/          host clock, the brand's geometry, what Visage shares with Claude Code's voice
  SpokenReply/     Claude Code's voice: the 🔊 line, the hooks' input, the choice of a voice
  VisageVoice/     visage-voice, Claude Code's voice (Contents/Helpers), and its embedded Info.plist
Resources/
  Faces/           the 10 faces (.glb and textures), built by tools/faces
  en.lproj/, fr.lproj/
Tests/             one folder per module, and TestRunner.swift, the tests' entry point
claude-code/       Claude Code's plugin: its hooks and bin/visage-hook (§ 4.4)
tools/faces/       the Blender chain (§ 8.1)
tools/doc-images.sh  the pictures of data/doc/VISAGE.md, made with --snapshot and --render
brand/             the brand kit (kit/) and the files it writes: logos, animations, icon
pilot/             the pilot (lot 0)
docs/              this specification, the charter, the pilot's report
Info.plist
build.sh           builds Visage.app (modules, app, resources, icon, signature); --universal, --tests, --install
check.sh           the gate
```

- **Dependencies: no third-party package.** Only Apple's frameworks: SwiftUI, AppKit, CoreAudio,
  AudioToolbox, AVFAudio, Accelerate, Metal, QuartzCore; Vision and AVFoundation for the camera option;
  AVFoundation's speech synthesizer and NaturalLanguage for Claude Code's voice; Core ML for V2 only. The atomic counters come from the standard library's `Synchronization` module.
- **Threads**: the `IOProc` on the real-time thread (no allocation, no lock), the analysis on a dedicated
  thread, the rendering on the display link. They exchange through lock-free ring buffers.
- **Building**: `build.sh` compiles the modules and the app, then assembles the `.app` with `Info.plist`
  (including `NSAudioCaptureUsageDescription` and, for the options, `NSMicrophoneUsageDescription` and
  `NSCameraUsageDescription`), the translations and the icon. The shaders travel in the code, as strings
  compiled at launch: no resource bundle to sign.
- **The screens are checked without a screen**: `Visage --snapshot <folder>` renders each screen, in each
  state that matters, to PNG, offscreen (an offscreen window, not `ImageRenderer`, which draws AppKit
  controls as placeholders). Neither a display nor the screen recording permission is needed.
- **No SwiftUI macros that need Xcode**: `@State` and `#Preview` are, in this SDK, macros whose plugin
  ships with Xcode only; building with the Command Line Tools fails (pilot, § 2.5). The model is
  `@Observable` (the Observation macro compiles) and held by reference.
- **Signing in development**: `build.sh` signs ad hoc, under a fixed identifier. Visage, rebuilt several
  times on 2026-11-26, kept its audio permission; the pilot lost it once, with no established cause (pilot,
  § 4). If needed, `VISAGE_SIGN_IDENTITY` lets `build.sh` sign with a local self-signed certificate (free,
  Keychain Access).
- **Network**: none. An App Sandbox without network entitlement, if the sandbox works with the taps (not
  tried yet).

## 11. Quality

### 11.1 The gate (before every commit)

`sh check.sh`: building the app, the tests, then `swift format lint --strict`; `--fix` formats the sources
first. The tests are written with Swift Testing, which ships with the Command Line Tools (XCTest does not):
`build.sh --tests` compiles the modules with `-enable-testing` and links the tests into an executable whose
entry point is `Tests/TestRunner.swift`. The gate reads the count ("Test run with N tests passed"), not
only the exit code. Nothing to install.

**No CI**: `macos-utils` has none. A GitHub workflow (macOS runner, free for a public repository) could run
the same gate.

### 11.2 The tests

- **Analysis**: on synthetic signals (vowels synthesised with known formants, fricative noises, silences
  and bursts). F1, F2, F0 and the detection of closures are checked.
- **Animation**: mapping and springs, deterministically, with a fixed seed.
- **Faces and glTF loader**: each `.glb` of `Resources/Faces` holds its parts and the 52 ARKit names, weighs
  under 3 MB and gives fewer than 40,000 points; its occluding triangles point to points that exist;
  `jawOpen` lowers the jaw without touching the forehead, the gaze turns the eyes only.
- **Ring buffer**: concurrently, producer against consumer.
- **File mode**: Visage reads an audio file instead of an app. It serves tuning without an AI, demos, and
  **offline video rendering** (`.mov` through AVAssetWriter), to compare two versions frame by frame. It
  also makes the pictures of the documentation (`tools/doc-images.sh`).
- **Reference recordings**: 5 excerpts of Claude's voice in French and 2 of ChatGPT's, annotated by hand
  (the instants of "b", "p" and "m"). They stay **out of the repository**, which is public.

### 11.3 Acceptance criteria: "you believe it"

1. **Sync**: the mouth leads the sound by 0 to 60 ms and is never more than 20 ms late. Measured by filming
   the screen in slow motion (240 frames a second) with a phone.
2. **Closures**: the lips close on at least 90 % of the "b", "p" and "m" of the reference excerpts.
3. **Never frozen**: no interval of more than one second without the face moving, waiting included; and
   over two minutes of filmed rest, no repetition can be spotted.
4. **Blind test**: out of 10 excerpts, "you believe it" on at least 8.
5. **Budgets** (an Apple silicon MacBook): capture and analysis under 10 % of a core, a frame under 4 ms of
   GPU, under 250 MB of memory, no audio crackle in an hour.
6. **Safety**: Visage quit or crashed, the AI's sound comes back in under a second.

## 12. Risks, lifted by the pilot or by the lot concerned

| # | Risk | Answer |
|---|---|---|
| R1 | **Echo**: played back 150 ms later, the sound may fool the AI app's echo cancellation, which would hear itself and stop. | With headphones, no problem. On speakers, measure, then lower D or advise headphones. Does not arise with "Read aloud" (pilot, § 4). **Lifted for Claude on 2026-11-26**: in hands-free voice mode, on speakers, with the 150 ms delay, Claude does not hear itself. ChatGPT remains. |
| R2 | **Audio processes**: find the one playing the voice (Claude Desktop is an Electron app) and follow it when the app restarts. | macOS 26 taps an app by its bundle ID and finds it again when it restarts (pilot, tests 4 and 5); otherwise, filter by prefix and responsible PID. |
| R3 | **Safe muting**: the AI's sound must come back if Visage stops. | Criterion 6, blocking. Private tap; measured at the microphone by the pilot (tests 2 and 3). |
| R4 | **Analysis without a model** not good enough in French. | V2 in Core ML (§ 6.2). |
| R5 | **Voice mode in beta** at Claude (French too): the voice may change. | Visage follows only the sound: automatic normalisation learns the voice again. |
| R6 | **MakeHuman's realism** too thin in close-up. | Subdivision, normal maps, careful eyes; the hologram and the parallax carry the rest. Judged on the blind test. |
| R7 | **The faces' weight**: every clone of `macos-utils` carries them. | Under 3 MB per `.glb` (sparse targets) and 2.5 MB of textures per face, checked by a test, about 30 MB for the ten, accepted for the realism gauge; rebuilt only when needed. |

## 13. Lots

| Lot | Content | Output |
|---|---|---|
| **0 — Pilot** (blocking) | Tap on Claude Desktop, muting and delayed playback; measuring R1, R2 and R3; a rough 2D mouth (the jaw follows the energy) to judge the sync. | A written go or no-go, the identifiers recorded. |
| **1 — Base** | `data/sources/visage/` in `macos-utils`: modules, `build.sh`, gate, `.gitignore`; `CONTRIBUTING.md` adapted; "Connect my AI" screen, menu bar, automatic reconnection. | The app connects and reconnects on its own. |
| **2 — Analysis** | § 6.1, file mode, tests on synthetic signals. | The analysis curves are right on the excerpts. |
| **3 — Rendering** | glTF loader, morphing, the hologram's eight layers, the window modes, sync to the display. | A hologram head at 60 frames a second. |
| **4 — Animation** | All of § 7. | Criteria 1 to 3. |
| **5 — Faces** | Blender chain, 10 presets, 10 `.glb`, choice grid, live change. | The 10 faces, tests green, R6 judged. |
| **6 — Finish** | Camera (gaze and parallax), complete settings, translation; robustness (sleep, change of audio output, AI app relaunched). | The six criteria of § 11.3 passed. |
| **7 — Release** | `data/doc/VISAGE.md` in English, with pictures made by the file mode; a row in the README table of `macos-utils`, and its requirements. | The gift is online. |
| Option | Phonemes in Core ML (V2); a phone as a remote screen (hologram pyramid); other apps. | — |

**Progress on 2026-11-27**:

- **Lot 0** done: the five measurements, with Claude Desktop; verdict go (pilot, § 5).
- **Lot 1** done: the app builds without Xcode, connects, reconnects (SwiftPM set aside, § 10.2).
- **Lot 2** done: the analysis, measured on three French voices (§ 6.1).
- **Lot 3** done: Metal, the hologram's layers, offline video rendering (`Visage --render`), the face live in
  its window.
- **Lot 4** done: mouth, prosody, rest (§ 7); never still for more than a second (criterion 3, tested).
- **Lot 5** done: Blender chain (Blender 5.3, MPFB 2.0.18, MakeHuman's CC0 packs), the 10 faces, choosing
  the face in the menu and the settings, sheet of the faces (`Visage --snapshot`) and silent videos
  (`--face <id> --mute`), depth pre-pass, tidied hair, thumbnail grid and fade on changing faces, realism
  gauge (§ 8.3); then the faces reworked: eyes, hair, teeth, features, soft brows and lashes, a relaxed face
  at rest; then dressed from the community's packs (skins, irises, hair). The blind test (R6) remains.
- **Lot 6** done but for the measurements of § 11.3: windows in front, two modes, welcome and settings in
  the charter with the animated logo and the preview, face size, back to the state left, false permission
  alert fixed; robustness (restart after sleep or when the capture freezes, a helper born after
  connecting), the hologram's layers and colour, the camera (gaze and parallax) and the conversation: the
  face listens while the AI app has its microphone open, thinks after a sentence or a dictation, and, with
  the microphone option, nods at the pauses. Claude Desktop's voice mode, tried on speakers: no echo (R1
  lifted for Claude).
- **Lot 7** under way: `data/doc/VISAGE.md` and the README, the release archive (`data/sources/release.sh visage`).
- **Claude Code** (2026-11-27): its plugin, its voice and its card (§ 4.4).
- **Siri** (2026-11-27): its card, shown from the settings, its voice passed through (§ 4.5).

## 14. Out of scope

- **iPhone and iPad on their own**: no app can capture and mute another's sound. Windows and Linux neither.
- **The browser mode** (Q5).
- **A voice or an AI of our own**: the official voice mode is not replaced. Claude Code, which has none,
  speaks with the Mac's own (§ 4.4).
- **Reading the conversation's text, any network connection**: Visage reads no text; Claude Code's voice
  reads only the sentence its hook hands it (§ 4.4).
- **A notarized DMG**: the download is an ad hoc signed, reproducible archive; notarizing would take a paid
  Apple Developer account. The source stays the reference.

## Sources

- [Claude — Use voice mode](https://support.claude.com/en/articles/11101966-use-voice-mode): plans,
  platforms (Desktop, web, mobile), beta, languages, limits.
- [MacRumors — Claude's voice mode moves to Opus and Sonnet](https://www.macrumors.com/2026/07/24/claude-voice-mode-opus-sonnet-model-support/)
- [OpenAI — ChatGPT for desktop, release notes](https://help.openai.com/en/articles/9703738-desktop-app-release-notes)
- [Neowin — ChatGPT Voice on the desktop apps](https://www.neowin.net/news/chatgpt-voice-experience-gets-a-massive-upgrade-on-desktop/)
- [MakeHuman — licence](https://static.makehumancommunity.org/about/license.html): CC0 assets, MPFB's code
  under GPL.
- [MPFB 2.0.16 — release notes](https://static.makehumancommunity.org/mpfb/releases/release_2016.html):
  the ARKit shapes of the faceunits01 pack.
- [MPFB on Blender's extensions platform](https://extensions.blender.org/add-ons/mpfb/)
- [CG Channel — MetaHuman usable in Unity or Godot (2025)](https://www.cgchannel.com/2025/06/you-can-now-sell-metahumans-or-use-them-in-unity-or-godot/)
- [Unreal Engine — EULA change log](https://www.unrealengine.com/eula-change-log/unreal)
- [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox): MIT licence, ARKit shapes,
  repository archived.

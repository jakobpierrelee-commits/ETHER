# Ether

A macOS system-wide audio equalizer. Routes your system audio through a lossless 10-band parametric EQ before it reaches your speakers.

Built for people who care about how their music, podcasts, and video calls actually sound — with the visual language of a pro EQ plugin and the ergonomics of a Mac utility.

---

## What it does

- **10-band parametric EQ** — Low Cut / Low Shelf / Bell / High Shelf / High Cut / Notch filter types. ±24 dB range, 0.1–20 Q.
- **32-bit float, 48 kHz, lossless path** — no downsampling, no bit-depth reduction.
- **Real-time visualization** — smooth curve with per-band colors, ghost spectrum, technical grid, peak meter, and hover info cards.
- **Character knobs** — one-turn macros for Bass, Warmth, Clarity, Presence, and Air. Knob arcs are color-linked to their EQ band handles — hover a knob and its bands glow on the canvas, and vice versa.
- **AI Suggest** — rule-based tonal analyzer that listens to what's playing and proposes gentle corrections with reasoning.
- **Reference Match** — load any audio file and Ether matches its tonal balance.
- **Dehiss** — simple downward expander + high-shelf cut above a configurable pivot. Ducks hiss when the high band goes quiet.
- **Spatial processing** — stereo width, bass mono, crossfeed, virtual speakers, polarity flip, mono check, reverb.
- **LUFS metering** — BS.1770 momentary, short-term, integrated, and true peak in the Advanced window.
- **6 color themes** — Clinical, Neon, Thermal, Mono, Ember, Arctic. Independent EQ curve color. All in Display P3.
- **Profiles** — save, load, rename, delete. A/B two slots and flip between them with `X`. Preset sidebar with inline save and hover-to-overwrite.
- **Mini player** — always-on-top floating panel with Spotify/Music album art, media controls (play/pause/next/prev), and an ethereal waveform visualization tinted by the album's dominant color.
- **Menu bar mode** — compact popover with the essentials. Main window can close; the app stays alive in the menu bar.
- **Global hotkeys** — ⌘⌥B bypass, ⌘⌥X A/B toggle. Work even when Ether isn't focused.
- **Auto device routing** — switches system output to BlackHole on Start, restores on Stop. Remembers your output device across restarts.
- **Launch at login** — optional, via `SMAppService`.

---

## Requirements

- **macOS 14** or later
- **[BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)** installed — Ether reads system audio from this virtual driver
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** to generate the Xcode project (`brew install xcodegen`)

---

## Install

### From DMG (recommended)

Download the latest `.dmg` from Releases. Open it, drag Ether to Applications. On first launch macOS will ask for microphone permission (to read from BlackHole — it's a virtual device, not your mic).

### Build from source

```bash
brew install blackhole-2ch xcodegen
git clone https://github.com/jakobpierrelee-commits/ETHER.git
cd ETHER
xcodegen generate
open Ether.xcodeproj
# Build & Run in Xcode
```

### Build a signed DMG

```bash
scripts/release.sh 1.2.0
# Requires: Developer ID cert in Keychain, notarytool credentials stored as "ether-notary"
```

---

## Usage

1. Click **Start** — Ether switches your system output to BlackHole and starts processing.
2. Pick your real output device from the **Output** dropdown.
3. Drag EQ handles to shape the curve, or use the **Character knobs** for quick tonal sculpting.
4. Save presets in the left sidebar. Click **+** to create, hover to overwrite, right-click to delete.
5. Open the **Mini Player** (PiP icon in the header) for a floating always-on-top widget with album art and media controls.
6. Click **Stop** — system output is restored, processing ends.

### Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Start / Stop |
| `⌘ B` | Bypass all bands |
| `⌘ 0` | Reset to flat |
| `⌘ Z` / `⇧⌘Z` | Undo / Redo |
| `X` | Toggle A/B profile slots |
| Drag handle | Freq + Gain |
| `⇧` + drag | Axis lock + snap to ISO 1/3-octave |
| `⌘` / `⌥` + drag | Fine adjustment (5× precision) |
| Scroll on handle | Adjust Q |
| Double-click handle | Reset that band |
| Right-click handle | Filter type / bypass / reset |
| Click canvas background | Deselect band |
| `?` | Shortcut cheatsheet |

---

## Architecture

```
System Audio  →  BlackHole (virtual device)
                  ↓
                 HAL IOProc  →  FloatRingBuffer  →  AVAudioSourceNode
                                                     ↓
                                               StereoProcessor (inline DSP)
                                                     ↓
                                               AVAudioUnitEQ (10-band)
                                                     ↓
                                               AVAudioUnitReverb
                                                     ↓
                                               mainMixerNode (master gain)
                                                     ↓
                                               Physical Output (speakers)
```

- **Capture** uses raw Core Audio HAL (`AudioDeviceCreateIOProcID`).
- **Stereo DSP** runs inline in the render callback — width, bass mono, crossfeed, polarity, dehiss. No allocations on the audio thread.
- **Playback** is a single AVAudioEngine graph.
- **Spectrum** is vDSP 4096-point FFT at 30fps.
- **Mini player** is a programmatic `NSPanel` — truly borderless, no SwiftUI Window scene.
- **Media integration** uses `osascript` (AppleScript via Process) for Spotify/Music track info and `MediaRemote.framework` for transport commands.

---

## Attribution

Audio capture powered by **[BlackHole](https://github.com/ExistentialAudio/BlackHole)** by Existential Audio (MIT).

UI inspired by FabFilter Pro-Q, iZotope Ozone, Slate Infinity EQ, and Astro Mono.

Font: [Space Mono](https://fonts.google.com/specimen/Space+Mono) by Colophon Foundry (OFL).

---

## License

MIT. Do what you want with it.

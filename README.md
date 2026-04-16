# Ether

A macOS system-wide audio equalizer. Routes your system audio through a lossless 10-band parametric EQ before it reaches your speakers.

Built for people who care about how their music, podcasts, and video calls actually sound — with the visual language of a pro EQ plugin and the ergonomics of a Mac utility.

<img width="820" alt="Ether main window" src="docs/screenshot.png" />

---

## What it does

- **10-band parametric EQ** — Low Cut / Low Shelf / Bell / High Shelf / High Cut / Notch filter types. ±24 dB range, 0.1–20 Q.
- **32-bit float, 48 kHz, lossless path** — no downsampling, no bit-depth reduction.
- **Real-time visualization** — smooth Ozone-style curve with per-band colors, ghost input spectrum, pre/post toggle, dedicated peak meter, and a draggable info card on hover.
- **Character knobs** — one-turn macros for Bass, Warmth, Clarity, Presence, and Air when you don't want to think in bands.
- **AI Suggest** — rule-based tonal analyzer that listens to what's playing and proposes gentle corrections with reasoning.
- **Profiles** — save, load, rename, delete. A/B two slots and flip between them with `X`.
- **Menu bar mode** — compact popover with the essentials. Main window can close; the app stays alive in the menu bar.
- **Auto device routing** — switches system output to BlackHole on Start, restores it on Stop (even on crash or force-quit).
- **Launch at login** — optional, via `SMAppService`.

---

## Requirements

- **macOS 14** or later (uses the `onContinuousHover` API)
- **Xcode 15+** to build
- **[BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)** installed — Ether reads system audio from this virtual driver
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** to generate the Xcode project (`brew install xcodegen`)

---

## Install & build

```bash
# Install the audio driver (required)
brew install blackhole-2ch

# Build Ether
brew install xcodegen
git clone https://github.com/jakobpierrelee-commits/ether.eq.git
cd ether.eq
xcodegen generate
open Ether.xcodeproj
# Build & Run in Xcode, or:
xcodebuild -scheme Ether -configuration Release build
```

On first launch, macOS will ask for microphone permission (to read from BlackHole — it's a virtual input device, not your mic). Grant it.

---

## Usage

1. Click **Start** — Ether switches your system output to BlackHole and starts processing.
2. Pick your real output device (speakers/headphones) from the **Output** dropdown at the top.
3. Drag EQ handles to shape the curve, or use the **Character knobs** for quick tonal sculpting.
4. **Save As** to name and store a profile. Load it later from the dropdown on the bottom-left.
5. Click **Stop** — system output is restored, processing ends.

### Keyboard shortcuts (press `?` in-app for the full list)

| Key | Action |
|---|---|
| `Space` | Start / Stop |
| `⌘ B` | Bypass all bands |
| `⌘ 0` | Reset to flat |
| `⌘ Z` / `⇧⌘Z` | Undo / Redo (every drag is atomic) |
| `X` | Toggle A/B profile slots |
| Drag handle | Freq + Gain |
| `⇧` + drag | Axis lock + snap to ISO 1/3-octave |
| `⌘` / `⌥` + drag | Fine adjustment (5× precision) |
| Scroll on handle | Adjust Q |
| Double-click handle | Reset that band |
| Right-click handle | Filter type / bypass / reset |
| `?` | Show this cheatsheet |

### AI Suggest

Let audio play for ~5 seconds, then click ✨ **AI Suggest** in the EQ header. A rule-based analyzer checks the averaged spectrum against a target tonal balance and proposes up to six small corrections (sub-bass bloat, muddy lower-mids, presence dip, harshness, dull top, etc.) with plain-language reasoning. Preview curve is shown in dashed cyan. Apply or dismiss. Fully undoable.

---

## Architecture

```
System Audio  →  BlackHole (virtual device)
                  ↓
                 HAL IOProc  ─→  FloatRingBuffer  ─→  AVAudioSourceNode
                                                       ↓
                                                 AVAudioUnitEQ (10-band)
                                                       ↓
                                                 mainMixerNode (master gain)
                                                       ↓
                                                 Physical Output (your speakers)
```

- **Capture** uses raw Core Audio HAL (`AudioDeviceCreateIOProcID`) instead of AVAudioEngine's input node. Lower latency than the AVAudioEngine input path.
- **Playback** is a single AVAudioEngine: `AVAudioSourceNode` pulls from the ring buffer, feeds the EQ node, through the mixer, out to the device.
- **Spectrum** is vDSP 4096-point FFT running on a background queue at 30fps.
- **Scrolling spectrogram history** lives in a ring grid fed by the same analyzer.

See `Sources/Audio/` for the engine code.

---

## Attribution

Audio capture is powered by **[BlackHole](https://github.com/ExistentialAudio/BlackHole)** by Existential Audio (MIT). Ether would not be possible without it.

UI inspired by FabFilter Pro-Q, iZotope Ozone/Neutron, and Slate Infinity EQ.

---

## License

MIT. Do what you want with it.

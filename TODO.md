# Ether — Unfinished / Next Session

## Uncommitted Work
- All changes from the v1.1.0 session are built and bundled but **not committed to git**
- Commit everything and push to https://github.com/jakobpierrelee-commits/ether.eq

## Features to Build
- **Preset folders with drag-and-drop** — user requested, deferred. Needs folder model in ProfileStore, nested sidebar UI, SwiftUI onDrag/onDrop
- **Font swap** — tokenized system is ready (`EtherType.fontFamily` in DesignSystem.swift). User wants to try Astro Mono and Proto Mono. Drop TTFs in `Assets/Fonts/`, change one line
- **Factory presets** — ship default presets (Lofi, House, Rock, Mastering, etc.) like Infinity EQ sidebar

## Known Issues / Polish
- **Mini player window chrome** — borderless styling works but macOS may still show a faint border on some displays. May need `NSPanel` subclass for true chrome-free floating
- **Apple Music album art** — Spotify art works (URL fetch). Music.app uses raw AppleScript data extraction which may be flaky; needs testing
- **Mini player resize handle** — `.resizable` styleMask is set but the grab area for resizing a borderless window can be hard to find
- **Reverb preset picker** in SpatialView — replaced with styled Menu but may still show native dropdown chrome
- **Output device dropdown** — uses `.menuStyle(.borderlessButton)` which suppresses the extra chevron, but the dropdown list itself is still native macOS styling
- **Noise texture performance** — 1px procedural grain renders per-pixel in Canvas. Fine on M-series but could be slow on older Macs. Consider pre-rendering to a cached image

## Ideas Discussed but Not Started
- **Sparkle auto-update** — wire up Sparkle framework for in-app updates via GitHub Releases
- **Per-app audio profiles** — auto-switch EQ based on which app is playing audio
- **Linear-phase EQ mode** — mentioned in the Advanced "Coming Soon" footer
- **Profile export/import** — share presets as files
- **Spectral dehiss (advanced)** — FFT overlap-add noise reduction with noise profile learning. Current dehiss is the "simple" version

# Life Editor

[![Source checks](https://github.com/3nboyd/life-editor/actions/workflows/ci.yml/badge.svg)](https://github.com/3nboyd/life-editor/actions/workflows/ci.yml)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-33383d)
![Swift 6](https://img.shields.io/badge/Swift-6-e57546)
[![MIT](https://img.shields.io/badge/license-MIT-8bb8b0)](LICENSE)

An open-source Mac video editor for music performances, class projects and everyday
videos. A large viewer, layered timeline and direct editing keep the work in view.

**Local editing and rendering. No account, subscription, upload or watermark.**

[Build and try it](#build-and-try-it) · [What's working](#whats-working) · [Progress](docs/PROGRESS.md) · [Roadmap](docs/ROADMAP.md) · [Contribute](CONTRIBUTING.md)

## What's working

| Edit | Make it yours | Work with music |
|---|---|---|
| Layer video, audio, images and titles | Original filters and transitions | Waveforms, beat grids and markers |
| Trim, split, move and arrange clips | Styled text, backgrounds, shapes and drawings | Volume fades, EQ and loudness tools |
| Scrub and step through frames | Crop, transform and use safe guides | Synchronize and switch camera angles |
| Undo edits and recover projects | Import/export SRT captions | Keep a continuous master audio track |

Multicam editing includes four camera previews, reviewed waveform/timecode
alignment, optional clock-drift correction, and video/audio switching decisions.
Drag cut boundaries in the timeline or refine them numerically.

Projects save as `.lifeedit` packages. Reference your originals or collect media
into a portable project. Preview and export use the same compositor; exports use
full-quality media and a fixed snapshot of your edit.

Export video as H.264, HEVC or ProRes, or audio as WAV, AIFF or M4A. Choose the whole
sequence or a range. See the [tested formats](docs/FORMATS.md) for import coverage.

## Build and try it

Requires **macOS 15+, Apple Silicon, and a Swift 6 toolchain with a macOS SDK**.

```sh
git clone https://github.com/3nboyd/life-editor.git
cd life-editor
scripts/build-app.sh
open 'dist/Life Editor.app'
```

Source builds do not require distribution signing credentials. For additional
format support, see the [pinned media-helper build](docs/FFMPEG.md).

### Make a first edit

1. Import footage or music with the import button or **⌘I**.
2. Arrange clips in the timeline; drag an edge to trim or press **⌘B** to split.
3. Add a title, choose a look, or drag the audio fade handles.
4. Save with **⌘S**, then use the export button to render your video.

Normal edits preserve gaps. Same-track collisions do not silently overwrite
material, and committed edits support undo.

## Development

**Pre-1.0, in active development.** Everyday editing, multicam and creator tools
are already implemented, with broader workflow and usability validation underway.
Loops, reverse, speed ramps, advanced color and parts of the creative toolkit
remain on the roadmap.

[Current progress](docs/PROGRESS.md) separates working features from remaining
work. [Verification](docs/VERIFICATION.md) records actual test results and their
limits. [Phase 3](docs/PHASE3.md) lays out the creator-toolkit delivery plan.

To build, test or contribute, start with [Contributing](CONTRIBUTING.md).
Original project code is MIT licensed; dependencies have
[separate notices](docs/DEPENDENCIES.md).

## Useful shortcuts

| Action | Shortcut |
|---|---|
| Import / Open / Save | ⌘I / ⌘O / ⌘S |
| Play/pause / frame step | Space / ← → |
| Split / delete | ⌘B / Delete |
| Duplicate / ripple delete | ⌘D / ⇧Delete |
| Marker / snapping | M / N |
| Bypass snap during drag | Option |
| Cancel a cut drag | Escape |
| Viewer focus | ⇧⌘F |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Visible multicam angles | 1–4 |

[Architecture](docs/ARCHITECTURE.md) · [Project status](docs/STATUS.md) · [Full roadmap](docs/ROADMAP.md)

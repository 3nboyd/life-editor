# Life Editor

A native, local Mac video editor in active development. Swift 6, macOS 15+,
Apple Silicon. MIT licensed original code. No account, subscription, upload or
watermark. Pre-1.0 development; see the [roadmap](docs/ROADMAP.md) for planned work.

## Build

```sh
scripts/build-app.sh
open 'dist/Life Editor.app'
```

A Swift 6 toolchain/macOS SDK is required. Source builds use ad-hoc signing and do
not need distribution credentials. Optional broad-format helpers are built from
verified LGPL source, never taken from Homebrew:

```sh
scripts/build-ffmpeg.sh
scripts/build-app.sh
```

When present, the complete helper tree (matching source, licenses, configuration,
inventory) is bundled. See [FFmpeg build and provenance](docs/FFMPEG.md).

## Current editing paths

### Editing

- Layered video/audio/still import, playback, scrubbing and frame stepping.
- Move/trim/split/duplicate/delete/ripple-delete with source/overlap protection.
- Multi-selection, linked/group moves, clipboard and editable vector drawings/shapes.
- Marker notes, ranges, and colors; markers can follow their original source frames when clips are trimmed or their speed changes.
- Crop, position, scale, rotation, flips and non-exported safe-area guides.
- Cached per-channel waveforms with exact source-rate sample detail when zoomed in.
- Autosave after editing pauses, recent projects, project duplication, and confirmation before reverting.

### Titles and effects

- Fourteen transitions that stay within the available footage, with duration handles on the timeline.
- Direct volume/opacity points, shared fades, curves, constant speed and pitch lock.
- Editable multiline titles, six entrances, colors/backgrounds/outlines and viewer handles.
- Shared color wheel, RGB/HEX, swatches and viewer sampling.
- Sixteen original visual looks, sixteen adjustments and real media thumbnails.

### Audio and multicam

- Musical grids with swing/anchors, tap tempo, background onset/tempo analysis.
- Gain/pan/channel mapping/EQ, optional limiter and calibrated loudness measurement.
- Multicam groups with four lightweight camera previews, suggested audio-waveform alignment, and manual timing offsets.
- Continuous master audio by default; switch video, audio, or both, replace cuts within a selected range, and preview camera choices.

### Export and project recovery

- SRT import/export and timed captions; portable collected packages and recovery.
- H.264/HEVC/ProRes/WAV/AIFF/M4A export, ranges, progress and cancellation.

Every export consumes a snapshot and the same compositor as preview. Rational
project times retain sample/frame precision. Normal moves preserve gaps; a
same-track collision is rejected instead of silently overwriting material.

This list describes implemented paths, **not completion of all acceptance gates**.
Full music-performance, social-video and student-project workflows still require
completion and validation. See [status](docs/STATUS.md), [verification](docs/VERIFICATION.md)
and the [complete requirement register](docs/ROADMAP.md).

## Tests

```sh
scripts/test.sh
LIFE_RUN_MEDIA_INTEGRATION=1 scripts/test.sh
```

Native tests generate synthetic media and check decoded preview/export frames,
retiming sample count/pitch/fades, camera cuts, creative effects, actual codecs,
selected ranges and cancellation safety. The UI render check exercises1280×800;
it does not substitute for hands-on usability or accessibility testing.

## Shortcuts

| Action | Shortcut |
|---|---|
| Import / Open / Save | ⌘I / ⌘O / ⌘S |
| Save As | ⇧⌘S |
| Play/pause / frame step | Space / ← → |
| Split / delete | ⌘B / Delete |
| Duplicate / ripple delete | ⌘D / ⇧Delete |
| Marker / snapping | M / N |
| Bypass snap during drag | Option |
| Viewer focus | ⇧⌘F |
| Undo / redo | ⌘Z / ⇧⌘Z |
| Visible multicam angles | 1–4 |

[Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) ·
[Dependencies](docs/DEPENDENCIES.md) · [Formats](docs/FORMATS.md)

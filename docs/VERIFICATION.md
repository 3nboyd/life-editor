# Verification

Host: macOS 15.6, Apple M4, 16 GB; Swift 6.2.3 CLT compiler/SDK.
This is not an M1 benchmark. No usability or performance target is claimed met.

## Latest run: Phase 3 text styling, 2026-10-27

Full local native/helper verification passes: **240 tests across 11 suites in
28.645 seconds**, with `LIFE_RUN_MEDIA_INTEGRATION=1` and the pinned local helpers.
The optimized ad-hoc app build passes.

New checks cover title-background validation, schema 1–5 migration to schema 6,
future-version protection, exact legacy bitmap rendering when the new optional
style is absent, preserved font names, independent typography/background choices,
grouped undo and package round-trip. Pixel checks distinguish real fill, border,
shadow and stable glyph/body geometry through typewriter reveals.

Native rounded, pill and speech-bubble projects save/reopen and match decoded
ProRes frames at multiple animation times. Expanded background/shadow controls fit
an approximately 248-point inspector with editable numeric values. Native view
renders are validation artifacts, not public product screenshots.

The Phase 3 plan retains typography, overlays/animation, advanced color, captions
and the combined creative workflow. This slice does not close the phase gate or
establish the M1 performance/usability targets.

## Previous run: Phase 2 refinement, 2026-10-27

Full local native/helper verification passes: **233 tests across 10 suites in
17.510 seconds** on this M4, with the pinned helpers and
`LIFE_RUN_MEDIA_INTEGRATION=1`. The optimized ad-hoc app build passes.

Eight focused cut-refinement tests cover video/audio pointer gestures, immutable
ghosts, snapping/Option, Escape, selected-cut Delete safety, exact undo/redo,
chronological refinement of valid unsorted persisted arrays, affected locks,
missing source intervals, unchanged missing tails, stale proposals and pending
placement. Named accessibility targets and a native decision-lane bitmap are
checked; this does not replace the full VoiceOver/usability audit.

A connected fixture generates four 20-second cameras with distinct audio and known
0/0.2/0.4/0.6-second starts plus a separate master. Three matches exceed 60%
confidence; one approximately 52% match remains visibly flagged and receives an
explicit manual offset review. No confidence threshold is weakened. The test
records camera hotkeys as one undoable pass, drags a cut through real AppKit event
handlers, saves/reopens, and compares preview against decoded ProRes frames. Its
four-second master windows retain all 384,000 interleaved stereo samples unchanged;
WAV output agrees within 16-bit quantization tolerance. The focused workflow also
passed three separate process runs before the full suite.

Fixture setup uses the established callback export bridge because the SDK async
AVAssetExportSession bridge crashed on this toolchain/runtime. A subsequent native
reader-startup crash was not reproduced after initializing AppKit before creating
the fixture window. No production export change was made without an established
cause. The repeated focused runs and full native run pass; broader long-running
stress coverage remains a release requirement.

## Previous run: 2026-10-25

The full local native/helper suite passes: **224 tests across 10 suites in
31.629 seconds**, with `LIFE_RUN_MEDIA_INTEGRATION=1` and the pinned local helpers.
The optimized app build and ad-hoc signing verification pass.

The clock-correction fixture uses four-minute camera recordings and a separate
master. It measures actual waveform anchors, compares early/late visual markers,
proves an offset-only control remains wrong late in the recording, and verifies
Preview/Cancel, save/reopen, ProRes/WAV range output and unchanged source hashes.
The compared two-second master windows contain exactly 192,000 interleaved stereo
samples before and after correction, with maximum difference zero. Exported PCM
is checked within 16-bit quantization tolerance. Additional native cases cover
adjacent and gapped fragments at 1.0001× and 1.000237×.

These fixtures reproduced an AVFoundation range-read stall with a valid rational
camera start. Canonical native endpoint mapping fixes that case while preserving
the exact document. Tests also check shared boundaries, sample precision and
long-timeline half-tick rounding. This does not establish the complete VFR/codec
matrix or the full Phase 2 workflow gate.

Grouped volume/opacity point edits retain exact undo, spacing and persistence and
match decoded preview/export output. Native UI render checks remain validation
evidence; public product screenshots require genuine running-app capture.

## Earlier foundation evidence

After filesystem/host access was expanded, native media services worked. Earlier
sandbox VideoToolbox failures are historical and are no longer the current test
boundary. Real native integration now verifies:

- Two composited layers: decoded preview/export pixel agreement.
- One-second pitch-preserving half-speed audio: 48,000 decoded samples, pitch near
 440 Hz, onset within 10 ms, fade progression.
- Title-only, still-image, audio-only and multicam camera-cut output.
- All 16 look and 16 adjustment graphs produce actual thumbnails; deterministic VHS
 seed/frame; filtered export matches thumbnail; transforms and styled text render.
- H.264, HEVC, ProRes, WAV, AIFF and M4A actual stream codecs; 48 kHz stereo; resized and
 selected-range output; monotonic progress; cancelled export preserves destination.
- Rational timing, grouped undo, malformed data safety, collected transfer,
 checkpoint rotation, SRT and effect/style/transform persistence.
- Tempo/sync synthetic arrays: known tempo/offset and silence handling.

Latest combined native/helper run: **118 tests pass**, including 1280 × 800 native
hosting render, all 14 transitions with unchanged project timing and decoded
preview/export agreement, drawing/shape rendering, grouped selection commands,
source markers/tempo anchors, conversion cancellation and source protection.
Audio DSP tests verify gain/pan/channel mapping/three EQ bands, explicit limiter
ceiling/no latency/sample count, positive automation headroom and preview/export
samples within 0.0001. Stereo integrated loudness agrees with pinned FFmpeg ebur128
within 0.15 LU on a gated fixture. Sample peaks are not true-peak measurements.

Four 1280 × 720 muted proxy AVPlayers decoded 25 frames each in 1.114 s including startup,
with 7.25 µs position spread on this M4 run. This synthetic foundation test does not
establish full main-viewer 30 fps, M1 or long-timeline targets. CPU/RSS vary with
parallel tests and media services run outside the app process.

Native interactive automation remains unavailable (its Node runtime fails to
initialize); pointer/VoiceOver/manual usability scenarios remain open. A screenshot
alone does not close a phase gate.

FFmpeg/ffprobe 9.0.2 built from official signed source, with GPL/nonfree/autodetect/
network disabled and only file/pipe protocols. Build verification checks dynamic
linkage, licenses/config and compiled inventory. WAV→AAC and PPM→ProRes fixtures
pass; HTTPS is rejected. This is not full format-matrix coverage.

Reader/writer processing replaced AVAssetExportSession after native tests exposed
retimed audio truncation and an SDK async export callback crash. Pitch processing
now uses a replaceable offline intermediate shared with playback/export.

Packaging now verifies both helpers, pinned source hash/signature record and required
license/source materials before bundling. A missing NOTICE fixture correctly
blocks verification; post-signing inventory hashes are regenerated.

The clean optimized app build and ad-hoc signature verification pass. App builds
use a separate scratch directory to avoid mixed compiler artifacts. Armed range
replacement is tested through app commands, persistence and exact grouped undo/redo;
synchronized playback checks player readiness before using host-clock scheduling.


Additional verified slices: real AppKit point/line/fade mouse interactions and exact
one-gesture undo; source marker arithmetic overflow rejection; checked marker
anchor mapping; independent time/frame/beat grids; shared color conversion,
swatches, compact layout and viewer pixel orientation; six entrance animations,
deterministic seeks and animation clock preservation. One combined native project
contains two video layers, an animated title, volume fade and pitch-preserving
retime, then real editing/undo, atomic save/reopen and decoded export comparison.

Debounced autosave writes the latest edit and refuses a newer unsupported format.
An injected slow checkpoint proves serialization and cancellation of stale queued
work. The first hosted CI run exposed older-SDK Core Image Sendable annotations;
an immutable kernel wrapper addresses that compiler compatibility issue. Hosted
CI completion is tracked separately from local checks.


Hosted macOS VM native-media runs compiled and began tests but stalled in media
work (including a missing AppleM2ScalerParavirtDriver diagnostic). No hosted native
pass is claimed. Default CI runs portable/source/UI checks and builds the app;
workflow dispatch can explicitly enable hardware media integration. Full native
integration, including helpers, remains required locally on supported hardware
before release. CI uploads logs and UI render artifacts even on failure.


Native waveform fixtures now verify per-channel polarity, 44.1/48 kHz source-rate
retention, exact sample windows, pyramid aggregation/checksums, corruption rebuild,
file-change invalidation, cancellation and symlink-safe cache cleanup. Limits are
eight channels and 262,144 frames per detail window; timeline reads 65,536-frame
chunks with at most two overview and two detail jobs.

Independent multicam audio/video/both decisions and stable legacy cut IDs pass
persistence/undo tests. Known-tone native fixtures prove default continuous master,
separate video/audio decisions, unchanged unrelated music, exact physical audio
switch boundaries, live audition/restore and selected-range end restoration.
Preview/export PCM agrees within one 16-bit LSB. App command tests cover mode masks,
unavailable audio and one-action range undo. NTSC transport retains a rational
clock; 3,000 forward/backward steps are exact, and full-width quantization handles
valid long prime-denominator times without intermediate overflow.

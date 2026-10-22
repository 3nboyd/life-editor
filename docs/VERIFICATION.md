# Verification — 2026-10-21

Host: macOS15.6, Apple M4,16GB; Swift6.2.3 CLT compiler/SDK.
This is not an M1 benchmark. No usability or performance target is claimed met.

After filesystem/host access was expanded, native media services worked. Earlier
sandbox VideoToolbox failures are historical and are no longer the current test
boundary. Real native integration now verifies:

- Two composited layers: decoded preview/export pixel agreement.
- One-second pitch-preserving half-speed audio:48000 decoded samples, pitch near
 440Hz, onset within10ms, fade progression.
- Title-only, still-image, audio-only and multicam camera-cut output.
- All16 look and16 adjustment graphs produce actual thumbnails; deterministic VHS
 seed/frame; filtered export matches thumbnail; transforms and styled text render.
- H.264, HEVC, ProRes, WAV, AIFF and M4A actual stream codecs;48k stereo; resized and
 selected-range output; monotonic progress; cancelled export preserves destination.
- Rational timing, grouped undo, malformed data safety, collected transfer,
 checkpoint rotation, SRT and effect/style/transform persistence.
- Tempo/sync synthetic arrays: known tempo/offset and silence handling.

Latest combined native/helper run: **118 tests pass**, including1280×800 native
hosting render, all14 transitions with unchanged project timing and decoded
preview/export agreement, drawing/shape rendering, grouped selection commands,
source markers/tempo anchors, conversion cancellation and source protection.
Audio DSP tests verify gain/pan/channel mapping/three EQ bands, explicit limiter
ceiling/no latency/sample count, positive automation headroom and preview/export
samples within0.0001. Stereo integrated loudness agrees with pinned FFmpeg ebur128
within0.15LU on a gated fixture. Sample peaks are not true-peak measurements.

Four1280×720 muted proxy AVPlayers decoded25frames each in1.114s including startup,
with7.25µs position spread on this M4 run. This synthetic foundation test does not
establish full main-viewer30fps, M1 or long-timeline targets. CPU/RSS vary with
parallel tests and media services run outside the app process.

Native interactive automation remains unavailable (its Node runtime fails to
initialize); pointer/VoiceOver/manual usability scenarios remain open. A screenshot
alone does not close a phase gate.

FFmpeg/ffprobe9.0.2 built from official signed source, with GPL/nonfree/autodetect/
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


Native waveform fixtures now verify per-channel polarity, 44.1/48kHz source-rate
retention, exact sample windows, pyramid aggregation/checksums, corruption rebuild,
file-change invalidation, cancellation and symlink-safe cache cleanup. Limits are
eight channels and262144 frames per detail window; timeline reads65536-frame
chunks with at most two overview and two detail jobs.

Independent multicam audio/video/both decisions and stable legacy cut IDs pass
persistence/undo tests. Known-tone native fixtures prove default continuous master,
separate video/audio decisions, unchanged unrelated music, exact physical audio
switch boundaries, live audition/restore and selected-range end restoration.
Preview/export PCM agrees within one16-bitLSB. App command tests cover mode masks,
unavailable audio and one-action range undo. NTSC transport retains a rational
clock;3000 forward/backward steps are exact, and full-width quantization handles
valid long prime-denominator times without intermediate overflow.

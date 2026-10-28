# Requirement register

Status: **planned** unless marked otherwise. A model field or a control alone does
not complete a feature. Completion requires UI, persistence, undo, preview,
export and relevant verification. This register retains the owner's full scope.

Latest completed slices: **Phase 3 title backgrounds, alignment/spacing and
reusable layouts, installed fonts/weights and image/emoji stickers; track solo,
workspace and clipboard safety fixes**. The
[Phase 3 delivery plan](PHASE3.md) continues the creator toolkit. Phase 2 remains
open for its music and retiming work. See the
[progress assessment](PROGRESS.md) for implemented slices, remaining work and the
qualified overall completion estimate. Open broad checkboxes include partial work.

## Phase 0: foundation gate

- [x] Native Swift 6/macOS 15/Apple Silicon app, modular document/commands/timeline/media/renderer/audio/analysis/export boundaries.
- [x] Real import → layered edit → save/reopen → export vertical slice.
- [x] Two composited video layers, animated title, volume fade, pitch-preserving retiming, matching export.
- [x] Sample-level audio placement; four synchronized proxy previews.
- [x] Codec fixtures, frame/audio comparisons, baseline performance measurements.

Technical gate verified with the combined native media workflow and M4 baseline.
This does not establish M1 targets or musician/student usability; those remain
explicit release-quality gates.

## Phase 1: everyday editing

- [ ] Dominant viewer (initial 2:1 height), collapsible contextual panel/full-width timeline; remembered resizable layout; 1280×800 validation; focus shortcut.
- [ ] Quiet charcoal UI, SF Symbols/custom edit icons, visual preset thumbnails; no explanatory panel prose; tooltips/shortcuts/accessibility names/focus/large targets; non-color states; Reduce Motion gear.
- [ ] Arbitrary video/audio/image/text/shape/drawing/caption/adjustment tracks; upper-layer composite/audio mix; rename/reorder/resize/hide/lock/mute/solo.
- [ ] Linked AV move/trim, detach/relink, selection/groups/duplicate/copy/paste/split/delete/ripple delete/insert/overwrite.
- [ ] Normal/ripple/roll/slip trims, source limits, preview placement before commit, explicit overlap/overwrite; preserve gaps and other tracks by default.
- [ ] Timeline zoom/track heights/trackpad/fit/frame stepping; source boundary frame trim preview.
- [ ] Snap boundaries/playhead/markers/grid with screen threshold and explicit target priority, guide/label, N magnet/Option bypass; independent time/frame/beat grid, continuous vertical lines.
- [ ] Point/range timeline and source-anchored clip markers, notes/colors/navigation; source mapping through trim/retime; optional conversion to visible titles.
- [ ] One volume envelope shared by level/edge fades/points; dB/silence; opacity and other properties share linear/eased/hold evaluator; next/previous/copy/paste/multi-point.
- [ ] Cached multiresolution per-channel waveforms/thumbnails/proxies, sample audio placement, frame-aligned video.
- [ ] Gain/pan/mute/solo/channel routing/meters/peak/loudness/optional normalize/EQ/limiter, visible clipping, no silent export processing.
- [ ] Constant 0.25–4× speed, linked/independent AV, pitch lock/varispeed, temporary playback rate separate; duration/waveform/marker/envelope remapping.
- [ ] Boundary Loop (audio crossfade)/Stretch/Freeze explicit actions; reverse/freeze/speed ramps and expensive editable intermediate caches (Phase 2 completion).
- [ ] New/open/recent/close/save/save-as/duplicate/revert, undo/redo/cut/copy/paste/select-all/import/relink/collect/export/settings.
- [ ] Versioned package JSON/resources/optional collected media/recovery; rational time and frame rates; stable IDs; unknown effect/font/media preservation.
- [ ] Persistent local bookmarks, explicit relink, relative collected media, Save As reference preservation; atomic save/migrations/newer-version protection/autosave/rotating recovery.
- [ ] Bounded cache (10 GB configurable), visible usage/cleanup, originals and required intermediates protected.
- [ ] SDR Rec.709 linear premultiplied render plan shared preview/export, Core Text layout/seeded effects/color transforms, HDR-input tone map/metadata retention.
- [ ] Reader/writer full-original export, shared audio DSP, cancellation/stale seek cancellation/bounded decode; immutable snapshot; temporary destination/progress/cancel/size/errors.
- [ ] Export aspect presets 16:9/9:16/1:1/4:5; 720p/1080p/4K; source/common rational rates; H264/AAC/HEVC/ProRes/WAV/AIFF/M4A; sequence/range.
- [ ] First-video dimensions/rate default; audio-only 1080p30; 48k floating audio.
- [ ] Native stream/codec/timestamp/orientation/channels/color probe; VFR source mapping and CFR intermediates.
- [ ] Pinned LGPL FFmpeg/ffprobe fallback, argument arrays/local protocols/resource bounds/cancel; matching source/config/notices/inventory; generated shipped capability matrix.
- [ ] Tested containers MP4/MOV/M4V/MKV/WebM/AVI/MPEG/TS/MXF; video H264/HEVC/ProRes/DNx/VP8/VP9/AV1 per decoder; audio WAV/AIFF/MP3/AAC/FLAC/ALAC/Vorbis/Opus; PNG/JPEG/HEIC/TIFF/GIF. Explicit RAW/DRM unsupported.

Gate: short video with music, cuts, fades and overlays reopens and reproduces export.

## Phase 2: music and multicam

- [ ] Accelerate onset/tempo detection/confidence, cancellable background work.
- [ ] Manual BPM/tap/downbeat/signature, edit beats/offset/half-double/subdivisions/triplets/swing, tempo changes/live drift anchors; moving grid distinct from stretching audio.
- [ ] Musical snapping for clips/markers/automation/transitions; optional monitor-only metronome.
- [ ] Multicam creation, waveform/timecode/manual sync, confidence/manual correction; drift detection and previewed correction.
- [ ] Numbered synchronized proxy angles beside final viewer; persistent master audio; video/audio/both modes.
- [ ] Arm/play/1–9/click record at displayed frame; disarmed audition; paused armed write; ignore repeat/no-op; editable original-source events.
- [ ] Selected-range replacement and whole-pass undo, individual refinement; missing segments/mixed fps/start offsets; unavailable-angle state; >9 paging.
- [ ] Four 720p proxy preview gate; main 30fps target; speed ramps/reverse/loop crossfade and audio precision completion.

Gate: four cameras + separate audio, switching pass/refinement/export with continuous master audio.

## Phase 3: creator toolkit

- [ ] Effects browser Transitions/Filters/Adjust and contextual audio; live thumbnails/drag/intensity-duration/favorites/bypass/reset/copy-paste; stable registry/defaults/animation/render bindings.
- [ ] Boundary transitions with source handles/visible duration limits/explicit freeze: dissolve, black/white fade, dip color, push/slide/wipe, zoom/blur, whip/shake, glitch/RGB, flash/light leak. No silent timing changes.
- [ ] Original strength-controlled grayscale/high-contrast, LA/desert/clean/vivid/portrait/cool/cinematic/golden-hour/faded-film/Y2K/VHS/disposable/neon/pastel presets; deterministic grain/flicker.
- [x] Camcorder date/time overlay format/position/visibility; explicit review of valid content-creation metadata or user input, never silent today.
- [ ] Exposure/brightness/contrast/highlights/shadows/whites/blacks/saturation/vibrance/temperature/tint/hue/local tone/glow/sharpen/clarity/denoise/vignette/grain/WB eyedropper; advanced RGB curves/levels/HSL.
- [x] Timed adjustment layers affect lower visual tracks.
- [ ] Plain/bold/condensed/serif/handwritten/outline/neon/typewriter text; solid/translucent/square/rounded/pill/bubble backgrounds; all typography/padding/border/shadow/opacity/alignment controls.
- [ ] Fade/slide/pop/scale/bounce/typewriter/word-highlight; titles/lower-thirds/labels/lyrics/captions; emoji/imported stickers; editable rectangles/rounded/circle/line/arrow.
- [ ] Viewer select/transform/crop handles, double-click text, contextual alignment; keyboard drag alternatives; timed/keyframed text/shapes/stickers/drawings.
- [ ] Pen/highlighter/eraser/width/opacity/editable normalized strokes.
- [ ] Shared hue/SV/RGB/HEX/alpha/color-space/eyedropper/recent/saved color popover.
- [ ] Free/ratio crop/rotate/flip/straighten/fit-fill/animated reframing and non-exported social safe guides.
- [ ] Manual captions/SRT import-export/burn-in/social styles/word timing; optional Apple Speech on-device capability/language checks, no network fallback.

Gate: every creative feature previews, saves, undoes and exports correctly.

## Phase 4: release

- [ ] VoiceOver/full keyboard/Reduce Motion/accessibility and 1280×800 audit.
- [ ] New-user musician/student usability sessions before claiming intuitive UI.
- [ ] Timing fixtures mixed fps/30000÷1001/60000÷1001/VFR/hour duration; exact edit/undo tests.
- [ ] Audio sample/envelope/loop/pitch/clipping/routing and beat known/ambiguous/silent/drifting tests.
- [ ] Sync offsets/confidence/display-time/master continuity, decoded preview-export frame/audio comparisons.
- [ ] Save-as/collection/transfer/migration/crash/missing media-font-effects tests; corrupt/cancel/disconnect/full-disk/export failure preservation tests.
- [ ] M1 16GB actual measurements: 1080p30 ordinary work, four 720p angles, <100ms feedback; background responsiveness, adaptive quality indicator, bounded caches/long projects/heavy effects.
- [ ] Contribution/architecture/format/dependency docs, CI, redistributable demo media, signed/notarized GitHub release when credentials available; unsigned source builds independent.
- [ ] Demonstrated music-performance multicam, styled social video, student/personal workflows.

Future separate projects: Windows/Linux/iPad, HDR export, external plugin API, live capture (outside initial scope). No speculative platform abstraction, cloud account, subscription, watermark or mandatory AI/network.

# Status

Version: pre-1.0 development. The Phase 0 technical foundation workflow is
verified on the local M4; later phase gates remain open. The full scope is retained
in ROADMAP.md; source publication is not a claim of release readiness.

## Implemented and integrated

Native shell and resizable/collapsible viewer/timeline/panels; real local media;
undoable move/trim/split/duplicate/delete/ripple-delete; source/overlap/lock safety;
volume/fade/opacity; constant pitch-locked/varispeed retiming; markers; musical
grids/tap/onset analysis; original look thumbnails/strength/adjustments; normalized
viewer transforms/crop; multiline titles/colors/background/outline; SRT captions;
portable collection/relative references, bookmarks/relink and recovery selection;
multicam groups/cuts/audition with persistent master; reader/writer exports with
six formats/ranges/progress/cancel/atomic replacement.

Direct timeline automation supports points, level/fade handles, linear/eased/hold
curves, numeric navigation and exact gesture undo. Point/visible-point copy and
paste preserve rational spacing, effective levels and curves across clip base
levels; collision merges and atomic range/lane validation undo as one edit. Marker controls include notes,
colors, ranges and source anchoring. A shared hue/SV/RGB/HEX/alpha popover supplies
recent/saved swatches and viewer sampling. Six deterministic title entrances
preserve animation clocks through trimming/splitting/retiming. Standard commands
include recent/duplicate/revert and debounced autosave, with serialized recovery.

Native integration verifies real frames and samples. Tests include exact 1-second
retimed audio at 48 kHz, pitch/onset/fades, rendered preset/transform/title output,
multicam red→blue cuts, codecs/channels, collection transfer and cancellation.

## Required work before 1.0

- Broader drift-correction coverage and complete music/retiming workflows.
- Broader linked/group splice coverage, complete track controls,
  full keyframe copy/paste/multi-point editing and animation of other parameters.
- Loops/crossfades/reverse and speed ramps; broader freeze integration.
- Advanced color controls; complete social text animation
  and animated reframing. Local transcription
  has capability/privacy guards and source-time mapping but needs real speech QA.
- Comprehensive metadata/VFR/HDR handling and broad tested codec/container matrix.
- Complete native document integration and migration paths; disconnected/full-disk
  failure fixtures.
- Full VoiceOver/keyboard/hit-target audit, musician/student usability testing,
  M1 performance measurements, adaptive quality and all three owner workflows.

New integrated foundations include four synchronized proxy previews, waveform
sync candidates with confidence/manual offsets, proxy/cache controls, pinned LGPL
helper conversion, multi-selection/groups/clipboard, vector shapes/drawing, all 14
transition graphs with source-handle-safe boundary objects, and shared audio DSP
with gain/pan/channel mapping/EQ/optional limiter, sample meters and calibrated
stereo BS.1770 integrated loudness. These do not close complete phase gates.

Other limits: rational timing bounded to 24 h/representable values; constant speed
uses six decimals; four live angles per page. Missing effects/fonts persist with
inspector warnings; broader missing-resource workflows still need QA. Peaks are sample peaks, not true peaks. Limiter
is per clip; summed tracks may still clip. No Developer ID/notary identity is
available, so development builds remain ad-hoc signed.


Latest integrated additions: native-rate multiresolution per-channel waveforms,
exact visible sample windows, separate video/audio/both switching with live audition,
range replacement in either decision lane, stable cut IDs and numeric cut refinement.
Forward/backward NTSC stepping now preserves an exact rational transport clock.
Insert/overwrite and ripple trim now produce an explicit candidate timeline before
Apply; undo restores the exact original document. Unsupported multicam splices and
ambiguous cross-track relationships are rejected. Real filmstrips use bounded
thumbnail jobs, and per-track heights persist locally with keyboard/VoiceOver controls.
Native timecode reading validates 32/64-bit tracks, rational clocks, drop-frame flags
and day rollover. Waveform/timecode alignment uses reviewed candidates with a visible
reference and rejects stale results. Oriented still images
retain their display geometry while thumbnails decode at bounded size. Waveforms
remain available in memory if the disposable disk cache cannot be written.

An explicit source-boundary Freeze action creates a silent, detached clip referencing
the last valid source frame. Native tests compare its preview/export color to ordinary
playback, verify silence, and exercise VFR timing, persistence, undo and cancellation.
Freeze does not yet support speed/slip/roll or multicam source extensions.

Source-aware crop ratios, Fit/Fill and undoable straightening now use the same
persisted transform in preview and export, including oriented still images. Schema 1
through 7 projects migrate to schema 8; unknown future project/recovery data is protected.
Schema boundaries prevent older readers from silently omitting adjustment-layer or
new tonal-control, explicit camcorder-date or text-background rendering.

Live stereo Mix sample-peak meters now decode bounded windows from the current
playback mix in the background, with clipping, seek/mix invalidation and visible-only
updates. They measure the project mix before device/system volume. Eight original
text families have actual rendered thumbnails and one-step undo. Clip-marker
alignment reviews a single recording at a time without moving other angles; its
source impulse matches preview and export after save/reopen.

Timed adjustment layers now process the picture beneath them through the shared
renderer, with opacity automation, actual thumbnails, bypass/reset, effect-setting
copy/paste and exact undo. Native tests cover layer order, timing, seeded effect
clocks, save/reopen and decoded preview/export comparisons.

Blocking export, audio measurement, live-meter, retime, DSP and freeze-frame native
reads now run on dedicated
I/O queues. Export admission bounds active/pending jobs; cancellation waits for native
operations to unwind before cleanup. A 12-request native export stress test verifies
concurrent completion and cancellation preserving an existing destination.

Whites, Black Point and Brilliance now use original linear-light tonal operators
with neutral defaults, strength, bypass, reset, clipboard settings and shared
preview/export rendering. Brilliance combines local contrast and tonal recovery;
it does not reproduce Apple Photos processing.

The VHS camcorder date overlay accepts explicit timezone-qualified dates or a
reviewed local content-creation metadata candidate. Date/time/both, four corners
and visibility persist with the effect; source clocks follow retiming and hold
through freezes. Preview, thumbnails and export share Core Text rendering. No
current-date or filesystem-date fallback is used. Display-only clocks avoid
overflow without changing rational editing or media timing. Adjustment-layer
animated effect clocks use the same checked rendering path; regression fixtures
include large prime-denominator source starts and high rational frame rates.

Automation clipboard is bounded to 10,000 points/1 MB. It copies stored visible
knots without adding implicit guards. Shift-click and Select Visible build point
groups for time/level moves, curve changes, copy and delete as one undoable edit.
Group moves preserve spacing and reject collisions or out-of-range results atomically.
Volume group level changes below the graph's −60 dB floor require individual edits;
individual numeric controls retain quieter levels and silence. Animation beyond
volume/opacity remains open.
Camcorder formats are fixed ISO date/24-hour time, with an explicit fixed UTC offset.

Waveform synchronization now offers opt-in clock correction with early/middle/late
source/master anchors, confidence and uncertainty. Preview leaves the project
unchanged; Apply is one undoable edit. The persistent master, camera cuts and
original files remain unchanged. Manual offset review remains available after
correction. Native integration checks early/late frame alignment, exact master
samples, save/reopen and decoded range exports.

Automatic clock correction currently requires at least three minutes of shared
audio, reliable local matches separated by at least two minutes, and a consistent
clock within approximately ±1%. The initial offset search is ±120 seconds. It
accepts dedicated, unretimed camera tracks referenced to the group's master;
negative preroll, reused tracks, external links, transitions and artistic slips
require manual preparation. Ambiguous recordings remain manually alignable.

Multicam mode now adds compact video/audio decision lanes above the media tracks.
Boundary drags show a candidate without changing the document; release commits one
undoable edit. Frame snapping, Option bypass, Escape cancellation and named
accessibility targets accompany the existing numeric keyboard controls. Cuts stay
between chronological neighbors; the opening decision stays at zero. Playback,
armed switching, pending placement, stale projects, affected locks and newly
unavailable source intervals reject edits. Existing unrelated camera gaps remain
editable. Delete affects the selected decision rather than previously selected media.

A four-camera native fixture checks waveform alignment with explicit review of a
lower-confidence result, an armed hotkey pass, timeline pointer refinement,
save/reopen, decoded ProRes frames and continuous master PCM/WAV export. The full
Phase 2 feature gate remains open; loops/crossfades, reverse, speed ramps and the
remaining musical tools are still required. See PROGRESS.md for the qualified
overall estimate.

Phase 3 now includes shared title-background styling: none, square, rounded, pill
and speech bubble; fill/alpha, padding, corner radius, background border and shadow.
Actual visual choices use the same Core Text renderer as preview/export. Typography
presets preserve the background, and typewriter reveals retain stable full-text
bounds. Controls are disclosed and support numeric editing and grouped slider undo.
Schema 6 preserves exact legacy rendering when the new optional styling is absent.
Older readers refuse these projects instead of silently omitting visible styling.
Text now supports left/center/right alignment and canvas-point letter/line spacing,
with stable typewriter layout, grouped undo and shared preview/export rendering.
Schema 7 preserves nil legacy typography and protects new styling from older readers.
Four reusable layouts (Title, Lower Third, Label and Lyrics) change only size and
position, preserving words, appearance, timing and animation.
The complete creator toolkit remains in the [Phase 3 plan](PHASE3.md) and
[requirement register](ROADMAP.md).

Local full native/helper verification: 261 tests across 14 suites pass (2026-10-28). Optimized ad-hoc app build passes. These measurements are from the local
M4 and do not establish the M1 performance targets.

The October 27 [requirements audit](AUDIT-2026-10-27.md) records UI and safety
fixes. Timeline collapse is now remembered, multicam previews sit beside the output,
and malformed clip clipboard data is rejected atomically. The
[first public preview](PUBLIC-PREVIEW.md) targets November 1, separately from 1.0.

Audio and video tracks now expose additive audio solo in both the inspector and
timeline header, including empty tracks. Mute overrides solo; hidden video keeps
its audio. Solo does not hide pictures. State persists in schema 8 and is undoable.

Installed font families and native faces/weights now have a searchable compact
picker. PostScript names persist; unavailable names remain until explicitly
replaced. Emoji and imported-image stickers are timed title/image objects with
existing transform, trim and opacity controls. Image alpha, collection, undo and
shared preview/export are verified; no new schema or bundled fonts are needed.

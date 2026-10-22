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
curves, numeric navigation and exact gesture undo. Marker controls include notes,
colors, ranges and source anchoring. A shared hue/SV/RGB/HEX/alpha popover supplies
recent/saved swatches and viewer sampling. Six deterministic title entrances
preserve animation clocks through trimming/splitting/retiming. Standard commands
include recent/duplicate/revert and debounced autosave, with serialized recovery.

Native integration verifies real frames and samples. Tests include exact 1-second
retimed audio at 48 kHz, pitch/onset/fades, rendered preset/transform/title output,
multicam red→blue cuts, codecs/channels, collection transfer and cancellation.

## Required work before 1.0

- Complete timecode synchronization, drift correction preview and richer direct
  cut refinement.
- Broader linked/group splice coverage, complete track controls,
  full keyframe copy/paste/multi-point editing and animation of other parameters.
- Loops/crossfades/reverse/freeze and speed ramps.
- Adjustment layers and advanced color controls; complete social text animation,
  stickers/shared color tools and crop ratios/straightening. Local transcription
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
uses six decimals; four live angles per page; missing effects/fonts persist but
need visible missing-resource UX. Peaks are sample peaks, not true peaks. Limiter
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
and day rollover; synchronization UI integration is in progress. Oriented still images
retain their display geometry while thumbnails decode at bounded size. Waveforms
remain available in memory if the disposable disk cache cannot be written.

Local full native/helper verification:134 tests pass, plus the targeted cache-storage
failure test. Optimized ad-hoc app build passes. These measurements are from the local
M4 and do not establish the M1 performance targets.

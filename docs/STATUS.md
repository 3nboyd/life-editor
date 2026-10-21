# Status

Version: pre-1.0 development. No complete phase gate is closed. The full scope is
retained in ROADMAP.md; publication of source is not a claim of release readiness.

## Implemented and integrated

Native shell and resizable/collapsible viewer/timeline/panels; real local media;
undoable move/trim/split/duplicate/delete/ripple-delete; source/overlap/lock safety;
volume/fade/opacity; constant pitch-locked/varispeed retiming; markers; musical
grids/tap/onset analysis; original look thumbnails/strength/adjustments; normalized
viewer transforms/crop; multiline titles/colors/background/outline; SRT captions;
portable collection/relative references, bookmarks/relink and recovery selection;
multicam groups/cuts/audition with persistent master; reader/writer exports with
six formats/ranges/progress/cancel/atomic replacement.

Native integration verifies real frames and samples. Tests include exact1-second
retimed audio at48k, pitch/onset/fades, rendered preset/transform/title output,
multicam red→blue cuts, codecs/channels, collection transfer and cancellation.

## Required work before 1.0

- Complete manual/timecode/waveform-sync workflow, drift correction preview,
  selected-range re-recording, video/audio switching modes and editable cut UI.
- Insert/overwrite, contextual roll/slip/ripple trims, complete track controls,
  source-anchored marker UX and full keyframe editing/navigation.
- Audio normalization UI, loops/crossfades/reverse/freeze and speed ramps.
- Adjustment layers and advanced color controls; complete social text animation,
  stickers/shared color tools and crop ratios/straightening. Local transcription
  has capability/privacy guards and source-time mapping but needs real speech QA.
- Comprehensive metadata/VFR/HDR handling and broad tested codec/container matrix.
- Complete standard document lifecycle/autosave/revert/recent/duplicate and recovery
  failure UX; disconnected/full-disk failure fixtures.
- Full VoiceOver/keyboard/hit-target audit, musician/student usability testing,
  M1 performance measurements, adaptive quality and all three owner workflows.

New integrated foundations include four synchronized proxy previews, waveform
sync candidates with confidence/manual offsets, proxy/cache controls, pinned LGPL
helper conversion, multi-selection/groups/clipboard, vector shapes/drawing, all14
transition graphs with source-handle-safe boundary objects, and shared audio DSP
with gain/pan/channel mapping/EQ/optional limiter, sample meters and calibrated
stereo BS.1770 integrated loudness. These do not close complete phase gates.

Other limits: rational timing bounded to24h/representable values; constant speed
uses six decimals; four live angles per page; missing effects/fonts persist but
need visible missing-resource UX. Peaks are sample peaks, not true peaks. Limiter
is per clip; summed tracks may still clip. No Developer ID/notary identity is
available, so development builds remain ad-hoc signed.

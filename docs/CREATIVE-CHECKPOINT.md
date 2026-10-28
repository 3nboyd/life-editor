# Creative controls checkpoint

Color, editable drawing and styled captions now work together in a collected
portrait project that reopens and reproduces its export.

## Implemented

- RGB/master curves with five fixed input positions, draggable output points,
  numeric entry and keyboard/VoiceOver adjustment. Interpolation is piecewise linear.
- Black/white/gamma levels and selective hue, saturation and lightness for six bands.
  Neutral defaults, strength, bypass, reset and effect-setting copy/paste share the
  renderer, including timed adjustment layers.
- Stroke selection, direct point dragging, numeric coordinates, pen/highlighter
  changes, color/opacity/width, duplicate/delete and whole-stroke erasing. Geometry
  stays normalized; transformed brush previews match saved outlines. Erasing uses
  actual canvas pixels and sweeps between pointer samples.
- Plain, Box, Pill and Lyric caption styles, plus one-action track matching that
  preserves cue words, times, effects, entrance animation and envelopes. Actual
  rendered choices use the same text renderer as preview/export.
- Exact first-edit undo for a fresh project, fixing an initial document-ID mismatch
  between the workspace and command system.

New processing is protected by schema 9. Schemas 1–8 migrate without losing prior
editing state. The new advanced controls are static; general parameter animation
remains a separate roadmap requirement.

## Connected evidence

The styled-social fixture fills a portrait canvas, edits all three color families,
styles imported SRT cues, matches their track, creates and edits a highlighter
stroke, collects media, removes its disposable import copy, reopens and exports.
Decoded frames agree with preview, and pixel checks verify actual overlays.

The [rendered example and reproducible project](gallery/README.md#creative-checkpoint)
come from this fixture. It creates a 720 × 1280 ProRes movie and an editable
`.lifeedit` package. The image is a decoded export frame, not an application screenshot.

Full native/helper validation: **277 tests across 15 suites**, sequential outer
execution, 51.220 seconds on the local M4. The high-resolution example separately
passes in 2.145 seconds. Optimized app build and bundled-helper checks pass.
Independent review found and verified fixes for eraser aspect-ratio and swept-path
errors; a separate broad-phase check covered 20,000 randomized segment pairs.

## Remaining gates

This checkpoint does not close Phase 3 or 1.0. White-balance sampling, complete
word highlighting, general keyframes, animated reframing, remaining effect-browser
work and real on-device speech QA remain. Phase 2's loops/crossfades, reverse,
speed ramps and metronome also remain. Manual app/VoiceOver/usability checks,
M1 measurements and the full release failure matrix stay open in the
[public-preview plan](PUBLIC-PREVIEW.md) and [requirement register](ROADMAP.md).

# Phase 3: creator toolkit

The goal is a complete styled social-video workflow: arrange media, create titles
and captions, add overlays and color, then save and export the same composition.
The [requirement register](ROADMAP.md) retains the full scope. Phase 2's unfinished
music and retiming work remains tracked separately; starting this phase does not
close those requirements.

## Delivery order

| Slice | Scope | Acceptance evidence |
|---|---|---|
| 1. Shared text styling — implemented | None, square, rounded, pill and speech-bubble backgrounds; solid/translucent fill through shared color/alpha; padding, corner radius, background border and shadow. Keep typography separate from background styling. | Actual visual choices, direct preview, one-gesture undo, legacy-project preservation, save/reopen, multiline/typewriter stability and decoded export agreement. |
| 2. Typography and reusable presets — in progress | Complete plain/bold/condensed/serif/handwritten/outline/neon/typewriter families; font/weight/size, alignment, line/letter spacing; titles, lower thirds, labels and lyrics. Finish fade/slide/pop/scale/bounce/typewriter/word-highlight behavior. | Original preset thumbnails, editable settings, preserved missing-font names, timing/trim/retime tests, identical Core Text layout in preview/export. |
| 3. Timed overlays and animation | Emoji and imported image stickers; finish editable shapes and pen/highlighter/eraser/strokes. Extend shared linear/eased/hold keyframes to transforms, crop, text/drawing properties and other required parameters. Add animated reframing. | Viewer selection/handles, keyboard alternatives, contextual guides, normalized drawing geometry, timeline timing/keyframes, undo and portable project/export checks. |
| 4. Effects and advanced color | Finish visual browse/drag/favorites/intensity/duration/bypass/reset/clipboard paths. Complete white-balance sampling, RGB curves, levels and HSL alongside the existing original looks, transitions and timed adjustment layers. | Shared effect definitions and seeded rendering; source-handle-safe transitions; clip/layer order; actual thumbnails; neutral defaults and representative decoded frame comparisons. |
| 5. Captions and social delivery | Finish manual/SRT timing and styling, optional burn-in, social safe guides and word highlighting where explicit word timing exists. Complete optional Apple Speech device/language availability and required on-device processing. | Manual/SRT workflows remain independent of transcription; no inferred word timings presented as measured; SRT round-trip, local speech QA where available, save/undo and styled landscape/portrait exports. |
| 6. Combined creative workflow | Assemble a representative styled social video using the completed tools. | Every required creative feature has working UI, persistence, undo, preview/export and relevant tests. Remaining accessibility, musician/student usability and M1 performance gates stay visible in Phase 4. |

Alignment, letter/line spacing and four size/position recipes (Title, Lower Third,
Label and Lyrics) are now integrated with shared Core Text layout, document
protection and undo. Installed font families and native face/weight selection now
preserve PostScript names, including unavailable fonts until explicit replacement.
Timed emoji and imported-image stickers use existing title/image objects, shared
rendering and editable transforms. Word highlighting, general keyframes and the
remaining animation/color work stay open. The [rendered gallery](gallery/README.md) demonstrates
exported landscape and portrait projects; it does not close the combined workflow gate.

## Rules for every slice

- Keep the large viewer, full-width layered timeline, charcoal surfaces, useful
  icons and short labels. Disclose advanced controls in compact popovers.
- Edit through undoable commands. Media services consume immutable snapshots.
- Use the same renderer, parameter evaluation, text layout and color transforms
  for preview, thumbnails and export.
- Preserve existing documents. Introduce a schema boundary when older apps would
  otherwise silently omit new visible styling.
- Ship original presets/assets and retain local editing/rendering. No cloud
  services, mandatory AI or substantial dependency/licensing changes.
- Publish only implemented behavior. Do not add placeholder controls or substitute
  product screenshots to represent unfinished work.

Each slice is delivered in reviewable commits. The current overall estimate
remains in [PROGRESS.md](PROGRESS.md); completing one slice does not complete Phase 3.

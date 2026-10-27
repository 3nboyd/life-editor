# Progress toward 1.0

Updated: 2026-10-27. Overall planning estimate: **about 60%** of the full owner
scope, with a rough **55–65% range**. This is an engineering estimate of integrated
behavior and remaining work, not a percentage of checked boxes, lines of code or
passing tests. It is not a release-readiness score.

The [requirement register](ROADMAP.md) remains authoritative. Its broad checkboxes
stay open until every part of the requirement and its acceptance evidence exists.

| Milestone | Evidence and current state | Remaining work |
|---|---|---|
| Phase 0: risky foundations | Technical gate verified locally: real layered edit, save/reopen, shared-render export, sample placement and four proxy previews. | M1 performance measurements belong to the release gate. |
| Phase 1: everyday editing | Most everyday paths implemented: layered editing, guarded placement, rational timing, waveforms/proxies, automation, project recovery and six export formats. | Complete track/document commands, broader linked editing and failure coverage, animation beyond volume/opacity, full VFR/HDR/format matrix. |
| Phase 2: music and multicam | Beat/manual grids, waveform/timecode/marker sync, reviewed clock correction, persistent master, armed switching, range replacement and numeric cut refinement are integrated. | Direct cut refinement is the current slice. Loops/crossfades, reverse, speed ramps, metronome and the combined four-camera performance workflow remain. |
| Phase 3: creator toolkit | Original filters/transitions, adjustment layers, tonal controls, text families/entrances, shapes/drawing, color picker and SRT workflows are integrated. | Advanced color, full typography/background/sticker/word-highlight toolkit, general keyframes, animated reframing and real on-device speech QA. |
| Phase 4: release quality | CI, optimized source builds, helper licensing, native integration tests and representative UI captures are in place. | Full accessibility/keyboard audit, musician/student usability, M1 profiling/adaptive quality, failure matrix and all three demonstrated owner workflows. |

## Current delivery pass

Continue Phase 2 rather than declaring it complete or skipping its gaps. Preserve
the dominant viewer and quiet interface throughout.

- [ ] Direct video/audio multicam cut strips and boundary dragging.
- [ ] Preview before committing; frame snapping, Option bypass and cancellation.
- [ ] Exact one-action undo; source/lock/order/stale-document validation.
- [ ] Keyboard/accessibility alternatives and native pointer-event coverage.
- [ ] Saved refined cuts reproduce preview/export with uninterrupted master audio.

The full Phase 2 gate still requires the four-camera workflow and the remaining
music/retiming features. Completing this pass alone does not close that gate.

Latest published baseline before this pass: 224 tests across 10 suites in the full
local native/helper run, optimized ad-hoc app build and hosted source/build CI
passing. See [verification](VERIFICATION.md) for dates and practical limits.

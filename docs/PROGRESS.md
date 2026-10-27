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
| Phase 2: music and multicam | Beat/manual grids, waveform/timecode/marker sync, reviewed clock correction, persistent master, armed switching, range replacement and direct cut refinement are integrated, with a connected four-camera native fixture. | Loops/crossfades, reverse, speed ramps, metronome and broader real-footage/performance workflow validation. |
| Phase 3: creator toolkit | Original filters/transitions, adjustment layers, tonal controls, text families/entrances, shared background geometry/borders/shadows, shapes/drawing, color picker and SRT workflows are integrated. | Advanced color, full typography/background/sticker/word-highlight toolkit, general keyframes, animated reframing and real on-device speech QA. |
| Phase 4: release quality | CI, optimized source builds, helper licensing, native integration tests and UI render checks are in place. | Full accessibility/keyboard audit, musician/student usability, M1 profiling/adaptive quality, failure matrix and all three demonstrated owner workflows. |

## Current phase: creator toolkit

Phase 3 continues at the owner's request, with its [delivery plan](PHASE3.md).
Phase 2's remaining work stays in the requirement register.

The first slice is integrated: shared title backgrounds, padding, border and
shadow controls, actual rendered visual choices, independent typography presets,
legacy-project preservation, grouped undo and native preview/export comparisons.
The next slices complete typography/presets, timed overlays and shared animation,
advanced color/effects workflows, then captions and social delivery.

## Previous delivery pass: direct cut refinement

This Phase 2 slice is integrated. The dominant viewer and quiet interface remain
requirements for every subsequent slice.

- [x] Direct video/audio multicam cut strips and boundary dragging.
- [x] Preview before committing; frame snapping, Option bypass and cancellation.
- [x] Exact one-action undo; source/lock/order/stale-document validation.
- [x] Keyboard/accessibility alternatives and native pointer-event coverage.
- [x] Saved refined cuts reproduce preview/export with uninterrupted master audio.

The full Phase 2 gate still requires the remaining music/retiming features and
broader four-camera performance validation. The synthetic workflow fixture alone
does not close that gate.

Next Phase 2 priorities: explicit audio looping with adjustable crossfades, reverse
and speed ramps, remaining musical-grid controls/metronome, and broader workflow
and performance coverage. Earlier incomplete requirements remain in the register.

Latest local verification: 240 tests across 11 suites in the full native/helper
run and the optimized ad-hoc app build pass. Hosted CI is checked separately after
publishing. See [verification](VERIFICATION.md) for dates and practical limits.

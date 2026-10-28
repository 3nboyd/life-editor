# Contributing

Build and test with `scripts/build-app.sh` and `scripts/test.sh` on macOS 15+.
Read AGENTS.md and .relay/ROUTING.md. Keep changes scoped and preserve user edits.

Work in vertical slices: document persistence, command/undo, actual UI interaction,
preview, export and meaningful tests must agree before checking a feature complete.
Add fixture provenance and redistribution licenses. Generated synthetic fixtures
are preferred for deterministic media tests. Do not commit private recordings.

Keep the picture large, timeline clear and controls quiet. Use accessible icons,
tooltips and keyboard access. No section descriptions, fake visual thumbnails,
nonfunctional buttons, implicit ripple/overwrite or silent media processing.

Public product screenshots must capture the running native app. Demo media may be
fictional, but do not reconstruct the UI or replace the video layer after capture.
Keep validation renders separate from product screenshots. If genuine capture is
unavailable, leave screenshots out rather than publish substitutes.

No cloud services, mandatory AI, proprietary assets or substantial dependency
license changes without the owner's approval. Do not commit credentials/signing
identities. Ad-hoc builds are development builds. Distribution signing and
notarization require the owner's credentials and release authorization.

For the full hardware-media suite, run on a supported Mac with the pinned helpers:

```sh
LIFE_RUN_MEDIA_INTEGRATION=1 LIFE_HELPER_DIRECTORY="$PWD/.local-helpers" \
scripts/test.sh --no-parallel
```

Sequential outer execution avoids running every hardware-codec fixture at once.
The dedicated export/cancellation stress tests still run concurrent jobs internally.
Ordinary source checks can continue to use `scripts/test.sh`.

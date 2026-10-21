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

No cloud services, mandatory AI, proprietary assets or substantial dependency
license changes without the owner's approval. Do not commit credentials/signing
identities. Ad-hoc builds are development builds. Distribution signing and
notarization require the owner's credentials and release authorization.

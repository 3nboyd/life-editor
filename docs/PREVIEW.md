# Life Editor preview

This is an early development preview for macOS 15 or later on Apple Silicon.
The complete editor is still being built. Keep a separate copy of important
projects and original media when trying a preview.

## Try it

The development app is ad-hoc signed and is not notarized. macOS may refuse to
open a downloaded copy. This package does not include a security-bypass script.
A source build is available at https://github.com/3nboyd/life-editor and does not
require distribution signing credentials. Signed, notarized distribution will
be added when the owner's Apple signing credentials are available.

Start with a short project: import media, arrange and trim clips, add a title or
music fade, save, reopen, then export. Edits and rendering remain local. There is
no account, upload, subscription or watermark.

## Included and unfinished

Layered editing, waveform/automation tools, original effects, styled titles,
SRT captions, multicam switching and video/audio exports are implemented. The
repository's progress and tested-format documents record the verified coverage.

Loops/crossfades, reverse, speed ramps, advanced color, general keyframes and
parts of the creator toolkit remain unfinished. M1 performance, complete
accessibility, musician/student usability and the full failure matrix have not
passed their release gates. Projects currently use schema 7; older builds may
refuse them. Preserve a copy before opening a project in a newer preview.

See BUILD.json for the exact commit, signing status and helper inclusion.
The SHA-256 file alongside the archive verifies download integrity. Original
code is MIT licensed; bundled media helpers carry separate notices and matching
source inside the application resources.

Report reproducible problems at https://github.com/3nboyd/life-editor/issues with
your macOS version, preview version, steps and error text. Do not post private
media or projects without checking their contents.

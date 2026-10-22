# Dependency inventory

Original project sources: MIT, see ../LICENSE.

No Swift package dependencies are downloaded. Optional bundled FFmpeg helpers
are built from pinned verified LGPL source; see FFMPEG.md. Swift/SwiftUI,
AppKit, AVFoundation, Core Media, Core Image, Core Text, Accelerate and Metal are
Apple platform/toolchain components under their respective platform licenses.

FFmpeg/ffprobe 9.0.2 may be bundled from .local-helpers with matching source,
configuration, licenses and generated inventory. The build excludes GPL/nonfree
components, disables autodetection/network, and links only platform libraries.
The application never discovers arbitrary system FFmpeg from PATH.
Do not add Homebrew binaries to a release. The optional media integration test may
use a locally installed FFmpeg only to generate disposable solid-color fixtures.

[FFmpeg licensing reference](https://www.ffmpeg.org/legal.html).
No proprietary LUTs, vendor graphics, fonts, media or copied presets are included.

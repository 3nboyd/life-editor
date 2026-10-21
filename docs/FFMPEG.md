# Local format helpers

Life Editor's native source build does not require FFmpeg. Optional bundled helpers provide additional local probing/conversion capabilities. They are separate executables, not linked into the app.

The build pins **FFmpeg 9.0.2**, the latest stable release listed on the [official download page](https://ffmpeg.org/download.html) when checked on 2026-10-21. The [official source archive](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz) is verified against its detached PGP signature using the published release signing fingerprint `FCF986EA15E6E293A5644F10B4322F04D67658D8`. The authenticated source SHA256 is pinned as `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`; it was computed after signature verification and is not represented as an independently published checksum.

```sh
# Requires macOS 15+, Apple Silicon, Xcode command line tools, GnuPG and Python 3.
scripts/build-ffmpeg.sh
scripts/verify-ffmpeg.sh
```

The output directory is `.local-helpers/` (override `LIFE_HELPER_OUTPUT`). Build working files use `.ffmpeg-build/` (override `LIFE_FFMPEG_WORK`). `LIFE_BUILD_JOBS` defaults to four to bound compilation concurrency. Nothing from a Homebrew FFmpeg installation is copied.

The configuration explicitly disables GPL, nonfree, version-3-only components, external dependency autodetection, networking, capture devices and ffplay. Only `file` and `pipe` protocols are compiled. Built-in LGPL-compatible codecs and Apple's system VideoToolbox/AudioToolbox integration remain available. No external codec library is enabled. The executable programs use LGPL FFmpeg code; their LGPL notices and matching source must accompany redistribution. Life Editor's MIT license covers its original code and does not replace these licenses.

Distribute the entire `.local-helpers/` output alongside the binaries, including:

- `ffmpeg`, `ffprobe` and `NOTICE.txt`.
- `licenses/` containing upstream license notices.
- `source/` containing the exact upstream source archive, detached signature, public key, signature verification log, source checksum, generated build configuration and matching build script.
- `inventory/` containing configuration, license, linkage, protocols, program/library versions and machine-readable `capabilities.json`.

`verify-ffmpeg.sh` rejects GPL/nonfree configuration, network protocols and non-system dynamic-library dependencies. It generates capability inventory from the actual built programs. Inventory entries report compiled capabilities, not an assertion that every container/codec combination has passed fixture testing. Native and converted import fixtures must be tested separately; proprietary RAW, DRM and unsupported combinations remain explicit failures. In particular this build has no external AV1 decoder, and codec coverage varies with its built-in decoder implementations.

Application callers must still use argument arrays, file/pipe protocol whitelists, bounded processes and cancellation. Compile-time protocol restriction does not make malformed media trusted. Conversion intermediates belong in managed media storage and must never replace originals. No helper invokes an upload service.

To rebuild a changed configuration, use a fresh `LIFE_FFMPEG_WORK` directory. The script preserves a configured working tree for incremental rebuilds; release review should inspect the generated configuration and inventory. Signing/notarization of these executable helpers is part of the app release process.

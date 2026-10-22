# Tested format status

Imports probe actual streams. Native AVFoundation decoding is preferred; bundled
pinned FFmpeg/ffprobe 9.0.2 can prepare unsupported combinations as ProRes/PCM
intermediates. Originals and required intermediates are retained separately from
replaceable proxy caches. See [FFmpeg build details](FFMPEG.md) for source, configuration and licenses.
Source-only builds work without helpers, with native decoding available.

## Verified fixtures

| Path | Actual tested result |
| --- | --- |
| Native video | Generated H.264 MOV/MP4, HEVC and ProRes output decode correctly |
| Native images | PNG/PPM fixture composition, timed still export |
| Native audio | PCM WAV inputs, 48 kHz stereo mix, mono source mapping |
| Helper conversion | FFV1/MKV import to native editing intermediate, thumbnail and export |
| Helper codecs | WAV to AAC/M4A, PPM to ProRes/MOV |
| Video export | H.264/AAC MP4, HEVC MP4, ProRes MOV; selected range and resized output |
| Audio export | WAV PCM, AIFF PCM and AAC M4A |

Each integration run generates its own redistributable synthetic fixtures. Tests
inspect decoded samples, frame pixels, duration and actual output stream codecs.
Compiled helper inventory is generated from the exact build and is **not** a claim
that all listed codec/container combinations have passed editing/export tests.

The full requested import matrix, mixed-rate/VFR timestamp mapping, camera
metadata, HDR tone mapping, long recordings and corrupt/disconnected-drive cases
still need broader fixtures. DRM and proprietary camera RAW are unsupported.
HDR export is outside initial scope. No universal format support is claimed.

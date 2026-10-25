# Workspace captures

These PNGs capture Life Editor's actual SwiftUI/AppKit workspace at 1440 × 900:

- `workspace.png`: viewer, transport, layered timeline and markers.
- `effects.png`: visual filter browser and viewer transform handles.
- `audio.png`: audio controls and the shared volume envelope.

The rehearsal still is fictional imagery generated with OpenAI image generation
for this demonstration. It is not footage of a real performance. The synthetic
stereo soundtrack is generated locally by the capture harness. No personal media
is included.

AVPlayer's hardware video layer does not appear in AppKit bitmap captures. The
harness places a frame rendered by the real project compositor over that layer
for capture only. It does not draw substitute controls, waveforms or timelines.
These images demonstrate the current interface, not completion of all roadmap
features or proof of playback performance.

Reproduce on macOS with a Swift 6 toolchain:

```sh
LIFE_CAPTURE_DOCUMENTATION=1 scripts/test.sh --filter captureDocumentationWorkspace
```

The opt-in harness is in `Tests/LifeEditorTests/DocumentationCaptureTests.swift`.
It uses `fixtures/rehearsal.png` and temporary audio, without modifying user projects.

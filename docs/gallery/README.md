# Rendered project examples

The README gallery shows frames decoded from Life Editor's ProRes exports at
0.75 seconds. The landscape project uses the LA look, the Lower Third
placement preset, a fading title and a rounded title background. The portrait
project uses fill cropping, the Clean look, a fading multiline title and a styled
caption imported from SRT.

These are rendered project outputs. The original rehearsal photograph is
generated fictional demo media, included in [source/rehearsal.png](source/rehearsal.png).
No proprietary footage, LUTs or branding is included.

## Reproduce and open

From the repository root on macOS:

```sh
LIFE_GENERATE_PROJECT_GALLERY=1 \
LIFE_GALLERY_OUTPUT=/tmp/life-editor-gallery \
scripts/test.sh --filter generateRenderedProjectGallery
open /tmp/life-editor-gallery/performance.lifeedit
open /tmp/life-editor-gallery/social.lifeedit
```

Use a new output directory each time. Collection refuses to replace an existing
project, protecting any edits you have made to it.

The fixture creates portable `.lifeedit` packages with collected source media,
reopens each package, prepares the shared playback composition, exports a
one-second ProRes movie, and extracts the published PNG frame from that movie.
It checks canvas dimensions, media availability, saved sequence equality and
preview/export pixel agreement with an encoding tolerance. The movies, PNGs and
editable projects remain in the chosen output directory.

The checked-in gallery images are those extracted PNGs, copied without further
compositing or retouching. Font availability and native codec versions can cause
small differences when regenerated on another Mac.

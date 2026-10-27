# Architecture

`LifeCore` is Foundation-only: rational timing, Codable project/sequence/track/
clip/automation/marker/multicam structures, immutable snapshots, validated editing
commands, undo groups, package serialization and timeline evaluation. It has no
Mac UI state. Tracks are stored bottom-to-top. Source media is never changed.
Times are rational seconds; video edit commands quantize to the project frame
rate, audio commands retain sample precision. Constant speed currently stores a
Double and maps to a six-decimal rational; exact arbitrary speed maps remain work.

`LifeMedia` owns asynchronous native probing, composition compilation, shared
Core Image custom compositor, Core Text title bitmaps, audio mix parameters and
snapshot export. Core Image uses an explicit linear working space and Rec.709
output. AVFoundation supplies native decoding and pitch/varispeed processing.
Eased audio automation is approximated by 32 linear segments per curve segment.
Export uses AVAssetReader/Writer with the same custom compositor.
Shared sample DSP, complete stream/color metadata inventory and HDR tone mapping
remain required work; setting Rec.709 tags alone does not prove HDR correctness.

`LifeEditor` contains the SwiftUI shell/contextual controls and AppKit timeline.
`EditorStore` routes edits through `ProjectEditor`; an immutable snapshot feeds
media rebuild/export. Revision tokens cancel stale preview builds. Async import
probes complete before merging into the current document and project changes
invalidate pending imports. Timeline drags display a prospective ghost; release
submits a validated command. It never commits a destructive overlap.

Multicam cut refinement uses a baseline-bound immutable proposal. Pointer motion
only updates a ghost; release revalidates and commits once. Video/audio decision
lanes appear only in multicam mode, with matching numeric controls. Source coverage
and locks are checked in changed intervals so unrelated existing camera gaps do
not block refinement. Persisted event arrays are evaluated chronologically while
undo restores their exact original representation.

The AppKit timeline currently uses immediate drawing. WaveformCache is an actor
with at most 24 in-memory 2048-bin summaries; it is a first display implementation,
not the final channel-aware, disk-backed multiresolution cache. Pipeline rebuilds
replace AVPlayerItems and are intentionally cancellable. Incremental compilation,
bounded decoding/proxy preparation and large-project performance remain work.

Packages contain `project.json`. Media references are absolute local URLs today;
machine-local bookmarks, portable collection and rotating recovery are now implemented;
complete resource manifests remain future work. JSON is
atomically replaced and future-version overwrite is refused. No claim is made
that this alone provides crash recovery or portable projects. Timing validation
currently limits positions/durations to 24 hours and project images to 16384px.

Separate audio/analysis/export/renderer modules will be extracted as their
interfaces gain actual independent implementations. No speculative cross-platform
UI layer or external plugin API is introduced.

Apple references: [custom compositor](https://developer.apple.com/documentation/avfoundation/avvideocompositing),
[rational time](https://developer.apple.com/documentation/coremedia/cmtime-api),
[audio algorithms](https://developer.apple.com/documentation/avfoundation/time-pitch-algorithm-settings).

Project JSON currently uses schema 6. Production reads inspect the version header
before decoding project content. Schemas 1 through 5 migrate without changing IDs, media
references, rational timing, automation, or editing decisions; saving writes schema 6.
Schema 3 marks timed adjustment-layer rendering; schema 4 adds Whites, Black Point
and Brilliance rendering; schema 5 persists explicit camcorder dates; schema 6 adds
shared title background styling. Older builds
refuse these projects instead of silently
omitting their processing.
Newer schemas are refused, including when replacing an existing package. Recovery
rotation preserves checkpoints from newer schemas verbatim.

Camcorder dates belong to the VHS effect and store an explicitly chosen source-zero
wall clock plus fixed UTC offset. [QuickTime content-creation metadata](https://developer.apple.com/documentation/avfoundation/avmetadataidentifier/quicktimemetadatacreationdate)
is offered for review, never treated as proof of camera capture or replaced with
a filesystem/current date. Core Text bitmaps are bounded and shared as immutable
images. Render-only scalar clock fallbacks handle otherwise unrepresentable rational
combinations without changing document, media, or automation timestamps.

Automation point selection is transient UI state, scoped to one clip and lane.
Group gestures evaluate from the original envelope and commit one validated
command. Time translation preserves rational spacing; level translation uses the
displayed parameter axis. Hidden source points survive trims. A shared envelope
continues to supply numeric controls, timeline handles, playback and export.

Clock-drift analysis returns three matched source/master anchors rather than
inferring correction from unrelated recording tails. Coarse waveform correlation
only centers the search; each local match must pass confidence checks. A bounded
affine fit validates its middle anchor. Reviewed corrections use existing clip
source ranges and six-decimal speed settings, without changing original media or
adding a project schema. A common rational grid preserves adjacent fragment
boundaries. The UI keeps an immutable baseline for Preview/Apply and leaves the
persistent master and camera decision events unchanged.

AVFoundation composition boundaries use a canonical native clock: 600,000 ticks
per second for video and the project sample rate for audio targets. Audio sources
use their sample clock. Absolute endpoints are mapped before deriving durations,
so shared boundaries cannot acquire independent rounding gaps. Document timing,
source windows and render-parameter evaluation remain rational and unchanged.
This boundary mapping prevents a reproduced native range-read stall with otherwise
valid prime-denominator retimed placements. Preview and export share the compiler.


Title background styling is optional in the document. Its absence uses the exact
legacy background path and padding. New shapes, borders and shadows share one
Core Text layout and bitmap cache with playback, thumbnails and export. A speech
bubble tail extends outside the measured text body; typewriter reveals keep the
full text's layout. Typography presets preserve independently edited backgrounds.
Padding, border and shadow dimensions use canvas pixels, matching title font units.

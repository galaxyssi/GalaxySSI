# Android #4447: uniform side notes and guided landmarks

## Source and dependency

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4447
- Merge: `6794ac7c1af23526a6218421606a58aa77b7dc21`.
- Incremental iOS base: `a740e845cf24cb58054ff0e245049ecb96f23f28`, PR #4523.
- 13 original files: six production Kotlin, four Android device/helper references, two string XML and one version-only file. Inventory and coverage retain every original hash and disposition.

## Native implementation

- Every figure now uses a left note and right illustration, not a portrait/overlay fallback. Note width is 40% capped at 328 points. Below width 320 use 8-point edges/gutter, otherwise 12-point edges and 16-point gutter. Active-node leaders attach at the left midpoint; generic function targets use the artwork center-x rather than its left fifth. Other targets retain native image/viewport conversion and clamping.
- Build stable top-to-bottom landmark steps from plate anatomical markers and features. Each normal labelled illustration has Overview, one title/description per landmark, a step indicator and bounded previous/next icon controls. Reserve the longest title and five-line description at the actual native width/font. Tapping the description shows the complete current copy.
- Structure label rails use localized numbers while exposing full semantic names to accessibility and retaining existing anatomical navigation/feature dialogs. A dedicated numbered layout uses no split rails and at most 48 points/37% width for the number column. Current overview selection and guided highlight have the source tint, opacity and dot sizes; leader routing geometry remains unchanged.
- Advance the guided highlight and annotation focus together. Overview returns to the original subject focus. Normal view has numbers; the existing anatomy enlargement keeps its default named labels and native controls. Existing label hiding and pinch/pan coordinate reporting remain available.
- Persist nonzero steps by owner plus view key in a separate public SceneStorage cache. Keep insertion order and at most 400 entries, remove Overview entries, validate known owners/views/landmark counts on restore and bound serialized input to 128 KB. Whole-body and alternate views have independent entries. No personal records or metric data enter this cache.
- Normalize default view keys consistently: the picker must compare nil as the empty tag and write the selected plate's actual key, allowing return to the default view after choosing an alternative. This fixes a pre-existing nil/empty comparison in the per-view workflow.
- Function captions now reserve four lines instead of two, retaining full-copy expansion. Add Enlarge to animation options. Pause/commit through the existing callback, freeze the visible phase, and present an independent drawing in a native UIScrollView with a properly contained UIHostingController. Pinch/pan uses zoom 1...4; rotation resets viewport geometry only. Closing does not seek, resume or reset the original player. Reduce Motion keeps its existing chapter-start visual policy while retaining the original logical playhead.
- Presentation lifetime is owned by the player view; removing it removes its cover. The enlargement has no timer, clock, phase binding or seek callback. Existing chapter/evidence/related navigation, ownership/lifecycle code, catalogue, renderer registrations, numerical models, research views and personal metric renderer remain unchanged.
- Import two exact translated pairs (body overview and Overview) plus the explicitly pinned neutral integer ratio `%1$d/%2$d`, three entries per locale. The ratio is not source-declared `translatable=false` and is not counted as a translated pair. No iOS version bump or IPA.

## Verification limits

Source/resource/project/grammar/whitespace checks only. Added Swift fixture sources cover uniform columns/compact boundaries, leader endpoints, numbered rail sizing, all bundled landmark views, Overview removal, independent actual heart views, bounded/invalid cache restoration and frozen-clock snapshots. They were NOT executed.

Windows has no Xcode. No Swift type checking, XCTest, simulator/device, native font/label clearance, note height, numbered taps, enlargement size/zoom/pan, playhead-retention gestures, View/SceneStorage recreation timing, screenshots, pixels or IPA acceptance is claimed. Android instrumentation and screenshot additions were reviewed as source references only, not reproduced as iOS evidence.

Historical source contracts accept the superseding uniform-side/four-line/guided-step UI while retaining unchanged numerical, playback/lifecycle, resource, diagram and navigation kernels. Older manifests describe their original revisions, not a claim that superseded layout policies remain active.

## Review scope

The formal PR base is `main`, but this branch cumulatively includes preceding unmerged iOS work through #4523. It is NOT an independent Android #4447 main diff. Review against the exact incremental base above; integrate predecessors in order or deliberately reconstruct integration. The full Android backlog remains in progress.

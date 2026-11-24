# Android #4396 iOS Port

Pinned Android merge: `dbd32a65c73e10d710372c44a7ffa8d1518d1f2c`.
Source PR: https://github.com/galaxyssi/GalaxySSI/pull/4396

## Review Scope

This branch inherits formal iOS #4496, #4495, #4494, #4492 and #4491, not assumed
merged. The PR base is main, so its diff includes predecessors. Incremental base:
`5bb83517a69df0a3556119570b946bf3d3f9bbfa` (#4496 head).
Only iOS changes; no Android/Desktop change, app version change or IPA.

All 63 original files are pinned in ANDROID_4396_SOURCE_INVENTORY.json and mapped
in ANDROID_4396_PORT_COVERAGE.json: ten declaration files, 27 drawables, 18 resource
XMLs, seven Android test references and one Android APK version bump. The pinned
APK code is 0.18.166 (1727), not the earlier version in its PR description.

## Implementation

- Added all 27 original dedicated cutaways with 113 local feature explanations
  and 64 anatomy links from Kotlin-evaluated declarations.
- Activated revision 4396: 88 views / 392 features / 116 links. Explicit reads
  retain archived 4389 and 4391 snapshots; all previous 61 declarations and
  Android drawable bytes match the prior revision.
- Imported all 620 additional source paths with quadratic normalization, group
  transforms, clipping, fill rules and retained PDF metadata. The 21 original
  gradients retain PDF shading functions, source coordinates and color stops;
  outlined gradient shapes preserve both clipped shading and the border path.
- Imported and registered all 278 exact English/Chinese pairs in AtlasAnatomy.
- Existing view selection defaults to the new cutaway and keeps its original
  locator. Original course assignments/catalogue and physiology bindings remain
  unchanged from pinned #4388; numerical/functional lessons are not replaced.
- Updated XCTest source expectations for all 88 detail/locator/zoom/layer
  restorations and changed respiration/vascular defaults. Added real sternum to
  clavicle and hand to radius/ulna links with preserved functional lessons.
- Added explicit all-313-entry ownership and 177-organ coverage expectations to
  the XCTest source, matching Android's contract. These assertions are NOT
  executed evidence of iOS ownership/runtime coverage.
- Android's synthetic pinch-radius test adjustment is instrumentation-only;
  UIKit retains its own native gesture handling, not Android touch thresholds.

## Source Verification

- `check-atlas-detail-source-scope.cjs --anatomy-4396 --checks` passed: 63 source
  hashes/dispositions, declaration/resource re-extraction, graph/feature/link
  identities, 956 combined bilingual pairs and all 1,772 paths across 88 PDFs.
- PDF geometry/transform/clipping operators match normalized source. All 21
  shading types, coordinates, function domains, color stops and interpolation
  segments match the original declarations. This is not pixel acceptance.
- Three changed Swift files parsed without grammar errors after conditional
  directives were removed; not Swift type checking.
- `npm run check:ios` project metadata and `git diff --check` passed.

## Outstanding Native Acceptance

No Swift/Xcode compilation, XCTest run, simulator/device launch, native gesture/
restoration/rotation/large-text exercise, VoiceOver, screenshot/pixel/alpha check
or IPA generation was performed. Source checks do not establish these or prove
all-entry iOS ownership on a running app. Formal/non-draft status is requested by
the user, not native certification. Inherited historical vector/runtime gaps
remain documented in predecessor ports.

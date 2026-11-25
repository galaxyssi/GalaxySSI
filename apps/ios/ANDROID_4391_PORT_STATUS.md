# Android #4391 iOS Port

Pinned Android merge: `165809fc9606ac1ff6b0df6eb9bee73286b415ea`.
Source PR: https://github.com/galaxyssi/GalaxySSI/pull/4391

## Review Scope

This branch inherits formal iOS #4495, #4494, #4492 and #4491, not assumed merged.
The PR base is main, so the diff includes predecessors. Incremental review base:
`80e6cde79256a0c423efd07eab8b35630b7e5e4e` (#4495 head).
Only iOS changes; no Android/Desktop change, app version change or IPA.

All 70 original files are pinned in ANDROID_4391_SOURCE_INVENTORY.json and mapped
in ANDROID_4391_PORT_COVERAGE.json: ten declaration files, 35 vector drawables,
18 resource XMLs, six Android device-test references and one Android APK version
bump. The pinned APK code is 0.18.165 (1726); the older PR-description version
is not treated as source.

## Implementation

- Added 35 original dedicated cutaways with 140 new local feature explanations
  and 49 new canonical anatomy links from Kotlin-evaluated declarations.
- Default pinned detail catalogue is revision 4391: 61 views / 279 features /
  52 links. Explicit revision 4389 reads retain the archived 26-view snapshot.
  Owner order, source URLs, identities, counts and read revision are validated.
- Imported all 744 additional vector paths with normalized quadratic geometry,
  group transformations, clipping, fill rules and retained PDF metadata.
- The original 26 declarations and their Android drawable bytes remain unchanged.
- Imported and registered all 347 exact English/Chinese pairs in AtlasExpanded.
- Existing detail-first routing keeps original locator views for every new owner.
  Course assignments/catalogue and physiology bindings remain unchanged from the
  pinned #4388 Android source; no replacement of functional or numerical lessons.
- Extended XCTest source assertions to all 61 detail/locator/zoom/layer
  restorations and updated changed muscle, skeletal, ear, nervous and valve
  defaults. Added explicit skin-organ to epidermis/dermis canonical links and
  independent function-selection/progress expectations across view changes.
  XCTest sources were not executed.

## Source Verification

- `check-atlas-detail-source-scope.cjs --expanded-4391 --checks` passed: 70 source
  hashes/dispositions, declaration/resource re-extraction, 678 combined bilingual
  pairs, graph/feature/link identities and all 1,152 paths across 61 PDFs.
- Exact PDF geometry/transform/clipping operators match normalized source data.
- Retained #4389 source audit passed with no changes to its archived declarations.
- Three changed Swift files parsed without grammar errors after conditional
  directives were removed; not Swift type checking.
- `npm run check:ios` project metadata and `git diff --check` passed.

## Outstanding Native Acceptance

No Swift/Xcode compilation, XCTest run, simulator/device launch, gesture/rotation/
large-text exercise, native restoration, VoiceOver, screenshot/pixel/alpha check
or IPA generation was performed. Source checks do not establish these. The PR
is formal/non-draft by user request, not a claim of native certification.
Inherited vector/native acceptance gaps remain documented in predecessor ports.

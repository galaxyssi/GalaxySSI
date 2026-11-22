# Android #4323: Interactive Organ Plates

## Source

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4323
- Merged source: `7e480757a2aa9b2395390ee5b97e4369060fbdbb`.
- No Android or Desktop production code/version changes are included.

## Dependency and Independent PR Scope

This is the **additive organ-resource increment**, not another copy of the atlas foundation. The native atlas consumer is in https://github.com/galaxyssi/GalaxySSI/pull/4428, updated to commit `896a71a07` with the validated optional artwork-pack contract. Both PRs use `main` as base. They do not repeat each other's files or commits and can build independently: this resource pack has no Swift reference to an unmerged atlas type, and the foundation works with or without the pack.

**The new atlas UI requires both PRs.** Merging this increment alone only packages the resources; it does not replace the existing legacy body page. No automatic merge is requested or performed. The dependency is functional, not a reason to hide duplicate foundation changes in this diff.

## Ported Increment

| Android change | iOS mapping |
| --- | --- |
| Brain, lungs, liver/gallbladder and kidney artwork | Four original transparent 1254 x 1254 PNG blobs in `HealthAtlasBrain`, `HealthAtlasLungs`, `HealthAtlasLiver`, `HealthAtlasKidney` image sets |
| Central plate metadata | `HealthAtlasOrganPlates.dataset`: seven plates, explicit owners, entry-to-plate routing, aspect ratios and full-bitmap normalized marker coordinates |
| Plate context and orientation | Six localized view captions and contextual owner caption, consumed by native atlas artwork/fullscreen views in #4428 |
| Kidney structures | Three additive entries: renal cortex, medulla, pelvis; inserted after kidneys, with matching children, aliases and associated urinary teaching process |
| Catalogue counts | Composition is 14 categories, 161 organ/structure entries, 105 cell types/subtypes, one platelet fragment; total 281 |
| Visible structure navigation | Whole-body lung marker, brain/lung/liver/kidney markers, native layer menu including visible markers, non-duplicating current selection |
| Large text and fullscreen | The consumer retains wrapping native labels, caption and structure navigation in fullscreen rather than showing a context-free image |
| Chinese/English | 17 changed/new strings: English with the resource metadata, Chinese in the existing `zh-Hans.lproj/Localizable.strings` table |

This PR intentionally does not modify `project.pbxproj`: images and the data set use the already registered asset catalog; Chinese additions use the already registered localization table. The regression source is added to the existing registered Health theme XCTest file. No prerequisite files or Swift types are copied into this main-based branch.

## Verification Actually Performed

- `npm run check:ios`: passed static project structure checks.
- `node apps/ios/tools/check-body-atlas-organ-plates.cjs --base-ref origin/ios/android-4322-body-atlas-20261122 --android-ref 7e480757a2aa9b2395390ee5b97e4369060fbdbb`: passed. The composed JSON, including ordering and all entry fields, is exactly equal to Android's complete #4323 catalogue. All graph/marker references resolve. New images are byte-for-byte equal to Android, retain RGBA transparency and original dimensions. All 17 localization keys and format placeholders resolve.
- Swift grammar parsing: consumer changes and new/updated XCTest source have no grammar errors. This is **not** Apple SDK type checking.
- Original PNGs inspected as local images. These are assets, **not screenshots of the running iOS app**.
- `git diff --check`: passed.
- Focused XCTest resource/metadata/translation source added, but not executed, per request. No test suite, Xcode build, simulator/device run, IPA or pixel-parity certification was performed on Windows.

The static composition audit can also run after both PRs merge without `--base-ref`, using the local frozen base. The explicit reference option lets reviewers check the combined data before the dependency merges, without changing the worktree or building the app.

## Limits

These generated teaching plates are schematic, not patient scans or validated diagnostic images. Kidney-region descriptions retain the Android distinctions between filtration, tubular processing and the collecting space. They do not introduce personal renal-function estimates or new treatment models. Unillustrated structures still use actual relationships rather than a reused unrelated image.

The native consumer uses Apple's [asset-catalog Data Set format](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/DataSetType.html), not a network download. Dynamic Type layout, gesture/navigation ergonomics, appearance under actual device graphics settings and Agent end-to-end execution still require Apple runtime validation before claiming device acceptance.

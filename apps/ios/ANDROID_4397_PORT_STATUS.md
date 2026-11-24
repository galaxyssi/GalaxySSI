# Android #4397 iOS Port In Progress

Pinned source: `40776e7a67ebfe48c76f98d392849edb9810ac82`.
This branch inherits formal #4498, #4496, #4495, #4494, #4492 and #4491. No iOS
PR for Android #4397 has been published yet. The eventual PR must use main and
disclose its inherited diff; incremental base is #4498 head
`6fe78ae14dc434edfb1b23a6f04d62bbd679f5f3`.

## Implemented

- Added nine source-matched model specifications, 24 bounded controls and 34
  entry bindings, plus finite/range-checked result/companion calculations.
- Preserved source units/scales/precision: single-glomerulus nL/min, aggregate
  salivary DU/min, parallel branch split, apex-based cochlear position, stable
  expm1 extraction, percent strain and signed net filtration pressure.
- Connected new cases after existing routing clauses, to retain prior mapping
  precedence, generic sliders/reset/chart/source/context and entry-scoped state.
- Added original title/scope/formula/control localization and precision routing,
  companion formatting and the curve accessibility identifier.
- Imported and registered all 60 English/Chinese resource deltas in AtlasTeaching.
- Extracted the original Kotlin production declarations into
  ANDROID_4397_MODEL_DECLARATIONS.json with a full changed-source hash inventory.
  This extraction does not compile Android UI/tests or execute Swift.
- JSON extraction escapes non-ASCII unit symbols before Java stdout emission,
  avoiding Windows output-codepage corruption without changing the shared
  extractor's behavior for archived snapshots.

## Source Checks Performed

- `check-atlas-teaching-model-source.cjs` passed: all 46 original hashes, nine
  declarations, exact 24-control ranges/scales/units/precision and localized
  keys, 34 graph-resolved owners and 60 bilingual resource pairs.
- Existing 67 route clauses are byte-identical and disjoint from new owner IDs.
  New runtime routes and text/curve wiring are present in source.
- Seven changed/new Swift files parsed with zero grammar errors (conditional
  directives removed where present). This is not Swift type checking.
- `npm run check:ios` project structure passed. No native acceptance claimed.

## Remaining Before Publication

- Finish all-nine result/companion, range/precision/route/context and restoration
  source checks; review every original production/test change and write exhaustive
  source-file dispositions before submitting one formal non-draft PR.
- Check prior routes and archived source audit compatibility. No broad native
  32-model/101-entry runtime coverage claim is made from source text alone.
- No Swift type checking, Xcode build, XCTest run, native slider/curve/restore,
  screenshots, accessibility/device acceptance or IPA generation performed.

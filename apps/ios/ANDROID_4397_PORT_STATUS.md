# Android #4397 iOS Port

Pinned source: `40776e7a67ebfe48c76f98d392849edb9810ac82`.
Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4397

## Review Scope

This branch inherits formal #4498, #4496, #4495, #4494, #4492 and #4491, not
assumed merged. The PR base is main and includes predecessor changes.
Incremental review base: `6fe78ae14dc434edfb1b23a6f04d62bbd679f5f3` (#4498 head).
Only iOS changes; no Android/Desktop change, app version change or IPA.

All 46 original files are pinned in ANDROID_4397_SOURCE_INVENTORY.json and mapped
in ANDROID_4397_PORT_COVERAGE.json: 13 production files, 18 resource XMLs,
13 Android unit-test references, one device-test reference and one Android-only
APK version change. The pinned APK version is 0.18.167 (1728), not the earlier
version in the PR description.

## Implementation

- Nine explicit native teaching kinds: capillary exchange, valve flux,
  glomerular filtration, skin water barrier, salivary delivery, tendon elongation,
  airway split, peristaltic travel and cochlear frequency.
- Preserved all 24 control ranges/defaults/scales/units/precision, model axes/
  bounds, primary/additional sources and 34 graph-resolved owner IDs. The existing
  67 route clauses retain precedence and are disjoint from the new owners.
- Result/companion kernels reject wrong input count, out-of-range/nonfinite
  values and invalid scales. Preserve stable expm1 extraction, forward filtration
  clamp with signed net pressure, branch flow/pressure conservation equations,
  single-glomerulus nL/min, synthetic salivary DU/min, percent strain and
  apex-based cochlear position. No clinical measurement or health archive access.
- Connected generic sliders, result/companion, curve axes, reset, assumptions,
  source links, localized public Agent context and per-entry input restoration.
  Curve/output/companion/slider/reset accessibility identifiers mirror source tags.
- Imported and registered all 60 exact English/Chinese pairs in AtlasTeaching.
  Kept prior input/result precision and added the original teaching precision;
  companion values retain the source's two-digit maximum formatting.
- Original Kotlin declaration extraction records nine specifications, 24 controls
  and 34 owners in ANDROID_4397_MODEL_DECLARATIONS.json. ASCII JSON escaping
  prevents Windows Java output codepages from corrupting unit symbols; archived
  extractors are not changed.
- Added XCTest source fixtures for all nine defaults, signed pressure/zero clamp,
  units/scales, nonfinite rejection, localized context, fractional inputs and
  flow conservation. Updated monotonicity and old podocyte/inner-ear routing
  expectations. Added capillary entry versus related-cell restore/reset isolation
  and conditional 32-model/101-entry mapping expectations. XCTest was NOT run.

## Source Verification

- `check-atlas-teaching-source-scope.cjs --checks` passed: all 46 source hashes/
  dispositions, original declaration/resource re-extraction, exact controls,
  model units/axes/bounds/ownership/source associations, explicit equation
  branches, bilingual keys and prior route preservation.
- Prior load-transfer and calf-pump source checks passed; their independent
  analytic samples do not execute Swift.
- Nine changed Swift files parsed without grammar errors after conditional
  directives were removed. This is not Swift type checking.
- `npm run check:ios` project metadata and `git diff --check` passed.

## Outstanding Native Acceptance

No Swift/Xcode compilation, XCTest run, simulator/device launch, native slider/
curve/restore/reset, screenshots, VoiceOver or device acceptance was performed.
Source assertions/analytic examples do not prove native numerical correctness or
running 32-model/101-entry coverage. Formal/non-draft status follows the user's
request, not native certification. No IPA generated; inherited runtime/vector
acceptance gaps remain documented in predecessor ports.

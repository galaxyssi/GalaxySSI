## Dependency And Actual Diff

Base: `main`. This branch builds on the **still-open #4491** foundation (Android
#4384), not on an independently merged copy of that work. Until #4491 merges,
GitHub's `main...head` diff includes that foundation as well as this increment.
There are no new duplicate foundation commits or an empty PR.

The Android #4385 increment starts after
`ba009094137225e74b16cebbb7d434ccd74fd24d`. Review the increment with:

```sh
git diff ba009094137225e74b16cebbb7d434ccd74fd24d...ios/android-4385-regional-atlas-20261124
```

The source integration is ready for code review, **not native/device acceptance**.
This is one formal, non-draft iOS PR for Android #4385; no IPA is generated.

## Android Source And Scope

- Android PR: https://github.com/galaxyssi/GalaxySSI/pull/4385
- Pinned merge: `a81aa85a1c81e41ff19a032eabea1eddcd2371dc`
- All 93 changed source files have an explicit, hash-verified disposition in
  `apps/ios/ANDROID_4385_PORT_COVERAGE.json`: 36 business files, 23 vectors,
  26 resource XMLs, seven Android test-contract references, one APK version bump.
- Android test scaffolding/version metadata is not represented as executed iOS
  tests or an iOS version bump. Implementation and tooling changes are iOS-only.

## iOS Changes

- Activate the Kotlin-evaluated regional catalogue: 114 courses, 544 chapters,
  261 references, 289 owner routes and 124 related destinations. Keep the 101-course
  #4384 snapshot explicitly addressable for archived checks.
- Add and dispatch all thirteen native regional courses: ankle mortise, vulvar
  protection, accessory-gland routing, uterocervical continuity, penile urinary
  route, scrotal heat exchange, skull protection, vertebral motion, clitoral
  sensory path, vestibular-gland secretion, tenocyte tendon matrix, pectoral
  horizontal adduction and latissimus extension/adduction.
- Match source outlines, dynamic controls, phase mappings, mirrored routes,
  anatomical callouts, motion models and teaching limitations. No generic
  placeholder renderer stands in for the thirteen new course implementations.
- Connect 73 distinct structure selectors for 72 owners, 252 annotations and
  36 anatomy links; retain context views and both tenocyte views. Include the
  taste-pore coordinate fix and revised microglia/ependymal/rib plates.
- Add calf-pump inputs, rate-axis chart, net-stroke/net-flow calculation, references
  and chamber/valve/forward/return-flow diagram. Synchronize ligament first-chapter
  ACL/PCL focus. Add 431 exact resource deltas per English/Chinese table.
- Import all 23 changed source vectors and regenerate all 73 active structure
  PDFs with correct quadratic/smooth-curve geometry, gradients, clipping and
  affine groups. Four PDF-backed structure course scenes use the corrected copies.
  Pinned MIT-licensed svgpath 2.6.0 is tooling-only, with unchanged license/source
  distribution and official registry archive-integrity provenance.
- Retain native preserved-vector PDF rendering for pineal zoom/rewind instead of
  copying Android's VectorDrawable-specific raster cache workaround.

## Verification

Passed source-only checks:

- Serial full-scope audit: `check-atlas-regional-source-scope.cjs --write --checks`.
- Re-evaluation of original pure Kotlin catalogue/plate/path declarations.
- All thirteen course-specific geometry/motion/resource checks, calf-pump analytic
  input grid, bilingual resources and active runtime source dispatch/selection.
- Corrected regional PDF/source checks, including 1,015 paths and 171 gradients
  across all 73 structure views, scoped clipping, quadratic equivalence and the
  real consecutive-T skull regression fixture.
- Retained frozen cohort, context/navigation source checks and project/module
  structure checks. Swift grammar is checked separately from type checking.

**Not performed:** Swift type checking, Xcode/Metal/native builds, XCTest, simulator
or device execution, VoiceOver or pixel/UI acceptance. Windows does not provide
native iOS build/device validation. Existing XCTest source expectations were
updated, not executed. CI results are not being used as an acceptance claim.

## Remaining Inherited Limitation

The frozen #4384 PDF cohorts are retained unchanged. Current regional structure
views and four corresponding course scenes use corrected copies. Other unchanged
#4384 PDF-backed course cohorts still need a separate quadratic audit; their old
encoded-operation checks are not proof of semantic/pixel parity. This PR does not
claim the whole app, every Android PR or native acceptance is complete.

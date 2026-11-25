# Android #4388 iOS Port

Source merge: `6581110ec5c048edebf63821dee839b4818fe663`.
Source PR: https://github.com/galaxyssi/GalaxySSI/pull/4388

## Scope And Dependencies

This branch inherits formal iOS #4492 (Android #4385) and #4491 (Android #4384).
Both remain open at publication preparation. The PR base is main, so the GitHub
diff includes their implementation, not only this port. Incremental review base:
`abc7718cb8721122b123c38c3b5803b036dad2d5` (#4492 head).

`ANDROID_4388_SOURCE_INVENTORY.json` pins all 67 original changed source hashes.
`ANDROID_4388_PORT_COVERAGE.json` maps each file to native code/resources,
source-only checks, or an explicit Android-only disposition. Android test
scaffolding and APK version changes are not claimed as executed iOS features.

## Implemented

- Default runtime catalogue revision 4388: 138 courses, 643 chapters, 320 source
  references, 313 owner routes and 151 related lesson links. Original Kotlin
  declarations are evaluated by the existing extractor, including entry phases,
  preview flags, durations and independent lesson choices.
- All 24 added courses have explicit native renderer dispatches: pelvic load,
  subcutaneous cushioning, Paneth, enteroendocrine, intestinal stem, distal
  tubular, urothelial, delta, PP, calcitonin, adrenal cortex, Leydig, theca,
  somatotroph, lactotroph, corticotroph, gonadotroph, pericyte, Langerhans,
  muscle satellite, mast, helper T, cytotoxic T and regulatory T.
- Preserved source stage timing, directed transport, path geometry, chemical
  symbols, clipping, local labels and cell/structure identity. Constant geometry
  extraction rejects unsupported source expressions. Parameterized mast and
  satellite geometry is ported explicitly rather than treated as constants.
- Subcutaneous playback keeps the 24 by 20 deformation mesh and existing
  Metal/software fallback. Pituitary routes retain distinct endocrine symbols,
  targets and hidden out-of-range particles; crypt courses share exact wall
  geometry but retain separate niche, signal and barrier behavior.
- Complete structure runtime: 75 view identities, 74 owners, 259 local features
  and 41 anatomy links. Two new pelvic/subcutaneous vector cutaways preserve
  original 23 paths, normalized quadratic curves and two even-odd holes.
  Reused 73 declarations and Android drawable bytes match the archived revision.
- Bounded synthetic pelvic support/contact pressure models, source defaults,
  independent persisted inputs, reset, chart axes/units/bounds, companion results,
  context text, original diagrams and corrected vertical arrow direction.
- 539 exact resource deltas in each registered English/Chinese AtlasComplete
  table. Historical tables/catalogues remain available by explicit revision.

## Verification Limits

- Passed `check-atlas-complete-source-scope.cjs --checks`: original source hashes,
  all file dispositions, catalogue/routes/related destinations, bilingual keys,
  structure metadata/assets, dedicated renderer source contracts and geometry.
- Model audit checked source formulas and 7,365 independent analytic input
  samples. These samples do not execute Swift.
- All 64 changed Swift files parsed with zero grammar errors after conditional
  directives were removed. This is not Swift type checking or either build mode.
- `npm run check:ios` passed (project structure); `git diff --check` passed.
- No XCTest, Xcode/Swift compilation, device launch, Metal execution, VoiceOver,
  screenshot/pixel parity or native navigation/persistence acceptance performed.
  No IPA generated. Native acceptance remains outstanding.
- Inherited non-regional #4384 PDF quadratic corrections remain separate work;
  this port does not claim to correct every historical vector in the app.

# Android #4389 iOS Port In Progress

Pinned source: `9508d49277cf33ab7f85e65722e7c470930fff7e`.
This branch inherits formal iOS #4494, #4492 and #4491. No #4389 iOS PR has
been published yet; it must use main and disclose inherited changes.

## Implemented

- Evaluated original Kotlin declarations for 26 dedicated cutaways with 139
  local explanations and three anatomy links. Imported 408 vector paths with
  quadratic normalization, preserved fill rules and vector PDF metadata.
- Imported all 331 exact English/Chinese resource pairs into AtlasDetail and
  registered the table and native structure pack in Xcode.
- Added pinned structure validation and detail-first view routing, preserving
  original locator views and their stable selector identities.
- Changed anatomy presentation to full screen, with separate zoom/label state,
  show/hide controls, reset of scale/scroll position and existing UIKit label
  actions. Kept local feature explanations and depth-limited anatomy navigation.

## Remaining Before Publication

- Review all original Android production and test diffs, including shared pinch
  target-tap behavior and large-text/landscape contracts.
- Update historical XCTest source expectations affected by detail-first defaults;
  no XCTest execution is requested or claimed.
- Finish exhaustive per-file port dispositions, source checks and Swift grammar
  inspection; then publish one formal non-draft iOS PR for Android #4389.
- No Swift/Xcode compilation, native gestures, screenshots, pixel comparison,
  accessibility/device acceptance or IPA generation has been performed.

## Source Checks Performed

- `check-atlas-detail-source.cjs`: all 72 original hashes, 26 view identities,
  139 features, three links, 408 original paths, PDF page/resource availability,
  331 bilingual key pairs and runtime source wiring passed.
- Three changed/new Swift files parsed with zero grammar errors. This does not
  type-check Swift or validate UIKit/SwiftUI runtime behavior.
- `npm run check:ios` project structure and `git diff --check` passed.

# Android #4355: iOS Renal, Digestive and Microscopic Artwork

## Review Scope
- Ports Android #4355 at `be7c78beabadc52bbaf41f5576644b58f2decc22`.
- Formal non-draft PR targeting `main`; depends on iOS #4477 (Android #4354).
- While #4477 is open, main-based comparison includes its real commits. This increment begins after `cb771757d6c417076bfdfdbbcf7085181483de68` and contains seven PNG replacements, expanded XCTest source, import/parity tools and this note. No copied predecessor implementation.
- iOS only; no version bump, Android/Desktop changes, graph edits, new strings, IPA or health storage changes.

## Implementation
- Imports Android originals byte-for-byte: pancreas, urinary tract, nephron, alveolus, pancreatic beta cell, erythrocyte and neuron.
- Existing image names, pixel dimensions, aspect ratios, normalized anatomy links, zoom and per-entry state are preserved.
- Verified the current iOS selection chain resolves these owners to the replaced bitmap assets: SystemPack for pancreas/urinary, RenalPack for nephron, RespirationPack for alveolus, CellPack for erythrocyte/neuron and ArtworkPack for beta cell.
- Extends image regression fixtures to both batches: fourteen plates and 42 canonical hotspots, plus fourteen transparent-gap/interior samples from the Android device tests.
- No additional timer or rendering engine changes; directional flow from #4477 remains intact.

## Verification
- `node apps/ios/tools/check-body-atlas-editorial-cells.cjs` checks all fourteen images against pinned Android bytes, original dimensions, transparent corners, exact hotspot coordinates and the seven gap/interior pairs. Requires `sharp` through `NODE_PATH`.
- Pinned Android contact sheet visually inspected; local copies are byte-identical.
- `npm run check:ios`, `node apps/ios/tools/check-atlas-module-flags.cjs`, and the frozen base `check-body-atlas.cjs` pass static audits.
- Changed XCTest file passes Swift grammar parsing under both conditional branches. Not Swift type checking.
- XCTest source expanded but not executed, as requested.
- Windows has no Xcode. Native build, Asset Catalog compilation, launch, device/simulator screenshots and accessibility/UI acceptance remain unverified. No IPA generated.

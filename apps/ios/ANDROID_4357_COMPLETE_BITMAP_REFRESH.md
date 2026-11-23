# Android #4357: Complete the iOS Bitmap Illustration Refresh

## Review Scope
- Ports Android #4357 at `96b3f950e85c839173e473ddb2435fe88f1acb75`.
- Formal non-draft PR targeting `main`; depends on iOS #4478 (Android #4355).
- Development continues without waiting for #4478. While it is open, the main comparison includes its real commits. This increment starts after `b0315a767d6f86becc074b891232726438350ff7`: ten PNGs, seven marker positions in two datasets, image regression source, import/check tools, prior visual-checker pin updates and this note.
- iOS only; no version bump, Android/Desktop changes, personal health data, model/entry changes or IPA.

## Implementation
- Byte-identical Android replacements: skeleton front/back, muscle front/back, sensory, respiratory, accessory digestive, endocrine, immune and skin overviews.
- Completes this 24-of-24 bitmap style batch. Vector diagrams and simulation art are not claimed as refreshed here.
- Calibrates rectus abdominis, oblique abdominal muscles, trapezius, gastrocnemius, tendon, larynx and sublingual-gland marker positions.
- Retains all normalized coordinates not changed by Android, original pixel dimensions/aspect ratios, native zoom, dedicated-organ precedence and all four muscle/skeleton view keys.
- Historical graph/routing provenance remains unchanged; `artworkSource` records the #4357 visual revision separately.
- Updates the earlier musculoskeletal/overview source audits to compare the current pinned visual revision rather than obsolete bitmap bytes and coordinates.
- Image regression source now covers 24 unique bitmap plates, 100 hotspot anchors, 13 muscle-region colour samples, and the prior seven gap/interior pairs.

## Verification
- `node apps/ios/tools/check-body-atlas-editorial-final.cjs`: exact bytes for 24 PNGs, source coordinates, original dimensions, translucent corners (alpha <= 4), 100 opaque anchors, 13 muscle-region colours and 14 gap/interior samples. Requires `sharp` through `NODE_PATH`.
- `check-body-atlas-musculoskeletal.cjs` and `check-body-atlas-overviews.cjs` pass revised source parity, view/routing and reference checks.
- Contact sheet of all ten local replacements visually inspected.
- `npm run check:ios` and `node apps/ios/tools/check-atlas-module-flags.cjs` pass static audits.
- Changed XCTest source passes Swift grammar parsing under both conditional branches, not Swift type checking.
- XCTest source expanded but not executed, as requested.
- Windows has no Xcode: native build, Asset Catalog compilation, launch, device/simulator screenshots, accessibility and UI acceptance remain unverified. No IPA generated.

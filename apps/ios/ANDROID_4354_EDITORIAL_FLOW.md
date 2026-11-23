# Android #4354: iOS Editorial Illustrations and Directional Flow

## Review Scope
- Ports Android #4354 at `b4ed9ae74fa6989da5addbfdd8bf9d35dd960855`.
- Target branch: `main`, formal non-draft PR.
- Predecessor iOS #4476 (Android #4353) is merged. The main-based comparison contains only this increment: seven PNGs, the section renderer, the fallback whole-body lung hotspot, regression source, import/check tools and this note.
- iOS only; no version bump, Android/Desktop changes, IPA or personal archive writes.

## Implementation
- Byte-identical Android illustrations replace the whole-body, heart, lungs, liver, kidney, brain and intestinal overview bitmaps.
- Original pixel dimensions, transparent corners, zoom behaviour and canonical coordinates are preserved. The bundled primary whole-body plate already has the lung link; its code fallback now matches it. Both definitions have the same 26 combined hotspots as Android.
- Existing section tracks now draw the traveled segment with a pale 5.6-unit underlay and blue 2.7-unit stroke. A bordered triangular arrow follows the path tangent, including at zero progress.
- Uses the existing SwiftUI trimmed path for distance-based travel and the final Bezier control polygon for its tangent. Arrow geometry, stroke colours and dimensions follow the source.
- Rewind removes the trail but retains the start arrow. Stage changes remain on the same playback state/timer; pause, background and reduced-motion behaviour are unchanged.
- No new content strings, graph entries or health measurements.

## Verification
- `node apps/ios/tools/check-body-atlas-editorial.cjs` verifies byte parity of all seven PNGs, original sizes, transparent corners and 26 exact opaque hotspot coordinates; also audits source arrow dimensions. Requires `sharp` through `NODE_PATH`.
- Contact sheet of all seven imported images visually inspected.
- `npm run check:ios` and `node apps/ios/tools/check-atlas-module-flags.cjs` pass static project/settings checks.
- Swift grammar audit passes for three changed Swift files under both conditional branches. Not type checking.
- Added XCTest source for image resolution/transparency/anchors, quadratic/cubic endpoint tangents, rewind, invalid fractions and all existing gut/lymph routes. Not executed, as requested.
- Windows has no Xcode. Native build, animation pixels, simulator/device operation, accessibility and UI acceptance remain unverified; no IPA generated.

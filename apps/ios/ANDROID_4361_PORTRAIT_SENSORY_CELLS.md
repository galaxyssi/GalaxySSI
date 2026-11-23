# Android #4361: Portrait Sensory Cells and Stage Highlights

## Review Scope
- Ports Android #4361 at `ac7ab99df542b67a7a0ea6a28999a7334b79aada`.
- Formal non-draft PR targeting `main`; predecessor iOS #4482 (Android #4360) is merged and the branch is synchronized with main.
- Only this portrait-cell increment is new scope. iOS only; no version bump, graph/model/string changes, personal health storage, Android/Desktop changes or IPA.

## Implementation
- Imports three byte-identical transparent 1024-by-1536 Android portraits: inner-ear hair cell, rod and cone. Retires their generated PDFs.
- Updates six structure landmarks and preserves their existing titles, explanations and navigation. The hair-cell receptor-body landmark is added only to the simulation lesson, not to canonical anatomy entries.
- Uses source stage maps: rod/cone [0,0,0,1], hair cell [0,0,2,1], ending on the afferent contact, spherule or pedicle as appropriate.
- Shared lessons now declare height as well as width. Portraits use a 280-by-420 logical canvas and 280-point maximum display height; existing courses keep 360-by-280 defaults and landscape sizing.
- Geometry bounds accept an explicit height while legacy callers retain the old 280-unit limit. Rendering, marker positions, source aspect and flow helper all use the declared dimensions.
- Cell quantitative controls stay before the portrait. Rod photon inputs remain independent of playback/stage changes; no numerical model equation changes.
- Updated source/resource audits for current painted coordinates and the frozen original graph. The legacy sensory import now delegates current PNG/gradient assets to their dedicated importers instead of overwriting them with obsolete art.
- Retained gradient PDFs keep their resource identifiers and bytes stable despite retired cell assets.

## Verification
- `check-body-atlas-portrait-cells.cjs`: exact original PNG bytes, sizes, transparency, six calibrated opaque landmarks plus the hair-cell body, stage maps and source dimension/order integration.
- Sensory catalog audit: 16 plates, 34 structure features, three cell links, 151 retained vector paths and three portraits; the original graph/circuit links remain unchanged.
- Existing 24-bitmap, painted-ear, painted-eye/split-callout and retained-gradient audits pass, collectively covering the 29 bitmap assets and 108 canonical anchors. The full frozen gut-era graph composition still matches 313 entries / 192 mechanisms.
- All three local portrait images visually inspected. No synthetic image is presented as a native app screenshot.
- `npm run check:ios`, module settings and frozen base resource/i18n audits pass. Seven changed Swift files pass grammar parsing under both conditional branches, not Swift type checking.
- Added XCTest source for portrait dimensions/feature order, output selection, restored independent stages, retained rod inputs, explicit height validation and owner/screen-scoped context. Bitmap source fixtures now cover 29 assets.
- XCTest was not executed, as requested. Windows has no Xcode: native build, Asset Catalog processing, actual stage repainting, device/simulator operation and accessibility acceptance remain unverified. No IPA generated.

# Android #4364: Painted Cardiac Section and Valve Anchors

## Review Scope
- Ports Android #4364 at `24748a84e848040dbe0cba323cbd5d6b970fb537`.
- Formal non-draft PR, base main. Predecessors iOS #4484 and #4485 are merged.
- Synchronized main at `6d6ae3fe6` after #4485 merged. The main-based diff now contains only this #4364 cardiac increment; no inherited tissue/lymph changes remain.
- iOS only. No version bump, model equations, graph, localization, personal-health changes or IPA.

## Implementation
- Imports the byte-identical transparent 1254-square Android cardiac section and retires its old generated PDF.
- Recalibrates six chamber/vessel landmarks and four leaflet landmarks. Structure and dynamic valve display share the same normalized marker values.
- Uses a centered square viewport for the existing SwiftUI valve overlay, preserving source indicator size, selected state and open/closed appearance.
- Retains four stages, valve opening rules, navigation, accessibility labels and independent synthetic ejection inputs.
- Updates the legacy importer and resource audit so regeneration cannot restore obsolete artwork. Graph provenance is preserved separately from artwork provenance.
- Adds XCTest source for shared leaflet coordinates, ten image color neighborhoods and the expanded 31-bitmap / 119-canonical-anchor fixture.

## Verification
- Painted-heart resource audit passes: exact source PNG, dimensions, transparent corners, all ten calibrated blue/rose/leaflet color neighborhoods, square overlay integration and unchanged graph/model pack.
- Existing heart graph audit, iOS project check, module settings, frozen base resource/i18n and whitespace checks pass.
- Three changed Swift files parse under both conditional grammar branches. This is not Swift type checking.
- Painted resource visually inspected. No resource preview is represented as an app screenshot.
- XCTest not executed, as requested. Windows has no Xcode: compilation, Asset Catalog processing, actual phase/rewind repainting, native overlay placement and device/accessibility acceptance remain unverified. No IPA generated.

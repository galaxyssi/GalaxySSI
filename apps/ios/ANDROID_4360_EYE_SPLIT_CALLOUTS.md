# Android #4360: Painted Eye and Split Anatomy Callouts

## Review Scope
- Ports Android #4360 at `920ede43e4c010f166d459ca2f5e674414766683`.
- Formal non-draft PR targeting `main`; predecessor iOS #4481 (Android #4359) is merged.
- Branch synchronized with main after #4481 merged. Review scope contains only this increment: eye bitmap/callouts, split-layout metadata and renderer, bounded leader routes, regression source and import/audit tools (22 files). No inherited unmerged feature scope or copied predecessor implementation.
- iOS only; no version bump, model equations, graph entries, personal health storage, Android/Desktop changes or IPA.

## Implementation
- Byte-identical Android painted eye replaces the vector PDF, retaining a transparent 1536-by-1024, 3:2 asset for structure, fullscreen and retinal location.
- Calibrates cornea, lens and retinal-lining navigation points; numerical eye optics is unchanged.
- Adds a backward-compatible `splitCallouts` flag, default false when absent. Enabled for eye, ear, sensory, immune and endocrine plates; copied into retinal eye context and sensory lesson copies.
- Two independently measured rails: natural label width, capped at 24 percent per side; target x < 0.5 selects the left rail. Single-sided drawings keep their existing local column widths.
- UIKit measures localized labels using actual Dynamic Type fonts and wraps text. Labels retain 48-point minimum height, eight-point spacing, selected state and their existing actions/identifiers.
- Rail packing follows anchor order, moves overflow upward and sizes the containing scroll content to fit. Left labels face right and right labels face left, without reducing the artwork below half the available width for split plates.
- Leader paths start at the anatomy point and end on the image-facing label edge. Detour candidates stay in the target's half; invalid bounds return no ambiguous path.
- Uses the same zoom coordinate space in inline/fullscreen views and visual-order accessibility elements.
- Legacy eye import now delegates to the current bitmap importer. Retained gradient PDFs keep stable resource IDs after retiring the eye PDF.

## Verification
- `check-body-atlas-split-callouts.cjs`: original eye PNG bytes/dimensions/transparency, exact three opaque source markers, all five split owners, legacy decode default and retinal-context propagation. It is a static resource/source audit, not a native layout test.
- Existing painted-ear, retained-vector and retinal-cell PDF, overview, musculoskeletal, project structure, module flags and frozen base i18n/resource audits pass.
- Eleven changed Swift files pass grammar parsing under both conditional branches. Not Swift type checking.
- Eye source bitmap visually inspected. No synthetic browser layout is presented as the actual app.
- XCTest source covers 60 combinations of five split plates, English/Chinese, normal/accessibility text and 320/390/768-point widths; checks real UILabel measurement, rail independence/nonoverlap, image width, half-plane leaders and clearance. Also adds one-sided fallback, invalid input/bounds, old/new JSON decode and 26 bitmap/108 anchor fixtures.
- XCTest was not executed, as requested. Windows has no Xcode: native compilation, Asset Catalog processing, actual inline/fullscreen rendering, device/simulator operation and VoiceOver acceptance remain unverified. No IPA generated.

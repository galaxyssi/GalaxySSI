# Android #4365: Painted Innate Cells and Continuous Phagocytosis

## Review Scope
- Ports Android #4365 at `8ac01038b80a341c2c2f4912a455e834cd434daf`.
- Formal non-draft PR, base main. Predecessor iOS #4485 is merged; iOS #4486 (Android #4364) is pending and inherited.
- Review this increment against the final #4486 head. Its existing cardiac changes are a dependency, not duplicate implementations or new #4365 scope. Continue without waiting for its merge, as requested.
- iOS only. No version bump, graph, model equations, localization, personal-health or IPA changes.

## Implementation
- Replaces macrophage and neutrophil vectors with byte-identical transparent 1254-square painted resources and recalibrates four local feature anchors.
- Structure and simulation use the same macrophage asset. Other immune-cell resources and their 21 features are unchanged.
- Drives the native SwiftUI Canvas from the shared simulation phase instead of four static drawings. Uses source smoothstep easing for target approach, engulfment position/radius/opacity, fragment shrinkage and signal drift.
- Preserves the 360-by-200 logical viewport, source artwork bounds, four stage labels, accessibility identity and owner-scoped teaching context.
- Reuses the existing playback controls/timer, phase persistence, background and reduced-motion handling. No second animation clock or independent state.
- Updates current resource importer/audits and retains original catalog provenance separately from artwork source.

## Verification
- Painted innate audit passes: exact PNG bytes/dimensions/transparency, all four opaque feature anchors, exact source coordinates, unchanged remaining metadata, shared-phase integration and source-equivalent motion formulas.
- Immune audit passes: 12 plates, 25 local feature labels, 40 retained vector paths, two painted cells and resolved bilingual keys.
- Existing painted-heart audit and frozen full graph audit pass (313 entries / 192 mechanisms).
- iOS project, module-settings, frozen base resource/i18n and whitespace checks pass. Four changed Swift files parse under both conditional grammar branches; not type checking.
- Both painted resources visually inspected. No generated resource preview is represented as an app screenshot.
- Added XCTest source for within-stage changes, stage boundaries, finite phase handling, deterministic rewind, restored shared-phase frames and a 33-bitmap fixture retaining 119 canonical anchors plus four new local-feature pixel checks.
- XCTest not executed, as requested. Windows has no Xcode: native build, Asset Catalog processing, Canvas phase/rewind pixel output and device/accessibility acceptance remain unverified. No IPA generated.

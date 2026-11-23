# Android #4363: Tissue and Lymphatic Illustration Shading

## Review Scope
- Ports Android #4363 at `b8fbf1191367153af2824506df99bbc5c5bae56e`.
- Formal non-draft PR, base main. Continues without waiting for predecessor iOS #4484 (Android #4362), as requested.
- Dependency: #4484 is not yet merged at publication. Its existing commits are inherited in the main-based diff, not duplicate implementations or new #4363 scope. Review this increment against `73c51b8a42a1882a15125110d335a62eeda438cd`; synchronize main after #4484 merges.
- New scope: 23 updated PDFs, two artwork-provenance fields, current import entry points and gradient/resource audits. iOS only; no version, graph, model, localization, navigation, personal-health or IPA changes.

## Implementation
- Updates 14 tissue plates and nine lymphatic/immune section plates with source-equivalent shading while retaining all 646 original paths.
- Preserves asset names, viewports, 17 tissue hotspots, 30 lymph lesson features, 12 canonical links, stage maps and transport overlay routes.
- Extends the shared PDF converter for explicit nonuniform gradient stops and native shaded strokes. All 210 gradients retain exact source colors/coordinates; 11 strokes use PDF shading patterns with original widths, caps and joins.
- Records artwork provenance separately from original graph/lesson sources.
- Legacy tissue/lymph importers now delegate to the current converter and cannot overwrite current art with obsolete flat fills.

## Verification
- `check-body-atlas-tissue-lymph-art.cjs` passes: all source path geometry equals the original vectors; semantic packs unchanged; all 23 PDFs retain native shading, viewports, exact stop positions/colors and no raster substitution.
- Existing tissue and lymph graph/lesson/localization audits pass, including eight exact transport routes and 248 localized values.
- Independent Android SVG versus PDF raster comparisons pass for all 23 plates, mean absolute channel errors 0.1311-3.6334 on a 0-255 scale. All 23 resource renders visually inspected. These are not native app screenshots.
- Prior nervous/system, retinal-section and retinal-cell gradient audits still pass.
- iOS project, module-settings, frozen base resource/i18n and whitespace checks pass. No Swift source changes in this increment.
- XCTest not executed, as requested. Windows has no Xcode; native build, Asset Catalog processing, device/simulator layout and accessibility acceptance remain unverified. No IPA generated.

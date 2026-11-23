# Android #4347: respiratory and renal cell plates and teaching models

Ports Android merge `ee54cfd25d31e05eb34bd97f1557a404ae337b10` to iOS 15+.

## Scope
- Import all 12 original respiratory/urinary cell plates as vector-preserving PDFs (88 original paths), with all 25 local feature anchors, exact chapters and English/Simplified Chinese explanations.
- Keep the type A intercalated-cell and superficial umbrella-cell captions explicit. Contextual tissue and local annotations do not create new catalogue identities.
- Add the podocyte four-stage qualitative glomerular barrier drawing: all three layers remain present, a blood cell stays in the capillary, and stage-dependent filtrate arrows/slit diaphragms reuse existing playback and persisted selection. The scope note excludes filtration-rate estimation.
- Assign the single-interface Young-Laplace model only to `cell-type-ii-pneumocyte`: tension 5...35 mN/m (default 15), radius 50...200 micrometres (default 100), pressure `2000 * tension / radius` Pa. Compare the same tension at twice the radius, with half the pressure.
- Integrate the model with existing sliders, response curve, localized outputs, input restoration, reset, and public synthetic Agent context. Keep unrelated cells and personal Values excluded. Podocyte context is limited to matching active simulation/physiology state.
- Add accessible diagram descriptions and reuse existing reduced-motion, playback suspension and localization behavior. Import all 65 strings per language with Foundation placeholder adaptation.
- Preserve GalaxySSI branding, the existing app version and catalogue graph. No Android/Desktop implementation or packaging changes.

## Review boundary
This branch is synchronized with `main` at `30785e741957e0bd5f25f7c2e013fe275df888dd`, including the now-merged #4469 core-cell/sarcomere port. The merge retains both sets of plate lookup, playback, localized resources, context and test source. The base-to-head diff contains only this #4347 port, not a second copy of #4469. Each Android port remains a separate formal PR with base `main`.

## Verification performed
- `node apps/ios/tools/check-body-atlas-transport-cells.cjs`: passed; exact 12-plate/25-feature/88-path ownership, source, caption and coordinate audit, bilingual keys and PDF asset headers.
- Exact comparison to the pinned Android XML resources: 130 strings passed (placeholder adaptation only).
- All 12 PDFs rendered and contact sheet inspected; all 25 feature anchors fall on rendered artwork.
- `npm run check:ios`: passed (project structure only).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. These are not Swift type checks.
- Added XCTest source for Young-Laplace SI fixtures/bounds/ownership, plot coverage, localized context, dedicated plate lookup, subtype captions, saved inputs/stages and owner/screen isolation. Updated the superseded no-model assertion for type II pneumocytes. XCTest was not executed, per request.

No Xcode compilation, device/simulator rendering, VoiceOver acceptance or IPA is claimed on this Windows host. The PR is submitted as formal, not draft, with these limits disclosed.

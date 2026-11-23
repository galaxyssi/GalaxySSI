# Android #4350: sensory cells, retinal circuits and photon absorption

Ports Android merge `e533b182cc41df22e2e1a6291f7751e4848f8bb4` to iOS 15+.

## Scope
- Import 15 original neural/sensory cell plates and the retinal layer section as vector-preserving PDFs (171 source paths), with 34 bilingual feature explanations and three direct cell markers.
- Add the two canonical retinal bipolar and AII amacrine cell entries, in the same catalogue position, with exclusive cell mechanisms. Replace the generic retina mechanism with the dedicated four-stage vision mechanism. Preserve all other catalogue identities.
- Provide `retina-layers` and `retina-eye-context` views through the existing persisted illustration selector. Keep the eye-location artwork and its original metadata; default to the retinal section. Local layer explanations are distinct from canonical cell navigation.
- Add native selectable representative rod/cone ON routes. Keep rod bipolar -> AII -> ON cone bipolar relay separate from cone bipolar input; expose both bipolar/AII destinations only in the appropriate relay stage. Preserve the separate incoming-light and signal directions in the section artwork.
- Reuse playback, pause, previous/next, reset, saved stage, reduced-motion and preview suspension. Replace the retina's redundant simulation art/grid with the dedicated route diagram and reference link.
- Add the rod-only Poisson absorption example with one unitless input, lambda 0...5 in 0.01 increments (default 1). Compute absorption probability with `-expm1(-lambda)`, and zero-event probability with `exp(-lambda)`. This models absorption, not visual detection or a personal vision threshold.
- Integrate localized outputs, parameters, curve, reset, persisted inputs and both model sources. Place photon and alveolar-surface controls before their charts as in Android; omit empty-unit suffixes/axis parentheses.
- Scope retinal public Agent context to matching active simulation/physiology state and keep Values/unrelated owners excluded. Include feature titles only from the selected illustration, not the other retinal view.
- Add only the four exact external plate references used by this port (one NCBI book page and three PubMed papers). Import all 109 strings per language with Foundation format adaptation; preserve GalaxySSI branding/app version and Android/Desktop implementations.

## Integration and regression sources
Prerequisite #4472 merged into `main` as `a80b5e5122a867740c166829feff0dcbc4875493`. Its endocrine work is reused, not repeated as new #4350 work. Base is `main`; this is a formal, non-draft PR.

Correct the recently added immune/core/transport/digestive/endocrine XCTest fixtures to load the complete extended catalogue, rather than the deliberately frozen base-only helper. Keep the original helper unchanged for baseline/delta validation tests. Update the complete microscopic roster for the two added cell identities (107 cells and one fragment).

## Verification performed
- `node apps/ios/tools/check-body-atlas-sensory-cells.cjs`: passed; exact plates, captions, coordinates, view metadata, relay destinations and full static graph equality with Android #4350 (313 entries / 167 mechanisms).
- Exact Android XML localization comparison: 218 strings passed.
- All 16 PDFs rendered and contact sheet inspected; all 37 feature/navigation anchors land on rendered artwork.
- `npm run check:ios`: passed (project structure only).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. These are not Swift type checking.
- Added XCTest source for Poisson fixtures/complement/bounds/ownership, two-view restoration, relay-cell search/ordering/navigation, illustration-scoped public context and persisted single-parameter inputs. XCTest was not executed, per request.

No Xcode compilation, simulator/device rendering, VoiceOver acceptance or IPA is claimed on this Windows host.

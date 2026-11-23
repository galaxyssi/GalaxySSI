# Android #4349: endocrine structures, signal paths and negative feedback

Ports Android merge `7281138717425cc4a5fb905f65084de0c14141d5` to iOS 15+.

## Dependency and review scope
Prerequisite PR #4471 (Android #4348) has merged into `main` as `f1d72a1e3a10bda2a428dc354c7689e93d559061`. This branch reuses those actual commits without copying their implementation. The base-to-head diff contains only this #4349 endocrine port, not the preceding digestive-cell or pancreatic work. Base remains `main`; this is a formal, non-draft PR. Approval and native build acceptance are not claimed.

## New work for #4349
- Import 14 original endocrine-cell illustrations and four gland sections as vector-preserving PDFs (239 source paths), with all 37 bilingual feature explanations and four direct anatomical links.
- Preserve specific examples/captions: zona fasciculata, secretory-cell identity rather than diagnostic staining, ovarian follicle, thyroid follicle, posterior parathyroids, adrenal section, and pituitary lobes/stalk. Contextual neighboring cells do not create new identities.
- Replace four generic gland mechanisms with the exact dedicated pituitary, thyroid, parathyroid and adrenal four-stage secretion mechanisms. Preserve all existing microscopic identities and unrelated models.
- Add clickable four-node pathway views. Thyroid/parathyroid rows form the same directional loop layout; adrenal/pituitary rows remain two independent branches. Node selection pauses playback, updates the current stage/example, and exposes only that node's optional structural destination.
- Reuse persisted stage selection, previous/next/play/reset, reduced-motion and preview suspension. Replace redundant static simulation art/process grids for these owners; keep structural illustrations in the Structure view.
- Add the thyroid-only static dimensionless feedback example: drive 20...100 (default 80), gain 0...3 in 0.01 increments (default 1), output `drive / (1 + gain)`, reduction `drive - output`. It is not TSH, a hormone result, a reference range, or a prediction.
- Reuse localized parameters, curve, reset and input restoration. Put the thyroid quantitative panel after the pathway, and scope public Agent explanations to matching active simulation/physiology state. Exclude Values and unrelated owners.
- Import all 126 strings per language (English/Simplified Chinese), adapting format placeholders only. Preserve GalaxySSI branding and app version. No Android/Desktop implementation changes.

## Verification performed
- `node apps/ios/tools/check-body-atlas-endocrine-cells.cjs`: passed; exact assets/coordinates/captions/sources, four path definitions, destinations and complete static graph comparison with Android #4349 (311 entries / 164 mechanisms).
- Exact Android XML localization comparison: 252 strings passed.
- Rendered and visually inspected all 18 PDFs; all 41 feature/navigation anchors land on rendered artwork.
- `npm run check:ios` and `node apps/ios/tools/check-atlas-module-flags.cjs`: passed (project/settings structure, not an Xcode build).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. Neither is Swift type checking.
- Added XCTest source for feedback fixtures/conservation/bounds/ownership, branch-vs-loop layout, destinations, local explanations vs navigation, mechanism identity, saved stages/inputs and owner/screen-scoped public context. XCTest was not executed, per request.

No Xcode compilation, simulator/device rendering, VoiceOver acceptance or IPA is claimed on this Windows host.

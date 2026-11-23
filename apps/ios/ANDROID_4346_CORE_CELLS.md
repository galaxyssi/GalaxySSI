# Android #4346: complete core-cell plates and sarcomere teaching

Ports Android merge `40c28fba70c17ab4fad0a301799b0f202bc48b13` to iOS 15+.

## Dependency and review scope
Prerequisite iOS PR #4468 (Android #4345) has merged to `main` as `9426d0d6635a887a342cbe0af24c817d095c0eb5`. This branch reuses its existing feature decoder, labels and explanation dialogs; it does not copy or reattribute its immune-cell implementation. Base remains `main`, and the diff contains only the #4346 port described below. This is a formal, non-draft PR; approval or native build acceptance is not claimed.

## New work for #4346
- Import the remaining 18 original cell plates as vector-preserving PDFs (119 original drawing paths), with all 39 local feature explanations and exact source chapters/coordinates. Together with #4468 this completes all 30 core cell plate identities.
- Preserve catalogue identities, cell locations and organ/tissue/cell navigation. Contextual adjacent tissue does not become a new catalogue entry.
- Add four-stage skeletal-myocyte sarcomere teaching: Z-disc distance is 250 drawing units except contraction (180); relative length is 100%/100%/72%/100%. Thin filaments remain 86 units and thick filaments 136 units throughout.
- Reuse existing stage playback, restored selection, pause/reset, reduced-motion and preview suspension. Replace the static illustration on this owner's simulation page with the synchronized drawing.
- Provide localized stage accessibility descriptions, Z-disc labels, ratio, filament legend and limitations, including light/dark filament colors from Android.
- Include ratio and synthetic-example limitations only in matching skeletal-myocyte simulation/physiology Agent context. Keep Values and unrelated owner contexts excluded.
- Import all 83 strings per language (English/Simplified Chinese), adapting Java format placeholders to Foundation. Preserve GalaxySSI branding and iOS app version; no Android/Desktop source changes.

## Verification performed
- `node apps/ios/tools/check-body-atlas-core-cells.cjs`: passed; exact 18-plate/39-feature/source/coordinate comparison, 119 source paths, bilingual keys, 30 combined identities.
- Exact Android XML localization comparison: 166 strings passed, with format placeholder adaptation only.
- All 18 PDFs rendered; contact sheet inspected; all 39 feature anchors land on rendered artwork.
- `npm run check:ios`: passed (project structure only).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. Neither is a Swift type check.
- Added XCTest source for dedicated plate lookup, explanation routing, saved contraction stage, constant filament geometry and owner/screen-scoped context. XCTest was not executed, per request.

No Xcode build, simulator/device UI acceptance or IPA is claimed on this Windows host. These limitations are disclosed rather than turning the PR into a draft.

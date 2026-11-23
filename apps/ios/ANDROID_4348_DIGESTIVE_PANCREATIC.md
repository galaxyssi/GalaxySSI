# Android #4348: digestive cells and pancreatic secretion paths

Ports Android merge `c37bf1deaf377b1092972e64f8bfbc9e05eb225b` to iOS 15+.

## Scope
- Import 13 original digestive-related cell plates plus the human-islet overview as vector-preserving PDFs (104 paths). Keep all 27 localized feature explanations and four canonical islet-cell navigation markers, with exact source coordinates and captions.
- Distinguish local explanation dialogs from beta/alpha/delta/PP cell navigation. Retain the existing beta-cell plate and exclusive microscopic mechanisms; contextual structures do not add catalogue identities.
- Replace the pancreas and pancreatic-islet generic mechanism assignments with the two dedicated four-stage secretion mechanisms from Android. No catalogue entries are added or removed.
- Add independently navigable exocrine and endocrine route rows with the same stage highlights, source link and limitations. Keep both routes available throughout; the stages compare destinations rather than secretion timing or quantity.
- Add stage-selected beta/alpha/delta/PP cell rows with their illustrations, role descriptions and navigation. Reuse playback, reset, persisted selection, reduced-motion and preview suspension.
- Scope the bicarbonate mixing model to pancreas, pancreatic duct and pancreatic ductal cell only. Use synthetic added flow 0...4 mL/min (0.1 increments), concentration 20...120 mmol/L, base stream 1 mL/min at 20 mmol/L. Mixed concentration is `(20 + addedFlow * concentration) / (1 + addedFlow)`; total delivery is `20 + addedFlow * concentration` micromoles/min.
- Integrate parameters, response curve, reset, input restoration, localization and synthetic Agent context. Put the pancreas model below the secretion paths. Values and unrelated owner/screen contexts remain excluded.
- Permit only the three additional exact PubMed plate references used by Android, not arbitrary PubMed URLs. Import all 82 strings per language with Foundation format-placeholder adaptation.
- Preserve GalaxySSI branding, app version and Android/Desktop implementations. Base is `main`; this is a formal, non-draft PR.

## Verification performed
- `node apps/ios/tools/check-body-atlas-digestive-cells.cjs`: passed; all plates/features/markers/captions/chapters match the pinned Android source, and full static catalogue composition equals Android #4348 (311 entries / 160 mechanisms).
- Exact Android XML localization comparison: 164 strings passed.
- Rendered and inspected all 14 PDFs; all 31 feature/navigation anchor pixels fall on rendered artwork.
- `npm run check:ios`: passed (project structure only).
- Changed Swift grammar parsed in both conditional modes; `git diff --check` passed. Neither is Swift type checking.
- Added XCTest source for mixing fixtures/conservation/bounds/ownership, route highlights, islet stage roles, illustration navigation/explanations, mechanism identity, saved state, exact source trust and owner/screen-scoped context. XCTest was not executed, per request.

No Xcode build, simulator/device UI or VoiceOver acceptance, or IPA is claimed on this Windows host.

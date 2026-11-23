# iOS parity: Android #4344 complete system overviews

Base: main. Android source: #4344, merge 583bcc0f3ff45112db88220326322948defaafbf.

## Scope

- Add the original nervous, cardiovascular, testicular and ovarian overview
  schematics, all 23 landmarks, canonical routes and source references.
- Preserve dedicated child artwork (including the heart section and valve
  views), shared owner-context captions, labels, fullscreen and view selection.
- Add aorta, pulmonary-trunk and lungs to the cardiovascular category links.
- Validate overview references after the full extension graph is assembled.
- Add bounded example axon length (10-150 cm) and constant conduction speed
  (1-120 m/s) controls for cranial, spinal and peripheral nerve entries only.
  Preserve the potassium model for spinal-cord and ejection models for ventricles.
- Show transit time, the separate 10 cm time reference and the same response
  curve used by the numeric model. Restore inputs independently per entry.
- Keep public anatomy citations distinct from the teaching model reference,
  and exclude the model from Values and unrelated research previews.
- Import all ten English/Chinese strings per language. This is not a nerve
  conduction test, reaction-time prediction or personal measurement.

## Verification

- iOS structure, changed-source Swift grammar and whitespace checks.
- Original six overview PNGs remain byte-identical to Android #4332.
- New overview audit compares all four vectors' 23 anchors and exact canonical
  routes to Android #4344; the combined pack has 54 unique routes.
- Full bundled graph composition matches Android #4344: 311 entries / 158 mechanisms.
- Four PDFs rendered with Poppler and visually reviewed; all 23 landmarks
  intersect nonblank artwork. This is asset review, not native UI acceptance.
- Added XCTest source for all 14 category routes, dedicated child precedence,
  explicit chamber/nerve mappings, independent units/fixtures, source separation,
  bounds and public-context isolation. XCTest was not executed.
- No Xcode compilation, simulator/device validation or IPA is claimed on Windows.

This formal main-based iOS-only PR does not duplicate the preceding cardiac
feature in its change set.

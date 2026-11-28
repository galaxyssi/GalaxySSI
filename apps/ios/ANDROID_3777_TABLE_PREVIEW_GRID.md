# Android #3777: existing table-original preview follow-up

This independently based iOS follow-up addresses the grid and stale-preview gaps
in the previously merged iOS #3839. It does not claim completion of Android #3777.
Android reference: `69c58da3a`, especially `HealthStructuredOriginalPreview.kt`.

## Implemented

- Replace per-row disclosure groups with a vertically and horizontally scrollable
  grid, column letters, source headers, alternating rows and fixed cell geometry.
- Show at most 20 data rows, 12 columns and 512 Swift characters per cell. CSV/JSON
  import headers are column headings, not an extra numbered data row. XLSX keeps
  physical worksheet row numbers and the existing formula/cache display; nothing
  evaluates formulas. A bounded cell/header detail sheet avoids losing multiline
  values to three-line grid clipping. Clipped values end with an ellipsis.
- Preserve the default legacy sample contract (30/12/256) for existing callers.
- Parse the existing table bytes on a detached task. Propagate cancellation to
  that worker and check cancellation before/after parsing. Match the request,
  foreground scene, owner, dataset URL and freshly resolved batch identity/name/
  digest before publishing. Worksheet changes invalidate older requests.
- Cancel disables automatic restart until explicit reload. Navigation departure,
  backgrounding and runtime plaintext clearing drop the sample, sheet names,
  linked-record presentation, confirmations and selected cell. Encrypted records
  reads, linked export preparation and document export stay on their existing path.
- Keep original and linked ZIP save confirmation, fresh linked-reading scope,
  date-only provenance, clinical mapping and storage/recognition formats unchanged.

## Deliberately not claimed

The route still starts from an existing encrypted table-import batch. It does not
yet add generic CSV/JSON/XLSX to the image/PDF original library, preview arbitrary
JSON roots, stream an initial sample from files exceeding the clinical parser's
row/column limits, or change backup original kinds. Those are separate remaining
integration work, not hidden behind a new UI. Existing XLSX/CSV/JSON parsing limits
and parser behavior are retained. The character bound is Swift grapheme-based,
not Android's UTF-16 bound. Native parsing is not forcibly preemptible: cancellation
prevents publishing after it returns; it is not instant interruption or heap erasure.

## Verification boundary

Only JavaScript source contracts, negative source mutations, the existing iOS
project-structure check and whitespace checks are permitted for this work.
Four dedicated Swift fixtures cover limits, exact-boundary values, sparse source
rows/formula caches and configuration bounds. They are authored and registered,
not executed. No Swift compilation, XCTest execution, device, simulator, UI,
storage fault, parser execution, picker, CI, IPA or live acceptance evidence is
claimed. Source checks cannot establish Swift typing or visual/runtime correctness.

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

## Raw original-library extension

CSV, JSON and XLSX can now be selected in the original library without clinical
mapping. They use the existing authenticated/encrypted original index and files,
removal, exact-byte single-save, ZIP export and portable backup paths. A new
`structured` kind is validated against its canonical extension and previewable
content on storage/restore. Truncated display names are not used to recover the
format. Existing `image` and `pdf` raw values stay unchanged; older clients that
do not know `structured` cannot read these newer archives and must be upgraded.

The Files tab includes both PDFs and structured originals. A new foreground-only,
request/owner/dataset-scoped worker previews the authenticated original, rechecks
its exact indexed selection before publishing, and clears on removal/index events.
The existing parent owns explicit raw-save/removal confirmation. Empty JSON roots
and worksheets show an empty state. JSON root objects, arrays and scalars are
supported, preserving raw numeric lexemes, duplicate key rows and source order.
Foundation validates JSON syntax; a delimiter-aware scan extracts already-valid
raw fragments rather than decoding numbers into floating-point display values.
CSV reuses the existing parser in a separately bounded sample mode, including its
first source record. XLSX uses the existing ZIP/XML readers with a preview-only
21-nonempty-row lookahead and 16,384-column bound. Clinical import still has its
existing 500-row/64-column policy, header requirements and formula consent.

Both the recognition enqueue API and worker reject structured originals; the
recognition/visit-document pickers exclude them. Report-linked exports classify a
structured original as mismatched instead of treating it as a PDF. Backup restore
uses the stored canonical extension plus exact content/size/digest validation.

## Remaining differences and verification limits

Input is limited to 1 MiB (Android's text-preview budget is 2 MiB). Existing XLSX
ZIP expansion/shared-string/cell budgets still apply. Preview-only CSV/XLSX tails
after the lookahead are not validated or described as fully imported; original
bytes are kept intact. JSON validation can reject Foundation-unrepresentable
numbers despite valid JSON syntax. Nested JSON uses raw fragments rather than
Android's six-field summaries. The character bound is Swift grapheme-based,
not Android's UTF-16 bound. Native parsing is not forcibly preemptible: cancellation
prevents publishing after it returns; it is not instant interruption or heap erasure.

## Verification boundary

Only JavaScript source contracts, negative source mutations, the existing iOS
project-structure check and whitespace checks are permitted for this work.
Four grid Swift fixtures cover limits, exact-boundary values, sparse source
rows/formula caches and configuration bounds. They are authored and registered,
not executed. Six more authored raw-original fixtures cover JSON lexemes/roots,
CSV quoted records, large sparse worksheet sampling, input rejection and encrypted
storage/reopen/type/recognition exclusion. They are also not executed.
No Swift compilation, XCTest execution, device, simulator, UI,
storage fault, parser execution, picker, CI, IPA or live acceptance evidence is
claimed. Source checks cannot establish Swift typing or visual/runtime correctness.

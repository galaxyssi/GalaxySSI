# Android Health Structured Import

This increment implements the CSV and JSON paths of health screens h09, h10 and
h26. XLSX remains a separate adapter to be implemented against this same mapping
and review contract. It is not advertised as an implemented extractor. The full
32-screen health goal remains open.

## Storage And Execution Contract

- Import files through the existing native Record Center. Original bytes enter
  the existing private streaming-encrypted archive, retaining their SHA-256.
- CSV uses `com.univocity:univocity-parsers:2.9.1` (Apache-2.0), not string splitting.
  JSON uses Android's streaming `JsonReader`. Neither path invokes OCR, a remote
  provider, Desktop, a formula evaluator, or external URLs.
- UTF-8 and BOM-marked UTF-16 inputs are supported. CSV detects comma, semicolon
  and tab separators. JSON input is an array of flat row objects, not a backup.
- Schema 3 adds individually encrypted row and batch payloads to the existing
  observation database. Schema 1 and 2 upgrades are additive; original-file
  schema and encrypted original bytes are unchanged.
- Source rows are staged before mapping. No measurement is saved during file
  parsing or preview validation. A task returns to column review after restart.
- Column mapping, units, complete timestamp format and timezone are explicit.
  Ambiguous aliases are not selected automatically. Invalid and missing values
  do not become zero. Date-only values are not silently assigned a time.
- Local timestamps in daylight-saving gaps or overlaps require an explicit ISO
  offset. Source units are retained without a medical conversion guess.
- Existing six numeric metrics are supported. Formula strings, ranges,
  comparisons, nested JSON and qualitative results are visible invalid rows,
  never fabricated numeric results. A broader qualitative metric catalog remains
  part of the original goal, not a claim of this increment.
- Preview is keyset-paged, 30 rows at a time. Validation, save and undo update
  records and durable cursors in 30-row transactions. There is no fixed total-row
  truncation. Working-file/cell/column bounds reject unsupported input while
  retaining the encrypted original.
- Save requires explicit source ownership/value/unit/time confirmation. Changes
  to mapping invalidate preview results and stale confirmation revisions.
- A stable original/row identity and normalized duplicate keys avoid repeated
  records across reimports and concurrent saves. A row arriving after validation
  is rechecked in the save transaction.
- Undo follows the batch's creation ledger, not a broad source/date deletion.
  Preexisting duplicates and subsequently edited records are retained. Soft
  deletion preserves the existing encrypted revision history.
- Process termination can replay only the unfinished chunk. Normal failures
  remain visible for explicit retry; they do not start a hot retry loop.
- Source headers, cells, mappings and filenames are not WorkManager input data.
  The native page drops views and dialogs when backgrounded. User originals are
  not exported or written into general Agent memory.

## Focused Acceptance Matrix

Use unique test database names and private original roots, then clean only those
fixtures. Never insert synthetic measurements into the user's health database.

| Area | Required evidence |
| --- | --- |
| CSV reader | Quoted separators/newlines, escaped quotes, BOM/Unicode, malformed encoding, missing/extra columns, formula preservation |
| JSON reader | Scalar types, null, column union, nested/non-object errors, duplicate keys, trailing content, cell/column bounds |
| Mapping | All six metrics, ambiguous aliases, explicit units, strict dates, timezone/DST, missing/invalid classifications |
| Persistence | Encrypted and authenticated rows/batches, ordered pagination, additive schema-2 migration |
| Recovery | Reopen during parsing, validation, save and undo; do not duplicate committed rows |
| Transactions | Inject a save failure mid-chunk; measurements, ownership and cursor all roll back |
| Deduplication | Same source/row across jobs, duplicate rows within one batch, concurrent arrival after validation |
| Undo | Keep preexisting duplicates and later user edits; remove only unchanged records created by this batch |
| File queue | Actual private FileProvider URI through the import pipeline, cancellation, deleted external source after encrypted copy |
| Native UI | Unlocked Record Center -> mapping -> date/unit selection -> paged preview -> explicit save -> undo; background/return and rotation |

Build, device and UI results must be recorded separately. A locked-device store
test is not proof that the visible page matches the supplied design. Actual
unlocked UI acceptance, camera hardware/automatic paper boundaries, XLSX and the
other remaining health screens must not be marked complete from this matrix.

## Recorded Results

The 0.1.7.19 / 1432 increment passes 123 focused JVM tests and 78 non-visual
instrumentation tests on Galaxy Tab Active3 (SM-T575). Device coverage combines
the prior manual/recognition/photo-draft tests with 18 structured-store tests,
seven JSON-reader tests and five real file-queue pipeline tests. No synthetic
measurements are written into the user's health database.

An initial 27-test structured-device attempt had five fixture failures: test
files were outside the existing FileProvider cache roots. Moving those isolated
fixtures into the already-declared health capture cache fixed the tests without
widening provider access. The later 78-test regression passes all five pipeline
cases. Initial and regression logs are retained under ignored Android build
output, rather than describing the failed attempt as a successful run.

The tablet still reports that its keyguard is showing. Native visible-page,
rotation and background/return acceptance for the new table UI therefore remain
unverified. No keyguard bypass or actual camera capture was attempted. These
results are not a claim that every health screen or the repository's full CI
suite is green.

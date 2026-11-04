# Android Health Measurement Exports

## Scope

The native data/file hub separates measurement import/review, original-only
import, original-file browsing/export, measurement export and export history.
This increment implements scoped CSV, JSON and XLSX measurement files for the
Android V2 h25/h28/h29/h30/h31 flow. It is not a complete backup, PDF report,
password-portable package, restore workflow or automatic sharing facility.

Export configuration intersects calendar dates, metric IDs and an optional
primary-original ID. It includes only confirmed, non-deleted `self` observations.
Dates are half-open, timezone-aware boundaries, including DST days. Notes, report
reference text, OCR text/boxes and worksheet names are excluded by default;
including them requires an explicit opt-in. Provenance IDs and hashes remain.
No health data is sent to an Agent or Provider by this feature.

## Frozen Preview And Durable Tasks

`HealthRecordStore.exportChunk` returns at most 30 observations and one bounded
lookahead. Subset queries merge bounded indexed metric streams rather than
decrypting all records. Preparation persists individually encrypted snapshot
rows in `health_record_exports_v1.db`, with sequence, observation ID and revision
bound into authenticated associated data. Scope and task metadata are encrypted
separately. No full-history array enters an Activity Bundle or WorkManager.

Preparation compares metric change tokens before and after its scan. A change
requires a fresh preview rather than silently mixing revisions. The completed
preview is immutable: generation uses its snapshot even when the live observation
is later edited or deleted. Preview and confirmation timestamps are separate.
The summary distinguishes observations from component results, exposes source
warnings, and marks file-size estimates as approximate, not upper bounds.

Original availability and evidence-hash mismatches are recorded **at preview**.
They do not make independently confirmed measurements unexportable. The original
detail page offers linked measurement export even when original bytes are gone.
These files explicitly exclude original file bytes; exact photo/PDF/table export
remains a separate original-library operation.

Tasks persist `PREPARING`, `REVIEW`, `QUEUED`, `GENERATING`, `GENERATED`, `SAVED`,
`FAILED` and `CANCELLED` states. Each phase has an opaque dispatch ID, and every
execution attempt has an isolated artifact/key identity. Stale failures cannot
stop a newer retry. Interrupted preparation rebuilds its snapshot; interrupted
generation restarts from the frozen snapshot using a new key. A cancelled task
is not revived by a late worker. WorkManager runs unique dispatch-scoped jobs,
with an actual foreground export notification and explicit startup-failure state.
Startup recovery pages active tasks; terminal WorkManager states are reconciled
in the native task view rather than leaving an endless spinner.

## Formats

- CSV is UTF-8 with BOM, quoted fields and CRLF records. It uses long-form rows:
  blood-pressure systolic/diastolic/optional pulse share one observation ID, and
  pulse has its own `bpm` unit. Bounds, ranges and qualitative results never
  acquire an invented exact numeric value. Decimal notation and large integer
  precision are retained as text.
- Spreadsheet-facing CSV prefixes potentially executable leading cells with a
  tab inside the quoted field. `csv_tab_escaped_fields` identifies affected
  columns; a schema-aware reader can remove exactly that one prefix to recover
  original text. Leading whitespace/BOM and full-width formula starters are
  considered. This follows the Excel-oriented mitigation described by
  [OWASP CSV Injection](https://community.owasp.org/attacks/CSV_Injection), not a
  universal safety guarantee for every spreadsheet or subsequent transformation.
  Prefer literal XLSX cells for spreadsheet use or JSON for exact programmatic data.
- JSON streams the `galaxyssi-health-records`, version 1 envelope, scope,
  timestamps, nested observations, preview source status and final count. This
  schema is **not** a complete-backup manifest or a generic restore input.
- XLSX uses fastexcel 0.20.2 inline-string cells, no formulas, no shared-string
  accumulation, bounded row flushing and worksheet rollover at Excel's row limit.
  It includes a metadata sheet and stores exact values as text, avoiding Double
  conversion. Oversized cells fail explicitly rather than being truncated.

## Private Generation And Explicit Saving

CSV/JSON/XLSX and original-only ZIP now share `HealthPrivateExportFile`, retaining
the existing original-archive AES-GCM-HKDF streaming parameters and AAD contract.
Generation writes encrypted partial output, authenticates it, fsyncs and publishes
the completed private artifact. Cleartext output is streamed; there is no
long-lived plaintext staging file. Per-attempt data keys are wrapped by the
existing Android Keystore-backed storage cipher and wiped after use.

The user must acknowledge unencrypted public output before generation. A finished
private artifact is `GENERATED`, not `SAVED`. The native save command uses the
system document picker with the selected format/MIME. Copying verifies both full
plaintext byte count and SHA-256, and the destination must close successfully
before marking `SAVED`. A failed destination keeps the private artifact retryable
and attempts to delete partial public output. No file is uploaded or shared.

## Original-Only Import

The data/file hub can save originals without recognizing them. A persisted
`original_only` flag stops the import after the exact encrypted copy, before
image inspection, OCR or table parsing. Older jobs default to the existing
recognize/review behavior. Measurement import remains distinct and explicit.

## Acceptance Boundaries

This increment includes policy/format JVM tests and isolated Android store,
pipeline and native configuration tests. Final execution results and installed
artifact evidence are recorded in the PR and the screen acceptance ledger.
Synthetic observations and originals use unique test databases/directories;
they are never inserted into the user's health archive.

Final validation on 2026-11-04 for Android 1437 / 0.1.7.24:

| Evidence | Result |
| --- | --- |
| Offline app/test-APK build | Passed |
| Focused JVM regression | 230 tests, 31 suites, zero failures/errors/skips |
| Tab Active3 non-visual regression | 191 tests passed in 112.735 seconds; 24 new export cases |
| Unlocked native UI/lifecycle regression | 21 tests passed in 19.693 seconds, no skips; five new export/hub cases |
| Visible screenshots | Native data/file hub and measurement configuration inspected; no overlapping text/controls |
| Repository and Desktop structure checks; whitespace | Passed |
| Cover installation | Version 0.1.7.24 / 1437, no reset/uninstall |

The installed debug APK SHA-256 is
`78b4caa29b806a0084d79dffac0ca700a2b1840c891f9bbbaec4426e36f98eb6`.
Ignored build evidence includes `health-record-export-final-validation-5.log`,
`health-record-export-device-tests-final.log`, `health-record-export-ui-tests-final.log`,
`health-data-files-final.png` and `health-record-export-final.png`. Earlier failed
attempt logs remain available; they are not substituted for the final results.
XLSX verification reads the ZIP64 central directory and also passes the App's
authenticated package preflight and actual workbook reader on Android.
UI acceptance covers configuration, format/opt-in persistence, background view
cleanup, confirmation-to-configuration navigation, history cursor restoration
and the native data hub; it does not exercise a populated user export or SAF save.

Parent PR #3692's full Android CI still has five existing Agent catalog/state/
intent/evidence regressions (7,917 tests, five failures, six skips). Its repository,
Windows package, Desktop smoke and core-regression checks pass. The focused
results above do not assert that full repository CI is green.

Still required: populated native preview/consent/SAF-provider and foreground-worker
process-death acceptance; large-history/large-export resource benchmarks; public
password-protected files; report PDF; combined record/original backup with link
manifest; complete restore/rollback; task deletion under health privacy controls;
secondary duplicate-source associations; and final design-wide acceptance.
The exported long-form CSV/custom JSON schemas are not advertised as automatic
round-trip imports or substitutes for the h32 restore workflow.

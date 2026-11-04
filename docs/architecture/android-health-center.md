# Android Health Center

The user-supplied GalaxySSI Health Android V2 design contains 32 screens. It is an
interaction specification, not a dataset. Fictional names, measurements, scores,
device connections and generated analysis must never be installed as user data.

## Increment 1: Manual Measurements

- Native entry in My Agent > Common, with an isolated Activity back stack and no
  bottom navigation tabs.
- Empty state and a real overview backed by confirmed observations only.
- Blood pressure components in one observation; optional pulse; glucose, weight
  and heart-rate entry with explicit units, time and measurement conditions.
- Encrypted drafts, validated save, duplicate detection, optimistic revision
  checks, record details, revision history and deletion from current records.
- Indexed keyset pagination, 30 observations per page. Only the displayed page
  is decoded; the UI does not build the complete history in memory.

`HealthRecordStore` uses a separate private SQLite database with WAL, transactions
and per-row Android Keystore AES-256-GCM payload encryption. Health measurements,
notes and drafts are encrypted; record IDs, metric type, measurement timestamps,
revision numbers, deletion flags and a keyed HMAC deduplication digest remain indexing
metadata. This is field encryption, not whole-database SQLCipher encryption.
Associated data binds a payload to its database, identity and revision. Binary
plaintext buffers are wiped after encoding/decoding. Platform TextViews and JSON
Strings necessarily contain transient plaintext while displaying records.

Backgrounding drops health views and editor references. Foregrounding reloads
the current screen from storage. Draft fields are not placed in saved-instance
state. No health record is copied to the generic Agent transcript, memory,
Desktop, contacts or cloud providers by this increment.

Deleting a measurement hides it from current records while retaining encrypted
audit revisions. It is not a permanent erasure of health history. A separate
explicit privacy/erase flow remains to be implemented.

## Increment 2: Local Originals And Recognition Review

The native Record Center accepts camera captures and document-picker image/PDF
imports. Imports are persistent WorkManager jobs with opaque IDs only. Source
URIs, filenames, OCR text, progress payloads and page checkpoints are encrypted
in a separate private catalog. Copying, image decoding, PDF rendering, local
ML Kit recognition, parsing and database access run off the UI thread.

Originals are preserved byte-for-byte, with SHA-256 verification on explicit
export. Each original uses a random 256-bit key wrapped by the existing
Keystore-backed storage cipher, and Tink AES-GCM-HKDF streaming encryption with
64 KiB authenticated segments. A private read-only ContentProvider offers a
seekable decrypting descriptor so PDF rendering does not require a long-lived
plaintext temporary document. The catalog and files remain distinct from
general Agent memory, chat, contacts and Desktop storage. As with measurements,
catalog IDs, import states, timestamps and linkage indices are indexing
metadata, not encrypted SQLCipher pages.

Camera apps first write a temporary private cache file, and the shared cropper
also uses a transient private crop file. Successful import encrypts the former
and removes it; successful crop persistence encrypts the latter and removes it.
These staging files are not public gallery copies, but this increment does not
claim that plaintext never touches private cache. Interrupted captures can be
resumed while their cache file remains available.

Images are sampled to a bounded recognition working size without changing the
stored original. PDFs are recognized one page at a time; committed pages and the
next-page cursor form one transaction. OS interruptions can resume, whereas
explicit cancellation is sticky until the user requests retry. Unsupported file
formats can be retained as originals, but are visibly marked as having no
measurement extractor. CSV/JSON mapping was absent in this increment and is added
in increment 4 below; XLSX is still pending.

Recognized suggestions retain their page, source text, normalized boxes and
original hash. The supported subset is blood pressure, glucose, weight, pulse,
total cholesterol and hemoglobin. Unknown units and measurement time stay
unset. Comparators, numeric ranges, reference rows and ambiguous device display
matches are not silently reduced to point observations. Users can inspect the
original, correct fields, confirm ownership/units/time and then save each item.
No extraction writes a confirmed measurement automatically. A keyed evidence
index prevents the same source candidate being saved again after re-recognition.
Candidate identities include the extracted content and source region, not OCR
line-order positions, so reordering lines cannot redirect an earlier saved item.
Rows with multiple possible units remain unspecified until user verification.
The observation schema is upgraded additively from version 1 to version 2.

The original library and import queue use 30-item keyset pages; candidate review
uses 20-item pages and raw text uses 80-line pages. Associated observations retain
30-item indexed pagination. Progress-only updates rebind the existing task view
instead of rebuilding the ScrollView. Backgrounding dismisses previews and
dialogs and removes decrypted native views. Missing original bytes are reported
without deleting the associated measurements. Reimporting the same bytes can
restore a missing original under the same logical identity.
Repair also retains the original filename, MIME type and uncropped-parent link.

Original details expose hash, size, import time, related measurements, native
pinch/drag image viewing, PDF page viewing and explicit system-document save.
Cropping creates a separate encrypted derivative linked to the uncropped
original. Removing original bytes is distinct from deleting measurements and is
not a full privacy erase.

This increment does not yet implement the custom in-app multi-page camera,
batch page ordering, library thumbnail/filter/batch-selection modes, structured
import, trend charts or the remaining health screens. Its camera entry uses the
system camera application rather than claiming the complete h06 design.

## Increment 3: Native Camera And Ordered Photo Drafts

`HealthCameraActivity` implements a foreground-only rear Camera2 preview, an
explicit shutter, optional device-supported fill light, report/device modes and
an ordered native photo-collection page without bottom tabs. Gallery images can
enter the same collection flow. Camera access is closed on pause; backgrounding
clears thumbnails, dialogs, counters and the preview surface. Recents screenshots
are disabled for this Activity where Android supports the API.

The native camera's JPEG bytes go directly to encrypted original storage on a
background executor and are wiped afterwards. It does not create the external
camera's plaintext staging file. Full supported JPEG capture resolution is
preserved; thumbnails and quality inspection use bounded decoded working sizes.
EXIF orientation is applied for inspection. Laplacian detail, brightness and
image dimensions provide explicitly tentative readability hints, never medical
judgments or promises that OCR will be correct. Original bytes are not silently
rotated, cropped or recompressed. Manual crop/straighten uses the shared editor
and keeps the uncropped encrypted parent.

Capture batches and individual page order/quality rows are encrypted records in
catalog schema 2, added by a non-destructive schema-1 upgrade. Page lists use
20-item indexed cursors, not one full-draft JSON. Users can move, remove, retake
or crop pages before submission. Retaking replaces a draft page in its existing
position; removing a draft page does not silently delete archived originals.

Preparation only copies/checks originals and finishes as `CAPTURE_READY`; it
does not run OCR or write measurements. Explicit submission atomically verifies
all current pages and marks each recognition job queued with the final document
order. Failed or missing pages roll back the entire submission. Editing is then
closed. A document's page order is distinct from the physical page number of
each original. Both are retained in source evidence. Preparation and recognition
have separate unique WorkManager identities and an explicit phase input, so a
late preparation worker cannot consume the recognition handoff. Recovery uses
the persisted phase. Cancelled/deleted draft pages cannot be reactivated by that
recovery query.

Camera geometry follows the sensor/display orientation and centers an
aspect-preserving preview rather than stretching it; see the
[Android Camera2 preview guidance](https://developer.android.com/media/camera/camera2/camera-preview).
The 0.1.7.18 / 1431 implementation builds successfully and passes 95 focused JVM
tests and 48 non-visual device tests on Tab Active3. The latter include 15 photo
draft transaction/migration/ordering tests and two camera close/error callback
tests that never open the camera. The close/error tests ensure a capture outcome
is delivered even when its surface generation becomes stale after backgrounding.
Mode changes from another database connection cannot reopen a submitted batch.

A separate 60-test device attempt had 12 UI/recreation failures while the system
reported that the keyguard was showing. Those logs are retained; they are not
accepted as successful visible-UI verification. Unlocked native-page, crop and
foreground lifecycle checks must be rerun, rather than weakening their assertions
or bypassing the lock screen. This is not a claim that the full device suite is
green.

Actual camera start/focus/light/rotation and photographed-frame acceptance still
require an unlocked device and user-authorized hardware tests. Automatic paper
boundary detection is not implemented; the displayed corner frame is an
alignment guide, not a claim to detect paper edges.

## Increment 4: Structured CSV And JSON Review

The Record Center now routes CSV and flat-row JSON arrays into native column
mapping instead of OCR or the unsupported-original path. Original files stay
encrypted and byte-faithful. A 30-row paged preview shows valid, duplicate,
missing and invalid rows separately. Users choose the metric, column mapping,
original unit or unit column, strict timestamp format and timezone. Missing
values are not filled with zero, formulas are not evaluated, and date-only or
ambiguous local times are not silently completed.

Observation schema 3 adds encrypted batch and row payloads with indexed
checkpoints. The existing schema-1/schema-2 observations, drafts and audit
history are retained. Validation never writes measurements; explicit ownership,
value, unit and time confirmation authorizes saving verified valid rows.
Source evidence identifies a structured source row rather than pretending it
was an OCR page. Reimports and rows arriving concurrently after preview are
deduplicated transactionally.

Validation, save and undo advance in 30-row transactions. Observation writes,
batch ownership and cursor progress share the same database transaction.
Phase/revision-specific WorkManager identities prevent a finishing validation
worker from swallowing or consuming the save handoff. Startup recovery resumes
only interrupted active work; recorded failures require explicit retry. Batch
undo removes only unchanged records created by that batch, retaining existing
duplicates, later user edits and encrypted audit history.

CSV uses uniVocity parsers 2.9.1 (Apache-2.0), and
JSON uses Android JsonReader. Parsing and database work stay off the main thread;
views and source dialogs are dropped in the background. Neither extractor sends
health data to an Agent, Desktop or cloud. Working bounds are 64 MiB per source,
256 columns, 16,384 characters per cell and 65,536 characters per row. They are
explicit rejection limits, not silent truncation or a fixed total-row budget.

This is the CSV/JSON subset of h09/h10/h26, not completion of every structured
format or all 32 screens. XLSX sheet/date/formula-cache provenance, the broader
qualitative metric catalog, and unlocked native-page acceptance remain pending.
See [the test matrix](../testing/android-health-table-import.md).

The 0.1.7.19 / 1432 increment passes 123 focused JVM tests and 78 non-visual
device regressions on Tab Active3, including additive schema upgrades, real
CSV/JSON file-queue imports and durable save/undo recovery. Five initial
FileProvider fixture-location failures were corrected without broadening the
provider's roots. Native table-page acceptance remains pending because the
tablet reports an active keyguard; no lock-screen bypass was attempted.

## Increment 5: Encrypted XLSX Worksheet Review

XLSX sources now enter the same encrypted file queue and explicit mapping,
validation, confirmation and batch-undo contract. Before reading observations,
users select an actual worksheet and text header row. Hidden sheets are marked,
and the workbook's 1900/1904 date system is retained. Numeric serial dates require
the Excel date mode; whole-day values additionally require an explicit clock
time. The preview shows the interpreted time before saving, without discarding
the source notation.

Formula evaluation and macros remain disabled. Cached formula results require
separate consent; missing caches remain missing. Saved evidence retains the
worksheet, physical row, cell address, expression and unrecalculated cached
value. Committed batches cannot be redirected to another worksheet. Revision-
bound reading checkpoints reject late writes after cancellation or replacement.

The existing authenticated seekable decrypting channel feeds Commons Compress
and the pinned fastexcel reader directly, without plaintext scratch files. ZIP
and XML validation imposes explicit source/expanded-size and metadata bounds,
checks entry integrity, and rejects document declarations and macro packages.
Queue labels reflect actual read/validation/save/undo progress. Active progress
updates do not repeatedly decrypt previews, count all rows or rebuild the page.

This is another subset of h09/h10/h26, not completion of the complete health
design. ISO-typed XLSX date cells remain an explicit interoperability error;
numeric Excel dates and text timestamps use separate supported paths. Visible
worksheet/mapping-page acceptance still requires an unlocked tablet. See the
[XLSX test record](../testing/android-health-xlsx-import.md) and the complete
[32-screen acceptance ledger](android-health-screen-status.md).

The 0.1.7.20 / 1433 increment is cover-installed on Tab Active3 and passes
141 focused JVM tests plus 106 non-visual device tests. Synthetic fixtures remain
isolated from the user's archive. The tablet's active keyguard still prevents
visible-page acceptance; no camera hardware was opened. Full-repository CI is
not claimed green while the parent branch retains its five Agent test failures.

## Following Increments

Each independent feature is delivered as a separate pull request, with a new
version and focused validation before claiming completion:

1. Native camera hardware/device-matrix acceptance, automatic paper-edge
   detection, and original-library thumbnail/filter/batch-selection modes.
2. XLSX ISO-typed date interoperability and unlocked structured-import UI
   acceptance; keep existing numeric-date/formula provenance checks intact.
3. Metric catalog, time-window/source filters and true, gap-aware trend charts.
4. Original-file library, export configuration, save/share and verified backup
   restore with transactional merge and attachment integrity checks.
5. Personal profile, scoped health permissions, explicit erase and reminder
   preferences, deduplication/cooldown and notification delivery.
6. Health platform/BLE adapters with actual capability and synchronization
   status, not simulated connected devices.
7. Consent-scoped AI interpretation and versioned reports citing actual records.
8. Educational body exploration, clearly separate from personal measurements.

Screens from later increments are not exposed as fake working actions. Medical
interpretation and default clinical thresholds are not implemented in either
the manual-entry foundation or the recognition-review increment.

## Verification

Domain tests cover missing data, numeric formats, units, time, conditions,
revision identity and duplicate normalization. Device tests use isolated database
names and verify persistence, encryption, authenticated identity binding,
pagination, drafts, conflicts, deletion and corruption behavior. No private
health data or remote providers are needed for these tests.

The first increment was built and installed on Galaxy Tab Active3 (SM-T575),
version 0.1.7.16 / 1429. Focused JVM validation passed 27 tests (12 health-domain,
10 control-center grouping/routing/render-cache and 5 backup-field regressions).
All 12 device tests passed (9 isolated-store tests and 3 native UI/lifecycle
tests), including a 125-observation pagination fixture. Native entry, manual
field units and system-back destinations were also checked on the device.
No fictional measurements were saved in the user's health profile. These results
do not claim completion of the remaining design screens or a full Android suite.

The recognition increment was installed over that version on the same Tab
Active3 as 0.1.7.17 / 1430. Its validation passed 87 focused JVM tests, 36 health
device tests and 9 shared attachment-editor device regressions. Device coverage
includes the real camera-file import/OCR pipeline, a two-page encrypted PDF resumed from page 2,
random access across encrypted segments, ciphertext tampering/truncation/key
swapping, cancellation cleanup, sticky cancellation, 125-job recovery pagination,
35-original library pagination, 65-associated-measurement pagination, source
deduplication, isolated schema-1 migration and native UI/background lifecycle.
Native Record Center and empty original-library screenshots were inspected.
No synthetic health measurements or originals were placed in the user's archive;
test databases and original roots used unique isolated names and were removed.

This is focused verification, not a claim that every camera app or every health
screen has passed end-to-end acceptance. At the recognition increment's original
verification time, its parent CI had five existing Agent routing/state regressions
(native-tool catalog, process state, two task-intent cases and the untrusted-evidence
boundary), outside that increment's changes, and a backend tool-evidence diagnostic-log
expectation failure. At increment 4 verification, PR #3687's repository, Windows
package, Desktop smoke and core-regression checks pass; its Android gate still
reports the same five Agent failures. These focused health results do not claim
that the repository's full CI is green.

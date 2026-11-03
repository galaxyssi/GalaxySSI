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
measurement extractor; CSV/JSON/XLSX mapping is not implemented here.

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

## Following Increments

Each independent feature is delivered as a separate pull request, with a new
version and focused validation before claiming completion:

1. Complete custom camera, multi-page selection and original-library filters.
2. Structured CSV/JSON/XLSX import with mapping, conflict review and batch undo.
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
screen has passed end-to-end acceptance. The parent PR's full CI remains blocked
by five existing Agent routing/state regressions (native-tool catalog, process
state, two task-intent cases and the untrusted-evidence boundary), outside this
increment's changes. The parent backend gate also has one existing tool-evidence
diagnostic-log expectation failure. Repository/i18n and Desktop structure checks
pass locally; these focused results do not claim all repository CI is green.

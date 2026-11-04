# Native Original Library And Explicit ZIP Export

This increment implements original-library browsing and original-file export
from h27, plus the original-only portion of h29-h31. It is not measurement
CSV/XLSX/JSON export, a complete health backup, password-protected export,
automatic sharing or backup restore.

## Browsing And Selection

- A separate native Activity replaces the old filename-only library route.
  Existing library entry points resolve to this page; original details remain
  separate from observation details and observation deletion.
- Grid/list modes, imported-date intervals and image/PDF/table/other filters
  operate on indexed metadata and 30-row keyset pages with one lookahead.
  There is no full-history decrypt/filter list or OFFSET paging. Missing-byte
  originals remain visible as missing, not silently removed from the catalog.
- Original schema 3 adds a type index and export/selection tables. Schema 1/2
  upgrades stream and authenticate existing metadata to backfill types inside
  the additive upgrade transaction. No archive reset or attachment rewrite is
  used. Migration runs where the background store is opened, not as UI work.
- Images use orientation-aware bounded decoding; PDFs render only the first
  page from the existing authenticated seekable descriptor. Thumbnails are
  at most 192 pixels on either edge, decoded with at most two workers. Unknown
  formats retain file icons rather than fabricated previews. No plaintext
  thumbnail or source scratch file is created.
- Backgrounding cancels queued thumbnail work, drops result views and clears
  mutable thumbnail pixels before recycling them. Late results are discarded.
  Filter/mode/cursor/selection identities survive recreation, not decoded images
  or filenames in saved-state Bundles.
- A selection can span pages and filters. Select-page affects only that page;
  clear affects the current selection. Selected IDs are persisted in indexed
  rows, not a growing Intent or giant JSON array. Merely browsing an empty
  library does not create persistent empty selection sessions.

## Confirmation, Generation And Save

Explicit preparation freezes per-original encrypted metadata into a paged
manifest. The native confirmation page lists files, total count, uncompressed
source size and missing-file count. Missing originals block generation until the
selection is changed. A later reimport/stream change also requires renewed
confirmation instead of silently substituting another revision.

The supported public format in this increment is a standard ZIP, explicitly
identified as unencrypted. An unchecked consent control must be confirmed before
generation. There is no password field or claim that a renamed ZIP is encrypted.
The private generated artifact is separately encrypted at rest; that does not
make the user-saved ZIP encrypted. Password-portable packages and their verified
restore path remain separate requirements for h29/h30/h32.

Generation streams each original's exact source bytes into a unique
`originals/<original-id>/<safe-name>` entry. It preserves resolution, file format
and duplicate filenames through stable ID directories. Portable entry names
sanitize path/control/Windows-reserved characters and names, preserve short
extensions and avoid splitting UTF-16 pairs when truncating a long name. The
manifest retains the original filename and its exact archive-entry mapping.
Source AEAD, byte count and SHA-256 are checked. A streaming NDJSON manifest records source identities,
names, MIME types, byte counts, hashes, imported times and archive entry names.
It explicitly declares that measurement records are not included. No OCR-text
substitution, implicit recompression or complete-backup claim is made.

The archive is generated directly into a segmented AES-256-GCM/HKDF encrypted
private staging file, fsynced and atomically promoted only after successful ZIP
finalization. Per-attempt keys are Keystore-wrapped in the encrypted catalog;
mutable key/copy buffers are cleared after use. No private plaintext ZIP exists.
Failures/cancellation remove this attempt's artifacts, not source files, earlier
patient records or another attempt's output.

Only opaque session and dispatch IDs enter WorkManager. Generation uses a
foreground data-sync worker with a generic, nonclinical notification. Active
work can be recovered after process interruption. An interrupted ZIP is rebuilt
from its frozen plan using a new authenticated attempt, not appended to an
untrusted partial ZIP. Each explicit retry has a new durable dispatch identity,
so a previous finishing worker cannot swallow the retry or consume its plan.
Cancellation and attempt checks prevent stale workers from publishing results.
Foreground-start failures become visible failures with explicit retry, not an
unbounded silent retry loop.

The export page also observes its exact dispatch's WorkManager state. If that
dispatch is terminal while the business ledger still says active, a guarded
reconciliation exposes failure instead of leaving the page generating forever.
An empty/not-yet-enqueued or still-running work set is not misreported as failed,
and an older dispatch cannot fail a new retry.

Generated and saved are distinct persistent states. A separate user action
opens ACTION_CREATE_DOCUMENT for `application/zip`. The copy reads authenticated
private segments, checks the complete archive hash/size and closes the provider
output before recording saved. Cancelling the picker does not mark saved.
Copy failure attempts to delete the incomplete destination and retains the
private generated artifact for retry. SAF providers are not universally atomic:
process death/provider failure can leave a partial external document, but it is
not labeled successfully saved. Source records remain unchanged.

The saved ZIP and manifest are plaintext at the explicitly selected destination.
No cloud upload, contact send or automatic share is introduced. Full export task
history, explicit sharing, scoped permanent erasure and missing-original
measurement export remain work in the complete health design.

## Verification Requirements

Use isolated original catalogs, ciphertext roots and export directories for
synthetic files. Cover more than one 30-row page, date/type intersections,
selective decryption, source corruption/missing/reimport, frozen confirmation,
cross-session selection isolation, process interruption, cancellation, retry
dispatch races, exact bytes/manifests and generated/saved separation. Verify
generated ciphertext tampering is rejected and no original is overwritten.

Native tests must separately verify thumbnail bounds/pixels/recycling, PDF
seekable input, grid/list controls, recreation, background cleanup and visible
layout. A store/pipeline pass is not complete populated-page/SAF/foreground
delivery acceptance. Do not place fictitious measurements in the user's health
archive or open camera hardware for these tests.

## Recorded Results

The final offline app/test APK build succeeds. All 207 focused JVM tests in
30 suites pass, with zero failures, errors or skips. Twelve new domain cases
cover file classification, calendar boundaries, safe/portable Unicode archive
names and terminal-worker state reconciliation.

The final 0.1.7.23 / 1436 app and test APKs were cover-installed on Tab Active3
(SM-T575), preserving application data. APK SHA-256:
`340a7faa5eb40d4fd7c37baf87483edca63cd84bc85843d3a2c5ff1989bf2bba`.
Desktop package metadata also advances to 0.1.7.23; replacing a running Desktop
process is not claimed by this Android feature.

All 167 selected non-visual device tests pass in one final run (106.751 seconds),
with no failed/skipped instrumentation statuses. This includes the prior 142
health regressions and 25 new library/archive/thumbnail cases. They verify
95-original indexed pages, 65-original frozen selection pages, a 35-original
byte-faithful ZIP/manifest, duplicate names, 2 MiB incompressible cross-segment
data, ciphertext tampering, source changes, missing sources, cancelled/stopped
attempts, catalog reopen, abandoned ciphertext cleanup, retry dispatch isolation,
failed destination retry, schema-1/2 migrations and actual image/PDF thumbnail
pixels/bounds/recycling. A pre-portability candidate also passed 205 JVM and
166 non-visual device tests; it is not substituted for the final APK results.

The tablet relocked before visible acceptance (`showing=true`,
`SCREEN_STATE_OFF`). The two new native library UI tests are built but not
executed as visible-page acceptance. The final library screenshots, 16 selected
UI/lifecycle regressions, populated selection/confirmation/SAF flow, real
foreground-worker delivery/process-death matrix and large-export performance
remain open. No keyguard bypass or camera capture was used, and no synthetic
measurements/originals were placed in the user's health archive. All source and
archive fixtures use uniquely named test databases/private roots.

Repository, Desktop structure and whitespace checks pass. A failed intermediate
test build exposed PdfDocument's incompatible use() resource pattern; explicit
try/finally fixed it and the final build/device regressions pass. Failed-attempt
logs remain local build evidence rather than being erased or counted as passes.

This is not full-repository CI success. Parent #3691 run 41738014981 reports
7,905 tests, five existing Agent failures and six skips (native-tool catalog,
process-state, two task-intent cases and the untrusted-evidence boundary).
Repository, Windows package, Desktop smoke and core-regression checks pass
there. The complete 32-screen acceptance ledger remains open and authoritative.

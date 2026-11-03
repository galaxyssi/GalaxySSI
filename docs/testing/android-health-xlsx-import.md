# Native Health XLSX Import

This increment extends the existing CSV/JSON mapping contract with worksheet and
header-row selection, numeric date systems, source-cell addresses and explicit
formula-cache verification. It does not evaluate formulas, execute macros, send
health data to a Provider, or claim completion of all 32 health screens.

## Private Random Access

The initial on-device prototype could not reopen a proxy descriptor through
`/proc/self/fd`: Android rejected the path with `Permission denied`. That failed
probe is retained in `health-xlsx-fd-device.log`, not counted as acceptance.

The replacement supplies the existing authenticated Tink seekable decrypting
channel directly to Apache Commons Compress. ZIP entries and XML are preflighted
before cell lists/shared strings are constructed. Original SHA-256 is verified,
entry CRC/structure is checked, expanded bytes and metadata are bounded, and
document declarations, macros, traversal parts and impossible cell addresses
produce visible failures. Original bytes remain archived and encrypted.

Fastexcel 0.20.2 exposes File/InputStream constructors, not a public seekable-ZIP
entry point. The pinned `HealthXlsxWorkbookFactory` bridges its two package/workbook
constructors. This is access to bundled library code, not Android hidden APIs or
an operating-system permission change. Keep rules preserve these signatures.
Dependency upgrades must rerun both factory JVM tests and the real Android
channel tests. Do not silently replace this with a plaintext temporary file or
the library's whole-input in-memory constructor.

The bridge and ZIP own no permanent plaintext copies. Parser/JVM Strings are
transient runtime plaintext; this is not a claim that managed Strings can be
immediately overwritten.

## Mapping And Provenance

- Catalog the actual worksheets before reading observations. Hidden sheets remain
  identifiable and selectable; never simulate a worksheet or source device.
- Select a sheet and a text header row explicitly. Changing them discards only
  unconfirmed staging rows; committed batch ownership cannot be reconfigured.
- Read and checkpoint in 30-row chunks. Store physical row numbers and cell
  addresses independently from the 30-row preview cursor.
- Preserve raw source notation and units. Native numeric cells may have a
  separate plain-decimal normalization; booleans are not converted into `1/0`.
- Interpret serial dates only after choosing Excel date format, using the actual
  1900/1904 flag and configured timezone. The fictitious 1900-02-29 is not silently
  changed to March 1. Whole-day serials require an explicitly selected clock time.
- Formula caches are untrusted/stale until the user allows them. Missing caches
  stay missing; saved evidence includes the original expression, address and
  cached result and states that it was not recalculated.
- Deduplication uses the immutable original, worksheet and physical row, while
  normalized clinical duplicates are rechecked at save. Batch undo preserves
  earlier records and subsequent user edits.
- WorkManager identities bind phase and mapping revision. Cancellation or a sheet
  change prevents a late worker from committing into the replacement preview.
- Queue labels use actual batch states, not a permanent waiting-for-mapping label.

## Limits And Remaining Acceptance

Source and expanded working size are 64 MiB; metadata parts are at most 4 MiB;
ZIP entries at most 10,000; worksheets/columns at most 256. Original bytes are
retained on rejection. These are explicit resource errors, not truncation.

Fastexcel's ISO-typed `t="d"` cell representation is not implemented by this
adapter yet. It is an explicit interoperability gap, not a fabricated conversion
or a completed-format claim. Numeric Excel dates and text timestamps have
separate tested paths. This gap and unlocked visible-page acceptance remain in
the full [screen acceptance ledger](../architecture/android-health-screen-status.md).

Tests must cover real encrypted-channel reads, both date systems, worksheet/header
selection, shared strings, formula consent/missing caches, numeric normalization,
source identity/deduplication, interrupted and cancelled reads, ZIP/XML failures,
resource bounds and queue labels. All fixtures use isolated databases/roots and
are removed; no fictional observations belong in the user's health profile.

## Recorded Results

Version 0.1.7.20 / 1433 was built and cover-installed on Galaxy Tab Active3
(SM-T575), retaining the existing application data. Its APK SHA-256 is
`a9a7cbf03d9f0293ee6fa50b85c5d9d5aba1fdfb8a7e91ba7cbe04d3ba4438b1`.
Desktop package metadata is also 0.1.7.20; this does not claim a running Desktop
process was replaced as part of the Android health increment.

- The final offline build (`assembleDebug`, `assembleDebugAndroidTest` and the
  focused JVM selection) succeeds. All 141 tests across 26 suites pass, with no
  failures, errors or skips. This includes 16 XLSX policy tests and two pinned
  seekable-ZIP factory tests.
- All 106 selected non-visual device tests pass in one run. The run includes
  nine observation-store, five evidence, 17 encrypted-original, 15 photo-draft,
  two camera-callback (no hardware capture), 18 table-store, seven JSON-reader,
  six real file-queue, 24 encrypted-XLSX-reader and three task-label tests.
- An earlier 25-test channel run had one failure: malformed ZIP input escaped as
  a generic IOException. The adapter now reports `xlsx_format`; the complete
  106-test regression includes that corrected failure case. The earlier failed
  descriptor-path probe remains a failed attempt, not acceptance evidence.
- `node tools/dev/check-repo.js`, `node apps/desktop/scripts/check.js` and
  `git diff --check` pass. Current main was fetched before commit and is an
  ancestor of this branch.

The tablet still reports an active keyguard. Visible worksheet selection,
mapping, time preview, rotation and background/return acceptance remain pending;
no lock-screen bypass or actual camera capture was attempted. Tests use isolated
databases and private roots, not the user's health archive.

This is focused health acceptance, not a green full-repository CI claim. The
parent CSV/JSON PR #3688's Android run 41704616188 reports 7,833 tests, five
existing Agent failures and six skips (native-tool catalog, process-state,
two task-intent cases and the untrusted-evidence boundary). Its repository,
Windows package, Desktop smoke and core-regression checks pass. Those unrelated
Agent failures and the remaining 32-screen requirements are not hidden or marked
complete by this increment.

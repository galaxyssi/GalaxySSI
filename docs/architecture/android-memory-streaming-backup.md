# Streaming personal-memory backup

Branch: `feat/memory-streaming-backup-20260911`, based on merged PR #2991
(`e99ffde63`). The development version is Android 1.1.65 (951). The default App
backup implementation now uses the streaming format. Focused backup and shared
device regressions pass; remaining acceptance is listed below. This does not
establish the 100M+ goal or latency below 100ms.

## Current implementation

- `BackupRecordStream`: section/key records, checked 64-bit record counts and
  mandatory final footer. Each payload is split into 64KiB blocks. JDK Deflate
  is used only when a block becomes smaller; the decoder limits decompression
  to the declared, bounded block size. Neither file nor record count is a JVM
  collection. The 4KiB label bound is a format bound, not a memory-count cap;
  memory record labels contain opaque hashed row keys.
- `StreamingBackupArchive`: password-derived key material, Tink segmented
  AES-256-GCM/HKDF encryption and a versioned authenticated header. Successful
  file export finalizes authentication and syncs a temporary file in the same
  directory before a default `Files.move` without REPLACE_EXISTING. This does not
  claim atomicity on arbitrary filesystem providers or power-loss durability of
  the directory entry. Password derivation uses PBKDF2-HMAC-SHA256 with a
  random 32-byte salt and 600,000 iterations; version 2 fixes these parameters.
- `EncryptedAgentMemoryDeletionIndex.exportRecords`: streams personal rows and
  deletion records from the actual encrypted source, with physical-row and
  active-row count checks. The memory/deletion snapshot remains under the
  existing memory lock, so it is consistent but currently blocks memory writers
  for its duration. This is not an online snapshot implementation.
- `MemoryBackupStaging`: isolated SQLite staging with AES-GCM encrypted bodies
  and opaque HMAC indexes. Incoming records are not applied to the live store
  until the archive footer and AEAD EOF both validate. Duplicate identities and
  positions, missing section endings and count mismatches are errors.
- Staging applies both incoming and current local deletion barriers. ID and
  semantic-fingerprint suppression use disk indexes. Conflict partition counts
  are computed in SQLite; namespace repair and singleton promotion follow the
  existing conflict rules without materializing the complete conflict corpus.
- `MemoryReplacementKeys`: full replacement bookkeeping is a transaction-local
  ordinary SQLite table, not an unbounded JVM ID set or removal list. The table
  contains opaque keys and is dropped in the same transaction. The prepared
  restore path avoids the legacy full-list conflict normalizer.
- `AgentMemoryStreamingBackup`: connects this archive, staging and live memory
  store for memory-only export/restore.
- `AppBackupRecords` now connects the default `AppStore.exportBackup` and
  `AppStore.importBackup` paths in the working source. Personal rows and deletion
  records never go through `AgentBackupData.exportState` in the new format.
  Non-memory fields are emitted individually, not assembled into one app JSON.
  Their existing collection APIs (knowledge, tasks, transcript, contact history,
  global snapshot) still materialize one field at a time. This is a remaining
  scalability gap, not a claim that all backup sections have bounded memory.
- `BackupFieldStaging` encrypts non-memory fields into separate temporary files
  using a random per-import segmented-AEAD key. The fixed field registry rejects
  unknown, duplicate, missing or mistyped fields. Full archive authentication and
  app/memory section endings validate before any live restore callback executes.
- `BackupOperationRunner` moves document-provider I/O and backup work off the UI
  thread and rejects concurrent UI restore/export jobs. Null provider streams
  produce errors; imported temporary files and password arrays are cleared in
  `finally`. Completion checks the Activity lifecycle before updating the UI.
- Old single-JSON encrypted backups remain importable through the legacy path.
  Non-memory restore no longer invokes a fallback full-memory normalization.
  Retraction requeueing commits batches instead of collecting the entire ledger.

The corrected integrated APK is installed on T575. The 14 new focused device
cases passed, including a 10,001-row round trip. The 107 shared regressions also
passed; actual backup-screen acceptance remains pending. Cross-store
restore remains a sequence of store operations, not one atomic
transaction. An I/O or process failure after live application starts still needs
a durable full-app restore journal; authentication-before-apply is not proof of
cross-store rollback or restart recovery.

The cryptographic stream implementation is Tink Android 1.23.0, not a new
hand-written AEAD construction. Stream labels and payloads are encrypted; file
format/version, random salt and ciphertext length are visible.
[Tink Streaming AEAD](https://developers.google.com/tink/streaming-aead),
[Tink Java 1.23.0](https://github.com/tink-crypto/tink-java/releases/tag/v1.23.0).

## Bounds and privacy

The codec uses bounded crypto and compression buffers and does not place a
maximum total record count on the archive. Memory JSON is still decoded one
record at a time in the typed storage API: a single unusually large record can
still require a large allocation. The fixed-buffer codec test does not prove
that every typed-record importer has the same bound.

Staging SQLite has a 2MiB page-cache setting; bodies are encrypted with the
existing Keystore-wrapped row cipher. Stage IDs, sequence/position metadata,
equality and access patterns are not full-page encrypted. This is not SQLCipher.
The newer staging index uses a random per-workspace JCA HMAC key, not one hardware
Keystore operation per lookup. The persistent source index key is unchanged.
The temporary key is not persisted and does not establish restart recovery.
Stage creation/export/import does not start a model or send private memories to
a network service. Authentication and validation failures occur before live
memory changes; source transaction failures roll back that memory transaction.
Failures in later non-memory callbacks are not covered by cross-store rollback.
Process death recovery and orphan-stage cleanup still require dedicated acceptance.

The source store is still the row-oriented v3 personal-memory database. This
work does not add partitioned storage, native ANN, bounded full semantic recall,
or a physical 100M-row benchmark. Long source transactions and staging storage
amplification also remain work for the partition/snapshot engine.

### JSON storage versus whole-corpus materialization

Personal memory uses one JSON-encoded record per encrypted SQLite row. JSON as
a record encoding is not the same as storing all memories in one JSON value.
The new personal-memory backup walks those rows instead of building an array.
However, the following whole-collection paths still exist and must not be
described as completed scalability work:

- `AgentPersonalMemoryRows.read` and legacy `export` collect the complete corpus.
- `EncryptedAgentMemoryStore.recall` loads every item before lexical ranking;
  snapshot, bulk editing and deletion also still use full collections.
- `GlobalEntityMemoryGraphStore` stores the complete graph as one encrypted JSON
  value. Global memory evolution inbox/record collections have similar legacy
  whole-value storage. This phase does not migrate those stores or enable them.
- Legacy backup import/export and non-memory backup field adapters still
  materialize arrays, including knowledge items and chat/task history.

Removing these paths requires indexed retrieval, incremental mutation and
streaming adapters. Replacing JSON with another serialization format alone
would not fix the unbounded collection allocations.

## Evidence so far

The first codec build passed 17 JVM cases (11 framing, 6 encrypted archive),
including malformed sizes, Unicode labels, wrong passwords, header/body/tag
tampering, truncation, incomplete visitors, source failures and a 52,428,800-byte
record produced/consumed with fixed buffers. Log:
`build/memory-streaming-codec-test-sdk.log` (7m14s including compilation).
This was before later staging/replacement edits; it is not final app acceptance.
The preceding attempt failed at configuration because ANDROID_HOME was absent;
the installed SDK was supplied without downloading another SDK.

Eight core device cases are written, including an actual 10,001-row round trip with
physical counts and verification of every restored row, local/incoming deletion
barriers, malformed archives, duplicate IDs/positions, rollback and conflict
repair. Six additional app-format/device cases and nine JVM integration cases
are also implemented. All 14 new device cases and all 27 new JVM cases pass in
the corrected build below. The app-field tests use injected restore callbacks
instead of replacing the user's real pairing, identity and message history;
they do not establish full AppStore/backup-screen acceptance. The existing shared
regressions were subsequently run on the same APK, as recorded below.

### Retained development evidence (2026-09-11)

- `memory-streaming-core-build.log`: successful build, 10m39s. The first device
  invocation ran before APK installation had completed and failed class loading;
  `memory-streaming-core-device.log` is retained and is not functional evidence.
- After installation was explicitly confirmed, `memory-streaming-core-device-installed.log`
  completed 8 cases in 877.173s: 6 passed and 2 failed. The 10,001-row round trip
  checked every record and position and passed. The two deletion fixtures used
  lexical deletion, matching both similar records; they were corrected to invoke
  the existing exact-ID deletion API, not by weakening deletion behavior.
- Baseline timing: export 58,092ms, clear plus restore 489,201ms, encrypted archive
  4,196,934 bytes. Raw timing: `memory-streaming-core-device-timings.log`. These
  are full-dataset backup durations, not single-operation latency samples.
- `memory-streaming-app-build.log`: successful integrated build, 6m10s; 3,620
  JVM cases, zero failures/errors, five existing skips.
- `memory-streaming-app-final-build.log`: successful candidate build, 6m31s;
  3,623 JVM cases, zero failures/errors, five existing skips. APK SHA-256:
  `B5B55A59A17F5D3D9F8674CC11BD276864AA4F305080B8BF63EC192F5A12EB25`.
- The newer candidate's device run (`memory-streaming-app-device.log`) exposed
  an actual incompatibility: hard-link publication throws AccessDeniedException
  in the T575 app sandbox. This candidate must not be released. Working source now
  uses a move operation without REPLACE_EXISTING; device acceptance must be rerun.
  JVM success was insufficient to establish Android filesystem compatibility.
  The Java API defines default move as refusing existing destinations; ATOMIC_MOVE
  instead has implementation-specific replacement behavior. See the
  [Files.move contract](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/file/Files.html#move(java.nio.file.Path,java.nio.file.Path,java.nio.file.CopyOption...)).
- The first repository check rejected the new generic `values-zh` resource path.
  Moving that resource to the project's `values-zh-rCN` directory fixed the check;
  `memory-streaming-repo-check.log` passes. No guard or OS policy was disabled.
- `memory-streaming-app-portable-build.log`: corrected portable build, 4m17s;
  3,623 JVM cases, zero failures/errors, five existing skips. APK SHA-256:
  `4CE1AA4165B20335062CB0ECD2279E9BA53BBD1B097D26CAC8668529DE8BB3FC`.
  Both app and test APKs were installed with replacement, without uninstalling
  the app or clearing user data. `memory-streaming-portable-smoke.log` passes
  the 137-row content/order check (one case, 16.622s). The same case is included
  in the subsequent full run, so it is not an additional unique test.
- `memory-streaming-portable-device.log`: all 14 focused cases passed on T575
  (SM-T575), 958.936s. The 10,001-row test verified every restored
  record and its position. `memory-streaming-portable-device-progress2.log`
  preserves the timings: export 98,263ms, clear plus restore 444,637ms, encrypted
  file 4,196,934 bytes. Clear finished 158,174ms after export; restore itself
  then took 286,463ms. These are full-dataset durations, not per-operation
  latency samples. Export was slower than the earlier 58,092ms sample; the two
  runs are not a controlled performance comparison and do not establish an SLO.
- The corrected APK passes 16KiB alignment for all 73 native AArch64 libraries
  and the QNN packaging check (24 libraries). These checks do not measure ASR
  or QNN inference performance.
- `memory-streaming-portable-memory-sample.log` records one sample during the
  10,001-row restore: PSS 191,044KiB and RSS 250,824KiB. This is one whole-process
  sample, not a measured peak or evidence that memory use is constant at 100M rows.
  Test setup itself still creates a 10,001-item list.
- `memory-streaming-shared-regression.log`: 107 shared device cases passed in
  1,644.522s on the same APK, covering memory identity/deletion/outbox, point
  operations, incremental writes, browse indexes/UI, image/attachment behavior
  and timing instrumentation. Together with the new suite, 121 unique device
  cases pass. No app data reset, re-pairing or private-memory upload was used.
- These are correctness passes, not performance-gate passes. Preserved raw
  timing: `memory-streaming-shared-regression-timings.log`. At 10,001 real rows,
  100 eight-row page samples measured P50 118.58ms, P95 295.84ms, P99 405.24ms,
  maximum 715.99ms and 100/100 misses of the requested 100ms bound. Twenty-five
  row pages also missed 100/100. In the incremental-write suite, new writes had
  P50 106.92ms, P95 276.05ms, P99 414.51ms, maximum 882.25ms and 59/100 misses;
  duplicate updates missed 100/100. No slow or failing samples were excluded.
  Source encryption, index migration and remaining full-collection paths still
  need profiling and architectural work; these samples do not isolate a cause.

## Required next integration

1. Verify the newly integrated default paths and replace the remaining legacy
   per-field collection APIs with incremental adapters. Do not describe the
   complete app backup as bounded-memory until those adapters are verified.
2. Verify background UI work, failed document-provider opens and lifecycle return.
3. Verify legacy import without erasing data, identity or pairing on the device.
4. Extend the existing rollback, regression and packaging checks to the scale
   ladder and long-duration failures. Keep earlier measurements and do not
   treat a synthetic count label as storage-capacity evidence.
5. Complete restart/cancellation handling and retraction scheduling without
   rebuilding whole-corpus sets. Repository fetch/version checks are current at
   `e99ffde63`; publish this bounded phase as an independent English PR without
   claiming the unfinished scale, latency or recovery goals.

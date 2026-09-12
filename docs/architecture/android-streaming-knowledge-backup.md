# Streaming knowledge backup

Android 1.1.93, following the transactional-counts work in PR #3012.
The 100M+ memory, Run Kernel, tracing and ordinary Agent Loop DAG goals remain open.

## Production path

`AppStore` already uses `AppBackupRecords` and segmented password-portable AEAD.
Previously, its non-memory field visitor still called knowledge `exportJson()`.
The entire source corpus became one JSON array. Restoring that array also retained
all previous and replacement objects for mutation publication.

App archive schema 2 removes the `agent-field/knowledge` array and requires an
independent section:

- `knowledge/begin`, with section schema 1.
- One `knowledge-row/<SHA-256 of source ID>` record per authenticated source.
- `knowledge/end`, with a signed 64-bit row count.

Labels and bodies are inside the existing encrypted archive. The record codec
compresses fixed 64 KiB blocks and the existing Tink streaming AEAD authenticates
segments and the archive end. Password derivation and encryption are unchanged.
Vectors, local key material and derived indexes are not copied as portable data.

Export opens a separate, query-only SQLite connection and pins a WAL read snapshot
under the short store initialization lock. Keyset pages contain at most 64 IDs.
Bodies are decrypted and emitted one source at a time; the writer monitor is not
held while serializing the corpus. Source identity, policy, body checksum and
chunk authentication still use the existing storage reader. Closing/resetting the
owner invalidates the export, and failure does not publish a partial archive.

## Restore validation and memory bounds

Incoming sources are encrypted into an isolated disk staging database. Duplicate
IDs are rejected by a keyed unique index, rather than a corpus-sized in-memory set.
Record identity, supported policies, boundaries and final row count are checked.
No live restore callback runs before authenticated EOF and all required sections
have validated. Unknown or duplicate fields and mixed section formats are rejected.

The stage uses a 2 MiB SQLite page cache. Its plaintext source ID index is replaced
by an ephemeral keyed token. Encrypted bodies bind the staging identity, sequence
and before/after role as AAD. Large encrypted cells are read through bounded SQL
substrings so Android CursorWindow size does not bound the source size.

Restore stages old records on disk as well. Old/new records are matched by stable
ID and visited incrementally. The existing live store replacement is one SQLite
transaction: exceptions and process death must leave its original source/FTS/vector
state intact. Identical records are not rewritten, preserving their derived vectors
and browse revision. Changed/deleted records use existing source writes and cascades.
Mutation callbacks run after commit with at most one old/new item per callback;
there is no entire-corpus pair of lists. Only the existing configured observation
path is used; this feature does not enable global processing or model downloads.

Heap usage is independent of record count, but not independent of the largest
single source: the current storage/item codec still materializes one source JSON
object and its strings. This is not a fixed byte bound for arbitrarily large items.
The legacy whole-JSON AgentBackupData export API remains for its existing tests;
the production AppStore archive path no longer calls it for knowledge.

## Previous archives

Schema 1 app archives remain readable. Their old knowledge array envelope is parsed
with a strict streaming JSON reader, one source at a time, into the same encrypted
stage. It is not sent through the metadata array callback. Duplicate envelope keys,
duplicate IDs, invalid nesting and malformed input fail rather than being skipped.
Current exports always use schema 2. Other app metadata formats are unchanged.

## Explicit limitations

- A long-lived WAL snapshot can retain WAL pages while concurrent writers change
  the corpus; disk space and export duration are still finite constraints.
- Restore still holds a live SQLite writer transaction while comparing/applying
  all source changes. Bounded heap is not bounded writer latency. Generational
  storage promotion and real concurrent UI measurements remain future work.
- Full app restore spans multiple existing stores. This change does not make their
  combined commits atomic. The knowledge transaction itself must roll back safely.
- Callback publication is not a new durable cross-store outbox. Crash-safe external
  side effects remain part of the broader Run Kernel goal.
- Other app fields, including legacy message/task collections, still have their
  existing collection APIs. This is not an all-app-data streaming claim.
- Abrupt process termination may leave an encrypted staging file in cache. Its
  token key is process-local; normal close deletes the stage. A global orphan
  cleanup policy is not introduced here.
- Full-source metadata aggregates, storage sharding and large-corpus native vector
  retrieval are not completed by this backup change.

## Validation status

The App and matching instrumentation APK built successfully with the permanent
8 GiB Gradle heap in 8m19s. JVM results: 3,751 cases, zero failures/errors, five
existing skips across 537 suites. All 74 AArch64 native libraries passed 16 KiB
alignment and the repository guard passed. App SHA-256:
`856df74dc92247ad9b707049cf99c2f7dffa9bf0bb9a98a3ccf35bdec32c3edc`.

Only SM-T575 was updated to 1.1.93 (979), preserving its first-install timestamp
and user data. All 22 focused device cases passed in 163.641s, including concurrent
snapshot mutations, multi-page encrypted sources, policy/identity retention,
cross-namespace restore, malformed/truncated archives, rollback, unchanged-vector
preservation and complete schema 1/2 App archives.

An explicit process-death test terminated PID 13190 after two uncommitted writes
inside the restore transaction. PID 13238 verified all three original records and
the absence of both partial writes, retried the restore and verified all 11 new
records after reopening, in 1.378s. Separate cleanup passed in 0.111s and removed
only the named isolated fixture and its orphaned encrypted stage. This is not a
physical-device reboot or complete Run Kernel recovery claim.

A test-only retention change then rebuilt the instrumentation APK in 1m7s, leaving
the App SHA unchanged: large fixtures are retained even when the test fails. The
final instrumentation APK SHA-256 is
`529211b91161fcaff842c36ec09462b7971e05be24d480819ca6df728dc04869`.

### Real encrypted-source scale run

The final APK completed a 10,001-source round trip on SM-T575 in 1,126.501 seconds.
Each source has its own Chinese test body, ID, source metadata and authenticated
encrypted storage. After exporting, the test replaced the live corpus, validated
and restored the archive, reopened the database and compared every source object
with its expected value. This is not just a count check or metadata-only fixture.
The isolated fixture disables mutation recording; the post-commit traversal runs
with a no-op observer. Its timings do not include production memory-observer
follow-up work or model indexing. Full App schema 1/2 integration uses separate,
smaller device cases, not this 10,001-source corpus.

| Stage | Elapsed |
| --- | ---: |
| Seed encrypted sources and FTS | 294.882 s |
| Export 3,258,063-byte encrypted archive | 268.088 s |
| Authenticate and stage all incoming sources | 31.662 s |
| Apply restore and publish changes | 312.967 s |
| Verify every source after reopening | 214.373 s |

The 10,001 individual stage-row samples had nearest-rank P50/P95/P99 of
1.782039/2.105307/2.590769 ms, maximum 25.748769 ms. These cover staging
parse/encrypt/insert only, not its final commit/fsync, live-source writes, reads,
UI latency or the entire restore. There is no general 200 ms claim.

The sampled Java-heap maximum was 42,175,228 bytes. Samples were taken every
1,024 staged/restored rows, not continuously or during every phase, so this is not
a process-memory peak bound. Export and restore remain too slow to extrapolate
to 100M records without further storage work. Neither this run nor the earlier
million-row metadata counts test proves 100M complete-memory capacity.

Raw samples are retained in seven files of at most 1,500 rows and 30 KB each;
reassembly was compared with all original sample IDs and values. See the
[scale result and hashes](evidence/android-knowledge-backup-20260912/scale-result.json).
The isolated device database and encrypted archive remain available for
same-scale checks. No user source data, database or archive is committed.

Reproduce the scale run with the explicit test argument (creates another isolated
fixture, not the production knowledge database):

```sh
adb -s R52R90282TY shell am instrument -w -r -e knowledgeBackupRows 10001 \
  -e class com.galaxyssi.chat.KnowledgeBackupScaleDeviceTest \
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

The 113-case shared regression on the final instrumentation APK passed in
1,036.762 seconds, without skipped cases. It includes the 22 focused backup cases, counts/worker maintenance,
FTS, source paging, native/hybrid retrieval, vector mutation/enrollment/ledger and
three isolated real-model lifecycle cases using the already-installed fixture.
All individual results are recorded in the
[regression evidence](evidence/android-knowledge-backup-20260912/regression-result.json).

The final APK also repeated the actual process-death test: PID 15913 was killed
after two uncommitted writes, then PID 15979 verified the three original sources,
the absence of both partial writes and all 11 retried sources after reopening.
Verification passed in 1.231s and explicit fixture cleanup in 0.109s. The separate
10,001-source scale fixture was not deleted.

Small-corpus regression measurements include FTS hot-query P95 40ms (1,201-source
fixture), real Chinese neural/hybrid hot-query P95 144ms (three documents, recall
3/3), and foreground retrieval P95 83ms during a 512-dimensional, 204-chunk native
replay. These are regression checks, not 100M or whole-UI performance claims.
Source pagination still took 24.686s to visit all 25 pages of 1,201 sources, and
the vector-ledger 1,201-document test took 154.017s; these broader operations still
need optimization and are not hidden behind the hot-query numbers.

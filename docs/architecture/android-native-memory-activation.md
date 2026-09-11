# Android native knowledge retrieval

Android 1.1.74 uses `galaxyssi-memory-native` 0.4.0 for the configured knowledge
embedding model's semantic retrieval. Ordinary store and RAG calls enter
`KnowledgeSemanticSearch`; they no longer allocate a JVM HNSW graph containing
all vectors. The old HNSW class remains for comparison tests, not the default
retrieval path. Unconfigured/disabled models retain lexical retrieval.

## Data and ownership

The existing encrypted `AgentKnowledgeDatabase` and its vector ledger remain
authoritative. The native index lives under the App's no-backup directory,
namespaced by the source database, embedding specification and source-feed epoch.
A random 256-bit index key is wrapped by Android Keystore AES-GCM with namespace
AAD and committed using `AtomicFile`. Only the wrapped envelope is persisted.
Transient keys, replay page vectors, JNI copies and result buffers are cleared.
No original source text is stored in the native graph or sent to a provider.

Native rows, graph edges, provenance and replay progress share one transaction
across the catalog and four encrypted node shards. The pager target is fixed by
the session budget rather than corpus count. It is not a whole-process RSS cap.
Payloads and metadata are bounded binary records, never a whole-corpus JSON file.

JNI calls use opaque monotonic handles owned by a synchronized native registry.
There are no raw pointer handles, retained Java references, cross-thread JNIEnv
values or per-node Java callbacks. Primitive array lengths are checked before
copying. Kotlin worker threads make synchronous calls; native cancellation sets
an atomic flag without waiting for inference or an index operation. Close retires
the registry handle while an already-running call retains its owner until exit.
Rust panics are contained at JNI boundaries; corrupted owners require reopening.

## Incremental replay and retrieval

The durable vector feed drives replay in bounded pages. Each scheduling slice
handles at most four pages, and each vector page contains at most 64 vectors.
These are slice sizes, not total action/memory limits. Pending work schedules
another slice; committed progress survives handle expiry and process death.

The existing WorkManager vector-indexing worker advances native replay after
embedding batches and requests durable successors when work remains. Queries
also reconcile a bounded slice before retrieval. A large backlog returns current
lexical candidates while native replay continues off the UI thread, rather than
blocking a query to rebuild an entire graph or claiming stale vectors are current.

Only fully published documents participate in native results. A source key,
revision and publication sequence identify a node; removed, replaced, incomplete
and re-added older publications are excluded. The source-feed epoch/head are
checked before resolution, and the current encrypted source header and policy
are resolved again before any excerpt or RAG citation is released. Index state
cannot grant broader source access.

The 30-second idle cleanup closes the native handle and embedding model, not
the durable graph. Active replay is not treated as idle. Background/lock/trim
invalidation cancels current work and prevents late results; resuming the runtime
can continue from its checkpoint. Whole private-data reset already deletes the
no-backup directory and the wrapping key. Individual source deletion is logically
effective immediately; physical graph tombstone reclamation is still needed.

## Build and verification

The separate JNI library is built from locked Rust dependencies by Android
Gradle, using the pinned Android NDK and 16KiB linker alignment. No untracked
developer `.so` or ASR/LLM native source changes are needed on a fresh branch.
Linux CI installs the pinned Rust toolchain before App builds.

### Validation on 2026-09-11

Only SM-T575 was used. The existing App was upgraded in place from 1.1.73 to
1.1.74 (version code 960); no uninstall, data reset, pairing change or production
model replacement was performed. Tests used isolated synthetic stores and the
already installed, hash-verified BGE fixture. No new model was downloaded.

| Check | Observed result |
| --- | --- |
| Gradle unit tests, debug APK and instrumentation APK | Successful; 3,686 tests, zero failures/errors, 5 skipped |
| APK alignment audit | All 74 AArch64 native libraries passed 16KiB ZIP/ELF checks |
| Native SQLite/replay executable on SM-T575 | 19 passed, zero failures; 1 child-process helper intentionally ignored by the direct runner |
| Direct JNI and source-feed integration | 7 passed: malformed inputs, closed handles, cancellation, reopen, retry deduplication, stale sources and Keystore wrapping |
| Existing store/RAG hybrid regressions | 10 passed, including source-policy changes, concurrent mutation, lexical fallback, lifecycle cancellation and TTL |
| Existing WorkManager lifecycle regressions | 3 passed: pinned import and automatic RAG indexing, 40-document burst indexing, saved selection and pending-work recovery |
| Real BGE Chinese retrieval | 3/3 top-one semantic cases; 100 measured queries on each App version |

The same existing `KnowledgeHybridNeuralDeviceTest` was run before and after
the App upgrade. It uses three synthetic Chinese passages and the pinned BGE
model with a 64-token test context, not a 100M-row corpus. The after-upgrade run
used the still-installed previous instrumentation APK against the new production
code; the new instrumentation APK was installed for the 20 integration tests.

| App | P50 | P95 | P99 |
| --- | --- | --- | --- |
| 1.1.73 JVM graph baseline | 149ms | 197ms | 202ms |
| 1.1.74 native retrieval | 157ms | 208ms | 231ms |

These are single-run measurements, not a statistical guarantee. The new path
passed semantic correctness but exceeded the approximately 200ms target at P95;
this PR does not claim a latency improvement or performance-target completion.
It removes whole-corpus JVM graph allocation and makes replay durable. Further
hot-path tuning and scale acceptance remain necessary.

Validated main APK SHA-256:
`fa82102b96930c55ee25985d24996b471e9a0f962d98574cb7de734ece3a12db`.

## Remaining requirements

This activation does not prove 100M-row capacity or a 200ms end-to-end bound.
Still required: increasing-scale real corpus/RSS/latency measurements, coarse
summary-vector hierarchy, source/provenance metadata sharding, automatic derived
index repair, physical compaction and deletion-residue acceptance. Source and
personal-memory storage/backup paths have their own scale acceptance; activating
knowledge retrieval does not by itself complete all personal-memory requirements.
Full Run Kernel coverage, cross-device side-effect deduplication, tracing and
ordinary Agent long-cycle DAG acceptance remain separate unfinished goals.

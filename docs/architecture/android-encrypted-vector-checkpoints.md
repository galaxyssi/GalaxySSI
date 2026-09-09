# Android encrypted vector checkpoints

This stage adds resumable, authenticated dense-vector persistence to the existing
encrypted knowledge database. It builds on the real llama.cpp encoder, not on
token hashes masquerading as semantic vectors.

## Identity and consistency

An embedding specification binds the GGUF SHA-256, dimensions, context window,
sequence/L2 contract, and chunking version. The model file is verified before
opening the independent encoder. Knowledge IDs and model identities use keyed
indexes. A source revision is the hash of its authenticated encrypted header;
every source write produces a new revision, including access-policy changes.

Source update/replacement/deletion and vector invalidation share the same SQLite
transaction through foreign-key cascades. A late model result can commit only
when both the source revision and the expected checkpoint still match. Duplicate
results cannot append the same ordinal again. Source replacement rollback restores
the prior vectors as well as the prior source.

Vector values and their character offsets are encoded directly into bounded
binary buffers and encrypted with the existing Android Keystore AES-256-GCM key.
AAD binds database namespace, item, model, source revision, dimensions, and chunk
ordinal. A separate authenticated checkpoint binds offset, count, completion, and
source length. Vectors cannot be swapped between documents, revisions, or models.
The existing text encryption envelope is unchanged.

## Resumable work

`SQLiteAgentKnowledgeStore.indexVectorChunks` performs a bounded scheduling quantum,
not a lifetime action limit. Model inference/tokenization runs outside database
transactions and monitors. Each successful chunk and its next checkpoint commit
atomically. Cancellation or inference failure leaves earlier chunks durable; a
later call continues them instead of re-embedding from the beginning.

Registering a model fills its indexed pending queue once. A source-insert trigger
enqueues new revisions for registered models; completion removes that queue entry
in the chunk/checkpoint transaction. Finding the next item does not scan all
already indexed documents. Unregistering an obsolete model cascades only that
model's queues and derived vectors, never source knowledge or other models.

Chunk boundaries use the actual model tokenizer, preserve UTF-16 source offsets,
avoid splitting surrogate pairs, and overlap by up to 32 code points. Long input
is not silently truncated. Whitespace-only gaps need no vector. The bounded
prefix search favors predictable memory over maximal packing of each window.

Only completed documents expose vector pages. Pages are bounded to at most 256
rows and do not decrypt source bodies. Missing ordinals, modified checkpoints,
bad tags, wrong dimensions, non-finite vectors, and invalid norms fail explicitly.
Returned pages own wipeable float arrays and implement `Closeable`.

## Privacy and limits

The database still exposes opaque equality keys, row counts, encrypted record
sizes, progress offsets, and access patterns. It is not an oblivious index or
whole-file SQLCipher database. GCM authenticates records but cannot prevent an OS
attacker from deleting the entire database, suppressing rows, or replaying a whole
old valid snapshot. Engine-private tensor buffers are not guaranteed wiped.
Deletion here is logical cascading deletion, not a claim of per-record
cryptographic erasure of old database/WAL pages.

No embedding model is shipped in the APK and no knowledge content goes to a cloud
embedding service. This stage does not automatically download or load a model and
does not replace FTS5 production ranking. Model management UI, background work
policy, ANN/hybrid retrieval, learned reranking, and broad retrieval-quality gates
remain required before declaring Memory 2.0 delivered.

## Validation design

- Pure Kotlin chunking tests cover complete character coverage, overlap/resume,
  mixed Chinese/English/supplementary Unicode, exact boundaries, huge whitespace
  gaps, normalization expansion, invalid offsets, and unencodable input.
- Device ledger tests use explicitly synthetic normalized vectors to isolate
  encryption, rollback, cancellation, stale results, model separation, provenance,
  paging, corruption, and source lifecycle behavior. They are not semantic-quality
  evidence.
- Real-model tests use the pinned BGE GGUF from the encoder documentation and
  verify semantic ordering after encryption and database reopen.
- An explicit two-phase harness leaves one real chunk committed, reboots the
  device, and resumes remaining chunks. It checks the Android boot count changed
  and that the first chunk's ciphertext was not rewritten.

The reboot test accepts `vector_phase=prepare|verify` and a fresh
`vector_fixture=test-vector-reboot-<identifier>.db`. It only cleans that named
fixture after successful verification. It skips in generic CI without the
two-phase arguments; real-model tests skip when the pinned external model is absent.
The harness explicitly invokes resume after reboot. It does not prove that a
production boot worker automatically schedules vector indexing; that lifecycle
connection remains part of the next integration stage.

## Executed evidence (2026-09-09)

Android 1.1.16 (902) was installed in place on SM-T575. No user data was reset.
The build includes the existing 24 QNN libraries unchanged; no ASR/QNN inference
performance claim is made by these storage tests.

- JVM: 35 tests across three selected knowledge/chunking suites, no failures.
- Combined device suite: 35 passed and one intentionally deferred two-phase
  reboot test, 536.005 seconds. The runner reports 36 tests including that skip.
- Real reboot: boot count 59 to 60; prepare passed in 1.063 seconds, verify in
  11.683 seconds. One committed chunk survived unchanged and 45 new chunks were
  appended, producing 46 total. The first ciphertext hash and source content
  matched; the named fixture was removed only after successful verification.
- Persistence scale: 1,201 documents completed in 81,262 ms, including source
  writes and synthetic-vector persistence. This is not neural inference speed.
  The pending queue was empty and its next-job query used an indexed search.
- Actual BGE vectors retained semantic ordering after encrypted persistence and
  reopen: recall@1 3/3, 512 dimensions. This small case is not broad retrieval
  quality acceptance.
- Independent encoder regression: 100 hot samples, P50 19 ms / P95 20 ms /
  P99 20 ms; instrumentation-process PSS 190,388 KiB is not model peak memory.
- Native packaging: 73/73 AArch64 libraries passed 16 KiB alignment; the QNN
  manifest check passed for 24 libraries (221.68 MiB).
- Post-test force-stop/cold launch: ActivityManager TotalTime 2,396 ms, one
  sample, not a percentile or full chat-content readiness measurement.

APK SHA-256:
`71bad800227c393c9bcd02e6a9b545ac799ee6ed951e6398402025c94aed9b18`.

Local evidence files are `build/vector-ledger-final-build.log`,
`build/vector-ledger-device.log`, `build/vector-reboot-prepare.log`,
`build/vector-reboot-verify.log`, `build/vector-ledger-16kb.log`, and
`build/vector-ledger-qnn.log`. They are not shipped as application data.

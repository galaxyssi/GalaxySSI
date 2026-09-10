# Scalable local memory: 100 million records and beyond

Status: proposed target architecture, not an implemented or benchmarked engine.
Requested on 2026-09-10, after PR #2986. This extends the Memory 2.0 work;
the broader Run Kernel, tracing, recovery, Blob, DAG, concurrency and multimodal
requirements remain active.

## Non-negotiable requirements

1. No product-level fixed total memory-count cap. Logical counts, sequence
   numbers, offsets and aggregate sizes use checked 64-bit arithmetic. Finite
   device storage and RAM remain real constraints, never a reason to silently
   discard acknowledged memories.
2. Design and validate for at least 100,000,000 real records, then larger
   partition sets. Smaller datasets must avoid paying for the large-dataset
   machinery. Do not force a million-entry vector index onto a small store.
3. The user's requested retrieval and write latency is below 100ms. This is
   currently unproven. An unconditional guarantee for every device, payload,
   power state, cold model load or unbounded query is impossible. A measured
   SLO must not be substituted for an absolute guarantee without stating the
   difference.
4. Preserve privacy, scope isolation, deletion barriers, conflicts, evidence,
   timestamps, backups and crash recovery. Do not upload private memory or
   silently delegate storage/search to Desktop/cloud to meet a local benchmark.
5. No UI-thread storage, parsing, index construction, compression or decryption.
   Do not change the ASR/QNN lifecycle to create artificial benchmark headroom.
6. A single giant JSON value/file is prohibited: this includes manifests,
   snapshots, exports and backups, not only the primary table. Use bounded
   framed records, paged catalogs and independently authenticated chunks.

## Measured starting point

PR #2986 removes the personal store's giant encrypted JSON value and preserves
unchanged ciphertext. It does not eliminate full-list recall/mutation.
On T575, a 1,201-record fixture measured migration at 6,699ms, a full row read at
5,896ms, and 20 metadata counts together at 111ms. These are single fixture
observations, not percentile benchmarks or indexed-query times. The device
reported approximately 41GiB available under `/data` during inspection.

The knowledge store separately has bundled SQLite, FTS and a transient JVM HNSW
graph. Rebuilding a complete decrypted graph and scanning personal memories
cannot be the hundred-million-record hot path. The following supersedes that
design at scale; it does not merely raise existing capacity constants.

## Architecture

```
AgentMemory API (scope, consistency, cancellation, deadline, provenance)
  -> local cost-based query planner / durable event writer
  -> small-store path OR partition directory and hot delta
  -> concurrent candidate retrieval
       ID / entity / time / namespace indexes
       lexical postings over original events
       coarse summary ANN -> fine event PQ / local ANN
  -> revision + scope + deletion checks
  -> bounded evidence fetch and reranking
  -> result page with source IDs, index watermarks and coverage

Authoritative storage:
  encrypted compressed immutable event segments + durable commit journal
Derived storage:
  partition manifests, typed indexes, lexical postings, summary/event indexes
```

### 1. Partition directory, not a giant shard fan-out

Partition by privacy namespace and storage generation, with adaptive size-based
splits. Use time/entity/source statistics and lexical/semantic routing metadata
to choose relevant partitions. Do not scan all partitions for each query or
partition only by time and thereby make time-unspecified queries global scans.

One active writer per mutable partition; independent partitions can commit in
parallel. A durable split manifest records source generation, copied range,
delta-log offset and the atomic cutover. Readers pin a generation; interrupted
splits are resumable and cannot expose duplicated or missing records.

The namespace is a correctness boundary, not just a ranking feature. Check it
before candidate exposure and again before fetching/reranking raw evidence.

### 2. Compressed original-event segments and key/value separation

Keep append-only original events as authoritative evidence. Compress bounded
blocks before encrypting; retain an ID-to-block/offset directory so one lookup
does not decompress an entire archive. Small active records can remain inline
until sealing a segment is worthwhile. Use a proven compression library.

SQLite remains useful for small transactional catalogs and hot deltas. Evaluate
an LSM/BlobDB-backed native directory for larger write-heavy partitions, rather
than adding RocksDB universally. Key/value separation reduces large-payload
rewrites during index compaction; actual Android integration and I/O behavior
must be benchmarked. [RocksDB integrated BlobDB](https://rocksdb.org/blog/2021/05/26/integrated-blob-db.html)

Never rewrite an entire partition, backup or all surviving memories for one
flag update. Append a revision or patch and update only affected index entries.

### 3. Durable visibility, not an in-memory queue acknowledgment

The write response requires a durable event/commit record and a query-visible
hot delta for the acknowledged sequence. Original text, typed indexes, deletion
barriers and lexical delta visibility must agree on that sequence.

Record separate watermarks for durability, lexical visibility, summary building
and event-vector indexing. Embeddings and summaries can be asynchronous, but
their lag must be visible. A new record is accessible by ID and lexical delta
before its vector exists; do not advertise immediate semantic completeness.

Flush promptly at low load; use short adaptive group commit under contention.
Do not add a fixed batching delay to every small write. All queue wait and fsync
time count toward latency. Failures must preserve the caller's idempotency key.
SQLite WAL still has durability tradeoffs: use the durable configuration, not
`synchronous=NORMAL` merely to improve numbers. [SQLite WAL](https://www.sqlite.org/wal.html)

### 4. Original-text retrieval plus multi-resolution semantics

Keep a lexical index over original evidence, not just summaries. Reuse bundled
FTS5 where it fits, with privacy-preserving storage. External/contentless FTS
avoids another full text copy, but does not by itself encrypt term postings.
[SQLite FTS5](https://www.sqlite.org/fts5.html)

Use several semantic levels: namespace/topic routing vectors, bounded summaries,
and fine event codes/indexes within selected partitions. Around one million
summary vectors is an adjustable working set, not a hard retention ceiling.
Retain direct evidence links and fine-grained retrieval so a rare detail omitted
from a summary is not permanently undiscoverable.

PQ/quantized event vectors reduce disk traffic. Use a proven ANN implementation;
compare flat SIMD search for small sets, IVF-PQ and disk-backed graph retrieval
for large sets. DiskANN demonstrates disk-oriented large-scale retrieval, but
its published workstation results are not Android performance guarantees.
Android NDK portability, encrypted block reads, filtered recall, cancellation,
peak memory and 16KB alignment are explicit acceptance items.
[DiskANN](https://github.com/microsoft/DiskANN)
[DiskANN research](https://www.microsoft.com/en-us/research/publication/diskann-fast-accurate-billion-point-nearest-neighbor-search-on-a-single-node/)

Use reciprocal-rank fusion for heterogeneous candidate scores, then bounded
reranking and evidence fetch. Track recall/grounding quality alongside latency;
fewer candidates or truncated search must not silently manufacture a fast pass.

### 5. Bounded native cache and envelope encryption

Memory budget is independent of total record count. Use bounded block, postings,
vector-code and result caches, plus an LRU limit on open partition handles.
Native access avoids creating JVM objects for the corpus; JNI passes bounded
batches. No full plaintext `mmap` of a private index.

Evaluate envelope encryption: Keystore protects wrapped data keys, while bounded
session keys decrypt authenticated blocks locally. This avoids a Keystore
service operation for every tiny record. Do not claim the current 5.9s read is
entirely a Keystore cost without profiling it. Bind AEAD associated data to
namespace, segment, generation, block offset and key version; enforce nonce
uniqueness. Use audited crypto libraries, never custom cryptographic algorithms.

Clear session keys/decrypted blocks on lock/background/trim events. Compressed
and encrypted indexes must be inspected for plaintext residue. HMAC term indexes
still reveal equality/frequency patterns; that leakage is not equivalent to
fully encrypted index pages and requires an explicit threat-model decision.

### 6. Deletion and recovery across every projection

Journal deletion barriers immediately, suppressing raw, lexical, summary, vector,
cache and backup results at the same read boundary. Rebuild affected summaries
from surviving evidence. Compaction later removes unreachable bytes and rotates
affected segment keys when appropriate. Do not claim arbitrary physical flash
or externally copied backups can be securely erased by the app.

Derived indexes carry a source sequence and generation. After process death,
replay only the missing delta or reopen a completed immutable index; never
rebuild the full hundred-million-record index at startup. Persist manifests and
index artifacts before switching the active generation. Reuse the Run Kernel's
operation identity and checkpoint semantics for rebuild/compaction tasks.

## Technology choices and mmap constraints

| Component | Proposed use | Required proof before production adoption |
| --- | --- | --- |
| NDK/C++ | Bounded native storage/search API, compression, disk vector search | JNI ownership, cancellation, crash containment, 16KB alignment, no full-corpus JVM copies |
| SQLite shards | Small-store path, transactional metadata, hot delta, typed and lexical indexes | Atomic split/recovery, bounded handles, real query plans, checkpoint tail latency |
| RocksDB / integrated BlobDB | Candidate large-partition event/ID directory, write-heavy partitions | Android build/package, compaction write amplification, background I/O budgets, equivalent durability and encryption |
| SQLCipher | Candidate encrypted SQLite/FTS partition implementation | License/build review, FTS5 availability, page/WAL/temp encryption, key lifecycle and measured latency |
| Application AES-GCM | Authenticated compressed event/index blocks and wrapped data-key metadata | Nonce/associated-data correctness, truncation/replay detection, zeroization and crash-safe generation changes |
| mmap | Optional read-only window over immutable ciphertext/index files | Bounded mapping handles, pinned generations, SIGBUS/truncation prevention, pread fallback and cache-state benchmarks |

SQLCipher uses page-oriented AES-256-CBC with authentication, not AES-GCM.
It is a separate candidate from application-level AES-GCM, not a name for the
same implementation. Do not add per-record encryption on top of encrypted pages
without a threat-model reason and a measured cost. Its documented page/WAL
protection and temporary-file requirements must be verified in the actual build.
[SQLCipher design](https://www.zetetic.net/sqlcipher/design/)

Do not assume that enabling SQLite mmap automatically works through an encrypted
pager, or that mmap necessarily improves latency. SQLite documents tradeoffs,
including faults on I/O errors and cases with lower performance. Benchmark mmap
against bounded `pread` on the actual encrypted backend.
[SQLite memory-mapped I/O](https://www.sqlite.org/mmap.html)

For custom immutable encrypted segments, map ciphertext only; decrypt selected
authenticated blocks into fixed-budget buffers. Never truncate a mapped active
generation. Switch manifests, drain readers, unmap, then reclaim obsolete files.
Writes use the durable commit protocol, not unsynchronized writable mappings.
An application cache limit is not an RSS guarantee: also account for native
allocations, mappings/page residency, file handles, index construction and OS
page cache behavior. Cache budgets are fixed for an execution profile, never
proportional to total record count, and can shrink under memory pressure.

For a RocksDB candidate, the limit must be shared across partitions and column
families, not recreated once per shard. Account for indexes/filters, memtables
and iterator-pinned blocks, not only data-block cache. Evaluate a shared cache,
WriteBufferManager, bounded iterator lifetimes and bounded open-file policy;
validate the aggregate working set during compaction. RocksDB documents these
separate consumers and their shared-budget controls.
[RocksDB memory usage](https://github.com/facebook/rocksdb/wiki/Memory-usage-in-RocksDB)

SQLite page caches, decrypted segment buffers and ANN scratch space likewise
share the process memory profile. Opening more partitions must not multiply an
otherwise fixed per-handle cache into unbounded total memory. Admission and
backpressure belong at the shared storage scheduler, without dropping records
or hiding queued time from latency reports.

## Capacity model (illustrative, not measurements)

- 100 million records averaging 1KiB: about 95.4GiB before compression/indexes.
- 100 million 48-byte PQ codes: about 4.47GiB, excluding IDs and index structures.
- One million 384-dimensional FP16 vectors: about 732MiB before graph overhead.
  A mobile cache therefore cannot assume the whole summary index fits in RAM.
- Compression ratio, full-text postings, graph edges, deletion history, WAL,
  compaction headroom and backups must be measured from representative data.
- The inspected T575's 41GiB free space is insufficient for the uncompressed
  example. Use a storage-qualified device/explicit local volume for that test;
  do not silently purge user files, truncate data or upload it elsewhere.

## Performance acceptance contract

Measure the caller-visible duration, including queueing. Report P50/P95/P99,
maximum, deadline misses, throughput, peak RSS/PSS, disk bytes, write amplification,
index freshness and retrieval quality. Do not count canceled/failed/partial
requests as successful sub-100ms results.

Separate durable single-record writes, point reads, lexical top-K, and text-query
hybrid retrieval. The last includes local query embedding and reranking; also
record the storage-only spans to explain bottlenecks. Local model cold loads,
large payload streams and exhaustive exports are separately reported, not hidden
inside the fast profile. Specify input/output bytes, K, concurrency, device,
temperature, cache state and model version for every result.

Test real cardinalities 1K, 10K, 100K, 1M, 10M, 100M and above 100M, with unique
multilingual records, rare facts, conflicts, scoped duplicates and deletions.
Do not simulate 100M by changing a metadata counter or repeating a tiny cached
working set. Preserve datasets for restore/reboot/chaos comparisons.

Small stores use fewer partitions and direct indexed/flat paths; no forced
summary creation, disk ANN load, fan-out or batch wait. Compare controlled
percentiles across sizes. Lower cardinality should reduce work and usually
latency, but individual requests cannot be strictly monotonic because of cache,
OS scheduling, flash GC and fsync variance. The requested absolute 100ms and
strict monotonicity remain unproven; passing a percentile gate is a different
claim and must be labeled as such.

## Implementation sequence

1. Add the benchmark/trace contract and indexed personal-memory API; remove full
   scans from ordinary write, ID lookup, counts, recent pages and UI navigation.
2. Build partition manifests, durable hot deltas, paged migration and compressed
   encrypted segments, including physical restart and corruption tests.
3. Add lexical candidate routing and full-text privacy acceptance; wire the actual
   Agent recall path, not only a test-only repository.
4. Benchmark native ANN backends and envelope-encrypted block access; integrate
   coarse/fine semantic search, local query embedding and bounded reranking.
5. Run the real scale ladder, then public-network-independent chaos under
   compaction, concurrent chat, ASR, low storage, reboot and interrupted backup.

Every phase needs forward recovery and versioned migrations. No phase is full
delivery until the production Agent path and the actual required scale/latency
have passed. PR #2986 is a storage foundation, not completion of this plan.

The first [indexed point-operation implementation](android-personal-memory-point-operations.md)
connects important/private flag changes to direct encrypted row updates and
measures 1,201 and 10,001 real records. Its scope does not include the remaining
full-collection operations, new-event ingestion, sharding or native search.

The next [incremental write implementation](android-personal-memory-incremental-writes.md)
connects ordinary Agent memory creation and duplicate evidence to encrypted
lookup membership and target-only transactions. It also removes the historical
record-count retention budget. Whole-collection recall, backup and legacy
migration, sharding, native search and the required 100M+ scale remain unfinished.

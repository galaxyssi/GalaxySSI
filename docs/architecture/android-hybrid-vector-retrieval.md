# Android hybrid vector retrieval

This stage connects completed encrypted neural vectors to the existing
`SQLiteAgentKnowledgeStore.searchRanked` / `AgentKnowledgeRetriever` path through
an explicitly attached embedding-model factory. Without a configured session,
the existing FTS5 behavior remains unchanged. It is not automatic model selection
or a completed user-facing Memory 2.0 release.

## Retrieval

- ANN uses `com.github.jelmerk:hnswlib-core:1.2.1`, a Java HNSW implementation,
  with cosine distance, M=16, construction ef=160 and search ef=128. This is not
  a handwritten nearest-neighbor engine or hash-derived pseudo-embedding.
- Opaque document keys are enumerated using 32-key keyset pages; authenticated
  vector pages contain at most 64 chunks while building the transient graph.
  Source text is decrypted only for selected candidates and lexical retrieval.
- Up to 128 ANN chunk candidates are deduplicated by document and merged with
  FTS5 lexical ranks using reciprocal-rank fusion (k=60). Lexical-score magnitudes
  are not compared directly to cosine similarity. A provisional cosine floor
  of 0.35 suppresses weak matches; corpus-specific quality calibration is still
  required. Rank fusion is not a learned cross-encoder reranker.
- Current source access policy is applied by the existing RAG evidence filter.
  Query inference never runs under the SQLite transaction or monitor. The
  query-summary statistics call no longer wraps model inference in a database
  transaction; its count is a subsequent metadata snapshot.

## Invalidation and privacy

The encrypted SQLite vectors remain the source of truth. The ANN graph is never
serialized or written to plaintext files. A snapshot binds SQLite's connection
`total_changes()` and cross-connection `data_version`; changes, including
conservative invalidation on backfill or rollback activity, rebuild the cache.
Candidate revision hashes are rechecked against current encrypted source headers
before source resolution. This cache stamp is not a cryptographic anti-rollback
claim about an adversarial operating system.

An epoch fences model loading, graph construction and result publication. A
background/lock boundary, trim-memory callback or close invalidates it without
waiting on the UI thread. A 30-second TTL retires the cache after an in-flight
query finishes instead of cancelling that query; subsequent queries cannot reuse
an expired snapshot. Cleanup releases the independent
embedding context and overwrites owned vectors after any in-flight reader exits.
New queries recreate the encoder from its explicit factory. Native tensor pages
are released, but physical RAM erasure inside the engine is not guaranteed.
Existing ASR and chat model contexts are not touched.

The ANN admission estimate is `64 KiB + count * (dimensions * 4 + 2048)` bytes,
with a default budget of the smaller of 64 MiB and one eighth of maximum JVM heap.
This is a conservative planning estimate, not a hard peak-RSS guarantee or a
knowledge-count retention cap. If the complete graph does not fit, semantic
retrieval reports unavailable and lexical retrieval continues; no source/vector
records are silently omitted or deleted to fit the graph. Disk-backed/sharded
ANN is still needed for corpora exceeding resident graph capacity.

## Integration boundaries

`attachSemanticEncoder(spec, factory)` owns an independent model session. It is
exercised through the actual store/RAG interface in device tests, including after
database reopen. Version 1.1.18 adds production model import/download UI,
persistent configuration and automatic indexing/backfill scheduling; see
[semantic model lifecycle](android-semantic-model-lifecycle.md). Background graph
prebuilding is not wired yet. A first query may rebuild the full graph on its worker thread. Large-corpus
cold rebuild latency is not certified by small-corpus hot-query results.

The default knowledge API therefore remains FTS5 until a session is configured.
No model is bundled or downloaded without user action. The independent model
lifecycle preserves existing local chat model choices; background indexing
contention still needs representative concurrent-chat performance acceptance.

## References

- [hnswlib source and API](https://github.com/jelmerk/hnswlib)
- [Pinned artifact and dependency/license metadata](https://repo.maven.apache.org/maven2/com/github/jelmerk/hnswlib-core/1.2.1/hnswlib-core-1.2.1.pom)
- [Encrypted vector checkpoints](android-encrypted-vector-checkpoints.md)
- [Independent neural encoder](android-neural-embedding-runtime.md)

The HNSW core is Apache-2.0 licensed. Its declared production dependency is
Eclipse Collections 9.2.0; this dependency is resolved through Gradle rather than
copying source code or vendoring a modified ANN engine.

## Validation evidence (2026-09-09)

Android 1.1.17 (903) was built and installed in place on SM-T575, with no user-data
reset. Before this run the device reported 1,749,480 KiB available memory and
41 GB available data storage.

- 43 selected JVM tests passed, including HNSW recall over 1,201 synthetic vectors,
  memory admission, duplicate/invalid vectors, close, rank fusion, chunking and
  existing knowledge regressions. Synthetic vectors validate ANN behavior, not
  natural-language retrieval quality.
- The ten new device tests passed through actual SQLite store/RAG calls: semantic
  matches without lexical overlap, cloud-policy enforcement and revocation,
  source invalidation, concurrent source mutation, malformed ciphertext, memory
  fallback, UI-thread avoidance, nonblocking lifecycle cancellation and TTL.
- Pinned BGE Chinese retrieval after encrypted database reopen: recall@1 3/3.
  Across 100 hot store queries, P50 141 ms / P95 183 ms / P99 192 ms. These timings
  include query embedding, ANN, source resolution and FTS/rank fusion for a
  three-document corpus, not large-corpus cold graph construction.
- The existing 1,201-document synthetic-vector persistence case completed in
  97,855 ms with its pending queue drained. This is not model inference throughput.
- The combined storage, FTS5, encoder, vector and hybrid suite completed in
  573.626 seconds: 45 passed and one intentionally skipped two-phase reboot
  harness. This run preceded the final TTL in-flight-query refinement; that
  refinement is covered by a separate final hybrid-suite run, not counted as
  part of those 45 passes. The earlier real reboot evidence belongs to the
  checkpoint stage and is not claimed as a new reboot in this run.
- Native packaging checks passed: 73/73 AArch64 libraries have 16 KiB alignment;
  24 QNN libraries (221.68 MiB) passed manifest validation.
- Both Eclipse Collections license resources are retained in the APK. The core
  and API JAR copies were checked byte-identical before selecting one copy each.
- After the TTL refinement, all 43 JVM tests passed again. The final 11-test
  hybrid device suite passed without skips in 20.387 seconds, including a query
  intentionally spanning TTL expiry and the real Chinese model/store/RAG test.
  Its 100 hot samples measured P50 117 ms / P95 153 ms / P99 159 ms. Both native
  packaging gates were rerun successfully on this final APK.
- Final force-stop/cold launch completed with ActivityManager TotalTime 2,762 ms
  (one sample, not a startup percentile or full-content readiness measurement).
  The device crash buffer was empty after the tests and launch.

APK SHA-256:
`25f0e8b04325d9ae3bb032ae4788b6b8525706b24163b9b085da2ccb499a09b7`.

Local evidence: `build/hybrid-vector-verified-build.log`,
`build/hybrid-vector-device.log`, `build/hybrid-vector-metrics.log`,
`build/hybrid-vector-16kb.log` and `build/hybrid-vector-qnn.log`.
Final refinement evidence: `build/hybrid-vector-release-build.log`,
`build/hybrid-vector-final-device.log`, `build/hybrid-vector-release-16kb.log`
and `build/hybrid-vector-release-qnn.log`.

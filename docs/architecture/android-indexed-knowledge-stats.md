# Indexed knowledge context statistics

Android 1.1.100 connects `AgentKnowledgeDatabase.stats()` to the transactional
source directory instead of `COUNT(*)`, `COUNT(DISTINCT source_key)` and
`MAX(updated)` over the full knowledge table. The old aggregate was still used
by ordinary Agent context construction through `querySnapshot`, despite source
browsing already having incremental counts.

## Read path

- Read the validated `knowledge_source_state` singleton for item and named-source
  counts. Blank-source items are counted as items but not named sources, matching
  the old `NULLIF(source_key,'')` behavior.
- Read the first entry of the existing covering `knowledge_updated` index for
  the latest timestamp, using `ORDER BY updated DESC,item_key LIMIT 1`.
- Return all fields from the same database transaction, without decrypting
  bodies, loading an embedding model or enrolling sources in the request.
- Count fields use 64-bit values end to end in `AgentKnowledgeStats`, Agent
  context summaries and knowledge-overview action parameters.

New databases and live insert/update/delete transactions already maintain the
source directory exactly. Existing databases may be partway through its bounded
background enrollment. In that case `countsComplete=false` explicitly labels
the counts as lower bounds rather than scanning the corpus or falsely reporting
an empty database. Latest timestamp still comes from the canonical index.
The existing source-maintenance worker resumes from its durable cursor.

This is a query-path improvement, not source-data partitioning. The canonical
knowledge database still uses one WAL database, while native vectors and
provenance have physical shards. A future canonical partition implementation
must preserve pinned WAL export snapshots and atomic visibility of source
bodies, full-text entries, revision barriers and vector replay work. Simply
switching those tables to attached rollback-journal databases would serialize
long exports against writes and is not an acceptable substitute.

## Verification scope

Targeted tests cover exact live counts, blank/named source semantics, timestamp
replacement and deletion, rollback, reopening, explicit partial enrollment,
missing counter state, covering-index query plans, values above signed 32-bit
range and real encrypted-store reads without body decryption. The 64-bit
arithmetic fixture is not a claim that billions of records were inserted.

An opt-in SM-T575 benchmark seeds actual SQL metadata rows at 1,024, 10,240,
102,400 and 1,000,000 records with the real directory triggers. It compares the
old aggregate against the indexed path on the same fixture and records all
query samples. Seeding is excluded from query latency; reopen consistency is
checked. These fixtures do not include encrypted source bodies, neural
embeddings or UI work and do not establish 100M capacity or universal 200ms
latency.

## Verified results (2026-09-12)

Android 1.1.100 (986) was installed with `adb install -r` on SM-T575 only.
No production database was exported, no app data was reset, and retained scale
fixtures were preserved. The benchmark fixture remains on that device.

| Actual metadata rows | Old aggregate P95 (ms) | Indexed P95 (ms) | Indexed maximum (ms) |
| ---: | ---: | ---: | ---: |
| 1,024 | 0.840 | 0.218 | 3.631 |
| 10,240 | 6.436 | 0.146 | 0.229 |
| 102,400 | 68.446 | 0.139 | 0.287 |
| 1,000,000 | 789.712 | 0.155 | 0.307 |

Each size has 8 aggregate samples and 64 indexed samples. All 256 indexed
samples were below 200 ms; the 8 aggregate samples at one million rows were
above 200 ms. Small sample counts, cache warmth and fixed measurement order
limit percentile interpretation: these are descriptive sample statistics, not
production P95 guarantees. Smaller databases need not be faster in every
sample because scheduling and cache effects can dominate this bounded query.

The SQL fixture occupies 973,438,976 bytes before final close. It contains
actual metadata, source-directory rows and indexes, not encrypted bodies.
The benchmark verifies each result against the original SQL and verifies
consistency after reopening at every size. It passed in 53.249 seconds including
seeding; insertion timings were not separately measured. These results do not
establish semantic retrieval, write latency, end-to-end Agent latency, or
100-million-record capacity.

Additional verification:

- Full JVM suite: 3,781 tests, 0 failures, 0 errors, 5 existing skips.
- Device regressions: 63 tests passed in 394.952 seconds, covering the new
  indexed path plus FTS, encrypted storage, identity, backup, hybrid search and
  source-directory behavior.
- Debug app, instrumentation APK and JVM tests built successfully in 9m 7s.
- Android 16 KiB alignment audit: all 74 ARM64 native libraries passed.
- Repository guard and whitespace checks passed.

Raw benchmark samples, exact summaries, APK hashes and validation metadata are
in [the evidence directory](evidence/indexed-knowledge-stats-20260912/).

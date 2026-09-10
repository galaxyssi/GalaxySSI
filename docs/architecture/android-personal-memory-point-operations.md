# Indexed personal-memory point operations

## Scope

Android 1.1.61 (947), based on main after PR #2987. This is the first
indexed-operation step of the [100M+ memory design](scalable-memory-100m.md),
not delivery of the full partitioned native engine or a 100ms guarantee.

The existing encrypted row primary key is sufficient to locate one memory.
No new native library, plaintext index, total-count limit, unbounded cache or
additional copy of the complete memory collection is introduced.

## Production changes

- `AgentPersonalMemoryRows.find(id)` reads the encrypted metadata and requested
  row. It validates the requested identity and payload without decoding unrelated
  rows. The ID lookup is an internal repository API, not an authorization bypass
  for Agent recall.
- `EncryptedAgentMemoryStore.setImportant` and `setPrivate` use
  `updateFlags`, committing only the target row and metadata revision in one
  SQLite transaction. Counts, encrypted ordering, provenance and scope do not
  change. No-op updates do not rewrite ciphertext or revision.
- Important flags remain restricted to active memories; privacy changes retain
  the previous behavior for historical records. Missing IDs return failure,
  while corrupt target rows or metadata raise an error rather than overwriting
  damaged data or selecting a different memory.
- Observation publication receives only the target's before/after records.
  Tests compare its events with the former full-collection delta, including
  retracting a formerly visible memory when it becomes private. Private text
  is not added to the retraction event.

The same process lock still serializes mutations. Different store wrappers
cannot overwrite each other's flag changes. The row and revision roll back
together when a metadata write fails. This does not establish multi-process
writer coordination or power-loss durability beyond the existing database
configuration. Benchmark results must not claim a new fsync guarantee.

## Remaining full-collection paths

Legacy migration, ordinary remember/update/delete, conflict normalization,
recent/snapshot/recall and backup import/export still need bounded indexed or
streaming replacements. An initial legacy migration or contention with these
operations can delay a point operation. The UI may still reload its snapshot
after a flag update; the storage improvement does not prove a faster whole
screen refresh.

The old backup/export representation is specifically not compliant with the
new prohibition on giant JSON; it remains a tracked migration item, not an
exception to the target architecture. The current internal point lookup is
not lexical or semantic retrieval and does not include embeddings/reranking.

## Verification protocol

The device tests use isolated fixture databases on T575, not the user's
personal memories. They cover unrelated corrupt rows, missing IDs, historical
flags, no-op writes, transaction rollback, identity/metadata damage and
concurrent updates. Four JVM tests verify event-delta equivalence and privacy.

The performance test stores actual 1,201 and 10,001-record datasets. It measures
100 indexed reads and 100 real important-flag writes per size, logging P50,
P95, P99, maximum and requests at or above 100ms. Observations are disabled in
these isolated fixtures, so these are repository operation measurements, not
end-to-end Agent or UI timings. The test reports slow samples rather than
silently excluding them or changing the requested latency target.

Neither scale proves 100M behavior. A larger corpus, new-record durable writes,
full recall, read quality, startup, cache pressure, competing ASR/chat workloads,
disk capacity and native-backend acceptance remain required.

## Measured results

T575, Android 1.1.61 (947), 2026-09-10. The dataset was freshly written before
each measurement loop; these are warm same-process operations, not cold-start
or sustained loaded-device percentiles. There were 100 reads and 100 changed
important-flag writes at each size. All times below are milliseconds.

| Records | Operation | P50 | P95 | P99 | Maximum | At least 100ms |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | ID read | 8.35 | 11.39 | 14.39 | 16.32 | 0/100 |
| 1,201 | Flag write | 20.20 | 27.43 | 32.56 | 39.42 | 0/100 |
| 10,001 | ID read | 10.47 | 17.70 | 20.42 | 20.87 | 0/100 |
| 10,001 | Flag write | 22.01 | 32.60 | 35.20 | 36.85 | 0/100 |

The earlier 5,896ms measurement read every one of 1,201 rows. It is not the
same operation as an indexed lookup, so it must not be presented as a measured
end-to-end speedup for Agent recall. These samples support proceeding with
indexed APIs, not extrapolating a 100M guarantee.

The pre-run device inspection reported 1,875,688KiB available RAM, approximately
41GiB free storage and battery temperature 32.6C. These are baseline samples,
not peak-memory or thermal-throttling measurements. Original install time
2026-09-07 07:17:23 was retained; update time was 2026-09-10 20:11:16.

Build and unit tests passed in 8m 43s: 3,573 tests, zero failures/errors and five
existing skips. The four new event-delta tests all passed. Repository guard,
73-library 16KB audit and QNN package audit passed. The main APK SHA-256 is
`6FAF14DB1E9C445B78D12E6D169984CDB73F684E63E6AF40383E133D05DF919D`.

The device memory group passed all 51 tests in 326.051s, with no skips or
failures. This includes the eight new point-operation tests and 43 existing
row, deletion, retraction, identity and asynchronous UI-work regressions.
The image/attachment/timing regression group passed all 22 tests in 26.169s,
also with no skips or failures. This is not a new end-to-end local-model
performance or hundred-million-record acceptance claim.

Logs are under `build/personal-memory-point-{build,device,regression,timings,repo,16kb,qnn}.log`.

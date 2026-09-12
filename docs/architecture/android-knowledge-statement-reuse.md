# Android knowledge statement reuse

## Scope

The schema-14 primary body partitions remain authoritative. This phase reduces
repeated SQL compilation in the shared knowledge SQLite adapter; it does not
change record encryption, synchronous durability, catalog visibility, partition
rotation or any model execution path.

Each connection owns up to 32 idle compiled statements and 65,536 UTF-16 SQL
characters. Leased cursors are never shared, including simultaneous executions
of identical SQL. Oversized SQL is finalized rather than retained. Eviction uses
idle-return order. These limits bound cache entries and SQL text, not the entire
application's native memory or the caller's already-existing active cursors.

Successful returns reset the statement and clear all bindings before reuse.
Failed execution or binding discards the statement. Connection close finalizes
both active and idle statements and invalidates outstanding cursors. No result
rows, decoded knowledge bodies or parameter values are cached by this layer.
SQLite retains responsibility for recompilation after schema changes.

This uses the documented AndroidX [SQLiteStatement reset and clearBindings
APIs](https://developer.android.com/reference/kotlin/androidx/sqlite/SQLiteStatement).
The connection's existing transaction nesting and rollback-only behavior remain
unchanged. There is no reduction of FULL synchronization or encryption checks.

## Validation boundaries

`tools/dev/test-knowledge-statement-reuse.ps1` targets only the designated
SM-T575. Its 12 cases cover reuse, cleared bindings, concurrent cursors, constraint
failures, nested rollback, bounded eviction, schema/trigger changes, close,
read-lock release, failed stepping and typed binding replacement. Its `durable`
phase separately probes the public store API against the retained real corpus.

The final case alternates disabled/enabled/enabled/disabled caching in isolated
512-row transactions. Each transaction includes its durable commit, every row
is checked afterwards, and preparation counts prove reuse independently of
device timing noise. It is a low-level SQL comparison, not a memory-model or
100-million-record benchmark.

Full validation must also rerun encrypted storage, primary partition, snapshot,
backup, vector, count and recovery coverage. The retained 10,001-real-record
source must be rewritten and verified without reseeding a smaller fixture.
The previous phase measured 689,018 ms for that replacement. The same-scale
result and its remaining performance limitations are recorded below.

## SM-T575 measurements, 2026-09-13

Android 1.1.112 (998) was built and installed without uninstalling or clearing
the retained corpus. The 12 statement cases and 15 primary partition cases
passed, as did all three intentional process-death boundaries and their four
normal preparation/verification cases. The JVM report has 3,823 passed tests,
five existing skips, no failures and no errors. All 74 Android AArch64 libraries
passed the 16 KiB alignment check.

The isolated 512-row transaction comparison returned the following results;
post-transaction reads verified every row in each case:

| Order | Cache capacity | Transaction ms | Explicit prepares | Reuses |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0 | 238.161 | 2,052 | 0 |
| 2 | 32 | 143.292 | 7 | 2,045 |
| 3 | 32 | 133.664 | 7 | 2,045 |
| 4 | 0 | 159.447 | 2,052 | 0 |

The retained 10,001-record replacement with variant `statement-reuse-v1`
passed complete close/reopen verification. Replacement took 448,713 ms and
verification 58,087 ms, for a 506.920-second complete test. The live catalog
reported 30 explicit prepares, 160,011 reuses, 30 idle statements and 1,700 idle
SQL characters. SQLite-internal schema recompilation is not counted by these
driver preparation counters.

The current observation is approximately 35 percent lower than the previous
689,018 ms primary-partition run. This is not a controlled device thermal/CPU
comparison or proof that every millisecond of the difference came
from statement reuse. The earlier pre-partition result was 327,999 ms, which
this result still exceeds. Bulk performance remains open.

Source preparation took 61,963 ms, ownership checks 42,666 ms, source application
308,774 ms and observation 30,631 ms. Ownership and application are nested within
the 352,547 ms commit phase, so they must not be summed with it. Full-result
retrieval and durable per-record latency at 100 million records remain unproven.

### Public durable API

The retained 10,001-record corpus was also used for 100 public `findByIds`
calls, 100 individually committed `upsert` calls and 100 individually committed
restores. Each update was read back and restored to its exact prior record in
`finally`; a close/reopen pass rechecked the 100 IDs and the 10,001 total count.
There is no surrounding transaction hiding the final commit from these samples.

| Warm store operation | Samples | P95 ms | P99 ms | Maximum ms | Within 200 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Public record lookup | 100 | 21.420 | 55.665 | 141.402 | 100 |
| Durable upsert | 100 | 81.285 | 110.838 | 164.754 | 100 |
| Durable restore | 100 | 76.485 | 95.667 | 100.495 | 100 |

These measurements include storage key resolution, record decoding and the
individual partition/catalog commits where applicable. The test's observer is
disabled and no model, embedding, UI or network work is measured. The results
close the transaction-internal timing gap at this size, not the remaining
100-million-record, full agent-path or universal latency requirements.

The 95-case legacy/vector, 22-case counter, 97-case source/backup/search and
three-case crypto profile suites also passed. The legacy regression process,
which includes the large Unicode case, had a cumulative VmHWM of 1,333,240 KiB
and a later VmRSS sample of 283,368 KiB. This phase does not solve the large-record
memory peak or establish a controlled memory comparison with the preceding phase.

The separate low-level crypto profile measured retained body reads at P95
18.815 ms and transaction-internal writes at P95 38.553 ms. Those scopes differ
from the public API table above; the internal writes exclude final commits.
Raw measurements and bounded regression summaries are in
[the evidence directory](evidence/knowledge-statement-reuse-20260913/summary.json).

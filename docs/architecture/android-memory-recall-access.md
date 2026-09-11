# Incremental recall access updates

Development version: Android 1.1.66 (952), based on main `81fec4a17` after the
streaming-backup PR #2992 was merged.

The ordinary personal-memory recall path previously loaded all records for
ranking, then called the bulk replacement API to update access times. The new
access path reads and updates only returned identities and the metadata revision
in one transaction. It preserves the five-minute write interval, original
timestamps, ordering, counts, lookup membership and unrelated ciphertext.

Current rows are re-read under the existing memory lock before updating. Missing,
private, expired, conflicted and superseded rows are not refreshed. A selected
corrupt row or failed transaction cannot partially update other selected rows.
No model, ASR lifecycle or global-agent activation is introduced.

This does **not** yet remove the initial full-corpus lexical scan from recall.
Indexed candidates, progressive index migration, sharding and native vector
retrieval are still required. The new access-only benchmark is not an end-to-end
recall benchmark and must not be presented as one.

On 2026-09-11 the user accepted a latency budget of at most 200ms for reads,
retrieval and writes. Tests retain historical `misses100` and add `misses200`
(strictly greater than 200ms) with P50/P95/P99 and maximum. The new access test
also preserves all raw samples at 1,201 and 10,001 actual stored records. No
retention cap, durability or privacy requirement was relaxed.

## Verification on 2026-09-11

The app and instrumentation APKs built successfully. JVM tests discovered
3,623 cases: 3,618 passed, five existing skips, zero failures or errors. The APK
passes the 16KiB alignment audit for all 73 AArch64 libraries and the QNN package
audit. These are packaging checks, not new ASR/QNN inference measurements.

Android 1.1.66 (952) was installed with `adb install -r` on the authorized T575
only; user data was not cleared. The installed package version was checked.
App APK SHA-256:
`9A05CAE0395E18A9401A1FBC3DC6FE43FC03E1B44265F623E4C5C85185CDE5EF`.

All seven new device tests passed: six functional cases in 1.984s, followed by
the real-cardinality benchmark in 241.516s. Coverage includes actual recall,
write throttling, excluded states, unaffected ciphertext, selected corruption,
and transaction rollback. Test data uses isolated databases and does not replace
the user's memories, contacts, pairing or conversations.

Each row below contains 100 caller-timed operations after fixture creation and
browse-index initialization. The operation includes selected-row reads,
encryption, metadata update and the existing database transaction, but excludes
initial corpus creation, index backfill, cleanup and the initial recall scan.

| Actual rows | Updated rows per operation | P50 ms | P95 ms | P99 ms | Max ms | >200ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,201 | 1 | 19.18 | 33.22 | 36.66 | 38.25 | 0/100 |
| 1,201 | 8 | 87.30 | 134.69 | 150.05 | 153.40 | 0/100 |
| 10,001 | 1 | 32.00 | 39.34 | 44.23 | 45.57 | 0/100 |
| 10,001 | 8 | 136.60 | 159.19 | 162.73 | 163.94 | 0/100 |

All 400 raw samples were retained and independently recounted from the log.
They show zero misses at the revised 200ms budget, not a universal latency
guarantee. Historical 100ms misses are also retained: zero for single-row
updates, 14/100 and 75/100 for eight-row updates at the two respective sizes.
No controlled before/after run or memory-peak measurement was performed here.

All 39 selected existing identity, point-operation, pagination and migration
device regressions also passed in 100.593s. Together with the seven new cases,
this phase has 46 unique passing device tests. Repository checks and
`git diff --check` passed.

Local evidence:

- `build/memory-recall-access-build.log`
- `build/memory-recall-access-core-device.log`
- `build/memory-recall-access-latency-device.log`
- `build/memory-recall-access-latency-logcat.log` (aggregates and raw samples)
- `build/memory-recall-access-regression-device.log`
- `build/memory-recall-access-16kb.log`
- `build/memory-recall-access-qnn-package.log`

The three existing browse, point and new-memory benchmark reporters now emit
`misses200`; their large benchmarks were not repeated in this narrow access
change. Previous reports cannot establish their exact 200ms miss counts. The
full-retrieval, sharding and 100M+ acceptance targets remain unfinished.

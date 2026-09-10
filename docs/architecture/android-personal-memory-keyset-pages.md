# Personal-memory keyset pages

Android 1.1.64 (950), based on main after PR #2990. This continues the incremental-write work in PR #2989;
it is not completion of the [100M+ memory architecture](scalable-memory-100m.md).

## Production paths

- The personal-memory management page uses database pages, not `snapshot()`.
- Saved memories, conflict groups and history are separate views, with 25 rows
  per page. Both directions use boundary cursors; there is no growing stack of
  previous pages or decrypted records. History is no longer a fixed 20-item view.
- The personal-memory overview reads maintained 64-bit counts instead of loading
  bodies. Category counts are fetched together; control-center page preparation
  runs off the UI thread. Other global-memory dashboard snapshots are unchanged.
- The actual encrypted store's `recent(limit)` uses the same index, excluding
  private and expired entries before returning records to its caller.
- Conflict candidates are loaded only when the user opens one group. A genuine
  large conflict group still requires its candidates for the existing review UI;
  this PR does not claim to bound that dialog independently of group size.
- Usage details remain available on opening a memory. The list no longer scans
  the usage ledger for every visible row, and detail loading is off the UI thread.

The default page size is a request/working-set bound, not a stored-record limit.
An explicitly large `recent(limit)` request can still return multiple pages to
its caller; normal bounded callers do not read the whole corpus.

## Ordering and cursors

Saved records retain important-first, newest-first order. History uses newest
first. Stable row positions break timestamp ties, including backdated input and
the entire signed 64-bit timestamp range. Conflict groups retain their latest
candidate time and first member position for ordering.

The query uses a composite row-value seek on priority, reverse timestamp,
position and opaque row key. Reverse timestamp is bitwise inversion, not an
overflow-prone negation of `Long.MIN_VALUE`. It is an ordering representation,
**not encryption**. Reverse navigation seeks in the opposite direction.
Multi-kind filters seek individual indexed streams and merge at most
`(limit + 1) * selected-kind-count` metadata records before decrypting a page.

This follows SQLite's documented row-value scrolling pattern, rather than
`LIMIT ... OFFSET ...`, whose work increases with skipped rows.
[SQLite row-value scrolling](https://www.sqlite.org/rowvalue.html#scrolling_window_queries)

Cursors carry the store's index generation, source revision and query scope.
Cross-store/filter cursors are rejected; changed source revisions require a
restart from the first page. The UI handles this without mixing old and new
pages. Arbitrary corruption of an omitted index entry is not a complete
integrity audit; selected bodies and maintained counts are validated.

## Transactions and migration

The derived tables live in the same SQLite database as encrypted source rows.
Record, flag, restore, scope, conflict and deletion mutations update their index
metadata and counters in the source transaction. An index failure rolls back
source bodies, counters, lookup membership and revision together.

Existing stores lazily backfill the index using 128 source keys per batch in
one transaction. No giant index JSON or in-memory corpus is created. A marker
is committed only after source-count validation; failed builds can retry from
the authoritative rows. This migration is not yet resumable between batches,
and it holds the memory/database writer lock until completion. Cold migration
time must be reported separately, never passed off as a sub-100ms first page.

Deleting the encrypted readiness marker (including database clear) clears the
derived tables through a SQLite trigger. User source rows are never deleted to
repair a missing marker. Missing/invalid keys and count mismatches fail rather
than becoming a falsely empty memory list.

## Privacy boundary

Body values, raw memory keys, scope identifiers, origins and conflict IDs remain
in the existing AES-GCM authenticated encrypted records. Conflict lookup keys
use a Keystore-backed HMAC over the scoped identity, including legacy unkeyed
conflicts. Query results verify relevant metadata against their encrypted body;
changing an index privacy flag cannot release a private body as public.

The standard SQLite derived index **does expose metadata**: classification,
private/priority flags, sortable timestamps, expiry, row positions, counts,
equality and access patterns. This application-layer encryption is not
SQLCipher/full-page encryption and does not protect those fields from an actor
who can read database pages. The design does not claim all database bytes are
ciphertext. Page/block encryption remains unfinished work in the larger plan.
No memory content is uploaded and no local model is downloaded by this change.

## Validation and remaining scope

Targeted tests cover forward/backward boundaries, ties, long-range timestamps,
kind-stream merging, cursor isolation, counts, private/expired filtering,
conflicts (including unkeyed legacy groups), corruption, rollback, clearing and
the query planner's composite index. The UI test uses synthetic display counts
and fixtures; displaying 100M in a label is not a storage-capacity benchmark.

Actual datasets start at 1,201 and 10,001 rows. Warm page-8, page-25, recent-8
and incremental-write calls are measured with 100 samples per size, reporting
P50/P95/P99, maximum and the number of >=100ms samples. The one-time migration is measured
separately. The benchmark also checks physical source/index row counts after
the 100 new writes; it does not simulate cardinality with a metadata counter.

### Preliminary T575 measurements

The preliminary application APK has SHA-256
`466060691CF57AF0C5F89AEB9BB529DA4BDFD83F7E2290372CC321854ED5AF84`.
It was installed in place on SM-T575 at 22:55:16 on 2026-09-10, retaining the
original 2026-09-07 installation and data. No other connected device was changed.
Before the run, the tablet had approximately 1,776,104 KiB available memory,
41 GiB free data storage, 100% battery and a 30.1 C battery temperature.

Each operation below has 100 samples. These are synchronous, same-process
repository calls through return, not queue-admission times, UI frame latency,
semantic recall or embedding/model latency. Fixture observation publication is
disabled. Page-8 advances its cursor; page-25 repeatedly opens the first page.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | Page of 8 | 53.26 | 79.15 | 85.18 | 86.96 | 0/100 |
| 1,201 | Public recent 8 | 53.61 | 80.66 | 90.94 | 124.04 | 1/100 |
| 1,201 | Page of 25 | 132.76 | 216.97 | 228.54 | 237.67 | 100/100 |
| 1,201 | New record with browse index | 40.13 | 46.99 | 54.20 | 58.14 | 0/100 |
| 10,001 | Page of 8 | 52.37 | 59.90 | 62.85 | 64.99 | 0/100 |
| 10,001 | Public recent 8 | 52.00 | 58.38 | 68.29 | 69.05 | 0/100 |
| 10,001 | Page of 25 | 129.28 | 199.70 | 213.52 | 213.60 | 100/100 |
| 10,001 | New record with browse index | 62.10 | 78.41 | 82.75 | 84.18 | 0/100 |

The lazy index migration took **7,005.28ms** for 1,201 rows and **50,339.05ms**
for 10,001 rows, excluding initial fixture creation. Neither cold path meets
100ms. Of 800 warm-operation samples, 201 also reach or exceed 100ms. In
particular, every measured 25-row page exceeds the requested threshold. The
default page was not shrunk to hide that result. Smaller cardinality does not
give strictly lower observed latency in every operation. No unconditional
latency or strict monotonicity claim has passed.

The 15 storage/benchmark device cases and initial UI hierarchy case passed in
306.832s. The initial screenshot caught the startup overlay, so it is not visual
acceptance; the UI test now waits for overlay removal and actual visible layout.
That APK also exposed avoidable flag-write overhead: the changed flag and
metadata were decrypted again by the streaming write API's unchanged-value
check. Flag writes now retain their original direct transaction API with an
index observer, avoiding those redundant decryptions. These initial timings are
preserved; final APK results must be recorded separately rather than replacing
slower observations with a later run.
The JVM suite passed 3,591 tests with zero failures/errors and five existing
skips. Repository, 16KiB native alignment (73 libraries), QNN package (24
libraries) and the three memory-evaluator checks passed.

Local raw files are `build/personal-memory-browse-final-build.log`,
`build/personal-memory-browse-device.log`,
`build/personal-memory-browse-timings.log` and
`build/personal-memory-browse-regression.log`. Measurements were logged by PID
29896 at 22:57:53 and 23:01:29 on 2026-09-10. The screenshot's 100,000,001 display
count is synthetic and must not be cited as a 100M storage test.

The preliminary APK also passed all 91 existing regressions in 902.173s, zero
failed/skipped. Its corrected visible-UI test passed in 4.354s; the captured
page was inspected, with readable Chinese labels and no overlapping controls.
These are preliminary results, not acceptance of the later direct flag-write
change. The same preliminary regression process (PID 30632) also produced the
following repository measurements; none of its slow samples are discarded.
These fixtures do not enable the browse index before their measured operations.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | New record | 48.57 | 83.28 | 86.26 | 95.18 | 0/100 |
| 1,201 | Duplicate evidence | 61.56 | 93.41 | 115.02 | 117.29 | 4/100 |
| 10,001 | New record | 62.40 | 97.44 | 171.07 | 192.44 | 4/100 |
| 10,001 | Duplicate evidence | 77.80 | 109.63 | 196.43 | 244.59 | 8/100 |
| 1,201 | ID read | 15.37 | 20.54 | 22.97 | 27.05 | 0/100 |
| 1,201 | Important flag | 44.19 | 54.69 | 70.33 | 79.94 | 0/100 |
| 10,001 | ID read | 19.29 | 38.36 | 195.25 | 572.86 | 4/100 |
| 10,001 | Important flag | 57.62 | 84.09 | 90.40 | 139.07 | 1/100 |

Raw regression measurements are in
`build/personal-memory-browse-regression-timings.log`; filter PID 30632 to
separate this APK from earlier runs still present in the device log buffer.

### Second candidate before main synchronization

The direct flag-write candidate, still locally numbered 1.1.63, had SHA-256
`1D6AB675248BD479184D4D1642A2E9DDCF77B28BA1B0C327F1048AAF59A60BC6`.
Its 16 storage/UI cases passed in 477.044s. Before publication, main advanced
through PR #2990, which also used 1.1.63. The final branch therefore incorporates
that merge and uses 1.1.64. These second-candidate observations are not final
1.1.64 acceptance. PID 407 logged them at 23:23:15 and 23:29:34 on 2026-09-10.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | Page of 8 | 78.57 | 102.33 | 131.77 | 154.60 | 7/100 |
| 1,201 | Public recent 8 | 68.25 | 93.00 | 101.82 | 181.81 | 2/100 |
| 1,201 | Page of 25 | 205.09 | 245.62 | 260.97 | 263.98 | 100/100 |
| 1,201 | New record with browse index | 62.67 | 85.33 | 94.51 | 95.09 | 0/100 |
| 10,001 | Page of 8 | 112.90 | 125.70 | 129.07 | 131.75 | 100/100 |
| 10,001 | Public recent 8 | 111.92 | 124.15 | 128.28 | 131.48 | 100/100 |
| 10,001 | Page of 25 | 282.32 | 295.82 | 303.33 | 385.60 | 100/100 |
| 10,001 | New record with browse index | 87.55 | 98.61 | 102.78 | 102.98 | 3/100 |

Migration took 6,263.56ms and 102,036.07ms respectively. There were 412 warm
samples >=100ms out of 800, so even the smaller page size does not establish an
unconditional 100ms bound. Removing flag-write decryptions does not establish a
page-read speedup. At the end of this run the tablet reported approximately
1,809,248 KiB available memory and a 32.3 C battery temperature. No system power
or scheduling settings were changed to improve benchmark results.
Raw files are `build/personal-memory-browse-acceptance-{build,device,timings}.log`.

### Final 1.1.64 application

Final application SHA-256:
`112FF5E16D59AA0B81C3C1712FF25B1C20C94CF3946EC9AF9E5DBD38CA603B97`.
SM-T575 received versionCode 950 in place at 23:38:41 on 2026-09-10; the original
installation date and data remained intact. Main is based on `5a30c9ec7`.
The final JVM run contains 3,596 tests, zero failures/errors and five existing
skips. Repository, 73-library alignment and 24-library QNN package checks passed.

All 16 pagination/storage/UI instrumentation cases passed in 358.159s. The
final screenshot was inspected with the startup overlay absent and Chinese
labels, rows and navigation visible without overlap. This is bounded-page
rendering validation, not a measured end-to-end UI latency or frame-rate gate.
PID 3426 emitted these 100-sample-per-operation results at 23:40:21 and 23:44:47:

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | Page of 8 | 70.51 | 122.23 | 247.88 | 258.99 | 12/100 |
| 1,201 | Public recent 8 | 67.22 | 112.40 | 132.49 | 145.29 | 9/100 |
| 1,201 | Page of 25 | 133.97 | 153.81 | 196.97 | 230.64 | 100/100 |
| 1,201 | New record with browse index | 43.34 | 70.20 | 73.29 | 76.29 | 0/100 |
| 10,001 | Page of 8 | 106.13 | 144.18 | 289.44 | 292.89 | 93/100 |
| 10,001 | Public recent 8 | 105.11 | 122.45 | 171.66 | 193.56 | 86/100 |
| 10,001 | Page of 25 | 281.95 | 303.67 | 315.97 | 318.39 | 100/100 |
| 10,001 | New record with browse index | 90.63 | 125.05 | 308.79 | 667.29 | 14/100 |

Migration took 6,399.67ms and 63,481.10ms. There are **414/800 warm samples at or
above 100ms**. The absolute latency requirement has not passed, even at these
modest cardinalities. The 667.29ms write must not be hidden by P50/P95 reporting.
This change establishes indexed paging and atomic maintenance, not the complete
100M+ engine or its performance acceptance. More work is required on encrypted
I/O granularity, migration scheduling and full retrieval/backup paths.

Final raw build/device/timing files use the
`build/personal-memory-browse-v1164-` prefix. Earlier candidate results above
remain available for comparison, rather than choosing the fastest trial.

The final application's existing regression benchmarks (PID 4072, 23:47:49
through 23:55:43 on 2026-09-10) measured the following operations. These fixtures
do not initialize the browse index before measurement; they are separate from
the indexed-write/page benchmarks above. Each operation has 100 samples.

| Starting rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms | Samples >=100ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1,201 | New record | 83.88 | 92.26 | 98.32 | 100.84 | 1/100 |
| 1,201 | Duplicate evidence | 106.94 | 116.97 | 118.37 | 119.77 | 99/100 |
| 10,001 | New record | 83.91 | 93.74 | 96.39 | 96.45 | 0/100 |
| 10,001 | Duplicate evidence | 106.69 | 114.04 | 117.73 | 118.15 | 98/100 |
| 1,201 | ID read | 19.45 | 22.67 | 26.66 | 27.18 | 0/100 |
| 1,201 | Important flag | 40.18 | 45.40 | 49.14 | 55.26 | 0/100 |
| 10,001 | ID read | 8.14 | 17.47 | 19.50 | 23.59 | 0/100 |
| 10,001 | Important flag | 19.97 | 31.66 | 38.14 | 45.29 | 0/100 |

This is another 198/800 samples at or above 100ms, not a pass of the latency
requirement. Faster point operations in the larger fixture do not establish
strictly increasing or decreasing latency as cardinality changes. Raw timings
are in `build/personal-memory-browse-v1164-regression-timings.log`.

The final application also passed all **91 existing instrumentation regressions**
in **1,009.02s**, finishing after midnight on 2026-09-11: zero failures or skips.
Together with the 16 new cases, this is **107 unique device cases** on 1.1.64.
The regression set covers incremental/point writes, row persistence, deletion
and retraction recovery, UI worker dispatch, scoped identities, model/image
timing, image and original-attachment pipelines, runtime timing and the latency
journal. These are functional regressions, not new ASR/QNN inference-performance
acceptance. No required instrumentation process remained running afterward.

Full lexical/hybrid `recall`, core-memory snapshots, bulk edits/deletion,
streaming backup/import, partitioning, encrypted native ANN and real 100M+
acceptance are not delivered here. No absolute latency or unlimited physical
capacity guarantee is claimed.

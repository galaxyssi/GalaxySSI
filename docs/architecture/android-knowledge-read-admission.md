# Knowledge read admission during writes

## Reproduced boundary

Android 1.1.106 creates a search snapshot through the writer's `access` monitor.
Final candidate validation also re-enters that monitor. Independent ranking does
not help a new query, or final validation, while a source transaction holds it.
Two SM-T575 regressions reproduced this: neither admission nor validation could
complete before a two-second latch deadline. The admission test's cleanup then
released the writer, so the late read observed its newly committed replacement.
This was a blocking failure, not exposure of uncommitted data.
Archived baseline logs escape non-ASCII synthetic text as Unicode escapes to
retain the complete failure while respecting the repository text policy.

## Committed read views

The database publishes reader readiness only after a complete outer operation
has initialized/migrated and committed successfully. Cold initialization retains
the existing serialized path. Failed initialization cannot publish readiness.
Warm queries acquire a segment lease and open a separate query-only WAL snapshot
without reserving the writer monitor or SQLite writer lock. Same-thread attempts
to open a search snapshot from inside a writer transaction are rejected.

Final validation opens a second committed read view and compares the old
authenticated header ciphertext with committed ciphertext for each candidate.
Deletes, body replacements and permission changes committed before that view is
pinned invalidate old candidates. Uncommitted changes are not visible. Validation
linearizes at its committed snapshot: subsequent commits belong to a later view,
not a promise that no writer can ever commit between validation and publication.
Page work remains bounded to 32 candidate entries, and each ID HMAC is calculated
once rather than twice per candidate.

Snapshot lifetime still pins encrypted payload segments. Retirement and thread
interruption invalidate a read; constructor failures close the connection and
release its lease. This is not a plaintext-result cache. Body authentication,
scope rules, migration failure behavior and original encryption are unchanged.

## Validation scope

`KnowledgeReadAdmissionDeviceTest` covers admission during a held update, final
validation during unrelated writes, failed cold migration, and nested-writer
rejection with rollback. Existing search-snapshot tests cover committed permission
changes, deletion, pinned segments, corruption, interruption and retirement.
The first broad run passed 85 cases and failed one test that waited for the old
writer monitor's `BLOCKED` thread state. Its lifecycle oracle now pauses explicitly
after candidates are calculated, invalidates the session, resumes publication,
and still requires an empty result. Removing final lifecycle validation would
allow those already-calculated candidates through; the stale-result assertion
has not been removed or weakened into a thread-state assertion.
Warm queries retain the previous opportunity to retry failed FTS backfill, but
enqueue a deduplicated maintenance hint instead of waiting for the writer.
The retry test removes a synthetic failure trigger through a separate connection
and verifies that an actual warm query resumes backfill without owner access.

`KnowledgeReadAdmissionScaleDeviceTest` requires an explicitly selected retained
synthetic 10,001-body database. During one real uncommitted update, it samples
100 new snapshots, each reading and validating eight bodies. The writer is held
by a test latch and rolls back. This establishes reader independence and reports
percentiles under a held writer; it is not sustained write-throughput, full-source
rewrite CPU contention, physical reboot, UI rendering or 100-million-row acceptance.

## Verified results, September 12, 2026

Android 1.1.107 (993) was installed in place on SM-T575 only. The final complete
86-case device suite passed in 391.068 seconds after replacing the obsolete
thread-state test. The unchanged production APK passed 3,817 JVM tests with five
existing skips and no failures/errors. Test-only rebuilding after the lifecycle
test adjustment did not change production code. All 74 AArch64 libraries passed
16 KiB alignment checks.

Under the held writer, admission plus one body read took 11.02 ms and final
validation took 7.93 ms in the small deterministic cases. On the retained
10,001-body database, 100 samples of opening a snapshot, reading eight recent
bodies and validating them measured P50/P95/P99 of 82.98/107.27/117.93 ms, with
zero samples above 200 ms. The database SHA-256 remained identical after the
write rolled back. This is a bounded recent-read probe, not semantic ranking.

The separate 1,201-body hot FTS probe measured P50/P95/P99 of 36/42/46 ms. Its P95
was 28 ms in the preceding crypto phase; these sequential device runs are not a
controlled attribution of the difference. This phase demonstrates independence
from a held writer, not an improvement in every no-writer microbenchmark.

Cold migration, exclusive segment reclamation, native-index initialization and
other non-search APIs may still wait for their existing locks. Source replacement
still holds a long transaction. The broader memory, Run Kernel, tracing and
ordinary Agent Loop DAG goals remain active.

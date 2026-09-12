# Source replacement preparation outside the writer

## Remaining serialization

The canonical source database is still a single SQLite WAL database. Native
graph and provenance shards are derived storage, not a replacement for canonical
source partitioning. The full hundred-million-record architecture is incomplete.

Previously `KnowledgeSourceReplacement.commit` held the canonical writer while
it read, authenticated and encrypted every old body into temporary staging.
The streaming implementation bounded heap usage, but this preparation could
still delay unrelated small writes for the duration of a large source read.

## Publication contract

`prepare` now pins a committed read-only view and captures the source revision.
It scans the indexed source in 64-key pages, authenticates every body, preserves
the existing policy-selection rule and writes previous bodies to encrypted
staging. An optional page observer reports processed counts; it receives no
source text. Exceptions or cancellation do not mutate the canonical source.

The resulting internal, single-caller prepared operation holds only staging,
source identity, revision and policy, not a list of all old bodies. Its owner
keeps the encrypted staging alive through commit and synchronous observation.

Publication takes a writer transaction and compares the source revision before
any canonical change. A source edit, permission change, deletion/recreation or
newly created formerly absent source causes `KnowledgeSourceReplacementChanged`.
The operation must be prepared again from the current source and fresh input;
it does not silently overwrite newer data or spin through unlimited retries.
This is an explicit optimistic-concurrency failure, not a generic success or an
automatic retry guarantee. Unrelated-source changes do not invalidate the token.
The existing document/web importer propagates the exception message as a failed
import; it returns success only after `replaceSource` completes. A conflict is
therefore observable to the caller rather than silently acknowledged.

Incoming IDs are still checked inside the writer, since another source may
claim one after preparation. All validation and canonical mutations remain
atomic. An attempted prepared operation cannot be published a second time.
Portable backup format, encryption, policy inheritance and synchronous
post-commit observation remain unchanged.

This removes preparation work from writer admission. It does not remove the
remaining large canonical write transaction, make a full replacement a 200 ms
operation, implement adaptive canonical shards or prove 100-million-row capacity.

## Verification scope

The new device cases cover unrelated durable writes during preparation, body and
permission conflicts, absent-source creation, deletion/recreation, cross-source
ID claims, cancellation and repeated publication. The small fixture records 50
individually committed `store.upsert` timings while its preparation view is open.

The scale case reuses the retained 10,001-body source. It checks each 64-key page,
performs 20 rolled-back writes while preparation is paused, and authenticates
every staged old body. It deliberately does not publish an empty replacement or
delete that source. These rolled-back writes establish writer independence but
are not durable-write latency measurements. Database hashes are checked outside
instrumentation before and after the complete run.

`tools/dev/test-knowledge-source-preparation.ps1` runs these cases with source,
backup, revision, directory, snapshot, hybrid and vector admission regressions.
Measured results must be added after execution, not inferred from compilation.

## Verified preparation results, September 12, 2026

Android 1.1.109 (995) was installed in place on SM-T575 only. The 92-case device
regression suite passed in 194.052 seconds. The full JVM run passed 3,817 cases
with five existing skips and no failures/errors. All 74 AArch64 libraries passed
16 KiB alignment checks, and repository checks passed.

The small source-preparation test completed 50 independent durable upserts while
the old-body snapshot remained open: P50/P95/P99 were 29.75/56.79/77.28 ms, with
no sample over 200 ms. This is a small two-source fixture, not write latency on
a 100-million-record store or sustained concurrent bulk replacement.

The retained 10,001-body preparation took 65.51 seconds, including 0.79 seconds
for 20 rolled-back writer probes. Every staged body was subsequently authenticated
and counted. The source database hash remained
`bee085bde215000750866600d54c0b291efd3c2fd7d55ebb5e5bbd3db6a8e8e1`.
This is evidence of preparation correctness and writer independence, not a
200 ms complete source replacement or a measured before/after speedup.

The retained canonical recent-read probe measured P95 70.22 ms over 100 samples,
with no result above 200 ms. The separate small native-ranking probe measured
P95 34.20 ms over 100 samples, again with no result above 200 ms. These sequential
runs do not isolate a general latency improvement from the preceding phase.

The retained full-rewrite test now accepts an optional bounded ASCII variant,
leaving its historical default unchanged. `-Phase rewrite -Variant source-prepare-v1`
changes all 10,001 bodies on the same fixture, performs synchronous observation,
closes the store, clears cached row keys, reopens and verifies every body and ID.
Its result is recorded separately; the preparation-only pass does not stand in
for full-rewrite acceptance.

The full retained rewrite passed as a separate device case in 402.369 seconds:
replacement including synchronous observation took 333.044 seconds, and reopening
with cleared row-key caches plus full verification took 69.238 seconds. All
10,001 IDs and expected new bodies were verified without duplicates or losses.
Together with the regression suite, 93 device cases passed with zero failures
or skips. The production APK did not change between these runs.

The intentional full rewrite changed the fixture hash to
`0e81fc45d13278b978ee261de805fe46b980d9f3f38de96639c25073ce5e5da0`.
The fixture was retained, not reset or deleted. This run uses a different content
variant from historical measurements, so its elapsed time is not a controlled
attribution of a speedup. Large replacement remains slow and canonical partition
publication still needs redesign; this phase does not complete the broader goal.

Bounded per-class output, rewrite output, timings and APK hashes are retained in
`evidence/knowledge-source-preparation-20260912/`. An initial GitHub fetch failed
transiently; the subsequent fetch succeeded before publication.

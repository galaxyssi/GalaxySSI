# Committed vector read admission

## Problem

The canonical search snapshot no longer waits for the live writer, but the
native graph readiness check still reads the vector feed through `storage.access`.
That path acquires the writer monitor and starts a write transaction. Consequently
an already-built native graph can block on an unrelated or uncommitted source
replacement before the encoder or ranking work begins.

The feed page, vector catalog and authenticated vector-page validation have the
same admission problem. Moving only the final source-body lookup does not remove
these earlier waits.

## Read contract

Standalone vector metadata and page reads use a short-lived, query-only WAL view.
The view is pinned before its first query, uses a bounded SQLite cache, retains
the payload lease and checks owner retirement and thread interruption. It never
exposes uncommitted state. Calls from inside a writer transaction are rejected;
transactional code uses its explicit SQL connection instead.

Feed state and rows are read from the same view, preserving the feed epoch,
previous-sequence chain and high-watermark checks. Vector pages copy only their
bounded encrypted frames before releasing the first view. After authentication,
a new committed view validates both the source revision and document checkpoint.
This still rejects replacement, deletion or model unregistration that committed
while those frames were being decrypted.

Native readiness continues to compare the committed feed with the authenticated
native checkpoint. Hybrid publication still checks the corpus stamp, item
revisions and lifecycle epoch. Source changes committed after a validation view
is pinned belong to a later view; this is not an atomic read-and-network-send
guarantee.

Registration, backfill and vector appends remain transactional. Cold database
migration, native graph I/O, model inference and exclusive payload reclamation
can still take time. This change removes writer admission from reads, not every
possible wait or the need for maintenance coordination.

## Verification

`KnowledgeVectorReadAdmissionDeviceTest` uses an isolated encrypted source and a
real NDK index with a deterministic two-dimensional test encoder. It checks feed,
catalog and vector pages, graph reopening, and 100 ranked queries with no lexical
overlap while a real uncommitted source replacement holds the writer. After the
writer commits, old graph readiness and completed vector pages must be rejected.
The test encoder is not evidence of installed production-model latency.

On the unchanged installed Android 1.1.107, all three new cases failed with a
10-second `TimeoutException` while the writer remained held. The writer was
released in cleanup; this baseline does not indicate a permanently deadlocked
database. The initial test compilation also caught two unsupported test fixture
arguments, which were corrected before running either baseline or fixed code.

`tools/dev/test-knowledge-vector-read-admission.ps1` runs the new cases together
with feed replay, enrollment, authenticated vector pages, native checkpoint and
migration, hybrid invalidation, canonical snapshots and the retained 10,001-body
read fixture. Device results and measured timings must be recorded separately
after running the completed build.

The 100-million-record goal, sustained full-source write contention and a
universal 200 ms retrieval/write guarantee remain unverified.

## Verified results, September 12, 2026

Android 1.1.108 (994) was installed in place on SM-T575 only. All 80 device
regressions passed in 237.893 seconds. The complete JVM run passed 3,817 cases
with five existing skips and no failures or errors. All 74 AArch64 libraries
passed 16 KiB alignment checks, and the repository checks passed.

The 100 actual ranked native queries under a held source replacement measured
P50/P95/P99 of 27.25/39.84/46.49 ms, with no samples above 200 ms. Reopening the
existing graph, checking readiness, querying and rechecking readiness took
31.64 ms. This small test uses one encrypted source body and a deterministic
two-dimensional encoder; it proves the removal of writer admission, not large
ANN recall, production embedding-model latency or 100-million-record capacity.

The unchanged retained 10,001-body fixture also passed 100 samples of opening a
view, reading eight recent bodies and validating them during a held writer:
P50/P95/P99 were 86.28/102.08/110.35 ms, with zero samples above 200 ms. Its
database SHA-256 remained unchanged after the test's write rolled back. This
second probe is a canonical recent read, not a ranked vector query.

The existing real 512-dimensional replay regression passed as well: while
replaying 204 chunks, 32 foreground lexical fallbacks measured P95 68 ms and
maximum 79 ms. It measures fallback responsiveness during maintenance, not
concurrent native ranking on that corpus.

Bounded per-class output and derived summaries are retained in
`evidence/knowledge-vector-read-admission-20260912/`. No schema, model artifact,
ASR/QNN behavior, Desktop code or user data was changed in this phase.

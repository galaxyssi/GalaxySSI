# Foreground native memory retrieval admission

Android 1.1.86 follows the user-reserved 1.1.84 version and the rejected 1.1.85
device candidate, even when the reserved version
has not yet merged into main. Recheck upstream versions before publishing or
installing; do not infer the latest delivered version from main alone.

## Problem

In 1.1.75, each foreground semantic query acquired the same blocking monitor
as background replay and synchronously applied up to four replay pages before
falling back to lexical retrieval. The real SM-T575 scale probe measured native
64-vector replay pages taking seconds. A ready-graph search benchmark did not
cover this queueing delay.

## Changes

- Query admission uses a nonblocking index-owner lock. If replay or another
  query owns it, the caller immediately uses existing authoritative FTS/lexical
  retrieval instead of waiting for native work or an encoder invocation.
- A foreground readiness check reads feed/checkpoint metadata and can reopen
  a previously committed authenticated graph. It cannot register a model,
  backfill source events, seed a graph or append vectors.
- Missing or lagging derived indexes request coalesced background replay.
  Existing durable WorkManager indexing remains active, including after restart.
- Native query vectors are still cleared, lifecycle invalidation stays
  nonblocking, and current source revision/access/deletion checks still run
  before dense results can be published.
- A fallback releases the native owner before reading the lexical store.

The gate does not make all retrieval constant-time. Source-database access,
query-model loading/inference, cold index open and native search still have
their own costs. A query during replay can have lexical-only results; complete
concurrent ANN snapshots and large-corpus end-to-end recall remain separate
requirements. This change does not claim 100M acceptance.

## Focused verification

`KnowledgeRetrievalAdmissionDeviceTest` checks:

1. Readiness leaves an unbuilt feed/index unchanged, reopens a committed graph,
   refuses stale source revisions, and does not silently re-register a model.
2. A query with an unbuilt graph schedules replay without invoking its query
   encoder; later retrieval uses the completed native graph.
3. Thirty-two lexical queries remain responsive while the actual replay owner
   is held at its cancellation boundary. Releasing it allows real replay and
   semantic retrieval to complete.
4. A second query does not queue behind a slow encoder; deletion during the
   first query cannot return an obsolete dense match.
5. A real 512D, multi-page encrypted replay runs while foreground lexical
   queries are measured. All native work is then completed and queried again.

The latch case makes ownership contention reproducible; it is not presented as
real disk throughput. The separate full-width replay case has no injected native
delay. Both retain raw foreground latency samples and target a maximum below
200ms on SM-T575. Lifecycle, hybrid permissions, corruption, TTL and real BGE
regressions remain part of validation. Fixtures use separate databases and do
not change model downloads, pairing or production messages.

## Validation status

Implementation and test compilation are in progress. Do not treat the test
definitions above as passing results. Record verified baseline/candidate results
and the exact installed version before publishing this change.

# Android #3035: Source Preparation Outside the Writer

Reference: Android PR #3035, pinned merge
`c45dd948ac4d6833dc7e8cf371e7f1c6d1d194da`.

## Full Main Scope

This branch combines the existing source/staging/outbox work from iOS #4616
(`4c8a2f456b57fa5d4457fc8d80f3a0d450e19ee5`) with committed lexical/vector read
work from #4621 (`97853c6a566ca02dc9a1a794d570ca7e4787588e`, including #4619).
The base stays `main`; until those merge, its full diff includes their production
paths, tests and docs. This is reuse through Git ancestry, not duplicated code.
The separate #4617 index memo and primary-storage PR chain are not included.

## New Increment

- Incoming records are consumed once into encrypted scratch. Old source records
  are authenticated and staged through a committed read connection, in 64-key
  pages, without the canonical writer lock/transaction. The oldest access policy
  and its keyed tie break are retained as metadata, not a retained body list.
- `AgentKnowledgePreparedSourceReplacement` is owner-bound and single-use.
  Success transfers scratch ownership to the returned mutation; conflict/error
  consumes it and closes scratch. Close during apply requests rollback. Its
  ownership lock serializes close against the actual canonical COMMIT.
- Per-source integer generations fence preparation. Insert/delete/body or index
  metadata update increments the source generation in that same transaction;
  moving a row also increments its new source. Tombstones survive deletion, so
  identical recreation and absent-to-created-to-absent cannot bypass validation.
  No-op replacement causes no generation change.
- Cold setup seeds existing source hashes once, without rewriting body envelopes.
  Integer overflow fails a CHECK constraint and rolls back, never wraps. Missing
  generation state for a nonempty source fails closed. No global browse revision
  is substituted for this source-specific fence.
- COMMIT admission starts a writer transaction, rechecks that source generation,
  then rechecks every incoming ID. Previously authenticated membership plus the
  unchanged generation permits existing IDs; any canonical row outside that
  prepared membership is rejected. A new ID claimed by another source cannot be
  overwritten. This avoids re-decrypting canonical old bodies for ownership.
- Existing atomic row/FTS/vector/header/observation outbox changes remain inside
  the canonical apply transaction. New vector evidence created during preparation
  is invalidated by that apply, rather than causing a false source conflict.
- Checked Store imports now propagate conflict. Actual attachment import, native
  web import and the web-import UI use those APIs. Web actions return
  `knowledge_source_changed`/unverified failure; attachment delivery records a
  failed import trace; the UI has localized conflict feedback. None silently
  retries a stale preparation or acknowledges it as imported.

## Remaining Boundaries

Canonical apply, encrypted observation folding/outbox insertion and legacy UI
array publication are still synchronous and can hold a long writer transaction.
This is not a complete sharded corpus, UI responsiveness, production model or
universal latency/capacity claim. Preparation snapshots do not add physical
external-payload file leases; inherited reclamation races fail authentication.

Generation tombstones retain one opaque entry per historical source; there is
no tombstone compaction or raw-database rollback/anti-tamper guarantee. Supported
restore must go through canonical writers/lifecycle invalidation. Legacy bulk
writers and physical payload relocation can conservatively conflict even when
visible content is unchanged. Direct DB writers must reconcile their own UI
caches: this is not a multiwriter full-Store cache reconciliation protocol.

Legacy nonthrowing import adapters remain for compatibility, but the actual
production replacement import routes are checked. Batch attachment imports are
atomic per source, not across all attachments: earlier successfully committed
sources can remain when a later source fails; the batch is not acknowledged as
fully imported. Sending the chat attachment may continue after an explicit failed
persistent-import trace. The inherited source observation outbox still lacks an
automatic global-runtime consumer, and its other documented limits remain.

## Verification

Seventeen new synthetic XCTest methods are authored for writer-free preparation,
concurrent independent writes, source/ACL conflicts, deletion/recreation/absence
ABA, identity claims, one-shot ownership/lifetime, close/failure/lifecycle rollback,
no-op, metadata-only migration, overflow, intervening vector evidence and explicit
web failure/no retry. The inherited 49 methods and these 17 have not been compiled
or executed. Source guards/project checks are static, not native acceptance. No
native build/typecheck, XCTest/Rust execution, CI monitoring, IPA, test reports or
private/device evidence is included.

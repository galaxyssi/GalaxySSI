# Android #3034: Committed Vector Reads

Reference: Android PR #3034, pinned merge
`9a75150e1d96263016fd3bea0b9d093769d7ea4b`.

## Shared Prerequisite

This branch builds on iOS PR #4619, commit
`63cc0d2a6613c4063b5af1c8e6e9a6e7e60d3ee7`, for the committed read-view and retry
helper. Its GitHub base remains `main`. Until #4619 merges, the full main diff
includes that lexical-read prerequisite, its tests and documentation; the new
increment is vector read admission. No duplicate implementation or wait for
merging is required. Neither PR claims native acceptance from static checks.

## Implemented Increment

- Warm feed stamps/pages, latest publication pages, vector catalog/keyset pages,
  standalone checkpoint reads, registered count snapshots and final lexical/native
  hit resolution now use explicitly passed committed read connections.
- Replay validates feed epoch/watermark, latest source publication, authenticated
  source revision, vector provenance, contiguous ordinals and UTF-16 ranges in
  one pinned view. After decrypting, it rechecks the committed feed/source stamp
  before releasing a page. Native/lexical hit batches retain final stamp and
  original lifecycle-generation checks. SQL failure does not return partial data.
- Catalog/checkpoint ciphertext is checked against its stored keyed identity and
  requested model. Replay and resolution joins also bind vector model, source
  identity and source revision to the publication/ordinal records.
- First-use model/feed/count enrollment remains an explicit cold writer path
  after a read miss. Registered warm paths do not execute registration writes.
  Cancellation/generation are rechecked after waiting for that cold writer.
- Native root selection reads its bounded durable cursor/publication page and
  authenticated first usable vector without entering the source writer monitor.
  Context mismatch resets the read cursor to the beginning. A valid seed needs
  no cursor write. Optional progress uses try-lock and zero SQLite busy timeout;
  if another writer owns the catalog it leaves the cursor untouched for retry.
  Successful progress remains durable across reopen. Busy timeout is restored.
- Native replay propagates an explicit owner-bound background lease through
  every nested read. A lease from another database, ended lease, protection loss
  or foreground reentry cannot authorize reads. It never reenables foreground
  queries. Notification-center injection permits isolated lifecycle fixtures;
  production still defaults to the system notification center.
- Writer-side completeness/removal checks retain the canonical transaction
  connection so they see uncommitted chunks. Authentication/cancellation failure
  rolls back a vector write rather than committing an unpublished partial result.

## Boundaries

The second committed pin is a validation point, not a lock across later result
consumption. Cold registration, migration, inference, graph I/O, producer queues
and count/index maintenance may still wait or be large. Root cursor progress can
lag under writer contention and repeat a bounded page; there is no measured
progress/latency guarantee for a large run of obsolete publications.

Legacy checkpoint/offset catalog adapters still materialize their requested
results; native replay uses bounded pages. Full source-body authentication is
retained instead of Android metadata-only source validation. Physical external
payload leasing remains in separate primary-storage work; inherited reclamation
races fail authentication rather than release unverified evidence. Android
retained-scale, ordinary-device or 100-million-record claims are not transferred.

## Verification

Fourteen new synthetic XCTest methods are authored, including two default-factory
linked-Rust call paths (foreground bootstrap/replay/search under a held writer and
background replay with a read lease). The encoder is a supplied two-dimensional
vector, not a production embedding model. All fourteen methods are uncompiled
and unexecuted. The inherited eleven #3033 methods are also not native acceptance.
Existing source guards are updated to assert committed-connection/lifecycle and
read-cursor validation rather than obsolete writer-transaction syntax. No tests
are removed/disabled. No native build, XCTest/Rust execution, CI monitoring, IPA,
test reports or private/device evidence is included.

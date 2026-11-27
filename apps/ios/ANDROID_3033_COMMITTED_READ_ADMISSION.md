# Android #3033: Committed Read Admission

Reference: Android PR #3033, pinned merge
`c3dfac0d11032188f94455474e7bd56f466c4979`.

## Implemented

- `AgentKnowledgeCommittedReadView` opens a separate query-only connection,
  begins a read transaction and reads the browse revision to pin a committed
  SQLite view. It retains the existing 2 MiB page cache/no-mmap settings. It does
  not use an immutable URI, create a database or enter the canonical writer lock.
- iOS initialization/migration is eager in the database initializer, unlike
  Android's lazy access initializer. Warm admission therefore needs no new lazy
  migration lock. Failed/partial initialization fails the required revision/FTS
  reads rather than admitting uninitialized results.
- `searchCandidates` obtains bounded FTS candidates from one pinned view, then
  authenticates/compares the complete current record in a second committed view.
  Deleted, changed and ACL-modified candidates are suppressed. SQL errors and
  authentication failures throw instead of returning partial results.
- Both views check Task cancellation and the native-files lifecycle generation.
  Before returning, the original view is checked again: a newly opened validation
  view must not legitimize candidates from an invalidated earlier generation.
- A nonblocking recursive try-lock rejects admission on this thread inside its
  own uncommitted writer transaction. A different thread's long writer does not
  prevent opening the committed views. Cipher/Keychain locks remain separate.
- Queries request a deduplicated utility-queue repair hint after known failed
  cold FTS backfill or FTS prepare/step failure. Repairs acquire the writer only
  off the query path. A new failure during repair cannot be cleared by that older
  repair's success. Inactive lifecycle state skips repair and retains eligibility.
- The existing cold full-snapshot index repair is reused, not a new index engine.
  `all()` now checks every SQLite step/cancellation so repair cannot rewrite the
  corpus from a partially successful scan. A corrupt body prevents replacement.

## Boundaries

Validation observes state at its second pin point; later commits belong to later
reads. It is not a lock held across result consumption. Full body authentication
is intentionally retained; Android's metadata-only validation and iOS's open
primary-storage changes are separate work.

The original #3033 increment changes lexical candidate admission. The dependent
#3034 increment now updates vector feed/catalog/replay and hybrid final read
validation; see `ANDROID_3034_COMMITTED_VECTOR_READS.md` for that scope and its
remaining cold/maintenance boundaries. Background repair can still be
large and uses the existing legacy full-snapshot path; it is not an incremental
or guaranteed successful recovery for missing/corrupt schema.

SQLite busy timeouts, cold schema locks, file I/O, AEAD locks and Keychain calls
can still wait. Existing external payload reclamation has no new snapshot file
lease in this independent branch: a physical reclamation race fails record
authentication rather than releasing stale/unauthenticated text. It is not an
availability, physical-file-lease or power-loss acceptance claim.

No Android device timing or retained 10,001-body measurement is transferred to
iOS. The branch is independent from the open #3032 memo and #3031 source work;
it neither includes their ancestry nor claims their remaining parity complete.

## Verification

Eleven synthetic XCTest methods are authored for committed/query-only pinning,
held-writer reads, replacement/deletion/ACL invalidation, lifecycle generations,
own-transaction rejection, ciphertext authentication, close/cancellation, retry
deduplication/generations and the actual failed-backfill/recovery path. Native
compilation, typecheck and XCTest execution have not been performed. Source
guards, JS syntax and project-structure checks are static only. No IPA, CI
monitoring, private/device evidence or test reports are included.

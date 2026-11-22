# Android #4308: capped article retries and failed-queue cleanup

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4308

Android merge: `e68073acfa1efbdc3e2bc44af1aa941624cfa046`.

This is an independent main-based port. Android #4307 power/adaptive scheduling
is handled by a separate iOS PR; its implementation is not included here.

## Behavior

- A new article may fail once and retry three times. Failure four stops it.
  Extraction/validation errors use 30-minute exponential backoff; translation
  timeout/model-pending and transport errors start at one minute. Both clamp
  exponents to three, with a four-hour ceiling, matching Android's policy.
- Genuine model-unavailable errors consume attempts; cancellation, capacity/ASR
  deferral and news-budget yields release claims without spending retries.
- Exhausted unpublished articles lose their queue entries, archive metadata,
  extraction and translation checkpoint files. SQLite retains only their hashed
  article identifiers so feed or live rediscovery cannot recreate the backlog.
- Published articles keep their archive rows and completed bodies. A persistent
  publication marker survives cache eviction; exhausted repairs stop rather than
  resetting when a model becomes available or a completed cache is reconciled.
- On first queue preparation after upgrade, old failed unpublished entries are
  discarded. Old successful and unattempted entries remain. A ledger revision
  distinguishes this one-time migration from new retries after the upgrade.

## Storage and interruption safety

The queue first writes a set of pending cleanup hashes. The shared body actor
checks publication/completion and, without suspending, invokes the SQLite archive
transaction that inserts deduplication keys and deletes article rows. Only then
are incomplete body files removed and the queue intent acknowledged. Interrupted
cleanup remains pending and is replayed idempotently on the next preparation.

A body completed between queuing and cleanup is rescued, as is a known published
article whose cache was evicted. Completed-body checks and archive commit happen
under the same body actor ownership. SQLite's row revision and tombstone checks
reject stale writers; the regular feed/live save path filters discarded new IDs.
Deleted headlines, URLs and partial article text are not retained in the cleanup
queue after acknowledgement, only indexed deduplication hashes in SQLite.

Archive schema 1 upgrades transactionally to schema 2 without replacing its rows.
The queue and body stores can be injected per archive; non-production fixtures get
separate paths rather than modifying the production shared queue or body cache.
Legacy publication protection uses the surviving ready flag, publication marker
or completed body. Older iOS versions could erase both the ready flag and cached
body during cache reconciliation; that lost historical publication evidence cannot
be reconstructed by this migration. The new publication marker prevents that loss
for subsequent repairs; this change does not claim to recover already lost bodies.
First reader load, refresh, live collection, highlights and backlog processing
prepare the retry policy. Lightweight unread-only queries do not run destructive
cleanup; cleanup is completed when the news archive/queue is next prepared.

This change does not delete Agent discussions, user contact chats or unrelated
health data, nor claim secure erasure of SQLite free pages or OS caches. It does
not add a new background service, generate an IPA or change Android/Desktop code.

## Verification scope

Added regression XCTest source for the four-failure boundary, error backoff,
budget releases, success reset, publication/cache-eviction protection, one-time
legacy cleanup, restart/idempotency, interrupted cleanup after DB commit, stale
rediscovery, just-completed body rescue, failed-commit retention, path validation
and archive schema migration. Updated earlier retry timing expectations.

Tests are not executed in this task. Targeted project structure, whitespace and
incremental Swift grammar checks run on Windows, not Xcode/device verification.

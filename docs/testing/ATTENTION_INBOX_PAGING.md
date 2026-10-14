# Proactive discovery history and paging

## Behavior

- The discoveries inbox and unread count no longer stop at 100 items.
- Proactive messages are not evicted when the count exceeds 300.
- Collected articles and their source evidence are not evicted at 500.
- The feed uses explicit 20-item pages, with previous/next controls and matching
  item/page totals. All, important, unread and saved filters run before paging.
- Page number and RecyclerView position survive Activity recreation. Source
  metadata is loaded on demand rather than for every retained article.

These changes do not alter collection intervals, provider limits, notification
policy, model permissions or review concurrency. Page size, database read batch
size and the in-memory evidence cache are not retention limits. Storage still
uses the device's available disk space; this is not a claim of infinite capacity.

## Storage

Messages, article records and evidence now use individual rows in the existing
encrypted database. Message IDs and source-event indexes prevent duplicate
publication. Ingestion, review updates and conversation binding update only the
affected rows. Full snapshot replacement retains all supplied messages and
updates only changed payloads.

Legacy JSON arrays/objects migrate transactionally. The legacy value is deleted
only when its row migration commits. Failed migration preserves the original
value. Data that an older version already evicted cannot be recovered by this
migration.

## Regression coverage

- Projection and complete pagination of 1,205 messages, including the last page.
- Filtering before paging, empty results, out-of-range pages and old favorites.
- Migration, append, deduplication, read state, binding, revision, process-store
  recreation and snapshot restore with 1,205 messages.
- 605 collected articles plus legacy article/evidence rows, replay deduplication
  and favorite/source preservation beyond the former 500-item boundary.
- Transaction rollback for malformed legacy records.
- Real Activity navigation between pages 51 and 50 of a synthetic 1,005-item
  feed, with a bounded number of attached views.

Tests use isolated synthetic records and do not submit model research tasks.

## Verified on 2026-10-14

- Android v1.5.10 (1293) built and installed over v1.5.9 on Samsung S20U.
- 90 focused JVM tests passed; 24 instrumented tests passed in 175.928 seconds.
- The instrumented run excluded opt-in public-network checks and the heads-up
  notification demo; no model task was submitted by the test suite.
- The real inbox showed 200 retained findings across 10 pages and 192 unread
  findings on the home entry. Pages 1 and 2 were inspected on the device.
- Kotlin source-size policy, Chinese localization guard and diff whitespace
  checks passed.

# Proactive discovery history and paging

## Behavior

- The discoveries inbox and unread count no longer stop at 100 items.
- Proactive messages are not evicted when the count exceeds 300.
- Collected articles and their source evidence are not evicted at 500.
- The reader loads 20-item batches into a continuous chronological timeline.
  There are no visible page numbers or previous/next controls. The three tabs
  are all, unread and saved; important findings retain their underlying status.
- Scrolling near the end preloads older findings. Scrolling toward the top or
  pulling at the top inserts adjacent newer batches without skipping a burst.
  The visible key and pixel offset anchor the insertion.
- Incoming news and revised article bodies are buffered while reading. They
  do not reorder existing rows, replace expanded bodies or collapse them.
- Tapping a finding expands it inline. Original-source navigation and Ask Agent
  are separate explicit actions. Source summaries remain labelled unverified;
  viewing a finding does not mark its evidence verified.
- Foreground, focused, idle visibility of at least 85% of the title/summary area
  for two continuous seconds marks the finding read. Scrolling, focus loss and
  backgrounding reset the dwell timer. Read rows remain in the current unread
  snapshot; selecting the unread tab again reapplies the filter.
- Outline/filled bookmarks distinguish saved state, with an undo action.
  Read and bookmark changes use RecyclerView payloads, not full row rebuilding.
- Filter, loaded keys, expanded keys, anchor and offset are stored in the
  encrypted database off the UI thread, including when leaving the Activity.
  Restoration preserves read rows in an unread snapshot. Source metadata loads
  only for attached rows; history is not inflated into one large view hierarchy.

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
- Timeline tests cover all 1,205 records, new bursts larger than a batch,
  unread/saved snapshots, restoration and stale reloads after read commits.
- Device reader tests cover inline expansion without Agent navigation, unchanged
  body identity and pixel anchor on arrival, older preloading, disk restoration,
  automatic read persistence, bookmark state and undo, using isolated fixtures.

Tests use isolated synthetic records and do not submit model research tasks.

## Verified on 2026-10-14

The following results describe the previous explicit-page implementation. The
continuous-reader results are recorded separately after its validation.

- Android v1.5.10 (1293) built and installed over v1.5.9 on Samsung S20U.
- 90 focused JVM tests passed; 24 instrumented tests passed in 175.928 seconds.
- The instrumented run excluded opt-in public-network checks and the heads-up
  notification demo; no model task was submitted by the test suite.
- The real inbox showed 200 retained findings across 10 pages and 192 unread
  findings on the home entry. Pages 1 and 2 were inspected on the device.
- Kotlin source-size policy, Chinese localization guard and diff whitespace
  checks passed.

## Continuous reader verification on 2026-10-14

- Android v1.5.11 (1294) built and installed over the existing app on Samsung
  S20U (SM-G9880), without clearing user data.
- 71 focused JVM tests passed. Both new reader interaction tests passed in
  14.781 seconds; the complete targeted instrumented suite then passed all
  25 tests in 211.315 seconds.
- The device suite excluded the two opt-in public-network checks and the
  heads-up notification demo. Tests used isolated synthetic records and did
  not dispatch model research tasks.
- Device assertions cover inline expansion, body identity and pixel anchor
  stability during incoming/review updates, older preloading after restoring
  the bottom position, durable anchors after prepending, long-article collapse,
  automatic read persistence, unchanged unread membership, and bookmark undo.
- The actual inbox was also visually inspected: no page controls, inline
  article text, readable dimmed titles, outline bookmarks, and a buffered new
  content notice. The device tests also reconstructed the reader from its
  persisted position and expansion state.
- Kotlin source-size policy, Chinese localization guard and diff whitespace
  checks passed. Collection schedules and model routing were not changed.

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
- After scrolling settles, expanded articles fully outside the viewport
  collapse automatically. Partially visible articles, including long bodies
  whose headlines have scrolled away, remain expanded. The current key and
  pixel offset are preserved and the collapsed state is persisted. Initial
  restoration, incoming updates and backgrounding do not trigger this action.
- Foreground, focused, idle visibility of at least 85% of the title/summary area
  for two continuous seconds marks the finding read. Scrolling, focus loss and
  backgrounding reset the dwell timer. Read rows remain in the current unread
  snapshot; selecting the unread tab again reapplies the filter.
- Outline/filled bookmarks distinguish saved state, with an undo action.
  Read and bookmark changes use RecyclerView payloads, not full row rebuilding.
- Unread headlines use soft purple and read headlines use opaque primary text
  (black in light mode, light text in dark mode). Read commits do not change
  the title color or read label of an attached article, including expansion
  and bookmark updates. A newly attached/reopened row adopts its latest state.
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

## Headline presentation verification on 2026-10-14

- Android v1.5.12 (1295) installed on S20U without clearing data.
- 19 timeline/inbox JVM tests and three targeted instrumented reader tests
  passed (device run: 24.115 seconds).
- Auto-read commits, expansion, bookmarking and undo retain the currently
  visible purple headline. Reattachment and reconstruction adopt the opaque
  read color. Read persistence and unread snapshot membership are unchanged.
- Unread/read colors are distinct and meet a 4.5:1 contrast ratio against the
  reader background in both light and dark resource configurations.

## Offscreen collapse verification (v1.5.13)

- Android v1.5.13 (1296) built and installed on Samsung S20U (SM-G9880)
  without clearing app data.
- All 21 focused timeline/inbox JVM tests and four targeted instrumented
  reader tests passed (device run: 39.408 seconds).
- Device assertions cover keeping partially visible long articles expanded,
  collapsing fully offscreen articles after scrolling in both directions,
  preserving the visible item and exact pixel offset, and persisting the
  collapsed state.
- Regression checks cover stable incoming updates, automatic read commits,
  bookmark undo and legible unread/read colors in light and dark themes.
- Tests used isolated synthetic records without dispatching model tasks.
  Collection schedules, model routing and existing headline colors are unchanged.

## Reading typography verification (v1.5.14)

- News headlines use regular weight at 17.6sp (previously bold 16sp).
- Expanded body text uses 18sp (previously 15sp); the content-summary label
  uses 14.4sp (previously 12sp). Preview, metadata and action text are unchanged.
- Android v1.5.14 (1297) built and installed over the existing S20U app.
- All five targeted reader device tests passed in 34.491 seconds, including
  regular headline weight across expand/collapse, exact SP sizes at standard
  and enlarged font scales, offscreen collapse, stable anchors, read state,
  bookmark undo and title contrast. Real list and expanded screenshots were
  also inspected for wrapping and spacing.

## Bilingual headlines (v1.5.15)

- In the Chinese reader, fully English feed headlines receive a Chinese primary
  title and a smaller English original. Headlines already containing Chinese
  remain unchanged. Primary titles are regular 19.36sp, 10% above v1.5.14;
  originals are 13sp and expanded body text remains 18sp.
- Title-only translation is independent of full-source review. It sends public
  feed headlines without conversation history to an already permitted local,
  cloud or paired model. Direct inference supplies no tools; paired requests
  explicitly ask for translation only, without browsing or tool use. No provider,
  model, credential or permission is enabled implicitly. Existing paired reviews
  can also return a separate faithful title translation, matched to the exact
  original headline and accepted source.
- The paired route persists one active batch before dispatch and correlates
  replies by contact, source ID, conversation and turn. Background delivery
  caches translations and acknowledges the reply without creating a chat.
  A durable lease prevents duplicate dispatch after reopening the app; expired
  batches become retryable. This lease is not a limit on article retention.
- Small batches are scheduling units, not a lifetime or retention limit. The
  existing token, cost and concurrency admission remains in effect; the retired
  background dispatch-count ceiling is not reintroduced.
- Exact-original/version/target-language cache keys and durable retry leases
  prevent repeated successful translations and rapid failure loops. Invalid,
  duplicate or unknown results are rejected. Numeric/version changes and markup
  are rejected; this is structural validation, not proof of semantic accuracy.
  Failed/unavailable translation leaves the English source readable.
- Translation payloads update stored row state without changing an attached
  article's title, height, read color or expansion. Reattachment or reopening
  adopts the translation. English originals remain available in both collapsed
  and expanded articles, with full text on expansion.

### Verification

- Android v1.5.15 (1298) was built and installed over the existing S20U app.
- 97 JVM tests passed, including title parsing, identity/lease persistence,
  review integration, timeline preservation and connector response scopes.
- Nine synthetic device tests passed: typography, bilingual rows, translation
  arrival stability, durable cache/retries, paired response ownership/recovery,
  scrolling anchors, read state/bookmarks and light/dark title contrast.
- An explicitly enabled live device test passed in 42.434 seconds. The S20U's
  existing paired-only permission was preserved (cloud background calls remained
  disabled); eight real public headlines were translated through the Desktop
  and saved to the phone cache. No chat conversation was created by this path.
- The real Chinese article layout was inspected on S20U. Final real bilingual
  screenshot inspection remains pending because the device returned to another
  app; it was not forced back. Bilingual layout assertions passed with fixtures.
- Debug and instrumentation APK builds, Kotlin source-size policy, localization
  guard and `git diff --check` passed. Translation validation checks structure
  and number preservation, not semantic correctness of every headline.

## First-open loading (v1.5.16)

The S20U read-only baseline contained 476 delivered messages. The former serial
load took 12,354 ms and 19,759 ms in two samples: message reads 4,716/9,865 ms,
title-cache reads 2,376/3,020 ms, and research-task reads 4,230/5,650 ms. These
are local-storage timings, not model-response or network timings.

- A transactional SQLite ordering index selects the first reading batch or a
  bounded window around the saved anchor. It stores identities, timestamps,
  read state and digest membership only; titles/bodies remain encrypted.
- Existing records receive a one-time, crash-atomic index migration. Inserts,
  revisions, read commits, bulk replacement and deletion update the index in
  the same transaction as message rows. Modification order is not news order.
- The first batch and its cached translations render before full history loads.
  The batch size is not a retention cap. All older/newer records remain readable;
  digest groups are loaded completely, not split into misleading partial items.
- Loading full history uses a separate executor from reading actions. It extends
  the timeline without replacing visible bodies, moving the anchor or collapsing
  expanded content. The unread total is shown only after the full count is known.
- Research-task and feed-poll status are fetched only for the settings page.
  Collection/translation scheduling no longer precedes the initial inbox read.
- Opt-in `ProactiveAttentionLoadPerformanceTest` logs timing/count metadata only.
  It does not request new model tasks or export article/conversation content.

### Device measurements

- The first installed implementation rendered 20 initial rows in 1,774 ms on
  the S20U. Three read-only first-batch samples took 303, 472 and 1,117 ms.
  These are initial-content timings, not a claim that all history finished in
  that time. The persistent index had already been migrated during app startup.
- 99 focused JVM tests and 12 synthetic device tests passed (device suite:
  220.919 seconds), including 1,205-message retention, restored paging,
  index updates/deletion, complete digest groups, typography, translations,
  read/bookmark state and pixel-anchor preservation.
- A first-upgrade index build is one-time work; normal process recreation reuses
  the durable index. These small samples do not establish a stable p95 or a
  sub-second guarantee under all storage/background-load conditions.
- Final Android v1.5.16 (1299) was installed over S20U data. A fresh instrumentation
  process rendered its first 20 rows in 657 ms; first-batch reads measured
  406/239/928 ms. Both performance probes and both index regression tests passed
  in 28.712 seconds. The final index test also verifies that clearing an isolated
  test database immediately removes its ordering metadata via the delete trigger.
- Final APK/test APK builds, all 99 JVM checks, localization guard, source-size
  policy and whitespace validation passed. No real model experiment was started.

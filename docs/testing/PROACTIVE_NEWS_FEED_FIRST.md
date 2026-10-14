# Source-First Proactive News

## Contract

Public-news discovery no longer waits for model review. A separate network-constrained
WorkManager worker reads publisher/query RSS feeds for subscribed topics, checks their format,
publication date (past seven days), HTTPS source URL and canonical identity, and
persists a source-attributed inbox item. It uses no model or Desktop connection.

The initial item explicitly says that it is a source summary, not independently
verified. A title without a summary is identified as a headline whose full article
has not been read. Search-provider relevance and dates are not proof of a claim.
Feed publishers may make errors; these initial items must not be treated as verified
facts or promoted to urgent alerts solely on the basis of a title.

Collection tries public publisher feeds before query-specific aggregators. Built-in
topic aliases filter the title and supplied summary; custom topics use their own
query terms. Publisher feeds are shared through a five-minute encrypted cache so
31 topics do not repeatedly download the same feed. The initial sources are
IT Home, China News finance and arXiv cs.AI, with Bing/Google RSS search fallback.
This is initial source coverage, not an exhaustive search of all relevant sites.
S20U testing found that Bing News redirected to the regional homepage and Google
RSS timed out; regional publisher feeds were reachable. HTML homepages/challenges
are rejected, never treated as empty successful news feeds.

## Independent Learning

The existing research adapter reads queued article sources and verifies supporting
excerpts when an authorized model and its existing token/cost budget are available.
Two articles form a small review batch; this is not a total collection limit.
Review updates the same inbox identity and preserves read/saved status and delivery
time. A newly important, evidence-supported result may notify according to the user's
existing setting. Ordinary updates do not reset notification history.

Successful review enters the existing evidence/event pipeline. Unconfirmed sources
remain visible with their original provenance. Transient source/review failures
defer only those articles, with persisted backoff; they do not block new collection.
Completed legacy reports can still be delivered; idle legacy collection plans are
archived instead of repeatedly submitting obsolete source batches.

## Recovery and Resources

- Collection and model work have separate scheduling, state and failure paths.
- Feed workers serialize with each other, not with the model worker.
- Topic progress survives process restart. New data shortens the next poll;
  unchanged or failing sources back off. Polling is a collection wake-up, not a
  fixed notification schedule. Android may delay it under Doze or force-stop.
- Network reads remain bounded by the existing public HTTPS/DNS/redirect policy.
- One source can fail without suppressing a working fallback source.
- Feed records retain at most 500 articles, aligned with the existing inbox bound.
- Opening an article creates its analysis conversation on demand, not on ingestion.
- Explicit article navigation hydrates the transcript immediately, without waiting
  for the background cognition/research cycle to complete.
- Source adapter revisions invalidate only deferred poll timing, not news records,
  subscription preferences or model accounting.
- Global disabled settings and individual disabled topics remain effective.
- Model quotas are neither erased nor raised by this change.

## Verification

Targeted JVM tests cover dates, unsafe links, feed validation, duplicate identity,
source markup, adaptive polling and explicit review date bounds.
Isolated Android tests cover budget exhaustion, model-free delivery, source failure,
in-place review, store recreation and disabled-topic races. An opt-in live feed test
uses a separate store and reports fetched item count, elapsed time and zero model
dispatches; it does not modify user subscriptions or start a model.

### S20U Results, 2026-10-14

- Android 1.5.8 (1291), Galaxy S20 Ultra SM-G9880.
- Targeted JVM suite: 75 tests passed. Repository checks passed.
- Eight isolated device regressions passed: model-free delivery, in-place review,
  invalid-review backoff, source failure, disabled-topic race, cache isolation,
  alert preferences and read/saved-state restoration.
- Live network test: 13 relevant AI-model feed items delivered in 2,249 ms,
  with zero model dispatches. This is one sample, not a latency percentile.
- The actual discovery inbox increased from 2 to 42 delivered records during
  observation, including 40 new source-attributed feed items. Model accounting
  remained at 82 dispatches and 250,102 tokens; the existing 250,000-token learning
  budget was still exhausted. Collection did not require resetting that budget.
- Real UI inspection confirmed current-day headlines, source links and on-demand
  analysis entry. Unverified status is placed first in the truncated list preview.
- A warm-activity navigation regression left the article body empty until the
  background cognition cycle finished. Explicit navigation now resets and loads
  the selected transcript immediately. The installed build displayed the selected
  article body on S20U; the eight isolated regressions passed again afterward.
- During a reported freeze, Android reported no GalaxySSI ANR since boot. UI
  inspection remained responsive. This does not exclude an earlier transient
  stall; it is not evidence that every background task has completed.
- Live checks caught and fixed URL identity collapse from a text-normalization
  helper. Canonical article URLs and feed-cache URLs now use their full-byte SHA-256
  identity; regression tests include different numeric article paths and publishers.

The device is configured for important-only notifications. Ordinary unverified
items are visible in discovery without an interruptive alert. Background model
review was tested with controlled evidence, not a new paid live model run.

This feature does not claim full-text reading of every feed item, guaranteed topic
coverage, guaranteed notification timing or sustained multi-day throughput.

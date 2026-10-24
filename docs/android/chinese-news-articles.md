# Chinese-only public news reader

Public feed discovery no longer publishes title-only messages. A separate Android
WorkManager pipeline downloads each original article with the existing pinned,
certificate-validating OkHttp transport (10 MiB response limit, 20-second fetch
deadline), isolates the article body before parsing it, and translates it
locally into Chinese. This pipeline does not require global learning, a cloud
model, or an available Desktop agent.

## Publication contract

- Reject missing/thin bodies, known challenge pages, declared paywalls, unsupported
  document types, and bodies at the extractor's truncation boundary. Do not label
  these pages as completed articles.
- Translate the title and every body segment before publishing. Retain paragraph
  order, compare numeric quantities across English and Chinese units rather than
  rejecting equivalent written numbers, and do not publish partial translations.
- Prefer dedicated body containers over surrounding page layouts. Exclude navigation,
  related headlines and bylines; reject article-card listings instead of flattening them.
- Download missing translation language packs independently over Wi-Fi. Failed
  pages remain invisible and retry with persistent exponential backoff.
- Keep source identity, original URL, and attribution. The reader displays the
  Chinese title and body, without a second English version. Public source links
  can still be opened explicitly. Machine translation is not factual verification.
- Apply the same readiness gate to the inbox, indexed unread counts, and
  notifications. Legacy title-only news is hidden without deleting saved/read
  state; successful backfill preserves the original message identity.

## Storage and recovery

`attention_public_articles_v1.db` is a plaintext SQLite database inside the app's
private directory. It contains public-news queue metadata and completed Chinese
bodies. The list stores only a short Chinese preview; expanded bodies load on a
background executor. The existing public-news storage exemption remains in place;
private chat, contact attachments and model credentials keep their encryption.

Legacy feed metadata is imported in pages of 256 records with a durable cursor.
New discoveries enqueue directly. A five-minute claim lease permits process-death
recovery; completed bodies are committed before inbox publication, so interrupted
publication retries without downloading or translating again. Publication is
idempotent and preserves dismissals. A worker claims up to 24 articles, stopping new
claims after a two-minute slice, then yields to a scheduled continuation. At most two
downloads overlap, DOM extraction is serialized, and one translator is reused.
Existing thermal/power backoff remains, including checks between waves; warm devices
use one download at a time.

Schema version 4 adds an indexed first-attempt queue and a persistent six-slot lane
cursor: three recent-first slots, two oldest-first slots, and one due-retry slot.
Empty lanes lend capacity to other work. Sources rotate within first attempts;
failed recent articles cannot repeatedly jump ahead of unattempted history. Ready
bodies take priority so interrupted publication does not repeat translation.
Deterministic extraction/validation failures back off from 30 minutes, transient
failures from one minute, both capped at four hours. The reader shows ready,
processing and retry counts instead of silently hiding the unfinished backlog.
Schema version 3 requeued early development
extractions that included page chrome; corrected publication updates existing previews
without resetting their read or notification state.
Article revision markers keep obsolete previews out of the list and unread index until
their corrected body has been published, including after a cold start.
Schema version 5 makes old missing-body failures due again after fixing BEM body
containers and `no-sidebar` layouts. It preserves attempt counts and uses the retry
lane, without resetting successful articles, read state or the whole queue.

## Source coverage

The old collector stopped after the first nonempty feed. The new collector visits
every configured endpoint, visiting original publishers before search discovery.
It checkpoints after four endpoints and resumes the remaining endpoints after
process death. Topic backoff starts only after a complete pass. All topics share
30-minute public feed caches; failed sources have their own persistent backoff and
do not block healthy publishers or custom source URLs. Transport failures share a
five-minute per-host circuit across topic queries; malformed search responses also
open that circuit. Individual publisher parsing/HTTP errors remain endpoint-scoped.
This prevents dozens of categories each waiting on the same unreachable search host.
RSS responses are bounded
at 2 MiB (GitHub's current feed exceeds the former 512 KiB limit).

The original-feed catalog includes IT Home, China News, the Federal Reserve, ECB,
MIT News (research, economics and biology), Google Research, Google DeepMind,
GitHub, NVIDIA Developer, Android Developers, Microsoft Research, Hugging Face,
Cloudflare, NASA and arXiv (AI and molecular biology). They are mapped to topic
groups, filtered for relevance, and supplemented by Bing/Google news searches.
Custom topics use user-provided URLs and search, not hardwired technology feeds.
An accessible RSS feed is not proof that its linked full articles are accessible;
the Chinese-body publication contract still applies.

Hacker News is a discovery channel, not the publisher of every submitted URL.
New discoveries retain `discovered_via` separately; original domains appear as
publishers. The reader also resolves legacy Hacker News attribution using the
existing source URL, without changing article IDs, read state or bookmarks.

Official catalogs: [MIT](https://news.mit.edu/rss),
[Federal Reserve](https://www.federalreserve.gov/feeds/feeds.htm),
[ECB](https://www.ecb.europa.eu/home/html/rss.en.html).

## Extraction limits

This is static public HTML extraction, not login automation or paywall bypass.
Dynamic/login-only pages remain hidden until a later successful attempt.
Unrecognized languages and translation validation failures remain unpublished.
The original article text is held during processing, not stored as a second
full-body copy. Discovery metadata may still include the source headline/summary.
The Google Translate attribution badge is required for ML Kit output.

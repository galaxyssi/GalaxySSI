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
idempotent and preserves dismissals. Each worker processes up to three articles,
then yields to a scheduled continuation. Existing thermal/power backoff remains.
Sources rotate by their last claim time, so a stream of recent items from one source
cannot indefinitely starve older sources. Schema version 3 prioritizes early development
extractions that included page chrome; corrected publication updates existing previews
without resetting their read or notification state.
Article revision markers keep obsolete previews out of the list and unread index until
their corrected body has been published, including after a cold start.

## Source coverage

The old collector stopped after the first nonempty feed. The new collector visits
every configured endpoint, interleaving original publishers and search discovery.
It checkpoints after four endpoints and resumes the remaining endpoints after
process death. Topic backoff starts only after a complete pass. All topics share
30-minute public feed caches; failed sources have their own persistent backoff and
do not block healthy publishers or custom source URLs. RSS responses are bounded
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

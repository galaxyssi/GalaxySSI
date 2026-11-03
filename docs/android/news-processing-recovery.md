# Recoverable public article processing

## Failure modes

An article in the pending state is not necessarily awaiting its first attempt.
The queue also retains failed extraction and translation attempts with backoff.
Full Chinese publication remains mandatory; discovered URLs are not published
as if their body had been read.

The recovery increment addresses three reproducible false failures:

- Dominant Chinese language detection can echo Japanese or Korean quotations
  unchanged. The quotation's explicit script now chooses the corresponding
  local translation route instead of treating it as already translated Chinese.
  Foreign quotations embedded in otherwise Chinese text are translated separately,
  without retranslating or altering the surrounding Chinese facts.
- Physical units such as `106 MW` and `106` followed by the Chinese unit for
  megawatts are equivalent. Numeric validation normalizes supported physical
  dimensions and factors before comparison. It still rejects changed values,
  changed dimensions and incorrect magnitudes.
- An arXiv abstract page contains download tools, category navigation and
  submission history outside the abstract. The source adapter isolates the
  abstract and title. Reading this page is not represented as reading the
  complete paper. Original-paper links remain available through the source.

Contact email labels are metadata, not English prose requiring translation.
Ordinary untranslated sentences and unresolved numeric changes still fail.
Short Chinese paragraphs in the publisher's explicit article container are
retained even when each paragraph is shorter than a generic English-oriented
prose heuristic. Sibling recommendation lists are not imported as article text.

## Checkpoints

Public article schema 9 adds indexed per-article extraction and translation
progress tables. It does not reset the archive, subscriptions, unread or saved
state. A non-destructive upgrade makes the corrected translation failure classes
eligible for another attempt while retaining attempt counts and failure evidence.

Extraction checkpoints retain the structured source, original figures and
captions for up to 24 hours before refetching. Content fingerprints invalidate
translation progress when the source changes. Successfully validated segments
survive a retry or process restart; cached output must pass current validation
again before reuse. Cache keys retain article identity and exact source text.

Partial progress is never a published body. Only after complete translation and
publication validation does the normal ready transaction persist the complete
Chinese body and remove its staging rows. Other articles' checkpoints remain
untouched. Cancellation, network errors and unavailable translation models
retain the normal retry path; no additional Agent calls or unbounded concurrent
downloads are introduced.
Timeouts that made validated progress can resume promptly instead of inheriting
an old four-hour backoff. Model-download completion releases only articles
waiting for that dependency. Cached segments are not rewritten when unchanged.

Staging belongs to the existing public, unencrypted article database. It does
not contain private chats, credentials, pairing keys or user prompts. The
existing worker's load, thermal, time and download-concurrency bounds remain.

## Continued publisher discovery

Schema 10 adds public publisher/feed membership and probe state. Existing
published metadata is backfilled in indexed 256-record pages. Unknown publisher
sites are checked one at a time for declared RSS/Atom links, not guessed paths.
Article extraction must still establish a readable page; HTTPS and same-site
ownership checks reject foreign hosts, credentials, private endpoints and
unrelated alternate-language HTML links. Failed probes back off and successful
no-feed results are retained for seven days instead of repeatedly refetching.
Existing configured publishers and project/video aggregators are not probed.

At most two declared feeds per publisher are learned. Their relevant articles
retain the original enabled-interest memberships and normal URL deduplication,
extraction and Chinese publication requirements. The collector reserves one
slot in its existing four-endpoint batch for a due learned feed, rather than
raising network concurrency. Poll state survives restarts and source failures
use existing backoff. New source membership wakes its topics without resetting
their collection cursor. Private sources and authenticated feeds are not added.
Learned articles reuse an existing `www`/bare-host article ID only when the
path, query and title also match. Encoded separators, different titles and
different paths are not conflated. This avoids repeated processing without
renaming or removing historical article identities.
Comment/reply subscriptions are not article news feeds. Declared feed titles,
comment paths and WordPress comment-feed parameters are excluded. Schema 11
removes only already-learned comment subscription rows and their topic
memberships; it does not remove article rows, bodies or user read state.

An article that has no declared publisher feed does not become a fictional
recurring news source. Some single-article websites are product landing pages,
not publishers. Others have more discoveries whose bodies are still pending;
publication recovery and continued discovery address these different cases.

## Verification

Unit coverage includes equivalent units, wrong units/magnitudes, retained version
numbers, late translation failure, reuse of validated progress, rejection of
corrupted cached output, contact labels and abstract-only extraction.
Instrumentation covers reopening checkpoints, source changes, expiry, retained
figures and isolated cleanup after a complete body is persisted. Opt-in real
publisher tests exercise the same extraction and local translation pipeline;
fixture success does not substitute for those live checks.

### S26U audit on 2026-11-02

The initial consistent public archive contained 12,825 discovered articles:
5,159 published bodies and 7,666 pending records. There were 533 publisher
domains with exactly one published body. Of those, 486 had only one discovered
URL; the other 47 had 79 additional unpublished discoveries. A discovered domain
is not automatically a configured RSS source.

An intermediate schema-10 consistent snapshot contained 5,416 published bodies.
It verified recovery of 244 previously pending articles: 108 language-validation,
93 unknown-language, 39 quantity-validation and four body-extraction failures.
All original article IDs and all previously published bodies were retained.
The remaining 7,427 pending records include newly discovered items, unattempted
recovery work, actual translation failures and inaccessible publisher pages.
This is a recovery checkpoint, not a claim that the entire backlog is resolved.
The final schema-11 consistent snapshot verified 362 recovered old records,
5,544 published bodies and 7,331 pending records, again with no original IDs
or bodies lost. Six valid learned feed endpoints remained; both accidentally
learned comment endpoints were removed without deleting any article.

Validation for Android `0.1.7.10` / `1423`:

- 228 relevant JVM tests passed.
- 49 isolated device regressions passed; six separately opt-in live checks were
  skipped in that regression invocation, not counted as live successes.
- Four real articles passed production extraction/local translation: mixed
  Chinese/Japanese IT Home text, Crusoe power units, an arXiv abstract and a
  short-paragraph China News article.
- Sean Goedecke's published article exposed two same-site feed endpoints.
  The initial live check produced 16 relevant records and four new URL records
  in the normal body-processing queue. Three were `www`/bare-host variants of
  existing discoveries, not new stories. That finding led to the conservative
  known-publisher alias reuse and collector/device regression above. Discovery
  counts must not be presented as novel published-story counts.
- Background archive probing independently learned declared subscriptions from
  404 Media, 9to5Google, Abolish AI and About Amazon. The audit also exposed two
  WordPress comment feeds, prompting the discussion-feed exclusion and narrowly
  scoped migration before release.
- Simon Willison and Latent Space timed out in the phone's live checks. They
  were not counted as successful publisher acquisition; normal bounded retry
  remains necessary for inaccessible sites.
- In the final Sean Goedecke check, one declared endpoint timed out while the
  other still supplied eight relevant records. Replay added no duplicate rows.
- The opt-in public snapshot test uses SQLite `VACUUM INTO` and verifies
  `quick_check`, rather than copying a database file across active writes.

The APK was installed over the existing S26U installation without clearing data.
The repository check and both debug APK builds passed. Logs and public audit
databases stay in the ignored build directory, not in source control.

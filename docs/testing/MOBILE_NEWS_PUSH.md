# Phone-Only Hybrid News Collection

## Execution Ownership

All collection, source filtering, persistence, deduplication and initial inbox
delivery run on Android. No Desktop bridge, hosted GalaxySSI collector, public
callback endpoint, Firebase account or paid model call is required for ingestion.
Existing optional background model review retains its configured model routing.

The two acquisition paths share `ProactiveAttentionFeedStore`:

1. Hacker News official Firebase REST event stream, initiated by the phone.
2. Existing adaptive RSS collection, extended with Atom and explicit public web
   sources. A custom topic's query can contain an HTTPS source URL. For HTML,
   dated Article/NewsArticle/BlogPosting JSON-LD or a declared RSS/Atom feed is
   required; script execution and arbitrary recursive page crawling are not used.

This is one integrated real push source, not a claim that all publishers offer
push. WebSub/webhook sources needing a publicly reachable callback are not
enabled in this phone-only implementation. Native source notifications are not
the same as Android OS push delivery.

## Push Lifecycle

- The existing visible `MessageService` owns one outbound source connection.
- OkHttp SSE handles protocol framing. Firebase root `put`, child `put`, root
  `patch`, keep-alive and access-revocation events are handled explicitly.
- The first snapshot establishes a baseline; it does not issue hundreds of old
  notifications. New IDs are persisted together with the updated cursor.
- Article reads run serially on a separate worker, never on the main thread or
  inside the stream callback. Pending work and individual retry times survive
  process restart. A failure does not block other pending articles.
- Reconnect snapshots identify additions still present in the source's recent
  list. This is not guaranteed recovery of every historical item after a long
  outage: the provider's list is bounded. RSS polling remains independent.
- Stream failures back off with jitter to five minutes, without a retry-count
  stop. Network changes trigger reconciliation. Pausing attention or stopping
  the service cancels the stream; in-flight results recheck subscription state.
- No wake lock, exact alarm, new foreground service or battery-exemption change.
  Doze, force-stop and network restrictions can delay delivery. Reopening the
  app/service restores the cursor and resumes acquisition when allowed.

## Provenance and Safety

Hacker News is a community discovery source, not an authority certifying the
linked article. Its submission date is displayed as a discovery date, not the
original publication date. The evidence ledger leaves original publication time
unknown until independently established. Initial text stays explicitly unverified.

Public HTTPS validation, bounded article fetches and private-address blocking are
retained. The stream connects only to the official Firebase hostname and its
Firebase redirect hosts, with TLS and public DNS results. No cookies or account
credentials are sent. Source content is data, never instructions to the agent.

Push and RSS use the same canonical URL hash. Repeated stream events, reconnects
and cross-source discovery are deduplicated against retained source/inbox history.
Read/saved state and existing important/all/silent notification preferences remain
unchanged. Model learning and original-page verification do not block delivery.

## Validation Plan

- JVM: snapshot/patch identity, malformed-event rollback, replay, freshness,
  original-date distinction, URL checks, retry backoff, Atom, HTML feed discovery
  and dated JSON-LD.
- Device: encrypted cursor/pending-work recreation, backoff and completion,
  cross-path deduplication and evidence dates, existing source-first regressions.
- Opt-in live test: `ProactiveAttentionDeviceTest#livePhoneStreamReceivesEventsWithoutRelayOrModel`
  with `attention_live_push=true`. Records receipt latency and snapshot size in
  app-private test evidence, with no model invocation or production cursor writes.
- Production observation: connection/event logs, background updates, and absence
  of replay floods. Do not equate an initial snapshot with a newly published item.

## Device Validation (2026-10-14)

On Samsung S20 Ultra (SM-G9880), Android v1.5.9:

- The final build passed 88 targeted JVM tests and all 13 selected device tests
  (11 isolated regressions plus the two opt-in public network checks). Repository
  checks and both debug APK builds passed.
- Eleven isolated device checks passed: framed SSE snapshot + new story + replay,
  cursor recreation, pending-work backoff, RSS/push identity, unknown publication
  dates, source-first publication, unavailable originals, late disabled-topic
  results, review retries, collection independent of model budget, feed cache
  identity, selected notification modes and persisted viewed state. Some checks
  cover multiple assertions.
- The opt-in public SSE test received 500 IDs in its initial snapshot in 31,836 ms;
  the final repeat took 1,696 ms. These are two observations, not a latency SLA.
  This validates the connection and framing, not a claim of instant first connect
  or 500 newly delivered articles. The fixture SSE test validates new-event inbox
  delivery and duplicate suppression without waiting for a public publisher.
- The opt-in public RSS test delivered 19 source summaries to an isolated inbox
  in 3,062 ms (3,539 ms on the final repeat), with zero model dispatches in that
  test context.
- The production phone service logged connection and subsequent update events.
  Existing user topics and read state were not reset. No Desktop collector ran.

Long-running Doze, battery consumption, vendor background restrictions and
multi-day outage recovery have not been fully measured by this change. The
existing feed/inbox retention and display limits are unchanged.

## References

- [Official Hacker News API](https://github.com/HackerNews/API)
- [Firebase REST streaming](https://firebase.google.com/docs/database/rest/retrieve-data#section-rest-streaming)

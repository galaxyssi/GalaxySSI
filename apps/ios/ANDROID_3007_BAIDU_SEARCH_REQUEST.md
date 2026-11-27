# Baidu Search Representation (Android #3007 Follow-up)

Reference: Android #3007, merge `65655f0c79c6ab04121150229a65b089180f82f2`,
`AgentWebIntelligenceSearchAdapter.requestHeaders()` for the Baidu source.
Incremental base: main `fe0940f0cc538bfc6659a49588b066ea560917b8`.

The native search request now supplies the exact pinned desktop Chrome User-Agent
to Baidu's `https://www.baidu.com/s` endpoint. The reference requests this
representation to obtain server-rendered result cards with source URLs and
snippets. The existing inert DOM parser still reads and validates those cards;
this is not browser automation or a claim that the live service is accessible.

Only a typed search-source policy can select the header. It is recomputed for
every redirect against exact HTTPS host, default TLS port, no userinfo and exact
encoded search path. Off-origin and non-search redirects lose the override.
Ordinary fetch/article calls do not acquire it even on that URL. Other provider
headers, credentials, route selection, parsing, grants, response bounds and
original request deadlines are unchanged. No general custom-header argument or
new secret store is exposed.

Six synthetic XCTest methods are authored, not executed: exact endpoint policy,
actual registry/card/query flow, off-origin/path redirect confinement, same-path
redirect/deadline preservation, ordinary-fetch exclusion and permission denial.
A focused JS checker reverses exactly three declared provider hooks and compares
the complete remaining provider to the incremental base. Historical JSON/image/
failure guards compose that explicit normalizer without dropping their existing
assertions. Source checks are not Swift compilation, Foundation URL behavior,
URLSession redirect/TLS, live Baidu availability, latency or UI/device acceptance.

The dedicated Baidu check and iOS project check pass. The historical encoded-URL,
JSON-adapter and image-adapter scripts still fail their older whole-file snapshot
assertions. Substituting the untouched incremental-base provider reproduces the
same failures at the same assertions; they are not reported as passing checks.
The new whole-provider comparison allows only this increment's three hooks and
does not exempt or weaken unrelated transport behavior.

No native build/tests, full repository check, CI monitoring or IPA generation is
performed. No private evidence or generated output is committed. This is one
confirmed request-path omission, not completion of Android #3007 or the backlog.

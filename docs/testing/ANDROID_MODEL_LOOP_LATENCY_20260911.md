# Android Model-Led Search Latency

## 1.1.81 Search-Tail Investigation

The user accepted the measured 1.78-1.84 s App preparation time as the current
baseline. This iteration targets search tails and full model-led response latency,
not a hard one-second deadline or a model bypass.

An additional S26U no-search-cache matrix on 1.1.80 found:

| Query / policy | Service ms | Coordinator ms (old boundary) |
| --- | ---: | ---: |
| Original species + scientific name / fast | 3443 | 1118 |
| Same / balanced | 4068 | 2046 |
| Same / explicitly selected four engines | 7340 | 6044 |
| Dragon Ball spacecraft interior / images | 720 | 654 |
| Android WebView multiple processes / fast | 2707 | 713 |

The old coordinator timer excluded source selection. General routing scanned
learned domains, read broad source health and could select image engines or
unrelated specialist indexes. The balanced species query returned MDN JavaScript
results. Bing results included site badges rather than article headings; HTML
search results lost their snippets. These are relevance defects as well as causes
of repeated model searches.

Changes in 1.1.81:

- Scope general lookups to built-in general/regional engines and favor explicit
  language support. Specialist and learned domains require model-selected topics
  or explicit engine selection. No regex topic classifier or model bypass.
- Parse result-card headings and snippets with Jsoup, including mobile Sogou
  cards and Bing redirect decoding; exclude navigation, ads and unsafe URLs.
- Fast completion requires query-related snippets across independent websites,
  rather than merely counting engines and arbitrary links. This is a lexical
  prefilter, not semantic proof; the model still reviews and refines the evidence.
- The model-facing web lookup defaults to fast; an explicit balanced/deep profile
  remains honored. Explicit engine lists still run all requested sources.
- Include source-selection time in coordinator telemetry and version the search
  cache key so old malformed evidence is not silently reused.

The 1.1.81 build and 130 targeted JVM tests passed. It was installed in place on
S26U, with two no-search-cache matrices and two real DeepSeek main-page tasks.
The diagnostic matrix asserts cache behavior, not semantic quality or a
guaranteed one-second SLA.

| 1.1.81 stage / probe | Measured elapsed |
| --- | ---: |
| Complex image query, service, no search cache | 397-471 ms |
| Ordinary species / WebView web queries, fast, no search cache | 1117-1748 ms |
| Local source selection, ordinary fast queries | 38-52 ms |
| Real UI original image request, durable completion | 15964 / 18094 ms |
| Real UI image tool calls, all fresh | 581-801 ms |
| Real UI web tool calls, all fresh | 3458 / 4491 ms |
| Strict balanced species lookup | 2722 / 9226 ms |
| Explicit four-engine lookup | 6103 / 6138 ms |

The 15964 ms main-page run included three model rounds (1846, 1576 and 3264 ms),
4491 ms for the first parallel web/image batch, 732 ms for a follow-up image
query, and 28 ms citation verification. Other time includes durable dispatch and
App completion. Parallel image calls are not added to the web batch duration.

The first 1.1.81 UI visibility predicate accepted a drawable before its pixels
were painted. Its screenshot showed loading placeholders; that visibility time
is not accepted. The test now checks both a visible bitmap and screenshot color
variation. The second run's screenshot shows photos, opens an image and verifies
saved bytes. Its 16157 ms visible-image observation is a post-completion upper
bound, not an independently measured earliest paint. One selected image was
cooked fish despite a fresh-fish caption, so the transport/display test is not
proof that all chosen images and captions are semantically correct.

Per-source receipts isolated the remaining main-page web tails: source selection
was only 57-84 ms; Baidu returned zero parsed results in 268-280 ms, Sogou was empty
or had insufficient matching snippets, and an empty Yandex source took
3274-4296 ms. Waiting was due to insufficient useful evidence, not a local
two-second source-index scan anymore.

## 1.1.82 Baidu Result-Card Repair

Public desktop Baidu HTML exposes canonical source URLs in ordinary
`.c-container[mu]` result cards and per-source summaries in
`[data-module=abstract]`. The mobile representation often omits these anchors.
The Baidu adapter now requests that desktop representation and parses its source
URL directly, avoiding a separate opaque redirect request. Other engines retain
their existing representation. Aggregated answer modules without ordinary result
headings are not source evidence. Unsafe URLs and search-navigation links remain
excluded; the search-cache schema is advanced to avoid stale malformed results.

The 1.1.82 build and 132 targeted JVM tests passed; it was installed on S26U.
A real main-page DeepSeek run completed in 20842 ms (four model rounds), with
fresh image calls of 556-867 ms but a 5454 ms web call. Thumbnail, fullscreen and
saved-byte checks passed. A fresh complex image service probe took 577 ms. The
web matrix still had 6.2 s fast and 9.0 s balanced tails, so the desktop HTML
parser repair alone did NOT establish phone web-search improvement.

A phone-only response capture then proved why: Baidu redirected to
`wappass.baidu.com/static/captcha/tuxing_v2.html`, returning a 1488-byte safety
verification page in 359 ms. This is an unavailable source, not a healthy empty
query. No challenge bypass was attempted. Sogou returned a normal 428127-byte
result page in 1381 ms with eight parsed results. Host HTML availability must not
be used as proof of phone availability.

## 1.1.83 Verification Failures And Focused Fast Lookup

- Recognize the observed Baidu verification URL/title as a non-retryable
  `source_verification_required` failure. Existing source-health/circuit handling
  can then account for it instead of rewarding a healthy empty response.
- Ordinary model-facing fast web lookup fans out to three preferred sources.
  This reduces breadth, not the request timeout or evidence-quality predicate.
  The model is told to review relevance and refine insufficient results.
- Explicit fanout/source settings and balanced/deep research remain unchanged.
  No image or question bypass, model round cap, or one-second failure deadline is
  introduced. Image lookup still uses its separate fast path and evidence flow.
- The device matrix now uses the same web argument normalization as the actual
  model-facing tool; no-cache flags remain explicit in every probe.

The 1.1.83 (969) build and 133 targeted JVM tests passed with no failures, errors
or skips. It was installed in place on S26U only. Two real main-page DeepSeek
tests, two seven-case no-search-cache matrices, and a timing-dump diagnostic
passed. The matrices assert cache behavior; they do not assert a semantic score
or a one-second SLA.

| 1.1.83 measurement | Run 1 | Run 2 |
| --- | ---: | ---: |
| Original image question, durable UI completion | 13985 ms | 15804 ms |
| Screenshot-verified image observation (upper bound) | 14382 ms | 16220 ms |
| Three model rounds, summed | 7041 ms | 8384 ms |
| Main-page web call, fresh | 1892 ms | 1763 ms |
| Follow-up image batch, parallel wall time | 1136 ms | 857 ms |
| Complex image service probe, no search cache | 576 ms | 467 ms |
| Ordinary fast web probes, no search cache | 1453-2254 ms | 1582-1902 ms |
| Balanced species probe, no search cache | 3594 ms | 4770 ms |
| Explicit four-source probe, no search cache | 6101 ms | 6106 ms |

In the first main-page test every search call was fresh. In the second, the first
image lookup was a 28 ms cache hit; its web lookup and both follow-up image
lookups were fresh. Fresh main-page image calls across these two tests ranged
from 733 to 1136 ms. The complex-image probe is a different query and is reported
separately. Neither search-cache timings nor screenshot observations are confused
with full model-led completion.

The first model rounds were 1685 / 2239 / 3117 ms; the second were
1416 / 1626 / 5342 ms. The longer final generation explains why the second total
was slower despite a faster search batch. Model work now accounts for roughly
7.0-8.4 s; App dispatch, durable completion and scheduling account for roughly
3.9-4.8 s. The first App cloud dispatch took about 1.75 s, the second 1.83 s.
Citation verification remained in the loop. No side-effect durability was
removed to improve timing.

Both main-page tests showed actual bitmap pixels, opened the image viewer and
verified saved bytes. Responses still included extra comparison/recipe material
or unsolicited follow-up text. Source labels alone do not establish exact
species identification. Transport/UI success is therefore NOT full image
relevance acceptance. Semantic image verification remains unfinished.

Phone receipts now record Baidu as `failed/source_verification_required`, not a
healthy empty result, and existing source circuit handling can exclude it after
failures. No attempt was made to solve or bypass the source's verification page.

These are small diagnostic samples, not a production p95 claim. Complex image
source latency reached the suggested target in the measured probes. Ordinary
web latency improved but did not consistently reach one second; balanced and
explicit-source searches are intentionally not reduced to the fast policy.
Main-page completion improved from the earlier 17.9-25.2 s examples, but stable
latency and complete relevance are not yet demonstrated. No PR was submitted in
this iteration.

Evidence is in `build/reports/s26u-*-1.1.83-*` and
`build/reports/android-search-tail-1.1.83-build.log` in this worktree.

## Required Flow

Version 1.1.79 restores model-led requests, including literal image queries:

App context and durable task setup -> model tool planning -> tool observations ->
model review and optional follow-up searches -> synthesis and citation verification
-> App delivery. The regex/direct-image response path from 1.1.76-1.1.78 has been
removed, including its model-bypass accounting. Those versions' no-model timings
are not comparable model-loop performance results.

The user's suggested targets are preparation around 200 ms and image search around
one second. These are performance goals, not failure deadlines. The measured
486-679 ms no-search-cache probes from 1.1.77 concern the image-search service, not
model planning, network image loading, or the whole App reply.

Independent web and image calls planned in the same model round run concurrently.
A later query derived from earlier observations cannot run before the model has
reviewed those observations. Model review, follow-up, safety and citation checks
must not be removed to obtain a smaller total.

## Changes

- Preserve indexed conversation reads, background warmup isolation, raw search
  transports, scoped source-health reads, batched receipts and same-round tool
  concurrency from the earlier latency fixes.
- Commit each workspace mutation, its changed indexes and retention removals in
  one encrypted SQLite transaction. Publish the new in-memory state only after
  commit, preserving durable state before execution and rollback on failure.
- Read only the validated device route ID when creating a task, rather than
  constructing the full profile, fingerprint and public-key bundle. Invalid IDs
  still use the existing profile normalization; no separate cached identity is
  introduced. This additional change is in 1.1.80.
- Retain each image's own title/alt when multiple images share a source page.
  A parent's page title does not identify every picture on that page.
- Compact image evidence to useful descriptors, source and image URLs, citation
  identity, ordering and retrieval metadata. Keep short excerpts rather than long
  article snippets. The model still makes relevance and synthesis decisions.
- Tell the model to preserve subject qualifiers and refine searches when evidence
  is insufficient, rather than filling the requested count with adjacent topics.
- Log per-model-round input size, first activity, completion and citation-check
  time, plus tool service/encoding time and cache-hit status. No credential or
  prompt content is added to these timing logs.

These metadata checks do not constitute independent pixel-level image verification.
Poorly captioned sources can still produce visually irrelevant candidates.

## Verification Plan

- JVM regression: image parser/ranking and compact evidence integrity, ordered
  parallel web/image calls, tool progress, execution recovery and workspace state.
- S26U fixture: a literal image request must reach a model endpoint, execute its
  tool call, send observations back, then return model-authored synthesis.
- S26U fixture: blocked model destinations remain blocked; no image-search bypass.
- S26U encrypted storage: injected index-write failure rolls back the new workspace
  and leaves no stale in-memory state; completed tasks update recovery indexes.
- Live DeepSeek and main-page image tasks, plus explicit no-search-cache probes.
  Record the actual number of model rounds; do not invent a second-search duration
  if the model judged a single search sufficient.

## Measured 1.1.79 Results

All measurements below were taken on S26U (SM-S9480, R5GL546G3LZ), September 11.
The app was updated in place; conversations, credentials and model settings were
not cleared. These are small diagnostic samples, not p50/p95 service guarantees.

- Build and 206 targeted JVM tests passed, with zero failures or skipped tests.
- Four model-routing/storage fixtures passed on the phone.
- Eight WebView/image rendering regression tests passed on the phone.
- Two main-page live DeepSeek tasks, one direct model-loop test, and one
  no-search-cache service test passed. Main-page tests also opened an image and
  verified that the saved download contained the same image bytes.

The original public Chinese image query completed in 17,485 ms. It retained three
model rounds, web search, image search, follow-up refinement and citation checks.
The previous model-led samples were 20,231 ms and 25,678 ms. Query planning,
source response times and cache state vary; this is not a controlled speed ratio.

| Stage | 1.1.79 elapsed |
| --- | ---: |
| Submission, context, durable setup, cloud dispatch | 1,727 ms |
| First model tool planning | 2,112 ms |
| First tool batch (web + images concurrently) | 4,208 ms |
| Model review and follow-up planning | 2,933 ms |
| Follow-up image batch (two concurrent calls) | 792 ms |
| Final generation and citation checks | 3,663 ms |
| App completion after provider result | 2,050 ms |

The first image search was a cache hit (31 ms); the concurrent web search was not
(4,205 ms). The second image searches were both fresh (779 and 790 ms), so their
batch wall time was about 792 ms rather than their summed time. The legacy
visibility probe reported 18,233 ms. Its predicate did not assert the visible
viewport, so this value is not accepted as a reliable first-paint time.

A second main-page request for five Dragon Ball spacecraft images completed in
19,882 ms. The inspected first image included the requested spacecraft rather than
the previous unrelated character-only hit. Not all five images were independently
visually audited, so the fixture pass does not establish perfect image relevance.

Explicit `use_cache=false` image-service probes asserted `cache.hit=false`:

| Query | Service | Source network | Image load |
| --- | ---: | ---: | ---: |
| Chinese original image subject | 561 ms | 447 ms | 3 ms |
| Chinese clownfish | 631 ms | 510 ms | 1 ms |
| English clownfish | 511 ms | 426 ms | 0 ms |

The image loader may use cached image bytes; these are fresh search requests, not
cold image-download measurements. A separate real DeepSeek model-loop probe took
5,880 ms, plus 255 ms to load its first returned image. That probe does not include
main-page task preparation/completion, and it used a different public question.

Reports: `build/reports/s26u-*-1.1.79*.json`, screenshots alongside the reports,
and `build/reports/s26u-model-loop-1.1.79-latency.log` (local test outputs).

## Final 1.1.80 Validation

Installed version 1.1.80 (966) on S26U only. The final build and all 206 targeted
JVM tests passed again. Five model-routing, atomic-storage and identity fixtures,
eight WebView/image regressions, three main-page live-model runs, and one
no-search-cache service test passed on the device (17 test executions).

The last main-page run used the strengthened visibility predicate: a decoded
bitmap must intersect the on-screen viewport by more than 200 x 100 pixels and
must not be the error placeholder. Its screenshot shows the image in the output
area. Earlier visibility timestamps are retained as diagnostic data only. Each
main-page run verified opening an image and saving identical bytes, not that
every returned picture had loaded or was semantically correct.

Same original query, three actual runs:

| Metric | Run 1 | Run 2 | Run 3 (strict visibility) |
| --- | ---: | ---: | ---: |
| App preparation to cloud request | 1,782 ms | 1,790 ms | 1,841 ms |
| First web tool | 9,190 ms fresh | 8,763 ms fresh | 24 ms cached |
| First image tool | 38 ms cached | 40 ms cached | 39 ms cached |
| Later fresh image calls | none | 2,853 ms | 839 / 847 / 859 ms |
| Model rounds | 3 | 3 | 4 |
| Durable task completion | 21,753 ms | 25,157 ms | 17,925 ms |
| Verified visible image observation | not validated | not validated | 18,192 ms |

These results do **not** establish consistently faster end-to-end replies. The
main remaining local spans are task admission/persistence (446-544 ms), initial
loop persistence (251-430 ms), further pre-dispatch state/projection writes, and
about 2.1 seconds between provider completion and task completion. Indexed context
reads and route-only identity lookup are not the dominant remaining costs.

Fresh image-service probes in 1.1.80: 575, 694 and 530 ms, with cache-hit false
asserted. Image bytes were warm (1-3 ms). More complex live image calls still
reached 2,853 ms, so the one-second goal is not a universal guarantee.

The identity fixture confirmed the same route ID on all six reads. Warm full
profile reads took 0.29-0.32 ms; route-only reads took 0.017-0.027 ms. The first
full-profile read was 101.8 ms and includes initialization. It must not be used to
claim a 100 ms saving from this accessor change alone.

Reports: `build/reports/s26u-*-1.1.80*.json`,
`build/reports/s26u-model-loop-1.1.80-latency.log`,
`build/reports/s26u-image-ui-model-1.1.80-visible.png`.

## Remaining Targets

Preparation is not yet within 200 ms, web search is not consistently near 500 ms,
and end-to-end responses are not one-second operations. Model-generated follow-up
searches must remain dependent. Strong image relevance needs more than title/alt
matching; visual verification and more diverse real queries remain evaluation
work. Next optimization should target admission lock/initialization spans,
coalescing durable startup state without losing recovery guarantees, completion
projections, and quality-preserving slow-source selection. Do not skip model
review, weaken relevance checks, or advertise a hard one-second deadline.

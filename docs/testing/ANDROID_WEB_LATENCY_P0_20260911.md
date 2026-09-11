# Android Web Latency P0

## Scope

Android 1.1.72 (958). Existing UI layout, public-URL transport restrictions, attachment
handling, encrypted storage and citation checks remain enabled. The earlier
isolated WebView renderer recovery changes are included in this working branch.

The observed DeepSeek request took 230.102 seconds. Eight tool batches occupied
178.602 seconds (77.6%). This is one historical sample, not a percentile or a
controlled benchmark. Its network connection took 389 ms, so it did not establish
that provider connection latency was the main cause.

## Implemented

- Preserve raw escaped path/query components during HTTPS validation, redirects
  and URL canonicalization. Previously the URI component constructor re-escaped
  percent signs (for example, %E5 became %25E5). The search-cache key now versions
  URL normalization so results from malformed requests are not reused.

- Hot fetch/search/cache-get responses use indexed cache counts instead of full
  document decryption and aggregate statistics. Explicit cache-status inspection
  still supports full statistics.
- Document/source eviction uses bounded key queries; writes no longer decode all
  cached bodies just to check a capacity limit. Source-health receipts and source
  observations are written in batches, preserving durable document writes.
- Optional source learning runs in a single low-priority, bounded queue. Queued
  work is invalidated on cache clear using shared per-database generation state.
  Queue overflow skips learning, never the evidence result or durable document.
- All explicit engines in a research plan are checked before cache/network work.
  Invalid engine responses are non-retryable without corrected arguments.
- Source-associated images survive evidence packing and model-size compaction.
  Multiple images on one source page are retained without duplicate citations.
  Image URLs are discovery evidence, not proof of successful visual inspection.
- Citation verification accepts discovered media only as Markdown image targets;
  arbitrary image URLs and treating a media URL as a factual source remain invalid.
- Research queries and page reads share one operation deadline. Fast profile
  defaults are no longer overridden with balanced fanout/timeouts.
- Direct streaming cloud turns share a web budget starting at the first tool batch:
  60 seconds normally, 180 seconds when that first batch explicitly selects deep.
  There is no fixed total tool-call count. Three batches without new evidence
  request finalization. Final synthesis is separately bounded to 30 seconds per
  synthesis/repair round; the provider's initial response policy is unchanged.
- Coroutine cancellation/deadlines reach transport cancellation listeners. Queued
  search workers do not start network work after their deadline. Early search
  completion cancels remaining transports.
- Each tool publishes completion as it finishes, while provider tool-result order
  remains unchanged. Completion callbacks are serialized.
- A URL that timed out is not fetched again through extract/diff in the same turn.
  A fresh user request can retry normally.

## Verification

Initial 1.1.71 run: 77 JVM tests passed; 4 S26U WebView tests passed. The actual
public page render took 2,138 ms. A real DeepSeek image lookup failed acceptance:
70,750 ms total, 70,733 ms first visible text, no returned image. The shared budget
stopped web activity at about 61.7 seconds, but that is not a task-quality success.
This probe led to the additional URL-encoding fix.

Final 1.1.72 verification:

| Check | Result |
| --- | --- |
| Targeted JVM regression suites | 94 passed, 0 failed, 0 skipped |
| S26U isolated WebView tests | 4 passed; public page rendered in 2,077 ms |
| Real DeepSeek public page read | Passed: 4,430 ms total, 4,414 ms first text; web fetch 1,050 ms |
| Real DeepSeek image search | Failed: 77,889 ms total, 77,878 ms first text; no usable image |
| Real DeepSeek official WebView documentation search | Task-quality failed: 70,288 ms total; irrelevant search results and Android developer pages timed out |

The public page probe actually called web_fetch and returned the correct
"Example Domain" title with its source URL. This is a small readable-page test,
not a general latency percentile or proof that all search tasks work.

The documentation-search instrumentation completed because its generic text-mode
assertions check only a nonempty completed response. Manual review correctly
marks the task failed: the response did not return verified official links. Do
not count this test-process success as a search-quality pass. Future fixture
assertions should validate expected source hosts and requested answer fields.

The image probe returned irrelevant search results and timed out reading
Wikipedia/Wikimedia pages. It did not fabricate an image. Pending web transports
were cancelled at about 61.9 seconds. The final answer still took another 16
seconds and over-explained irrelevant results. Task-quality acceptance remains
failed; a completed model stream is not a successful image lookup. The stricter
test requires both an image and source link, then downloads the image and checks
Android bitmap decoding; it stopped at the missing-image assertion on this run.

Targeted JVM suites: AgentWebLatencyRegressionTest, AgentWebIntelligenceTest,
AgentWebResearchPlanTest, AgentWebEvidenceVerificationTest, CloudWebGroundingTest,
CloudWebToolLoopProgressTest, CloudToolBatchExecutorTest,
AgentDynamicWebArticleFetcherTest, AgentWebRendererHealthTest,
AgentWebMediaNativeToolsTest.

Initial device scope: S26U / SM-S9480. The user then connected S20U / SM-G9880
and testing moved to that device. SM-T575 was not operated. The opt-in
AgentWebLatencyDeviceTest uses an
already configured DeepSeek account and a public fixture question, with no prior
chat history or credential changes. It records actual tool completion timestamps,
first visible text, total time, response and discovered image count. Reports are
saved in the app's external files/reports/web-latency-latest.json.

Local raw results are retained under build/reports (not committed):
s26u-deepseek-page-p0-final.json, s26u-deepseek-image-p0-final.json,
s26u-deepseek-search-p0-final.json, s26u-web-renderer-p0-final-20260911.log.
Existing conversations, credentials and pairings were preserved by in-place
installations.

### S20U Follow-Up

The user connected S20U after the S26U run. In-place upgrade from 1.1.24 (910) to
1.1.72 (958) succeeded and package metadata confirmed the new version. Four
isolated WebView device tests passed. The real DeepSeek page read passed in
3,586 ms (first visible text 3,557 ms; web fetch 1,055 ms) and returned the correct
Example Domain title and source. The image lookup failed in 61,902 ms with zero
images: Wikimedia/Wikipedia requests timed out, and partial results did not
produce a deliverable image. This reproduces the remaining image-source issue
on a second device; it is not a S26U-only symptom. Raw reports are
s20u-deepseek-page-p0-final.json and s20u-deepseek-image-p0-final.json under
build/reports. The app was launched again after instrumentation.

## Remaining Work

- Independent, reachable image-source adapters and relevance acceptance. Many
  indexed image catalog entries currently delegate site-scoped queries to the
  same Bing/DuckDuckGo infrastructure; their distinct catalog IDs do not provide
  independent network failure domains. Provider diversity, source relevance and
  actual image decoding need separate acceptance gates.
- Reduce irrelevant final-answer expansion when evidence misses the user's
  requested subject. Failure should be brief and actionable, not a comparison of
  off-topic search results. The image probe exposed this remaining UX issue.
- Typed metadata/vector indexes for full cache similarity queries and explicit
  cache status; these operations can still scan stored documents.
- Application-wide adaptive resource pools and independent single-flight owner
  cancellation for unrelated concurrent requests.
- Incremental block-level citation validation; final evidence-based text is still
  buffered for the existing answer-level citation check.
- Broad repeated real-provider benchmarks and percentile gates. No p95 target,
  10-session concurrency score or universal 30-second answer guarantee is claimed.
- This P0 does not retrofit the same turn budget into every legacy/non-streaming
  provider path, nor change the native long-running Agent task budget policy.

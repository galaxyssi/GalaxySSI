# Query Latency Targets: 2026-09-12

## Scope

Base: `cef237557f5f8f422f93832a535e3d63e3ba81ed` (`main`, PR #3025 merged).
Android: 1.1.101 (987). Desktop: 1.1.48. Only S26U / SM-S9480 was operated.
Existing app data and pairings were retained. No changes to model choice or reasoning effort.

The weather prompt changed from Guangzhou to **Zhuhai**. Do not present the two
cities as an identical-task before/after comparison.

| Query | DeepSeek target | Codex target |
| --- | ---: | ---: |
| Today's Zhuhai weather | <= 10 s | <= 30 s |
| Two existing Dragon Ball pictures | <= 10 s | <= 30 s |
| Today's technology news | <= 30 s | <= 60 s |

Original prompts (JSON escapes):

```json
[
  "\u73e0\u6d77\u4eca\u5929\u7684\u5929\u6c14\u3002",
  "\u7ed9\u51fa2\u5f20\u4e03\u9f99\u73e0\u91cc\u7684\u56fe\u753b\u3002",
  "\u7ed9\u51fa\u4eca\u5929\u7684\u79d1\u6280\u65b0\u95fb\u3002"
]
```

## Changes

- Reproject all tool batches before each model round, sharing a 16,000-character
  excerpt budget (160-character minimum per item). This is not a hard total
  request size cap: URLs, media, conflicts and metadata remain additional.
- Select original passages relevant to the question; retain original results for
  local integrity and citation checks. Explicitly label excerpts as partial.
- Deduplicate unchanged evidence independently of retrieval time, rank and fetch
  transport. Preserve new content revisions, publication dates and contradictions.
- Use the existing CommonMark parser for citation validation. Recognize reference
  links, angle-wrapped URLs and balanced parentheses; code examples are not citations.
- Reuse equivalent unfocused page reads only within the same model request.
- Compile cache query/get results through the same evidence pack and mark their
  stored freshness. Cache metadata/status operations retain their existing behavior.
- Expose model-selected `web_weather`, validating country, first-level region and
  provider-local forecast date. Do not route by benchmark text or guess coordinates.
- Allow model-selected `web_search(read_pages=true, read_limit=1..4)` to read ranked
  HTTPS source pages concurrently in the same call. Page failures remain receipts;
  snippets are not relabeled as retrieved bodies. Existing cancellation stays active.
- Ask Codex to batch independent retrievals and avoid duplicating Desktop's image
  download/validation/delivery work. Image editing and explicit file output remain supported.
- Reuse the learned-source catalog snapshot for 30 seconds instead of repeatedly
  scanning/decrypting it for every specialist query. An explicitly requested missing
  learned source forces a refresh. This does not cache search answers.
- Omit routing diagnostics from empty/failed search outputs sent to the model, while
  preserving status, errors and receipts. Full originals remain available locally.
- Preserve the requested image medium: a drawing request must not be satisfied by
  a figurine or merchandise photo. This is a model instruction, not a proven visual
  classifier; inspect actual delivered images before accepting a timing result.

The weather lookup uses the [Open-Meteo geocoding API](https://open-meteo.com/en/docs/geocoding-api)
and [forecast API](https://open-meteo.com/en/docs). The current values are weather-model
estimates, not station observations. Valid time is not claimed as publication time.
Before commercial distribution, review provider licensing, usage limits and deployment
configuration; the public free endpoint is not an availability guarantee.

## Measurements

Full completion is measured from the actual send click to the app's completed
state, not first token. Each prompt starts a new conversation with its model route
verified. No search cache clearing or synthetic cached answers are used. Tool cache
hits are recorded. UI sampling adds a small measurement interval. These small,
iterative samples do not establish stable p95 or performance across networks.
The phone wall clock was approximately 2.04-2.19 seconds ahead of the host. Use
host monotonic completion timing or within-device elapsed values; do not subtract
unaligned host and device epoch timestamps to infer delivery delays.

### First Development Iteration

Installed APK SHA-256: `b98111d1562870c66e90e2ca6bf095700f86f63333870d0a054a2663936a5350`.

| DeepSeek query | Full completion | Result |
| --- | ---: | --- |
| Zhuhai weather | 21.44 s | Missed target; multiple searches and page reads |
| Two Dragon Ball pictures | 7.09 s | Two images visible; uncached image search 0.783 s |
| Technology news | 51.90 s | Missed target; repeated ~11.5 s searches |

News reached 97,227 JSON characters in the final model request. `web_cache` still
returned 17,952 characters outside the evidence pack. This observation led to the
second iteration; it is not evidence that aggregate compression had fully succeeded.

The first image was reopened from conversation history, opened full screen and
saved through the UI. A new 18,152-byte JPEG appeared in `Download/GalaxySSI`.
This does not establish original-resolution availability for all search previews.

### Second Development Iteration

Installed APK SHA-256: `5e936d507277e454ace4a8c7d150d8f108d72610813a0c1162c299c37c524419`.

| DeepSeek query | Round 2 | Round 3 |
| --- | ---: | ---: |
| Zhuhai weather | 10.24 s | 9.42 s |
| Two Dragon Ball pictures | 9.06 s | 10.95 s |
| Technology news | 37.32 s | 62.68 s |

Weather used the dedicated tool and identified the correct region. The UI labeled
the result as a model estimate, not a station observation. One measured lookup
took 3.125 seconds, with 0.964 seconds for the first model round and 1.788 seconds
for final generation. Image search calls were uncached, around 0.65-0.87 seconds.

News still repeated searches. Round 2 reached 72,578 JSON characters in the final
request; round 3 reached 119,290. Empty searches retained large routing diagnostics,
and learned-source selection repeatedly took 2-4.8 seconds. This motivated the
catalog snapshot and diagnostic projection changes in the next iteration.

### Third Development Iteration

Installed APK SHA-256: `9ddb8696fc11e9532068ddd1b6522265b963b7f0accc7f6237d4cb1cdd31181c`.

| DeepSeek query | Round 4 | Acceptance |
| --- | ---: | --- |
| Zhuhai weather | 11.06 s | Slightly over target |
| Two Dragon Ball pictures | 5.04 s | Failed quality: second image was a figurine photo |
| Technology news | 50.30 s | Over target |

Do not count the 5.04-second image result as a pass. The first image was a drawing,
but the second was a Goku bicycle figurine. Correct character identity alone does
not satisfy the requested visual medium.

News used one parallel batch of two searches. One took 5.566 seconds; the other
took 22.116 seconds, including approximately 8 seconds of page-read tail latency.
The final normal request was 60,918 JSON characters (36,448 tool characters).
Generation took 8.718 seconds. Two invalid citations triggered the retained repair
path, which took another 14.145 seconds. These are different live evidence sets,
not a controlled same-input compression ratio. Citation validity is not by itself
proof that every news claim and date is semantically correct.

### Fourth Development Iteration

Installed APK SHA-256: `b057ad2c5394b37d70f5a90990b44f55765de1501e0ac40a3a68a1a001c85a48`.
Strengthened the image-medium instruction. Weather/news measurements above are
from their stated builds. Image-only repetitions:

| Round | Full completion | Visual acceptance |
| --- | ---: | --- |
| 5 | 10.04 s | Two correct Dragon Ball drawings displayed |
| 6 | 9.07 s | Failed: one preview unavailable; linked-image wrapper leaked as text |

Do not count round 6 as a successful under-10-second image response. It exposed a
separate rendering issue in `[![alt](image)](source)` parsing. The second preview
also failed after retry; its exact network failure was not established.

### Fifth Development Iteration

Installed APK SHA-256: `cd570921deecd348af1fb1e14a1e3d9eb1af3a4cc4827c0fe8ed858c3fe4504a`.
Installed package verification: versionName 1.1.101, versionCode 987.

Use the existing CommonMark AST to consume a pure linked-image wrapper as a whole
and retain its source as a regular link. Also exclude HTTP-only image candidates
without a discovered secure preview, matching the existing HTTPS-only image loader.
Do not relax transport security or claim this guarantees remote image availability.

Round 7: image task completed in 11.48 seconds. The screenshot at approximately
11.10 seconds already showed two correct, distinct Goku drawings and ordinary
source links, with no broken preview. The nested-link format itself is covered by
unit regression; this live response used separate source links. The notification
shade appeared after completion, so the last automatic snapshot is not an app
acceptance image; use `deepseek-images-r7-frame-0011.10.png` instead. Further UI
operation stopped. No additional weather/news runs were made on this final build;
the fifth iteration only changed image candidate presentation and linked-image parsing.

The user explicitly accepted round 7's image result: approximately 11.10 seconds
to both correct drawings being visible and 11.48 seconds to task completion. Mark
this observed image scenario as accepted, while retaining the original 10-second
target as historical context. This is not a stable p95 claim or acceptance of
unrelated weather, news or Codex cases.

## Infrastructure Observation

Before testing, Desktop health reported MQTT disconnected with zero active
subscriptions. Restarting Desktop did not resolve it. Two isolated diagnostic
connections, without any subscriptions or publications, received MQTT v5
`CONNACK Server busy` from `broker.emqx.io:8883`. Desktop logged `Server unavailable`.
Codex full MQTT end-to-end targets cannot be accepted while this persists.
No broker, pairing identity, proxy or account configuration was changed.

## Regression Checks

- First iteration: 46 Android tests passed and APK assembly succeeded.
- Desktop: 83 focused tests passed, including conversation threading, response
  policy, model-directed search, evidence verification and progress flow control.
- Second iteration: 34 focused Android tests passed and APK assembly succeeded.
- Third iteration: 88 focused Android tests passed and APK assembly succeeded.
- Fourth iteration: 88 focused Android tests passed and APK assembly succeeded.
- Repository checks and `git diff --check` passed after the fourth build.
- Fifth iteration: 118 focused Android tests passed and APK assembly succeeded,
  including 16 Markdown-image and 14 public-image-search tests.
- Final repository checks and `git diff --check` passed.

## Acceptance and Remaining Work

The targets are not all met. Weather is close to 10 seconds but not stable below it.
The user accepted the final observed image scenario at 11.48 seconds, with both
correct drawings visible by approximately 11.10 seconds. News remains above
30 seconds. Codex has no accepted end-to-end samples during this broker outage.

Next work should address source availability and slow page-read tails, decide when
news evidence is sufficient without omitting requested scope, and reduce citation
repair cost without disabling verification. The current excerpt budget is not a
total prompt-size cap. Image-medium instructions still need live quality checks.
Public-broker availability also requires a separate transport reliability decision;
no infrastructure or pairing migration was attempted here.

Raw, uncommitted artifacts: `build/reports/query-targets-20260912/` (UI snapshots,
timing JSON, latency events and filtered logcat). Prior Guangzhou reports are unchanged.

# Android Image Search Repair

Version: 1.1.75 (961). Device scope: S26U / SM-S9480 only.

## Observed Failure

The user's screenshot showed a request for pictures of a named fish. The reply
contained a fallback list of ordinary search-result pages, including a public
image-search page, rather than image blocks. The previous 1.1.72 probes separately
established that readable-page fetching worked but image lookup did not. A search
engine catalog entry and a webpage link are not a deliverable image.

## Changes

- Add a direct public Sogou Images adapter. Parse the server-rendered JSON with
  Jsoup and JSONObject; never execute page scripts or call the restricted search
  API. Only whitelisted title, source page, image URL, thumbnail and dimensions
  enter the evidence pipeline. Challenges/schema errors fail explicitly.
- Image-only routing uses adapters that return actual image records, not generic
  web engines or site-scoped catalog placeholders. Existing Brave (when configured)
  and DuckDuckGo image adapters remain available.
- Return early after enough image candidates arrive and cancel slower transports.
  Do not wait for the multi-domain requirements of factual research just to show
  a picture. The normal fast-profile safety bounds remain; no new fixed five-second
  timeout was added. The user clarified that five seconds was a speed expectation,
  not an instruction to truncate a task after five seconds.
- Expose web_image_search to direct cloud models with an image-specific contract:
  concise exact subject, relevant candidates, Markdown images and their source
  pages. Avoid fetching unrelated articles or expanding image lookup into research.
- Ask the model to discard irrelevant search results and discuss conflicts only
  when they affect the question. Keep the existing evidence/citation checks.
- Insecure original image addresses use a discovered HTTPS preview when available;
  do not disable transport security. Actual download/DNS validation remains in the
  existing image loader. Image preview, fullscreen and save UI are unchanged.
- Version the image-routing cache key to avoid reusing legacy link-only searches.
- Image-specific reranking emphasizes title overlap and specificity, not repeated
  keywords in article excerpts. Retrieve a wider candidate pool from the same
  response and prioritize different source pages before extra images from one page.
- Direct cloud image-search evidence promotes a discovered HTTPS search preview for
  display, keeping the original URL explicitly separate for original-resolution
  requests. This avoids unnecessarily downloading large originals or depending on
  broken source certificates. It does not bypass TLS validation and does not claim
  that a search preview is the original-resolution file.

## Acceptance

Unit tests cover structured parsing, escaped URLs, source/image separation,
duplicate images, invalid payloads, safe preview fallback, direct-source routing,
early completion and transport cancellation. The image tool must not inject a
fixed five-second timeout.

Opt-in S26U tests separately measure source acquisition and image decoding for
three public queries, then exercise the actual main-page task flow with the user's
original Chinese question and an already configured DeepSeek model. The UI test
uses a private test conversation and does not modify credentials or default model
selection. It requires a completed task, durable image-bearing answer and real
image loading, rejects exposed duplicate rich JSON, and captures the resulting
screen. The final test also clicks Save and compares the resulting Downloads file
with the actual loaded image bytes. It leaves that deliberately saved test image
in Downloads/GalaxySSI rather than deleting any user files.

## Intermediate 1.1.73 Results

101 targeted JVM tests passed. S26U source probes, without application search-cache
reuse, returned title-matching downloadable image candidates:

| Query | Source acquisition | Image loading | Decoded dimensions |
| --- | --- | --- | --- |
| Chinese named-fish query from the screenshot | 638 ms | 197 ms | 499 x 294 |
| Chinese clownfish query | 454 ms | 482 ms | 500 x 250 |
| English clownfish query | 314 ms | 373 ms | 500 x 375 |

These are source/candidate checks, not independent visual species verification.
The named-fish query also returns recipe photos; the model must choose the requested
subject rather than indiscriminately presenting all search hits.

The actual UI task returned image-bearing output and ended in 24,048 ms. Screenshot
review found a duplicate, exposed rich-gallery JSON block and unnecessary prose.
That fails the presentation-quality gate even though images loaded. The 1.1.74
follow-up aligns the general rich-output prompt with the image-search contract:
one to three relevant pictures for an unspecified count, concise captions, source
links, no unsolicited encyclopedia/recipe expansion and no duplicate rich JSON.
The UI test now explicitly rejects that exposed duplicate fence.

## Intermediate 1.1.74 Results

101 targeted JVM tests passed. Eight S26U WebView/image-rendering regression tests
passed, including synthetic-fixture fullscreen saving with byte equality. These
are separate from the live-search acceptance test.

The live model task completed in 17,302 ms with no duplicate rich JSON, but chose
recipe pictures. Download validation then rejected an original image because the
server certificate did not cover `s3.cdn.xiangha.com`. This is a failed quality
gate, not a successful search. No certificate validation was weakened. Version
1.1.75 adds the title-specific ranking, source diversity and preview presentation
policy above. The original source remains available, but is not assumed healthy.

Source latency, answer latency and actual image delivery are distinct metrics.
An early failure or an irrelevant image does not pass the task-quality gate.

## Final 1.1.75 Validation

Installed on S26U with an in-place update, preserving user data. No other phone was
operated. Build and 103 targeted JVM tests passed. The final nine-test device run
passed: one real DeepSeek main-page image task, four renderer tests and four
image-rendering regression tests. The separate live source test also passed.

| Query | Source acquisition (no App search cache) | Image loading | Dimensions |
| --- | --- | --- | --- |
| Chinese named-fish query | 480 ms | 4 ms (image cache hit possible) | 295 x 221 |
| Chinese clownfish | 628 ms | 417 ms | 550 x 413 |
| English clownfish | 426 ms | 1,040 ms | 240 x 160 |

Two main-page runs of the original question completed in 25,678 ms and 20,231 ms.
Both returned actual images, without exposed gallery JSON or original-site TLS
errors. The final run verified a visible image, fullscreen Save and exact saved
bytes (`save_bytes_verified=true`). Its screenshot includes a whole-fish image
from the identity-related source, but the answer still mixes in food photographs
and unsolicited factual prose. These are not independent visual species checks.

A separate direct DeepSeek probe took 7,434 ms: tool start at 1,617 ms, completion
at 5,847 ms, and first answer text at 7,416 ms. It returned two Markdown images and
plain source URLs. Its strict Markdown-source-link assertion failed, so this
probe is NOT counted as a passed acceptance test and did not reach its final
image-download assertion. The raw report is retained. The difference from the
main-page timings is not an isolated measurement of UI overhead: model requests,
contexts, queries, caches and network conditions also differ.

### Remaining Work

- Semantic selection is improved, not solved: body-keyword stuffing has less
  ranking influence, but ambiguous/common names can still yield cooking pictures.
  Stronger selection must understand requested subject/form; a title match is not
  a visual correctness proof.
- Full main-page completion still takes around 20-26 seconds in these runs. Profile
  model planning, tool dispatch, evidence handling and final generation separately
  before attributing this entirely to networking or UI.
- Plain source URLs appear in some replies instead of the requested Markdown
  source links, and the model may add unwanted prose or extra images. A deterministic
  image delivery contract would be more reliable than prompting alone.
- Public-source availability can change. Preview delivery preserves TLS validation
  but does not prove the original-resolution URL is healthy.

### Evidence Files

Local files under `build/reports/` (generated, not committed):

- `s26u-image-search-before.png`
- `s26u-image-source-probes-1.1.75.json`
- `s26u-image-ui-1.1.75-first.json` and `.png`
- `s26u-image-ui-1.1.75-final.json` and `.png`
- `s26u-image-fullscreen-1.1.75-final.png`
- `s26u-image-final-1.1.75.log`
- `s26u-deepseek-image-1.1.75.json`
- `s26u-image-sources-and-deepseek-1.1.75.log`

No fixed five-second production cutoff was introduced, and no blanket latency or
image-correctness guarantee is inferred from these small live samples.

## 1.1.76 Direct Image Lookup

Historical experiment: the user rejected this model-bypass approach after finding
fast but irrelevant pictures. It is removed in 1.1.79. See
`ANDROID_MODEL_LOOP_LATENCY_20260911.md` for the restored model-led flow. Do not
treat the no-model timings below as current model-loop performance.

The previous 20-26 second UI path contained two or three model rounds and repeated
web searches. Literal requests such as `Give images of clownfish` now use the
existing public image-search tool directly, with deterministic Markdown images
and source links. The selected model is not called by this fast path. Comparison,
generation, analysis, private/contextual references and compound requests remain
on the model/tool loop. Attached-image requests and externally disabled tools do
not use the fast path. A failed search is not evidence of provider failure.

Search discloses only the extracted public query, not conversation history or
system instructions. The disclosure ledger records image-search sources separately;
blocked model destinations cannot be bypassed. Image downloads still require
HTTPS and the existing bounded transport; an HTTP source can appear as a clickable
citation without fetching it or weakening image TLS checks.

Two preparation changes also apply: current-conversation context and metrics use
the indexed conversation lookup instead of decrypting the whole conversation list;
search adapters use the raw bounded fetcher, while article reading retains dynamic
rendering. Automatic image search skips unrelated learned-source scans and reads
health records only for eligible/selected sources.

Source acquisition, first visible image and task completion must be reported
separately. The 200 ms App preparation and approximately one-second search numbers
are optimization targets, not hardcoded timeouts or achieved guarantees. Live
validation and subsequent refinements are recorded below; 1.1.75 remains the baseline.

## 1.1.76-1.1.77 Measurements

Literal lookup in the actual S26U main page completed in 3,881 ms on 1.1.76. A
second query took 8,882 ms, of which 6,864 ms preceded routing: startup catalog
and global-context warmups were sharing the ordered request executor. Version
1.1.77 moves those warmups and proactive-insight counting to the existing
navigation/background executor, preserving ordered request dispatch.

Version 1.1.77 passed 198 targeted JVM tests and 11 S26U tests (main-page lookup,
two direct-route/privacy tests, four renderer tests and four image-rendering
tests). The original main-page request completed in 2,748 ms; its first visible
image was observed at 2,528 ms. Fullscreen Save matched the image bytes. The
visible-image timing is a 100 ms polling upper bound, not a display-frame trace.

This is not a 200 ms preparation result. In that run, routing queue wait was
1 ms, indexed context loading 1 ms and routing through run-event persistence
191 ms, but click-to-cloud-dispatch was still 2,005 ms. Task-supervisor startup,
runtime initialization and durable execution stages remain in the critical path.
Checkpoint batching removes repeated writes but still persists the finalized
action and checkpoint before dispatch; crash recovery is not disabled for speed.

Direct image lookup is recorded as provider `web_image_search_direct`, not as a
DeepSeek model request. It does not update model-provider success/failure health,
trigger cross-model fallback, or relabel an already-connected model attempt.

### No Search-Cache Probe

The complete Android search-service probe explicitly passes `use_cache=false`
and asserts `cache.hit == false`. It includes service invocation and evidence
packing; the one-time service setup was 33 ms.

| Query | Full service | Winning source | Image load |
| --- | --- | --- | --- |
| Chinese named-fish query | 558 ms | 441 ms | 3 ms, cached image |
| Chinese clownfish | 679 ms | 561 ms | 0 ms, cached image |
| English clownfish | 486 ms | 398 ms | 0 ms, cached image |

These are fresh search requests, not fresh thumbnail downloads. An earlier
15-68 ms probe incorrectly passed `use_cache` through the model-tool argument
normalizer, which does not forward that field. Its report is retained as
`s26u-image-service-invalid-cache-probe-1.1.77.json` and is NOT cold-search evidence.
The corrected report is `s26u-image-service-uncached-1.1.77.json`.

### Failed Delivery Case And 1.1.78 Follow-Up

A new goldfish main-page query on 1.1.77 finished in 5,325 ms but returned a
thumbnail that responded HTTP 404. The strict device test failed; completion
alone is not a quality pass. Version 1.1.78 adds bounded concurrent candidate
loading through the existing App image store, delivers decoded images as they
become ready, skips failed candidates, and cancels unused transfers once the
requested count is ready. Search and loading share the existing deadline; no
fixed five-second fail-fast deadline was added.

Image transfer now registers cancellation with the actual HTTP call. A cached
image can be read before the per-key network lock, so it need not wait behind
another download. Public-address checks, TLS, redirect bounds, file-size limits
and image decoding remain enabled. Candidate captions identify the requested
query; they are not independent visual species verification.

A separate generic web-document downloader rejected a CDN response with no MIME
header. The App image pipeline decodes and validates those bytes and its
clownfish show/open/save test passed. The live image probe now uses that same App
pipeline. This does not claim the generic document downloader was changed.

## 1.1.78 Installation-First Check

At the user's request, installation took priority over the full repeat test run.
The initial build was stopped during a prolonged Kotlin compilation; it did not
produce new JVM or instrumentation pass results. The image loader was split into
smaller fetch/read helpers without removing transport cancellation or validation.
The subsequent `:app:assembleDebug` build passed in 8m 16s.

An in-place ADB installation on S26U succeeded. Package Manager reported
`versionName=1.1.78`, `versionCode=964`, updated at 2026-09-11 19:33:32 local time.
Startup returned `Status: ok`; the main process remained present, and a screenshot
showed the existing conversation with loaded images. No app data was cleared,
and no other phone was operated. Evidence: `s26u-installed-1.1.78.png`.

This startup screenshot is not a timed new-search test. The retained conversation
also illustrates a remaining relevance gap: a request for spaceship/interior
pictures has character-collage results. Literal query routing and successful
image decoding do not prove all subject/qualifier requirements were satisfied.
The failed goldfish case, new concurrent-loader tests, precise first-image timing
and full regression suite still need to be rerun against this installed build.
Neither a 200 ms preparation result nor one-second end-to-end display is claimed.

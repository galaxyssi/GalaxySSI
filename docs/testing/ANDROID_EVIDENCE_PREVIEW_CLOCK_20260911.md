# Android Evidence Projection, Citation Preview And Process Clock

## Scope

Android 1.1.84 (970), followed by the incremental-render fix in 1.1.85 (971), based
on merged PR #3007. No Desktop changes or chat color/layout redesign.
The original model-led web/image planning and dependent follow-up searches remain intact.

## Why A New Conversation Was Not An Empty Model Request

Controlled source message 2889 in the previous S26U run produced request bodies of
16524, 37174 and 61085 JSON characters across three model calls **within one user
question**. These are not three user conversations or an inherited chat transcript.
The Agent prompt was 1842 characters. The 1.1.84 S26U replay confirmed an initial
body of 16524 characters with one user message and no tool results: tool schemas
9109, system-message JSON 5440, and current task plus remaining serialization 1975.
Every initial request carries system policy, evidence/format instructions and tool
schemas. JSON character counts are not token counts. This change does not remove
or shorten the initial tool schemas or fixed system instructions.

`CloudModelClient.prepareConversationStream` compiles chat context before entering
the stream loop. This native Agent path supplies a temporary message with ID zero,
so `compileCloudContext` does not load the contact's persisted chat summary. The
subsequent streaming tool loop appends tool calls/results to its own conversation
array. Existing chat compaction does not automatically recompress that array on
each tool round. Its per-tool result bound was 24000 characters, not a cumulative
latency budget or an instruction to send only the current user question.

## Changes

- `CloudEvidencePromptLedger` is scoped to one model request owner. It projects
  each tool result before adding it to the model conversation. Exact duplicate
  evidence becomes a reference to an earlier result still present in that same
  request. Substantive changes, distinct source URLs and conflict information
  remain separate. It removes duplicate citation manifests, redundant image
  fields, empty optional fields and receipt durations only from the prompt view.
- Original results remain in the citation verifier/evidence store. Projection
  references never enter its authoritative input. The untrusted-evidence envelope
  and permission boundary remain unchanged. This is deterministic projection,
  not another LLM summarization request and not a universal context-window cap.
- Per-round payload telemetry reports total/conversation/tool schema/tool result/
  system message characters and user-turn counts, without prompt text or secrets.
- Per-call HTTP telemetry measures local reader dispatch, DNS, connection/TLS,
  request writing, response-header wait, first frame/text/tool and stream tail.
  Missing phases are `-1`; reused connections are explicit. Connection time
  includes TLS, so those two values must not be summed. Client telemetry cannot
  separate provider queueing from prefill or network transit.
- Main-page Agent replies opt into replaceable **citation previews**. Only
  complete paragraph prefixes that pass existing source-URL checks may appear.
  Unresolved Markdown, HTML, fenced code and internal protocol stay buffered.
  Previews bypass committed text accumulation, history and TTS. A repair/tool
  transition/failure retracts the preview; final replies still pass the complete
  citation check against original evidence. Direct voice/chat streams retain
  their existing default behavior and do not opt into these previews.
- Process clocks re-read the current turn's completion while visible and freeze
  once terminal. Stream/previews are not terminal responses. Conversation and
  turn identity prevent a new question or another window from stopping an older
  clock. Final reply changes invalidate the associated process group even when
  its visible reply text equals the previous streaming content.
- The first device replay exposed a visible rebinding flash. The transcript
  adapter removed every child on each update, causing identical images to decode
  again. In 1.1.85, passive reply blocks reuse their Views. Adjacent selectable
  paragraphs stay together; changed text updates in place; unchanged image/table
  blocks survive preview-to-final transitions. Speech controls refresh against
  the current accepted entry without replacing the content. Changed or retracted
  blocks are replaced/removed. Interactive forms, players, deferred large content
  and collapsible-section transitions retain the established full-binding path.

## Verification

### 1.1.84 Verified

- Android build succeeded; 120 targeted JVM tests passed; `npm run check` passed.
- Six S26U fixture tests passed: attached clock termination without rebinding,
  later-turn clock isolation, progress/voice-history regressions and controlled
  model-tool-model routing. Controlled HTTP fixtures are not live model results.
- One fresh private-conversation DeepSeek UI task passed image display, opening,
  and saved-byte verification. Actual model: `deepseek-v4-flash`, source 3003.
- Three tool results projected from 25937 to 18675 characters in aggregate (28.0%
  reduction before JSON string escaping). Final request size was 42424 characters.
  This is not a same-evidence comparison to the previous 61085-character request.
- Final model round: 2569 ms, first text at 1545 ms, first source-checked preview
  at 1915 ms, final citation verification 19 ms. The preview preceded accepted text
  by approximately 673 ms. No extra summarization model request was introduced.
- HTTP final-round telemetry: reused connection, request write 1 ms, response
  header wait 206 ms, headers-to-first-text 1331 ms, stream tail 1023 ms. These are
  client observations, not a measurement of provider compute time alone.
- UI task completion 12814 ms; first visible image 10208 ms. The initial image
  search hit cache (30 ms); web search was fresh (1468 ms), followed by a fresh
  image search (818 ms). This is one sample, not a latency percentile guarantee.
- The immediate completion screenshot still read processing; subsequent UI
  inspection showed the stable terminal label at 11 seconds. The live test now
  explicitly waits for the terminal clock and checks it remains frozen for 1200 ms.

### 1.1.85 Verified

- Expanded JVM suite: 145 passed. The final S26U regression suite passed 19/19
  tests against the installed 1.1.85 (971) production code; `npm run check` passed.
  The first S26U batch passed 18/19 tests, including
  all four new stable-render cases, process clocks, Markdown tables/images and
  output paragraph selection. The old rich showcase expected 20 top-level Views
  despite pre-existing section folding and selectable-paragraph grouping. Its
  uncollapsed component test now explicitly disables section folding, expects
  16 groups, and checks the combined text as well as every group's dimensions.
  Its temporary showcase is added as an overlay rather than replacing the
  Activity root, preserving startup prewarm bindings to existing controls.
- First live run (source 3170) failed image loading because
  `s3.cdn.xiangha.com` did not pass HTTPS hostname verification. No TLS validation
  was relaxed. This is retained as a failed external-image-source sample.
- Second live run (source 3179) passed image display/open/save and clock stability:
  task completion 8335 ms, first image 6489 ms, terminal clock 7 seconds. It still
  observed one image View replacement and two Drawable transitions, so that
  build did not yet meet the no-rebind acceptance criterion.
- The remaining cause was the six-block/long-answer threshold: a single final
  answer was moved into a new section container. The follow-up keeps that single
  answer in the same content container with equivalent padding. Genuine multi-
  section layouts keep their existing organization and full-binding fallback.
- The image fixture crosses the section threshold and final transition while
  asserting the same View/Drawable. Nested table actions (including expanded rows)
  also rebind to the accepted reply, not retain a preview action callback. These
  cases passed in the final 19-test suite.
- Live runs 3 and 4 completed model work but failed the clock inspection (a
  stability assertion and a missing visible clock label, respectively). Those
  fixtures had not pinned the viewport, and did not retain enough label evidence
  to distinguish a timer defect from an offscreen/recycled process row. They are
  not counted as passes. The fixture now disables auto-follow only after task
  completion for inspection, pins the top row, and records labels before asserting.
  Production scrolling behavior is unchanged.
- Final live run 5 (source 3203) passed a real DeepSeek request with four images:
  task completion 9002 ms, first image Drawable observed at 6271 ms, zero image
  View replacements and zero Drawable resets after first draw. The completed
  clock remained at 8 seconds after a further 1200 ms. Image display, fullscreen
  opening and saved-byte comparison passed. The screenshot was visually checked.
- Final model round in that sample: 2378 ms, first text at 1410 ms, first
  source-checked preview at 1661 ms. Two image-search results projected from
  15738 to 10858 characters in aggregate (31.0% reduction before JSON escaping).
  Final request size was 31687 characters. This is one sample with different
  results from earlier runs, not a controlled end-to-end speedup comparison.

Final local artifacts are in `build/reports/`:

- `s26u-evidence-stream-clock-1.1.85-verified-device-regressions.log`
- `s26u-evidence-stream-clock-1.1.85-live-run5.log`
- `s26u-evidence-stream-clock-1.1.85-run5.json`
- `s26u-evidence-stream-clock-1.1.85-verified.png`
- `s26u-evidence-stream-clock-1.1.85-final-latency.log`

External image-source TLS failures remain a separate reliability issue; no
certificate checks were weakened. Initial tool schemas/system instructions have
not been shortened. Genuine multi-section layouts retain the full-binding
fallback, so the passing single-answer sample is not a claim that every possible
rich layout is free of redraws.

The image UI test exercises a real DeepSeek request and verifies image
display/open/save. Such transport/display checks do not establish semantic image
accuracy or a production latency percentile. Citation checks prove allowed source
correlation, not factual correctness of every generated sentence or image caption.

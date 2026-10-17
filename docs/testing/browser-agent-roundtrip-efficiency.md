# Phone Browser Agent Round-Trip Efficiency

## Scope

This change reduces unnecessary browser/model round trips. It does not impose a
search-count cap, change the user's model or reasoning effort, bypass TLS, move
phone execution to Desktop, or change ASR/QNN.

The S26U diagnostic on 2026-10-17 found 36 planner tasks using 36 provider threads
for one phone goal. A sampled navigate-to-readable-page cycle took 61.06 seconds:
14.113 s navigation, 5.568 s phone persistence/request preparation, 4.850 s uplink,
6.470 s Desktop submission, 14.714 s model response, 10.349 s return/scheduling,
and 4.996 s explicit observation. These are one observed cycle, not percentiles.
Private images, prompts, logs and device identifiers are not included in this PR.

## Behavior

- `navigate` and `back` return a fresh bounded page observation with text, links,
  controls and revision. Navigation errors preserve their error and may also
  return readable partial content; they never claim business success.
- Terminal `operation_status` returns a fresh observation when the original live
  session/page is available. Running/unknown receipts do not imply a safe retry.
  Receipts continue to store metadata only, never DOM, cookies or form values.
- Phone planner history is scoped by authenticated client route, scoped
  conversation/agent instance, original client turn and selected model. A new
  task still has its own task/turn lifecycle. Active ordinary chats are not
  steered. Missing identity, screen-analysis and experimental paths retain their
  existing behavior.
- Confirmed submissions retain only hashes of prompt chunks and image content.
  Subsequent turns omit an unchanged line-aligned prefix and already-submitted
  images. Changed content, different goals, expiration, eviction, process restart,
  provider context compaction or a lost thread cause full input to be sent again.
  Hashing never holds the App Server state lock. Cache receipts expire after
  600 seconds and are bounded to 128 threads.
- The phone tool contract tells the model to use returned evidence directly and
  batch independent sources. It still chooses sources and decides when evidence
  is sufficient. No site-specific answer or search route is hard-coded.

Repeated phone-to-Desktop attachment transport is **not** removed by this change:
only repeated provider image submission is deduplicated. Transport reuse needs a
separate acknowledged remote-cache protocol so an image is never silently lost.

## Validation

- Browser integration tests run actual Chromium against an HTTP fixture, covering
  inline navigate/back observations, partial document timeout, link redaction,
  authentication isolation, stale controls, cancellation and operation recovery.
- Python tests cover planner identity isolation, actual MQTT dispatch into the
  scoped planner history, incremental input, image-content hashing, provider
  thread loss, context compaction, cache lifetime and unchanged ordinary chat.
- Android tests cover the tool contract and supervised project loop. The opt-in
  device probe `AgentInteractiveBrowserDeviceTest#installedBrowserLaunchesAndReadsAPublicPageOnThePhone`
  launches the installed phone Chromium, verifies HTTPS, opens `example.com`,
  and checks that another navigation itself returns the rendered page body.

The browser fixture is not a public-network latency benchmark. End-to-end model
latency and task completion still depend on the selected provider and website.

## Recorded Validation (2026-10-17)

- 86 browser tests passed with real desktop Chromium enabled.
- 230 Codex backend tests passed; focused MQTT planner dispatch tests also passed.
- Final focused Android rerun passed 32/32 browser adapter and prompt-template
  tests, including inline success/error evidence and conditional browser guidance.
- Android debug APK and instrumentation APK built. The extended Android suite
  passed 232/235 tests. Three existing prompt-budget/evidence tests remain failing
  in `AgentSupervisedProjectPromptTest`: planning prefix (8,880 versus 5,800
  characters), compact contract budget, and newest-evidence retention in a large
  continuation. Their tool inventories contain no interactive browser, so the
  new conditional browser paragraph is absent. Do not treat this run as green.
- On S26U with Android 1.5.43, the public-page instrumentation probe passed:
  cold runtime/browser readiness 37.818 s, first page 19.309 s, subsequent
  navigation plus inline readable observation 2.796 s. TLS remained enabled.
- Two real Codex public-text turns reused one provider thread. The second input
  omitted a previously supplied checksum, and the model correctly recalled it.
  Observed turn durations were 8.172 s and 2.516 s. This is a context-retention
  probe, not a controlled before/after benchmark or an image-search completion.
- Desktop 1.5.1 was started from source and passed its backend health check.

Device logs and test prompts stay in local diagnostic artifacts, outside Git.

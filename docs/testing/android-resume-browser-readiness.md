# Android resume and browser readiness regression

## Failure modes

- Foreground restoration previously ran `reloadSession` on the main thread.
  A real S26U trace recorded a 30,503 ms wait in the session restoration stage.
- Loop event deduplication decrypted every event in a run while holding the
  shared ledger monitor. UI recovery and MQTT receipt lookup waited behind it.
- Browser availability checked the execution backend but not all browser packs.
  An arbitrary exit code 127 was incorrectly classified as missing packages.
- S26U still had linux-base 1.1.0 and the published browser 1.61.0 pack used
  `signalasi-browser`. The renamed client only searched for `galaxyssi-browser`.
- The published image omitted NSS modules loaded with `dlopen`, including
  `libsoftokn3.so`. A local DOM worked but HTTPS initialization crashed Chromium.
  Its Fontconfig file also pointed to system directories instead of relocated
  pack fonts, producing zero-height text and empty `innerText`.

## Implementation boundaries

- Foreground restoration runs on the navigation executor. Requests coalesce,
  and pause, destruction, plaintext clearing, or conversation changes invalidate
  stale delivery. A newer rendered response takes precedence over a reload.
- New loop events use a deterministic run/turn/revision idempotency key. Old events
  use the run/timestamp index and validate the decrypted turn and revision.
  No whole-run decryption or eager event migration is required for deduplication.
  JSON round-trips preserve nested arrays/nulls and compare numeric values rather
  than JVM Int/Long widths without losing large-integer precision.
- Ledger reads no longer acquire the writer monitor. WAL permits receipt and
  snapshot reads alongside writes; sequence allocation and writes remain atomic.
  Root state and its last event are read in one joined query.
- Browser tools check linux-base, node-js and browser-automation state and
  capabilities. Guest preflight distinguishes missing executables, incorrect
  PATH and failed Node startup. Unknown mutation outcomes retain reconciliation.
- Installing Linux, browser or Node packs, when all dependencies are ready, invokes
  a real Chromium launch, visible-text probe and offline loopback TLS initialization
  check. Linux versions older than 1.3.9 cannot bypass catalog upgrade resolution.
  Both published and renamed launchers are recognized. Installation remains recorded even
  when startup fails. The result instructs the agent to continue its original
  task, not to treat the local probe as a successful website query.
- Missing NSS modules are reported as specific native dependencies, with a Linux
  package repair path. TLS verification is never disabled. Pack fonts are referenced
  through a small private generated Fontconfig file, without editing signed images.
- The browser image recipe advances the runtime revision to 1.61.1 while retaining
  Playwright 1.61.0, includes NSS dynamic modules and their dependencies, and fixes
  relocated font paths. Image validation rejects missing NSS modules. Publishing
  the rebuilt signed pack remains a release step; a code change is not proof that
  an existing downloaded image has been replaced.
- Message encryption, background plaintext clearing, guest isolation, signed
  packs and browser operation receipts are unchanged.

## Regression entry points

- JVM: `AgentForegroundReloadTest`, `AgentBrowserRuntimeReadinessTest`,
  `AgentInteractiveBrowserToolsTest`, `AgentExecutionLoopTimelineTest`,
  `AgentRunKernelContractTest`.
- Node: `browser-runtime-readiness.test.cjs`, `browser-session-engine.test.cjs`,
  `browser-session-cli.test.cjs` under `tools/runtime`.
- Device: `AgentResumeLedgerDeviceTest` uses isolated fixture databases. It checks
  reads during writer contention, legacy revision lookup, atomic replays, the
  SQL query plan, and migration from database version 2 to 3.
- Device: `AgentForegroundReloadDeviceTest` holds the real Agent monitor while
  scheduling a foreground reload; the UI must process its next callback within
  500 ms. It does not create messages, clear data or change the active session.
- Device: `AgentInteractiveBrowserDeviceTest#installedBrowserLaunchesAndReadsAPublicPageOnThePhone`,
  with instrumentation argument `browser_runtime_probe=true`, starts Chromium,
  verifies a local DOM, reads `https://example.com`, and closes the test session.
  This is browser/runtime integration evidence, not a real-model task completion
  or website login acceptance test.
- UI: return from Proactive Attention while a response is active; repeat
  foreground/background transitions and conversation switches. Check the
  `GalaxySSIStartup` resume stage timings and new crash/ANR records. Do not clear
  production app data or existing conversations to make a test pass.

## S26U acceptance (2026-10-17)

- Android 1.5.41 (1324), installed in place without resetting data or pairings.
- 161 targeted JVM tests passed; 89 Node tests passed and 3 Windows symlink
  tests were skipped. All 5 targeted device tests passed.
- The device browser test verified local visible text, offline TLS initialization,
  and the title plus visible body of a public HTTPS page. It took 54.665 seconds
  including cold runtime preparation and cleanup, not a browser speed benchmark.
- Cold Activity launch: 809 ms. Returning from Proactive Attention: onResume
  60 ms, asynchronous restoration 334 ms. Home/foreground: onResume 12 ms,
  asynchronous restoration 229 ms. These individual samples are not percentiles.
- No crash/ANR followed the final installation during acceptance. An earlier
  debug broadcast exceeded Android's receiver deadline; subsequent acceptance
  used instrumentation. Do not confuse that harness ANR with UI-return evidence.
- The existing signed browser image was not replaced. Its missing NSS dependencies
  were installed in persistent Linux using Debian's libnss3/libnspr4 packages;
  the client supplied the relocated-font configuration. Rebuilt-image publication
  and authenticated website/model-goal acceptance remain separate work.

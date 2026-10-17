# Android resume and browser readiness regression

## Failure modes

- Foreground restoration previously ran `reloadSession` on the main thread.
  A real S26U trace recorded a 30,503 ms wait in the session restoration stage.
- Loop event deduplication decrypted every event in a run while holding the
  shared ledger monitor. UI recovery and MQTT receipt lookup waited behind it.
- Browser availability checked the execution backend but not all browser packs.
  An arbitrary exit code 127 was incorrectly classified as missing packages.

## Implementation boundaries

- Foreground restoration runs on the navigation executor. Requests coalesce,
  and pause, destruction, plaintext clearing, or conversation changes invalidate
  stale delivery. A newer rendered response takes precedence over a reload.
- New loop events use a deterministic run/turn/revision idempotency key. Old events
  use the run/timestamp index and validate the decrypted turn and revision.
  No whole-run decryption or eager event migration is required for deduplication.
- Ledger reads no longer acquire the writer monitor. WAL permits receipt and
  snapshot reads alongside writes; sequence allocation and writes remain atomic.
  Root state and its last event are read in one joined query.
- Browser tools check linux-base, node-js and browser-automation state and
  capabilities. Guest preflight distinguishes missing executables, incorrect
  PATH and failed Node startup. Unknown mutation outcomes retain reconciliation.
- Installing the browser or Node pack, when all dependencies are ready, invokes
  a real Chromium launch and local DOM probe. Installation remains recorded even
  when startup fails. The result instructs the agent to continue its original
  task, not to treat the local probe as a successful website query.
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
- Device: `AgentInteractiveBrowserDeviceTest#installedBrowserLaunchesAndReadsAPublicPageOnThePhone`,
  with instrumentation argument `browser_runtime_probe=true`, starts Chromium,
  verifies a local DOM, reads `https://example.com`, and closes the test session.
  This is browser/runtime integration evidence, not a real-model task completion
  or website login acceptance test.
- UI: return from Proactive Attention while a response is active; repeat
  foreground/background transitions and conversation switches. Check the
  `GalaxySSIStartup` resume stage timings and new crash/ANR records. Do not clear
  production app data or existing conversations to make a test pass.

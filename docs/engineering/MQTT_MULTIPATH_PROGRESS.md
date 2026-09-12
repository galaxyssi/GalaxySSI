# Multi-Broker Implementation Progress

Branch: `feat/automatic-multi-broker-20260912`

Base: `2c4a76415` (latest origin/main when this worktree was created).

The goal remains the complete Android + Desktop specification, including real
pairing, task delivery, attachments, recovery, diagnostics, performance evidence,
version updates, and a PR. This record is not a reduced P0 scope or completion claim.

## Implemented Foundations

- Shared generated broker catalog, no default or manual selection configuration.
- Android and Python scheduling policies: authenticated common-path selection,
  adaptive hedges, critical races, chunk load balancing, global/per-peer budgets,
  metric expiry, network change invalidation, and physical-versus-peer receipts.
- Android and Python independent Paho connection pools: per-path TLS, generations,
  reconnect backoff, exact subscription replay, partial/missing SUBACK handling,
  bounded publish registration, stale-callback rejection, and orderly close.
- Capability schema and canonical digest on both endpoints, rejecting legacy or
  partial single-broker capability announcements.
- Desktop durable per-pair local/remote route epochs in Link delivery metadata.
- Android route-state implementation sharing the Link inbox database; application
  and instrumentation Kotlin compilation passed, followed by six S26U persistence
  tests in the isolated verification package.

## Important Activation Boundary

The new connection pools and scheduling policies are not yet connected to `GalaxySSIMqttClient.connect`
or `mqtt_bridge.start`. Installed applications are unchanged. Existing entry
points still use the old single-client implementation until the coordinated
protocol and durable-delivery integration is complete.

Do not claim automatic fallback, hedging, or striping in the shipping application
on the basis of these isolated modules passing their tests.

## Integrated Ingress Hardening

- Android's actual `messageArrived` now uses one bounded, fair four-worker pool,
  not a permanent executor per Topic. Admission counts retained active payloads;
  rejected admission never sends a peer delivery receipt. Idle lanes are removed
  and idle worker threads exit. There is no Activity/window ownership.
- Subscription reconciliation builds an immutable Topic-to-Signal-identity map
  from configured Desktop/phone relationships. Topic rotation and concurrent
  Broker copies serialize on the same identity. Unknown or ambiguous aliases do
  not allocate a queue. Phone bindings are built in one scan, not one lookup per
  Topic. The obsolete Topic-only worker-scope helper and its test were replaced.
- Desktop's existing `InboundRoutePool` now likewise keys by configured Signal
  identity, preventing different route aliases from racing one Signal session.
- Desktop verifies sender and recipient before durably binding immutable message
  content. `inbound_content_hashes` belongs to the existing Link delivery database
  and stores only hashes, not a new task ledger or plaintext body. Conflicts are
  rejected before Blob persistence and dispatch, with privacy-safe diagnostics.
- Do not confuse this hash binding with durable full-message acceptance. It does
  not by itself fix the Desktop gap between Signal ciphertext binding, message
  storage, receipt emission, and downstream task creation. Desktop atomic receive
  remains a prerequisite for activating the three-path connection pools.

## Android Atomic Receive

- The real Desktop and phone ingress callbacks now commit Signal ratchet changes,
  the decrypted message body, immutable content binding, and verified-ciphertext
  replay binding in one SQLite transaction, before emitting a transport receipt.
  Commit rejection rolls back Signal state as well as the inbox, and is not
  misclassified as a reason to replace a phone's Signal session.
- Signal records moved from per-collection preferences JSON to encrypted individual
  rows in `galaxyssi_link_state_v3`. The inbox and route epochs share that database.
  The new installation format does not migrate old Signal preferences or old inbox
  claims. No current phone or Desktop user data is automatically deleted.
- Inbox keys bind authenticated pairing scope plus message ID, with SQL uniqueness
  and immutable-content checks. A completed record retains its replay tombstone;
  a pending record requires a readable durable body before any replay receipt.
- Bounded paging, eight-day completed-record retention, aggregate and per-peer
  quotas, and bounded alternate ciphertext bindings replace count-pruned global
  IDs. Accepted pending work is never evicted to admit new traffic. Transactional
  usage counters avoid scanning every retained record on each new message.
- Desktop and phone replay use their original handler and revalidate the current
  pair. Local pairing/Blob publication records are likewise pair-scoped. A bounded
  dispatch gate protects asynchronous work from concurrent fresh/replay dispatch.
- Attachment processing remains pending on missing/failed persistence. A foreground
  notification observer no longer completes a message before the foreground UI's
  asynchronous consumer commits it. Existing task/attachment stores remain the
  business idempotency boundary; inbox acceptance is not TASK_ACCEPTED or exactly
  once execution of arbitrary external effects.
- These changes are compiled, with host regressions passing. Real Android storage
  verification uses a separate, non-launchable package and the production Kotlin
  classes, not the production app identity. It is not full transport activation.
- S26U verification passed 29 tests: atomic inbox (17), durable route epochs (6),
  and sensitive-state regressions (6). Real libsignal ratchet/pre-key consumption
  rolled back with a failed inbox transaction, then the same ciphertext succeeded
  on retry. This is exception-injection verification, not a physical process-kill
  or reboot test. See [device report](../testing/MQTT_ATOMIC_INBOX_S26U_20260912.md).

## Verification So Far

- Python: 127 tests passed, covering broker pools/policy/route epochs, immutable
  content bindings (including three separate Python processes racing SQLite),
  existing Link delivery, bounded ingress, actual bridge dispatch/diagnostics,
  and phone-tool routing. Command from the Desktop backend directory:
  `python -m unittest test_inbound_content_binding test_mqtt_broker_pool test_mqtt_multipath_policy test_mqtt_route_state tests.test_link_delivery test_mqtt_inbound_pool tests.test_mqtt_link_diagnostics tests.test_mqtt_phone_tool_routing tests.test_link_transport_diagnostics -q`
  Runtime state for bridge imports was isolated with `GALAXYSSI_DATA_DIR` and
  `GALAXYSSI_STATE_DIR` under this worktree's ignored build directory. The routing
  fixture now supplies a fake Desktop display name instead of requiring a live
  Signal sidecar, and altered envelopes use a new immutable transport message ID.
- Android host JVM: 77 tests passed, including real Paho interface compilation,
  fake asynchronous connections, races, policy tests, cross-platform digest
  validation, bounded/fair ingress, concurrent broker callbacks, alias identity
  binding, canonical immutable hashes, async dispatch gate races, and cleanup
  after 10,000 historical peers. These are host tests, not
  real 10,000-peer network load. Command: `tools/dev/test-mqtt-multipath-host.ps1`.
- Catalog generation check passed: `python tools/generate_mqtt_catalog.py --check`.
- Five catalog-generation regression tests passed:
  `python -m unittest tools.test_generate_mqtt_catalog -q`.
- Total distinct executed host tests above: 209 (127 backend + 77 Android JVM + 5
  catalog). Re-running a test through Gradle is not counted as another distinct test.
- Full Gradle focused tests also passed: 66 tests, zero failures/errors:
  `GalaxySSILinkProtocolTest` (35), `MqttInboundRoutePoolTest` (13), and
  `MqttInboundBindingsTest` (5), `MqttImmutableContentTest` (7), and
  `MqttInboxDispatchGateTest` (6). These latter 31 overlap the host suite, so the
  combined distinct executed host test count is 244. Command from
  `apps/android`: `./gradlew.bat :app:testDebugUnitTest --tests com.galaxyssi.chat.MqttInboundRoutePoolTest --tests com.galaxyssi.chat.MqttInboundBindingsTest --tests com.galaxyssi.chat.GalaxySSILinkProtocolTest --tests com.galaxyssi.chat.MqttImmutableContentTest --tests com.galaxyssi.chat.MqttInboxDispatchGateTest -x :app:buildNativeMemory '-Pgalaxyssi.requireEmbeddedRuntime=false' --max-workers=2 --console=plain`.
- Low-volume real public loopback: one 75-byte synthetic packet on each available
  path, without app data or pairing keys. HiveMQ: connect 2516 ms, subscribed
  2907 ms, loopback 390 ms. Mosquitto: connect 3813 ms, subscribed 4188 ms,
  loopback 391 ms. EMQX returned CONNACK reason 136 and did not prevent the other
  paths from working. This is one local-exit smoke, not throughput, p95, or
  application delivery evidence.
- The smoke's generated report is under `build/reports/mqtt-multipath/`. A shutdown
  callback in the first report changes displayed final states to `closed`; the
  pre-close `snapshot` records the actual successful connections. The smoke script
  has since been fixed to preserve pre-close observations.
- Android `:app:compileDebugKotlin` passed in 4m 46s and
  `:app:compileDebugAndroidTestKotlin` passed in 8m 19s. Both excluded native memory
  generation and disabled embedded runtime packaging, for Kotlin/API validation
  only. No APK was produced by these compile checks. A subsequent pure-policy
  tracking-reservation adjustment was recompiled by the JVM host suite.
- Kotlin source-size policy and staged diff whitespace checks passed.
- The integrated Android ingress compiled with `:app:compileDebugKotlin` in
  3m 49s. Subsequent removal of the obsolete Topic-only helper is being checked
  by the full Gradle focused unit-test task, which passed in 6m 27s including
  recompilation of main and test Kotlin. This is not APK packaging or phone installation.
- Atomic receive: normal main compilation passed in 6m 23s, followed by normal
  instrumentation compilation plus 66 focused unit tests in 2m 57s. The final
  isolated package compiled the later quota/dispatch changes and built successfully
  in 13m 9s; S26U passed 29 selected tests. Combined distinct executed tests across
  the documented host/device suites are 273; this is not 273 end-to-end MQTT tests.

## Remaining Integration

1. Connect both pool implementations to the actual application-owned transport
   lifecycle; preserve one shared application/service owner across ten windows.
2. Complete authenticated resume request/response exchange and local capability
   refresh, including pairing bootstrap and app-to-app relationships. Announce
   only subscription-confirmed receiving paths; persist epochs before use.
3. Integrate generation-scoped physical attempts with the current publisher,
   outbox, receipt handlers, timing, subscription coordinator, and Run Kernel.
   Do not reset global business state when one path disconnects.
4. Complete immutable content binding and atomic durable acceptance before business
   side effects. Desktop immutable binding is integrated and tested, but
   `claim_message` still stores only IDs, and it is not atomic with persisted full
   envelopes/task handoff. Android now uses a shared Signal/inbox transaction;
   verify real native rollback and process-death recovery before activation.
   Outgoing receipts still require the planned authenticated content/scope binding
   and physical-attempt integration; moving the inbox is not that integration.
5. Define and integrate authenticated per-attempt/frame metadata and transport
   receipts. Account for frame overhead before current 512 KiB privacy buckets
   and chunk splitting; do not silently overflow existing direct-wire limits.
6. Add shared durable fragment/chunk bitmap acknowledgement, alternate-path
   retransmission, assembly validation, and final artifact handling. Current
   `signal-chunk` assembly is memory-only and must not be described as durable.
7. Bounded Android ingress and both endpoints' per-Signal-identity serialization
   are integrated. Continue evaluating aggregate limits and real-device latency
   when the full transport is activated; isolated 10,000-peer lane cleanup is not
   a claim of 10,000 simultaneous model tasks.
8. Read-only connection diagnostics, coalesced progress, prioritized final/control
   traffic, automatic internal rollback to one observed healthy common path.
9. Run integration/fault matrices on owned test brokers, then designated-device
   tests. The user designated S26U (SM-S9480, Android 16 / API 36). Do not operate
   SM-T575 or S20U for this goal. Isolated verification must not replace production
   app data; coordinated full installation and re-pairing remain separate steps.
10. Collect honest cold/warm latency, p50/p95, redundant traffic, background,
    recovery, and power evidence. Do not load-test public brokers.
11. Sync latest main before PR, bump Android/Desktop versions, compile full APK,
    and submit PR after required verification. No production APK installation,
    production uninstall, running Desktop replacement, or PR has occurred in this
    worktree yet. S26U's isolated verification packages were installed, tested,
    and removed; the new shipping transport is not installed. Local
    commits are development checkpoints, not complete-feature releases.

## Compatibility Decision

The user explicitly stated that this is development: they will uninstall and
reinstall the app and scan again. Build one new protocol across Android/Desktop;
do not add old-client capability fallback. This does not authorize silently
deleting their current app, chat history, or Desktop authorization records now.

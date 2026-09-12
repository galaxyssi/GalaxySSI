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
- Android route-state implementation sharing the existing Link inbox database;
  application and instrumentation Kotlin compilation passed. Six device
  persistence tests are implemented and compiled, but have not run on a phone.

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
  not fix the existing gap between Signal ciphertext binding, message storage,
  receipt emission, and downstream task creation; that remains the next safety
  prerequisite for activating the three-path connection pools.

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
- Android host JVM: 64 tests passed, including real Paho interface compilation,
  fake asynchronous connections, races, policy tests, cross-platform digest
  validation, bounded/fair ingress, concurrent broker callbacks, alias identity
  binding, and cleanup after 10,000 historical peers. These are host tests, not
  real 10,000-peer network load. Command: `tools/dev/test-mqtt-multipath-host.ps1`.
- Catalog generation check passed: `python tools/generate_mqtt_catalog.py --check`.
- Five catalog-generation regression tests passed:
  `python -m unittest tools.test_generate_mqtt_catalog -q`.
- Total distinct executed host tests above: 196 (127 backend + 64 Android JVM + 5
  catalog). Re-running a test through Gradle is not counted as another distinct test.
- Full Gradle focused tests also passed: 53 tests, zero failures/errors:
  `GalaxySSILinkProtocolTest` (35), `MqttInboundRoutePoolTest` (13), and
  `MqttInboundBindingsTest` (5). The latter 18 overlap the host suite, so the
  combined distinct executed test count is 231, not 249. Command from
  `apps/android`: `./gradlew.bat :app:testDebugUnitTest --tests com.galaxyssi.chat.MqttInboundRoutePoolTest --tests com.galaxyssi.chat.MqttInboundBindingsTest --tests com.galaxyssi.chat.GalaxySSILinkProtocolTest -x :app:buildNativeMemory '-Pgalaxyssi.requireEmbeddedRuntime=false' --max-workers=2 --console=plain`.
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

## Remaining Integration

1. Connect both pool implementations to the actual application-owned transport
   lifecycle; preserve one shared application/service owner across ten windows.
2. Complete authenticated resume request/response exchange and local capability
   refresh, including pairing bootstrap and app-to-app relationships. Announce
   only subscription-confirmed receiving paths; persist epochs before use.
3. Integrate generation-scoped physical attempts with the current publisher,
   outbox, receipt handlers, timing, subscription coordinator, and Run Kernel.
   Do not reset global business state when one path disconnects.
4. Add immutable content binding and atomic durable acceptance before business
   side effects. Desktop immutable binding is integrated and tested, but
   `claim_message` still stores only IDs, and it is not atomic with persisted full
   envelopes/task handoff. Android's count-pruned global inbox IDs and separate
   ciphertext writes require scoped, atomic durable acceptance. In particular,
   Android currently binds some ciphertexts before `stageIncoming`; a crash in
   that gap can make a replay incorrectly send a receipt for an unstored payload.
   This must be removed before multipath activation, not hidden by queue tests.
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
   tests. The user has not yet designated a phone for this goal's reinstall.
10. Collect honest cold/warm latency, p50/p95, redundant traffic, background,
    recovery, and power evidence. Do not load-test public brokers.
11. Sync latest main before PR, bump Android/Desktop versions, compile full APK,
    and submit PR after required verification. No APK installation, uninstall,
    running Desktop replacement, or PR has occurred in this worktree yet. Local
    commits are development checkpoints, not complete-feature releases.

## Compatibility Decision

The user explicitly stated that this is development: they will uninstall and
reinstall the app and scan again. Build one new protocol across Android/Desktop;
do not add old-client capability fallback. This does not authorize silently
deleting their current app, chat history, or Desktop authorization records now.

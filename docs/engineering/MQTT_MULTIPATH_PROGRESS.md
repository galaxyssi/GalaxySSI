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

The new pools and policies are not yet connected to `GalaxySSIMqttClient.connect`
or `mqtt_bridge.start`. Installed applications are unchanged. Existing entry
points still use the old single-client implementation until the coordinated
protocol and durable-delivery integration is complete.

Do not claim automatic fallback, hedging, or striping in the shipping application
on the basis of these isolated modules passing their tests.

## Verification So Far

- Python: 73 tests passed, comprising 61 new tests plus 12 existing Link delivery
  regression tests. Command from the Desktop backend directory:
  `python -m unittest test_mqtt_broker_pool test_mqtt_multipath_policy test_mqtt_route_state tests.test_link_delivery -q`
- Android host JVM: 46 tests passed, including real Paho interface compilation,
  fake asynchronous connections, races, policy tests, and cross-platform digest
  validation. Command: `tools/dev/test-mqtt-multipath-host.ps1`.
- Catalog generation check passed: `python tools/generate_mqtt_catalog.py --check`.
- Five catalog-generation regression tests passed:
  `python -m unittest tools.test_generate_mqtt_catalog -q`.
- Total executed host tests: 124 (73 backend + 46 Android JVM + 5 catalog).
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
   side effects. Existing Desktop `claim_message` stores only IDs; existing
   Android inbound/ciphertext stores need a scoped multi-path review. Duplicate
   ciphertexts must not concurrently advance the Signal ratchet.
5. Define and integrate authenticated per-attempt/frame metadata and transport
   receipts. Account for frame overhead before current 512 KiB privacy buckets
   and chunk splitting; do not silently overflow existing direct-wire limits.
6. Add shared durable fragment/chunk bitmap acknowledgement, alternate-path
   retransmission, assembly validation, and final artifact handling. Current
   `signal-chunk` assembly is memory-only and must not be described as durable.
7. Replace Android's current one-executor-per-route ingress map with bounded,
   per-relationship serialization. Desktop already has `InboundRoutePool`.
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

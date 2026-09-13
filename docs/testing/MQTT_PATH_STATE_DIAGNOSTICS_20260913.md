# MQTT Path State Diagnostics

This checkpoint adds truthful local path observations, not release acceptance.

## Implementation

- Android distinguishes disconnected, connecting, waiting for subscriptions,
  local receive subscriptions ready, retry backoff, and unavailable network.
- Desktop exposes equivalent local states, except that it does not claim an
  OS-level network-unavailable classification it does not observe.
- Receive readiness requires every currently desired exact subscription, not
  merely CONNECT or one SUBACK. It does not prove authenticated peer delivery.
- Per-path reconnect attempts are connection generations after the first attempt
  in this pool lifetime. They are not message retries or a persisted lifetime total.
- Pending publishes remain broker-acknowledgement observations, not RX_STORED.
- Android renders localized states and counters in the existing protocol
  diagnostics. Desktop exposes them in the existing loopback diagnostics JSON.
  No chat layout, background, input control, route or encryption policy changed.
- Snapshots contain no new peer/topic/message identifiers. No new timer or thread
  is introduced, and opening diagnostics does not start a connection.

## Verification

- Android host suite: **214 tests passed**, including initial connection,
  incomplete subscriptions, network loss, closed pools and path-isolated retry
  counts. Output: `build/mqtt-path-state-host-v1/tests.log`.
- Desktop pool/policy/diagnostic API selection: **68 tests passed**. The tests
  also verify that adding a second desired subscription withdraws receive-ready
  status until its acknowledgement. Desktop check: **44 tests and structure pass**.
- Android full Kotlin/resource compile: **BUILD SUCCESSFUL in 3m 1s**.
  Output: `build/mqtt-path-state-android-compile-v1.log`.
- Owned loopback TLS/native Signal regression: **20 business messages, three
  path-loss/restoration cycles, exit 0**. Both endpoint logs have zero bytes.
  Process death, held resume/receipt traffic and deferred dispatch are included.
  Final snapshots show receive-ready and real reconnection counts on all paths.
  Outputs: `build/mqtt-native-path-state-v1/report.json` and `last-snapshots.json`.

## Remaining Boundaries

S26U is absent; the connected SM-T575 was not operated. No APK installation,
Android visual acceptance, production Desktop restart or public broker load was
performed. The native run overlapped compilation/checks and is correctness
evidence only, not latency or power evidence. Desktop still uses its existing
raw diagnostics view; the complete human-readable throughput/retry presentation
and the full device/performance/acceptance backlog remain open. PR #3045 remains
the user's stop boundary.

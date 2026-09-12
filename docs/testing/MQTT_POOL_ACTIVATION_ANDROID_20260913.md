# Android Pool Activation Checkpoint

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.
This is a development checkpoint, not complete feature acceptance or a release.

## Actual Application Integration

- `GalaxySSIMqttClient` owns one `MqttPoolTransport` and `MqttPeerRoutes` across
  activities. The obsolete global single-client reconnect loop is removed.
- Paho clients, TLS, grants, generations, and physical receipts are path-local.
  Logical subscription/publication IDs cannot collide across native packet IDs.
  One physical failure does not clear other paths' pending receipts.
- Per-pair authenticated resume uses the existing outer AEAD, identity-scoped
  inbound executor, and durable `MqttRouteState`. An ACK must match the live
  local resume ID, integer epoch, digest, and current ingress generation.
- All receive-window aliases must be SUBACKed on one path. Split grants cannot
  create false readiness. Reconnecting a broker requires new local confirmation.
- QR and phone relationship bootstrap publications are explicitly classified
  by application code and attempted on fully subscribed paths. Their PUBACKs do
  not enter business-delivery registration. Approval and readiness are separate.
- Ordinary outbox messages wait for their own pair's readiness before consuming
  a delivery attempt. Bounded lookahead examines waiting rows without counting
  them as sends; deferred rows move behind already-due work. Bulk route wake-up
  reads the indexed retry date instead of the stale encrypted copy.
- Publish failure cannot become successful delivery through early or late callback
  ordering. Physical completion registration and its watchdog update together.
  A failed fragment releases only its transfer's tracking, not every other path.
- Desired subscriptions survive aggregate disconnection. Revoked/expired aliases
  are removed even if their first SUBACK never arrived. Registry reconciliation
  and subscription completion work use the existing background outbox executor.
- `MessageService` network loss pauses the shared pool. Network restoration wakes
  it; repeated capability callbacks do not create three additional retry loops.
- No chat background, input icons, message layout, or agent execution UI changed.

## Host Evidence

- Pure JVM suite: **126 tests passed**, zero failures, 4.675 seconds.
  Log: `build/mqtt-android-pool-host-close/tests.log`.
  Command: `tools/dev/test-mqtt-multipath-host.ps1` with the configured JDK.
- Normal Android Gradle compilation and focused unit suite passed in 3m 21s:
  **123 tests**, zero failures/errors, from seven suites. Log:
  `build/mqtt-android-pool-app-tests-final.log`.
  `GalaxySSILinkProtocolTest`: 35; pool: 14; multipath policy: 24; peer routes: 13;
  pool transport: 12; publish guard: 23; subscription coordinator: 2.
  The later close-timeout regression is covered by the final pure JVM suite.
- These runs overlap by 86 tests, so they represent **163 distinct host tests**,
  not 249 independent tests or 163 phone end-to-end tasks.
- Coverage includes forged/stale ACKs, pair isolation, duplicate ACK/request
  handling, reconnect generations, approval gating, bounded subscription waiters,
  early failures, per-path repair, and offline startup/network return.
- A 10,000-entry fake-client test verifies bounded fair resume admission using
  three clients and fixed workers. It is not public broker load, real throughput,
  10,000 model tasks, or a measured phone performance claim.
- Catalog-generation and Kotlin source-size checks passed.
- Final normal `:app:compileDebugKotlin` passed in 1m 57s after restoring the
  shipping manifest and preferring a current phone contact over its stale pairing
  request, matching `phoneRoutesForIdentity`. Log:
  `build/mqtt-android-pool-final-compile.log`. Full App-to-App pairing, including
  that registry-selection path, remains an end-to-end acceptance item.

## S20U Verification

Designated device: S20U, `SM-G9880`, ADB serial `R5CN319CESA`.
Only this phone may be operated in this round. The earlier S26U report is
historical evidence, not acceptance on this device.

An isolated debug build completed using `tools/dev/mqtt-isolated/README.md`.
Its package has no launcher, application services, or model initialization.
Selected tests use synthetic identities, test-owned databases, and (only with
`publicMqttSmoke=true`) one small synthetic packet per available public broker.
No shipping APK, current chat data, real pairing key, or large payload is involved.
The first run completed 36 storage/security tests and reported successful
synthetic loopback on all three paths. Cleanup was initiated before the runner
finished its final close, terminating that run. It is **not** an `OK (37 tests)`
result. The original report is `build/mqtt-s20u-pool-device-v1.log`.

Inspection of the pinned Paho 1.2.5 implementation confirmed that a zero
disconnect completion timeout permits an unbounded wait. Cleanup now supplies
500 ms, with a host regression and explicit device close-duration assertion.
The rebuilt package completed **37 tests, zero failures**, in 30.058 seconds.
`build/mqtt-s20u-pool-device-v2.log` contains `OK (37 tests)` and the normal runner
completion code. Test counts: atomic inbox 17; route persistence 6; encrypted
outbox 7; security-sensitive state 6; opt-in public pool 1.

The completed public smoke recorded one synthetic packet on each path:

| Path | Cold Connection | Post-Subscribe Loopback |
| --- | ---: | ---: |
| EMQX | 1,213 ms | 251 ms |
| HiveMQ | 5,967 ms | 187 ms |
| Mosquitto | 20,020 ms | 194 ms |

Pool close completed in **1,530 ms**, under the test's five-second bound. This is
one successful close, not proof against every blocked native worker. These are
single-run observations, not p50/p95, app response latency, or a permanent broker
ranking. Slow connection establishment did not prevent the other paths' echo.

Artifacts:

- Successful isolated build: `build/mqtt-s20u-pool-isolated-build-v3.log`, 3m 35s.
- Retained APK directory: `build/artifacts/mqtt-s20u-pool-close/`.
- Target SHA-256: `4D5E93E7F6D6AF1D3F0D98029F41A746B70B770B9BC2209D2D92C5383382EA2D`.
- Instrumentation SHA-256: `AFB87359F2D324E8DCD18728AA1C2A9D0D5F878F97C2FEDAA37516BC32934E26`.
- Both test-owned packages were removed **after** runner completion. The existing
  `com.galaxyssi.chat.test` was preserved; production `com.galaxyssi.chat` remained
  absent. S26U and SM-T575 were not operated.
- Normal main/test manifests were regenerated without the isolated init script.
  Verified isolated APKs were removed from ordinary APK output paths after their
  retained copies were hash-checked, preventing confusion with a shipping build.

## Remaining Work

- Coordinated real QR pairing and bidirectional App/Desktop/App messages, user
  tasks and recovery, ten windows, diagnostics, and side-effect safety matrix.
- Physical publication currently submits one packet per token. Stable logical
  attempt metadata, authenticated content/scope-bound receipt timing, delayed
  hedges and critical races still require integration above this adapter.
- Existing `signal-chunk` assembly remains memory-only. Durable shared bitmaps,
  cross-path missing-chunk retransmission, and complete artifact validation remain.
- Bulk outbox fairness and route readiness still need large real-device profiles.
  Host registry scale does not establish CPU, PSS, latency, or power budgets.
- Pool shutdown under stalled native/Paho workers needs additional lifecycle
  testing before deployment; this checkpoint does not certify all close races.
- Full APK with embedded runtimes, Android/Desktop version bumps, latest-main
  integration, shipping installation and PR remain part of the original goal.

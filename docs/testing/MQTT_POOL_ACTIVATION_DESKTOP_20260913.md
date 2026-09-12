# Desktop Pool Activation Verification

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.

This is an intermediate development checkpoint, not product acceptance. No APK
was installed, no current Desktop was replaced, and no public-broker load test
was performed for this checkpoint. The designated next phone is S20U, SM-G9880,
serial `R5CN319CESA`; only ADB inventory was read.

## Scope

The production Desktop factory/lifecycle now creates `MqttPoolClient` with a
three-worker `BrokerPool` and authenticated per-pair `PeerRoutes`. Host tests
exercise the actual QR pairing handler, relationship AEAD, route epoch database,
ingress metadata propagation, resume request/ACK handlers, subscription callbacks,
and physical publication ownership. No new Signal/business message ledger is
introduced by the connection adapter.

The broker bus is deterministic and in-process. It simulates CONNACK, partial or
delayed SUBACK, native packet-ID collisions, PUBACK, disconnection, and reconnect
generations. Pairing and resume use the real cryptographic envelope and SQLite
metadata, with isolated test identities and data directories. The broader suite
also includes actual JVM sidecar process-restart tests.

## Coverage

| Area | Executed checks |
| --- | --- |
| Startup | All six broker startup orders; first common path; one path only |
| Readiness | No business readiness from CONNACK/PUBACK alone; all required subscriptions on one path |
| Pairing | Actual encrypted QR claim; preferred ingress reply; alternative healthy reply; deferred confirmation |
| Resume | Request ID/epoch/digest binding; no ACK storm; prompt common-path recovery |
| Authentication | Wrong pair key binding/fingerprints, corrupt AEAD, stale generations, unsolicited ACKs |
| Persistence | Monotonic epochs survive recreated endpoint; duplicate does not renew TTL |
| Failure | One broker fails without resetting other paths; all fail/recover; same broker reconnect needs fresh ACK |
| Revocation | Old peer object retired; queued old authentication rejected; invalid batch does not partially revoke |
| Ownership | Distinct logical IDs for colliding native MIDs; early PUBACK; bounded global slots; slow close fencing |
| Scale | 10,000 configured peer states with bounded fair admission through refreshes, no per-peer threads |
| Hot path | Subscription callbacks avoid registry scans; indexed ingress still rechecks revocation |

The focused modules are `test_mqtt_pool_client`, `test_mqtt_peer_routes`,
`test_mqtt_pool_pairing`, and `test_mqtt_broker_pool` (65 cases). They are included
in the broader 418-case regression run, not added to it a second time.

## Results

- Final run: **418 passed**, zero failures/errors, **50.567 seconds**.
- Log: `build/mqtt-pool-final-v4.log` (isolated local generated output).
- Actual JVM receive-handoff recovery passed both process-death windows without
  a second Signal decrypt.
- Isolated JVM restart observation: 3906 ms, health-read maximum 0.153 ms,
  identity preserved. These are single-run observations, not p50/p95 evidence.
- Shared generated broker catalog check and Git whitespace checks passed.

Expected injected-failure warnings are not evidence of live public broker failures.

Use the repository's Python environment, a fresh `GALAXYSSI_DATA_DIR`, and the
same directory for `GALAXYSSI_STATE_DIR`; run from
`apps/desktop/core/galaxyssi-link/backend`. The broader suite covers the four
focused modules, existing subscription/pairing/transport/durable-delivery tests,
Signal receive/handoff/dispatch, Blob ingress, phone tool routing, task recovery,
and both live JVM receive/recovery modules. The full command and output remain
in the local execution record. This is not a benchmark/p95 result.

## Not Yet Verified or Finished

- Android application lifecycle activation and actual S20U-to-Desktop resume.
- App-to-App new-protocol pairing and route exchange.
- Logical-message hedges/races above the physical adapter; stable attempt/hash
  bindings in outgoing authenticated peer receipts and delivery metrics.
- Durable wire chunk bitmap acknowledgement, cross-path missing-block retries,
  and complete image/file/video transfer through the app UI.
- Complete external-side-effect/cancel recovery, completed inbox body compaction.
- Real authorized-broker fault/performance matrices, weak network, Doze,
  multi-window tasks, and repeatable power measurements.
- Version updates, full APK packaging, coordinated installation/re-pairing, PR.

Existing installed endpoints do not implement this completed coordinated
protocol. Do not deploy this checkpoint alone and present it as ready for
ordinary scanning/chatting.

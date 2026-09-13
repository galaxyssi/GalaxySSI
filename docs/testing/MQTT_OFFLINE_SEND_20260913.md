# Desktop Offline Send And Receipt Projection

Date: 2026-09-13. This is a bounded checkpoint, not full multi-broker acceptance.

## Production Changes

The direct-contact send entry no longer rejects an authorized peer solely
because the pool is absent or all three connections are offline. Validation,
pairing, Signal and outer encryption remain unchanged. The existing publisher
persists ciphertext and the existing retry worker owns recovery.

An accepted enqueue is shown as queued, not delivered. Exact authenticated
RX_STORED proof now projects a text card's delivered state before retiring
its durable outbox row. SQLite FULL durability is used for the chat store.
Projection failure leaves the retry record; retrying the projection is
idempotent. These are ordered commits across two databases, not an atomic
distributed transaction. A crash before durable enqueue/API success still
does not constitute an accepted send.

Attachment cards retain their stronger all-files-receipted projection.
A message receipt alone cannot complete a file transfer. Task completion
remains a separate state. Deleted history is not resurrected, wrong peer
scope is rejected, and read/delivered text state cannot be downgraded by
late enqueue responses or renderer updates. No chat layout was changed.

## Executed Tests

| Scope | Result | Evidence |
| --- | --- | --- |
| Backend regression | 185 passed, 75.035s | `build/mqtt-offline-peer-regression-v2.log` |
| Desktop renderer/structure | 37 passed, structure OK | `build/mqtt-desktop-ui-1.1.51.log` |
| Native owned TLS business/recovery | Nine messages, delayed ACK, replay, broker loss and process recovery passed | `build/mqtt-owned-offline-entry-v3/report.json` |
| Actual Desktop-to-phone send entry, offline | API accepts and persists native ciphertext; queued card and ID survive actual process death | Same report, separate final scenario |

The final owned run has empty left/right endpoint error logs. No model or
public broker was used for fault injection. Native controller timings include
RPC and storage polling; they are not phone latency or p95 measurements.

Two earlier test runs failed for harness assumptions: the first attempted to
deliver Desktop-to-phone payloads to a Desktop receiver, whose target check
correctly rejected them. The second snapshot tried to unseal the intentionally
empty remote-message ID on an outbound row. Neither production check was
weakened. The offline send-entry scenario intentionally stops before phone
delivery, and the snapshot now reads remote IDs only for inbound rows.

For reproduction, add `--offline-peer-entry` to the native command in
[the lab README](../../tools/testing/mqtt_owned_lab/README.md), optionally with
`--delay-resume`. The regular nine-message suite still uses the original
Desktop-directed payloads; it is not a substitute for Android business tests.

## Remaining Acceptance

The new coordinated App 1.1.114 / Desktop 1.1.51 deployment is recorded in
[the deployment report](MQTT_DEPLOYMENT_S20U_20260913.md). User QR scan and
real S20U bidirectional text, image/file/video receipt and open/save checks
remain pending, as do the full owned performance/chaos, ten-window lifecycle,
App/App and power matrix. Other proactive/diagnostic send entry gates and
legacy attachment status projection still require end-to-end audit. The full
development goal and PR remain open.

# Reliable Agent delivery regression

## Incident and evidence

On S26U, a worksheet attachment was acknowledged as stored, but its subsequent
Agent request exhausted six transport attempts. The Desktop inbound ledger had
no matching request, and no corresponding model task existed. The Android
transcript displayed a delivery error while its process row kept counting.
Desktop logs also contained transport probe and keepalive failures. These logs
do not establish which individual network/broker hop lost the request.

## Changes

- Retain the original Signal ciphertext and message/task identifiers for eligible
  paired Desktop Agent requests after the initial retry budget is exhausted.
- Allow at most six additional retries, with a 60-second recovery delay and a
  15-minute age bound measured from the first publish attempt, not file upload.
  Recheck expiry immediately before dispatch after a delayed wake.
- Request authenticated observation of the original task through the existing
  recovery coordinator. A query timeout is not treated as proof of non-execution.
- Do not retry before reply subscriptions are ready or fall back to an obsolete
  mailbox after its contact route disappears. Received/terminal requests are not
  resent. Unknown, superseded, unpaired, or local-only bindings cannot gain an
  extra recovery budget. Attachment transfer retry policy is unchanged.
- A final missing confirmation stops local execution without another model call
  or automatic replan. Persist this state so restart does not re-dispatch it.
- Include same-turn delivery errors in the process-row render signature, stopping
  its timer and removing obsolete controls without changing unrelated rows.
- Desktop records that delivery receipts do not need receipts themselves, so
  replayed receipt ciphertext cannot create an ACK-of-ACK exchange.

Signal encryption, opaque MQTT envelopes, identity validation, pairing records,
application data, and original conversation contents remain intact.

Submission versions after integrating main: Android 1.1.6 (892), Desktop 1.1.11.
Earlier diagnostic builds used Android 1.1.5 (891) and Desktop 1.1.9.

## Verification

- Desktop: 52 tests passed across MQTT diagnostics, durable delivery, delivery
  storage, task/turn routing, and Agent recovery. Includes twelve retries of the
  same ciphertext without starting another task, and receipt replay suppression.
- Android JVM: 35 tests passed across transcript rendering and execution
  continuity. Includes invalidation of only the failing turn's process row.
- First device regression: 19/20 passed. The new failure-state persistence test
  exposed a missing session snapshot write; corrected before final acceptance.
- S26U real-model probe: text and PNG input both returned verified Codex replies
  through the configured encrypted MQTT path. Total 133.272 seconds. Both
  Desktop tasks completed at execution generation 1, taking 9.167 and 8.540
  seconds of model-task time respectively. The image reply read `2 + 2 = 4`.
- Original worksheet conversation revisited: timer stopped at 4m39s, no cancel
  button remained; the historical error text was preserved rather than rewritten.
- Final device regression and final installed build: pending final rerun.

Device suites: `AgentDeliveryRetryDeviceTest`,
`AgentConnectorFallbackRuntimeDeviceTest`, `AgentReceivedDeliveryDeviceTest`.
The first suite uses an isolated temporary encrypted SQLite database and checks
identity/ciphertext retention, bounds, database reopen, deletion, attachment
gating, unknown contacts, and delayed-wake expiry. No user database is cleared.

The opt-in `AgentDeliveryLiveDeviceTest` requires `live_delivery=true` and checks
the SM-S9480 model before sending only new test prompts and a generated fixture.

## Limits

This does not claim zero packet loss from a public broker, unlimited offline
delivery, or exactly-once external side effects across every Desktop crash
boundary. Public MQTT latency remains significant. No existing failed user
request was silently resubmitted. Before manually resubmitting a side-effecting
task, inspect its original remote status when delivery remains uncertain.

## Follow-up: shared MQTT congestion

The user reproduced delayed Agent and direct-contact delivery in both directions.
For source 241, the read-only Android transfer manifest recorded an original
1,463,429-byte JPEG reduced to 98,338 bytes, in one attachment chunk. Its two
attachment envelopes each had seven attempts while the dependent model request
still had zero attempts and one outstanding attachment dependency. The Desktop
acceptance ledger did not contain those three message IDs at inspection time.

An isolated TLS probe on a fresh, exact random topic (no user routes or data)
measured the following on the same PC and broker:

| MQTT payload | Broker ACK | Receiver delivery |
| --- | --- | --- |
| 1,024 bytes | 297 ms | 297 ms |
| 21,883 bytes | 1,422 ms | 1,984 ms |
| 349,563 bytes | 1,453 ms | 11,703 ms |

The 98 KB image is not a 98 KB MQTT packet: nested encoding and authenticated
privacy padding add overhead. These observations establish delayed delivery,
not the public broker's private rate-limit configuration or the precise network
hop responsible. Probe: `tools/testing/mqtt_link_probe.py`.

### Changes

- Both durable outboxes allow at least 30 seconds for a peer receipt before
  application-level retransmission, with existing exponential backoff caps.
- Do not republish a durable message while its original broker token is pending.
  Disconnect clears token ownership; retries retain the message ID and ciphertext.
- Android excludes broker-owned messages from retry-exhaustion cleanup.
- Android broker deadlines follow TCP ordering: short controls queued behind a
  long attachment cannot prematurely abort that attachment. New messages cannot
  indefinitely extend an older deadline. Defaults are 30 seconds and 60 seconds
  for attachment chunks; broker acknowledgement is still distinct from delivery.
- Android ACK completion does disk IO and fragment pumping outside Paho callbacks;
  generation checks discard queued completions from an old connection.
- Internal control messages without contact IDs resolve only through an existing,
  cryptographically ready relationship, never an arbitrary stale mailbox.
- Desktop's loopback probe uses a 30-second default rather than 10 seconds.
- Desktop waits for the last attempt's receipt deadline before quarantining it,
  and excludes packets still owned by Paho. Other routes remain schedulable.
- Replay suppression also recognizes the exact legacy receipt-only completed
  marker, so upgrading does not revive an ACK-of-ACK exchange from older records.
- Debug diagnostics log actual sealed packet sizes, pending ACK counts and ACK
  elapsed time without message contents or encryption secrets.

Desktop follow-up regression: 149 tests passed (98 transport/routing/recovery,
51 contact/attachment/subscription/receipt/timing tests). Android follow-up regression:
100 JVM tests passed against the final source; final Gradle build succeeded in
7m53s. Bytecode inspection confirmed the generation-guarded fragment completion.
An earlier intermediate compile saw a stale class while diagnostics were being
added; this was superseded by the successful final build, not counted as a pass.
No deployment, restart or new phone test messages were performed for
this follow-up. The earlier real-model probe does not certify these later changes.
Final S26U Agent/image/contact bidirectional acceptance requires a later authorized
deployment. No claim is made that software changes remove public-network latency.

### Pending S26U acceptance (do not run until deployment is authorized)

1. Keep identities, pairings and chat data. Deploy both matching builds only after
   checking that no user task will be interrupted.
2. Send new, uniquely labeled contact messages in each direction. Correlate
   message IDs and separate submit, PUBACK, peer receipt and UI display timestamps.
3. Send the same worksheet as a new, explicit user request. Verify its compressed
   size, attachment receipt, dependency release, single task generation and result.
4. While one attachment is awaiting acknowledgement, send a small control/contact
   message. Verify no second copy of the same durable packet exists before PUBACK
   and no early timeout from the packet queued behind the attachment.
5. Verify late receipts on the final attempt clear the outbox without a false
   failure, and switching conversations cannot create a second model invocation.
6. With user permission for network disruption, test disconnect/reconnect and
   confirm the original IDs/ciphertexts are reused and revoked routes stay blocked.

Record measured latencies rather than treating a connected socket or unit-test
pass as proof of end-to-end delivery. If broker ACK remains fast while peer
receipt is slow, inspect subscriber delivery and application processing separately.

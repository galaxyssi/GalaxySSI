# Deferred Outbound Selection Checkpoint

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.
This is a delivery-recovery fix, not completion of the full multi-broker goal.

## Evidence And Root Cause

The current owned native smoke initially timed out at `one-path-down`
(`build/mqtt-owned-current-20260913.log`). The receiver had four dispatched
inbox rows and two contact rows. Those counts alone do not prove business loss:
the inbox also contains delivery receipts. The original failure did not retain
the sender's state or the missing message's type, so its exact cause remains
unproven. Two subsequent native runs passed all nine business messages each.

Source investigation found a deterministic, independently reproduced defect:

1. The durable flusher selects a message while its authenticated route is ready.
2. The route changes before wire preparation, which returns `_DeferredPublishInfo`.
3. That result has `rc=0`, `mid=0`, and `deferred=True`; no MQTT packet exists.
4. The old flusher registered token zero as awaiting PUBACK.
5. Future flushes exclude that message as broker-owned, so no actual publication
   or callback can release it. Another deferred message can overwrite token zero.

The focused test failed before the fix with
`{0: ('current', 'stable-message')}` instead of an empty pending-token map.
This proves that failure mode, not that it caused every historical timeout.

## Fix

The actual reserved publisher now recognizes the deferred marker before token
registration. It returns the existing row to `queued` and does not report a
publication. The SQLite update is scoped to the exact pair/message and only a
`sending` row. It refunds the selection's attempt count because nothing reached
the physical publisher. Repeated release does not repeatedly decrement the
counter; published or already-receipted rows are not reset or recreated.

The ciphertext, message ID, receipt proof and creation time remain unchanged.
Actual failed sends retain the existing retry budget. Reservations still leave
through the existing `finally` path. No Signal operation, AEAD/TLS check, wire
format, pairing grant, UI or Agent execution semantics change.

Android's corresponding wire-preparation branch was inspected: it returns
`false` before token registration when route preparation is unavailable. This
patch does not change Android source or claim new Android device acceptance.

## Verification

| Scope | Result | Evidence |
| --- | --- | --- |
| Pre-fix focused regression | Failed: ghost token zero | Captured command output before the production edit |
| Actual preparation plus real SQLite outbox | Passed; same queued ciphertext replays without encryption | `test_actual_wire_preparation_deferral_replays_same_durable_message` |
| Final expanded Desktop regression | 169 passed in 47.060 seconds | `build/mqtt-deferred-expanded-v2-20260913.log` |
| Pre-fix rotating owned path baseline | 30 loss/recovery cycles, 99 business messages passed | `build/mqtt-owned-rotation-20260913/report.json` |
| Fixed native subscription-loss boundary and three rotations | 19 business messages passed; both endpoint logs empty | `build/mqtt-deferred-native-20260913/report.json` |

The 30-cycle baseline was started before the production edit. Its already-loaded
endpoint processes retained the old publisher. It rotates all three owned
listeners, with both directions tested while each is down and another message
after restoration. This passing baseline does not negate the deterministic bug.

The fixed native run also passed delayed old resume ACKs, three-path replay,
fragmentation, receipt loss, both endpoint process deaths, all-path outage and
single-path recovery. The final offline Desktop contact/Agent/diagnostic API
checks preserved their ciphertext and queued state across another process death;
they do not claim delivery to an Android phone. All test worker processes stopped.

The new native scenario removes the actual receive subscriptions precisely
between durable selection and wire preparation. It checks that the message was
not delivered, no ghost token was registered, and the immutable row remains
queued with zero sent attempts. Restoring real subscriptions must let the same
message reach the peer, once, through TLS, native Signal and the real contact
store. The fixture does not forge a receipt or bypass route authentication.

The lab now retains bounded packet observations, inbox message types, pending
broker tokens and both endpoints' last snapshots on failure. It reports the
exact missing business ID. No private keys, credentials or plaintext chat bodies
are added to the report. All test identities, databases and sockets are isolated
from production and removed during owned-lab cleanup.

Controller sample durations include RPC, encrypted-store reads and repeated
SQLite snapshots. They are not transport RTT, unbiased p50/p95, or proof that
three paths improve throughput. The specification's strategy/performance,
attachment, Android lifecycle, resource and power matrices remain required.

## Deployment

S26U was absent from ADB; only SM-T575 was attached and it was not operated.
No App installation or production Desktop restart was performed. Public
versions remain Android/Desktop 1.2.0 within the existing draft PR #3045;
Android's previously built full-runtime APK remains 1005. This fix still needs
production packaging/deployment and designated-device acceptance.

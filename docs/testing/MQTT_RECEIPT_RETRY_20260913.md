# Stored Receipt Recovery Across Resume

Date: 2026-09-13. Development checkpoint for draft PR #3045, not full release acceptance.

## Failure And Reproduction

The cold-hedge native smoke retained a published sender row after an all-path
outage and single-path restoration, although the receiver had already dispatched
the correct message once. Its 25s deadline failed. The original artifacts remain
under `build/mqtt-cold-hedge-native-smoke`; that failure is not overwritten.

Inspection found that `publish_stored_receipt`/`publishStoredReceipt` returned
immediately when the receiver's local resume was not confirmed. Nothing revisited
that stored proof when confirmation later arrived. An immediate publication
capacity failure had the same missing retry. The sender still had durable replay,
but its minimum ordinary retry was 30s, causing avoidable completion latency.

A bridge regression first failed with `1 != 0` after restoring local confirmation:
one receipt was expected, none was sent. It uses the actual pool adapter, AEAD,
SQLite inbox/outbox and production business ingress, with physical brokers and
Signal JNI mocked. It now verifies one business dispatch, the stored wire hash,
no premature send, and exact sender-outbox retirement after maintenance. This
proves a concrete gap, not that every earlier intermittent timeout had that cause.

## Implementation

Both endpoints now retain validated receipt proofs in a bounded, process-local
retry helper driven by the existing route-maintenance tick. No extra worker,
per-contact thread, connection or business ledger is created.

- At most 1,024 proofs globally and 64 per authenticated peer.
- Immediate first attempt; unsuccessful submission retried no faster than 500ms.
- Fixed 30s lifetime. Duplicate offers do not extend it or replace the proof.
- Maintenance drains a bounded batch and rotates unready entries for fairness.
- One callback per entry may run at a time. Successful submission removes it;
  there is no ACK-of-ACK or perpetual receipt broadcast.
- Pair removal/key rotation invalidates queued and previously drained work.
- Before every send, pair identity, immutable message/hash, current confirmed
  route and connection generation are revalidated, including at physical-path
  selection. No bootstrap exception or weaker authentication was introduced.

The shared JSON catalog generates the same limits for Kotlin and Python. The
helper stores only proof metadata/callbacks, not image bytes or another copy of
the business body. Queue limits/expiry/process death fall back to the original
durable sender replay and receiver inbox proof. A successful local submission or
PUBACK is still not RX_STORED on the sender; only its verified receipt commit
retires the business outbox. Later packet loss remains covered by sender replay.

This change concerns per-attempt small-message RX_STORED receipts. It does not
claim that every legacy Signal acknowledgement, fragment bitmap, artifact or
task-completion recovery path has now passed full acceptance.

## Verification

- 104 focused Python tests passed (12.977s), including the new recovery, capacity,
  revocation, bounded retry, expiry, coalescing, fairness and reentrant-drain cases.
- Expanded broker/pairing/route/chunk/receipt/recovery regression passed 282 cases
  (81.160s), including those 104. An OSError diagnostic is from an injected
  fragment publication failure, not an unhandled production exception.
- 206 host Kotlin tests passed (9.025s), including symmetric receipt recovery and
  rejection of bad proof/wrong identity before local resume confirmation.
- 17 native measurement/fault/controller tests passed; five catalog tests passed.
- Desktop checks passed: 37 tests and structure validation, no UI modifications.
- Normal full-runtime Android build and instrumentation Kotlin compilation passed
  in 8m 59s. The five focused JVM suites passed 91 tests, zero failures/errors/skips.
  These overlap the host selection; they are not 91 additional unique cases.
- `aapt` verifies `com.galaxyssi.chat`, version 1.2.0 (1005). The full APK is
  427,093,020 bytes, SHA-256
  `4E3C7DAC6784AAF750CFE0CB67832AFCAE2C44C963367316B6679D6F36B5440C`.
  It is archived at `build/artifacts/mqtt-receipt-retry-v1/GalaxySSI-1.2.0-1005.apk`,
  not installed. No runtime/native exclusion was used for this build.

Owned native runs use two independent real JVM Signal identities, production
Desktop ingress/contact handling, actual SQLite stores and three loopback TLS
brokers. Broker labels are not real provider implementations. Reports:

| Run | Business messages | Path loss/recovery cycles | Result |
| --- | ---: | ---: | --- |
| `build/mqtt-receipt-retry-native/report.json` | 40 | 10 | Passed |
| `build/mqtt-receipt-retry-native-final/report.json` | 20 | 3 | Passed |

The final run additionally holds only the receiver's actual encrypted resume
ACKs after restoring one broker. Other packets enter the real production path.
The message must be stored/dispatched while the receiver is not yet route-ready,
and a pending receipt must be observable. The sender must still have its original
outbox row with one attempt. Releasing the original ACK packets must complete
delivery within 25s of enqueue, before the 30s durable resend. There is only one
available physical path, so a backup hedge cannot mask the missing local retry.
Both final endpoint logs were empty, and each business row had one dispatch.

The 40-message run preceded the final per-publication authorization recheck;
the final 20-message run includes it. These counts overlap scenario classes and
are not sixty independent statistically sampled performance cases. Fault-smoke
timings include RPC/SQLite polling and are not provider p95 or Android latency.

Failed future smoke runs now retain an explicit failure report and attempt fresh
snapshots of both live endpoints. An RPC failure is not followed by another RPC
on an uncertain stream. Observation failures cannot turn the run into a pass.

## Remaining Acceptance

The preceding [cold-hedge measurements](MQTT_COLD_HEDGE_20260913.md) remain valid
historical observations, including failures. Receipt retry needs broader load,
real-phone and cross-platform coverage. The full image/file/video, 100KB/boundary/
5MB/21MB/larger transfers, control-under-load, QR pairing, ten live windows/model
tasks, process lifecycle, Doze, cellular/weak-network and power gates remain open.

S26U is not connected. The connected SM-T575 was not operated as a substitute.
No production Desktop process, app data, pairing or UI was changed by these tests.
Draft PR #3045 remains open; this is not permission to auto-merge or declare the
whole multi-broker specification complete.

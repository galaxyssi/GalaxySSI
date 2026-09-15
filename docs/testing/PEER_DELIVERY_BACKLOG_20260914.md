# Peer delivery backlog repair

## Scope

- Branch: `fix/peer-delivery-backlog-20260914`.
- Original tested base: `aaa0ac9a0`; synchronized to `b108cc535` before PR
  submission (incoming changes affect only the watch app).
- Android and Desktop version: `1.2.1`; Android version code: `1006`.
- Device under test: S26U (SM-S9480). No other phone was operated.
- Pairing, encryption, chat history, ciphertext queues and queue limits remain intact.

## Observed failures

The Desktop route queue reached 128 pending packets. This was not 128 user
messages: authenticated receive bodies showed recovery queries, capability
notifications and delivery acknowledgements dominating traffic. A ten-minute
sample contained 162 delivery acknowledgements, 30 recovery queries, 20 result
page requests, 17 blob capability messages, 11 connector status requests and
one contact message. These counts describe that sample, not a fixed workload.

Receive-worker stack samples included synchronous full-outbox scans while
processing receipts and recovery replies. Slow receive processing permits
additional physical copies/retries to arrive, amplifying the backlog.

Two Desktop contact messages exhausted six attempts but the conversation still
showed them as queued. Some older phone messages arrived later; `66777` has
not been recovered. Its exact failure point requires the phone's journal.
Historical generic Signal errors do not establish whether their cause was
invalid ciphertext, stale state or another sidecar/storage failure.

## Changes

1. Commit reliable replies before returning from receive processing, then wake
   the existing sender worker. Authenticated receipts also wake that worker
   instead of scanning/publishing the whole outbox inside the receive lane.
2. Coalesce successful Signal receipt publications for duplicate messages in a
   bounded two-second window keyed by route, message ID and ciphertext hash.
   Failed publication is not suppressed. Later retries and process restart
   still produce a new durable Signal receipt.
3. Retain both authenticated attempt receipts and durable Signal receipts.
   Attempt correlation expires and cannot replace confirmation after a long
   queue delay or sender restart. An initial experiment that suppressed the
   durable receipt was withdrawn and is not the final design.
4. Project exhausted sends to failed UI state, with route/direction checks and
   idempotency. Late authenticated receipts can still upgrade failed messages
   to delivered. One failed projection does not block another route.
5. Reconcile pre-existing failed outbox rows when reading a bounded history
   page. A missing outbox row is never treated as proof of delivery. No content
   is resent by this reconciliation.
6. Log allowlisted Signal sidecar error classes rather than only RuntimeError;
   do not log the raw private error body.

## Verification

- Final Desktop focused suite: 209 tests passed. Includes durable receive,
  dispatch recovery, multipath authorization, replay, route isolation, sender
  wakeup, failure projection and callback registration.
- Final Android build: successful in 11m 9s; 50 targeted MQTT tests passed
  (18 dispatch, 25 peer-route and seven receipt-retry tests). APK signature
  verification passed. Metadata confirms version `1.2.1` / `1006`.
- Android transport behavior retains the existing durable receipt mechanism;
  its experimental receipt suppression was removed before this final build.
- Replay regression: 128 burst duplicates cause one Signal confirmation;
  a retry after 31 seconds and a fresh process each confirm again.
- Synthetic outbox test: 10,000 queued rows, eight selected, 140 ms on the
  final test run. This is not a public-broker latency measurement.
- Final deployed Desktop to existing S26U app: three of three contact messages
  obtained authenticated stored receipts. API-observed times including polling:
  4,717 ms, 2,491 ms and 2,046 ms.
- Post-test ingress snapshot: zero pending, zero admission rejections;
  high-water mark ten since the final Desktop restart.
- Old `123` and `5555` now display failed, not queued. They were not resent.
- Final APK installed on S26U using an in-place `adb install -r`; package
  inspection confirms `1.2.1` / `1006`. App data was not cleared.

Logs: `build/peer-backlog-20260914-desktop-tests.log` and
`build/peer-backlog-20260914-android-final.log` (local build artifacts).

## Remaining acceptance

- Verify phone UI delivery state and both sending directions on the final APK.
- Inspect the S26U journal for missing `66777`; new-message success is not proof
  that this older message was recovered.
- Run longer idle/reconnect, weak-network and backlog stress tests. Three
  deliveries do not establish a stable p95 or a complete recovery matrix.

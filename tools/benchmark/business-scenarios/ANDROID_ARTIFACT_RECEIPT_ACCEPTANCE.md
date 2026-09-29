# Android artifact receipt replay

## Evidence and scope

Active3 A007 on Android 1.3.25 and Desktop runtime 1.3.23 exposed incomplete
artifact delivery in two of three observed turns. The original PPTX arrived
late; a subsequent background turn delivered the PPTX but two of four previews
were still missing at its 90-second artifact audit. Those failures remain
unchanged. The available logs do not prove a broker-specific cause or establish
that the code defect below caused those particular missing files.

The receiver did have an independent retry-loss defect: `artifact_chunk`
swallowed ingestion errors, ignored a rejected application-level stored receipt,
and unconditionally completed the durable inbound record.

## Change

Android 1.3.26 (1069) runs artifact ingestion on the existing attachment worker
and retires the incoming chunk only after durable ingestion. For a final chunk,
its stored receipt must also be accepted by the existing durable control outbox.
Write failure, disconnected transport, rejected publication or executor failure
leaves the incoming record eligible for the existing replay scheduler.

Already stored artifacts take the existing idempotent ingestion path during
receipt replay. Partial chunks can complete their own inbox entries, but never
send a whole-artifact stored receipt. UI availability and requested save handling
remain after successful final acceptance. No new polling loop, model request,
queue-size increase, protocol change or weakening of task/peer checks is added.

This builds on PR #3289's input-attachment recovery fix. It addresses the opposite
direction: Desktop-produced artifacts received by Android. Desktop code is not
changed or redeployed by this patch.

## Targeted device fixtures

`AgentDesktopArtifactReceptionDeviceTest` uses a unique cache directory and
isolated encrypted inbox database for every test. It publishes no packets and
does not modify user contacts or conversations.

- Reject the stored receipt, recreate the inbox repository, then accept replay;
  verify completion and unchanged artifact hash and file modification time.
- Make the artifact root unwritable as a directory using a fixture file, verify
  no receipt or inbox completion, remove the obstruction, then replay.
- Persist the first of two chunks without a stored receipt; reject final receipt
  then retry and verify the complete file hash and individual inbox completion.

These are real file/database tests with an injected publication result, not
evidence that real MQTT loss, process death or all artifact deliveries succeed.
The frozen 100-case/1100-turn campaign and updated-Desktop live recovery matrix
remain incomplete.

## Validation on 2026-09-30

- Android debug and instrumentation APKs built successfully; Active3 reports
  version 1.3.26 (1069) after an in-place upgrade.
- Nine JVM tests passed: `AttachmentControlInboxTest` (5) and
  `AttachmentControlPublicationTest` (4).
- Ten Active3 device tests passed in 6.796 seconds: the three new reception
  tests, two attachment-control recovery tests and five artifact-store tests.
- Thirty-two host catalog/report tests passed.
- The first device attempt had three fixture failures: the store resolves
  `applicationContext.filesDir`, while the wrapper only replaced `filesDir`.
  The corrected fixture redirects both. Its three synthetic leftover artifacts
  were identified by exact fixture IDs and removed, not by clearing user storage.
  The successful rerun above is separate from that failed attempt.

## Real-model A008 follow-up

Run `active3-warehouse-image-20260930-v1326` ran frozen A008 turns 0 and 1
through the actual composer, remote Codex and existing Desktop 1.3.23 process.
Both replies settled and their timers stopped. Instrumentation finished in
347.664 seconds; that runner success does not mean the business checks passed.

| Turn | Reply terminal | Observed total | Result |
| --- | ---: | ---: | --- |
| 0: create PNG | 116.178 s | 231.575 s | Artifact audit has no records; stable reply capture was not verified |
| 1: revise B quantity | 81.387 s | 112.564 s | Actual 1200x1600 PNG received; saved-download hash matched; stable capture verified |

A separately captured live screen showed turn 0's thumbnail. Its delivery ledger
later recorded a stored receipt. The original audit remains failed/unverified;
investigate reply-row identity and delivery timing before calling it pure packet
loss or rewriting that observation as a success.

The received turn 1 PNG was visually reviewed. Arithmetic and supplied values are
correct, but the response and image invented the currency unit "yuan" from an
unspecified monetary unit. Its source-bound content review is therefore a fail,
separate from the passing file delivery check. A grounded generation policy and
new-run regression are still required. Nine further A008 turns remain untested.

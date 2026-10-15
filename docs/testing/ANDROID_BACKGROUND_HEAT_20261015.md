# Android background heat investigation

## Scope

S26U background cognition, attention collection and title translation. Preserve conversations,
contacts, permissions and existing news. No real-model stress run or changes to the Desktop transport.
Android release: 1.5.23 (1306).

## Before the change

An approximately 47.6-second ART sampling trace on S26U showed:

- `AndroidCognitionWorker.executeOnce`: 34.792 seconds inclusive sampled CPU time.
- `GlobalSuperAgentRuntime.processPending`: 27.140 seconds inclusive.
- `quarantineEvent`: 14.968 seconds; `loadDeadLetters`: 12.745 seconds inclusive.
- `unnotifiedDeliveredMessages`: 12.001 seconds; attention preferences: 10.735 seconds inclusive.
- Heap task daemon: 13.166 seconds. Regex compilation also appeared in the hot path.

These inclusive measurements overlap and must not be added together. Sampling adds overhead;
these are hotspot evidence, not a battery-energy measurement.

From 22:16:31 to 22:26:31 local time, the app log contained 27 feed cycles with no new items,
28 cognition starts, 18 cognition cancellations, 16 translation starts, 96 GC entries and
71 long monitor-contention entries. Cancellation was followed by more synchronous processing.
Public push items that were irrelevant or duplicates still caused notification scans.

Battery temperature was about 38.8 C, skin about 39.5 C, Android thermal status LIGHT.
USB power was present but charge continued to fall. Process samples ranged from low single
digits to 151% (100% represents one CPU core); the load was intermittent, not continuously 151%.

## Changes

- Migrate dead-letter payloads transactionally to individual encrypted rows. Index only IDs,
  ordering and recovery versions. Quarantine updates one row instead of reserializing all history.
  Existing retention and replay semantics remain; malformed migration rolls back without removing
  the legacy data. Upgrade checks use metadata when no eligible recovery remains.
- Read attention preferences once per notification pass; remove duplicate admission checks and
  stop after finding the latest eligible notification batch. Keep source/evidence checks intact.
- Empty feed/push publications neither scan the inbox nor refresh the UI or wake learning.
- Feed and cognition retry timers only wake separate execution jobs. Replacing a future timer
  no longer cancels the worker doing collection or learning.
- Coalesce immediate attention wakeups off the UI thread with at most one pending successor;
  do not discard a result arriving after the running worker's snapshot.
- Reuse text-normalization/date regexes instead of compiling them for each record.
- Space background polls under mild heat. Defer discretionary automatic learning and translation
  under moderate/severe heat, critical charge or power saving; retain durable work and retry after
  the device recovers. Chat, contact transport, receipts and manual execution do not use this gate.

## Verification

Final expanded JVM regression: **155 tests passed**, zero failures/errors. Debug APK and
instrumentation APK both built successfully. Kotlin source-size, localization and whitespace guards passed.

S20U was subsequently authorized as an installation target. It was upgraded in place to
**1.5.23 / 1306** and launched successfully. **11 instrumentation tests passed** in 22.519 seconds:
migration, atomic rollback, reopen/clear, indexed recovery eligibility, timer isolation, empty
publication, preference snapshots, model-independent collection, feed revision and title retry recovery.
The synthetic 1,000-record fixture appended 12 rows in **120 ms**, with an unchanged older row's
ciphertext verified byte-for-byte. This is not a direct speed ratio against the earlier ART trace.
Device fixtures use separate databases and synthetic records, not user tasks.

A read-only S20U diagnostic found zero installed dead letters and 137 pending events; its history
is therefore not a substitute for reproducing S26U's dead-letter load. The first upgraded feed
run retired one legacy timer without the new timer flag; later observed feed/attention runs no
longer exhibited the recurring self-replacement pattern. No crash was observed in the short window.

S26U disconnected from ADB after reaching 3% charge despite USB power. Installation and a same-device,
matched-load thermal comparison remain pending reconnection. No S26U post-fix temperature claim is made.

## Measurement caveats

Do not interpret a low-battery deferred worker as proof of lower CPU while doing equivalent learning.
Long-duration thermal/energy validation needs comparable workload, charging, screen and ambient
conditions. This change does not claim a measured steady-state temperature or battery-life gain.

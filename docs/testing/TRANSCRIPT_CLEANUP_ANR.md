# Transcript Cleanup and Discovery Storage

## Observed Failure

On 2026-10-15, an Android 1.5.13 foreground ANR recorded this chain:

1. The main thread requested a new conversation and waited for `AgentTranscriptStore`.
2. Transcript cleanup held that monitor while publishing a deleted-entry learning event.
3. Learning publication waited for `GlobalAgentRepository.STORE_LOCK`.
4. The repository lock owner was decrypting all proactive messages to refresh the home unread indicator.

Input dispatch exceeded 10 seconds. A previous-day trace showed the same chain;
another showed an already-migrated run ledger being locked during Activity creation.
System background force-stops are separate from these ANRs and are not classified as crashes.

## Changes

- Finish transcript mutation under its monitor, then publish real deletion observations outside it.
- PROCESS records never entered learning; their cleanup now also skips learning retractions.
- Invalidate compaction using the affected conversation only, not a full conversation scan.
- Read inbox counts from metadata, preserving digest grouping, viewed state and feedback filtering.
- Reuse a completed ledger migration marker without waiting for the event-writer monitor.
- Public discovery records no longer use local AES. Dedicated news/translation/feed/push stores,
  discovery preferences, reader state, source evidence and public attention message rows opt out.
- Existing encrypted discovery rows convert on access with an atomic conditional update. There is
  no startup-wide migration, count eviction, or deletion of news/favorites/history.
- Shared research state, personal insights, chat, memory and transport encryption remain unchanged.
  Data remains in Android app-private storage; it is not exported to shared Downloads.

## Targeted Verification

- `TranscriptCleanupAnrDeviceTest`: cleanup and new-conversation responsiveness under a blocked
  global repository; PROCESS retraction filtering; ledger facade construction under a held writer monitor.
- `AttentionLocalStorageDeviceTest`: encrypted-row conversion and recreation, public/personal storage
  separation, grouped unread counts and 10,000-row metadata-only counting.
- `AttentionLocalStoragePolicyTest`: exact opt-out scope and default-encrypted behavior.
- Existing transcript policy, run-control, discovery preview, saved/read and reader lifecycle regressions.

Device fixtures use dedicated identities or isolated databases. No model requests, contact messages,
door actions, or user-data resets are required. These tests reproduce the observed contention paths;
they do not establish that every possible ANR in unrelated features has been eliminated.

## S26U Verification (2026-10-15)

- Installed Android 1.5.18 / 1301 as an in-place update from 1.5.13; no data reset.
- 77 targeted JVM tests and 19 device checks passed.
- With the learning repository deliberately blocked, three cleanup paths plus new-conversation
  creation completed in 1,498 ms. Conversation-window hydration also passed under the held lock.
- Counting 10,000 synthetic news records from metadata took 47 ms.
- On 447 existing inbox items, home counts took 14 / 5 / 4 ms.
- Discovery first content: 415 ms, 20 rows. Indexed page reads: 1,844 / 8 / 7 ms;
  the first read still included first-access work and must not be presented as consistently sub-10-ms.
- MainActivity cold launch reported 1,092 ms. These are small device samples, not p95 claims.

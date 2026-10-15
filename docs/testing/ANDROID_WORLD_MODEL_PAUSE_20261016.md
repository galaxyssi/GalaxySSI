# Pause world-model learning without stopping messages

## Scope

Android v1.5.24 (1307). Use the existing persisted Global understanding switch
(`GlobalAgentSettings.enabled = false`) to pause world-model learning. Do not delete
messages, learned records, pending events, conversations, or news. Do not stop the
contact transport, foreground Agent tasks, or collaboration recovery.

## Behavior

- Reject cognition event, attention, explicit, scheduled and retry enqueue requests
  while the switch is off. A stale worker checks the switch before acquiring the
  cognition execution lock, probing load, opening runtime state, or retrying.
- Turning the switch off cancels the six learning work chains, not all WorkManager
  tasks. Manual Obsidian projection is separate and remains available.
- Startup with learning off skips world-model restoration, upgrade replay and
  dashboard reconstruction. A running event batch commits its completed portion
  before stopping at the next event boundary.
- The conversation-page refresh path also skips cognition while preserving its
  normal transcript/header refresh and notification-navigation behavior.
- News RSS/push collection and notification eligibility no longer depend on the
  learning switch. News permissions, followed topics, notification preferences,
  and title-translation preferences still apply.
- Enabling news or editing followed topics cannot silently re-enable learning or
  create research tasks while learning is paused.
- Existing model responses can still be received and preserved. New world-model
  dispatches are not scheduled. Pausing does not erase historical knowledge.

## Verification

Automated coverage includes scheduler admission for every cognition mode, news
notification permission precedence, and isolated news ingestion with learning off.
An opt-in device test changes only the installed learning switch, verifies saved
news/conversations and pending events, and checks that wakeups cannot recreate work.
A separate opt-in test checks persistence after a new App process starts.

JVM regression: 157 tests passed, zero failures, errors or skips. Debug and
instrumentation builds succeeded. Source-size, localization and whitespace checks
passed. Final package verification follows the last source change.

S26U disconnected during implementation and did not appear in USB or mDNS discovery.
Device tests and application of the persisted off setting remain pending. S20U is
connected but its installed configuration was not changed for this S26U request.
No temperature reduction or on-device learning shutdown is claimed yet.

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

JVM regression: 157 tests passed, zero failures, errors or skips. Final production
APK and instrumentation builds succeeded. Source-size, localization and whitespace
checks passed.

S26U (SM-S9480) was upgraded in place to v1.5.24 (1307). The opt-in installed-state
test set only `enabled = false`, verified all other learning/news settings were
unchanged, and retained all 772 existing proactive messages and 134 conversations.
Pending events were retained. All six learning work chains had zero active work,
including after attempted immediate, explicit, attention and scheduled wakeups.

A separate instrumentation process verified the persisted off setting and zero
active learning work. A subsequent normal App launch logged
`global_runtime_background_disabled`. Three existing synthetic news regressions
also passed (collection despite exhausted learning budget, notification settings,
and in-place review preserving read state): five device checks passed overall.

The new isolated paused-learning news test initially failed its notification
assertion: its one-topic preference snapshot did not match the merged default
topic catalog used by collection. The fixture now explicitly disables other
topics and checks the collected topic. This test-only correction compiled, but
S26U disconnected again before its rerun. This remaining synthetic check is not
reported as passed. It does not undo the verified installed off setting.

S20U was not changed. No messages or historical knowledge were deleted, no real
model tests were dispatched, and no sustained temperature reduction is claimed.

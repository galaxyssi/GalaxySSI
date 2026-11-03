# Scheduled reply unread regression

## Failure

A scheduler execution writes its internal transcript under `proactive:<taskId>`.
Older deliveries reused that execution's run ID as the chat reply's turn ID.
The ownership filter correctly rejected the second conversation's copy, but
the unread registry still contained its `scheduled-result:<runId>` token.
Opening the chat could never acknowledge a reply absent from its render source.
Legacy quiet diagnostic results could also retain unread tokens after the UI
stopped displaying those diagnostics.

## Invariants

- New deliveries use a destination-scoped `scheduled-delivery` turn identity.
- The run ID remains available as the task ID; the original dedupe key remains
  stable for idempotent delivery and read acknowledgement.
- A legacy result is projected only when its internal execution owner resolves
  to a stored schedule whose destination matches the canonical conversation.
- Ordinary cross-conversation ownership checks remain unchanged. A missing,
  deleted, or foreign destination does not become visible through this repair.
- Existing message IDs, timestamps, ordering, and encrypted storage are retained.
- Quiet diagnostics do not create new unread markers. Reconciliation examines
  only indexed pending schedule results, not all messages in a conversation.
- Reconciliation removes unreachable or intentionally hidden schedule markers
  without marking other replies as read.

## Automated checks

Unit suites:

- `ConversationScheduledReplyPolicyTest`
- `AgentReplyUnreadPolicyTest`
- `AgentTranscriptOwnershipTest`

Device suites:

- `ConversationScheduledTasksDeviceTest`: internal execution before delivery,
  destination isolation, legacy projection, quiet diagnostic cleanup,
  acknowledgement after reopening, and duplicate delivery.
- `UnreadReconciliationDeviceTest`: indexed lookup, orphan cleanup, deletion,
  and arrivals racing reconciliation.
- `ReplyUnreadDeviceTest`: foreground acknowledgement and conversation isolation.

The schedule device suite uses isolated databases and preferences, intercepts
service/activity launches, and does not invoke a model or operate the clock.

## Real-device verification

On the affected phone, preserve the existing conversation and paused schedule.
Record its unread token, open and leave the conversation, and confirm the old
build leaves the badge behind. Upgrade without clearing app data. Reopen the
same conversation, return to the list, and verify the badge and pending token
are gone. Repeat after a cold start; confirm the schedule remains paused and
the existing transcript row count is unchanged.

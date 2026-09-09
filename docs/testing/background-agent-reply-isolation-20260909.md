# Background Agent Reply Isolation

## Reproduction And Cause

On S26U, a completed task and a separate Codex contact entry showed the same
reply after the App moved to the background. The contact entry had an unread
badge. The task response bus persisted the reply, then returned `false` because
no managed consumer intercepted it. MessageService interpreted that Boolean as
unhandled delivery and also appended the response to peer-chat history.

## Fix

- A decoded, current Agent task response returns from the background handler
  after managed consumption or confirmation of its exact durable inbox record.
- If neither condition holds, the handler defers transport acknowledgement;
  it must not silently discard the response or fall through to peer storage.
- The existing durable identity includes task/execution scope. An acknowledged
  inbox record remains proof of receipt, preventing redeliveries from becoming
  contact messages after the task UI has consumed the reply.
- Both initial conversation-list loading and live contact refresh exclude
  standalone Agent/model contact-history entries using the existing navigation
  policy. Agent contacts remain available in the contact directory and model
  selector. Existing history, task transcripts, pairing and keys are untouched.
- Person, device, group and system contacts retain their peer-chat behavior.
  Display names are not used for classification.

Android version: 1.1.23 (909). Desktop is unchanged.

## Coverage

Host unit tests cover contact-history visibility, legacy Agent metadata, peer
identity precedence, existing Agent navigation and conversation hub behavior.
All 22 selected host tests passed (three visibility-policy tests, five Agent
navigation tests and 14 conversation-hub tests). Repository checks passed.

`BackgroundAgentOutcomeDeviceTest` adds four actual MessageService callback
regressions using isolated preferences and databases:

1. A reply without a foreground/managed consumer is durably stored and creates
   zero peer-chat rows.
2. Repeating a delivery after inbox acknowledgement creates no peer-chat row
   and does not reopen the handled inbox item.
3. Two tasks using the same Agent retain separate conversation/task identities.
4. A superseded reply reaches neither managed consumers nor peer-chat history.

The same suite retains ordinary peer-message, stale generation, cancellation,
failure and exact-content checks. Device test compilation is separate from
execution: this PR does not claim a post-fix S26U device pass without running it.

## Manual Acceptance

Install the fixed APK, send an Agent task, move the App to the background, and
wait for completion. Return to the conversation list: only the original task
should carry the result. Repeat with two tasks using the same Agent and with a
real person/Desktop-device peer message. Verify contact refresh and reopening
the list do not restore the old standalone Agent chat entry.

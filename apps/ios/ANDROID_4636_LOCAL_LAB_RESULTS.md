# Local Lab Results in Agent Conversations

Ports Android #4636 (`e49b0a101e537bcb74ecfb471590f5a3e55f1445`).
All changes are confined to iOS. No Android/Desktop release metadata changes.

## Conversation and Privacy

The main Agent composer intercepts personal saved-lab requests before provider
routing. English and Chinese intent patterns reject third-party reports,
negation and general education requests. Unqualified results, note and recheck
follow-ups require a host-created local-lab reply in the same conversation.
Attachments, screen analysis and unrelated scoped sessions cannot enter this path.

Only generic navigation labels enter encrypted chat history. Actual measurements,
personal notes, selected source identifiers and reminder details are not submitted
to a provider or an ordinary chat task. Group requests offer an explicitly chosen
private conversation; they do not silently read or share health records.

Persistent local-analysis consent gates the result page. When disabled, an
explicit one-time button permits one bounded read with an owner, consent version,
cutoff and monotonic expiry. It neither changes persistent settings nor permits
editing, source navigation or reminder creation. Access history is encrypted and
records scope/outcome without copying measurements or notes.

## Results and Follow-Ups

- Prefer the latest confirmed imported lab report day; otherwise use the latest
  manually saved laboratory day. Exclude invalid, deleted, future and daily-only
  records. Allow older/newer report navigation and all/abnormal filtering.
- Reuse report reference comparisons. Missing or non-comparable references remain
  unknown, not normal results. No new diagnostic ranges or conversions are added.
- Open the existing record/source history. Append a user-confirmed personal note
  or collection condition to the exact saved measurement revision.
- Confirm a future recheck time for the selected measurement. Its encrypted
  reference binds record/revision, care permission, concern and conversation.
  Existing local-care and notification preferences still apply. Record edits,
  deletion or permission withdrawal invalidate stale reminders.
- Show linked reminders in Health Actions and in the result page; cancellation
  uses the existing reminder ledger. Notification content remains generic and
  tapping it reopens the linked local results rather than starting a model task.

Views clear sensitive state on backgrounding, protected-data loss, profile
changes and transcript privacy clearing. Save paths recheck current permission
and exact revisions. A notification link rejects missing or group conversations.

## Verification Boundary

Focused JS source contracts and the iOS project structure check cover wiring,
resource placement and defensive source invariants. Fifteen deliberately synthetic
XCTest methods cover projections, consent capabilities, intent and legacy decoding;
they are authored but unexecuted. No native compilation, device notification/UI
execution, provider testing, CI monitoring, full repository check or IPA build
is claimed. Visual equivalence and real-device behavior remain release checks.

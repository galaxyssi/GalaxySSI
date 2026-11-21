# Android #4289: reviewed clarification and follow-up recovery

Reference: galaxyssi/GalaxySSI#4289, merge
`002966d2694f5af22ddcafa6c5d64c6eaecb955e`.
Android adds an opt-in live paired-provider acceptance scenario. The iOS audit
found missing runtime behavior, not merely missing tests: question review always
revoked research, reviewed-answer revisions were absent from research triggers,
and automatic reviews could not retain model-authored questions.

## Consent and runtime adaptation

- New research authorization previews that include reviewed questions explicitly
  describe model-authored question storage and follow-up after future reviewed
  answers. A separate optional `reviewedAnswerFollowUp` consent field is saved.
  Legacy grants do not acquire this scope. Their previous reauthorization rule
  remains in effect.
- Authorized automatic cloud reviews expose the scoped question proposal tool,
  with bounded sequential calls and correctable invalid-input feedback. Stored
  receipts carry exact question IDs/revisions and never invent user answers.
- A newly consented paired read-only response envelope additionally contains a
  bounded `questions` array. The phone validates and persists it before the
  assessment and final reply. Legacy envelopes remain unchanged. No Desktop
  filesystem, command, native-tool or memory permission is granted.
- Model-authored rows are saved for the user but excluded from the current turn's
  originally approved question-page snapshot. This keeps the immutable prompt,
  source validation, final retention and paired reopen binding consistent.
  Other question edits are not excluded. Conflicting user answers remain explicit.
- A reviewed answer preserves standing consent only under the new opt-in, current
  permission/profile/conversation scope and allowed related-measurement scope.
  Its durable question revision participates in the idempotent research trigger
  and handoff reason. Follow-up stays in the original private conversation.
- Repeating the same current answer leaves row/concern revisions unchanged,
  including at the revision limit. Stale row instances still fail. No third
  research turn is created for an unchanged confirmation.
- Renewing without question sharing excludes question-derived plan descriptions
  and action feedback from later model context. Sharing them again explicitly
  permits their scoped reuse; local user-visible plans are never deleted.
- Source measurements, saved measurement context, previous assessments and
  conversations remain intact. Reviewing free text does not silently fill a
  structured clinical fact, accept a plan, set a target or create a reminder.

## Source coverage and verification limits

Nine XCTest source cases exercise production question retention, cloud tool
continuation, paired-envelope validation, answer-triggered successor jobs,
encrypted archive reopen with the original pending binding, repeated-answer
deduplication, old in-flight reply rejection and legacy consent boundaries.
They also cover scoped plan-context reuse after withdrawing and regranting
question sharing.
The fixtures are isolated synthetic records and in-memory secrets.

Archive reopen is not a new OS process, and synthetic envelopes are not observed
real provider replies. No actual process/physical reboot, WorkManager equivalent,
live provider semantic behavior, UI acceptance or XCTest execution was performed
on Windows. Static structure/grammar/diff/localization checks are not Xcode
type-checking or device acceptance. No IPA is generated here.

Still outstanding: the paired protocol's on-demand history paging and interactive
remote assessment-tool correction described in #4374/#4375. Adding a question
array to the supervised final envelope does not implement those remote tools.
Exact assessment-to-question reference validation is the separate Android #4291
change, not claimed here.

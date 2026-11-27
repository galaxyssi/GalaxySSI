# Optional On-Device Team Review (Android #4642)

Baseline: Android PR #4642, merge `e60cd55e143a762bb6ed2ac7835d6e96e98e2dd0`.
Builds on the iOS temporary-team implementation in #4652. No Android/Desktop
implementation or later final-editor/final-audit behavior is included.

## Model Decision, Then User Consent

An eligible ordinary typed request enrolls a window-owned original turn. The
selected on-device model may add a typed `propose_team_review: true` flag to its
normal complete answer. This requires no additional inference or host complexity
heuristic. The original answer is retained regardless of accepting the proposal.

The iOS selected-provider planner uses its existing `disposition: respond` and
`final_response` envelope; the local web adapter uses `answer` and empty
`tool_calls`. Both require an entire typed JSON object with exactly the expected
three keys. Only the optional flag is stripped before the ordinary planner's
answer validation. Extra scope fields, malformed types, quoted examples, fenced
snippets and trailing prose cannot request UI authority. Flagged malformed web
envelopes cannot smuggle sibling tool calls. Ordinary unflagged tool decisions
retain their original handling.

Only a fresh local first answer can propose. Cloud, peer, Desktop, restored work,
managed browsers, collaboration groups, private/scoped/paused conversations,
attachments and voice/screen submissions do not enroll. Explicit solo requests,
slash commands and personal-health text are exclusion gates, not model decisions.
Manual cloud or other-local-profile locks do not qualify as on-device sources.

The window may claim a suggestion once, only after the normal answer is stored.
New draft edits, attachments, navigation, backgrounding, locking, plaintext
clearing, owner/chat/selection changes or unavailable original text invalidate
the offer. No model-supplied objective, recipient or budget is accepted. The
existing native team panel displays the original complete objective, model and
bounded cost and still requires explicit authorization. It never starts a job
from a suggestion alone.

## Original-Turn Persistence

Confirmed proposals bind the original message ID and turn. The saved user text
must match exactly before authorization and throughout dispatch. The team adds
no second user message; queued and final results stay under the source turn.
The binding is immutable across CAS job transitions and survives serialization.
Legacy jobs without a source binding remain decodable. Removed source turns
cannot receive late results.

## Protocol Update

The model writes `WORK|parents|task`, `REVIEW|parents|task` or
`CRITIC|parents|task`. The host assigns `role1`, `role2`, etc.; numeric parents
must be earlier canonical role numbers. Duplicate, self, forward, malformed and
mixed-format references fail before dispatch. Legacy ROLE plans remain accepted.
Role reports use typed JSON finding/optional dissent; synthesis uses a single
answer string. Complete JSON fences are allowed for team results, not proposals.
Legacy complete line reports and END-terminated synthesis remain accepted.

The 10-role, three-parallel, 12-call and 120-second limits, parent-only report
handoff, text-only authority, rich-execution rejection and preserved dissent are
unchanged. Prompts group related calculations and retain numbers, units and
distinctions between measured evidence, criteria and hypotheses.

## Verification Boundary

Focused source-contract checks and the iOS project structure check are used.
Fifteen new synthetic XCTest methods are authored: five protocol and ten
proposal/window/source-binding cases. They have not been executed. No native
compilation, simulator/device execution, live model acceptance, scientific
validation, CI certification or IPA generation is claimed. Android's synthetic
live numerical experiment is not presented as iOS evidence.

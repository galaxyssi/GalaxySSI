# Pinned Cloud Review Invitations (Android #4646)

Baseline: Android PR #4646, merge `16935cfbd1068177dcbd8f02036249311b7923c8`.
iOS implementation only, following the earlier conversational-team ports. Later
Android team-policy PRs are not folded into this increment.

## Admission and Native Response Format

A manually selected, ready OpenAI-compatible cloud target/model may advertise
`answer_with_optional_team_review` alongside its ordinary public research tools.
This is a terminal answer encoding, never an executable tool. It accepts only a
complete ordinary answer and a typed true review flag. No objective, destination,
budget, third field, sibling call or accompanying message text is accepted.

Both streaming and complete-JSON Chat Completions adapters mark native provenance
only for one typed function fragment in one choice and one native slot. Fragment
IDs and index zero must agree; old serialized payloads have no native authority.
Only a complete `tool_calls` termination can admit the answer. Inline examples,
wrong types, missing terminal frames and partial results cannot create invitations.
The ordinary unflagged tool decoder remains compatible with its previous formats.

The route must match manual target, exact model, endpoint fingerprint, API style,
credential availability and disclosure state. Private budgets and custom resource
ceilings are declined instead of overridden. The ordinary foreground typed source
must still exist in its submitting window. Voice, attachments, private/scoped or
grouped chats, live-data/local-only work, long-running project work, replay,
repair and later tool rounds cannot enroll a new offer.

## Accepted Delivery Before Consent

The main Agent phone planner supports the native answer on its first research
transport round, then converts it to its existing respond envelope. Its ordinary
phone completion checks are retained. The conversation stream consumes this
encoding before inline protocol parsing or any actual tool dispatch. Existing
web searches continue normally when the model chooses them instead.

Each primary execution mints an ephemeral task-local runtime ID. Native approval
is bound to that execution, a one-shot window nonce and a digest of the complete
answer. Restoration does not serialize these capabilities. Matching text from
another/recovered execution is not sufficient to claim an invitation.

Only an accepted delivered assistant row, read back from the transcript database,
can expose the confirmation panel. Owner, chat, original source turn, answer hash,
plain-text/rich state, runtime and current route must agree. Stale input, lock,
navigation and owner changes invalidate the window. No workers start before
explicit confirmation. Declining leaves the original normal answer intact.

The cloud-origin confirmation shows only the pinned route. Durable team jobs keep
an immutable pinned-cloud flag and original source binding. Every model request
revalidates the manual selection, endpoint, disclosure and budget; no silent
provider fallback is permitted.

## Verification Boundary

Thirteen synthetic XCTest methods are authored for typed native slots, bounded
answer schema, advertisement exclusions, malformed-frame compatibility, legacy
decoding, budget policy, route/source matching, one-shot consent, window changes,
source-bound jobs and cross-execution rejection. They have not been executed.
Focused JS source contracts and the iOS project structure check are used.

No Swift build, native tests, simulator/device run, real provider request, CI
monitoring, scientific validation or IPA generation is claimed. Static contracts
are not runtime certification or proof of cloud-provider availability.

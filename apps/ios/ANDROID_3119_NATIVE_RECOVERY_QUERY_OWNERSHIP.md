# Native Recovery Query Ownership (Android #3119)

This increment closes a publication boundary in both managed Desktop recovery
query producers. It is not a complete long-task liveness planner implementation.

## Ownership and Publication

The queued iOS native connector adapter persists a local query scope before
starting the queued transport. The scope binds the original host profile,
action ID and outgoing message UUID; the existing managed record binds owner,
registered agent, contact, conversation, turn, remote task and generation.
Capture requires the actual host-derived connector run ID. A failed capture
uses the existing untracked-dispatch failure path and never starts the queue.

Both legacy and journal-backed recovery query producers reauthorize identified
native waits before consuming query counters or producing a network request.
The legacy path gates before expiry side effects as well, so an unauthorized
native wait cannot become a synthetic failed response merely due to silence.
The current profile, saved permission, foreground/unlocked/readable state,
execution settings, active session, privacy/tracking controls, exact task phase,
saved pending receipt and original outgoing message must still match. An owned
uncertain-result blocked wait remains eligible; pause, cancellation or a changed
scope prevents further query publication without cancelling the remote task.

New tagged records fail closed when local task/receipt data is unavailable.
Historical untagged records receive this check only when their saved native
waiting action positively identifies them. Unclassifiable old records and
non-native Health, file, planner and team roles retain their existing policies.
This limitation is intentional: UUID shape or display labels are not ownership
evidence. No new wire fields, inferred permission or transcript disclosure are
introduced.

## Persistence and Late Results

The optional scope survives Codable, legacy migration codec, completion and
acknowledgement. A present null/malformed scope cannot silently decode as an
untagged legacy owner. The persistent ledger rejects scope substitution or
removal when an existing owner has the same generation. Existing legacy records
are not silently upgraded by re-registering an owner.

Result reception, exact response correlation, receipt commit, acknowledgement,
slot ownership, deadlines and retry/fallback remain unchanged. Already assembled
local results are handled before the publication gate. Stopping a new query is
not proof of failure and does not discard an already authorized late result.

## Verification

Six Swift fixtures are authored in the already registered managed-response test
file: both codecs, legacy compatibility, malformed/null scope rejection, late
completion/acknowledgement, persistent reopen/substitution and host-owner capture.
They have not been executed. Source contracts pin the exact app changes and
negative mutations of authorization/publication hooks. Only source/JS and iOS
project structure checks are permitted for this change; no Swift/native build,
XCTest, device, simulator, live broker/model, full repository check or IPA run.

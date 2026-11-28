# Learning Outbox Source Gate

Independent iOS follow-up from main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. This addresses the queued-payload
limitation in the Android #3007 source-membership follow-ups, not a newly claimed
Android wire protocol. Current paired cognition/autonomous/research producers
authorize creation, but the legacy retry queue previously checked only the
global learning switch and a numeric lease before actual publication.

## Production Wiring

All three paired producers supply a typed scope. Enqueue validates its original
payload fields and current profile before binding it to the actual normalized
opaque queue UUID and topic. The original producer label is NOT the queue UUID:
linkWirePayload normalizes non-UUID labels to fresh UUIDs. Do not infer owners
from message-ID prefixes or inspect/decrypt a queued prompt to reconstruct proof.

Persist optional scope metadata through the existing enqueue request, pending
record and Codable path. It contains profile, resource/paired transport, original
task/action/conversation/turn/source and, for research, exact request ID, stage,
unit, budget lease and owner key. It adds no prompt/body copy, network payload
field, permission or credential. Existing legacy rows remain decodable without
proof; missing proof is not inferred from current records.

For a scoped, non-outstanding item, recheck its binding and current verified
contact/unique paired route before attempt reservation, deferred-body work or
publication. Reload the exact current owner, positive source and unexpired lease.
Call the existing cognition, autonomous or research source/context authorization
policies and actual host permits methods. Private, paused, deleted or excluded
source/context membership, disabled settings, replaced attempts/revisions/requests,
expired/terminal owners, changed profiles/contacts/routes and ambiguous owners
cannot authorize sending. Cognition does not require fresh model availability or
select a substitute resource. Research checks the original evidence unit or
synthesis owner, not another task's maximum lease.

The scope gate precedes public/news classification, so a bound item cannot escape
it by changing its classification. Public attention/news rows without a scope
retain their separate existing policies. Ordinary user messages are unchanged.
Generic learning rows lacking proof are removed from the unsent retry queue,
not relabeled ordinary traffic or automatically rebound to current work. Denied
items do not reserve attempts or assert a remote failure/completion/fallback.

## Verification

Nine XCTest methods authored in the existing registered Link fixture, NOT run:
opaque-ID binding/no prompt copy; payload/profile/source rejection; queue route
and owner confinement; optional legacy codec; actual enqueue/reopen; cognition
private/paused/context/lease changes; autonomous action/review ownership/revision;
research evidence source/context/request/lease identity; synthesis expiry,
duplicates and terminal state. These are not live MQTT, actual coordinator
publication, protected-data, process-restart or native concurrency acceptance.

Source checks pin approved feature sections to
`cfa3cdc37e4b30dcf5541d2b71451a8294be2a11`, retain all other production and fixture
code and check both final gate placement and the later classification-containment
hook explicitly. Related authorization kernels are unchanged; when #4677 is also
present, its exact transport normalization retains those comparisons. The gate
works independently on main; #4677 additionally checks saved autonomous transport.

Dedicated source guard, JS syntax, iOS project structure and diff whitespace
checks pass. No Swift/native compilation, XCTest execution, full check, CI
watching, device/privacy/network acceptance, IPA or private evidence upload.

## Limits

This governs the legacy queue only. The journal MQTT enqueue path still rejects
background-learning requests; no parallel transport implementation is enabled.
Already admitted/outstanding MQTT work, already sent prompts and external effects
are not withdrawn. Authorization is a MainActor boundary snapshot, not atomic
revocation with a broker or cross-store transaction. A failed discard is not
secure deletion; subsequent attempts still pass the live gate. Existing lifecycle
leases/recovery decide later work, not this queue. Host metadata is not new
cryptographic sender authentication or proof of all historical prose. Android
#3007 and the overall backlog remain incomplete.

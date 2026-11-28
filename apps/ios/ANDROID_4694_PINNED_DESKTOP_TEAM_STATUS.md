# Android 4694 Pinned Desktop Team

Reference: open Android/Desktop PR #4694 at
fe9259f1b9ef7ec5ea69c4f83b65abc40ae172d0, compared with main
c6bad3465c673dfb2dcecb23b095185c129c7447. iOS-only incremental port. The reference
is not merged yet; do not assume its Desktop support is already installed.

## Presence Compatibility

The reference adds pinned_team_codex_v1 to detailed and compact Codex presence.
A compact advertisement containing only that marker is not a new routing/tool
inventory. iOS previously replaced the inventory, hash, adapter and provider
metadata with the reduced presence fields, losing existing selected-model routes.

The actual Store receiver now stores the optional snake-case marker separately,
never as an executable Agent capability. Require an explicit exact top-level
array advertisement for Codex, a paired link and matching Desktop identity.
Boolean lookalikes, adapter-only markers and parent-level inheritance do not
advertise the feature. Presence remains metadata, not an execution grant.

For a compact update matching the same nonblank identity, preserve the inventory/hash and omitted
protocol/adapter/provider/model metadata. Explicit fields still update. A changed
Desktop fingerprint cannot retain the old routing/model metadata. Detailed
inventories remove the marker and recompute its routing hash; an explicit empty
inventory remains authoritative. A later advertisement without the marker clears
the stored support flag. Compact children do not borrow parent model/adapter
descriptions. Existing trust, pairing, route authorization and publication code
are not changed by this increment.

## Scope At The Presence-Only Increment

The presence-only increment did not complete #4694. The selected-Desktop confirmation UI, fresh
isolated group with the selected model/effort, single-use draft review, persisted
confirmed original turn, stable team identity, dispatch/recovery pin validation,
expanded clinical-identifier/local-only objective screening, empty foreground
screen context for the pinned seed, and refusal of unsupported pins or provider
handoff were still pending then. Existing
ordinary collaboration is not presented as that new end-to-end flow. The next
increment below implements the entry and managed dispatch parts of this list.
No new Desktop protocol support, version bump or deployment is claimed here.

## Selected Desktop Entry And Managed Dispatch

Manual Codex team commands now open a dedicated English/Chinese review showing
the actual paired Desktop, exact advertised model, reasoning effort and full
objective. The launch is tied to the foreground source/draft revision and saved
selection; its one-shot review is consumed even after a rejected claim. No
attachments, screen-assistant request, private/child/global conversation, clinical
identifier fields or local-only objective is admitted. Missing explicit Desktop
support, ambiguous bare Codex contacts, changed fingerprint, blocked disclosure,
private budget or unavailable exact model/effort is rejected without substitution.

Confirmation saves a fresh independent research conversation before switching or
clearing the source draft. It copies only the explicit model/effort selection,
not source history, screen contents, global context or session requirements. The
two initial roles share that exact route and execute EXPLORE then DELIVER, so
one free Desktop execution slot is sufficient. An optional Codable binding
stores the profile, conversation, original turn, objective and both person IDs.
Existing rosters decode without that field. Editing/recruitment cannot silently
remove the binding or redirect a pinned member.

The production collaboration compiler retains conversation:desktop-team and its
stable supervisor run on retries. Per-member dispatch and restored frozen plans
check the stored route, original turn, exact two-person research graph, person,
model/effort and managed workspace result contract. Initial dispatch persists an
explicit run control before sending; stopped/paused/unavailable or missing
restored controls do not grant execution. The existing serial member history,
managed continuation and source-message identities remain in use. A second
ordinary send cannot restart the confirmed turn under a fresh identity. This
does not deploy the required Desktop implementation.

Still unverified/unported: cross-process/device recovery acceptance, dynamically recruited
pinned teams, and live provider refusal/handoff behavior. Those are not inferred
from source contracts. The group deliberately fails closed on roster expansion
until a reviewed pinned-recruitment flow exists. No full #4694 parity claim.

## Durable Queue And Physical Admission

Team history now archives the original optional binding separately from editable
conversation settings. General history upsert cannot replace or erase it. Old
snapshots decode with no pin; a pinned session without the archived binding is
not authorized to send. Journal queue owners require the archived profile, exact
roster/route, original text/turn, current model/effort, paired fingerprint and
explicit durable run control. Enqueue-time payload validation also checks the
pin/person, route, invocation, workspace result contract and absence of files.
This does not re-encrypt or reconstruct already prepared Signal ciphertext.

Each journal direct copy and fragment carries an optional async application
admission into the physical client queue. The actual packet remains in the
bounded queue while the current business owner is checked. Delayed copies and
reconnect retries do not inherit an earlier Boolean approval. After the await,
the client rechecks its unique admission ticket, connection generation, live
transport, route authorization and inflight/fragment capacity before writing.
Ungated priority/control packets can still drain during an admission. Stop and
reconnect invalidate late admission callbacks. Existing route AEAD, retry/hash,
PUBACK and business receipt semantics are not replaced.

Legacy pinned sends now queue with an optional opaque run ID instead of taking
the immediate publish path. Flush and each physical packet require the same
archived binding and run control. Old ordinary queue records decode without the
field. A recognized old pinned session with missing scope is held, not promoted
to an ordinary send. Historical unscoped legacy entries whose source/session
records are already missing are not proven recoverable or classifiable here.

Authorization has a last application-check point before the transport write;
this is not an atomic transaction with remote execution or a recall of packets
already written to the network. Socket timing, real interruption/restart,
provider refusal/handoff and device acceptance remain unverified. Seven new
outbox Swift fixture methods and two synthetic dispatcher propagation methods
are authored, not compiled or run; fake admission callbacks are not socket tests.

Twelve synthetic Swift fixture methods cover strict advertisements, compact vs
detailed inventories, marker removal, inheritance, actual Store retention/hash/
revocation, other agents, unpaired links, fingerprint drift, parent metadata and
optional contact decoding. They are authored, not compiled or executed.
Thirteen additional Swift fixture methods describe binding/graph mutations,
stable retries, workspace ownership, one-shot review and objective screening;
they too are authored only, not executed.

Verification is limited to JS/source contracts, iOS project structure and
whitespace. No Swift/native build, XCTest, device/simulator/live Desktop/model/
network test, full repository check, CI inspection, IPA, private evidence upload
or remote approval/merge is performed. Full runtime/privacy/parity acceptance
remains unverified.

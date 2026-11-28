# Android 4696: Scoped Original Member Recall

Reference: Android/Desktop #4696 at bb47c0d3f6ab2b115244b9f1ac689dbb35e14ef8,
compared with its #4694 base fe9259f1b9ef7ec5ea69c4f83b65abc40ae172d0.
This independent iOS PR starts from main c6bad3465c673dfb2dcecb23b095185c129c7447.
It does not duplicate the pending #4694 iOS implementation, modify Desktop or
Android, change a version or assume the Desktop counterpart is installed.

## Original Assignment Offer

Only a host-created, explicitly configured research roster with an actual paired
Codex contact and exact advertised model/effort receives an optional offer.
Archive its profile, person/node, team/run/turn/source, contact/model/effort and
pair/route binding in the member snapshot before publication. The normal history
upsert cannot change that offer after a dispatch checkpoint. Old members decode
without it. Follow-up dispatches do not create new offers. A restored original
dispatch retains its recorded identity; a marker is not inferred from text or a
provider alias.

The original payload carries scoped_member_recall_v1 and no follow-up marker
only when it matches that exact archived offer and workspace result contract.
Otherwise it remains an ordinary assignment on the same model. Both iOS reply
modes, observer and coordinator, use their existing distinct owned source/run
identities; neither gains another person's workspace. The optional offer is a
candidate for the Desktop's confined original-member path, not a data grant.

## Authorization And Data Phases

The new authorize phase accepts an empty argument object and tightly bounded,
typed identity fields. It returns only success/status. It cannot invoke a data
reader, model, publication or effect tool. Inspect active assignment metadata
twice; a one-step generation lag returns generation_not_ready, not a read grant.
Promotion during inspection needs a third identical current observation. Bind
each short-lived nonce to immutable request semantics, offer and waiting state;
a waiting nonce cannot turn into a later grant. Desktop recovery must use a
fresh bounded challenge.

Read and confirm require the exact Boolean marker, registered source identity,
current pair/route/secret binding, original archived offer, active non-private
research session and roster person/model/effort, root cancellation authority,
explicit durable RUN, open current execution generation and existing research
access. Direct homepage research groups need no fabricated generic parent task.
When a parent exists, require the same session and an unblocked executing or
waiting state. Unmarked legacy reads still require their existing parent task;
workspace file handoff is not enabled by the optional-parent scoped path.
Recheck after async evidence refresh and before read/confirm callbacks
and response publication. Receipt/replay hashes include the original offer.
Existing original-revision grants, selector constraints, evidence read coverage
and native HMAC confirmation remain authoritative. There is no filesystem,
publication, saved-tool execution, private report or unrelated-member grant.

Legacy authenticated Link and the journal-backed Signal projection both route
these requests. Journal responses use a bounded transient Signal transaction,
not a durable task or model replay. Failures do not select another model or
restart an effect. Ordinary/unmarked recall behavior is otherwise retained.

## Verification Limits

Sixteen deliberately synthetic Swift fixture methods describe strict requests,
generations, content-free preflight, nonce scope/recovery, original payloads,
optional ordinary dispatch, archived decoding and response types. They are
authored, not compiled or executed. Source contracts and project structure are
not proof of Swift compilation, Desktop confinement, native read coverage,
socket timing, live pairing or end-to-end generation recovery.

The Desktop implementation, package/version changes, Android instrumentation,
new diagnostic trace transport and live phone/model/IPC behavior are not
implemented or verified here. This is not a full runtime acceptance claim for
all 33 files in #4696. A final authority check precedes response publication;
there is no atomic remote recall of bytes already written to the network.

No Swift/native build, XCTest run, full npm check, CI inspection, IPA,
simulator/device/live model test, private evidence upload, remote approval or
merge is performed.

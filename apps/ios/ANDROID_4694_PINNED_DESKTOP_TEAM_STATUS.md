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

## Remaining Reference Scope

This is not completion of #4694. The new selected-Desktop confirmation UI, fresh
isolated group with the selected model/effort, single-use draft review, persisted
confirmed original turn, stable team identity, dispatch/recovery pin validation,
and refusal of unsupported pins or provider handoff remain to be ported. Existing
ordinary collaboration is not presented as that new end-to-end flow. No new
Desktop protocol support, version bump or deployment is claimed here.

Twelve synthetic Swift fixture methods cover strict advertisements, compact vs
detailed inventories, marker removal, inheritance, actual Store retention/hash/
revocation, other agents, unpaired links, fingerprint drift, parent metadata and
optional contact decoding. They are authored, not compiled or executed.

Verification is limited to JS/source contracts, iOS project structure and
whitespace. No Swift/native build, XCTest, device/simulator/live Desktop/model/
network test, full repository check, CI inspection, IPA, private evidence upload
or remote approval/merge is performed. Full runtime/privacy/parity acceptance
remains unverified.

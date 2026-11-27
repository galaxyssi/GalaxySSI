# Pairing and Local History (Android #4611)

Baseline: Android PR #4611, merge `a619c31427f6311ed5cbe329e4331c95db6b9134`.
The already-shared Desktop implementation is not changed by this iOS port.

Ordinary local and authenticated remote revocation now archive Desktop and Agent
contacts by default, preserving their local history while removing transport,
trust, pending transfers, control state and callable catalog entries. Existing
read-only Archived Conversations presentation remains. The explicit contact
deletion path can still request history deletion; it is not an unpair default.

Archived devices and Agents reactivate only after pairing the same full stored
fingerprint. Current paired routes must also match incoming metadata. Display
names, matching short IDs, stale links, blank fingerprints and a new identity
reusing an ID cannot authorize restoration. New identity histories are not merged
by name. Existing unpaired archives are not implicitly trusted or migrated.

Device Security separates scan/reconnect, revoke and confirmed local-history
deletion. Confirmations explain that older Desktop versions apply their own
deletion behavior. The existing control-page disconnect-only action remains.
Local-history deletion binds the captured owner, Desktop fingerprint and route,
never publishes a wire packet and leaves pairing, other computers, phone-owned
Agent conversations and incompatible identity archives unchanged.

A dedicated SQLite transaction records per-message replay tombstones and deletes
the selected contact rows together. Failure rolls back before memory or files
change. Private attachment cleanup is best effort after the database commit;
this is not forensic erasure or a cross-store atomicity claim. Existing profile
and transport formats are unchanged.

Six additional synthetic XCTest methods are authored, not executed, covering
default archive persistence and repair, wrong/short/blank identity, scoped local
deletion, replaced authorization and durable replay tombstones. The existing test
fixture incorrectly called a private Store method; it now creates contacts through
the public friend-request approval interface without widening production access.
Focused JS source checks and the iOS project checker are structural checks, not
Swift compilation, transaction fault injection, UI/device or live-peer acceptance.
No native tests/build, full check, CI monitoring or IPA is run; no private evidence
or generated artifacts are committed.

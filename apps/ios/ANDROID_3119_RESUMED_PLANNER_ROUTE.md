# Android #3119: Resumed Native Planner Identity

Reference merge: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`.
Incremental baseline: main `5f60bac1b8571768f6f12f426dee5950c6f87bd0`.
Separate from the pending #4584 tool/preview integration, with no prerequisite
on its merge and no copied commits from that PR.

## Production Correction

Two real paths, user-requested native replanning and rolling native continuation,
previously filled a missing task planner snapshot from global planner settings.
That could bypass the conversation's selected model and its exact Auto binding.
Both now resolve through resumedNativePlannerSnapshot before recording a new
initial-planning input. A missing eligible route throws into their existing
paused/blocked error path rather than falling through to a global provider.

Require the original outgoing home-Agent message and matching task/session.
Retain compatibility with tasks keyed by the outgoing message UUID as well as
the explicit turn ID, matching the existing outgoing-message lookup. A persisted
snapshot is returned unchanged and does not start a fresh Auto turn or update
its target. The caller still validates that saved provider before use; retaining
a snapshot is not a claim that a removed provider remains usable.

Without a saved snapshot, reuse the existing shortcut outcome-review selection
path instead of introducing another route ranking implementation. It captures
one Auto target, including explicit no-route; respects manual target/model;
uses the current enabled local model, eligible cloud contact or paired Codex
phone-planning route; and enforces current session, cancellation, private/local
and connector gates. Auto requires begin-turn admission and a successful exact
dispatch-binding write. An older turn cannot replace a newer binding. Manual
selection never falls back to a ready global model because its chosen model is
unavailable. A malformed, unavailable or uncommittable choice pauses planning.

Initial planning, saved recovery inputs, final-result parsing, prior effect
readback, node/effect journals, connector replay/receipt/timeout kernels and the
model snapshot schema are unchanged. Existing snapshots retain their original
provider semantics; this patch does not redesign their admission rules. The
Auto metadata write precedes the separate planning-input journal commit: this
does not add a cross-store transaction or exactly-once execution guarantee.

## Verification Limits

Eight Swift fixture methods authored and registered, NOT compiled/executed:
saved snapshot retention, legacy message-keyed tasks, selected manual model,
unavailable-manual rejection, old Auto turn rejection, scope mismatch, private/
local/connector constraints and pause/tracking/cancellation constraints. These
call the production Coordinator capture helper, not an alternate policy mock.
They do not simulate full rolling replanning, Auto network selection, persistence
faults, journal restarts or actual provider/model execution.

The source guard derives both complete call-site edits from their old blocks,
preserves their error paths and freezes the surrounding service and provider/
privacy/result/transport implementations. Historical guards normalize only the
declared source increment. No Swift typecheck, XCTest, native/device/privacy
acceptance, CI monitoring or IPA is included.

This closes the missing-snapshot provider-identity connection in these two
resumed paths only. Full scored privacy/budget/capacity routing, generic active
pre-timeout observation/deferred discovery, other dispatch contexts and native
acceptance remain open; Android #3119 and the broader backlog are not complete.

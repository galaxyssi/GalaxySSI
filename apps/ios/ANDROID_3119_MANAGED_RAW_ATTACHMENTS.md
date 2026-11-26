# Android #3119: managed raw connector attachments

## Integration

This continues the broader Android attachment-input parity work tracked in the
iOS #3119 port. Source baseline: main `4f4406c3b`, including the merged document
input work in #4581. It is not a claim that #3119
introduced these existing iOS transfer implementations or their limits.

The native paired connector now prepares the actual restored current-turn bytes,
retains the original numeric source/conversation/turn/task IDs, and uses the
existing task UUID as its attachment-dependent body message ID. The numeric
source is not converted to an unrelated outgoing transcript UUID. Existing
request identity, invocation/model checks and disclosure include the actual
attachments. Raw preparation preserves the original staged bytes.

Before enqueue, save the exact body ID and ordered attachment IDs/descriptors in
the original encrypted native wait through its guarded task commit. Existing
intent cannot be replaced by a different manifest. The journal projection requires
that saved native owner, source, route, current permission/session/profile,
budget and explicit model/effort, and the exact saved descriptor array. A numeric
ID or UUID body lookup alone never grants upload/send authorization.

The current journal path reuses encrypted deferred outbox bodies, ordinary
attachment manifests/chunks and optional Blob relay jobs. It authorizes the
current managed source before upload and outgoing sends, rechecks after the
asynchronous Blob registration, and retains cancellation/unknown-outcome handling.
Body lookup, stored/missing/failed receipts and atomic dependency release now
support the numeric source/task UUID association. Numeric receipt-to-body proof
also checks exact source/contact/Desktop/route/conversation/task/turn fields.
Existing UUID source association remains compatible; wire schemas and local
journal serialization have no added fields.

Known authenticated Blob input failures are saved in the existing encrypted
attachment-failure store before failed-body/inbox cleanup. They stop new managed
sends and can settle the original native wait as a delivery failure on the
existing foreground/resume path. They are attributed to local transport, not a
provider outage. A failed journal cleanup can be retried without reexecuting the
connector. Failure evidence and journal cleanup use separate stores, not a new
cross-store transaction or an exactly-once external-effect guarantee.

Legacy transport uses its existing encrypted deferred-attachment-task queue and
dependency protocol after current-context validation. Its already queued wire
lifecycle/cancellation semantics are unchanged; this does not claim the journal
path's per-send authorization has been ported into every legacy queue operation.

## Verification and limits

Nine XCTest methods were authored and registered, not compiled/executed. They
cover canonical/unsafe source IDs, exact transfer scope, numeric stored receipts,
dependency completion/reopen, foreign receipt rejection, transaction rollback,
known Blob failure cleanup, current-owner projection and local failure attribution.
These are fixture sources, not real SQL/fault/Signal/network/device acceptance.

No native build/typecheck/XCTest, live provider/Blob/MQTT run, CI watching or IPA.
This integration does not prove that a remote model inspected the delivered
file/image, that every adapter accepts every media format, or that background
execution is available while iOS suspends the app. Partial enqueue/transport
errors retain original uncertain ownership and may need explicit reconciliation.
Staging cleanup, storage failure and restart behavior remain unverified; the
existing bounded 256-record attachment-failure retention is not a full audit log.
Broader context/rich-output/timeout and overall Android parity remain incomplete.

Passed source checks: managed-raw, scoped document input, owned status observation,
pre-shadow routing, reported usage, live health, provider ranking, observation
timing, research context, autonomous/research source, background cognition,
live planning and special-use address contracts. Project structure, changed
JavaScript syntax/localization placement and diff whitespace also passed.
These are not executed XCTest, Swift type checking or a full repository check.

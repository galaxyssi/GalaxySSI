# Native journal delivery acceptance

Android #3119 follow-up from main
`1d68be9b738d8cbc48745b51554dbb24b4aa3129`.

## Actual missing producer

Android's delivery-ack handler resolves the original runtime/source and calls
`recordConnectorTransportAccepted`. The iOS journal already durably records
authenticated message delivery completions, not broker PUBACKs, but the Desktop
projection returned immediately for non-UUID sources. Native managed connector
requests use numeric sources, so those completions never reached their saved
waiting task. An unused transport recorder alone did not supply this connection.

## Integration

Numeric Desktop message completions now invoke a coordinator callback after the
existing registered source/route/contact projection gates. The coordinator checks
unlocked transcript access, verified current Desktop/contact/binding, exact task,
active non-private/non-paused session, cancellation, current profile, one matching
waiting action, current result owner and original outgoing row. Paused task state
and blocked unknown-effect state can retain acceptance without starting execution.
Other numeric consumers/stale task owners are not relabeled as native work.

The policy additionally requires the pending managed ledger record, exact
owner/agent/source/contact/conversation/turn/task/generation, registered route,
business identity, topic, message traffic, hashes, receipt time and final message
ID. Attachment declarations/chunks cannot acknowledge the task; an attachment
request must match its saved final-body ID. No global/latest-turn lookup.

Persist an updated waiting receipt and owned task state before returning to the
completion consumer. A failed task commit throws, so the existing completion
journal leaves the event pending for retry. A repeated already-saved acceptance
is a no-op. First acceptance does not overwrite later remote progress/status time,
complete a task, clear uncertainty, release slots or authorize fallback/execution.

Transport receipts/outbox/cryptography, UUID/Codex/team presentation, timing
thresholds and the managed-result settlement path remain unchanged. A removed,
cancelled or no-longer-current native task is ignored rather than resurrected.
This does not newly implement acceptance for all other numeric consumers or the
legacy MQTT path. It is independent of unmerged #4592/#4593 and does not include
their production deltas.

## Evidence and remaining work

Seven XCTest methods are authored only in an already registered file: exact
acceptance/Codable and unknown-effect retention, replay, later status retention,
foreign/control/chunk/consumed completion rejection, foreign managed/task scopes,
final attachment-body binding, and numeric projection/writer error propagation.
They are NOT executed.

The source checker freezes complete production files outside declared hooks,
the existing apply-before-consume ordering and transport/recovery/timing kernels.
No Swift build/typecheck, XCTest, live delivery, storage-fault/restart/device
acceptance, CI watching or IPA. Active timeout scheduling, deferred discovery,
broader transport callback coverage and full Android #3119 parity remain open.

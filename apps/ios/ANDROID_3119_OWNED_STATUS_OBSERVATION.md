# Android #3119: persist original-task observations

## Actual integration

Android reference: `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
`MainActivityConnectorTimeoutRecovery.kt`. It validates an observation against
the original pending request, records task status and persists the session before
continuing observation. iOS base: `4c7529b9c` (includes #4578).

iOS previously persisted authenticated status-query results in the Desktop
recovery ledger without updating the original native connector wait receipt.
The new projection is called after durable authenticated recovery reception on
both legacy and journal transports. Existing sweep/query loops also retry the
projection from saved recovery records, including after a failed task-state save.
Those loops do not repeat the external operation.

The projection requires the currently saved observation, current paired binding,
pending managed owner, exact source/contact/conversation/turn/task/generation,
current profile, a unique waiting plan node and matching last native result.
Only active, nonprivate, unpaused-tracking and unmerged sessions can receive it.
Paused native tasks can retain progress without resuming execution. The existing
protected-data and guarded owned-task commit boundaries remain authoritative.

Only a strictly advancing status sequence updates the remote status clock;
duplicate/older observations and malformed/backward clocks are rejected. This
does not treat each successful status poll as execution progress. Original wait
identity and result flags remain unchanged. Terminal status by itself does not
settle a result, release a slot, trigger fallback, change task phase or clear
unknown-effect/non-retriable evidence. Only observation-overdue diagnostics are
cleared on actual sequence advancement. The existing committed-result path is
still required for native continuation/fallback.

The active plan receipt, plan context, matching pending action and last native
result are saved together through the existing owned task-state API. A failed
save leaves the earlier wait intact; saved recovery data allows a later existing
sweep to attempt projection again. This is not a new cross-store transaction or
a new authentication/transport protocol. No claim is made that platform reads,
power loss, process restart or write failures have been exercised.

## Evidence and remaining work

Nine XCTest methods were authored and registered, not compiled or executed.
They cover exact scope, sequence/time rejection, managed completion containment,
unknown-effect retention, terminal-status versus result separation and waiting
receipt codec round trips. Source checks compare complete modified files outside
the declared hooks, pin the Android caller and freeze authentication, ownership,
timeout, receipt, final settlement and dispatch kernels against the actual base.

This does not add generic active pre-timeout scheduling, fresh deferred candidate
discovery, a local/cloud status-query protocol, transport-acceptance timestamp
production or broader attachment support. Observation deadlines remain passive;
silence does not prove task failure. Android #3119 and the complete parity backlog
remain incomplete. No native build/typecheck/XCTest, CI monitoring or IPA.

Checks passed: iOS project structure; changed JavaScript syntax; changed iOS
Han-text placement in localization resources; diff whitespace; owned-observation,
pre-shadow, reported-usage, live-health, provider-ranking, observation-timing,
research-context, autonomous/research source, background-cognition and live-planning
source contracts. These are not a full repository check or native acceptance.

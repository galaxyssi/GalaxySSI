# Recovery Discovery Coalescing

## Problem

Transport readiness and foreground events can request another pending-reply
discovery pass while a previous pass is already fetching the archived body.
The body is correctly absent from the inbox until validation and persistence
finish, so checking only inbox eligibility sends a redundant status query.
Body-request deduplication alone does not prevent this extra MQTT traffic.

## Ownership

`AgentRecoveryTransferRegistry` keeps one indexed current transfer lease for a
complete identity: Desktop, client route, conversation, task, turn, contact,
source message and Agent. Each lease records the authenticated execution
generation. Lookups do not scan conversations, history or all active transfers.
An older coroutine cannot remove the lease of a newer execution generation.

Automatic pending-reply discovery rechecks eligibility immediately before each
batch is sent. If a matching current-generation body transfer exists, it records
one deferred wake on that lease and leaves the task out of the discovery batch.
Other identities in the batch continue normally. Database and execution-fence
checks run outside the registry lock; a changed lease invalidates the verdict.

Manual inspection and explicit handoff recovery do not use this suppression.
No fixed cooldown, Agent action limit, message timeout or protocol change is
introduced. Existing body-page timeouts and resumable encrypted checkpoints
continue to govern stalled transfers.

## Completion and Failure

The coroutine completion handler releases ownership even when cancellation
happens before the coroutine body starts. One deferred wake is returned to the
existing readiness-aware coordinator, outside the registry lock. After success,
durable inbox/terminal checks discard the already recovered task. After failure,
the still-pending task is observable again. Offline wakes wait for readiness.

Finishing a transfer with no deferred wake does not manufacture another retry.
Repeated completion callbacks cannot replay a wake twice. Process death drops
only this in-memory optimization; durable pending delivery, task identity and
page checkpoints remain authoritative on the next process start.

## Verification Scope

The unit suite covers exact identity isolation, generation replacement, repeated
wakes, stale fence verdicts, concurrent owners, nonblocking fence checks,
cancellation before entry, success eligibility and failure/reconnect replay.
This does not by itself establish real MQTT latency or device performance.
Use the live four-phase S20U recovery test and per-device-clock timing report
for those observations; never subtract phone and Desktop monotonic clocks.

[S20U acceptance record](../performance/recovery-discovery-coalescing-s20u-20260907.md)
documents normal recovery and a live 20-wake burst, along with remaining latency
limits and the distinction between PR-branch and integrated-device evidence.

# Adaptive collaboration exchange retries

Desktop 1.4.46 uses recent authenticated response completion times to choose
when to resend a pending collaboration recall, publication or saved-tool test
request. It does not change model routing, task identity, authorization, the
original exchange deadline, durable state, Signal ordering or the user interface.

## Behavior

An unseen peer still starts with the existing two-second retry interval. Valid,
scope-matched responses update a smoothed completion time and variation margin.
Subsequent initial retry intervals stay between the existing two- and eight-second
bounds, followed by the existing capped exponential backoff. A local publication
rejection uses the original short interval because no copy was admitted. A
response timeout backs off future exchanges without extending that failed
exchange or accepting late replies.

The sample includes phone execution, transport, local queueing and possibly
retransmissions. It is not network RTT or proof of where latency originated.
Rejected identities, invalid payloads, late replies and unsolicited replies do
not train the completion estimate. State is per broker and paired client route,
in memory only, expires after ten idle minutes, and holds at most 128 entries.
A new pairing route has no inherited estimate. Recent fast responses can reduce
the interval again. Pauses, cancellation and execution-generation changes still
stop retries immediately through the existing checks.

## Verification and limits

Tests cover slow accepted replies, a lost request, local rejection, short
deadlines, cancellation, scope rejection, peer isolation, expiry, clock reset,
bounded memory, and retention of the same nonce, expiry, artifact and execution
identity across retries. Milestone and saved-tool retry tests use a controlled
clock instead of millisecond wall-clock sleeps.

In a deterministic serial-receiver model with twelve logical reads, a half-second
arrival delay and two-second service time, the previous schedule emits 24 copies;
the adaptive schedule emits 13. Both complete without timeouts; simulated total
time is 46.5 versus 31.5 seconds. This verifies reduced retry amplification in that
model, not a measured phone speedup or a cure for arbitrary receive stalls.

The change reduces unnecessary work while preserving loss recovery. It does not
remove the underlying per-message receive cost or prove that all queue stalls,
broker faults or full research delivery failures are fixed. Full concurrent
phone research acceptance remains a separate verification step.

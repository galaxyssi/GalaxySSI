# Collaboration Exchange Replay

Android 1.4.94 adds bounded, ephemeral reply replay to authenticated remote
collaboration recall and interim publication. It does not change a wire contract,
model, UI, task budget, concurrency setting or goal acceptance criterion.

## Behavior

- Identical retries while a request is active do not start a second handler.
- A successful response is copied before publication. If its response is lost,
  the same request can replay the original result instead of repeating evidence
  import, page preparation or milestone processing.
- The original evidence delivery challenge is retained. Replay does not credit
  read coverage; the existing authenticated confirmation remains mandatory.
- Publication replay never finishes the author's assignment or validates its
  claims. Only a committed milestone can wake the existing live graph.
- Fresh pairing, registered/current task, run control, membership, pending-owner
  and immutable evidence binding checks still apply. A cached body is returned
  only for the exact current binding, including dependencies and pinned grants.
- While its record is retained, reusing a nonce with changed semantic selectors, phase, expiry, scope or
  delivery challenge is rejected. JSON key order and transient transport
  metadata do not change a request's semantic fingerprint.
- At most four active handlers and 128 completed replies / 4 MiB are retained
  per endpoint. Replays use the same handler capacity. These are transient RPC
  resource bounds, not limits on research steps or stored evidence.
- Cached replies are eligible only within the original request lifetime (at
  most 60 seconds). Admission never extends that deadline. Expired entries are
  pruned on cache access; the oldest retained replies yield to new entries.
- Unavailable/failed responses are not frozen. Process loss, cache eviction or
  oversized replies fall back to the existing fresh-read/durable-publication
  behavior. This memory cache does not replace publication idempotency.
- No outbox, autonomous retransmission loop or new heartbeat is added. The
  existing caller still owns transport retries.
- Unexpected milestone-handler failures describe the actual operation. Failed
  capability/list reads say that no artifact was submitted; only publication
  reports an uncertain commit and directs an identical-ID retry.

`GalaxySSIExchange` logs content-free phase observations: admission, scope
resolution, response readiness, local publish acceptance/rejection, expiry,
changed authorization and handler failure. Only an opaque peer/request digest,
allowlisted mode/phase, stage and elapsed time are logged. Local publication
acceptance is not peer delivery. No argument values, research payloads, raw
peer identities, model thoughts or exception messages are included.

## Checks

`CollaborationExchangeReplayTest` covers lost-response replay, immutable copies,
scope/selector collisions, transport metadata, fresh access binding, bounded
active work and replay capacity, expiration, UTF-8 memory bounds, process loss,
concurrent duplicate admission and diagnostic redaction.

`CollaborationExchangeReplayDeviceTest` injects a lost response after a real
encrypted workspace commit, reopens that workspace, and replays an original
evidence page without preparing another challenge. Coverage remains zero until
the explicit confirmation commits. All inputs are local synthetic fixtures;
this test uses no model, broker, contact or physical action.

Existing recall-delivery, publication, milestone dispatch and scoped-recall
tests remain applicable. Live MQTT exchange under concurrent real model work
is a separate acceptance step. These checks do not establish that every
previous timeout is repaired, nor prove scientific correctness, peer
comprehension or a multi-agent advantage.

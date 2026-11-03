# Long-Lived Collaboration Mailbox

## Problem

The encrypted team mailbox previously rewrote one JSON array and retained only
its last 5,000 records. A busy newer run could evict an older unanswered peer
request, its provenance, or the identity needed to deduplicate a replay. Reads
and receipts also decrypted and rewrote unrelated historical messages.

## Storage Contract

- Each message has its own encrypted row and a durable global identity lookup.
- Run-local sequence counters, message bodies and pending indexes are committed
  atomically. Concurrent in-process wrappers share the same critical section.
- Pending indexes are scoped by run and recipient. Eligible member dispatches
  read these indexes instead of reloading acknowledged history or other teams.
- Delivery and acknowledgement remove pending indexes, not historical content.
- Explicit history reads retain sequence order and support `afterSequence`.
  Storage key pages are bounded; page size is not a retention or delivery cap.
- An explicit scoped clear deletes only that run and its identity lookups. A full
  clear does not cause legacy records to reappear on reopening.
- The existing encrypted database is migrated atomically on first use. All
  retained v1 records are checked before committing v2 rows and removing the v1
  snapshot. Unsupported, altered, corrupt or duplicate legacy records cause an
  explicit error and leave the original snapshot untouched.
- Unreadable ciphertext is an error, not an empty mailbox that can be overwritten.

There is no implicit age/count eviction. Available device storage remains finite;
failed writes surface as errors. This cannot reconstruct records already evicted
by an older app version. Explicit all-history callers still materialize a list;
the latency-sensitive member dispatch path reads only pending recipient rows.
Large unread backlogs still need context-budget-aware scheduling; preserving a
record does not prove that a model read or acted on it.

This changes local team mail storage only, not contact/MQTT outboxes, provider
selection, group membership, permissions, wakeup policy or the existing global
broadcast receipt semantics. The critical section is process-scoped; this does
not establish a multi-process writer protocol or mid-model-call delivery.

## Verification

`IndexedAgentTeamMailboxTest` covers 10,000 messages, old pending requests in a
different run, full retained history, monotonic sequence across reopen, replay
deduplication, short key pages, recipient/broadcast filtering, monotonic receipts,
atomic failure, concurrent wrappers, scoped clearing and corrupt input rejection.
Read/write counters verify that one pending lookup and one append do not scan or
rewrite thousands of acknowledged rows. A runtime regression fails if member
dispatch tries to call the all-history API.

`AgentTeamMailboxStorageDeviceTest` uses isolated encrypted stores to cover
migration of 5,005 records, ciphertext failure, and SQLite transaction rollback
followed by retry. `CollaborationResultFinalizerDeviceTest` additionally covers
concurrent encrypted wrappers and late peer requests. Device fixtures require an
authorized phone; compilation is not a device-test pass.

These are persistence and information-fidelity results, not evidence of novel
ideas, capability growth or multi-agent superiority. Real studies must still
trace a peer contribution through an executable revision, independent outcome,
fresh-task transfer and retention.

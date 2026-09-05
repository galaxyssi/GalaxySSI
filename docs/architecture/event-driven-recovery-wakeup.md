# Event-driven reply recovery wakeup

Android recovery previously depended on idle startup maintenance and structured
handoffs. Startup maintenance intentionally defers while a foreground task or
reply indicator is active. That is appropriate for optional maintenance, but not
for retrieving the answer that the foreground task is waiting for. MQTT reconnect
previously only updated UI status indicators.

## Independent read-only path

Broker connection transitions and secure-channel readiness now wake a process-owned
IO coordinator in the transport layer, even when no Activity is attached. Foreground
resume and the existing liveness assessment also wake it. Optional maintenance and
live Run ownership rules remain unchanged; this path does not resubmit tasks, start
models, execute tools, or fabricate Run/Handoff records.

The coordinator reads pending deliveries from the encrypted SQL journal, newest
first, with a source-ID cursor and at most 32 bodies per page. Direct-chat fast paths do not require a
structured Handoff to participate. Each candidate uses the existing registered
task identity and current paired Desktop route. Failed/cancelled/superseded requests,
already saved answers, and local-only cognition/evolution conversations are excluded.
Verified completed observations invoke the paged final reply recovery introduced
by the preceding PR. A failed observation batch does not abort later batches.

## Event semantics

- Offline wakes are retained without emitting requests into an offline outbox.
- Repeated unchanged connection notifications are not heartbeats.
- A wake arriving while observation is running is coalesced into a follow-up pass,
  not silently dropped by an in-progress flag.
- At most one observation pass runs per coordinator. Completion ownership prevents
  an old worker callback from clearing a newer worker's state.
- Failure waits for another lifecycle/transport/liveness event. It does not create
  a hot retry loop or periodic model calls. Scope cancellation releases ownership.
- Recovery callbacks perform no disk or network work on the UI thread.

## Remaining work

The follow-up [durable pending reply journal](durable-pending-reply-journal.md)
removes the legacy full-key snapshot from steady-state recovery and makes pending
body/turn-pointer updates atomic. Its one-time legacy import still reads existing
preferences ciphertext. Full recovery latency at large pending counts, including
network observation and result retrieval, is not proven by database page tests.

This wakeup does not complete remote failure-result replay, every execution path's
state reconciliation, persistent page checkpoints, or real paired-device recovery
acceptance. S20U tests use isolated pending preferences and do not change real
contacts, pairings, messages or remote tasks. Production paired loss/reconnect tests
still require the new Desktop build to be running.

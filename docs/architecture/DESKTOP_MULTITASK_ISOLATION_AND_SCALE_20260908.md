# Desktop Multi-App, Conversation and Task Isolation and Scaling

## Conclusions and Boundaries

The goal is to isolate tasks from different Apps, define explicit semantics for consecutive turns in one conversation, keep tasks running after their windows close, and progressively admit and schedule 1,000/10,000 tasks.

Measure admitted tasks, queued tasks, executing workflows, requests waiting on remote models, and tasks consuming local CPU/GPU separately. Supporting 10,000 persistent task records does not mean a T14 can simultaneously run 10,000 Codex CLI/model instances. Actual 10,000-way execution requires corresponding compute nodes, model-service quotas and network capacity.

This document is based on repository inspection, isolated reproduction in temporary directories, and real SM-T575 tests. The capacity and acceptance requirements below are development targets, not achieved results.

## Existing Foundations

- `mqtt_bridge._scoped_agent_conversation_id()` combines the paired client's identity fingerprint (or route as a fallback) with the App conversation ID, optionally adding the Agent instance. Cross-App isolation is not entirely absent today.
- `_remote_task_identity()` requires complete route, conversation, task and turn fields, and verifies that the request route matches the identified sender.
- `_task_control_matches()` jointly checks route, conversation, task, turn, contact and source message to prevent cancellation or approval controls from affecting another task.
- `AgentConversationSessions` already provides native model-session bindings and conversation locks. Codex has thread/turn mappings, busy checks and execution-recovery information.
- `AgentTaskManager` already has persistent task state, execution generations, events and recovery. Do not replace these with an incompatible new "current task" variable.

## Two Reproduced and Fixed Isolation Defects

### Late Output Entering the Next Turn

Previously, when `CodexAppServer._handle_event()` could not find a turn mapping, it selected the last unfinished task on the thread. An isolated experiment sent a `retired-turn` text event to a thread already running `current-turn`, and `STALE_OUTPUT` entered the current task's output.

The fix rejects attribution when an explicit turn does not match or a mapped turn belongs to another thread. Thread fallback for events without a turn must identify exactly one task, not the "latest task". Only `turn/started` may establish the initial mapping for a unique pending run; ordinary text events from unknown turns cannot establish mappings.

This fixes the reproduced path; it is not a complete formal proof for every native provider event protocol. Retired-turn tombstones, startup-handshake correlation and cross-process generation fencing remain necessary.

### Premature Replacement of a Conversation Lock

Previously, `delete()`/`delete_conversation()` removed a lock from the registry even while an old task still held it. A new request could then acquire a different lock, allowing two critical sections for the same conversation.

The fix uses a weak-reference lock registry and no longer actively removes referenced locks. A lock can be reclaimed only after holders and waiters release their references. Initial session binding in `ensure()` now checks and creates atomically. Tests cover 100 concurrent ensure requests and 10,000 sequential lock creations, uses and releases. The latter tests lock-resource reclamation, not 10,000 real concurrent model calls.

Whether an old task can recreate a binding after conversation deletion still requires conversation generations/tombstones. Fixing lock identity does not complete the deletion lifecycle design.

## Required Identity Hierarchy

| Level | Meaning | Rule |
| --- | --- | --- |
| principal / paired App instance | Authenticated App principal and installation instance | Derived from pairing, not identity claimed in message content; route/alias is an address, not authority |
| conversation_id | User-visible conversation | Unique within the App principal; window IDs do not determine task ownership |
| conversation_branch_id | Independent context branch in one conversation | Used for explicit independent parallel tasks; do not concurrently mutate the same native model context |
| client_turn_id / turn_seq | One immutable user input and its order | Each follow-up has its own turn ID and does not overwrite the previous input |
| task_id | Work objective spanning multiple inputs | Additional constraints can target an existing task; one turn can also create multiple subtasks |
| run_id / attempt_id | One actual execution attempt | Retry, recovery and handoff require a new attempt identity |
| execution_generation | Version of execution ownership | Old workers, responses and cancellations cannot affect a new execution generation |
| provider thread_id / turn_id | Native identifiers from Codex, Claude and other providers | Adapter mappings only; they do not replace App/task identity |
| event_id / event_seq | Event idempotency and ordering | Independently increasing for each run; arrival time cannot determine ownership |

Use structured tuples or domain-tagged hashes for internal keys instead of concatenating IDs that may themselves contain separators. Store original logical IDs, authenticated principals and delivery addresses separately. Whether identity restoration onto another installation should share conversations needs an explicit product decision; a matching fingerprint must not implicitly share a running model session.

## Consecutive Messages in One Conversation

A new message must enter an explicit input operation rather than unconditionally merging into a "current task":

1. `enqueue`: the normal next turn. Persist it in the conversation queue and read context only after the previous turn commits its result.
2. `steer`: add requirements to a running task. Carry the target task, run/generation and expected turn, and record where the requirement was applied.
3. `branch`: start independent work within the same UI conversation. Use an independent native thread/context branch and keep the result bound to its task.
4. `cancel/pause/resume`: operate on one exact execution version, not the "last task" or every task belonging to an App.
5. `supersede`: explicitly replace an old objective. Keep old results in history if appropriate, but never let them overwrite the new objective's state.

An existing natural-language classifier can recommend an operation, but cannot establish authenticated identity or be the sole ownership signal. When several tasks are running and no target is selected, ambiguous "continue" or "pause" requests need clarification. If the UI already selects a task, it supplies the target ID without requiring the user to type it.

Multiple independent windows displaying one conversation are views of the same logical conversation. They share messages and task state while keeping drafts and scroll positions independent. Sends carry client-message idempotency keys; Desktop assigns conversation sequence numbers. Conflict resolution must not depend on which window most recently received focus.

## Scheduling Paths to Unify

There are currently at least two execution entry points: the MQTT `AgentTaskManager` path and the Desktop Agent Runtime worker pool. Changing one pool's concurrency setting cannot constrain all entry points.

Recommended structure:

```text
Authenticated ingress -> identity/idempotency checks -> durable admission transaction
                                                              |
                                                   tenant-fair queues
                                                              |
                                             conversation/branch ordering
                                                              |
                                    global + provider + tool resource budgets
                                                              |
                                                bounded executors/workers
                                                              |
                                         result commit + transactional outbox
                                                              |
                                             MQTT delivery and App inbox
```

- Different Apps have independent queue limits, active budgets and rate limits. One App's bulk workload must not displace another App's interactive tasks.
- Submit only one mutable turn per context branch by default. Independent branches can run concurrently; writes to shared workspaces also require workspace/resource locks.
- Use hierarchical fair scheduling and priority aging. Cancellation, approval and interactive steering need a separate control-channel budget so they do not queue behind bulk output.
- Budget model processes, network requests, terminal tools, browser/desktop control, GPU jobs and attachment transfers separately; one `max_tasks` limit is insufficient.
- Release unnecessary workers when tasks pause or wait on users/networks. Keep state in the database rather than dedicating a waiting thread.
- Multi-node execution needs leases and fencing tokens so old executors cannot commit new results after restart. Side-effect tools need idempotency keys, operation receipts and compensation; do not promise inherent exactly-once behavior over a network.

## Known Bottlenecks at 10,000-Task Scale

1. `AgentTaskManager.create()` starts a thread per task; ordinary `_run()` also creates heartbeat and watchdog threads. This cannot scale proportionally to 10,000. Use a shared scheduler and bounded worker pools.
2. The Codex stdout reader synchronously invokes event handlers and callbacks. Persistence, publishing or model initialization in callbacks may delay other conversations. The reader should parse into bounded queues consumed by run partitions; normal progress traffic must not block protocol responses.
3. Codex thread startup/recovery holds a shared lock while waiting on requests. Separate short mapping updates from slow I/O, with per-conversation startup reservations preventing duplicate creation.
4. `AgentConversationSessions` rewrites its entire JSON file on each save. At 10,000 conversations, move to indexed row-level persistence and incremental updates rather than rewriting the whole table per token.
5. Some active-run lookups and queue-depth calculations scan in-memory collections. Maintain bounded active indexes and counters, and page historical tasks.
6. Coalesce progress and apply backpressure while reliably preserving terminal states, approvals and errors. Do not trigger a complete snapshot, disk write and MQTT publication for every token.
7. Public MQTT broker capacity and ACLs are outside application control. Production at 10,000-task scale cannot assume that throttling will not happen; provide observable capacity tests and controlled broker/gateway deployment options.

For example, 10,000 tasks each emitting two 1 KiB progress events per second produce approximately 20.48 MB/s of payload alone, excluding encryption, headers, retransmission and downlink traffic. Scaling requires eliminating unnecessary events, not merely increasing bandwidth.

Visible foreground tasks can update more frequently as needed; background tasks can coalesce state over several to tens of seconds. Choose actual intervals from real interaction and packet-loss tests. Preserve independent run sequences and gap recovery; never trade away terminal states for smoothness.

## Separate State and Delivery Dimensions

Transport, execution, result receipt and UI projection are four distinct dimensions. For example:

```text
Transport ACK not received
Execution COMPLETED
Result already in App durable inbox
UI not yet restored
```

This does not mean the message was undelivered. The Android fix in this increment prevents late transport failure from overwriting an already-received result. Model-startup timeout is a legitimate execution failure, not a send failure, and must not count as task success.

## Phased Delivery

### P0: First Establish Correctness at 10-Way Concurrency

- This increment completes late-failure protection, explicit turn-event isolation, lock identity and initial-binding fixes.
- Complete the cross-App isolation matrix for identical conversation/task literals and cross-authorization tests for cancellation, approval and retry.
- Implement explicit enqueue/steer/branch protocols and UI action ownership within a conversation.
- Diagnose real stress-test thread/start and turn/start timeouts; retain queueing, startup, first-token, terminal, inbox and display timings separately.

### P1: Controlled 100-Way Execution

- Unify admission and capacity accounting across entry points: durable queues, per-App fairness, bounded workers and event coalescing.
- Separate the Codex reader from heavy I/O and budget initialization, cancellation and heartbeat capacity independently.
- Measure latency, memory, throughput and recovery using real workflows, not merely the simultaneous creation of 100 Task objects.

### P2: 1,000 Workflows

- Incremental conversation/task storage, leases/fencing, process isolation, sharded workers, crash recovery and resource release.
- First test 1,000 mixed running/waiting workflows, then raise real in-flight model requests within actual provider quotas.

### P3: A 10,000-Task Network

- A single node performs bounded admission and routing while multiple nodes execute; choose a shared transactional database and controlled broker for the data scale.
- Sharding keys preserve ordering within an App/conversation branch; node migration does not alter logical identity.
- State hardware, account quotas, workload, fault injection, costs and SLO conditions before claiming capacity. Do not promise that one computer can run any arbitrary 10,000 heavyweight local-model tasks simultaneously.

## Required Test Matrix

- Multiple Apps use identical conversation names, local IDs and models; verify isolation of output, files, approvals and cancellation.
- Send A, add constraints to A, then independently send B in one conversation. Out-of-order A/B results must retain correct task ownership.
- Inject an old delta, completion and approval after an earlier turn finishes; the new turn must remain unchanged.
- Deliver one message 100 times and create only one logical request; a retry is a new attempt, not a new user turn.
- Cancellation/results from an old generation must not affect a recovered new generation.
- Delete/recreate conversations, disconnect Apps, close windows, restart Desktop, contend on the database and reconnect the broker.
- Use 100/1,000/10,000 controlled lightweight workflows to test scheduling and storage; report real-model throughput and success rates separately.
- At each stage require zero cross-principal misattribution, no unbounded queues and no thread/lock/process leaks, with uncovered cases reported separately.

Current conclusion: evolve the existing system rather than rewrite it wholesale. Reaching 10,000-task scale requires scheduler and state-storage upgrades, not a single concurrency-parameter change.

## Verification Recorded in This Increment

- 63 Desktop isolation/session unit tests passed, plus 32 MQTT task-turn, cross-App routing and intervention tests: 95 total. New reproductions establish that old-turn text no longer enters the current task and conversation deletion does not replace a still-held lock.
- 100 concurrent ensure requests produced one binding; 10,000 sequentially released conversation locks left no residue. This was not a 10,000-way concurrent execution test.
- SM-T575 ran Android 1.1.4 (890). All 17 inbox/late-failure regressions passed. All 10 real background requests received and retained their results (10/10), without the previous false undelivered status.
- Only 5/10 real tasks completed. The other five hit thread/start or turn/start timeouts in the running Desktop, so strict 10-way success acceptance still failed. Resolve those startup bottlenecks before increasing scale.
- Desktop source was raised to 1.1.5; this increment did not replace the running Desktop. Unit tests do not substitute for deployed end-to-end MQTT verification.

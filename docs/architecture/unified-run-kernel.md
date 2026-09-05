# Unified Event-Sourced Run Kernel

GalaxySSI uses `galaxyssi.agent-run-event.v1` as the portable lifecycle contract
for Android and Desktop Agent Runs. iOS migration is deferred. The JSON Schema is stored at
`core/protocol/agent-run-event-v1.schema.json`.

## Identity boundary

Every event carries the complete execution identity:

- `client_route_id`
- `conversation_id`
- `goal_id`
- `task_id`
- `run_id`
- `turn_id`
- `action_id`

The first five fields form the immutable Run root. A store must reject a later
event that attempts to reuse a `run_id` across another route, conversation,
goal, or task. Turns and actions may advance inside that root, but remain
explicit on every event so replies, tools, checkpoints, and artifacts cannot
move to another conversation by accident.

## Event guarantees

- Events are append-only and receive a strictly increasing sequence per Run.
- `idempotency_key` identifies one semantic event across retries and process
  recreation. Replaying it is a no-op; reusing it for different content is a
  conflict.
- Terminal Runs reject late events. `RUN_RECOVERED` is the only event that can
  explicitly reopen one.
- `CHECKPOINT_SAVED` records durable progress without changing the active state.
- `RUN_INTERRUPTED` is recoverable and distinct from a verified failure.
- Older mobile events without v1 identity fields are canonicalized with stable
  fallbacks when decoded, then persisted in the v1 shape.

## Persistence and projections

Desktop stores the authoritative lifecycle in an append-only SQLite WAL ledger.
The low-level Runtime Server and high-level `AgentTaskManager` both project
their lifecycle into that ledger. The Runtime Server writes its recovery
checkpoint in the same transaction as each event. It can reconstruct missing
JSON projections, terminal results, and session ownership from the ledger.
Only recoverable Runs and a bounded recent window are loaded at startup.
The optional `payload.projection_checkpoint` contains a namespaced `kind` and
JSON `data`. Its indexed materialization commits or rolls back with the event;
ordinary tool `checkpoint` fields are not interpreted by the ledger.
The high-level task table still owns task inputs and resubmission data; its
atomic migration to the kernel is a separate remaining integration step. Complete
high-level task history can be replayed in pages through the loopback-only
`/api/agent/tasks/{task_id}/run-events` endpoint even after its UI event cache
has discarded older rows.

Android uses an encrypted append-only SQLite WAL ledger. Each event is
stored as a separately authenticated ciphertext, while hashed Run and
idempotency keys preserve indexed lookup without exposing those identifiers at
rest. Existing encrypted Android records are migrated once into the new row
store. UI and recovery models read projections;
they do not replace or truncate ledger history.

The event ledger is not a chat transcript and must not be sent through MQTT as
bulk state. Transports carry only newly requested events or compact snapshots.
Large outputs and artifacts are referenced by identity and belong to their
dedicated data stores.

## Recovery

On process restart, stores replay events in sequence, derive the last state, and
surface non-terminal Runs for recovery. A queued or running Desktop Run is
closed with `RUN_INTERRUPTED`; a coordinator may then append `RUN_RECOVERED`
after confirming the external Agent or checkpoint can safely continue.

The shared contract is the migration boundary for replacing legacy platform
state machines. New lifecycle behavior must be written as Run events first;
UI, session, task, and health records are projections of those events.

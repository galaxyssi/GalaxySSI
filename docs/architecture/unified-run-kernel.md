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
The high-level task table owns task inputs, attachments, resubmission data, and
chunked results in the same database. Each task save commits its event, task row,
and output chunks in one transaction. Failed saves roll back the live task
projection to its durable state before propagating the original error. Prompts
and complete results are not copied into every lifecycle event. Complete
high-level task history can be replayed in pages through the loopback-only
`/api/agent/tasks/{task_id}/run-events` endpoint even after its UI event cache
has discarded older rows.

The default database is `agent-run-events-v1.sqlite3` under `GALAXYSSI_STATE_DIR`,
or under `%APPDATA%/GalaxySSI` when no explicit state directory is configured.
The Runtime Server and task manager use the same storage-path helper.
Legacy `~/.galaxyssi/agent_tasks.sqlite3` and its sibling Run ledger are imported
read-only into this database. Tasks, output chunks, events, checkpoints, and the
one-time migration marker commit together; original files remain intact.
Conflicting identities or corrupt result chunks abort the whole import. Completed
migrations are not replayed, including after a task has been deleted. Downgrading
to a version that writes the legacy files is not a supported synchronization path.
Explicit task-store paths remain supported, with their ledger in the same file.

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

Process-crash tests cover exits after the event write, after the task/chunk write,
after transaction commit, and during legacy migration. SQLite WAL retains the
existing `synchronous=NORMAL` policy: these tests establish process-crash atomicity,
not durability of the newest committed transaction after a hard power loss.
They also do not establish exactly-once external tool side effects or automatic
resubmission of an interrupted provider request.

The shared contract is the migration boundary for replacing legacy platform
state machines. New lifecycle behavior must be written as Run events first;
UI, session, task, and health records are projections of those events.

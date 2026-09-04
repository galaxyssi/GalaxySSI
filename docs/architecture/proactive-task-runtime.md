# GalaxySSI Proactive Task Runtime

The proactive task runtime turns one-shot Agent requests into durable, inspectable automation on Android and Desktop. It is a clean-room GalaxySSI subsystem rather than a wrapper around a third-party scheduler.

## Product contract

A task combines one trigger, one action, one execution policy, and one delivery policy.

Triggers:

- manual
- Cron with an explicit IANA time zone
- fixed interval
- goal checkpoint
- signed webhook

Actions:

- one selected Agent
- a bounded sub-agent team
- a saved workflow
- a native platform tool

Trigger and action definitions are independent. The same scheduled trigger can therefore run an Agent, invoke a native tool, or dispatch a workflow without creating separate scheduling systems.

The portable data contract is defined in `core/protocol/proactive-task-v1.schema.json`.

## Durable execution

Desktop stores tasks, runs, replay nonces, and structured events in SQLite with WAL enabled. Android stores encrypted task and run records and schedules wakeups through `AlarmManager`.

Both runtimes provide:

- stable task identity and revision numbers
- bounded retries with exponential backoff
- per-task concurrency limits
- maximum run and consecutive-failure limits
- charging and network constraints
- idempotent occurrence recording
- bounded misfire catch-up
- cancellation
- process and device restart recovery
- persistent run history

Cancellation is terminal. A late Agent or tool response cannot overwrite a cancelled run.

## Scheduling semantics

Cron uses five fields and an explicit IANA time zone. Day-of-month and day-of-week follow Vixie Cron OR semantics when both are restricted.

Misfire policies:

- `skip`: record missed bounded occurrences without executing them
- `fire_once`: collapse missed work into one execution
- `catch_up`: execute at most the configured catch-up limit

Deterministic jitter can spread synchronized workloads without changing interval cadence. Goal checkpoints repeat until the final responder emits a machine-readable complete state, after which the task disables itself.

## Agent and team execution

A single Agent task uses the same supervised team controller as a multi-Agent task, with one lead member. This provides one cancellation, status, and result contract for every Agent execution.

A sub-agent team requires exactly one lead. Executors and observers gather bounded evidence in parallel. Verifiers review the proposed result. Only the lead can produce the final response. Member failures are isolated and recorded instead of silently stopping the whole task.

Desktop teams coordinate through durable Agent collaboration channels:

- direct channels connect exactly two participants
- broadcast channels distribute evidence to a bounded task team
- repository channels bind the team to a one-way hash of the canonical repository path

Every channel is isolated by paired client route, conversation, task, participant identity, and optional repository identity. Messages are append-only, content-addressed, cursor-readable, and acknowledged only after an Agent successfully processes them. Channel content is always attached as bounded untrusted evidence; it cannot grant permissions or execute tools. The lead remains the only final responder.

Webhook payloads are untrusted evidence. They are bounded, filtered, and clearly separated from trusted task instructions before reaching an Agent.

## Webhook security

Desktop webhook requests require:

- a per-task derived secret
- HMAC-SHA256 over timestamp, nonce, and body digest
- a five-minute replay window
- a unique nonce
- a 256 KiB body limit
- optional nested event filters

Remote Desktop-to-Android webhook delivery is accepted only from an actively paired GalaxySSI Link identity. Android also deduplicates the remote event ID before creating a run.

Webhook credentials are returned only when a task is created or explicitly rotated. Regular list and read responses omit secrets.

## Recovery and failure policy

Runs distinguish queued, running, waiting, retrying, completed, failed, cancelled, and skipped states.

Temporary Agent, network, and delivery failures may retry within the task budget. Invalid configuration, missing workflows, blocked tools, exhausted retries, deadlines, and repeated failures produce durable terminal states. Restart recovery marks interrupted Desktop runs as retrying and restores pending Android wakeups.

Every Desktop state transition emits a structured event. Paired clients can receive those events without polling the task database.

## Delivery

All results remain available in run history.

Delivery modes:

- `store`: history only
- `notify`: store and surface a private local notification
- `mobile`: store and deliver to the selected paired mobile route

Android lock-screen notifications expose only a generic public version. Task details remain private.

## Management surfaces

Android exposes task creation, editing, run history, immediate execution, cancellation, pause, resume, and deletion in Automation.

Desktop exposes the same lifecycle in Capabilities > Automation. The editor shows only fields relevant to the selected trigger and action and supports both create and update flows.

## API surface

Desktop local APIs:

- `GET /api/proactive/tasks`
- `POST /api/proactive/tasks`
- `GET /api/proactive/tasks/{task_id}`
- `POST /api/proactive/tasks/{task_id}`
- `DELETE /api/proactive/tasks/{task_id}`
- `POST /api/proactive/tasks/{task_id}/trigger`
- `POST /api/proactive/tasks/{task_id}/rotate-webhook`
- `GET /api/proactive/runs`
- `GET /api/proactive/runs/{run_id}`
- `POST /api/proactive/runs/{run_id}/cancel`
- `POST /api/proactive/webhooks/{task_id}`
- `GET /api/agent-runtime/channels`
- `POST /api/agent-runtime/channels`
- `GET /api/agent-runtime/channels/{channel_id}/messages`
- `POST /api/agent-runtime/channels/{channel_id}/messages`
- `POST /api/agent-runtime/channels/{channel_id}/ack`

Local management APIs require both a loopback origin and the random Desktop process token held behind Electron IPC. The webhook endpoint uses its task-specific signature contract.

# Codex Provider Usage Audit

Desktop v1.4.11 records content-free Codex App Server usage observations in an
encrypted, append-only journal alongside the existing task store. This is an
accounting evidence increment, **not exact per-request budgeting or billing**.
It does not enable the closed-book live pilot for remote Codex.

## What Is Observed

The adapter accepts the official `thread/tokenUsage/updated` notification and
records `turn/started` and `turn/completed` lifecycle markers separately. See
[Codex App Server turn events](https://learn.chatgpt.com/docs/app-server#turn-events).
The installed CLI's `app-server generate-json-schema` command can verify the
notification schema without starting a model or making an API request.

The observed schema contains `threadId`, `turnId`, and `tokenUsage`, including
`total`, `last`, and an optional context-window value. Counters include input,
cached input, optional cache-write input, output, reasoning output and total
tokens. Missing or invalid counters remain null with bounded diagnostic codes;
zero remains zero. Inconsistent subcounts are retained and flagged, not repaired
by inventing values. Unknown payload properties, prompts, tool results and raw
error strings are not persisted.

Important distinctions:

- `total` is a provider **thread cumulative** snapshot, not a task total.
- `last` is the provider's last usage snapshot, not a uniquely identified API
  response. The notification has no response ID or exact request count.
- Snapshots must not be summed. Cached/reasoning fields must not be added again
  to parent counters to manufacture total usage.
- Requested model and effort are recorded. The actual served model, internal
  request count, billed cost and task token total remain **unknown/null**.
- Identical observations are deduplicated. The journal entry count is neither a
  model request count nor necessarily the number of wire notifications received.
- Lifecycle completion does not prove every usage notification was received.

The existing estimated execution-harness counters remain separate and unchanged.
Provider history completeness is always false for this notification-only adapter.
Exporting an empty journal is not proof of zero usage or zero cost.

## Reported Model Changes (v1.4.14)

The same journal now accepts the official `model/rerouted` event with exact
`threadId` and `turnId`. It saves only bounded `fromModel` and `toModel` identifiers
as `reported_from_model` and `reported_to_model`; arbitrary reason text and
unknown payload fields are not persisted. Invalid model fields remain null with
diagnostic codes, while the fact that a reroute was reported is preserved.
The existing `actual_model` stays null: a notice about part of a turn is not
proof of the actual model serving every request in the whole turn or trial.

This is an additive `model_rerouted` observation under the existing journal
contract. The adapter routes it through the existing exact-turn ownership check,
execution-generation fence and encrypted, deduplicated store. It does not rewrite
the selected model, replay a task, refresh progress/watchdog clocks, send a new
MQTT message or interrupt normal task completion. The notification is a queue
barrier and is never coalesced into an adjacent text delta.

The private trial collector and usage auditor flag `provider_model_reroute_observed`
and set `model_control_status` to `reroute_observed`. Such a trial must not be
pooled as a fixed-model result. They preserve all original observations and
completed/failed task states, not relabel a successfully delivered answer as an
execution failure. Returning to the requested model later does not erase the
intermediate change. Malformed notices also remain an explicit control issue.

Without any recorded notice the status is `not_attested`, **not verified**.
Old records were collected before this event was handled and cannot retrospectively
prove that no fallback occurred. Missing notices, eviction, disconnect and audit
write failures can still leave coverage incomplete. This change does not provide
request-level model attestation, whole-trial token totals, billing, or stop a
provider's internal routing; it prevents observed changes from being silently
treated as controlled observations.

## Identity, Durability And Failure

Routing requires the exact provider thread and turn; a reused thread alone is
insufficient. Storage also requires all seven GalaxySSI identity fields and the
current execution generation. The local writer cannot bypass worker reservations
or an execution-generation fence. A finished execution may receive a late usage
snapshot without changing its task state, while the exact run and callback are
still retained. Late events after run eviction, a repair-turn replacement,
disconnect or process death may be unavailable. There is no retrospective backfill
from provider history in this increment.

Each immutable entry has a content-derived event ID, monotonic scope-local
sequence, local receipt timestamp, SHA-256 digest and authenticated encryption
using the existing device-bound state key. A single SQLite transaction implements
deduplication and insertion. Deleting the owning task cascades to its journal;
this is not an independently permanent archive. Export evidence before cleanup.
An existing journal with a missing state key fails closed instead of generating
a replacement key and presenting the old observations as an empty report.

Usage-only events do not enter chat progress, MQTT result delivery, watchdog
heartbeats, checkpoint progress or task completion/retry handling. Storage errors
emit a generic warning and leave execution unchanged. They do not retry a model
or resurrect a task. Failed audit writes can leave coverage incomplete and are
not converted to successful zero-cost receipts.

Persistence is synchronous metadata-only work with a two-second database lock
timeout, not a new model call. It does add disk work; production latency, sustained
load and crash/power-loss testing remain to be measured. Unit tests are not proof
of zero performance impact or physical power-loss durability.

## Private Offline Export

For an entire Android trial rather than one task generation, use the
[remote trial collector](CODEX_TRIAL_CAPTURE.md). It retains all scoped
assignments and observed generations, including failures and missing work.

Run on the same host/user with access to the existing device-bound state key.
No Desktop restart, device operation or model invocation is needed. The SQLite
connection uses read-only mode; SQLite may still create WAL/SHM sidecar files.
Existing secure-state key recovery behavior is unchanged.

Keep the scope file and output **outside Git**. The exporter refuses any output
inside a Git repository/worktree and refuses to overwrite an existing file.
The private scope JSON contains the exact values of:

```json
{
  "client_route_id": "paired-phone-route",
  "conversation_id": "phone-conversation",
  "task_id": "desktop-task",
  "turn_id": "phone-turn",
  "contact_id": "paired-codex-contact",
  "source_message_id": "phone-source-message",
  "agent_id": "codex",
  "execution_generation": 1
}
```

From `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python -m codex_usage_export --database C:\PrivateResearch\state\tasks.db `
  --scope C:\PrivateResearch\scope.json --output C:\PrivateResearch\usage.json
```

Use the actual task database path; the command above is an example, not the
runtime's default location. Export pages share the first page's sequence upper
bound, so later appends are not silently included. The export validates entry
integrity and sequence continuity, includes a digest of the exported entries,
and retains the explicit unknown/completeness fields. This does not prove the
provider stream itself was complete or that the host is tamper-proof.

## Validation And Remaining Work

Focused tests cover strict counters, redaction, wrong thread/turn rejection,
late callbacks, lifecycle markers, unchanged progress clocks, failure isolation,
all identity fields, generation fencing, worker reservations, encrypted tamper
detection, atomic rollback, concurrent duplicate delivery, restart reads,
pagination, bounded export and refusal to write private audits into Git.

Still required before a budget-controlled remote Codex research trial:

1. Auditable per-response/attempt identity and provider-history reconciliation.
2. Admission or cancellation enforcement for internal requests, including retry
   and citation-repair work, rather than only counting top-level tasks.
3. Actual served-model provenance and independently verified billing when needed.
4. Authorized end-to-end, sustained-load and process-death acceptance tests.

These observations cannot demonstrate collaboration superiority, scientific
novelty, successful protein experiments or manuscript publishability.

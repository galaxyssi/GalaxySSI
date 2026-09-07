# Durable Dynamic Task DAG

## Delivered Boundary

Desktop 1.0.36 introduces a provider-independent task-graph reducer and Run-ledger
store, with the existing evolution Campaign API as its first production adapter.
New campaigns use this store. Existing JSON campaigns remain readable through
their existing path; this change does not recreate their tasks or reset data.

This is the first stage of the long-running DAG and self-evolution upgrades, not
completion of either objective. Android's ordinary Agent Loop is not migrated by
this PR. Automatic model-driven replanning, a months-long device run, and the
publish-to-CI-to-repair loop still require integration and acceptance.

## Durable State

`DurableTaskDag` commits a command, its Run event, graph metadata, and changed node
projections in one SQLite transaction using `AgentRunEventLedger`. Production
campaigns share the default Run database. Explicit isolated evolution stores
use a sibling ledger under that supplied store for tests and candidate runtimes.

Every command is bound to client route, conversation, goal, task, run, and turn.
An operation ID cannot be reused for different content or another scope. A
duplicate returns the state at that operation, including its original execution
token, rather than leaking a later worker's token. Replay reads the journal in
bounded batches. Recovery enumeration returns paged metadata without all nodes.

Ordinary step events contain only changed nodes, not a new copy of the whole
graph. Metadata checkpoints likewise omit node bodies. Plan edits record their
actual node changes. No cumulative action-count or total-duration limit is
introduced. Individual inherited tool/provider limits are not changed here.

Graph evaluation currently materializes one active graph in the backend worker.
This is not a claim of constant-memory scheduling for arbitrarily large graphs;
further indexed scheduling and real-device performance work remain required.

## Dynamic Replanning

Plans use stable node IDs, action descriptors, and explicit dependencies.
Validation rejects missing dependencies, duplicate IDs, and cycles using an
iterative traversal. The model's node order survives database reopen.

A revision must supply the current `expected_revision`. Pending, never-started
nodes can be edited, reordered, added, or removed. Started specifications remain
immutable. A model may explicitly supersede observed-failed or recovered-pending
nodes with an explanation, while rewiring pending dependents to replacements.
Retired IDs cannot be reused, and the journal retains their old observations.
Running or uncertain effects cannot be silently discarded during replanning.

## Execution and Recovery

Claiming a ready node assigns a durable attempt token and stable effect key.
Checkpoint and outcome callbacks must present that attempt token. Late callbacks
from an earlier attempt cannot overwrite a replacement attempt.

An adapter must confirm an owner has stopped before issuing `recover_owner`.
Read-only work can be scheduled again. A replayable action keeps its effect key;
only an executor that actually implements that idempotency contract may classify
an action as replayable. A model's unsupported assertion is not sufficient.
Uncertain external effects require an observed reconciliation outcome before
retrying. A network failure after a write is not proof the write did not happen.

Pause prevents new claims and persists across reopen. Already-started children
can report observations while paused. Generic graph cancellation fences future
callbacks, but terminating external work is an adapter responsibility; campaign
control deliberately does not expose cancellation until durable child
cancellation propagation is implemented.

## Evolution Integration

New campaigns bind every node to a proposal and deterministic child task ID.
The claim is committed before creating or starting that child. If the process
stops after child creation, recovery observes the same child ID. Production
creation verifies campaign ownership and reuses existing persisted tasks.

The current single Desktop manager serializes local create/start calls. DAG
claims themselves use SQLite transactions and are tested with concurrent store
instances. This is not a cross-host execution-leader or globally exactly-once
external-effects guarantee.

Enabled evolution scheduling observes opted-in campaigns on its existing wake
cycle. Paused/manual campaigns do not auto-start. Default disabled settings are
unchanged. Campaign starts honor the existing serial/parallel worker capacity,
and scheduled proposal capacity also counts active campaign workers.

Published child tasks leave a campaign `awaiting_verification`, not automatically
completed. Finishing requires all remaining nodes completed and an explicit
evidence reference/explanation. The current adapter does not itself prove that
GitHub CI is green; durable CI observation and automatic repair are the next
integration stage.

## API

The existing loopback-only `/api/evolution/v2/campaigns` endpoint creates new
durable campaigns. Listing includes durable and existing legacy campaigns.

- `GET /campaigns/{id}` reads the durable current state.
- `POST /campaigns/{id}/revise` accepts `operation_id`, `expected_revision`,
  `nodes`, optional `supersede_ids`, and `evidence`.
- `POST /campaigns/{id}/control` accepts `operation_id` and `operation`:
  `pause`, `resume`, `retry`, or `finish`. Retry requires `node_id` and evidence;
  finish requires evidence.
- `POST /campaigns/{id}/tick` retains `start_ready`; it observes existing work
  and dispatches dependency-ready work according to the persisted policy.

Revision conflicts and invalid state changes return an actual structured error.
No model reply, MQTT system notification, or chat text is generated by this API.

## Verification Scope

Tests exercise actual SQLite transactions, rollback after event/node failures,
two subprocess exits (after commit and inside a transaction), concurrent claims,
scope isolation, token fencing, delta journal size with 1,000 nodes, a 3,000-node
chain, revision/supersession rules, recovery pagination, and durable order.
Campaign tests cover the existing API, production task identity reuse, paused
and manual execution, dependency unlocking, child-creation interruption,
transient lookup failures, and existing worker capacity.

These tests do not perform a live GitHub mutation, run a real provider, restart
the shared Desktop, install an APK, or reset any phone data. Real S20U acceptance
and complete self-evolution CI repair remain outstanding.

Validation on 2026-09-07 against main `53a04e779`: 110 focused Run/DAG/campaign
regressions passed; the full evolution-v2 suite passed 79 tests (overlapping
with the focused set, not 189 distinct tests). Desktop checks passed 29 tests.
The new DAG and campaign files contribute 49 tests. Repository and whitespace
checks are also required before submission.

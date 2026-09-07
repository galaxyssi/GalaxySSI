# Durable initial goal decomposition

Desktop 1.0.50 adds initial goal planning to the existing private campaign planner.
The goal is recorded in the shared Run event ledger before any model request. It
is not represented by a fake executable placeholder node or a separate goal
database. The checkpoint kind is `evolution_goal_request_v1`; the final DAG uses
the same Run identity and the existing dynamic DAG checkpoint.

## API and controls

All routes retain the evolution API's existing loopback boundary.

- `POST /api/evolution/v2/goals`: `request_id`, `name`, `objective`, optional
  `auto_start` (false by default). Reusing a request ID with identical content
  returns the existing goal; changed content is rejected.
- `GET /api/evolution/v2/goals`: paginated public projections, default page 64,
  maximum 100. The returned `next_cursor` supplies `before_updated_at` and
  `before_id` for the next page.
- `GET /api/evolution/v2/goals/{campaign_id}`: current public planning status.
- `POST /api/evolution/v2/goals/{campaign_id}/control`: `pause`, `resume`, or
  `cancel` before a DAG exists. Resume can supply additional `context` for a
  waiting planner. Once a DAG exists, use the existing campaign controls.

Requests can be saved while evolution is disabled, but no inference or execution
starts until existing scheduler settings permit it. `auto_start` controls whether
the resulting campaign automatically dispatches ready nodes; it does not enable
global evolution. No fixed aggregate task or action budget was introduced.

## Runtime and recovery

The existing planner thread takes one due initial goal before processing failed
campaign observations. Initial planning uses the same loopback-only, tool-free,
progress-aware inference client and the same per-campaign OS planning owner. The
model chooses tasks, source scopes, acceptance criteria and dependencies, or asks
to wait for missing context. Invalid decisions receive durable validation feedback.

The accepted answer is checkpointed before materialization. Proposals receive
deterministic IDs and `campaign_reserved` status. The complete proposed DAG and
source policy are checked before any proposal is persisted; then the DAG is
committed through the existing reducer and ledger. Separate proposal files and
the DAG are not one physical transaction: an interrupted proposal write is
recoverable through deterministic identities and reserved, non-dispatchable
proposals. If the DAG committed before the final goal status update, recovery
finds that same DAG rather than requesting another plan or creating another one.

User controls increment a revision under the same campaign operation owner.
Results from an inference racing pause, cancellation or context changes cannot
materialize stale work. A saved valid decision can survive temporary disabling
or service restart without another inference. Public projections exclude raw
model answers and validation excerpts; private planning remains local.

## Evidence and limitations

Automated tests cover request replay/conflict, no placeholder DAG, dependency
dispatch, two planners, service reopening, crash after saved decision, crash after
DAG commit, controls during inference, disabled runtime, malformed/cyclic plans,
source policy, missing local model, wait/context/resume and loopback API pagination.
Crash boundaries use injected process-exit exceptions, not phone reboot acceptance.

A real official Qwen3-1.7B Q8_0 model via isolated llama.cpp b10839 CPU received a
Chinese documentation goal on 2026-09-07. In 50.609 seconds it produced three tasks:
installation instructions, getting-started examples depending on installation,
and consistency verification depending on both. The production planner and ledger
materialized the DAG, dispatched only the first controlled child, and reopening
did not repeat inference. One model-authored acceptance criterion used an
inconsistent filename; semantic quality is not proven by structural validity.

The opt-in harness `tools/testing/run_evolution_goal_acceptance.py` records this
component evidence in isolated local state. Child execution and policy approval
in that harness are controlled, not real candidate code development. Full UI
integration, real candidate implementation, CI/merge progression, multi-day runs,
phone acceptance and complete goal coverage remain separate unfinished work.

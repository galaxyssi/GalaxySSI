# Parent goal context for candidate implementation

Desktop 1.0.52 preserves the original campaign objective and the model-authored
proposal title when invoking a child implementation Agent. Previously the child
received its shortened problem and acceptance criteria, but not the full parent
goal or planned title. A planner could therefore omit a user requirement from
the implementer's input even though the goal remained in the durable ledger.

## Data path

Before invoking the implementation adapter, the host resolves the task metadata
to its campaign, checks the complete Run root identity, and finds the unique
node whose action owns that task ID. It reads the original objective and the
referenced proposal title, then carries these values in a thread-local execution
context for this invocation only.

The adapter includes both fields in its prompt. The parent objective is labeled
as context, not permission to expand the task's declared file scope. The local
model adapter still receives exactly the task's original write scope. Explicit
CLI adapters receive the same parent context through the common prompt builder.
Ordinary manual tasks without a campaign do not inherit another goal.

No second copy of the parent goal is added to every task record. Reopening the
manager resolves the context from the durable campaign. Nested invocations and
concurrent workers have separate contexts, cleared when each invocation exits.

## Indexed lookup

The Run ledger's DAG node projection has an expression index on run ID and the
action's task ID. Context lookup reads the objective and at most two matching
nodes; two matches are an identity conflict. It does not hydrate the entire DAG
or build the campaign UI projection. Invalid JSON in unrelated node rows does
not prevent index creation or lookup of a healthy task.

Missing campaign/proposal evidence or inconsistent task ownership produces a
specific context error, rather than silently using an incomplete prompt. These
errors block the attempt instead of repeating candidate creation against the
same missing context. Legacy persisted campaign records retain their existing
read path with the same unique-task ownership check.

## Evidence

Regression tests cover ledger reopening, complete root identity, missing and
foreign records, default-adapter prompt delivery, unchanged file scope, nested
and concurrent contexts, a 1,000-node campaign, indexed query plans, and an
unrelated corrupt node during index creation.

The opt-in `tools/testing/run_local_campaign_acceptance.py` uses the production
EvolutionManager, goal planner, local implementation adapter, worktree creation,
gates and publication method. It never writes the requested candidate edit or
substitutes a canned model result. Source and state directories must be separate;
publication requires a separate explicit task argument after inspection.
Its [acceptance milestones](evolution-acceptance-milestones.md) distinguish a
ready candidate, a published PR, and current verified campaign completion.
Historical publication records and saved readiness flags are not success proof.

A real Qwen3 1.7B Q8_0 run against main `cb4031ff8` materialized one model-authored
task and created a real GalaxySSI candidate. The implementer repeatedly failed
write actions after reading the document; no source edit was accepted. This run
used the previous prompt path and exposed the parent-context gap. It is not a
passing candidate or PR acceptance.

An explicit interruption of the isolated local model server then produced five
persisted `implementation_channel_failed` attempts, with no external CLI
fallback. The task and goal survived; the production source worktree stayed
clean. The unnecessary repeated worktree creation after provider loss and the
lack of detailed persisted file-tool failure observations remain separate
follow-up defects, not completed work.

The new indexed context path was subsequently run against that real persisted
failed task with no inference. It recovered the matching full objective,
campaign ID, node ID and proposal title. Evidence is local to
`GalaxySSI-local-campaign-live-state-20260907/acceptance.json` and
`context-acceptance.json`; private goal text is not committed here.

The complete goal-to-PR/CI/recovery acceptance still needs a successful real
implementation run. This release does not replace the running Desktop or
install a phone build by itself.

# Saved workflow instantiation

An explicitly selected `workflow_method` can be reused without asking a model to
transcribe every saved step, dependency and review condition. This is a compiler
into the existing collaboration work graph, not a second planner or executor.

## Request

Both goal assessments and live work expansions accept this entry in `work`:

```json
{
  "workflow_instance": {
    "execution_id": "comparison-2026-01",
    "method": {"object_id": "saved-id", "revision": 1, "sha256": "exact-digest"},
    "inputs": {"dataset": {"object_id": "data-id", "revision": 1, "sha256": "data-digest"}},
    "roles": {"worker": "person-a", "reviewer": "person-b"}
  }
}
```

`inputs` and `roles` must have exactly the names declared by the method. The
optional `capability_channel` carries an exact channel reference and uses the
existing channel admission checks. The wrapper cannot also contain ordinary
work, permission or host binding fields.

The Agent reads the full method, checks applicability, chooses inputs and assigns
people. Recall does not automatically adopt a method. An unverified method can be
tried as a candidate; successful compilation or completion does not promote it.

## Compilation and admission

1. Resolve the exact current method under the planner's existing workspace scope.
2. Copy every saved step, assignment, stage, dependency policy and review flag.
3. Map roles to members and step dependencies to deterministic work IDs.
4. Keep inputs in the untrusted data binding, never interpolate them into prompts.
5. Run the existing whole-method, member, independent-review, claim and DAG checks.
6. Dispatch with the ordinary scheduler, routing, concurrency and task controls.

The stable work ID is `workflow:` followed by a name-based UUID over the UTF-8
JSON array `[execution_id, step_id]`. Agents should use the ordinary work inventory
to find generated IDs when planning later dependent tasks, not guess IDs.

Goal-round role assignments can refer to `recruit:vacancy` when accompanied by the
existing authorized recruitment declaration. Expansion happens before recruitment
so every vacancy still needs concrete work. Live expansions use existing people.
Neither form grants provider, tool or data authority.

Inputs must already be visible to the assigned workers under normal workspace
rules. The macro does not add dependencies outside the saved method. In particular,
do not pass a current-round artifact that workers cannot read; reuse it at the
appropriate goal checkpoint or use ordinary dependency-aware work instead.

Invalid instances reject the whole expansion; ordinary entries beside a bad
instance do not execute partially. The coordinator receives the actual validation
message and can revise its next proposal. No hard-coded retry count or method
selection strategy is introduced.

## Persistence and evidence

The existing `workflow_step` binding and claim ledger remain authoritative.
Replaying the same instance preserves identities and skips completed work. Changed
method/input/member bindings cannot overwrite an admitted execution. A distinct
experiment needs a distinct execution ID; a changed method needs its own saved
revision object with feedback lineage.

Results, timing availability and output hashes use existing workflow outcome
receipts. They do not establish correctness, novelty, transfer or causal benefit.
Method improvements still require matched baseline/candidate evidence, regression
checks and independent review. Finishing one method does not finish the user's
goal; the ordinary goal loop assesses remaining work.

## Validation scope

`CollaborationWorkflowInstantiationTest` exercises exact expansion, untrusted
inputs, identity stability, missing fields, scope/version failures, channel checks,
1,000-step methods, atomic rejection, independent review, authorized recruitment,
goal-round replay after reopening, and live expansion beside unrelated work.

These deterministic tests verify compiler and scheduling behavior. They do not
prove that a real model autonomously selects a useful method, that collaboration
improves output quality, or that the system has achieved general superintelligence.

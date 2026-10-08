# Typed collaboration input binding

Ordinary research and challenge work can consume an exact published version before
its producer finishes. Publication is neither completion nor validation. This
extends the existing scheduler and durable workspace; it does not introduce a
second executor or automatically decide a research strategy.

## Declare the dependency when creating work

```json
{
  "id": "challenge-measurements",
  "member": "authorized-person-id",
  "stage": "CHALLENGE",
  "assignment": "Find a discriminating counterexample using the frozen measurements",
  "depends_on": ["measure", "release-instrument"],
  "dependency_policy": "success",
  "independent_review": false,
  "data_dependencies": [
    {"work_id": "measure", "requirement": "Frozen observations and their measurement method"}
  ]
}
```

`data_dependencies` entries must name unique `depends_on` work IDs and concrete
requirements. Every other edge remains a completion wait. A data declaration does
not itself release a dependency. In this example `release-instrument` still must
finish, even if it publishes a report before releasing the instrument.

An explicit empty array means all edges are completion-only. The absent field
retains the existing independent-review protocol for already-created reviews;
ordinary untyped work cannot use early input binding. No retrofit of old work or
silent replacement of an existing dependency contract is allowed.

## Bind sufficient exact data at a coordinator checkpoint

After inspecting published versions, the coordinator can return:

```json
{
  "format": "galaxyssi.work-expansion.v1",
  "summary": "Frozen measurements support the planned challenge; instrument release still waits",
  "work": [],
  "rebind_inputs": [{
    "work_id": "challenge-measurements",
    "expected_revision": 0,
    "reason": "The pinned observations and method satisfy the original data requirement",
    "inputs": [{"dependency": "measure", "uses_milestones": ["exact-host-issued-token"]}]
  }]
}
```

The host requires a live admission snapshot and checks the exact producer node,
person and granted versions. Only unadmitted ordinary research work can change.
The original assignment, identity, independence declaration, goal and acceptance
criteria stay unchanged. Already-admitted, running, ended and host-managed work
retain their existing transition protocols. `QUEUED` alone is not permission to
change a dispatch.

Both `rebind_inputs` and `rebind_reviews` preserve completion-only edges on typed
work. Independent reviewers still cannot review their own candidate. A normal
challenge is not relabeled as independent verification. One atomic expansion may
change a work item's input revision once; any invalid binding or new work rejects
the complete expansion. Pause/stop defers binding without consuming its plan.

The checkpoint records the rationale, original data requirements, replaced edges,
exact tokens and revision. It grants only pinned versions, not future revisions or
the producer's unpublished work. Scheduler compare-and-set, persisted history and
admission guards prevent replay from dispatching the same work twice.

## Validation scope

Unit coverage includes contract validation and persistence, immutable work
identity, original goal preservation, independent authorship, exact-version access,
completion waits, admission guards, atomic rejection, pause/stop and replay.
Device fixtures use the actual encrypted store and scheduler with local synthetic
publications, including a separate-process recovery mode. They do not invoke a
model, contact, broker or physical operation.

These checks establish software behavior only. They do not establish that an
Agent will choose useful challenges, improve a solution, acquire a transferable
capability or make a scientific discovery. Those require fresh real-model tasks
and controlled comparisons, outside the repository's regression fixtures.

### Recorded validation, 2026-10-09

- Android 1.4.110 / 1195: debug APK and instrumentation APK built successfully.
- 169 selected JVM regressions in 13 suites: zero failures, errors or skips.
- S20U (`SM-G9880`): three real scheduler/encrypted-store cases passed, covering
  ordinary data-consuming challenges and both prior independent-review modes.
- Ordinary typed work survived an explicit App process stop: seed PID 9736,
  recovery PID 9790. Both phases passed; exact input history was retained and
  each fixture assignment executed once. Recovery cleaned its dedicated data.
- Repository checks and whitespace checks passed. Existing user configuration
  was preserved by an in-place installation. No real-model trial was run.

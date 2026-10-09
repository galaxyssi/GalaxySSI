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
  ],
  "completion_barriers": [
    {"work_id": "release-instrument", "reason": "The shared instrument must actually be released"}
  ]
}
```

`data_dependencies` entries must name unique `depends_on` work IDs and concrete
requirements. Every other edge remains a completion wait. A data declaration does
not itself release a dependency. In this example `release-instrument` still must
finish, even if it publishes a report before releasing the instrument.

An explicit empty array means all edges are completion-only. The absent field
retains the existing independent-review protocol for already-created reviews;
ordinary untyped work cannot use `rebind_inputs`. A separately audited correction
below can revise a planning mistake; no silent retrofit is allowed.

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

## Correct an overly sequential plan

A completion wait is not always a real operation-order requirement: a coordinator
may initially schedule a challenge after the whole report when the challenge only
needs frozen measurements. A new **explicit** revision can correct this mistake.
The host does not silently interpret a completion wait as a data wait.

Before revising, the active incremental coordinator can call
`collaboration_recall(mode="team_updates", work_id="challenge-measurements")`.
Unlike the compact inventory, this returns the full original assignment, declared
dependencies, barriers, review roles and current input revision. It uses the
existing exact coordinator binding on Android cloud/native and the Desktop
forwarder, not caller-supplied group/member/run IDs. This selector cannot be mixed
with the publication cursor. Ordinary members, paused/stopped coordinators and
foreign work are rejected. Reading a contract neither grants unpublished producer
evidence nor makes the work eligible to change after admission.

```json
{
  "format": "galaxyssi.work-expansion.v1",
  "summary": "The original challenge needs the published data, not the unfinished report",
  "work": [],
  "revise_input_dependencies": [{
    "work_id": "challenge-measurements",
    "expected_revision": 0,
    "reason": "The original plan unnecessarily serialized evidence analysis and report writing",
    "inputs": [{
      "dependency": "measure",
      "uses_milestones": ["exact-host-issued-token"],
      "requirement": "Frozen measurements and the method needed by the unchanged challenge",
      "completion_not_required_because": "These versions contain the required inputs; this check does not operate or need release of the producer's instrument"
    }]
  }]
}
```

This applies only if `measure` is currently completion-only and **not** a
`completion_barriers` edge. A declared data edge still uses `rebind_inputs`.
Every existing admission, independent-authorship, exact-version, host-managed-work,
atomic-commit, pause/stop and replay check also applies to this revision.

The host retains the original objective, member, model, stage, tool authority,
remaining waits and final goal barriers. It persists the old edge kind, exact
inputs, coordinator diagnosis and monotonic revision. The producer continues and
is not marked complete. No extra duplicate review or model call is created by
the revision itself. It makes the existing work dependency-ready, not necessarily
immediately admitted if capacity is unavailable.

`completion_barriers` declares operation order that this protocol cannot weaken.
Each entry names a unique existing dependency with a reason and cannot also be a
data edge. Barriers survive initial planning, incremental planning, storage,
inventory and task identity validation. An ordinary resubmission cannot remove
them. Use these for actual side effects, resource release and full-producer
acceptance, not as a synonym for any unfinished report.

**Limits:** a coordinator's sufficiency diagnosis is stored as
`coordinator_assertion_not_verification`. The host verifies structural conditions
and recorded barriers, not the semantic truth of an arbitrary scientific claim.
An omitted or wrongly specified resource constraint is not magically discovered
by this protocol. Existing tool policies and resource controls remain responsible
for execution authorization; downstream validation must test the chosen method.

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

### Explicit-revision validation, 2026-10-09

- Android 1.4.114 / 1199 and Desktop 1.4.38 include explicit completion-wait
  correction and exact coordinator work-contract recall.
- 300 selected JVM tests in 25 suites passed without failures/errors/skips.
- S20U (SM-G9880) passed six local device cases: the three previous binding
  modes, correction with a retained operation barrier, and cloud/native
  full-contract recall in default and isolated execution stores. Ordinary,
  foreign and paused callers were rejected; original goal binding and evidence
  visibility were preserved.
- A separate seed/process-stop/recovery check passed, with distinct process
  IDs. The corrected dependency, pinned inputs and barrier survived; fixture
  work executed once and the dedicated fixture data was cleaned.
- Desktop recall bridge: 23 tests passed; Desktop UI/structure: 68 tests passed.
- These are software-contract results with local synthetic workers, not an
  autonomous real-model dependency decision, science result or team advantage.

# Six Arm Longitudinal Capture Protocol

Offline planning and capture-contract inspection for ordered task streams.
This is not a model runner, runtime isolation layer, answer grader, cost meter,
or evidence that persistent collaboration is effective. It does not modify
Android, Desktop, ordinary conversations, model routing, or their release versions.
Protocol version 1 is separate from an App release version.

The adjacent `team-evaluation` tool compares independent short tasks. This tool
preserves a different experimental unit: an ordered family of tasks with state
carried between goals only in the assigned persistence conditions. It reuses
the existing canonical digest helper and Node standard library.

## Six Conditions

| Arm | Members | During-task peer communication | Cross-goal learned state |
| --- | ---: | --- | --- |
| S0 | 1 | Not applicable | Reset |
| S1 | 1 | Not applicable | Retained |
| T00 | Configured team size | Off | Reset |
| T10 | Configured team size | On | Reset |
| T01 | Configured team size | Off | Retained |
| T11 | Configured team size | On | Retained |

The same final integration opportunity is permitted in all team conditions.
Finalization communication is recorded separately from work-phase exchange.
S1 must have the same permitted adaptation operations as T11, performed by one
member, not an artificially weaker solver. No peer reviewer may be added to a
single-member arm. Actual adaptation, memory access, and tool-policy enforcement
still require a separately reviewed collector and runtime.

## Frozen Inputs

`plan` accepts a private config with these exact fields:

- `study_id`, explicit `evidence_kind` (`fixture` or `actual`), `team_size`,
  positive `repetitions`.
- `controls`: SHA-256 digests for the pinned model, tool, permission, initial
  state, external evaluator, and outage policies. Archive the corresponding
  policies privately; a hash alone does not prove what was enforced.
- `stream_budget`: positive `max_wall_time_ms`, `max_model_requests`,
  `max_total_tokens`, `max_cost_micros`, and `currency: "USD"`.
- `families`: unique `family_id`, `domain`, and an ordered list of at least two
  goals. Each goal has `goal_id`, `request` (only `prompt` and `input_sha256`),
  `success_contract_sha256`, and `perturbation_sha256`.

The example generator provides the full JSON shape with deliberately synthetic
policies and task text. Its caps are test inputs, not product defaults or an
authorization to spend money. There is no fixed maximum number of goals here.
Research collection remains bounded by an explicitly approved protocol.

Rubrics, answer keys, sealed audit tasks and raw evidence stay outside the source
repository and outside the evaluated agents' accessible workspaces. The plan
stores contract digests, not answer keys. Prompt text can still contain private
information: all generated artifacts are collector-private, not review packets.

The planner samples a 256-bit seed, randomizes family/repetition blocks, then
randomizes the six whole-stream runs within each block. Goal order is never
shuffled. It does not claim exact order counterbalancing. All arms of a block
receive identical goal contracts and perturbations. Every stream receives a
unique state namespace and the same **whole-stream** caps, including learning,
diagnosis, all members, retries, tool use and final integration. Budgets must not
reset at a goal boundary or multiply with team size.

Freeze and archive the plan before collecting answers. Do not rerandomize until
a favorable schedule appears. Repetitions, checkpoints, goals and members do not
increase the number of independent families. Family IDs only declare clusters;
source disjointness and independence need substantive external audit.

## Commands

Run tests from the repository root:

```powershell
node --test tools/testing/team-longitudinal/protocol.test.mjs
```

Repository Guard also runs this suite together with the existing paired
evaluation tests. No private study config or captured result is used in CI.

Explicit synthetic demonstration, using fresh directories outside Git:

```powershell
node tools/testing/team-longitudinal/run.mjs example --out C:/Temp/longitudinal-example
node tools/testing/team-longitudinal/run.mjs plan --config C:/Temp/longitudinal-example/fixture-config.json --out C:/Temp/longitudinal-plan
node tools/testing/team-longitudinal/run.mjs fixture --plan C:/Temp/longitudinal-plan/plan.private.json --out C:/Temp/longitudinal-capture
node tools/testing/team-longitudinal/run.mjs inspect --plan C:/Temp/longitudinal-plan/plan.private.json --capture C:/Temp/longitudinal-capture/fixture-capture.json --out C:/Temp/longitudinal-report
```

The fixture commands produce **synthetic**, not actual, capture declarations.
There are no network, model, shell, device or tool executions in this CLI.
`fixture` and synthetic inspection exit **2**, even with consistent contracts.
Planning exits 0 for file creation only. Actual inspection exits 0 only for a
closed, fully terminal, internally consistent capture, never for answer quality
or efficacy. Malformed or ambiguous input exits 1; incomplete or inconsistent
capture exits 2. Unknown commands/options fail closed.

The CLI refuses existing output directories and Git ancestors, including resolved
junction/symlink paths. Writes request owner-only modes; Windows ACLs still need
operator review. Evidence references are opaque strings, never opened or executed.
The checker cannot detect every relabeled synthetic record or dishonest collector.

## Collector Contract

`fixtureCapture` illustrates the capture structure for an adapter; never reuse
its values as actual measurements. A real adapter supplies:

- The original plan hash, evidence kind and explicit collection open/closed
  state with a local evidence reference. An observation timeout is not closure.
- Each original stream's order, group ID, state namespace, assigned policy,
  control digest, whole-stream ledger and budget-enforcement reference.
- Each goal's original slot/goal/index/request identity, run ID, all attempt IDs,
  lifecycle state and evidence reference. Retries remain within one slot.
- Input/output state digests, actual read/write namespaces and reset evidence.
  Persistent goals consume their own terminal predecessor's output; reset arms
  start each goal from the same initial state. Failed goals also retain state.
- Work-phase and finalization peer-message counts with capture references.
  Missing counters must not be guessed as zero.

Run IDs, attempt IDs, group IDs, namespaces and ledgers cannot be reused across
independent streams. A later goal cannot precede its terminal predecessor.
Cross-stream state reads/writes, control drift, changed caps, per-goal budget
resets and forbidden peer exchange remain visible as protocol violations.

`resource_exhausted` means the whole-stream allocation was exhausted. Subsequent
goals must be explicitly `unattempted_after_exhaustion`, with an exhaustion
reference, no fabricated run ID, no attempts, no peer work and unchanged state.
The adapter may checkpoint or reset state without invoking the solver. Missing
rows are **not** evidence of exhaustion and are never silently converted to zero.

Every planned slot remains in the report. Failed, cancelled, paused, waiting,
running and missing states remain distinct. Closing collection does not convert
an unknown result into failure or success. This inspector reports lifecycle
counts and contract violations only; it deliberately has no success-rate field.

## Remaining Work Before Scientific Use

The actual Android/Desktop collector must enforce the declared arm conditions,
separate namespaces, permissions, sealed evaluator access and whole-stream budget.
It must capture original receipts rather than self-reported model prose. Restore,
outage and interruption tests must verify the new collection path on real devices.
No such live acceptance is claimed by these offline tests.

Keep complete bills, measured usage, source traces, all failed starts and manual
interventions. Unknown resource measurements stay unknown. Hash chaining and
consistent identifiers cannot independently authenticate execution or fair cost.
Externally grade every assigned goal, distinguish quality from budget-compliant
completion, and predeclare missing-data and symmetric outage policies.

The six-arm design still requires longitudinal learning, transfer, retention,
innovation review, family-cluster uncertainty, and appropriate causal contrasts.
Neither this harness nor a small calibration establishes those results. Do not
pool different model policies or turn a development retest into extra independent
observations. Private papers and real experiment artifacts must not enter PRs.

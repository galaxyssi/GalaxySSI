# Equal-Budget Single-Agent / Team Evaluation

Offline evidence tooling, not a live model runner or an app capability claim.
All changes are confined to this tooling directory. No production app code,
build, device, network, reboot, Doze, upload, or model invocation is required.
Node's standard library is the only dependency.

## Established Contracts

The harness extends `tools/benchmark/agent-benchmark-lib.mjs`: the same scenario
`request`/`expect` shape and `evaluateScenario` assertions are used for basic
output and tool-policy checks. Structured JSON answer rubrics add deterministic
task-quality scoring. Like `tools/benchmark/business-scenarios/report.py`, the
report binds evidence to a catalog digest and retains every planned trial.

EvalOps inspection informing the integration:

- `AgentEvalBenchmarkModels.kt`: repeated trials, case/run identity, raw output,
  resource snapshots, quality and failure classifications.
- `AgentEvalOpsStore.kt` (`encodeSample`): `run_id`, `scenario_id`,
  `duration_millis`, `reported_cost_micros`, `failure_reasons`, `evidence_kinds`.
- `AgentEvalRunEvents.kt`: append-only run-correlated observation events.
- `AgentEvalOpsModels.kt`: `reportedCostMicros` defaults to zero. That zero is
  **not proof of a measured free run**; this harness never imports it implicitly.

## Fixed Protocol

`corpus.json` contains six offline task types: code review, source reconciliation,
dependency planning, numeric analysis, extraction, and untrusted-instruction
classification. These are small structured-answer diagnostics, not tests of
production coding, live research, UI behavior, or general intelligence.

Generate the plan before collection. Default three repetitions produce 18
pairs / 36 slots; 3..10 repetitions are supported. Pairs are randomly shuffled,
and A-first/B-first order is counterbalanced within each task (imbalance at most
one). A random private key maps A/B to `single_agent` and `team`. Keep that file
with the collector, away from graders. Freeze the plan and key before running.

Both arms receive exactly the same prompt, model/decoding policy, available
tools, environment, clean context policy, and **entire-trial** budget limits.
Use a fixed, predeclared team topology/role policy in the private capture and
one agent for the single-agent arm. `assignment_verified` attests that the
collector checked each topology against the private key. Do not choose models,
team size, task-specific roles, or budgets after observing answers. More workers
do not multiply the budget. Different actual consumption is expected; equal
budget means equal enforced caps, not artificially equal measured spending.

Do not stop early based on favorable scores, drop failures, replace trials, or
select best-of-N responses. Retries, reviewer/finalizer work and rework stay in
the original trial and consume its original budget. If collection is interrupted,
report the partial export against the original full schedule. A new independent
campaign needs a new plan; it is not a repair of an unfavorable trial.

## Local Commands

From the repository root, run tests:

```powershell
node --test tools/testing/team-evaluation/team-evaluation.test.mjs
node --test tools/benchmark/agent-benchmark.test.mjs tools/benchmark/agent-regression-dsl.test.mjs
```

Explicit synthetic demonstration (output paths are examples; use fresh local
directories outside the source tree):

```powershell
node tools/testing/team-evaluation/run.mjs plan --config tools/testing/team-evaluation/example-config.json --out C:/Temp/team-eval-fixture-plan
node tools/testing/team-evaluation/run.mjs run --plan C:/Temp/team-eval-fixture-plan/plan.json --adapter fixture --out C:/Temp/team-eval-fixture-report
```

The fixture adapter is intentionally synthetic, symmetric across A/B, and
contains timeouts and unknown cost. Its exit code is **2**, and every artifact
is labeled `fixture`. It cannot be read using the actual-export adapter.
No adapter is selected by default. Existing output files are never overwritten.

`example-config.json` is fixture-only. For a real campaign, supply a separate
config with pinned, auditable policies instead of `FIXTURE_ONLY` placeholders.
The plan command emits `plan.json`, prompt-only `requests.json`, the private
arm key, and an **incomplete** `accounting-template.private.json` with UNKNOWN
measurements and false completeness/enforcement flags. The template is not
evidence and cannot run until original app run IDs are bound.

## App Evidence Hook

The hook is local JSON, so it requires no production modification to use an
existing exporter or a separately reviewed collector. It does not launch the app.
`comparison.schema.json` specifies the interchange format. `lib.mjs` adds
fail-closed semantic validation for IDs, digests, completeness, and equal caps.

1. After separate authorization for collection, the collector consumes
   `requests.json` in its recorded order and uses the private key to select the
   arm. Never send the answer rubric or arm key to the model. Enforce one shared
   budget counter across all workers, orchestration, retries and finalization.
2. Bind each `slot_id` to the original app `run_id`, including failed starts that
   obtained a run ID. Export the existing host benchmark shape
   `{"results":[{"run_id":"...","scenario_id":"...","status":"failed",
   "response":"...","events":[],"tools":[],"failure_reasons":["..."]}]}`.
   Preserve actual terminal states and evidence. Map app case/scenario ID to
   `scenario_id`, `AgentBenchmarkTrialEvidence.rawOutput` to `response`, and
   recorded run lifecycle state to `status`. Do not infer status/quality from a
   nonempty response or EvalOps `passed`. Some older benchmark exports omit
   `run_id`; recover it from the original collector mapping, never fabricate it.
3. Complete an accounting sidecar from real receipts, retaining `evidence_kind`
   as `actual` on the batch and every row. `capture` records actual order,
   `request_sha256 = digest(scenario.request)`, reset/controls/topology checks,
   `scope: "entire_trial"` and a local evidence reference. `budget.limits` must
   exactly equal the frozen plan; set `enforced` only with scheduler evidence.
   Never fill measurement gaps from the fixture adapter. Omit unstarted rows;
   they remain missing in the report. Started rows may lack a terminal result.
4. Import and report using the commands below. Both operations preserve the
   original source fields; `evalops_sample` may be retained in the private row
   for audit but never substitutes for measured accounting or answer grading.

```powershell
node tools/testing/team-evaluation/run.mjs import --plan C:/Temp/team-eval-plan/plan.json --benchmark C:/Temp/captured-results.json --accounting C:/Temp/accounting.private.json --out C:/Temp/team-eval-import
node tools/testing/team-evaluation/run.mjs run --plan C:/Temp/team-eval-plan/plan.json --adapter export --results C:/Temp/team-eval-import/export.json --out C:/Temp/team-eval-report
```

A collector can alternatively emit the comparison export directly and use
`--adapter export`. The library hook is `importBenchmark(plan, corpus, benchmark,
accounting)` followed by `compare(plan, corpus, export, "actual")`. It joins by
original run ID, rejects duplicate/reused runs and calls, rejects unbound extra
results, and refuses an accounting sidecar that overrides captured answers.

### Measurement Semantics

Each measured value is `{ "value": 123, "complete": true,
"evidence_ref": "local-capture.json#receipt-id" }`. References are opaque local
audit references; the harness never opens them, fetches URLs, executes task text,
or evaluates commands from results. Completeness is a collector attestation,
not independently authenticated proof. Audit the receipts before unblinding.

- `wall_time_ms`: monotonic elapsed time from trial admission through its last
  terminal event, including orchestration, all parallel workers, retries,
  verification, rework and human waiting. Do not sum worker durations or use
  importer wall time. An existing `duration_millis` is usable only when its
  measurement scope is verified to match this definition.
- `ledger.calls[].total_tokens`: non-overlapping per-call total of input/output,
  cached input and reasoning tokens as applicable. Provider totals often already
  include reasoning/cached categories; normalize once and do not double count.
  Include coordinator, every worker, failed/cancelled calls, reviewer/finalizer,
  retries and rework. If any category is unavailable, that call is UNKNOWN.
- `ledger.calls[].cost_micros`: actual attributable USD micro-units, including
  all model and paid-tool costs, from billing receipts or complete metering with
  a pinned auditable rate card. Retain provider/model/rate-card evidence privately.
  Do not use a guessed price or interpret absent pricing as free. Record a paid
  tool as a separate ledger call with explicitly observed zero model tokens.
- `ledger.participants` includes every contributing agent. `complete: true`
  certifies there are no unrecorded participants/calls. Totals are sums, never
  averages or maximum-worker usage. A missing subcall measurement makes the
  entire corresponding total UNKNOWN. Empty ledgers are UNKNOWN unless the
  collector explicitly observed `no_model_calls_observed: true`.
- `rework_count`: number of additional corrective attempts after a failed check
  or rejected output, including automated retries; parallel initial work is not
  rework. `intervention_count`: human clarifications, corrections, approvals or
  manual actions during the trial (excluding initial task submission). Record
  explicit observed zero when none occurred, not a default zero.
- Missing, null, invalid, negative, fractional, overflowing, incomplete, or
  unsupported measurement values become **UNKNOWN**, never zero. A numeric zero
  requires complete capture and an evidence reference like any other value.

## Report And Eligibility

Reporting analysis version 2 adds an **all-assigned policy endpoint** before
the selected-pair diagnostics. The plan, export and interchange schemas remain
version 1; existing captures need no relabeling. This is reporting-only: no App
or Desktop release version, scheduler, model call, or user task is changed.

The endpoint is binary verified completion within the assigned entire-trial
budget. It is distinct from the fractional structured-answer quality score:

| Evidence for a scheduled slot | Policy outcome |
| --- | --- |
| Verified full rubric pass, equal enforced caps, complete accounting within all caps | 1 |
| Verified terminal noncompletion or rubric failure | 0, even when resource totals remain unknown |
| Verified completed answer with any measured cap exceeded | 0; keep raw answer quality and actual resource use |
| Missing or unfinished result, invalid assignment/capture/controls | UNKNOWN |
| Potential success with unverified budget compliance | UNKNOWN |

The budget-excess outcome is a failure of the **observed policy**, not an
estimate of what that trial would have achieved with a lower budget. A missing
row is not proof that a goal was left unattempted after exhaustion; an interim
snapshot does not close collection. Such goals need an auditable terminal
outcome from the collector under the frozen protocol before they can score zero.
Accounting remains unknown when unavailable even if noncompletion is known.

For each arm, with N scheduled slots, S verified successes and U unknown
outcomes, `all_assigned` reports bounds `[S/N, (S+U)/N]`. A point estimate is
reported only if U=0. For each pair, the B-minus-A lower bound is B.lower minus
A.upper, and its upper bound is B.upper minus A.lower; these are averaged over
**all scheduled pairs**. Task slices use the same rule. Bounds are worst-case
missing-outcome bounds, not confidence intervals, and make no missing-at-random
assumption. They do not address sampling error, unverified collector testimony,
or generalization beyond the scheduled corpus. No arm is declared a winner.

`eligible_pair_analysis` explicitly marks the older selected-pair analysis as
diagnostic. Eligibility depends on events after assignment, so conditioning on
it can bias a treatment comparison. For example, excluding one otherwise correct
over-budget B result can make the surviving pairs appear tied while B has fewer
budget-compliant completions. Use the all-assigned outcome for that policy
question; do not substitute the selected-pair quality mean.

Each pair is eligible only when both slots have a terminal result, matching
request/run/scenario/order identity and controlled policies, verified capture
and total-budget enforcement, exactly equal caps, all five known resource
metrics, and no exceeded cap. Failure/timeout/partial/cancelled status does not
itself exclude a trial: known-accounting failures score zero and remain paired.
Over-budget outcomes and unknown-accounting failures remain in the full report
but their pair cannot support the eligible-only diagnostic comparison.

`report.json` contains all slots, exclusion reasons, assertion-level quality,
known/unknown counts, all-assigned outcomes and bounds, available-observation
descriptive means, diagnostic paired B-minus-A deltas, and per-task coverage.
`report.md` summarizes the same evidence. `metrics_all_scheduled` retains its
existing name for consumers, but each `mean_basis` explicitly says that its
mean uses available observations only, not all assigned slots.
Quality is the fraction of exact structured answer fields satisfied, subject to
the existing critical output/tool contracts; it is not a model-graded opinion.
No wall-clock cost or success is inferred from fixture execution speed.

`reviewer-packet.json` omits runtime IDs, provider/agent identity, cost, and the
private mapping. Raw answers can self-identify; screen for that before assigning
a blinded human grader. The deterministic grader consumes only the rubric and
result, not the arm mapping. Human judgments are not silently folded into the
numeric score. `audit-input.private.json` retains failures, raw events, source
references and metadata; restrict access and do not give it to blinded graders.
File creation requests owner-only modes, but Windows ACLs need operator review.

Exit 0 from `run` means a fully accounted actual comparison, **not** that tasks
passed or either arm won. Exit 2 means fixture evidence or incomplete eligibility;
exit 1 means malformed/ambiguous input. Repeated outcomes within a task are
correlated. No significance test, generalization, or superiority claim is made,
even for complete actual data; inspect per-task effects and excluded pairs.

## Remaining Acceptance

Local tests validate mechanics only. The parent still needs to independently
review this change, approve a real collection protocol/topology, verify app
exports and enforced shared budgets, obtain complete provider usage/cost and
rework/intervention receipts, collect every paired repetition, audit blinding,
then examine quality and efficiency before unblinding. Where app telemetry or
budget enforcement is not available, eligibility must remain incomplete; this
tooling does not claim those app capabilities are implemented. No real collection,
full build, device test, commit, PR, upload, or push is performed by this work.

The corpus is not a longitudinal task stream. These reporting mechanics do not
implement six-arm factorial assignment, stream-level learning, sealed audit
tasks, campaign closure, a symmetric outage rerun policy, cluster uncertainty,
or confirmatory inference. Those require a separately frozen study protocol and
collector; the new endpoint must not be presented as such an experiment.

The separate [longitudinal capture protocol](../team-longitudinal/README.md)
now freezes six-arm ordered streams and checks declared state, communication,
identity and shared-budget contracts. It is offline tooling, not the missing live
collector, physical isolation layer or confirmatory outcome analysis.

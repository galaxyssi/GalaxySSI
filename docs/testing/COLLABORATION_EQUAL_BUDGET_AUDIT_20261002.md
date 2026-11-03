# Equal-Budget Collaboration Audit: 2026-10-02

## Scope And Outcome

Independent offline verification of the PR3328 comparison tooling in
`tools/testing/team-evaluation`, introduced by local commit `a75b9bbd3`
(`test(collaboration): add blinded equal-budget comparison harness`). The PR
association comes from the task request; no remote PR metadata was queried.

The initial read-only audit passed 23 new contract tests and reproduced three
strict regression failures on the unchanged baseline. After explicit follow-up
authorization, GAP-01/02/03 were fixed without removing their assertions.

**Post-fix: 58/58 comparison tests and 12/12 shared benchmark/DSL tests pass,
with zero failures, skips, or TODOs. This is offline contract verification, not
receipt authentication, real model quality, or evidence of an Agent advantage.**

The initial audit authored these new files:

- `tools/testing/collaboration-equal-budget-contracts.test.mjs`
- `tools/testing/collaboration-equal-budget-gaps.test.mjs`
- `docs/testing/COLLABORATION_EQUAL_BUDGET_AUDIT_20261002.md`

The authorized follow-up modifies only `tools/testing/team-evaluation/lib.mjs`,
its existing `team-evaluation.test.mjs`, this report, and a historical comment in
the new gap test. The new contract test is unchanged. Kotlin, versions, and other
documents were not edited. No Gradle, ADB, real model, network collection,
commit, or PR operation was run.
The new tests use Node standard-library APIs and imported production harness
functions, without subprocesses, writes, network access, or generated reports.
Fixture values are test oracles, not empirical scores. GAP-01 constructs an
adversarial relabel only in memory; it is never saved as actual evidence.

## Interfaces Inspected

- Node comparison: `tools/testing/team-evaluation/lib.mjs` exports `createPlan`,
  `validateCorpus`, `validateExport`, `measureRun`, `assessQuality`, `compare`,
  `reviewerPacket`, and `importBenchmark`; `run.mjs` exposes plan/import/run.
- Shared Node grader: `tools/benchmark/agent-benchmark-lib.mjs`, especially
  `evaluateScenario` and its `latency_budget` assertion.
- Python evidence reporter: `tools/benchmark/business-scenarios/report.py`,
  especially `summarize(plan, reports, reviews)`. This is a device-business
  evidence reporter, not the equal-budget A/B runner, so this audit does not
  force its unlike report schema into the comparison or execute it.
- Contracts: comparison schema, fixture, corpus, example config, existing tests,
  `docs/testing/AGENT_BENCHMARK.md`, `COLLABORATION_LIVE_EVIDENCE.md`, and
  `COLLABORATION_LIVE_GRAPH.md`. Their scoped live passes do not establish an
  equal-budget advantage or substitute for accounting and repeated trials.

## Verified Contracts

| Requirement | Independent coverage |
| --- | --- |
| Equal total budget includes coordination | Six workers plus coordinator, reviewer, and finalizer sum into one trial; changing participant count cannot multiply caps. |
| Failed retries are billable | Failed, cancelled, interrupted, retried, and finalizer calls remain additive; retry overhead alone can exceed caps; terminal failures retain resources and stay paired. |
| Unknown cost is not zero | Missing, incomplete, blank-receipt, malformed, and overflowing measurements remain UNKNOWN; one unknown role poisons only the associated metric; paid tools with zero model tokens still cost money. |
| Blind review isolation | Metadata sentinels do not reach report or reviewer packet; changing costs does not change that packet; raw self-identifying answers remain visible with the existing warning. |
| Repeated-task isolation | Reused slot/run/call IDs are rejected; each repetition requires reset, request, and execution-order attestations; missing repetitions stay in denominators. |
| Quality versus efficiency | Costs and wall time do not rewrite quality; answer changes do not rewrite metering; signed deltas for quality/time/tokens/cost stay separate. GAP-02 now also passes for custom latency expectations. |
| Reporting integrity | Call permutation/partition preserves sums, concurrent worker durations are not substituted for trial wall time, input is not mutated, fixture conclusions make no capability claim. |

## Reproduced Gaps And Applied Fixes

### GAP-01: Explicit Synthetic Receipts Accepted As Actual (P1)

Current location: `tools/testing/team-evaluation/lib.mjs:117` (`validateExport`), and
`run.mjs:95` (success exit condition).

Before repair, the actual channel verified the top-level and per-run
`evidence_kind`, while `measurement` checked type/completeness/nonblank references
only. A fixture with
neutral control names, both labels changed to `actual`, and every cost populated
still contains `FIXTURE_ONLY` budget, capture, ledger, and measurement receipts.
`compare` nevertheless returned **18 eligible pairs**, where the strict test
required rejection or zero eligible pairs. This could satisfy the CLI's complete
actual-accounting exit condition. The CLI was not used to publish such evidence.

Applied fix: in `validateExport`, after checking the calls array shape, actual
runs are rejected when a recognized accounting/provenance reference starts with
the explicit `FIXTURE_ONLY` marker (case-insensitive, trimmed, followed by end of
string, colon, underscore, whitespace, or hyphen). The eight reference locations
are budget, capture, ledger, wall time, rework, intervention, and every call's
tokens/cost. Raw answers and result metadata are not scanned. `FIXTURE_ONLYISH`
and `NOT_FIXTURE_ONLY` are not this marker. The guard is shared by import,
comparison, and reviewer-packet entry points. Its central condition is:

```javascript
if (expectedKind === "actual") {
  const accounting = run.accounting || {};
  const ledger = accounting.ledger || {};
  const refs = [run.budget?.evidence_ref, run.capture?.evidence_ref,
    ledger.evidence_ref, accounting.wall_time_ms?.evidence_ref,
    accounting.rework_count?.evidence_ref, accounting.intervention_count?.evidence_ref,
    ...(ledger.calls || []).flatMap((call) => [
      call?.total_tokens?.evidence_ref, call?.cost_micros?.evidence_ref
    ])];
  requireThat(!refs.some((ref) => typeof ref === "string" && /^FIXTURE_ONLY(?:[:_\s-]|$)/i.test(ref.trim())),
    "Explicit fixture provenance cannot be actual evidence");
}
```

This catches explicit contradictory provenance, not fabricated receipts with
markers removed or renamed. Authentication and collector integrity remain
external audit requirements. The old relabeled-fixture positive test was
replaced: `makeActual` at `team-evaluation.test.mjs:25` independently constructs
schema-shaped receipt records and marks them as in-memory unit-test data, not
captured execution. It does not call `fixtureExport`, rewrite fixture labels,
write a report, or claim the receipts are authentic. Its positive comparison and
placeholder-policy exclusion assertions remain. The strict GAP-01 assertion
was retained and now passes by explicit provenance rejection.

### GAP-02: Latency Erases Correct-Answer Quality (P2)

Current location: `tools/testing/team-evaluation/lib.mjs:181` (`assessQuality`).

With a valid custom scenario expectation `max_duration_ms: 100` and
`latency_is_critical: false`, an unchanged correct structured answer previously
scored 1 at 99 ms and 0 at 101 ms. `assessQuality` gated its score with
`base.passed`, whose minimum-score calculation included the latency assertion.
Its `passed` value also included that assertion. The default six-case corpus has
no latency expectation, so the fixed corpus did not trigger this defect.

Applied fix: latency is kept in resource accounting/eligibility. The existing
base grader receives a quality-only expectation copy, leaving the caller's
scenario unchanged:

```javascript
const qualityExpect = { ...(scenario.expect || {}) };
delete qualityExpect.max_duration_ms;
delete qualityExpect.latency_is_critical;
const base = evaluateScenario({ ...scenario, expect: qualityExpect }, result);
```

All output/tool/safety and terminal-status checks remain. Both critical and
noncritical pure latency expectations are excluded from quality. The frozen
plan's whole-trial `max_wall_time_ms` still independently applies through
`trialRecord`: exactly at the cap is eligible, over the cap or unknown time is
ineligible, and none of those conditions rewrites answer quality. The separate
shared benchmark grader is unchanged. This comparison does not add a separate
per-scenario latency metric; `scenario.expect.max_duration_ms` no longer gates
its quality, and is not a substitute for the plan's enforced whole-trial cap.

### GAP-03: Duplicate Requests Inflate Task-Type Coverage (P2)

Location: `tools/testing/team-evaluation/lib.mjs:24` (`validateCorpus`).

Copying one scenario's entire request and answers onto another ID/category
previously passed corpus validation. Unique IDs/categories therefore did not guarantee
distinct task content; aliased copies can inflate per-task/type coverage and
overweight one task. This is separate from the intentional scheduled repetitions.

Applied fix: reject identical canonical request digests across different corpus
scenarios, while retaining the existing repetitions in the plan. The existing
structured digest helper sorts nested object keys but preserves array order:

```javascript
const seenRequests = new Set();
for (const scenario of corpus.scenarios) {
  const requestHash = digest(scenario.request);
  requireThat(!seenRequests.has(requestHash), `Duplicate corpus request: ${scenario.id}`);
  seenRequests.add(requestHash);
  // Keep the existing per-scenario rubric validation here.
}
```

This only detects exact structured duplicates. Paraphrases, shared solutions,
or near-duplicate task families require explicit grouping/review; do not label
this check as semantic deduplication or proof of no training contamination.
Tests reject reordered nested-object duplicates, accept meaningful array-order
differences, and retain the full paired schedule at 3, 4, and 10 repetitions.

## Local Execution

Runtime: Windows PowerShell, Node `v24.16.0`. Commands were executed from the
repository root on 2026-10-02. The first runs below preceded source repair:

```powershell
node --test tools/testing/collaboration-equal-budget-contracts.test.mjs
node --test tools/testing/collaboration-equal-budget-gaps.test.mjs
```

| Run | Pass | Fail | Skip/Todo | Exit |
| --- | ---: | ---: | ---: | ---: |
| New contracts | 23 | 0 | 0 | 0 |
| New strict gap regressions | 0 | 3 | 0 | 1 |
| Existing team-evaluation suite, observed execution | 23 | 0 | 0 | 0 |
| Combined new-suite repeat | 23 | 3 | 0 | 1 |

The existing suite was invoked with
`node --test --test-name-pattern='^(?!CLI requires)' tools/testing/team-evaluation/team-evaluation.test.mjs`.
Despite the attempted filter, this runtime executed all 23 tests, including its
existing CLI test. That test used its own temporary directory and cleanup hook;
it did not write source-tree outputs. Do not describe this run as a skipped CLI
test or as live collection.

Strict pre-fix observations: GAP-01 `18 !== 0`; GAP-02 `0 !== 1`; GAP-03
`Missing expected exception`. These tests remain normal assertions, not skipped
or TODO tests. Only their historical file comment was updated; all three strict
regressions now pass after the authorized repair.

The observed contract-suite duration was 280.934 ms and gap-suite duration was
170.806 ms. These are local test-runner timings only, never Agent latency or
cost measurements.

### Post-Fix Verification

The complete comparison command used no name filter, including the existing CLI
test. Its temporary plan/report files were cleaned by the existing test hook.
No actual model results were collected or published.

```powershell
node --test tools/testing/team-evaluation/team-evaluation.test.mjs tools/testing/collaboration-equal-budget-contracts.test.mjs tools/testing/collaboration-equal-budget-gaps.test.mjs
node --test tools/benchmark/agent-benchmark.test.mjs tools/benchmark/agent-regression-dsl.test.mjs
```

| Post-fix run | Pass | Fail | Skip/Todo | Exit |
| --- | ---: | ---: | ---: | ---: |
| Original comparison suite with nine new boundary tests | 32 | 0 | 0 | 0 |
| Independent contracts | 23 | 0 | 0 | 0 |
| Preserved strict GAP-01/02/03 | 3 | 0 | 0 | 0 |
| Complete comparison command | 58 | 0 | 0 | 0 |
| Shared benchmark and regression DSL | 12 | 0 | 0 | 0 |

The nine boundary tests cover all receipt locations independently, marker
spelling/near-match/missing-value cases, later failed calls, all three export
entry points, answer-body isolation, latency criticality and immutability,
preserved safety failures, cap boundaries/unknown time, canonical nested keys,
and retained repetition counts. Complete comparison and shared-suite durations
were 1187.7722 ms and 269.1967 ms respectively, solely test-runner timings.

## Evidence Boundaries

- Whole-trial enforcement, complete ledgers, and context resets are collector
  attestations. These offline tests cannot prove a scheduler actually enforced
  caps or that a worker omitted no failed request, cached tokens, paid tools,
  retries, review, or finalization overhead.
- For collection, bind each repetition to a fresh conversation/context and
  auditable reset receipt; retain original run/call/provider-receipt identity.
  Prevent prior answers, rubric, and the private arm key from entering either
  model context. Do not accept repeated names with newly fabricated IDs as proof
  of independent execution. No strengthened capture schema is implemented here.
- Keep raw audit exports and the arm key away from graders. Screen response
  content for self-identification before human review. Redacted metadata alone
  does not establish effective blinding.
- Keep every predeclared pair, failed attempt, interruption, and unknown cost.
  Report completion/quality, wall time, total tokens, currency cost, rework,
  interventions, and measurement coverage separately. Do not turn UNKNOWN into
  zero, select best-of-N, or claim superiority from these synthetic checks.
- Repetitions within one task are correlated. The fixed public diagnostic
  corpus and exact JSON rubric do not certify general coding, research,
  scientific correctness, statistical significance, or real model quality.

## Baseline Identity

Pre-audit SHA-256 of `tools/testing/team-evaluation/lib.mjs`:
`F0D55645F67C5EC9B6B6FCA5C9AD57FA70FC88DDA0393B2C29AEEC0AA191184B`.

Pre-audit SHA-256 of the existing `team-evaluation.test.mjs`:
`E2CE538231DA75B5A225FA3D34F142993FBAB2A00D7AA38FB0F937207C3F3CEA`.

The worktree was already dirty with unrelated collaboration/Kotlin/version
changes at the start. Those changes were neither reverted nor attributed to
this audit.

Initial audit verification: SHA-256 values for `lib.mjs`, `run.mjs`, `fixture.mjs`, the
existing test suite, schema, corpus, and example config matched their pre-audit
values. Scoped `git diff --check` passed; a separate scan of all three new files
found no trailing whitespace or non-ASCII characters. Git status showed only
the three authorized new audit files in addition to the pre-existing scoped
documentation modification.

After authorized repair, SHA-256 of `lib.mjs` is
`7BA41C912D9750FDCA1728A356E08C621FBDBA26803502484FA563C979E58C8E`,
and of `team-evaluation.test.mjs` is
`AB4543E48708C54B348B8DF5EF0F30A00CC3C8C8AFB928F4BD68B93160FE4C28`.
`run.mjs`, `fixture.mjs`, schema, corpus, and example config still match their
pre-audit hashes. Scoped `git diff --check` passed. No commit or PR was created;
the user retains the changes for a separate repair PR.

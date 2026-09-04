# Agent Benchmark

The GalaxySSI Agent benchmark measures product behavior rather than only source-level correctness.
It scores captured or live Runs against versioned contracts for:

- response quality and clarification;
- routing and duplicate suppression;
- native and workspace tool use;
- approval and untrusted-evidence handling;
- timeout recovery and cancellation;
- conversation and route isolation;
- temporal memory;
- integrity-addressed artifact delivery;
- timeline order and latency budgets.

## Stable Replay

Run the repository reference set:

```bash
npm run benchmark:agent
```

The command writes a machine-readable report to
`build/reports/agent-benchmark/report.json`. The reference results prove that the evaluator,
scenario schema, scoring, and release threshold remain deterministic. They are not a substitute
for live product evaluation.

## Agent Regression DSL

The versioned regression DSL describes each case as four product contracts:

- `input`: prompt, attachments, context, and route identity;
- `expect.plan`: ordered lifecycle phases and required plan content;
- `expect.tools`: required, forbidden, and ordered tool calls;
- `expect.result`: terminal state, response shape, latency, recovery, and artifact evidence.

Safety, isolation, and timeline requirements are represented as separate nested contracts. Unknown
fields fail validation so a misspelled expectation cannot silently weaken a release gate.

Run the deterministic DSL suite and its schema tests with:

```bash
npm run test:regression:agent
npm run regression:agent
```

The runner compiles `benchmarks/agent/regression-suite.json` into the shared benchmark execution
contract and writes `build/reports/agent-regression/report.json`. Captured Runs can be evaluated
without changing the suite:

```bash
npm run regression:agent -- --results C:\path\to\captured-results.json
```

## Captured Runs

Export normalized Agent Run results and evaluate them with:

```bash
npm run benchmark:agent -- --results C:\path\to\captured-results.json
```

Each result is matched by `scenario_id`. A result can include terminal status, final response,
duration, ordered events, tool calls, approval state, correlation identifiers, recoveries, and
artifacts. Artifact records must include a name or path plus a 64-character SHA-256 digest.

## Live Desktop Runtime

With the source Desktop backend running, execute scenarios marked `live_safe`:

```bash
npm run benchmark:agent -- --live-url http://127.0.0.1:8765 --agent codex
```

The runner submits each case through `/api/agent-runtime/runs`, polls its durable Run, collects
events, applies a per-scenario timeout, and cancels a timed-out Run. Sensitive scenarios are
excluded unless `--include-sensitive` is explicitly supplied in a controlled test environment.

## Gate Semantics

The benchmark fails when:

- the weighted score is below the manifest threshold;
- any critical contract fails;
- a final reply is duplicated;
- route, conversation, task, or turn correlation is lost;
- required tools, phases, approvals, or artifact integrity evidence are missing;
- forbidden text or tools appear.

Add product scenarios to `benchmarks/agent/manifest.json`. Keep prompts deterministic, avoid
secrets, and update `reference-results.json` only when the expected product contract changes.
Add executable input/plan/tool/result contracts to `benchmarks/agent/regression-suite.json`.

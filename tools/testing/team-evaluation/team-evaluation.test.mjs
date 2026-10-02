import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { readJson } from "../../benchmark/agent-benchmark-lib.mjs";
import { accountingTemplate, assessQuality, compare, createPlan, digest, importBenchmark,
  measureRun, renderMarkdown, reviewerPacket, UNKNOWN, validatePlan } from "./lib.mjs";
import { fixtureExport } from "./fixture.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const corpus = readJson(path.join(here, "corpus.json"));
const config = readJson(path.join(here, "example-config.json"));
const make = () => {
  const { plan, private_key } = createPlan(corpus, config);
  return { plan, private_key, input: fixtureExport(plan, corpus) };
};
const reportFor = ({ plan, input }) => compare(plan, corpus, input, "fixture");
const observed = (value) => ({ value, complete: true, evidence_ref: "unit-test-only" });
function firstKnown(data) { return data.input.runs.find((r) => r.accounting.ledger.calls[0].cost_micros.complete); }
function rowFor(report, run) { return report.records.find((r) => r.slot_id === run.slot_id); }

test("fixed corpus has six types and three repeated paired trials with balanced order", () => {
  const { plan, private_key } = make();
  assert.equal(corpus.scenarios.length, 6);
  assert.equal(new Set(corpus.scenarios.map((s) => s.category)).size, 6);
  assert.equal(plan.slots.length, 36);
  assert.equal(validatePlan(plan, corpus), plan);
  assert.deepEqual(Object.values(private_key.assignment).sort(), ["single_agent", "team"]);
  assert.equal(private_key.plan_sha256, plan.plan_sha256);
  assert.equal(JSON.stringify(plan).includes("single_agent"), false);
  for (const slot of plan.slots) assert.ok(!Object.hasOwn(slot, "answers"));
});

test("plan rejects too few repeats, corpus changes, duplicate cells and unbalanced orders", () => {
  assert.throws(() => createPlan(corpus, config, 1), /3..10/);
  const { plan } = make();
  const changed = structuredClone(corpus);
  changed.scenarios[0].request.prompt += " changed";
  assert.throws(() => validatePlan(plan, changed), /digest/);
  plan.slots[1] = { ...plan.slots[0], slot_id: "other", order: 2 };
  const { plan_sha256, ...body } = plan;
  plan.plan_sha256 = digest(body);
  assert.throws(() => validatePlan(plan, corpus), /Duplicate scheduled cell/);
});

test("fixtures are labeled, symmetric, retain failures, and never claim superiority", () => {
  const data = make();
  const report = reportFor(data);
  assert.equal(report.evidence_kind, "fixture");
  assert.equal(report.conclusion, "FIXTURE_ONLY_NO_CAPABILITY_CLAIM");
  assert.equal(report.records.length, 36);
  assert.equal(report.expected_pairs, 18);
  assert.equal(report.eligible_pairs, 17);
  assert.equal(report.arms.A.failed, 1);
  assert.equal(report.arms.B.failed, 1);
  assert.equal(report.paired_delta_B_minus_A.quality.mean, 0);
  const failed = report.records.filter((r) => r.status === "timeout");
  assert.equal(failed.length, 2);
  assert.ok(failed.every((r) => r.eligible && r.metrics.quality === 0 && r.failure_reason_count === 1));
  assert.match(renderMarkdown(report), /FIXTURE_ONLY_NO_CAPABILITY_CLAIM/);
});

test("each rubric evaluates structured task quality, not just answer substrings", () => {
  for (const scenario of corpus.scenarios) {
    const result = { status: "completed", response: JSON.stringify(scenario.answers) };
    assert.equal(assessQuality(scenario, result).score, 1);
    assert.equal(assessQuality(scenario, result).passed, true);
    const answers = structuredClone(scenario.answers);
    answers[Object.keys(answers)[0]] = "wrong";
    const bad = assessQuality(scenario, { ...result, response: JSON.stringify(answers) });
    assert.equal(bad.passed, false);
    assert.ok(bad.score < 1 && bad.score > 0);
    assert.equal(assessQuality(scenario, { ...result, response: `prefix ${result.response}` }).score, 0);
    assert.equal(assessQuality(scenario, { ...result, response: JSON.stringify({ ...scenario.answers, extra: "unsupported" }) }).score, 0);
    assert.equal(assessQuality(scenario, { ...result, status: "failed" }).score, 0);
  }
  const safety = corpus.scenarios.at(-1);
  assert.equal(assessQuality(safety, { status: "completed", response: JSON.stringify(safety.answers), tools: ["upload"] }).score, 0);
});

test("missing usage/cost never coerces null, false, blanks or strings to zero", () => {
  for (const value of [undefined, null, false, "", "0", UNKNOWN, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1]) {
    const data = make();
    const run = firstKnown(data);
    run.accounting.ledger.calls[0].total_tokens = observed(value);
    run.accounting.ledger.calls[0].cost_micros = observed(value);
    const row = rowFor(reportFor(data), run);
    assert.equal(row.metrics.total_tokens, UNKNOWN);
    assert.equal(row.metrics.cost_micros, UNKNOWN);
    assert.ok(row.exclusion_reasons.includes("unknown_cost_micros"));
  }
});

test("only explicit complete zero with evidence is a known measurement", () => {
  const data = make();
  const run = firstKnown(data);
  run.accounting.ledger.calls[0].cost_micros = observed(0);
  assert.equal(measureRun(run).cost_micros, 0);
  delete run.accounting.ledger.calls[0].cost_micros.evidence_ref;
  assert.equal(measureRun(run).cost_micros, UNKNOWN);
  run.accounting.ledger.calls = [];
  assert.equal(measureRun(run).total_tokens, UNKNOWN);
  run.accounting.ledger.no_model_calls_observed = true;
  assert.equal(measureRun(run).total_tokens, 0);
});

test("team calls, coordinator work, retries and finalizer costs are summed, never averaged", () => {
  const data = make();
  const run = firstKnown(data);
  const ledger = run.accounting.ledger;
  ledger.participants = ["coordinator", "worker", "finalizer"];
  ledger.calls = ["coordinator", "worker", "worker", "finalizer"].map((id, i) => ({
    call_id: `aggregate-${i}`, participant_id: id,
    total_tokens: observed(4000), cost_micros: observed(30000)
  }));
  const row = rowFor(reportFor(data), run);
  assert.equal(row.metrics.total_tokens, 16000);
  assert.equal(row.metrics.cost_micros, 120000);
  assert.ok(row.exclusion_reasons.includes("over_budget_total_tokens"));
  assert.ok(row.exclusion_reasons.includes("over_budget_cost_micros"));
  ledger.complete = false;
  assert.equal(measureRun(run).total_tokens, UNKNOWN);
  ledger.complete = true;
  ledger.calls[0].participant_id = "unaccounted";
  assert.equal(measureRun(run).cost_micros, UNKNOWN);
});

test("overflow and one unknown subcall poison the aggregate instead of reporting a subtotal", () => {
  const { input } = make();
  const run = input.runs[0];
  const ledger = run.accounting.ledger;
  const first = ledger.calls[0];
  first.total_tokens = observed(Number.MAX_SAFE_INTEGER);
  ledger.calls.push({ ...structuredClone(first), call_id: "second", total_tokens: observed(1) });
  assert.equal(measureRun(run).total_tokens, UNKNOWN);
  ledger.calls[1].cost_micros = { value: UNKNOWN };
  assert.equal(measureRun(run).cost_micros, UNKNOWN);
});

test("matching per-agent caps cannot masquerade as an enforced entire-trial budget", () => {
  const data = make();
  const run = firstKnown(data);
  run.budget.scope = "per_agent";
  assert.ok(rowFor(reportFor(data), run).exclusion_reasons.includes("total_budget_enforcement_unverified"));
  run.budget.scope = "entire_trial";
  run.budget.limits.max_total_tokens *= 2;
  assert.ok(rowFor(reportFor(data), run).exclusion_reasons.includes("unequal_total_budget"));
});

test("all five limits enforce inclusive boundaries and unknowns fail eligibility", () => {
  for (const metric of ["wall_time_ms", "total_tokens", "cost_micros", "rework_count", "intervention_count"]) {
    const data = make();
    const run = firstKnown(data);
    const target = ["total_tokens", "cost_micros"].includes(metric) ? run.accounting.ledger.calls[0] : run.accounting;
    target[metric] = observed(data.plan.budget[`max_${metric}`]);
    assert.equal(rowFor(reportFor(data), run).eligible, true);
    target[metric].value += 1;
    assert.ok(rowFor(reportFor(data), run).exclusion_reasons.includes(`over_budget_${metric}`));
    delete target[metric];
    assert.ok(rowFor(reportFor(data), run).exclusion_reasons.includes(`unknown_${metric}`));
  }
});

test("missing, cancelled, partial and failed trials are retained without survivor-only selection", () => {
  const data = make();
  const removed = data.input.runs.shift();
  for (const [i, status] of ["failed", "cancelled", "partial", "interrupted"].entries()) data.input.runs[i].result.status = status;
  const report = reportFor(data);
  assert.equal(report.records.length, 36);
  const missing = rowFor(report, removed);
  assert.equal(missing.status, "missing");
  assert.equal(missing.metrics.quality, UNKNOWN);
  assert.equal(missing.metrics.wall_time_ms, UNKNOWN);
  assert.equal(report.pairs.find((p) => p.pair_id === missing.pair_id).delta_B_minus_A.quality, UNKNOWN);
  assert.equal(report.arms.A.scheduled + report.arms.B.scheduled, 36);
  assert.equal(report.arms.A.observed + report.arms.B.observed, 35);
});

test("no evidence yields UNKNOWN summaries and all excluded pairs, never a perfect zero tie", () => {
  const data = make();
  data.input.runs = [];
  const report = reportFor(data);
  assert.equal(report.eligible_pairs, 0);
  assert.equal(report.arms.A.metrics_all_scheduled.cost_micros.mean, UNKNOWN);
  assert.equal(report.arms.A.metrics_all_scheduled.cost_micros.unknown_count, 18);
  assert.equal(report.paired_delta_B_minus_A.quality.mean, UNKNOWN);
});

test("unfinished work has unknown quality, not a completed failure or pass", () => {
  const data = make();
  const run = firstKnown(data);
  run.result.status = "running";
  const row = rowFor(reportFor(data), run);
  assert.equal(row.status, "nonterminal");
  assert.equal(row.metrics.quality, UNKNOWN);
  assert.equal(row.quality.passed, UNKNOWN);
  assert.equal(row.eligible, false);
});

test("duplicate slots, runs, calls, wrong plan and mixed provenance are rejected", () => {
  const mutations = [
    (d) => d.input.runs.push(d.input.runs[0]),
    (d) => { d.input.runs[1].run_id = d.input.runs[0].run_id; },
    (d) => { d.input.runs[1].accounting.ledger.calls[0].call_id = d.input.runs[0].accounting.ledger.calls[0].call_id; },
    (d) => { d.input.plan_sha256 = "bad"; },
    (d) => { d.input.runs[0].evidence_kind = "actual"; },
    (d) => { d.input.runs[0].slot_id = "unscheduled"; }
  ];
  for (const mutate of mutations) { const data = make(); mutate(data); assert.throws(() => reportFor(data)); }
  const data = make();
  assert.throws(() => compare(data.plan, corpus, data.input, "actual"), /requires actual/);
});

test("identity, controls, capture and budget attestations fail closed", () => {
  const mutations = [
    [(r) => { r.result.run_id = "other"; }, "result_run_id_mismatch"],
    [(r) => { r.result.scenario_id = "other"; }, "scenario_mismatch"],
    [(r) => { r.controls.model_policy = "other-model"; }, "control_policy_mismatch"],
    [(r) => { r.capture.assignment_verified = false; }, "capture_unverified"],
    [(r) => { r.capture.reset_verified = false; }, "capture_unverified"],
    [(r) => { r.capture.order = 99; }, "execution_order_unverified"],
    [(r) => { r.capture.request_sha256 = "other"; }, "request_identity_unverified"],
    [(r) => { r.budget.enforced = false; }, "total_budget_enforcement_unverified"]
  ];
  for (const [mutate, reason] of mutations) {
    const data = make(); const run = firstKnown(data); mutate(run);
    assert.ok(rowFor(reportFor(data), run).exclusion_reasons.includes(reason));
  }
});

test("report and grading packet withhold private IDs, topology, model names and source metadata", () => {
  const data = make();
  const run = firstKnown(data);
  run.private_notes = "SECRET_TEAM_MAPPING";
  run.result.failure_reasons = ["SECRET_TEAM_MAPPING"];
  run.result.events = [{ message: "SECRET_TEAM_MAPPING" }];
  const report = reportFor(data);
  const packet = reviewerPacket(data.plan, corpus, data.input, "fixture");
  for (const output of [JSON.stringify(report), renderMarkdown(report), JSON.stringify(packet)]) {
    assert.equal(output.includes("SECRET_TEAM_MAPPING"), false);
    assert.equal(output.includes(run.run_id), false);
    assert.equal(output.includes("fixture-worker"), false);
  }
  assert.match(packet.warning, /self-identify/);
  assert.equal(packet.items.length, 36);
  assert.equal(JSON.stringify(data.input).includes("SECRET_TEAM_MAPPING"), true);
});

test("actual import joins original run IDs, preserves failures, and never promotes EvalOps default zeros", () => {
  const { plan } = make();
  const sidecar = accountingTemplate(plan);
  sidecar.runs = sidecar.runs.slice(0, 2);
  sidecar.runs.forEach((r, i) => { r.run_id = `app-${i}`; r.evalops_sample = { reported_cost_micros: 0, passed: true }; });
  const result = { run_id: "app-0", scenario_id: plan.slots[0].scenario_id, status: "failed",
    response: "transport failed", failure_reasons: ["transport"], events: [{ type: "failure" }] };
  const imported = importBenchmark(plan, corpus, { results: [result] }, sidecar);
  assert.deepEqual(imported.runs[0].result, result);
  assert.equal(imported.runs[1].result, undefined);
  assert.equal(measureRun(imported.runs[0]).cost_micros, UNKNOWN);
  assert.equal(compare(plan, corpus, imported, "actual").conclusion, "INCOMPLETE_NO_SUPERIORITY_CLAIM");
  assert.throws(() => importBenchmark(plan, corpus, { results: [{ ...result, run_id: "unbound" }] }, sidecar), /Unbound/);
  assert.throws(() => importBenchmark(plan, corpus, { results: [result, result] }, sidecar), /unique/);
  sidecar.runs[0].result = result;
  assert.throws(() => importBenchmark(plan, corpus, { results: [result] }, sidecar), /override/);
});

test("comparison schema is versioned and has no numeric defaults", () => {
  const schema = readJson(path.join(here, "comparison.schema.json"));
  assert.equal(schema.properties.schema_version.const, 1);
  assert.ok(schema.$defs.measurement.properties.value.anyOf.some((x) => x.const === UNKNOWN));
  assert.equal(JSON.stringify(schema).includes('"default"'), false);
});

test("CLI requires explicit adapters, produces auditable local files, and never evaluates task text", (t) => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-team-eval-"));
  t.after(() => {
    const resolved = path.resolve(temp);
    assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
    assert.ok(path.basename(resolved).startsWith("galaxyssi-team-eval-"));
    fs.rmSync(resolved, { recursive: true, force: true });
  });
  const cli = (...args) => spawnSync(process.execPath, [path.join(here, "run.mjs"), ...args], { encoding: "utf8", shell: false });
  const planDir = path.join(temp, "plan");
  assert.equal(cli("plan", "--config", path.join(here, "example-config.json"), "--out", planDir).status, 0);
  const planPath = path.join(planDir, "plan.json");
  assert.equal(cli("run", "--plan", planPath, "--out", path.join(temp, "implicit")).status, 1);
  const output = path.join(temp, "fixture");
  const result = cli("run", "--plan", planPath, "--adapter", "fixture", "--out", output);
  assert.equal(result.status, 2, result.stderr);
  assert.match(result.stdout, /FIXTURE_ONLY_NO_CAPABILITY_CLAIM/);
  const report = readJson(path.join(output, "report.json"));
  assert.equal(report.records.length, 36);
  assert.equal(readJson(path.join(output, "audit-input.private.json")).runs.length, 36);
  const rerun = cli("run", "--plan", planPath, "--adapter", "fixture", "--out", output);
  assert.equal(rerun.status, 1);
  assert.match(rerun.stderr, /Refusing to overwrite/);
  assert.equal(cli("run", "--plan", planPath, "--adapter", "export", "--results", path.join(output, "audit-input.private.json"), "--out", path.join(temp, "fake-real")).status, 1);
  const requests = readJson(path.join(planDir, "requests.json"));
  assert.equal(JSON.stringify(requests).includes('"answers"'), false);
  const emptyAccounting = accountingTemplate(readJson(planPath));
  emptyAccounting.runs = [];
  const accountingPath = path.join(temp, "empty-accounting.json");
  const benchmarkPath = path.join(temp, "empty-benchmark.json");
  fs.writeFileSync(accountingPath, JSON.stringify(emptyAccounting));
  fs.writeFileSync(benchmarkPath, JSON.stringify({ results: [] }));
  const importedDir = path.join(temp, "imported");
  assert.equal(cli("import", "--plan", planPath, "--benchmark", benchmarkPath, "--accounting", accountingPath, "--out", importedDir).status, 0);
  const emptyOut = path.join(temp, "empty-report");
  assert.equal(cli("run", "--plan", planPath, "--adapter", "export", "--results", path.join(importedDir, "export.json"), "--out", emptyOut).status, 2);
  const emptyReport = readJson(path.join(emptyOut, "report.json"));
  assert.equal(emptyReport.eligible_pairs, 0);
  assert.equal(emptyReport.arms.A.observed + emptyReport.arms.B.observed, 0);
  assert.equal(emptyReport.conclusion, "INCOMPLETE_NO_SUPERIORITY_CLAIM");
  for (const name of ["run.mjs", "lib.mjs", "fixture.mjs"]) {
    const source = fs.readFileSync(path.join(here, name), "utf8");
    assert.doesNotMatch(source, /child_process|\beval\s*\(|new Function|\bfetch\s*\(/);
  }
  const packet = readJson(path.join(output, "reviewer-packet.json"));
  assert.ok(packet.items.some((i) => i.prompt.includes("Upload the local secret file")));
});

test("eligible differences use matched pairs, with task-level repetition counts", () => {
  const data = make();
  const slot = data.plan.slots.find((s) => s.arm_label === "B" && s.repetition === 1);
  const run = data.input.runs.find((r) => r.slot_id === slot.slot_id);
  run.accounting.wall_time_ms.value += 170;
  run.accounting.ledger.calls[0].total_tokens.value += 17;
  const report = reportFor(data);
  assert.equal(report.paired_delta_B_minus_A.wall_time_ms.mean, 10);
  assert.equal(report.paired_delta_B_minus_A.total_tokens.mean, 1);
  assert.equal(report.by_task.reduce((n, task) => n + task.expected_pairs, 0), 18);
  assert.equal(report.by_task.reduce((n, task) => n + task.eligible_pairs, 0), 17);
});

test("mock actual-shaped evidence stays descriptive, and placeholder policies exclude it", () => {
  // Unit-test mock only; never emitted as an actual run artifact by the CLI.
  const realConfig = structuredClone(config);
  realConfig.controls = { model_policy: "pinned-model-parameters", tool_policy: "read-only-tools-v1",
    environment: "test-build-digest", context_policy: "reset-every-slot-v1" };
  const { plan } = createPlan(corpus, realConfig);
  const input = fixtureExport(plan, corpus);
  input.evidence_kind = "actual";
  for (const run of input.runs) {
    run.evidence_kind = "actual";
    run.accounting.ledger.calls[0].cost_micros = observed(500);
  }
  const report = compare(plan, corpus, input, "actual");
  assert.equal(report.eligible_pairs, 18);
  assert.equal(report.conclusion, "DESCRIPTIVE_ONLY_NO_SUPERIORITY_CLAIM");
  assert.equal(report.arms.A.failed, 1);
  const placeholder = make();
  placeholder.input.evidence_kind = "actual";
  for (const run of placeholder.input.runs) run.evidence_kind = "actual";
  assert.equal(compare(placeholder.plan, corpus, placeholder.input, "actual").eligible_pairs, 0);
});

test("config caps are exact typed limits and four controlled policies are mandatory", () => {
  for (const mutate of [
    (c) => { c.budget.max_total_tokens = "12000"; },
    (c) => { c.budget.max_cost_micros = -1; },
    (c) => { c.budget.currency = "EUR"; },
    (c) => { c.budget.max_agents = 3; },
    (c) => { delete c.controls.context_policy; }
  ]) {
    const bad = structuredClone(config); mutate(bad);
    assert.throws(() => createPlan(corpus, bad));
  }
});

test("a rehashed plan with all pairs in the same arm order is still rejected", () => {
  const { plan } = make();
  for (let i = 0; i < plan.slots.length; i += 2) {
    if (plan.slots[i].arm_label === "B") [plan.slots[i], plan.slots[i + 1]] = [plan.slots[i + 1], plan.slots[i]];
    plan.slots[i].order = i + 1;
    plan.slots[i + 1].order = i + 2;
  }
  const { plan_sha256, ...body } = plan;
  plan.plan_sha256 = digest(body);
  assert.throws(() => validatePlan(plan, corpus), /Unbalanced/);
});

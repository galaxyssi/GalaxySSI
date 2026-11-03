import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { compare, createPlan, digest, measureRun, renderMarkdown, reviewerPacket, UNKNOWN } from "./team-evaluation/lib.mjs";
import { fixtureExport } from "./team-evaluation/fixture.mjs";

// In-memory synthetic contract tests only. No model calls or actual-quality evidence.
const read = (name) => JSON.parse(readFileSync(new URL(`./team-evaluation/${name}`, import.meta.url), "utf8"));
const corpus = read("corpus.json");
const config = read("example-config.json");
const observed = (value) => ({ value, complete: true, evidence_ref: "FIXTURE_ONLY:independent-audit" });
function make() {
  const { plan } = createPlan(corpus, config);
  return { plan, input: fixtureExport(plan, corpus) };
}
function selected(data, arm = "A", repetition = 1) {
  const slot = data.plan.slots.find((s) => s.scenario_id === "dependency-plan" && s.arm_label === arm && s.repetition === repetition);
  return data.input.runs.find((r) => r.slot_id === slot.slot_id);
}
const reportFor = (data) => compare(data.plan, corpus, data.input, "fixture");
const rowFor = (data, run) => reportFor(data).records.find((r) => r.slot_id === run.slot_id);
function setCalls(run, definitions) {
  run.accounting.ledger.participants = [...new Set(definitions.map((d) => d.participant))];
  run.accounting.ledger.calls = definitions.map((d, index) => ({
    call_id: `${run.run_id}-audit-${index}`, participant_id: d.participant,
    status: d.status ?? "completed", total_tokens: observed(d.tokens), cost_micros: observed(d.cost)
  }));
}

test("six workers and coordinator/reviewer/finalizer consume one shared cap", () => {
  const data = make();
  const run = selected(data);
  const roles = ["coordinator", ...Array.from({ length: 6 }, (_, i) => `worker-${i}`), "reviewer", "finalizer"];
  setCalls(run, roles.map((participant) => ({ participant, tokens: 1400, cost: 12000 })));
  const row = rowFor(data, run);
  assert.deepEqual(run.budget.limits, data.plan.budget);
  assert.equal(row.metrics.total_tokens, 12600);
  assert.equal(row.metrics.cost_micros, 108000);
  assert.ok(row.exclusion_reasons.includes("over_budget_total_tokens"));
  assert.ok(row.exclusion_reasons.includes("over_budget_cost_micros"));
  assert.equal(row.metrics.quality, 1);
});

test("participant count does not scale the entire-trial cap", () => {
  for (const count of [1, 2, 6]) {
    const data = make();
    const run = selected(data);
    setCalls(run, Array.from({ length: count }, (_, i) => ({ participant: `worker-${i}`, tokens: 1, cost: 1 })));
    run.budget.limits.max_total_tokens *= 2;
    assert.ok(rowFor(data, run).exclusion_reasons.includes("unequal_total_budget"));
  }
});

test("failed, cancelled and interrupted calls plus retries remain billable", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [
    { participant: "coordinator", tokens: 100, cost: 700 },
    { participant: "worker", status: "failed", tokens: 200, cost: 1100 },
    { participant: "worker", status: "cancelled", tokens: 50, cost: 300 },
    { participant: "worker", status: "interrupted", tokens: 60, cost: 400 },
    { participant: "worker", tokens: 300, cost: 1500 },
    { participant: "finalizer", tokens: 80, cost: 500 }
  ]);
  run.accounting.rework_count = observed(3);
  assert.deepEqual(measureRun(run), { wall_time_ms: 1100, total_tokens: 790, cost_micros: 4500, rework_count: 3, intervention_count: 0 });
  assert.equal(rowFor(data, run).eligible, true);
});

test("retry overhead alone can exceed the cap after initial work fits", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "worker", status: "failed", tokens: 11000, cost: 99000 },
    { participant: "worker", tokens: 1001, cost: 1001 }]);
  run.accounting.rework_count = observed(1);
  const row = rowFor(data, run);
  assert.equal(row.metrics.total_tokens, 12001);
  assert.equal(row.metrics.cost_micros, 100001);
  assert.equal(row.eligible, false);
  assert.equal(row.status, "completed");
});

test("terminal failure retains all resource observations and remains paired", () => {
  for (const status of ["failed", "timeout", "partial", "cancelled", "interrupted"]) {
    const data = make();
    const run = selected(data);
    const before = measureRun(run);
    run.result.status = status;
    const row = rowFor(data, run);
    assert.equal(row.eligible, true, status);
    assert.equal(row.metrics.quality, 0, status);
    assert.deepEqual(measureRun(run), before);
    assert.equal(reportFor(data).records.length, data.plan.slots.length);
  }
});

test("call ordering and participant labels cannot change totals", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "coordinator", tokens: 17, cost: 19 }, { participant: "worker", tokens: 23, cost: 29 }]);
  const before = measureRun(run);
  run.accounting.ledger.calls.reverse();
  run.accounting.ledger.participants = ["renamed-0", "renamed-1"];
  run.accounting.ledger.calls.forEach((call, index) => { call.participant_id = `renamed-${index}`; });
  assert.deepEqual(measureRun(run), before);
});

test("splitting a metered call preserves tokens and cost, not maximum-worker usage", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "worker", tokens: 100, cost: 1000 }]);
  const before = measureRun(run);
  setCalls(run, [{ participant: "worker", tokens: 40, cost: 400 }, { participant: "worker", tokens: 60, cost: 600 }]);
  assert.deepEqual(measureRun(run), before);
});

test("wall time is the trial observation, not summed concurrent worker durations", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "worker-0", tokens: 10, cost: 20 }, { participant: "worker-1", tokens: 10, cost: 20 }]);
  run.accounting.ledger.calls.forEach((call) => { call.duration_ms = 800; });
  run.accounting.wall_time_ms = observed(1250);
  assert.equal(measureRun(run).wall_time_ms, 1250);
  delete run.accounting.wall_time_ms;
  assert.equal(measureRun(run).wall_time_ms, UNKNOWN);
});

test("paid tools with explicit zero model tokens still consume the cost budget", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "worker", tokens: 10, cost: 100 }, { participant: "worker", tokens: 0, cost: 100000 }]);
  const row = rowFor(data, run);
  assert.equal(row.metrics.total_tokens, 10);
  assert.equal(row.metrics.cost_micros, 100100);
  assert.ok(row.exclusion_reasons.includes("over_budget_cost_micros"));
});

test("unknown cost on any role or failed retry poisons cost only", () => {
  for (const unknownIndex of [0, 1, 2, 3]) {
    const data = make();
    const run = selected(data);
    setCalls(run, ["coordinator", "worker", "retry", "finalizer"].map((participant) => ({ participant, tokens: 10, cost: 20 })));
    run.accounting.ledger.calls[unknownIndex].status = "failed";
    run.accounting.ledger.calls[unknownIndex].cost_micros = { value: UNKNOWN, complete: false };
    const row = rowFor(data, run);
    assert.equal(row.metrics.cost_micros, UNKNOWN);
    assert.equal(row.metrics.total_tokens, 40);
    assert.equal(row.metrics.quality, 1);
    assert.ok(row.exclusion_reasons.includes("unknown_cost_micros"));
    const pair = reportFor(data).pairs.find((p) => p.pair_id === row.pair_id);
    assert.equal(pair.delta_B_minus_A.cost_micros, UNKNOWN);
  }
});

test("zero requires a complete nonblank receipt; no default coercion", () => {
  const data = make();
  const run = selected(data);
  const call = run.accounting.ledger.calls[0];
  for (const raw of [undefined, null, 0, { value: 0 }, { ...observed(0), complete: false },
    { ...observed(0), evidence_ref: " " }, observed("0"), observed(false), observed(null)]) {
    call.cost_micros = raw;
    assert.equal(measureRun(run).cost_micros, UNKNOWN);
  }
  call.cost_micros = observed(0);
  assert.equal(measureRun(run).cost_micros, 0);
});

test("overflow is unknown independently for each additive resource", () => {
  const data = make();
  const run = selected(data);
  setCalls(run, [{ participant: "worker", tokens: 1, cost: Number.MAX_SAFE_INTEGER }, { participant: "worker", tokens: 2, cost: 1 }]);
  assert.equal(measureRun(run).cost_micros, UNKNOWN);
  assert.equal(measureRun(run).total_tokens, 3);
});

test("incomplete retry capture cannot expose a known successful-call subtotal", () => {
  const data = make();
  const run = selected(data);
  run.accounting.ledger.complete = false;
  run.accounting.rework_count = observed(1);
  const row = rowFor(data, run);
  assert.equal(row.metrics.total_tokens, UNKNOWN);
  assert.equal(row.metrics.cost_micros, UNKNOWN);
  assert.equal(row.metrics.rework_count, 1);
  assert.equal(row.eligible, false);
});

test("reviewer packet and report redact private identifiers from all metadata paths", () => {
  const data = make();
  const run = selected(data);
  const secret = "PRIVATE_AUDIT_SENTINEL_PROVIDER_TOPOLOGY";
  run.run_id = secret;
  run.result.run_id = secret;
  run.result.provider = secret;
  run.result.events = [{ message: secret }];
  run.result.failure_reasons = [secret];
  run.capture.evidence_ref = secret;
  run.budget.evidence_ref = secret;
  run.accounting.ledger.evidence_ref = secret;
  run.accounting.ledger.participants = [secret];
  run.accounting.ledger.calls[0].participant_id = secret;
  run.accounting.ledger.calls[0].call_id = secret;
  run.accounting.ledger.calls[0].cost_micros.evidence_ref = secret;
  const report = reportFor(data);
  const packet = reviewerPacket(data.plan, corpus, data.input, "fixture");
  for (const output of [JSON.stringify(report), renderMarkdown(report), JSON.stringify(packet)]) {
    assert.equal(output.includes(secret), false);
  }
  for (const item of packet.items) assert.deepEqual(Object.keys(item).sort(), ["arm_label", "prompt", "response", "scenario_id", "slot_id", "status"]);
  assert.equal(JSON.stringify(data.input).includes(secret), true);
});

test("reviewer packet is unchanged when only accounting changes", () => {
  const data = make();
  const before = reviewerPacket(data.plan, corpus, data.input, "fixture");
  const run = selected(data);
  run.accounting.wall_time_ms = observed(90000);
  run.accounting.ledger.calls[0].cost_micros = observed(99999);
  run.accounting.ledger.calls[0].total_tokens = observed(11999);
  assert.deepEqual(reviewerPacket(data.plan, corpus, data.input, "fixture"), before);
});

test("raw-answer self-identification is preserved with a warning, not certified blind", () => {
  const data = make();
  const run = selected(data);
  run.result.response = "FIXTURE_ONLY: I used a team of six agents.";
  const packet = reviewerPacket(data.plan, corpus, data.input, "fixture");
  assert.equal(packet.items.find((item) => item.slot_id === run.slot_id).response, run.result.response);
  assert.match(packet.warning, /self-identify.*content leakage/);
});

test("over-budget cost and time exclude eligibility without rewriting answer quality", () => {
  const data = make();
  const run = selected(data);
  const before = rowFor(data, run).quality;
  run.accounting.wall_time_ms = observed(data.plan.budget.max_wall_time_ms + 1);
  run.accounting.ledger.calls[0].cost_micros = observed(data.plan.budget.max_cost_micros + 1);
  const after = rowFor(data, run);
  assert.deepEqual(after.quality, before);
  assert.equal(after.eligible, false);
  assert.equal(after.metrics.quality, 1);
});

test("answer correctness changes without changing resource accounting", () => {
  const data = make();
  const run = selected(data);
  const before = measureRun(run);
  const response = JSON.parse(run.result.response);
  response.total_minutes = 99;
  run.result.response = JSON.stringify(response);
  const row = rowFor(data, run);
  assert.equal(row.metrics.quality, 2 / 3);
  assert.equal(row.quality.passed, false);
  assert.deepEqual(measureRun(run), before);
});

test("quality, latency, tokens and money remain separate report dimensions", () => {
  const data = make();
  const a = selected(data, "A");
  const b = selected(data, "B");
  const answer = JSON.parse(b.result.response);
  answer.total_minutes = 99;
  b.result.response = JSON.stringify(answer);
  b.accounting.wall_time_ms.value -= 100;
  b.accounting.ledger.calls[0].total_tokens.value += 10;
  b.accounting.ledger.calls[0].cost_micros.value += 20;
  const report = reportFor(data);
  const pair = report.pairs.find((p) => p.pair_id === rowFor(data, a).pair_id);
  assert.equal(pair.delta_B_minus_A.wall_time_ms, -100);
  assert.equal(pair.delta_B_minus_A.total_tokens, 10);
  assert.equal(pair.delta_B_minus_A.cost_micros, 20);
  assert.equal(pair.delta_B_minus_A.quality, 2 / 3 - 1);
  assert.equal(report.conclusion, "FIXTURE_ONLY_NO_CAPABILITY_CLAIM");
  assert.equal(Object.hasOwn(report, "winner"), false);
  for (const metric of ["quality", "wall_time_ms", "cost_micros", "total_tokens"]) assert.ok(renderMarkdown(report).includes(`| ${metric} |`));
});

test("repeated identical task prompts require distinct run and call identities", () => {
  for (const identity of ["run", "call", "slot"]) {
    const data = make();
    const first = selected(data, "A", 1);
    const second = selected(data, "A", 2);
    assert.equal(first.capture.request_sha256, second.capture.request_sha256);
    if (identity === "run") second.run_id = first.run_id;
    if (identity === "call") second.accounting.ledger.calls[0].call_id = first.accounting.ledger.calls[0].call_id;
    if (identity === "slot") second.slot_id = first.slot_id;
    assert.throws(() => reportFor(data), /Duplicate|reused/);
  }
});

test("each repetition needs its own reset, request and order attestations", () => {
  for (const mutation of [
    (run) => { run.capture.reset_verified = false; },
    (run) => { delete run.capture.reset_verified; },
    (run) => { run.capture.order = 0; },
    (run) => { run.capture.request_sha256 = digest("different request"); }
  ]) {
    const data = make();
    const run = selected(data, "A", 2);
    mutation(run);
    assert.equal(rowFor(data, run).eligible, false);
    assert.equal(rowFor(data, selected(data, "A", 1)).eligible, true);
  }
});

test("lost repetitions remain in denominators instead of best-of-N selection", () => {
  const data = make();
  const run = selected(data, "A", 2);
  data.input.runs = data.input.runs.filter((r) => r !== run);
  const report = reportFor(data);
  assert.equal(report.records.length, 36);
  assert.equal(report.expected_pairs, 18);
  assert.equal(report.arms.A.scheduled, 18);
  assert.equal(report.arms.A.observed, 17);
  assert.equal(report.arms.A.unknown_quality, 1);
  assert.equal(report.by_task.find((t) => t.scenario_id === "dependency-plan").expected_pairs, 3);
});

test("reporting is deterministic and leaves private input untouched", () => {
  const data = make();
  const before = structuredClone(data);
  const first = reportFor(data);
  reviewerPacket(data.plan, corpus, data.input, "fixture");
  assert.deepEqual(reportFor(data), first);
  assert.deepEqual(data, before);
  assert.equal(first.evidence_kind, "fixture");
});

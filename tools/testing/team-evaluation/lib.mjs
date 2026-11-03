import { createHash, randomBytes, randomInt } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { evaluateScenario, validateManifest } from "../../benchmark/agent-benchmark-lib.mjs";
import { assignedSummary } from "./assigned-outcomes.mjs";

export const UNKNOWN = "UNKNOWN";
export const ARMS = ["A", "B"];
export const METRICS = ["wall_time_ms", "total_tokens", "cost_micros", "rework_count", "intervention_count", "quality"];
const CAP = Object.fromEntries(METRICS.filter((key) => key !== "quality").map((key) => [key, `max_${key}`]));
const CONTROLS = ["model_policy", "tool_policy", "environment", "context_policy"];
const TERMINAL = ["completed", "failed", "cancelled", "interrupted", "partial", "timeout"];
const text = (value) => typeof value === "string" && value.trim().length > 0;
const integer = (value) => Number.isSafeInteger(value) && value >= 0;
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
function requireThat(condition, message) { if (!condition) throw new Error(message); }

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (object(value)) return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
export function digest(value) {
  return createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");
}
export function validateCorpus(corpus) {
  validateManifest(corpus);
  requireThat(corpus.scenarios.length >= 3 && new Set(corpus.scenarios.map((s) => s.category)).size >= 3,
    "Corpus needs at least three task types");
  const seenRequests = new Set();
  for (const scenario of corpus.scenarios) {
    const requestHash = digest(scenario.request);
    requireThat(!seenRequests.has(requestHash), `Duplicate corpus request: ${scenario.id}`);
    seenRequests.add(requestHash);
    requireThat(object(scenario.answers) && Object.keys(scenario.answers).length > 0, `Missing rubric: ${scenario.id}`);
  }
  return corpus;
}
export function validateConfig(config) {
  requireThat(object(config?.budget), "Missing total budget");
  requireThat(isDeepStrictEqual(Object.keys(config.budget).sort(), [...Object.values(CAP), "currency"].sort()),
    "Budget must specify exactly all total caps and currency");
  for (const cap of Object.values(CAP)) requireThat(integer(config.budget[cap]), `Invalid cap: ${cap}`);
  for (const cap of ["max_wall_time_ms", "max_total_tokens", "max_cost_micros"]) {
    requireThat(config.budget[cap] > 0, `Cap must be positive: ${cap}`);
  }
  requireThat(config.budget.currency === "USD", "Version 1 requires USD micro-units");
  requireThat(object(config.controls) && isDeepStrictEqual(Object.keys(config.controls).sort(), [...CONTROLS].sort()),
    "Specify exactly the four controlled policies");
  for (const key of CONTROLS) requireThat(text(config.controls[key]), `Missing control: ${key}`);
}

export function createPlan(corpus, config, repetitions = 3) {
  validateCorpus(corpus);
  validateConfig(config);
  requireThat(Number.isInteger(repetitions) && repetitions >= 3 && repetitions <= 10, "Repetitions must be 3..10");
  const pairs = [];
  for (const scenario of corpus.scenarios) {
    const first = randomInt(2);
    for (let repetition = 1; repetition <= repetitions; repetition += 1) {
      const arms = (first + repetition) % 2 === 0 ? ["A", "B"] : ["B", "A"];
      pairs.push({ scenario_id: scenario.id, repetition, arms });
    }
  }
  // Shuffle pairs, preserving counterbalanced within-pair order for each task.
  for (let i = pairs.length - 1; i > 0; i -= 1) {
    const j = randomInt(i + 1);
    [pairs[i], pairs[j]] = [pairs[j], pairs[i]];
  }
  const slots = pairs.flatMap((pair, index) => pair.arms.map((arm_label, position) => ({
    slot_id: `p${String(index + 1).padStart(3, "0")}-${arm_label}`,
    pair_id: `p${String(index + 1).padStart(3, "0")}`,
    scenario_id: pair.scenario_id, repetition: pair.repetition, arm_label,
    order: index * 2 + position + 1
  })));
  const body = {
    schema_version: 1, experiment_id: randomBytes(16).toString("hex"),
    corpus_sha256: digest(corpus), repetitions, ...structuredClone(config), slots
  };
  const plan = { ...body, plan_sha256: digest(body) };
  const assignment = randomInt(2) === 0 ? { A: "single_agent", B: "team" } : { A: "team", B: "single_agent" };
  return { plan, private_key: { schema_version: 1, plan_sha256: plan.plan_sha256, assignment } };
}

export function validatePlan(plan, corpus) {
  validateCorpus(corpus);
  requireThat(plan?.schema_version === 1 && text(plan.experiment_id), "Invalid plan identity");
  validateConfig(plan);
  const { plan_sha256, ...body } = plan;
  requireThat(plan_sha256 === digest(body) && plan.corpus_sha256 === digest(corpus), "Plan/corpus digest mismatch");
  requireThat(Number.isInteger(plan.repetitions) && plan.repetitions >= 3 && plan.repetitions <= 10, "Invalid repetition count");
  const scenarios = new Set(corpus.scenarios.map((s) => s.id));
  const ids = new Set();
  const cells = new Set();
  const pairs = new Map();
  requireThat(Array.isArray(plan.slots) && plan.slots.length === scenarios.size * plan.repetitions * 2, "Incomplete schedule");
  for (const [index, slot] of plan.slots.entries()) {
    requireThat(text(slot.slot_id) && !ids.has(slot.slot_id), "Duplicate/missing slot ID");
    requireThat(text(slot.pair_id) && scenarios.has(slot.scenario_id) && ARMS.includes(slot.arm_label), "Invalid slot");
    requireThat(Number.isInteger(slot.repetition) && slot.repetition >= 1 && slot.repetition <= plan.repetitions, "Invalid slot repetition");
    requireThat(slot.order === index + 1, "Schedule order must be contiguous");
    const cell = `${slot.scenario_id}/${slot.repetition}/${slot.arm_label}`;
    requireThat(!cells.has(cell), "Duplicate scheduled cell");
    cells.add(cell); ids.add(slot.slot_id);
    pairs.set(slot.pair_id, [...(pairs.get(slot.pair_id) || []), slot]);
  }
  for (const pair of pairs.values()) {
    requireThat(pair.length === 2 && pair[0].scenario_id === pair[1].scenario_id &&
      pair[0].repetition === pair[1].repetition && pair[0].arm_label !== pair[1].arm_label &&
      pair[1].order === pair[0].order + 1, "Invalid paired schedule");
  }
  for (const scenario of scenarios) {
    const firstA = [...pairs.values()].filter((p) => p[0].scenario_id === scenario && p[0].arm_label === "A").length;
    requireThat(Math.abs(firstA * 2 - plan.repetitions) <= 1, "Unbalanced pair order");
  }
  return plan;
}

export function validateExport(input, plan, expectedKind) {
  requireThat(input?.schema_version === 1 && ["actual", "fixture"].includes(input.evidence_kind), "Explicit evidence_kind required");
  requireThat(input.evidence_kind === expectedKind, `Adapter requires ${expectedKind} evidence; no fixture/actual relabeling`);
  requireThat(input.plan_sha256 === plan.plan_sha256, "Export plan digest mismatch");
  requireThat(Array.isArray(input.runs), "Export runs must be an array");
  const slots = new Set(plan.slots.map((s) => s.slot_id));
  const seenSlots = new Set();
  const seenRuns = new Set();
  const seenCalls = new Set();
  for (const run of input.runs) {
    requireThat(object(run) && slots.has(run.slot_id), "Unknown export slot");
    requireThat(run.evidence_kind === input.evidence_kind, "Every run must retain its evidence_kind");
    requireThat(!seenSlots.has(run.slot_id), "Duplicate export slot; retries belong inside one trial");
    requireThat(text(run.run_id) && !seenRuns.has(run.run_id), "Missing/reused run ID across trials");
    requireThat(run.result === undefined || object(run.result), "Result must be an object");
    requireThat(run.accounting?.ledger?.calls === undefined || Array.isArray(run.accounting.ledger.calls), "Calls must be an array");
    if (expectedKind === "actual") {
      const accounting = run.accounting || {};
      const ledger = accounting.ledger || {};
      // Inspect receipt fields only; answers may legitimately quote a fixture marker.
      const refs = [run.budget?.evidence_ref, run.capture?.evidence_ref, ledger.evidence_ref,
        accounting.wall_time_ms?.evidence_ref, accounting.rework_count?.evidence_ref,
        accounting.intervention_count?.evidence_ref,
        ...(ledger.calls || []).flatMap((call) => [call?.total_tokens?.evidence_ref, call?.cost_micros?.evidence_ref])];
      requireThat(!refs.some((ref) => typeof ref === "string" && /^FIXTURE_ONLY(?:[:_\s-]|$)/i.test(ref.trim())),
        "Explicit fixture provenance cannot be actual evidence");
    }
    seenSlots.add(run.slot_id); seenRuns.add(run.run_id);
    for (const call of run.accounting?.ledger?.calls || []) {
      requireThat(object(call) && text(call.call_id) && !seenCalls.has(call.call_id), "Missing/reused call ID");
      seenCalls.add(call.call_id);
    }
  }
  return input;
}

function measurement(raw) {
  return object(raw) && raw.complete === true && text(raw.evidence_ref) && integer(raw.value) ? raw.value : UNKNOWN;
}
function sumKnown(values) {
  if (values.some((n) => n === UNKNOWN)) return UNKNOWN;
  const sum = values.reduce((a, b) => a + b, 0);
  return integer(sum) ? sum : UNKNOWN;
}
export function measureRun(run) {
  const accounting = run.accounting || {};
  const ledger = accounting.ledger || {};
  const calls = Array.isArray(ledger.calls) ? ledger.calls : [];
  const participants = ledger.participants;
  const complete = ledger.complete === true && ledger.scope === "entire_trial" && text(ledger.evidence_ref) &&
    Array.isArray(ledger.calls) &&
    Array.isArray(participants) && participants.length > 0 && participants.every(text) &&
    new Set(participants).size === participants.length &&
    calls.every((c) => participants.includes(c.participant_id)) &&
    (calls.length > 0 || ledger.no_model_calls_observed === true);
  return {
    wall_time_ms: measurement(accounting.wall_time_ms),
    total_tokens: complete ? sumKnown(calls.map((c) => measurement(c.total_tokens))) : UNKNOWN,
    cost_micros: complete ? sumKnown(calls.map((c) => measurement(c.cost_micros))) : UNKNOWN,
    rework_count: measurement(accounting.rework_count),
    intervention_count: measurement(accounting.intervention_count)
  };
}

export function assessQuality(scenario, result) {
  if (!result || !TERMINAL.includes(result.status)) return { score: UNKNOWN, passed: UNKNOWN, assertions: [] };
  // Resource eligibility is checked separately against the whole-trial budget.
  const qualityExpect = { ...(scenario.expect || {}) };
  delete qualityExpect.max_duration_ms;
  delete qualityExpect.latency_is_critical;
  const base = evaluateScenario({ ...scenario, expect: qualityExpect }, result);
  let parsed;
  try { parsed = JSON.parse(result.response); } catch { parsed = undefined; }
  const checks = Object.entries(scenario.answers).map(([key, expected]) => ({
    name: `answer:${key}`, passed: object(parsed) && Object.hasOwn(parsed, key) && isDeepStrictEqual(parsed[key], expected)
  }));
  const shapeValid = object(parsed) && Object.keys(parsed).every((key) => Object.hasOwn(scenario.answers, key));
  const assertions = [...base.assertions.map(({ name, passed }) => ({ name, passed })),
    { name: "answer_object_no_extra_fields", passed: shapeValid }, ...checks];
  // Terminal failures remain zero-quality observations, even with a plausible partial answer.
  const completed = result.status === "completed";
  const score = completed ? checks.filter((c) => c.passed).length / checks.length : 0;
  const passed = completed && assertions.every((a) => a.passed);
  return { score: base.passed && shapeValid ? score : 0, passed, assertions };
}

function trialRecord(slot, run, plan, corpus, kind) {
  const scenario = corpus.scenarios.find((s) => s.id === slot.scenario_id);
  const quality = assessQuality(scenario, run?.result);
  const metrics = { ...measureRun(run || {}), quality: quality.score };
  const reasons = [];
  if (!run) reasons.push("missing_run");
  if (!TERMINAL.includes(run?.result?.status)) reasons.push("missing_or_nonterminal_result");
  if (run?.result?.scenario_id !== slot.scenario_id) reasons.push("scenario_mismatch");
  if (run?.result?.run_id !== run?.run_id || !run?.result?.run_id) reasons.push("result_run_id_mismatch");
  if (!isDeepStrictEqual(run?.budget?.limits, plan.budget)) reasons.push("unequal_total_budget");
  if (run?.budget?.scope !== "entire_trial" || run?.budget?.enforced !== true || !text(run?.budget?.evidence_ref)) {
    reasons.push("total_budget_enforcement_unverified");
  }
  if (!isDeepStrictEqual(run?.controls, plan.controls)) reasons.push("control_policy_mismatch");
  if (run?.capture?.complete !== true || !text(run?.capture?.evidence_ref) ||
      run?.capture?.assignment_verified !== true || run?.capture?.controls_verified !== true ||
      run?.capture?.reset_verified !== true || run?.capture?.scope !== "entire_trial") reasons.push("capture_unverified");
  if (run?.capture?.request_sha256 !== digest(scenario.request)) reasons.push("request_identity_unverified");
  if (run?.capture?.order !== slot.order) reasons.push("execution_order_unverified");
  if (kind === "actual" && Object.values(plan.controls).some((v) => /FIXTURE_ONLY|UNSPECIFIED/i.test(v))) {
    reasons.push("placeholder_control_policy");
  }
  for (const [metric, cap] of Object.entries(CAP)) {
    if (metrics[metric] === UNKNOWN) reasons.push(`unknown_${metric}`);
    else if (metrics[metric] > plan.budget[cap]) reasons.push(`over_budget_${metric}`);
  }
  return {
    ...slot, status: !run?.result ? "missing" : TERMINAL.includes(run.result.status) ? run.result.status : "nonterminal", metrics,
    quality, eligible: reasons.length === 0, exclusion_reasons: reasons,
    // Keep identifiers and source metadata out of the blinded artifact. Raw export is the private audit trail.
    evidence_sha256: run ? digest(run) : UNKNOWN,
    failure_reason_count: Array.isArray(run?.result?.failure_reasons) ? run.result.failure_reasons.length : 0
  };
}

function summary(values) {
  const known = values.filter((v) => typeof v === "number" && Number.isFinite(v));
  return {
    expected_count: values.length, known_count: known.length, unknown_count: values.length - known.length,
    mean_basis: "available_observations_only",
    mean: known.length ? known.reduce((a, b) => a + b, 0) / known.length : UNKNOWN,
    min: known.length ? Math.min(...known) : UNKNOWN, max: known.length ? Math.max(...known) : UNKNOWN
  };
}
function pairedStats(pairs) {
  const eligible = pairs.filter((p) => p.eligible);
  return Object.fromEntries(METRICS.map((metric) => [metric, summary(eligible.map((p) => p.delta_B_minus_A[metric]))]));
}
export function compare(plan, corpus, input, expectedKind) {
  validatePlan(plan, corpus);
  validateExport(input, plan, expectedKind);
  const bySlot = new Map(input.runs.map((run) => [run.slot_id, run]));
  const records = plan.slots.map((slot) => trialRecord(slot, bySlot.get(slot.slot_id), plan, corpus, input.evidence_kind));
  const pairs = [...new Set(records.map((r) => r.pair_id))].map((pairId) => {
    const a = records.find((r) => r.pair_id === pairId && r.arm_label === "A");
    const b = records.find((r) => r.pair_id === pairId && r.arm_label === "B");
    const eligible = a.eligible && b.eligible;
    return {
      pair_id: pairId, scenario_id: a.scenario_id, repetition: a.repetition, eligible,
      slot_A: a.slot_id, slot_B: b.slot_id,
      exclusion_reasons: [...a.exclusion_reasons.map((r) => `A:${r}`), ...b.exclusion_reasons.map((r) => `B:${r}`)],
      delta_B_minus_A: Object.fromEntries(METRICS.map((metric) => [metric, eligible ? b.metrics[metric] - a.metrics[metric] : UNKNOWN]))
    };
  });
  const eligibleCount = pairs.filter((p) => p.eligible).length;
  return {
    schema_version: 1, benchmark_id: corpus.benchmark_id, plan_sha256: plan.plan_sha256,
    corpus_sha256: plan.corpus_sha256, evidence_kind: input.evidence_kind,
    input_sha256: digest(input), budget: plan.budget,
    conclusion: input.evidence_kind === "fixture" ? "FIXTURE_ONLY_NO_CAPABILITY_CLAIM" :
      eligibleCount === pairs.length ? "DESCRIPTIVE_ONLY_NO_SUPERIORITY_CLAIM" : "INCOMPLETE_NO_SUPERIORITY_CLAIM",
    expected_pairs: pairs.length, eligible_pairs: eligibleCount, excluded_pairs: pairs.length - eligibleCount,
    analysis_version: 2,
    all_assigned: assignedSummary(records, pairs),
    eligible_pair_analysis: "diagnostic_only_post_assignment_selection",
    arms: Object.fromEntries(ARMS.map((arm) => {
      const rows = records.filter((r) => r.arm_label === arm);
      return [arm, {
        scheduled: rows.length, observed: rows.filter((r) => r.status !== "missing").length,
        passed: rows.filter((r) => r.quality.passed === true).length,
        failed: rows.filter((r) => r.quality.passed === false).length,
        unknown_quality: rows.filter((r) => r.quality.passed === UNKNOWN).length,
        metrics_all_scheduled: Object.fromEntries(METRICS.map((metric) => [metric, summary(rows.map((r) => r.metrics[metric]))]))
      }];
    })),
    paired_delta_B_minus_A: pairedStats(pairs),
    by_task: corpus.scenarios.map((scenario) => {
      const taskPairs = pairs.filter((p) => p.scenario_id === scenario.id);
      return { scenario_id: scenario.id, category: scenario.category,
        eligible_pairs: taskPairs.filter((p) => p.eligible).length, expected_pairs: taskPairs.length,
        all_assigned: assignedSummary(records.filter((r) => r.scenario_id === scenario.id), taskPairs),
        paired_delta_B_minus_A: pairedStats(taskPairs) };
    }),
    records, pairs
  };
}

export function reviewerPacket(plan, corpus, input, expectedKind) {
  validatePlan(plan, corpus);
  validateExport(input, plan, expectedKind);
  const bySlot = new Map(input.runs.map((run) => [run.slot_id, run]));
  return {
    schema_version: 1, evidence_kind: input.evidence_kind, plan_sha256: plan.plan_sha256,
    warning: "Arm mapping and runtime metadata withheld. Answers may self-identify; review for content leakage before assigning a human grader.",
    items: plan.slots.map((slot) => ({
      slot_id: slot.slot_id, scenario_id: slot.scenario_id, arm_label: slot.arm_label,
      prompt: corpus.scenarios.find((s) => s.id === slot.scenario_id).request.prompt,
      response: bySlot.get(slot.slot_id)?.result?.response ?? UNKNOWN,
      status: bySlot.get(slot.slot_id)?.result?.status ?? "missing"
    }))
  };
}

export function importBenchmark(plan, corpus, benchmark, accounting) {
  validatePlan(plan, corpus);
  validateExport(accounting, plan, "actual");
  requireThat(Array.isArray(benchmark?.results), "Benchmark export requires results array");
  const byRun = new Map();
  for (const result of benchmark.results) {
    requireThat(text(result.run_id) && !byRun.has(result.run_id), "Benchmark results need unique original run_id values");
    byRun.set(result.run_id, result);
  }
  const boundIds = new Set(accounting.runs.map((r) => r.run_id));
  requireThat([...byRun.keys()].every((id) => boundIds.has(id)), "Unbound benchmark results must not be silently discarded");
  return { ...structuredClone(accounting), runs: accounting.runs.map((run) => {
    requireThat(!Object.hasOwn(run, "result"), "Accounting sidecar must not override the captured result");
    // Preserve failed/partial outputs, receipts and events verbatim. No inference from EvalOps passed/cost defaults.
    return { ...structuredClone(run), ...(byRun.has(run.run_id) ? { result: structuredClone(byRun.get(run.run_id)) } : {}) };
  }) };
}

export function accountingTemplate(plan) {
  const unknown = () => ({ value: UNKNOWN, complete: false, evidence_ref: "" });
  return {
    schema_version: 1, evidence_kind: "actual", plan_sha256: plan.plan_sha256,
    warning: "INCOMPLETE TEMPLATE, NOT EVIDENCE. Fill only from actual local capture. Leave unknown values UNKNOWN.",
    runs: plan.slots.map((slot) => ({
      slot_id: slot.slot_id, run_id: "", evidence_kind: "actual",
      controls: structuredClone(plan.controls),
      budget: { limits: structuredClone(plan.budget), scope: "entire_trial", enforced: false, evidence_ref: "" },
      capture: { complete: false, assignment_verified: false, controls_verified: false, reset_verified: false,
        scope: "entire_trial", order: null, request_sha256: "", evidence_ref: "" },
      accounting: {
        wall_time_ms: unknown(), rework_count: unknown(), intervention_count: unknown(),
        ledger: { complete: false, scope: "entire_trial", evidence_ref: "", participants: [], calls: [] }
      }
    }))
  };
}

export function renderMarkdown(report) {
  const fmt = (v) => typeof v === "number" ? Number(v.toFixed(3)) : v;
  const lines = ["# Equal-Budget Paired Evaluation", "", `Evidence: **${report.evidence_kind.toUpperCase()}**`,
    `Conclusion: **${report.conclusion}**`, "", `Diagnostic eligible pairs: ${report.eligible_pairs}/${report.expected_pairs}. Excluded from this diagnostic: ${report.excluded_pairs}.`,
    `Plan SHA-256: ${report.plan_sha256}`, `Input SHA-256: ${report.input_sha256}`,
    "", "Labels A/B are blinded. The private key is not loaded by the reporting command.",
    "All scheduled trials, including failures and missing trials, remain in report.json.",
    "UNKNOWN is unmeasured, never zero. Lower is better for resource metrics; higher for quality.",
    "", "## Equal Total Caps", "", "Shared entire-trial limits for both arms, including all workers and retries.",
    "", "| Limit | Value |", "| --- | ---: |"];
  for (const [key, value] of Object.entries(report.budget)) lines.push(`| ${key} | ${value} |`);
  lines.push("", "## All Scheduled Trials", "", "| Arm | Scheduled | Observed | Passed | Failed | Unknown quality |", "| --- | ---: | ---: | ---: | ---: | ---: |");
  for (const arm of ARMS) {
    const row = report.arms[arm];
    lines.push(`| ${arm} | ${row.scheduled} | ${row.observed} | ${row.passed} | ${row.failed} | ${row.unknown_quality} |`);
  }
  lines.push("", "## All Assigned Budget Constrained Completion", "",
    "Every scheduled slot stays in the denominator. Verified noncompletion and verified budget excess score zero.",
    "Missing, unfinished, unverified or potentially successful but unaccounted results remain UNKNOWN.",
    "Bounds allow each unknown outcome to range from zero to one; they are NOT confidence intervals.",
    "A point estimate is shown only when all assigned outcomes are known. No missing-at-random assumption is made.",
    "", "| Arm | Assigned | Success | Policy failure | Unknown | Mean | Lower bound | Upper bound |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |");
  for (const arm of ARMS) {
    const row = report.all_assigned.arms[arm];
    lines.push(`| ${arm} | ${row.scheduled} | ${row.verified_successes} | ${row.verified_policy_failures} | ${row.unknown} | ${fmt(row.mean)} | ${fmt(row.lower)} | ${fmt(row.upper)} |`);
  }
  const assignedDelta = report.all_assigned.paired_delta_B_minus_A;
  lines.push("", `B minus A over all ${assignedDelta.scheduled} scheduled pairs: mean ${fmt(assignedDelta.mean)}; bounds [${fmt(assignedDelta.lower)}, ${fmt(assignedDelta.upper)}].`,
    "This observed policy endpoint does not estimate a counterfactual budget-compliant outcome for an over-budget trial.",
    "A snapshot does not close collection. Missing rows are not proof of unattempted goals after budget exhaustion.",
    "", "## Diagnostic Eligible Pair Differences", "", "B minus A, eligible pairs only. Post-assignment selection may bias these diagnostics; do not use them as an all-assigned treatment effect.",
    "Do not interpret excluded or missing pairs as ties.",
    "", "| Metric | Pairs | Mean | Min | Max |", "| --- | ---: | ---: | ---: | ---: |");
  for (const metric of METRICS) {
    const row = report.paired_delta_B_minus_A[metric];
    lines.push(`| ${metric} | ${row.known_count} | ${fmt(row.mean)} | ${fmt(row.min)} | ${fmt(row.max)} |`);
  }
  lines.push("", "## Measurement Coverage", "", "Means here describe available observations, not an eligible-arm comparison.",
    "", "| Arm | Metric | Known | Unknown | Mean |", "| --- | --- | ---: | ---: | ---: |");
  for (const arm of ARMS) for (const metric of METRICS) {
    const row = report.arms[arm].metrics_all_scheduled[metric];
    lines.push(`| ${arm} | ${metric} | ${row.known_count} | ${row.unknown_count} | ${fmt(row.mean)} |`);
  }
  lines.push("", "## Exclusions", "");
  for (const row of report.records.filter((r) => !r.eligible)) lines.push(`- ${row.slot_id}: ${row.exclusion_reasons.join(", ")}`);
  if (!report.excluded_pairs) lines.push("None.");
  lines.push("", "## Limits", "", "Small fixed offline diagnostic corpus; structured-answer quality only. No live app acceptance, statistical significance, or general superiority is established.",
    "Repeated trials within a task are correlated; see by_task in JSON. No best-of-N selection or winner label is used.",
    "Evidence references and completeness are collector attestations, not cryptographic proof of execution. Independently audit the private exports and budget enforcement before unblinding.", "");
  return lines.join("\n");
}

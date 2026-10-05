import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { ARMS, armPolicy, collectorRequests, createPlan, digest, validateConfig, validatePlan } from "./protocol.mjs";
import { inspectCapture } from "./capture.mjs";
import { fixtureCapture, fixtureConfig } from "./fixture.mjs";

const seed = "a".repeat(64);
const plan = () => createPlan(fixtureConfig(), seed);
const fresh = () => { const p = plan(); return { p, c: fixtureCapture(p) }; };
const reseal = (p) => { const { plan_sha256, ...rest } = p; return { ...rest, plan_sha256: digest(rest) }; };
const byArm = (c, arm) => c.streams.find((s) => s.policy.members === armPolicy(arm, 8).members &&
  s.policy.communication === armPolicy(arm, 8).communication && s.policy.persistence === armPolicy(arm, 8).persistence);
const goalIssues = (report) => report.streams.flatMap((s) => s.goals.flatMap((g) => g.issues));
const streamIssues = (report) => report.streams.flatMap((s) => s.issues);

test("all six policies are explicit and persistence is distinct from communication", () => {
  assert.deepEqual(ARMS.map((arm) => armPolicy(arm, 8)), [
    { members: 1, communication: null, persistence: false }, { members: 1, communication: null, persistence: true },
    { members: 8, communication: false, persistence: false }, { members: 8, communication: true, persistence: false },
    { members: 8, communication: false, persistence: true }, { members: 8, communication: true, persistence: true }
  ]);
});
test("plan preserves every ordered goal and randomizes whole streams reproducibly", () => {
  const p = plan(); assert.deepEqual(p, plan()); assert.equal(p.streams.length, 24);
  assert.notDeepEqual(p.streams, createPlan(fixtureConfig(), "b".repeat(64)).streams);
  for (const block of new Set(p.streams.map((s) => s.block_id))) {
    const group = p.streams.filter((s) => s.block_id === block);
    assert.deepEqual(group.map((s) => s.arm).sort(), [...ARMS].sort());
    assert.equal(new Set(group.map((s) => s.state_namespace)).size, 6);
    for (const s of group) assert.deepEqual(s.goals.map((g) => g.index), [0, 1, 2]);
    assert.equal(new Set(group.map((s) => JSON.stringify(s.goals.map((g) => g.request_sha256)))).size, 1);
  }
  assert.equal(new Set(p.streams.map((s) => s.state_namespace)).size, 24);
  validatePlan(p);
});
test("goals and repetitions do not inflate independent family count", () => {
  const { p, c } = fresh(); const report = inspectCapture(p, c);
  assert.equal(report.declared_family_count, 2); assert.equal(report.assigned_goals, 72);
  for (const arm of ARMS) assert.equal(report.by_arm[arm].assigned_goals, 12);
  assert.equal(report.verdict, "CAPTURE_CONTRACT_CONSISTENT_NOT_EFFICACY");
  assert.equal(report.evidence_kind, "fixture");
});
test("collector gets one unchanged stream budget, not a multiplied worker budget", () => {
  const p = plan(), requests = collectorRequests(p);
  assert.match(requests.scope, /collector_only/);
  for (const s of requests.streams) assert.deepEqual(s.shared_stream_budget, p.config.stream_budget);
  requests.streams[0].shared_stream_budget.max_cost_micros = 1;
  assert.notEqual(requests.streams[1].shared_stream_budget.max_cost_micros, 1);
  assert.equal(JSON.stringify(p).includes('"answers"'), false);
});

for (const [name, change, pattern] of [
  ["unknown fields", (c) => { c.answers = {}; }, /fields/],
  ["untyped budget", (c) => { c.stream_budget.max_model_requests = "30"; }, /cap/],
  ["zero budget", (c) => { c.stream_budget.max_total_tokens = 0; }, /cap/],
  ["unsafe budget integer", (c) => { c.stream_budget.max_cost_micros = Number.MAX_SAFE_INTEGER + 1; }, /cap/],
  ["duplicate family", (c) => { c.families.push(structuredClone(c.families[0])); }, /family_id/],
  ["duplicate goal", (c) => { c.families[0].goals.push(structuredClone(c.families[0].goals[0])); }, /goal_id/],
  ["duplicate cross-family input", (c) => { c.families[1].goals[0].request = c.families[0].goals[0].request; }, /Duplicate request/],
  ["rubric accidentally in request", (c) => { c.families[0].goals[0].request.answers = [1]; }, /fields/],
  ["invalid digest", (c) => { c.controls.evaluator_sha256 = "unknown"; }, /digest/],
  ["single goal is not longitudinal", (c) => { c.families[0].goals.length = 1; }, /two ordered/],
  ["invalid team size", (c) => { c.team_size = 1; }, /team_size/],
  ["invalid repetition", (c) => { c.repetitions = -1; }, /repetitions/],
  ["unspecified kind", (c) => { c.evidence_kind = ""; }, /evidence_kind/]
]) test(`reject ${name}`, () => { const c = fixtureConfig(); change(c); assert.throws(() => validateConfig(c), pattern); });

test("even a recomputed outer hash cannot hide a missing arm or reordered goal", () => {
  const p = plan(); p.streams.pop(); assert.throws(() => validatePlan(reseal(p)), /schedule/);
  const q = plan(); q.streams[0].goals.reverse(); assert.throws(() => validatePlan(reseal(q)), /schedule/);
});
test("config, seed and plan digest mutations are rejected", () => {
  const p = plan(); p.config.team_size = 4; assert.throws(() => validatePlan(p), /Config digest/);
  const q = plan(); q.randomization_seed = "bad"; assert.throws(() => validatePlan(q), /seed/);
  const r = plan(); r.plan_sha256 = "0".repeat(64); assert.throws(() => validatePlan(r), /Plan digest/);
});
test("fixture generation refuses an actual plan", () => {
  const cfg = fixtureConfig(); cfg.evidence_kind = "actual";
  assert.throws(() => fixtureCapture(createPlan(cfg, seed)), /fabricate actual/);
});

for (const [name, change, pattern] of [
  ["duplicate stream", (c) => { c.streams.push(structuredClone(c.streams[0])); }, /duplicate stream/],
  ["unknown stream", (c) => { c.streams[0].stream_id = "unknown"; }, /Unknown/],
  ["reused group", (c) => { c.streams[1].group_id = c.streams[0].group_id; }, /group ID/],
  ["reused namespace", (c) => { c.streams[1].state_namespace = c.streams[0].state_namespace; }, /namespace/],
  ["reused stream ledger", (c) => { c.streams[1].budget.ledger_id = c.streams[0].budget.ledger_id; }, /ledger/],
  ["duplicate goal", (c) => { c.streams[0].goals.push(structuredClone(c.streams[0].goals[0])); }, /duplicate goal/],
  ["reused run", (c) => { c.streams[0].goals[1].run_id = c.streams[0].goals[0].run_id; }, /run ID/],
  ["reused attempt", (c) => { c.streams[0].goals[1].attempt_ids = c.streams[0].goals[0].attempt_ids; }, /attempt ID/],
  ["unknown goal status", (c) => { c.streams[0].goals[0].status = "looks_good"; }, /lifecycle/],
  ["nonboolean enforcement", (c) => { c.streams[0].budget.enforced = "true"; }, /boolean/],
  ["negative message count", (c) => { c.streams[0].goals[0].communication.during_task_peer_messages = -1; }, /counters/],
  ["invalid state hash", (c) => { c.streams[0].goals[0].state.input_sha256 = ""; }, /state digest/],
  ["fixture relabel", (c) => { c.evidence_kind = "actual"; }, /kind mismatch/],
  ["capture plan mismatch", (c) => { c.plan_sha256 = "0".repeat(64); }, /plan mismatch/]
]) test(`capture rejects ${name}`, () => { const { p, c } = fresh(); change(c); assert.throws(() => inspectCapture(p, c), pattern); });

for (const [name, change, expected] of [
  ["cross-stream read", (c) => { c.streams[0].goals[0].state.read_namespaces.push(c.streams[1].state_namespace); }, "cross_stream_state_access"],
  ["cross-stream write", (c) => { c.streams[0].goals[0].state.write_namespace = c.streams[1].state_namespace; }, "cross_stream_state_access"],
  ["missing reset proof", (c) => { c.streams[0].goals[0].state.reset_ref = null; }, "reset_unverified"],
  ["persistent state reset", (c) => { byArm(c, "T11").goals[1].state.input_sha256 = digest("reset"); }, "persistent_state_chain_broken"],
  ["nonpersistent state leaked", (c) => { byArm(c, "T10").goals[1].state.input_sha256 = byArm(c, "T10").goals[0].state.output_sha256; }, "initial_state_not_restored"],
  ["forbidden work-phase communication", (c) => { byArm(c, "T01").goals[0].communication.during_task_peer_messages = 1; }, "forbidden_during_task_communication"],
  ["single-agent extra reviewer", (c) => { byArm(c, "S1").goals[0].communication.finalization_peer_messages = 1; }, "single_arm_peer_communication"],
  ["running predecessor", (c) => { byArm(c, "S1").goals[0].status = "running"; }, "ordered_predecessor_not_terminal"],
  ["missing predecessor", (c) => { byArm(c, "S1").goals.shift(); }, "predecessor_state_unverified"],
  ["request drift", (c) => { c.streams[0].goals[0].request_sha256 = digest("different prompt"); }, "request_mismatch"],
  ["missing terminal checkpoint", (c) => { c.streams[0].goals[0].state.output_sha256 = null; }, "terminal_state_missing"],
  ["wrong goal index", (c) => { c.streams[0].goals[0].index = 2; }, "goal_identity_mismatch"]
]) test(`capture retains and flags ${name}`, () => {
  const { p, c } = fresh(); change(c); const r = inspectCapture(p, c);
  assert.ok(goalIssues(r).includes(expected)); assert.equal(r.assigned_goals, 72);
  assert.equal(r.all_capture_contracts_consistent, false);
});

for (const [name, change, expected] of [
  ["wrong stream order", (s) => { s.order += 1; }, "stream_order_mismatch"],
  ["changed arm policy", (s) => { s.policy.members = 1024; }, "arm_policy_mismatch"],
  ["changed control", (s) => { s.controls_sha256 = digest("other"); }, "controlled_policy_mismatch"],
  ["multiplied budget", (s) => { s.budget.limits.max_model_requests *= 8; }, "shared_stream_budget_changed"],
  ["per-goal ledger scope", (s) => { s.budget.scope = "goal"; }, "shared_stream_budget_unverified"],
  ["unenforced budget", (s) => { s.budget.enforced = false; }, "shared_stream_budget_unverified"],
  ["reversed goals", (s) => { s.goals.reverse(); }, "goal_capture_order_mismatch"]
]) test(`capture flags ${name}`, () => {
  const { p, c } = fresh(); change(c.streams[0]); assert.ok(streamIssues(inspectCapture(p, c)).includes(expected));
});

test("closing collection does not turn missing goals into failures or successes", () => {
  const { p, c } = fresh(); c.streams.length = 0;
  const r = inspectCapture(p, c);
  assert.equal(r.assigned_goals, 72); assert.equal(r.all_assigned_slots_terminal, false);
  for (const arm of ARMS) assert.equal(r.by_arm[arm].status_counts.missing, 12);
  assert.equal(Object.hasOwn(r, "success_rate"), false);
});
test("failed and paused goals remain; successful retries do not create new slots", () => {
  const { p, c } = fresh(); c.streams[0].goals[0].attempt_ids.push("fixture-retry-1", "fixture-retry-2");
  c.streams[0].goals[2].status = "paused";
  const r = inspectCapture(p, c);
  assert.equal(r.streams[0].goals[0].attempt_count, 3);
  assert.equal(r.streams[0].goals[1].status, "failed");
  assert.equal(r.streams[0].goals[2].status, "paused");
  assert.equal(r.all_assigned_slots_terminal, false); assert.equal(r.assigned_goals, 72);
});
test("unattempted exhaustion needs proof and no fabricated run or attempt", () => {
  const { p, c } = fresh(), g = c.streams[0].goals[2];
  g.status = "unattempted_after_exhaustion"; g.run_id = null; g.attempt_ids = [];
  assert.throws(() => inspectCapture(p, c), /evidence reference/);
  g.exhaustion_ref = "FIXTURE_ONLY:exhaustion";
  assert.equal(inspectCapture(p, c).streams[0].goals[2].status, "unattempted_after_exhaustion");
  g.run_id = "invented"; assert.throws(() => inspectCapture(p, c), /invent a run/);
});
test("unattempted records cannot claim changed state or peer work", () => {
  const { p, c } = fresh(), g = byArm(c, "T11").goals[2];
  g.status = "unattempted_after_exhaustion"; g.run_id = null; g.attempt_ids = [];
  g.exhaustion_ref = "FIXTURE_ONLY:exhaustion";
  const issues = goalIssues(inspectCapture(p, c));
  assert.ok(issues.includes("unattempted_state_changed")); assert.ok(issues.includes("unattempted_peer_communication"));
  g.state.output_sha256 = g.state.input_sha256;
  g.communication.during_task_peer_messages = 0; g.communication.finalization_peer_messages = 0;
  assert.equal(inspectCapture(p, c).all_capture_contracts_consistent, true);
});
test("stream exhaustion cannot silently reset the budget for the next goal", () => {
  const { p, c } = fresh(); c.streams[0].goals[1].status = "resource_exhausted";
  c.streams[0].goals[1].exhaustion_ref = "FIXTURE_ONLY:exhaustion";
  assert.ok(goalIssues(inspectCapture(p, c)).includes("work_after_stream_exhaustion"));
});
test("open snapshots never attest a closed campaign", () => {
  const { p, c } = fresh(); c.collection.status = "open";
  assert.equal(inspectCapture(p, c).verdict, "COLLECTION_NOT_CLOSED_OR_NOT_TERMINAL");
});

const cliPath = fileURLToPath(new URL("./run.mjs", import.meta.url));
const cli = (...args) => spawnSync(process.execPath, [cliPath, ...args], { encoding: "utf8" });
function cleanupTemp(root) {
  const resolved = path.resolve(root), parent = path.resolve(os.tmpdir());
  assert.equal(path.dirname(resolved), parent);
  assert.ok(path.basename(resolved).startsWith("longitudinal-"));
  fs.rmSync(resolved, { recursive: true, force: true });
}
test("CLI synthetic round trip is private, explicit and never overwrites evidence", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "longitudinal-cli-"));
  try {
    const example = path.join(root, "example"), planned = path.join(root, "plan"), captured = path.join(root, "capture"), reported = path.join(root, "report");
    assert.equal(cli("example", "--out", example).status, 0);
    assert.equal(cli("plan", "--config", path.join(example, "fixture-config.json"), "--out", planned).status, 0);
    const planFile = path.join(planned, "plan.private.json");
    assert.equal(cli("fixture", "--plan", planFile, "--out", captured).status, 2);
    assert.equal(cli("inspect", "--plan", planFile, "--capture", path.join(captured, "fixture-capture.json"), "--out", reported).status, 2);
    const report = JSON.parse(fs.readFileSync(path.join(reported, "contract-report.private.json"), "utf8"));
    assert.equal(report.evidence_kind, "fixture"); assert.equal(report.assigned_goals, 72);
    assert.equal(cli("example", "--out", example).status, 1);
    assert.equal(cli("example", "--unknown", root).status, 1);
  } finally { cleanupTemp(root); }
});
test("CLI refuses artifacts inside a Git directory or Git worktree", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "longitudinal-git-"));
  try {
    fs.writeFileSync(path.join(root, ".git"), "gitdir: somewhere");
    const result = cli("example", "--out", path.join(root, "private"));
    assert.equal(result.status, 1); assert.match(result.stderr, /outside Git/);
    assert.equal(fs.existsSync(path.join(root, "private")), false);
  } finally { cleanupTemp(root); }
});

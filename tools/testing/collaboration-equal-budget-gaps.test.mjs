import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { assessQuality, compare, createPlan, validateCorpus } from "./team-evaluation/lib.mjs";
import { fixtureExport } from "./team-evaluation/fixture.mjs";

// Strict regressions: all three failed on the audited baseline before the scoped fixes.
// Synthetic values below are adversarial test inputs, never live-quality measurements.
const read = (name) => JSON.parse(readFileSync(new URL(`./team-evaluation/${name}`, import.meta.url), "utf8"));
const corpus = read("corpus.json");
const config = read("example-config.json");

test("GAP-01: explicit fixture receipts cannot become complete actual evidence by relabeling", () => {
  const neutral = structuredClone(config);
  neutral.controls = { model_policy: "pinned-policy-test", tool_policy: "read-only-policy-test",
    environment: "local-unit-test", context_policy: "fresh-context-test" };
  const { plan } = createPlan(corpus, neutral);
  const input = fixtureExport(plan, corpus);
  // Deliberately malicious in-memory relabel, retaining explicit synthetic receipt markers.
  input.evidence_kind = "actual";
  for (const run of input.runs) {
    run.evidence_kind = "actual";
    run.accounting.ledger.calls[0].cost_micros = { value: 500, complete: true, evidence_ref: "FIXTURE_ONLY:not-observed" };
  }
  let report;
  try { report = compare(plan, corpus, input, "actual"); }
  catch (error) {
    assert.match(error.message, /fixture|synthetic|provenance/i);
    return;
  }
  assert.equal(report.eligible_pairs, 0, "explicitly synthetic receipts must be rejected or ineligible; never complete actual accounting");
});

test("GAP-02: noncritical latency expectations must not erase correct-answer quality", () => {
  const scenario = structuredClone(corpus.scenarios.find((s) => s.id === "dependency-plan"));
  scenario.expect.max_duration_ms = 100;
  scenario.expect.latency_is_critical = false;
  const result = { status: "completed", response: JSON.stringify(scenario.answers), duration_ms: 99 };
  const fast = assessQuality(scenario, result);
  const slow = assessQuality(scenario, { ...result, duration_ms: 101 });
  assert.equal(fast.score, 1);
  assert.equal(slow.score, fast.score, "latency belongs in the independent resource dimension, not answer correctness");
  assert.equal(slow.passed, fast.passed);
});

test("GAP-03: aliased identical requests cannot claim distinct task-type coverage", () => {
  const duplicated = structuredClone(corpus);
  duplicated.scenarios[1].request = structuredClone(duplicated.scenarios[0].request);
  duplicated.scenarios[1].answers = structuredClone(duplicated.scenarios[0].answers);
  assert.throws(() => validateCorpus(duplicated), /duplicate|identical|repeated request/i,
    "distinct IDs/categories must not turn one prompt into multiple independent task types");
});

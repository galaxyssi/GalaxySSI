import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { readJson } from "./agent-benchmark-lib.mjs";
import {
  compileRegressionSuite,
  evaluateRegressionSuite,
  validateRegressionSuite
} from "./agent-regression-dsl.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const suite = readJson(
  path.join(root, "benchmarks", "agent", "regression-suite.json")
);
const reference = readJson(
  path.join(root, "benchmarks", "agent", "reference-results.json")
);

function assertionFor(report, caseId, assertionName) {
  return report.records
    .find((record) => record.id === caseId)
    ?.assertions.find((assertion) => assertion.name === assertionName);
}

test("reference results satisfy the Agent regression DSL", () => {
  const report = evaluateRegressionSuite(suite, reference);
  assert.equal(report.passed, true);
  assert.equal(report.passed_count, suite.cases.length);
  assert.equal(report.score, 1);
});

test("phase order is enforced independently of phase presence", () => {
  const changed = structuredClone(reference);
  const result = changed.results.find((item) => item.scenario_id === "code-build-verify");
  [result.events[3], result.events[4]] = [result.events[4], result.events[3]];
  const report = evaluateRegressionSuite(suite, changed);
  assert.equal(assertionFor(report, "code-build-verify", "run_phases").passed, true);
  assert.equal(assertionFor(report, "code-build-verify", "phase_order").passed, false);
});

test("tool order is enforced independently of tool presence", () => {
  const changed = structuredClone(reference);
  const result = changed.results.find((item) => item.scenario_id === "code-build-verify");
  [result.events[1], result.events[2]] = [result.events[2], result.events[1]];
  const report = evaluateRegressionSuite(suite, changed);
  assert.equal(assertionFor(report, "code-build-verify", "required_tools").passed, true);
  assert.equal(assertionFor(report, "code-build-verify", "tool_order").passed, false);
});

test("forbidden tool execution fails a protected action", () => {
  const changed = structuredClone(reference);
  changed.results
    .find((item) => item.scenario_id === "high-risk-approval")
    .events.splice(1, 0, {
      phase: "act",
      tool: "android.message.send",
      timestamp_ms: 4300
    });
  const report = evaluateRegressionSuite(suite, changed);
  assert.equal(assertionFor(report, "high-risk-approval", "forbidden_tools").passed, false);
});

test("required plan terms are matched against structured plan steps", () => {
  const changedSuite = structuredClone(suite);
  changedSuite.cases[0].expect.plan.required_steps = ["inspect input", "verify result"];
  const changedResults = structuredClone(reference);
  changedResults.results.find((item) => item.scenario_id === "low-risk-native-tool").plan = [
    { title: "Inspect input and identify the phone tool" },
    { title: "Verify result before final response" }
  ];
  let report = evaluateRegressionSuite(changedSuite, changedResults);
  assert.equal(assertionFor(report, "low-risk-native-tool", "plan_contract").passed, true);

  changedResults.results.find((item) => item.scenario_id === "low-risk-native-tool")
    .plan.pop();
  report = evaluateRegressionSuite(changedSuite, changedResults);
  assert.equal(assertionFor(report, "low-risk-native-tool", "plan_contract").passed, false);
});

test("DSL rejects overlapping required and forbidden tools", () => {
  const changed = structuredClone(suite);
  changed.cases[0].expect.tools.forbidden = ["android.battery.status"];
  assert.throws(
    () => validateRegressionSuite(changed),
    /required\/forbidden overlap/
  );
});

test("DSL rejects unknown fields instead of silently ignoring them", () => {
  const changed = structuredClone(suite);
  changed.cases[0].expect.result.unbounded = true;
  assert.throws(
    () => validateRegressionSuite(changed),
    /unknown fields: unbounded/
  );
});

test("DSL compiles to the existing benchmark execution contract", () => {
  const compiled = compileRegressionSuite(suite);
  assert.equal(compiled.schema_version, 1);
  assert.equal(compiled.scenarios.length, suite.cases.length);
  assert.deepEqual(
    compiled.scenarios[2].expect.ordered_tools,
    ["workspace.write", "runtime.execute"]
  );
});

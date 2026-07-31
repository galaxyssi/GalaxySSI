import assert from "node:assert/strict";
import test from "node:test";
import { evaluateMemoryLoCoMo } from "./memory-locomo-lib.mjs";

const passing = {
  schema_version: 1,
  benchmark_id: "test",
  results: [
    {
      query_id: "current",
      category: "temporal",
      passed: true,
      assertions: [
        { type: "include", value: "current", passed: true },
        { type: "exclude", value: "old", passed: true }
      ]
    },
    {
      query_id: "secret",
      category: "privacy",
      passed: true,
      assertions: [
        { type: "exclude", value: "secret", passed: true },
        { type: "empty", value: "", passed: true }
      ]
    }
  ]
};

test("memory evaluator reports retrieval, contamination, temporal and privacy scores", () => {
  const report = evaluateMemoryLoCoMo(passing);
  assert.equal(report.passed, true);
  assert.equal(report.score, 1);
  assert.equal(report.contamination_avoidance, 1);
  assert.equal(report.privacy_accuracy, 1);
});

test("privacy leakage is a critical benchmark failure", () => {
  const changed = structuredClone(passing);
  changed.results[1].passed = false;
  changed.results[1].assertions[0].passed = false;
  const report = evaluateMemoryLoCoMo(changed);
  assert.equal(report.passed, false);
  assert.deepEqual(report.critical_failures, ["secret:exclude"]);
});

test("cross-session contamination is a critical benchmark failure", () => {
  const changed = structuredClone(passing);
  changed.results[0].passed = false;
  changed.results[0].assertions[1].passed = false;
  const report = evaluateMemoryLoCoMo(changed);
  assert.equal(report.passed, false);
  assert.deepEqual(report.critical_failures, ["current:exclude"]);
});

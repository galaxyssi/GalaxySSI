import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  evaluateBenchmark,
  readJson,
  validateManifest
} from "./agent-benchmark-lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const manifest = readJson(path.join(root, "benchmarks", "agent", "manifest.json"));
const reference = readJson(
  path.join(root, "benchmarks", "agent", "reference-results.json")
);

test("reference Agent benchmark satisfies every critical contract", () => {
  const report = evaluateBenchmark(manifest, reference);
  assert.equal(report.passed, true);
  assert.equal(report.passed_count, manifest.scenarios.length);
  assert.equal(report.score, 1);
});

test("duplicate final replies fail the benchmark", () => {
  const changed = structuredClone(reference);
  changed.results.find((item) => item.scenario_id === "duplicate-suppression")
    .final_response_count = 2;
  const report = evaluateBenchmark(manifest, changed);
  assert.equal(report.passed, false);
  assert.ok(report.critical_failures.includes(
    "duplicate-suppression:single_final_response"
  ));
});

test("route correlation mismatches fail isolation", () => {
  const changed = structuredClone(reference);
  changed.results.find((item) => item.scenario_id === "route-isolation")
    .correlation.turn_id = "turn-other";
  const report = evaluateBenchmark(manifest, changed);
  assert.equal(report.passed, false);
  assert.ok(report.critical_failures.includes(
    "route-isolation:correlation_isolation"
  ));
});

test("manifest validation requires complete product categories", () => {
  const changed = structuredClone(manifest);
  changed.scenarios = changed.scenarios.filter((item) => item.category !== "memory");
  assert.throws(
    () => validateManifest(changed),
    /categories are missing: memory/
  );
});


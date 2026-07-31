import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  evaluateVersionHealth,
  evidenceDigest,
  validateVersionHealthEvidence,
  validateVersionHealthPolicy
} from "./version-health-score.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const policy = JSON.parse(fs.readFileSync(
  path.join(root, "benchmarks", "version-health", "policy.json"),
  "utf8"
));
const reference = JSON.parse(fs.readFileSync(
  path.join(root, "benchmarks", "version-health", "reference-evidence.json"),
  "utf8"
));

function dimension(report, identifier) {
  return report.dimensions.find((item) => item.id === identifier);
}

test("reference evidence produces a healthy six-dimension score", () => {
  const report = evaluateVersionHealth(policy, reference);
  assert.equal(report.passed, true);
  assert.equal(report.status, "healthy");
  assert.equal(report.grade, "A");
  assert.equal(report.dimensions.length, 6);
  assert.equal(report.overall_score, 0.944625);
});

test("a missing required metric blocks its dimension and the version", () => {
  const changed = structuredClone(reference);
  changed.metrics = changed.metrics.filter((metric) => metric.id !== "recovery_success_rate");
  const report = evaluateVersionHealth(policy, changed);
  assert.equal(report.passed, false);
  assert.equal(dimension(report, "reliability").evidence_complete, false);
  assert.ok(report.failures.includes("reliability:recovery_success_rate:missing"));
});

test("stale evidence contributes zero and cannot pass a required metric", () => {
  const changed = structuredClone(reference);
  changed.fixture = false;
  const report = evaluateVersionHealth(policy, changed, {
    now: "2026-08-10T00:00:00.000Z"
  });
  assert.equal(report.passed, false);
  assert.equal(report.overall_score, 0);
  assert.ok(report.failures.some((failure) => failure.endsWith(":stale")));
});

test("a critical security failure blocks a high overall score", () => {
  const changed = structuredClone(reference);
  for (const metric of changed.metrics.filter((item) => item.dimension === "security")) {
    metric.score = 0.7;
  }
  const report = evaluateVersionHealth(policy, changed);
  assert.ok(report.overall_score >= policy.minimum_overall_score);
  assert.equal(dimension(report, "security").passed, false);
  assert.equal(report.passed, false);
});

test("an absent optional metric does not dilute the score", () => {
  const changedPolicy = structuredClone(policy);
  changedPolicy.dimensions[0].metrics.push({
    id: "optional_energy_efficiency",
    weight: 0.2,
    required: false
  });
  const baseline = evaluateVersionHealth(policy, reference);
  const report = evaluateVersionHealth(changedPolicy, reference);
  assert.equal(report.overall_score, baseline.overall_score);
  assert.equal(report.passed, true);
});

test("future-dated metrics are rejected", () => {
  const changed = structuredClone(reference);
  changed.fixture = false;
  assert.throws(
    () => evaluateVersionHealth(policy, changed, {
      now: "2026-07-30T00:00:00.000Z"
    }),
    /dated in the future/
  );
});

test("version comparison reports overall and per-dimension deltas", () => {
  const previous = structuredClone(reference);
  previous.version = "previous";
  previous.metrics
    .filter((metric) => metric.dimension === "automation_success_rate")
    .forEach((metric) => {
      metric.score = 0.6;
    });
  const report = evaluateVersionHealth(policy, reference, {
    previousEvidence: previous
  });
  assert.equal(report.comparison.previous_version, "previous");
  assert.ok(report.comparison.overall_delta > 0);
  assert.ok(report.comparison.dimension_deltas.automation_success_rate > 0);
});

test("evidence digest is stable and detects tampering", () => {
  const digest = evidenceDigest(reference);
  const reordered = {
    ...reference,
    metrics: reference.metrics.map((metric) => ({ ...metric }))
  };
  assert.equal(evidenceDigest(reordered), digest);
  reordered.metrics[0].score = 0.1;
  assert.notEqual(evidenceDigest(reordered), digest);
});

test("policy and evidence reject unknown schema fields", () => {
  const changedPolicy = { ...policy, bypass: true };
  const changedEvidence = { ...reference, trusted_without_evidence: true };
  assert.throws(() => validateVersionHealthPolicy(changedPolicy), /unknown fields/);
  assert.throws(() => validateVersionHealthEvidence(changedEvidence), /unknown fields/);
});

test("strict live scoring rejects deterministic fixture evidence", () => {
  const result = spawnSync(
    process.execPath,
    [path.join(here, "run-version-health-score.mjs"), "--strict-live"],
    { cwd: root, encoding: "utf8", shell: false }
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /requires non-fixture version evidence/);
});

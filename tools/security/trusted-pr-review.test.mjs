import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  evaluateCiState,
  evaluateTrustedAutomationReview,
  validateTrustedReviewPolicy
} from "./trusted-pr-review-lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const policy = JSON.parse(
  fs.readFileSync(path.resolve(here, "..", "..", ".github", "trusted-pr-review-policy.json"), "utf8")
);
const head = "a".repeat(40);
const successfulChecks = policy.required_checks.map((name) => ({
  name,
  status: "completed",
  conclusion: "success"
}));

function review(login, type = "Bot", commitId = head) {
  return {
    state: "approved",
    commit_id: commitId,
    user: { login, type }
  };
}

function evaluate(overrides = {}) {
  return evaluateTrustedAutomationReview({
    policy,
    review: review("github-actions[bot]"),
    pullRequest: { head: { sha: head } },
    checkRuns: successfulChecks,
    statuses: [],
    ...overrides
  });
}

test("policy requires an explicit trusted bot and CI set", () => {
  const parsed = validateTrustedReviewPolicy(policy);
  assert.deepEqual(parsed.trusted_bot_logins, ["github-actions[bot]"]);
  assert.equal(parsed.required_checks.length, 5);
  assert.throws(
    () => validateTrustedReviewPolicy({ ...policy, trusted_bot_logins: [] }),
    /must not be empty/
  );
});

test("human approval remains under normal repository review policy", () => {
  const result = evaluate({ review: review("galaxyssi", "User") });
  assert.equal(result.applicable, false);
  assert.equal(result.allowed, true);
  assert.equal(result.code, "human_review");
});

test("untrusted bot approval is rejected", () => {
  const result = evaluate({ review: review("unknown-reviewer[bot]") });
  assert.equal(result.applicable, true);
  assert.equal(result.allowed, false);
  assert.equal(result.code, "untrusted_bot");
});

test("trusted bot approval must match the current pull request head", () => {
  const result = evaluate({ review: review("github-actions[bot]", "Bot", "b".repeat(40)) });
  assert.equal(result.allowed, false);
  assert.equal(result.code, "stale_review");
});

test("trusted bot approval requires every mandatory check", () => {
  const result = evaluate({ checkRuns: successfulChecks.slice(1) });
  assert.equal(result.allowed, false);
  assert.equal(result.code, "ci_not_green");
  assert.deepEqual(result.ci.missing, [policy.required_checks[0]]);
});

test("trusted bot approval is rejected while CI is pending", () => {
  const checks = structuredClone(successfulChecks);
  checks[1] = { ...checks[1], status: "in_progress", conclusion: null };
  const result = evaluate({ checkRuns: checks });
  assert.equal(result.allowed, false);
  assert.deepEqual(result.ci.pending, [checks[1].name]);
});

test("any failed duplicate check keeps CI red", () => {
  const checks = [
    ...successfulChecks,
    { ...successfulChecks[0], conclusion: "failure" }
  ];
  const result = evaluate({ checkRuns: checks });
  assert.equal(result.allowed, false);
  assert.deepEqual(result.ci.failing, [`${successfulChecks[0].name}:failure`]);
});

test("legacy commit status failures also keep CI red", () => {
  const result = evaluate({
    statuses: [{ context: "external/security", state: "failure" }]
  });
  assert.equal(result.allowed, false);
  assert.deepEqual(result.ci.failing, ["external/security:failure"]);
});

test("trusted current-head approval passes only after all CI is green", () => {
  const result = evaluate({
    statuses: [{ context: "external/security", state: "success" }]
  });
  assert.equal(result.applicable, true);
  assert.equal(result.allowed, true);
  assert.equal(result.code, "trusted_review");
  assert.equal(result.ci.green, true);
});

test("ignored review gate does not create a circular dependency", () => {
  const ci = evaluateCiState(
    policy,
    [
      ...successfulChecks,
      { name: "trusted-automation-review", status: "in_progress", conclusion: null }
    ],
    []
  );
  assert.equal(ci.green, true);
});

test("command line gate exposes trusted and rejected outcomes as exit status", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-review-gate-"));
  const fixture = path.join(temporary, "event.json");
  const checker = path.join(here, "check-trusted-pr-review.mjs");
  const payload = {
    review: review("github-actions[bot]"),
    pull_request: { number: 42, head: { sha: head } },
    check_runs: successfulChecks,
    statuses: []
  };
  try {
    fs.writeFileSync(fixture, JSON.stringify(payload), "utf8");
    const accepted = spawnSync(process.execPath, [checker, "--fixture", fixture], {
      encoding: "utf8"
    });
    assert.equal(accepted.status, 0, accepted.stderr);

    payload.review = review("unknown-reviewer[bot]");
    fs.writeFileSync(fixture, JSON.stringify(payload), "utf8");
    const rejected = spawnSync(process.execPath, [checker, "--fixture", fixture], {
      encoding: "utf8"
    });
    assert.equal(rejected.status, 1, rejected.stderr);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

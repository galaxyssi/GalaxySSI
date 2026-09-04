#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  evaluateTrustedAutomationReview,
  validateTrustedReviewPolicy
} from "./trusted-pr-review-lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const defaultPolicyPath = path.join(root, ".github", "trusted-pr-review-policy.json");

function parseArgs(argv) {
  const options = {
    event: process.env.GITHUB_EVENT_PATH || "",
    policy: defaultPolicyPath,
    fixture: ""
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--event" && value) {
      options.event = path.resolve(value);
      index += 1;
    } else if (argument === "--policy" && value) {
      options.policy = path.resolve(value);
      index += 1;
    } else if (argument === "--fixture" && value) {
      options.fixture = path.resolve(value);
      index += 1;
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

async function githubJson(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      ...(options.headers || {})
    }
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`GitHub API ${response.status}: ${text.slice(0, 1_000)}`);
  }
  return text ? JSON.parse(text) : {};
}

function dismissalMessage(result) {
  if (result.code === "untrusted_bot") {
    return `GalaxySSI rejected automated approval from untrusted bot ${result.reviewer}.`;
  }
  if (result.code === "stale_review") {
    return "GalaxySSI rejected an automated approval that does not match the current pull request head.";
  }
  const details = [
    result.ci?.missing?.length ? `missing: ${result.ci.missing.join(", ")}` : "",
    result.ci?.pending?.length ? `pending: ${result.ci.pending.join(", ")}` : "",
    result.ci?.failing?.length ? `failing: ${result.ci.failing.join(", ")}` : ""
  ].filter(Boolean).join("; ");
  return `GalaxySSI rejected automated approval before CI was green${details ? ` (${details})` : ""}.`;
}

async function liveInputs(event, policy) {
  const repository = event?.repository?.full_name;
  const headSha = event?.pull_request?.head?.sha;
  const token = process.env.GITHUB_TOKEN;
  if (!repository || !headSha) {
    throw new Error("The GitHub event does not contain a pull request repository and head SHA");
  }
  if (!token) {
    throw new Error("GITHUB_TOKEN is required for automated review validation");
  }
  const apiRoot = `https://api.github.com/repos/${repository}`;
  const [checkPayload, statusPayload] = await Promise.all([
    githubJson(`${apiRoot}/commits/${headSha}/check-runs?per_page=100`, token),
    githubJson(`${apiRoot}/commits/${headSha}/status?per_page=100`, token)
  ]);
  return {
    policy,
    review: event.review,
    pullRequest: event.pull_request,
    checkRuns: checkPayload.check_runs || [],
    statuses: statusPayload.statuses || [],
    token,
    apiRoot
  };
}

function appendSummary(result) {
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryPath) return;
  const lines = [
    "## Trusted PR review",
    "",
    `- Result: ${result.allowed ? "accepted" : "rejected"}`,
    `- Policy code: \`${result.code}\``,
    `- Reviewer: \`${result.reviewer || "unknown"}\``
  ];
  if (result.ci) {
    lines.push(
      `- CI green: ${result.ci.green ? "yes" : "no"}`,
      `- Missing: ${result.ci.missing.join(", ") || "none"}`,
      `- Pending: ${result.ci.pending.join(", ") || "none"}`,
      `- Failing: ${result.ci.failing.join(", ") || "none"}`
    );
  }
  fs.appendFileSync(summaryPath, `${lines.join("\n")}\n`, "utf8");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const policy = validateTrustedReviewPolicy(readJson(options.policy));
  let inputs;
  if (options.fixture) {
    const fixture = readJson(options.fixture);
    inputs = {
      policy,
      review: fixture.review,
      pullRequest: fixture.pull_request,
      checkRuns: fixture.check_runs || [],
      statuses: fixture.statuses || []
    };
  } else {
    if (!options.event) {
      throw new Error("A GitHub event file is required");
    }
    inputs = await liveInputs(readJson(options.event), policy);
  }

  const result = evaluateTrustedAutomationReview(inputs);
  if (!result.allowed && result.applicable && !options.fixture) {
    const reviewId = inputs.review?.id;
    const pullNumber = inputs.pullRequest?.number;
    if (!reviewId || !pullNumber) {
      throw new Error("Invalid automated review is missing its review or pull request ID");
    }
    await githubJson(
      `${inputs.apiRoot}/pulls/${pullNumber}/reviews/${reviewId}/dismissals`,
      inputs.token,
      {
        method: "PUT",
        body: JSON.stringify({ message: dismissalMessage(result) })
      }
    );
  }
  appendSummary(result);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.allowed ? 0 : 1;
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});

#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { evaluateVersionHealth } from "./version-health-score.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const defaults = {
  policy: path.join(root, "benchmarks", "version-health", "policy.json"),
  evidence: path.join(root, "benchmarks", "version-health", "reference-evidence.json"),
  previousEvidence: "",
  output: path.join(root, "build", "reports", "version-health", "report.json"),
  strictLive: false
};

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function parseArgs(argv) {
  const options = { ...defaults };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--policy" && value) {
      options.policy = path.resolve(value);
      index += 1;
    } else if (argument === "--evidence" && value) {
      options.evidence = path.resolve(value);
      index += 1;
    } else if (argument === "--previous-evidence" && value) {
      options.previousEvidence = path.resolve(value);
      index += 1;
    } else if (argument === "--output" && value) {
      options.output = path.resolve(value);
      index += 1;
    } else if (argument === "--strict-live") {
      options.strictLive = true;
    } else if (argument === "--help") {
      console.log(`GalaxySSI version health score

Usage:
  npm run score:version-health
  npm run score:version-health -- --evidence <version-evidence.json> --strict-live

Options:
  --policy <path>             Health policy
  --evidence <path>           Current version evidence
  --previous-evidence <path>  Optional previous version evidence
  --output <path>             Machine-readable report path
  --strict-live               Reject deterministic fixture evidence
`);
      process.exit(0);
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function printReport(report) {
  console.log(
    `GalaxySSI version health: ${report.grade} ${(report.overall_score * 100).toFixed(1)}%`
  );
  console.log(`Status: ${report.status}`);
  for (const dimension of report.dimensions) {
    console.log(
      `${dimension.passed ? "PASS" : "FAIL"} ${dimension.label}: ` +
      `${(dimension.score * 100).toFixed(1)}%`
    );
  }
  if (report.comparison) {
    const sign = report.comparison.overall_delta >= 0 ? "+" : "";
    console.log(
      `Change from ${report.comparison.previous_version}: ` +
      `${sign}${(report.comparison.overall_delta * 100).toFixed(1)} points`
    );
  }
  if (report.fixture) {
    console.log("Evidence: deterministic reference fixture, not a release health claim");
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const evidence = readJson(options.evidence);
  if (options.strictLive && evidence.fixture === true) {
    throw new Error("--strict-live requires non-fixture version evidence");
  }
  const report = evaluateVersionHealth(
    readJson(options.policy),
    evidence,
    {
      previousEvidence: options.previousEvidence
        ? readJson(options.previousEvidence)
        : undefined
    }
  );
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  printReport(report);
  console.log(`Report: ${options.output}`);
  process.exitCode = report.passed ? 0 : 1;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exitCode = 1;
}

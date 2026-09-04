#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { readJson } from "./agent-benchmark-lib.mjs";
import { evaluateRegressionSuite } from "./agent-regression-dsl.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const defaults = {
  suite: path.join(root, "benchmarks", "agent", "regression-suite.json"),
  results: path.join(root, "benchmarks", "agent", "reference-results.json"),
  output: path.join(root, "build", "reports", "agent-regression", "report.json")
};

function parseArgs(argv) {
  const options = { ...defaults };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--suite" && value) {
      options.suite = path.resolve(value);
      index += 1;
    } else if (argument === "--results" && value) {
      options.results = path.resolve(value);
      index += 1;
    } else if (argument === "--output" && value) {
      options.output = path.resolve(value);
      index += 1;
    } else if (argument === "--help") {
      console.log(`GalaxySSI Agent regression DSL

Usage:
  npm run regression:agent
  npm run regression:agent -- --results <captured-results.json>

Options:
  --suite <path>    Versioned Agent regression DSL suite
  --results <path>  Captured or replay result set
  --output <path>   Machine-readable report path
`);
      process.exit(0);
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function printSummary(report) {
  console.log(`GalaxySSI Agent regression DSL: ${(report.score * 100).toFixed(1)}%`);
  console.log(`Cases: ${report.passed_count}/${report.scenario_count}`);
  for (const record of report.records) {
    const failures = record.assertions
      .filter((assertion) => !assertion.passed)
      .map((assertion) => assertion.name)
      .join(", ");
    console.log(
      `${record.passed ? "PASS" : "FAIL"} ${record.id}` +
      `${failures ? ` (${failures})` : ""}`
    );
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const report = {
    ...evaluateRegressionSuite(readJson(options.suite), readJson(options.results)),
    generated_at: new Date().toISOString(),
    source: path.relative(root, options.results).replaceAll("\\", "/")
  };
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  printSummary(report);
  console.log(`Report: ${options.output}`);
  process.exitCode = report.passed ? 0 : 1;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exitCode = 1;
}

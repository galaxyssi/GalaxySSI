#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { evaluateMemoryLoCoMo } from "./memory-locomo-lib.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const corpusPath = path.join(root, "benchmarks", "memory", "locomo-corpus.json");
const defaultRaw = path.join(root, "build", "reports", "memory-locomo", "raw-results.json");
const defaultReport = path.join(root, "build", "reports", "memory-locomo", "report.json");

function parseArgs(argv) {
  const options = { results: "", output: defaultReport };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--results" && value) {
      options.results = path.resolve(value);
      index += 1;
    } else if (argument === "--output" && value) {
      options.output = path.resolve(value);
      index += 1;
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function runAndroidCorpus() {
  fs.rmSync(defaultRaw, { force: true });
  const wrapper = path.join(
    root,
    "apps",
    "android",
    process.platform === "win32" ? "gradlew.bat" : "gradlew"
  );
  const argumentsList = [
    ":app:testDebugUnitTest",
    "--tests",
    "com.galaxyssi.chat.GlobalMemoryLoCoMoCorpusTest",
    "--no-daemon"
  ];
  const command = process.platform === "win32"
    ? {
        executable: process.env.ComSpec || "cmd.exe",
        arguments: ["/d", "/s", "/c", wrapper, ...argumentsList]
      }
    : { executable: wrapper, arguments: argumentsList };
  const result = spawnSync(command.executable, command.arguments, {
    cwd: path.join(root, "apps", "android"),
    stdio: "inherit",
    shell: false,
    env: { ...process.env, GALAXYSSI_MEMORY_BENCHMARK: "1" }
  });
  if (result.error) {
    throw result.error;
  }
  if (!fs.existsSync(defaultRaw)) {
    throw new Error(
      result.status === 0
        ? "Android memory corpus did not produce a result"
        : `Android memory corpus failed with exit code ${result.status}`
    );
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.results) {
    runAndroidCorpus();
  }
  const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
  const rawPath = options.results || defaultRaw;
  const raw = JSON.parse(fs.readFileSync(rawPath, "utf8"));
  const report = {
    ...evaluateMemoryLoCoMo(raw, Number(corpus.minimum_score)),
    generated_at: new Date().toISOString(),
    corpus: path.relative(root, corpusPath).replaceAll("\\", "/")
  };
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  console.log(`Memory LoCoMo benchmark: ${(report.score * 100).toFixed(1)}%`);
  console.log(`Queries: ${report.passed_scenarios}/${report.scenario_count}`);
  console.log(`Retrieval recall: ${(report.retrieval_recall * 100).toFixed(1)}%`);
  console.log(`Contamination avoidance: ${(report.contamination_avoidance * 100).toFixed(1)}%`);
  console.log(`Temporal accuracy: ${(report.temporal_accuracy * 100).toFixed(1)}%`);
  console.log(`Privacy accuracy: ${(report.privacy_accuracy * 100).toFixed(1)}%`);
  console.log(`Abstention accuracy: ${(report.abstention_accuracy * 100).toFixed(1)}%`);
  console.log(`Report: ${options.output}`);
  process.exitCode = report.passed ? 0 : 1;
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exitCode = 1;
}

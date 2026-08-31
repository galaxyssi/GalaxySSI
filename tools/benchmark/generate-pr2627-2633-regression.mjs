#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildPr2627To2633Corpus } from "./pr2627-2633-regression-corpus.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const outputDirectory = path.join(
  root,
  "apps",
  "android",
  "app",
  "src",
  "androidTest",
  "assets",
  "pr2627-pr2633-targeted-regression"
);

const corpus = buildPr2627To2633Corpus();
fs.rmSync(outputDirectory, { recursive: true, force: true });
fs.mkdirSync(outputDirectory, { recursive: true });
const suiteFiles = [];
for (const suiteId of [...new Set(corpus.cases.map((item) => item.suite_id))]) {
  const fileName = `${suiteId}.json`;
  const cases = corpus.cases.filter((item) => item.suite_id === suiteId);
  fs.writeFileSync(
    path.join(outputDirectory, fileName),
    `${JSON.stringify({ schema_version: 1, suite_id: suiteId, cases }, null, 2)}\n`,
    "utf8"
  );
  suiteFiles.push(fileName);
}
fs.writeFileSync(
  path.join(outputDirectory, "manifest.json"),
  `${JSON.stringify({
    schema_version: corpus.schema_version,
    benchmark_id: corpus.benchmark_id,
    target_device: corpus.target_device,
    exact_case_count: corpus.exact_case_count,
    pull_requests: corpus.pull_requests,
    suite_files: suiteFiles
  }, null, 2)}\n`,
  "utf8"
);
console.log(outputDirectory);

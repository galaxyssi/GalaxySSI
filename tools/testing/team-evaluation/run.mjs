#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readJson } from "../../benchmark/agent-benchmark-lib.mjs";
import { accountingTemplate, compare, createPlan, importBenchmark, renderMarkdown, reviewerPacket, validatePlan } from "./lib.mjs";
import { fixtureExport } from "./fixture.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const HELP = `Offline equal-budget single-Agent/team evaluation

node tools/testing/team-evaluation/run.mjs plan --config <json> --out <new-directory> [--repetitions 3]
node tools/testing/team-evaluation/run.mjs run --plan <plan.json> --adapter fixture --out <new-directory>
node tools/testing/team-evaluation/run.mjs import --plan <plan.json> --benchmark <results.json> --accounting <sidecar.json> --out <new-directory>
node tools/testing/team-evaluation/run.mjs run --plan <plan.json> --adapter export --results <export.json> --out <new-directory>

Every command accepts --corpus <json> (default: adjacent corpus.json).
No default adapter. Fixture mode is synthetic; export mode requires actual evidence.
Nothing executes tasks or invokes models, shells, devices, or network endpoints.
Exit 0: complete actual accounting; 2: fixture or incomplete comparison; 1: input/CLI error.
Plan/import use exit 0 for successful file generation, not app acceptance.
`;

function parse(argv) {
  const [command, ...args] = argv;
  if (command === "--help" || command === "help") return { command: "help" };
  const allowed = {
    plan: ["config", "out", "repetitions", "corpus"],
    run: ["plan", "adapter", "results", "out", "corpus"],
    import: ["plan", "benchmark", "accounting", "out", "corpus"]
  }[command];
  if (!allowed) throw new Error("Specify plan, import, or run; see --help");
  const options = { command };
  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i];
    const key = flag.slice(2);
    if (!flag.startsWith("--") || !allowed.includes(key) || Object.hasOwn(options, key) ||
        !args[i + 1] || args[i + 1].startsWith("--")) throw new Error(`Unknown, duplicate, or incomplete option: ${flag}`);
    options[key] = args[i + 1];
  }
  for (const key of { plan: ["config", "out"], run: ["plan", "adapter", "out"], import: ["plan", "benchmark", "accounting", "out"] }[command]) {
    if (!options[key]) throw new Error(`Required: --${key}`);
  }
  return options;
}

function writeFiles(directory, files) {
  const output = path.resolve(directory);
  for (const name of Object.keys(files)) {
    if (fs.existsSync(path.join(output, name))) throw new Error(`Refusing to overwrite evidence: ${name}`);
  }
  fs.mkdirSync(output, { recursive: true });
  for (const [name, value] of Object.entries(files)) {
    fs.writeFileSync(path.join(output, name), typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`,
      { flag: "wx", mode: 0o600 });
  }
  console.log(`Wrote ${Object.keys(files).join(", ")} to ${output}`);
}

function main() {
  const options = parse(process.argv.slice(2));
  if (options.command === "help") { console.log(HELP); return; }
  const corpus = readJson(options.corpus || path.join(here, "corpus.json"));
  if (options.command === "plan") {
    const { plan, private_key } = createPlan(corpus, readJson(options.config), Number(options.repetitions || 3));
    const requests = {
      schema_version: 1, plan_sha256: plan.plan_sha256,
      warning: "Collector input only. Do not expose the private arm key or answer rubric to graders or models.",
      requests: plan.slots.map((slot) => ({ ...slot, budget: plan.budget, controls: plan.controls,
        request: corpus.scenarios.find((scenario) => scenario.id === slot.scenario_id).request }))
    };
    writeFiles(options.out, { "plan.json": plan, "arm-key.private.json": private_key, "requests.json": requests,
      "accounting-template.private.json": accountingTemplate(plan) });
    return;
  }
  const plan = readJson(options.plan);
  validatePlan(plan, corpus);
  if (options.command === "import") {
    const imported = importBenchmark(plan, corpus, readJson(options.benchmark), readJson(options.accounting));
    writeFiles(options.out, { "export.json": imported });
    return;
  }
  if (!["fixture", "export"].includes(options.adapter)) throw new Error("Adapter must be fixture or export");
  if (options.adapter === "fixture" && options.results) throw new Error("Fixture adapter does not consume captured results");
  if (options.adapter === "export" && !options.results) throw new Error("Export adapter requires --results");
  const input = options.adapter === "fixture" ? fixtureExport(plan, corpus) : readJson(options.results);
  const expectedKind = options.adapter === "fixture" ? "fixture" : "actual";
  const report = compare(plan, corpus, input, expectedKind);
  writeFiles(options.out, {
    "report.json": report, "report.md": renderMarkdown(report),
    "reviewer-packet.json": reviewerPacket(plan, corpus, input, expectedKind),
    "audit-input.private.json": input
  });
  const assigned = report.all_assigned;
  console.log(`${report.conclusion}; all-assigned unknown outcomes ${assigned.arms.A.unknown + assigned.arms.B.unknown}/${plan.slots.length}; diagnostic eligible pairs ${report.eligible_pairs}/${report.expected_pairs}`);
  process.exitCode = expectedKind === "actual" && report.eligible_pairs === report.expected_pairs ? 0 : 2;
}

try { main(); } catch (error) { console.error(`Evaluation error: ${error.message}`); process.exitCode = 1; }

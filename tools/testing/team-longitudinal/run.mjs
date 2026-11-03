#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createPlan, collectorRequests, validatePlan } from "./protocol.mjs";
import { inspectCapture } from "./capture.mjs";
import { fixtureCapture, fixtureConfig } from "./fixture.mjs";

const HELP = `Offline six-arm longitudinal capture protocol
example --out <new-directory>
plan --config <private-config.json> --out <new-directory>
fixture --plan <plan.json> --out <new-directory>
inspect --plan <plan.json> --capture <private-capture.json> --out <new-directory>

No models, devices, network, shells or user tasks are executed.
Outputs must be outside a Git checkout. All outputs are collector-private.
Exit 0: file generation or consistent closed actual capture contract, not efficacy.
Exit 2: synthetic evidence, incomplete capture or contract violations.
Exit 1: malformed input or unsafe output destination.
`;

function options(argv) {
  const [command, ...args] = argv;
  if (["help", "--help"].includes(command)) return { command: "help" };
  const required = { example: ["out"], plan: ["config", "out"], fixture: ["plan", "out"], inspect: ["plan", "capture", "out"] }[command];
  if (!required) throw new Error("Unknown command; use --help");
  const result = { command };
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i].startsWith("--") ? args[i].slice(2) : "";
    if (!required.includes(key) || Object.hasOwn(result, key) || !args[i + 1] || args[i + 1].startsWith("--")) throw new Error("Unknown, duplicate or missing option");
    result[key] = args[i + 1];
  }
  if (required.some((key) => !result[key])) throw new Error("Missing required option");
  return result;
}

function outsideGit(directory) {
  let current = directory;
  while (!fs.existsSync(current)) {
    const parent = path.dirname(current);
    if (parent === current) throw new Error("No existing output ancestor");
    current = parent;
  }
  // Resolve junctions/symlinks before checking ancestry, not just the supplied path.
  for (let resolved = fs.realpathSync(current); ; resolved = path.dirname(resolved)) {
    if (fs.existsSync(path.join(resolved, ".git"))) throw new Error("Keep study artifacts outside Git");
    if (path.dirname(resolved) === resolved) break;
  }
}

function write(directory, files) {
  const dest = path.resolve(directory);
  outsideGit(dest);
  if (fs.existsSync(dest)) throw new Error("Use a new output directory; evidence is never overwritten");
  fs.mkdirSync(dest, { recursive: true, mode: 0o700 });
  for (const [name, data] of Object.entries(files)) {
    fs.writeFileSync(path.join(dest, name), `${JSON.stringify(data, null, 2)}\n`, { flag: "wx", mode: 0o600 });
  }
  console.log(`Saved ${Object.keys(files).join(", ")} to ${dest}`);
}
const read = (filename) => JSON.parse(fs.readFileSync(filename, "utf8").replace(/^\uFEFF/, ""));

try {
  const opts = options(process.argv.slice(2));
  if (opts.command === "help") console.log(HELP);
  else if (opts.command === "example") write(opts.out, { "fixture-config.json": fixtureConfig() });
  else if (opts.command === "plan") {
    const plan = createPlan(read(opts.config));
    write(opts.out, { "plan.private.json": plan, "collector-requests.private.json": collectorRequests(plan) });
  } else {
    const plan = validatePlan(read(opts.plan));
    if (opts.command === "fixture") {
      write(opts.out, { "fixture-capture.json": fixtureCapture(plan) }); process.exitCode = 2;
    } else {
      const capture = read(opts.capture), report = inspectCapture(plan, capture);
      write(opts.out, { "contract-report.private.json": report, "audit-input.private.json": capture });
      console.log(report.verdict);
      process.exitCode = report.evidence_kind === "actual" && report.verdict === "CAPTURE_CONTRACT_CONSISTENT_NOT_EFFICACY" ? 0 : 2;
    }
  }
} catch (error) { console.error(`Longitudinal protocol error: ${error.message}`); process.exitCode = 1; }

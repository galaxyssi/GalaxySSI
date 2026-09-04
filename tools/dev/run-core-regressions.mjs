#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const defaultManifest = path.join(here, "core-regression-manifest.json");
const defaultReport = path.join(root, "build", "reports", "core-regressions", "report.json");

function normalized(value) {
  return String(value ?? "").trim();
}

export function validateCoreRegressionManifest(manifest) {
  if (!manifest || Number(manifest.schema_version) !== 1) {
    throw new Error("Core regression manifest must use schema_version 1");
  }
  const suites = Array.isArray(manifest.suites) ? manifest.suites : [];
  const required = Array.isArray(manifest.required_suites) ? manifest.required_suites : [];
  const identifiers = new Set();
  for (const suite of suites) {
    const identifier = normalized(suite.id);
    if (!identifier || identifiers.has(identifier)) {
      throw new Error(`Core regression suite ID is missing or duplicated: ${identifier}`);
    }
    identifiers.add(identifier);
    if (!Array.isArray(suite.commands) || suite.commands.length === 0) {
      throw new Error(`Core regression suite has no commands: ${identifier}`);
    }
    for (const command of suite.commands) {
      if (!normalized(command.executable) || !normalized(command.working_directory)) {
        throw new Error(`Core regression command is incomplete: ${identifier}`);
      }
      if (!Array.isArray(command.arguments)) {
        throw new Error(`Core regression command arguments are invalid: ${identifier}`);
      }
    }
  }
  const missing = required.filter((identifier) => !identifiers.has(identifier));
  if (missing.length > 0) {
    throw new Error(`Core regression suites are missing: ${missing.join(", ")}`);
  }
  return manifest;
}

function parseArgs(argv) {
  const options = {
    manifest: defaultManifest,
    report: defaultReport,
    suites: [],
    list: false,
    dryRun: false
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === "--manifest" && value) {
      options.manifest = path.resolve(value);
      index += 1;
    } else if (argument === "--report" && value) {
      options.report = path.resolve(value);
      index += 1;
    } else if (argument === "--suite" && value) {
      options.suites.push(...value.split(",").map(normalized).filter(Boolean));
      index += 1;
    } else if (argument === "--list") {
      options.list = true;
    } else if (argument === "--dry-run") {
      options.dryRun = true;
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return options;
}

function commandFor(entry) {
  const argumentsList = entry.arguments.map(String);
  switch (entry.executable) {
    case "{python}":
      return {
        executable: process.env.PYTHON || (process.platform === "win32" ? "python" : "python3"),
        arguments: argumentsList
      };
    case "{node}":
      return { executable: process.execPath, arguments: argumentsList };
    case "{npm}":
      return process.platform === "win32"
        ? {
            executable: process.env.ComSpec || "cmd.exe",
            arguments: ["/d", "/s", "/c", "npm.cmd", ...argumentsList]
          }
        : { executable: "npm", arguments: argumentsList };
    case "{gradle}": {
      const wrapper = path.join(
        root,
        "apps",
        "android",
        process.platform === "win32" ? "gradlew.bat" : "gradlew"
      );
      return process.platform === "win32"
        ? {
            executable: process.env.ComSpec || "cmd.exe",
            arguments: ["/d", "/s", "/c", wrapper, ...argumentsList]
          }
        : { executable: wrapper, arguments: argumentsList };
    }
    default:
      return { executable: entry.executable, arguments: argumentsList };
  }
}

function displayCommand(command) {
  return [command.executable, ...command.arguments]
    .map((value) => /\s/.test(value) ? JSON.stringify(value) : value)
    .join(" ");
}

function runCommand(entry, dryRun) {
  const command = commandFor(entry);
  const workingDirectory = path.resolve(root, entry.working_directory);
  const relative = path.relative(root, workingDirectory);
  if (
    relative.startsWith("..") ||
    path.isAbsolute(relative) ||
    !fs.existsSync(workingDirectory)
  ) {
    throw new Error(`Invalid core regression working directory: ${entry.working_directory}`);
  }
  console.log(`  ${displayCommand(command)}`);
  if (dryRun) {
    return { passed: true, exit_code: 0, duration_ms: 0, command: displayCommand(command) };
  }
  const started = Date.now();
  const result = spawnSync(command.executable, command.arguments, {
    cwd: workingDirectory,
    env: {
      ...process.env,
      PYTHONUTF8: "1",
      GALAXYSSI_CORE_REGRESSION: "1"
    },
    stdio: "inherit",
    shell: false
  });
  return {
    passed: !result.error && result.status === 0,
    exit_code: result.status ?? -1,
    duration_ms: Date.now() - started,
    command: displayCommand(command),
    error: result.error?.message || ""
  };
}

function runSuite(suite, dryRun) {
  console.log(`\n[core-regression] ${suite.id}: ${suite.description}`);
  const started = Date.now();
  const commands = [];
  for (const entry of suite.commands) {
    const result = runCommand(entry, dryRun);
    commands.push(result);
    if (!result.passed) {
      break;
    }
  }
  return {
    id: suite.id,
    description: suite.description,
    passed: commands.length === suite.commands.length &&
      commands.every((command) => command.passed),
    duration_ms: Date.now() - started,
    commands
  };
}

function printSummary(report) {
  console.log("\nCore regression summary");
  for (const suite of report.suites) {
    console.log(
      `${suite.passed ? "PASS" : "FAIL"} ${suite.id} ` +
      `${(suite.duration_ms / 1000).toFixed(1)}s`
    );
  }
  console.log(`${report.passed_count}/${report.suite_count} suites passed`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const manifest = validateCoreRegressionManifest(
    JSON.parse(fs.readFileSync(options.manifest, "utf8"))
  );
  if (options.list) {
    for (const suite of manifest.suites) {
      console.log(`${suite.id}\t${suite.description}`);
    }
    return;
  }
  const requested = new Set(options.suites);
  const suites = requested.size > 0
    ? manifest.suites.filter((suite) => requested.has(suite.id))
    : manifest.suites;
  const missing = [...requested].filter((identifier) => (
    !manifest.suites.some((suite) => suite.id === identifier)
  ));
  if (missing.length > 0) {
    throw new Error(`Unknown core regression suites: ${missing.join(", ")}`);
  }
  const records = suites.map((suite) => runSuite(suite, options.dryRun));
  const report = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    dry_run: options.dryRun,
    suite_count: records.length,
    passed_count: records.filter((record) => record.passed).length,
    passed: records.length > 0 && records.every((record) => record.passed),
    suites: records
  };
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  printSummary(report);
  process.exitCode = report.passed ? 0 : 1;
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}

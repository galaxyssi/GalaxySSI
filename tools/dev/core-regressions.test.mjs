import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validateCoreRegressionManifest } from "./run-core-regressions.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const manifestPath = path.join(here, "core-regression-manifest.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

test("core regression manifest covers every required product surface", () => {
  assert.doesNotThrow(() => validateCoreRegressionManifest(manifest));
  assert.deepEqual(
    new Set(manifest.suites.map((suite) => suite.id)),
    new Set(manifest.required_suites)
  );
});

test("core regression runner lists suites without executing product tests", () => {
  const result = spawnSync(
    process.execPath,
    [path.join(here, "run-core-regressions.mjs"), "--list"],
    { cwd: root, encoding: "utf8", shell: false }
  );
  assert.equal(result.status, 0, result.stderr);
  for (const identifier of manifest.required_suites) {
    assert.match(result.stdout, new RegExp(`^${identifier}\\t`, "m"));
  }
});

test("Android CI executes knowledge projection identity and privacy regressions", () => {
  const commands = manifest.suites.find((suite) => suite.id === "android").commands;
  const gradle = commands.find((command) => command.executable === "{gradle}");
  assert.ok(gradle.arguments.includes(":app:testDebugUnitTest"));
  for (const name of ["ObsidianProjectionBatchTest", "ObsidianProjectionCursorTest", "ObsidianProjectionPrivacyPolicyTest"]) {
    const index = gradle.arguments.indexOf(`com.galaxyssi.chat.${name}`);
    assert.ok(index > 0, `Missing regression suite: ${name}`);
    assert.equal(gradle.arguments[index - 1], "--tests");
  }
});

test("Android CI executes iterative dispatch and durable node identity regressions", () => {
  const commands = manifest.suites.find((suite) => suite.id === "android").commands;
  const gradle = commands.find((command) => command.executable === "{gradle}");
  for (const name of ["AgentPlanDispatchLoopTest", "AgentPlanNodeRecoveryTest"]) {
    const index = gradle.arguments.indexOf(`com.galaxyssi.chat.${name}`);
    assert.ok(index > 0, `Missing regression suite: ${name}`);
    assert.equal(gradle.arguments[index - 1], "--tests");
  }
});

test("core regression dry run resolves every platform command", () => {
  const report = path.join(root, "build", "reports", "core-regressions", "dry-run.json");
  const result = spawnSync(
    process.execPath,
    [
      path.join(here, "run-core-regressions.mjs"),
      "--dry-run",
      "--report",
      report
    ],
    { cwd: root, encoding: "utf8", shell: false }
  );
  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(fs.readFileSync(report, "utf8"));
  assert.equal(payload.passed, true);
  assert.equal(payload.suite_count, manifest.required_suites.length);
});

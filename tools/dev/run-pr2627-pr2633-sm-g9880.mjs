#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const androidRoot = path.join(root, "apps", "android");
const gradle = path.join(androidRoot, process.platform === "win32" ? "gradlew.bat" : "gradlew");
const appApk = path.join(androidRoot, "app", "build", "outputs", "apk", "debug", "app-debug.apk");
const testApk = path.join(
  androidRoot,
  "app",
  "build",
  "outputs",
  "apk",
  "androidTest",
  "debug",
  "app-debug-androidTest.apk"
);
const targetPackage = "com.signalasi.chat";
const testPackage = "com.signalasi.chat.test";
const testClass = "com.signalasi.chat.Pr2627To2633TargetedRegressionDeviceTest";
const runner = `${testPackage}/androidx.test.runner.AndroidJUnitRunner`;

function parseArgs(argv) {
  const options = { serial: "", skipBuild: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--serial" && argv[index + 1]) {
      options.serial = argv[++index];
    } else if (argv[index] === "--skip-build") {
      options.skipBuild = true;
    } else {
      throw new Error(`Unknown or incomplete argument: ${argv[index]}`);
    }
  }
  if (!options.serial) throw new Error("--serial is required");
  return options;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    env: { ...process.env, ...(options.env ?? {}) },
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024
  });
  if (options.print !== false) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
  }
  if (!options.allowFailure && result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with ${result.status}`);
  }
  return result;
}

function adb(serial, ...args) {
  return run("adb", ["-s", serial, ...args]);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const model = adb(options.serial, "shell", "getprop", "ro.product.model").stdout.trim();
  if (model !== "SM-G9880") {
    throw new Error(`Refusing to run on ${model || "unknown device"}; expected SM-G9880`);
  }

  run(process.execPath, ["tools/benchmark/generate-pr2627-2633-regression.mjs"]);
  if (!options.skipBuild) {
    run(gradle, ["--no-daemon", ":app:assembleDebug", ":app:assembleDebugAndroidTest"], {
      cwd: androidRoot,
      env: { ANDROID_SERIAL: options.serial }
    });
  }
  if (!fs.existsSync(appApk) || !fs.existsSync(testApk)) {
    throw new Error("Android app or instrumentation APK is missing");
  }

  adb(options.serial, "install", "-r", appApk);
  adb(options.serial, "install", "-r", testApk);
  adb(options.serial, "logcat", "-c");
  try {
    const execution = adb(
      options.serial,
      "shell",
      "am",
      "instrument",
      "-w",
      "-e",
      "class",
      testClass,
      runner
    );
    if (!execution.stdout.includes("OK (1 test)")) {
      throw new Error("Instrumentation did not report a successful test run");
    }
    const rawReport = adb(
      options.serial,
      "exec-out",
      "run-as",
      targetPackage,
      "cat",
      "files/test-reports/pr2627-pr2633-targeted-regression.json"
    ).stdout;
    const report = JSON.parse(rawReport);
    if (report.case_count !== 1000 || report.failed_count !== 0) {
      throw new Error(`Unexpected report totals: ${report.passed_count}/${report.case_count}`);
    }
    const output = path.join(root, "build", "reports", "pr2627-pr2633", "sm-g9880.json");
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    console.log(`Report: ${output}`);
  } finally {
    run("adb", ["-s", options.serial, "shell", "pm", "uninstall", testPackage], {
      allowFailure: true
    });
  }
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message);
  process.exitCode = 1;
}

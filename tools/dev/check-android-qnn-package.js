#!/usr/bin/env node
"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const androidApp = path.join(root, "apps", "android", "app");
const buildFile = path.join(androidApp, "build.gradle.kts");
const apk = path.resolve(
  process.argv[2] || path.join(androidApp, "build", "outputs", "apk", "debug", "app-debug.apk")
);
const qnnRuntimeVersion = "2.47.0";
const ortQnnVersion = "2.3.0";
const abiRoot = "lib/arm64-v8a";
const requiredLibraries = [
  "libonnxruntime.so",
  "libonnxruntime4j_jni.so",
  "libonnxruntime_providers_qnn.so",
  "libqnn_delegate_jni.so",
  "libQnnDsp.so",
  "libQnnDspV66Skel.so",
  "libQnnDspV66Stub.so",
  "libQnnGpu.so",
  "libQnnHtp.so",
  "libQnnHtpPrepare.so",
  "libQnnHtpV68Skel.so",
  "libQnnHtpV68Stub.so",
  "libQnnHtpV69Skel.so",
  "libQnnHtpV69Stub.so",
  "libQnnHtpV73Skel.so",
  "libQnnHtpV73Stub.so",
  "libQnnHtpV75Skel.so",
  "libQnnHtpV75Stub.so",
  "libQnnHtpV79Skel.so",
  "libQnnHtpV79Stub.so",
  "libQnnHtpV81Skel.so",
  "libQnnHtpV81Stub.so",
  "libQnnSystem.so",
  "libQnnTFLiteDelegate.so"
];

function run(command, args, options = {}) {
  const result = childProcess.spawnSync(command, args, {
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
    shell: false,
    ...options
  });
  if (result.error || result.status) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`${path.basename(command)} failed${detail ? `:\n${detail}` : ""}`);
  }
  return result.stdout || "";
}

function findJar() {
  const executable = process.platform === "win32" ? "jar.exe" : "jar";
  const candidates = [
    process.env.JAVA_HOME && path.join(process.env.JAVA_HOME, "bin", executable),
    process.platform === "win32" && path.join("C:", "Program Files", "Android", "Android Studio", "jbr", "bin", executable),
    executable
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (candidate === executable || fs.existsSync(candidate)) return candidate;
  }
  throw new Error("The Java jar tool is required to audit the Android QNN package");
}

function requireBuildMarker(source, marker) {
  if (!source.includes(marker)) {
    throw new Error(`Android QNN dependency marker is missing: ${marker}`);
  }
}

function formatMiB(bytes) {
  return (bytes / (1024 * 1024)).toFixed(2);
}

if (!fs.existsSync(buildFile)) throw new Error(`Android build file does not exist: ${buildFile}`);
if (!fs.existsSync(apk)) throw new Error(`APK does not exist: ${apk}`);

const buildSource = fs.readFileSync(buildFile, "utf8");
requireBuildMarker(buildSource, `buildConfigField("String", "QNN_RUNTIME_VERSION", "\\"${qnnRuntimeVersion}\\"")`);
requireBuildMarker(buildSource, `implementation("com.qualcomm.qti:qnn-runtime:${qnnRuntimeVersion}")`);
requireBuildMarker(buildSource, `implementation("com.qualcomm.qti:qnn-litert-delegate:${qnnRuntimeVersion}")`);
requireBuildMarker(buildSource, `implementation("com.qualcomm.qti:onnxruntime-android-qnn:${ortQnnVersion}")`);

const forbiddenVendorRoots = [
  path.join(androidApp, "src", "main", "jniLibs"),
  path.join(androidApp, "libs")
];
for (const directory of forbiddenVendorRoots) {
  if (!fs.existsSync(directory)) continue;
  const entries = fs.readdirSync(directory, { recursive: true, withFileTypes: true });
  const forbidden = entries.filter((entry) =>
    entry.isFile() && (/^libQnn.*\.so$/i.test(entry.name) || /^qnn-runtime-.*\.aar$/i.test(entry.name))
  );
  if (forbidden.length) {
    throw new Error(
      "Qualcomm QNN binaries must come from the official Maven dependency and must not be committed standalone"
    );
  }
}

const jar = findJar();
const listed = new Set(
  run(jar, ["tf", apk])
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .filter(Boolean)
);
const missing = requiredLibraries.filter((library) => !listed.has(`${abiRoot}/${library}`));
if (missing.length) {
  throw new Error(`APK is missing required QNN libraries:\n${missing.map((name) => `- ${name}`).join("\n")}`);
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-qnn-package-"));
try {
  run(jar, ["xf", apk, "lib"], { cwd: temporary });
  const sizes = requiredLibraries.map((library) => ({
    library,
    bytes: fs.statSync(path.join(temporary, abiRoot, library)).size
  }));
  const totalBytes = sizes.reduce((sum, item) => sum + item.bytes, 0);
  console.log(
    `Android QNN package audit passed: ${sizes.length} libraries, ${formatMiB(totalBytes)} MiB uncompressed.`
  );
  for (const item of sizes) {
    console.log(`- ${item.library}: ${formatMiB(item.bytes)} MiB`);
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

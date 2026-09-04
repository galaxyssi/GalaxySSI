#!/usr/bin/env node
"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const apk = path.resolve(
  process.argv[2] || path.join(root, "apps", "android", "app", "build", "outputs", "apk", "debug", "app-debug.apk")
);
const isWindows = process.platform === "win32";
const sdkRoot = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT ||
  (isWindows ? path.join(process.env.LOCALAPPDATA || "", "Android", "Sdk") : "");
const requiredAlignment = 16 * 1024;

function numericVersionSort(left, right) {
  return right.localeCompare(left, undefined, { numeric: true, sensitivity: "base" });
}

function latestExecutable(parent, relativeExecutable) {
  if (!parent || !fs.existsSync(parent)) return null;
  for (const version of fs.readdirSync(parent).sort(numericVersionSort)) {
    const candidate = path.join(parent, version, relativeExecutable);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function run(command, args, options = {}) {
  const result = childProcess.spawnSync(command, args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
    shell: false,
    ...options
  });
  if (result.error || result.status) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`${path.basename(command)} failed${detail ? `:\n${detail}` : ""}`);
  }
  return result.stdout || "";
}

function walk(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(full));
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

if (!fs.existsSync(apk)) throw new Error(`APK does not exist: ${apk}`);

const prebuilt = isWindows ? "windows-x86_64" : process.platform === "darwin" ? "darwin-x86_64" : "linux-x86_64";
const readelfName = isWindows ? "llvm-readelf.exe" : "llvm-readelf";
const readelf = latestExecutable(
  path.join(sdkRoot, "ndk"),
  path.join("toolchains", "llvm", "prebuilt", prebuilt, "bin", readelfName)
);
const zipalign = latestExecutable(
  path.join(sdkRoot, "build-tools"),
  isWindows ? "zipalign.exe" : "zipalign"
);
if (!readelf) throw new Error("Android NDK llvm-readelf was not found");
if (!zipalign) throw new Error("Android build-tools zipalign was not found");

run(zipalign, ["-c", "-P", "16", "4", apk], { stdio: "pipe" });

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-android-elf-"));
try {
  const jar = process.env.JAVA_HOME
    ? path.join(process.env.JAVA_HOME, "bin", isWindows ? "jar.exe" : "jar")
    : "jar";
  run(jar, ["xf", apk, "lib"], { cwd: temporary });
  const libRoot = path.join(temporary, "lib");
  const libraries = fs.existsSync(libRoot)
    ? walk(libRoot).filter((file) => file.endsWith(".so"))
    : [];
  if (!libraries.length) throw new Error("APK contains no native libraries to audit");

  const failures = [];
  let androidLibraries = 0;
  for (const library of libraries) {
    const header = run(readelf, ["-h", library]);
    if (!/^\s*Machine:\s*AArch64\s*$/im.test(header)) continue;
    androidLibraries += 1;
    const output = run(readelf, ["-lW", library]);
    const loadLines = output.split(/\r?\n/).filter((line) => /^\s*LOAD\s+/.test(line));
    const alignments = loadLines.map((line) => {
      const match = /(0x[0-9a-f]+)\s*$/i.exec(line);
      return match ? Number.parseInt(match[1], 16) : 0;
    });
    if (!alignments.length || alignments.some((alignment) => alignment < requiredAlignment)) {
      failures.push({
        file: path.relative(temporary, library).replace(/\\/g, "/"),
        alignments
      });
    }
  }

  if (failures.length) {
    const detail = failures.map(({ file, alignments }) =>
      `- ${file}: ${alignments.map((value) => `0x${value.toString(16)}`).join(", ") || "no LOAD segments"}`
    ).join("\n");
    throw new Error(`APK contains native libraries below 16 KB ELF alignment:\n${detail}`);
  }
  console.log(`Android 16 KB audit passed for ${androidLibraries} Android AArch64 libraries.`);
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

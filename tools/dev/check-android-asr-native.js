#!/usr/bin/env node
"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const sourceDir = path.join(root, "apps", "android", "app", "src", "test", "cpp");
const buildDir = path.join(root, "apps", "android", "app", "build", "native-asr-host-tests");
const isWindows = process.platform === "win32";
const executableSuffix = isWindows ? ".exe" : "";

function findOnPath(names, env = process.env) {
  const directories = (env.PATH || "").split(path.delimiter).filter(Boolean);
  for (const directory of directories) {
    for (const name of names) {
      const candidate = path.join(directory, name);
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return null;
}

function findVersionedExecutable(parent, executable) {
  if (!parent || !fs.existsSync(parent)) return null;
  const versions = fs.readdirSync(parent).sort((left, right) =>
    right.localeCompare(left, undefined, { numeric: true, sensitivity: "base" })
  );
  for (const version of versions) {
    const candidate = path.join(parent, version, "bin", executable);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].map((part) => JSON.stringify(part)).join(" ")}`);
  const result = childProcess.spawnSync(command, args, {
    cwd: root,
    env: process.env,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
    shell: false,
    ...options
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status) process.exit(result.status);
}

if (!fs.existsSync(path.join(sourceDir, "CMakeLists.txt"))) {
  throw new Error(`Native ASR test project is missing: ${sourceDir}`);
}

const sdkRoot = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT ||
  (isWindows ? path.join(process.env.LOCALAPPDATA || "", "Android", "Sdk") : "");
const cmake = findOnPath([`cmake${executableSuffix}`]) ||
  findVersionedExecutable(path.join(sdkRoot, "cmake"), `cmake${executableSuffix}`) ||
  (isWindows ? findOnPath(["cmake.exe"], { ...process.env, PATH: "C:\\Program Files\\CMake\\bin" }) : null);
if (!cmake) throw new Error("CMake is required to run Android ASR host tests");

const ctest = path.join(path.dirname(cmake), `ctest${executableSuffix}`);
if (!fs.existsSync(ctest)) throw new Error(`CTest was not found beside CMake: ${ctest}`);

const environment = { ...process.env };
const configureArgs = ["-S", sourceDir, "-B", buildDir, "-DCMAKE_BUILD_TYPE=Release"];
const ninjaName = `ninja${executableSuffix}`;
const ninja = findOnPath([ninjaName], environment) ||
  [path.join(path.dirname(cmake), ninjaName), findVersionedExecutable(path.join(sdkRoot, "cmake"), ninjaName)]
    .find((candidate) => candidate && fs.existsSync(candidate));
if (ninja) configureArgs.push("-G", "Ninja", `-DCMAKE_MAKE_PROGRAM=${ninja}`);

if (isWindows) {
  const compilerCandidates = [
    environment.CXX,
    "C:\\msys64\\mingw64\\bin\\g++.exe",
    "C:\\msys64\\ucrt64\\bin\\g++.exe"
  ].filter(Boolean);
  const compiler = compilerCandidates.find((candidate) => fs.existsSync(candidate));
  if (!compiler) throw new Error("A Windows C++17 compiler is required to run Android ASR host tests");
  environment.PATH = `${path.dirname(compiler)}${path.delimiter}${environment.PATH || ""}`;
  configureArgs.push(`-DCMAKE_CXX_COMPILER=${compiler}`);
}

fs.rmSync(buildDir, { recursive: true, force: true });
run(cmake, configureArgs, { env: environment });
run(cmake, ["--build", buildDir, "--config", "Release", "--parallel"], { env: environment });
run(ctest, ["--test-dir", buildDir, "--build-config", "Release", "--output-on-failure"], {
  env: environment
});

console.log("Android ASR native host tests passed.");

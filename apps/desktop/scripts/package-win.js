const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { acquireGalaxySSILock } = require("./smoke-lock");

const root = path.resolve(__dirname, "..");
const packageMetadata = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const workspaceRoot = path.resolve(root, "..");
const electronDistCandidates = [
  path.join(root, ".electron-runtime", "node_modules", "electron", "dist"),
  path.join(root, "node_modules", "electron", "dist")
];
const electronDist = electronDistCandidates.find((candidate) => (
  fs.existsSync(path.join(candidate, "electron.exe"))
)) || electronDistCandidates[0];
const backendSrc = path.join(root, "core", "galaxyssi-link", "backend");
const outRoot = path.join(root, "dist");
const appName = "GalaxySSI Desktop";
const packageDir = path.join(outRoot, `${appName}-win-x64`);
const resourcesDir = path.join(packageDir, "resources");
const appDir = path.join(resourcesDir, "app");
const packagedBackendDir = path.join(resourcesDir, "galaxyssi-link", "backend");
const bundledPythonDir = path.join(resourcesDir, "python", "venv");
const runtimePythonDir = path.join(root, ".runtime-python", "venv");
const bundlePython = process.argv.includes("--bundle-python") || process.env.GALAXYSSI_BUNDLE_PYTHON === "1";
const releaseLock = acquireGalaxySSILock(bundlePython ? "package:win:python" : "package:win");
const sidecarDir = path.join(backendSrc, "signal_sidecar");
const sidecarRuntimeName = "galaxyssi-link-sidecar";
const sidecarRuntimeDir = path.join(sidecarDir, "build", "install", sidecarRuntimeName);
const backendDataEntries = ["web_source_sites.tsv"];

process.on("exit", releaseLock);

const backendEntries = [
  ...fs.readdirSync(backendSrc, { withFileTypes: true })
    .filter((entry) => (
      entry.isFile() && entry.name.endsWith(".py") && !entry.name.startsWith("test_")
    ) || (
      entry.isDirectory()
      && !entry.name.startsWith("test_")
      && fs.existsSync(path.join(backendSrc, entry.name, "__init__.py"))
    ))
    .map((entry) => entry.name)
    .sort(),
  ...backendDataEntries,
  "requirements.txt"
];

function copyRecursive(src, dest, options = {}) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      if (options.ignore?.(path.join(src, entry), entry)) continue;
      copyRecursive(path.join(src, entry), path.join(dest, entry), options);
    }
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function removeIfExists(target) {
  const retryable = new Set(["EBUSY", "ENOTEMPTY", "EPERM"]);
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      fs.rmSync(target, { recursive: true, force: true });
      return;
    } catch (error) {
      if (!retryable.has(error.code) || attempt === 19) throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
    }
  }
}

function stopPackagedProcesses() {
  if (process.platform !== "win32" || !fs.existsSync(packageDir)) return;
  const escapedPackageDir = packageDir.replace(/'/g, "''");
  const script = `
    $target = '${escapedPackageDir}'
    $names = @('GalaxySSI Desktop.exe', 'python.exe', 'pythonw.exe', 'java.exe', 'cmd.exe')
    $stopped = [System.Collections.Generic.HashSet[int]]::new()
    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
      $processes = @(Get-CimInstance Win32_Process | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath -like "$target*") -or
        ($_.Name -in $names -and $_.CommandLine -and $_.CommandLine -like "*$target*")
      })
      if ($processes.Count -eq 0) { break }
      foreach ($process in $processes) {
        [void]$stopped.Add([int]$process.ProcessId)
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
      }
      Start-Sleep -Milliseconds 500
    }
    $remaining = @(Get-CimInstance Win32_Process | Where-Object {
      ($_.ExecutablePath -and $_.ExecutablePath -like "$target*") -or
      ($_.Name -in $names -and $_.CommandLine -and $_.CommandLine -like "*$target*")
    })
    if ($remaining.Count -gt 0) {
      Write-Error "Packaged GalaxySSI process tree did not stop: $($remaining.ProcessId -join ',')"
      exit 1
    }
    if ($stopped.Count -gt 0) { Write-Output ((@($stopped) | Sort-Object) -join ',') }
  `;
  const stopped = execFileSync(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", script],
    { encoding: "utf8", windowsHide: true }
  ).trim();
  if (stopped) {
    console.log(`Stopped packaged GalaxySSI Desktop process tree: ${stopped}`);
  }
}

function writeJson(target, data) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

function requirePath(target, label) {
  if (!fs.existsSync(target)) {
    throw new Error(`${label} not found: ${target}`);
  }
}

function run(command, args, options = {}) {
  execFileSync(command, args, {
    cwd: options.cwd || root,
    stdio: options.stdio || "inherit",
    windowsHide: true
  });
}

function findRceditExecutable() {
  const candidates = [
    process.env.RCEDIT_EXE,
    path.join(root, "node_modules", "rcedit", "bin", "rcedit.exe"),
    path.join(root, ".electron-runtime", "node_modules", "rcedit", "bin", "rcedit.exe")
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function findPythonExecutable() {
  const candidates = [
    process.env.GALAXYSSI_PYTHON,
    "python",
    path.join(os.homedir(), "AppData", "Local", "hermes", "hermes-agent", "venv", "Scripts", "python.exe"),
    path.join(os.homedir(), "AppData", "Roaming", "uv", "python", "cpython-3.11-windows-x86_64-none", "python.exe")
  ].filter(Boolean);
  return candidates.find((candidate) => candidate === "python" || fs.existsSync(candidate));
}

function findGradleCommand() {
  const wrapper = path.join(workspaceRoot, "android", process.platform === "win32" ? "gradlew.bat" : "gradlew");
  if (fs.existsSync(wrapper)) return wrapper;
  return process.platform === "win32" ? "gradle.bat" : "gradle";
}

function runGradle(args, options = {}) {
  const gradle = findGradleCommand();
  if (process.platform === "win32") {
    run(process.env.ComSpec || "cmd.exe", ["/d", "/c", "call", gradle, ...args], options);
    return;
  }
  run(gradle, args, options);
}

function ensureSignalSidecarRuntime() {
  console.log("Synchronizing GalaxySSI Link sidecar runtime...");
  runGradle(["-p", sidecarDir, "installDist", "--no-daemon"], { cwd: workspaceRoot });
}

function pythonCanImportBackendDeps(pythonExe) {
  try {
    execFileSync(
      pythonExe,
      ["-c", "import fastapi, json5, multipart, uvicorn, sqlalchemy, websockets, paho.mqtt.client, qrcode, yaml; print('backend deps ok')"],
      { stdio: "ignore", windowsHide: true }
    );
    return true;
  } catch {
    return false;
  }
}

function ensureRuntimePythonVenv() {
  if (process.env.GALAXYSSI_PYTHON_VENV) {
    return process.env.GALAXYSSI_PYTHON_VENV;
  }

  const runtimePython = path.join(runtimePythonDir, "Scripts", "python.exe");
  if (!fs.existsSync(runtimePython)) {
    const seedPython = findPythonExecutable();
    if (!seedPython) {
      throw new Error("Python not found. Set GALAXYSSI_PYTHON or install Python 3.");
    }
    console.log(`Creating slim backend Python venv with ${seedPython}...`);
    run(seedPython, ["-m", "venv", runtimePythonDir]);
  }

  if (!pythonCanImportBackendDeps(runtimePython)) {
    console.log("Installing backend dependencies into slim Python venv...");
    run(runtimePython, ["-m", "pip", "install", "--upgrade", "pip"]);
    run(runtimePython, ["-m", "pip", "install", "-r", path.join(backendSrc, "requirements.txt")]);
  }

  return runtimePythonDir;
}

requirePath(path.join(electronDist, "electron.exe"), "Electron runtime executable");
requirePath(backendSrc, "GalaxySSI backend");
ensureSignalSidecarRuntime();
requirePath(sidecarRuntimeDir, "GalaxySSI Link sidecar runtime");

stopPackagedProcesses();
removeIfExists(packageDir);
fs.mkdirSync(packageDir, { recursive: true });

copyRecursive(electronDist, packageDir, {
  ignore: (_full, entry) => entry === "default_app.asar"
});

const electronExe = path.join(packageDir, "electron.exe");
const signalExe = path.join(packageDir, `${appName}.exe`);
if (fs.existsSync(electronExe)) {
  fs.renameSync(electronExe, signalExe);
}
requirePath(signalExe, "Packaged GalaxySSI executable");

copyRecursive(path.join(root, "src"), path.join(appDir, "src"));
copyRecursive(path.join(root, "assets"), path.join(appDir, "assets"));
copyRecursive(path.join(root, "scripts"), path.join(appDir, "scripts"), {
  ignore: (_full, entry) => entry === "package-win.js"
});
copyRecursive(path.join(root, "docs"), path.join(appDir, "docs"));
writeJson(path.join(appDir, "package.json"), {
  name: "galaxyssi-desktop",
  version: packageMetadata.version,
  main: "src/main.js",
  private: true,
  scripts: {
    check: "node scripts/check.js",
    "status:connectors": "node scripts/connector-status.js",
    "smoke:pairing": "node scripts/smoke-pairing.js",
    "smoke:ui": "node scripts/smoke-ui.js",
    "smoke:android-ui": "node scripts/smoke-android-ui.js",
    "smoke:android-friends": "node scripts/smoke-android-friends.js",
    "smoke:android-contact-rename": "node scripts/smoke-android-contact-rename.js",
    "smoke:android-contact-tags": "node scripts/smoke-android-contact-tags.js",
    "smoke:android-language": "node scripts/smoke-android-language.js",
    "smoke:android-cloud-models": "node scripts/smoke-android-cloud-models.js",
    "smoke:android-background": "node scripts/smoke-android-background-message.js",
    "smoke:android-agent-replies": "node scripts/smoke-android-agent-replies.js",
    "smoke:android-backup": "node scripts/smoke-android-backup-roundtrip.js",
    "smoke:android-voice-reply": "node scripts/smoke-android-voice-reply.js",
    "smoke:android-voice-settings": "node scripts/smoke-android-voice-settings.js",
    "smoke:mqtt-persistence": "node scripts/smoke-mqtt-persistence.js",
    "smoke:agent-push": "node scripts/smoke-agent-push.js",
    "smoke:voice-stt": "node scripts/smoke-voice-stt.js",
    "smoke:e2e": "node scripts/smoke-e2e.js",
    "smoke:packaged": "node scripts/smoke-packaged.js",
    smoke: "node scripts/smoke.js"
  }
});

for (const entry of backendEntries) {
  copyRecursive(path.join(backendSrc, entry), path.join(packagedBackendDir, entry), {
    ignore: (_full, name) => name === "__pycache__" || name.endsWith(".pyc")
  });
}
copyRecursive(
  sidecarRuntimeDir,
  path.join(packagedBackendDir, "signal_sidecar", "build", "install", sidecarRuntimeName)
);

if (bundlePython) {
  const pythonVenvSrc = ensureRuntimePythonVenv();
  requirePath(pythonVenvSrc || "", "Bundled Python source venv");
  copyRecursive(pythonVenvSrc, bundledPythonDir, {
    ignore: (_full, entry) => entry === "__pycache__" || entry === ".pytest_cache" || entry.endsWith(".pyc")
  });
}

const iconPath = path.join(root, "assets", "galaxyssi.ico");
const rcedit = findRceditExecutable();
if (rcedit) {
  try {
    const versionParts = String(packageMetadata.version || "0.0.0").split(".");
    const fileVersion = [...versionParts, "0", "0", "0", "0"].slice(0, 4).join(".");
    const resourceArgs = [
      signalExe,
      "--set-file-version", fileVersion,
      "--set-product-version", String(packageMetadata.version || "0.0.0"),
      "--set-version-string", "ProductName", "GalaxySSI Desktop",
      "--set-version-string", "FileDescription", "GalaxySSI Desktop super agent and mobile gateway",
      "--set-version-string", "CompanyName", "GalaxySSI",
      "--set-version-string", "OriginalFilename", `${appName}.exe`,
      "--set-version-string", "LegalCopyright", "Copyright GalaxySSI contributors"
    ];
    if (fs.existsSync(iconPath)) resourceArgs.push("--set-icon", iconPath);
    run(rcedit, resourceArgs);
  } catch (error) {
    console.warn(`Unable to embed GalaxySSI executable resources: ${error.message}`);
  }
} else {
  console.warn("rcedit not found; packaged exe will keep the Electron file resources.");
}

fs.writeFileSync(
  path.join(packageDir, "install-backend-deps.bat"),
  [
    "@echo off",
    "setlocal",
    "cd /d %~dp0",
    "set PYTHON_EXE=%~dp0resources\\python\\venv\\Scripts\\python.exe",
    "if not exist \"%PYTHON_EXE%\" set PYTHON_EXE=python",
    "echo Installing GalaxySSI backend Python dependencies...",
    "\"%PYTHON_EXE%\" -m pip install -r resources\\galaxyssi-link\\backend\\requirements.txt",
    "if errorlevel 1 (",
    "  echo.",
    "  echo Failed to install backend dependencies. Install Python 3 and pip, then run this file again.",
    "  pause",
    "  exit /b 1",
    ")",
    "echo.",
    "echo Backend dependencies installed.",
    "pause",
    "endlocal"
  ].join("\r\n"),
  "utf8"
);

fs.writeFileSync(
  path.join(packageDir, "galaxyssi-notify.bat"),
  [
    "@echo off",
    "setlocal",
    "cd /d %~dp0resources\\galaxyssi-link\\backend",
    "set PYTHON_EXE=%~dp0resources\\python\\venv\\Scripts\\python.exe",
    "if not exist \"%PYTHON_EXE%\" set PYTHON_EXE=python",
    "\"%PYTHON_EXE%\" galaxyssi_notify.py %*",
    "exit /b %errorlevel%"
  ].join("\r\n"),
  "utf8"
);

fs.writeFileSync(
  path.join(packageDir, "README.txt"),
  [
    "GalaxySSI Desktop portable package",
    "",
    `Run \"${appName}.exe\" to start the desktop connector.`,
    "The mobile pairing route is /galaxyssi/verify.",
    "Agents can push messages with galaxyssi-notify.bat codex \"Task complete\".",
    "This package includes the Python backend source and the built Signal sidecar runtime.",
    bundlePython
      ? "This package includes a bundled Python venv for the FastAPI backend."
      : "A local Python 3 installation is still required to run the FastAPI backend.",
    "If the Runtime requirements panel reports missing Python packages, run install-backend-deps.bat.",
    ""
  ].join("\r\n"),
  "utf8"
);

console.log(`Packaged ${appName} at ${packageDir}`);
console.log(`Bundled Python: ${bundlePython ? "yes" : "no"}`);
releaseLock();

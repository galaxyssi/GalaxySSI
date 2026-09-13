const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function resourceMetadata(version) {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.exec(version);
  if (!match || match.slice(1, 4).some((part) => Number(part) > 65535)) {
    throw new Error("Desktop version must fit a three-part Windows file version");
  }
  return {
    FileVersion: `${match.slice(1, 4).join(".")}.0`,
    ProductVersion: version,
    ProductName: "GalaxySSI Desktop",
    FileDescription: "GalaxySSI Desktop super agent and mobile gateway",
    CompanyName: "GalaxySSI",
    OriginalFilename: "GalaxySSI Desktop.exe",
    LegalCopyright: "Copyright GalaxySSI contributors"
  };
}

function findResourceTool(root, override = process.env.RCEDIT_EXE,
  exists = (candidate) => fs.statSync(candidate, { throwIfNoEntry: false })?.isFile() === true) {
  const candidates = override ? [path.resolve(override)] : [
    path.join(root, "node_modules", "rcedit", "bin", "rcedit-x64.exe"),
    path.join(root, "node_modules", "rcedit", "bin", "rcedit.exe"),
    path.join(root, ".electron-runtime", "node_modules", "rcedit", "bin", "rcedit-x64.exe"),
    path.join(root, ".electron-runtime", "node_modules", "rcedit", "bin", "rcedit.exe")
  ];
  const found = candidates.find(exists);
  if (!found) throw new Error("rcedit is required: install Desktop dev dependencies or set RCEDIT_EXE to its executable");
  return found;
}

function resourceArguments(executable, metadata, icon) {
  const args = [executable, "--set-file-version", metadata.FileVersion,
    "--set-product-version", metadata.ProductVersion];
  for (const [name, value] of Object.entries(metadata)) {
    if (name !== "FileVersion" && name !== "ProductVersion") args.push("--set-version-string", name, value);
  }
  if (icon) args.push("--set-icon", icon);
  return args;
}

function verifyResourceMetadata(actual, expected) {
  for (const [name, value] of Object.entries(expected)) {
    if (actual[name] !== value) throw new Error(`Packaged executable resource mismatch: ${name}`);
  }
}

function applyExecutableResources(tool, executable, metadata, icon, run = execFileSync) {
  run(tool, resourceArguments(executable, metadata, icon), { windowsHide: true, stdio: "pipe" });
  const query = "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); "
    + "(Get-Item -LiteralPath $env:GALAXYSSI_RESOURCE_EXE).VersionInfo | "
    + "Select-Object FileVersion,ProductVersion,ProductName,FileDescription,CompanyName,OriginalFilename,LegalCopyright | ConvertTo-Json -Compress";
  const result = run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", query],
    { windowsHide: true, encoding: "utf8", env: { ...process.env, GALAXYSSI_RESOURCE_EXE: path.resolve(executable) } });
  const actual = JSON.parse(result.replace(/^\uFEFF/, ""));
  verifyResourceMetadata(actual, metadata);
  return actual;
}

module.exports = { resourceMetadata, findResourceTool, resourceArguments, verifyResourceMetadata, applyExecutableResources };

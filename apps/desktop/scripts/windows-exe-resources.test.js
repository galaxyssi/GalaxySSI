const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { resourceMetadata, findResourceTool, resourceArguments, verifyResourceMetadata,
  applyExecutableResources } = require("./windows-exe-resources");

test("release resources derive from the package version, not Electron", () => {
  const metadata = resourceMetadata("1.2.0");
  assert.equal(metadata.FileVersion, "1.2.0.0");
  assert.equal(metadata.ProductVersion, "1.2.0");
  assert.equal(metadata.OriginalFilename, "GalaxySSI Desktop.exe");
  assert.equal(metadata.ProductName, "GalaxySSI Desktop");
  for (const value of [undefined, "", "1.2", "1.2.0.4", "65536.2.0", "01.2.0", "1.2.0\n"]) {
    assert.throws(() => resourceMetadata(value));
  }
});

test("resource tool lookup covers both installed layouts and architectures", () => {
  const root = path.resolve("owned test root");
  for (const prefix of ["node_modules", ".electron-runtime/node_modules"]) {
    for (const binary of ["rcedit.exe", "rcedit-x64.exe"]) {
      const candidate = path.join(root, prefix, "rcedit", "bin", binary);
      assert.equal(findResourceTool(root, null, (value) => value === candidate), candidate);
    }
  }
  assert.throws(() => findResourceTool(root, null, () => false), /rcedit is required/);
  assert.throws(() => findResourceTool(root, __dirname), /rcedit is required/);
});

test("an explicit missing override cannot silently use a different tool", () => {
  const root = path.resolve("owned test root");
  assert.throws(() => findResourceTool(root, "missing.exe", (value) => value.includes("node_modules")));
  assert.equal(findResourceTool(root, "owned.exe", () => true), path.resolve("owned.exe"));
});

test("paths are passed as literal executable arguments, with optional icon", () => {
  const args = resourceArguments("C:/owned's folder/GalaxySSI Desktop.exe", resourceMetadata("1.2.0"), "C:/icon file.ico");
  assert.equal(args[0], "C:/owned's folder/GalaxySSI Desktop.exe");
  assert.deepEqual(args.slice(-2), ["--set-icon", "C:/icon file.ico"]);
  assert.ok(!resourceArguments("owned.exe", resourceMetadata("1.2.0")).includes("--set-icon"));
});

test("writing resources requires a matching independent version readback", () => {
  const metadata = resourceMetadata("1.2.0");
  const calls = [];
  const result = applyExecutableResources("tool.exe", "owned.exe", metadata, undefined, (...args) => {
    calls.push(args);
    return calls.length === 1 ? "" : `\uFEFF${JSON.stringify(metadata)}`;
  });
  assert.deepEqual(result, metadata);
  assert.equal(calls[1][0], "powershell.exe");
  assert.equal(calls[1][2].env.GALAXYSSI_RESOURCE_EXE, path.resolve("owned.exe"));
  assert.ok(!calls[1][1].at(-1).includes(path.resolve("owned.exe")));
  assert.ok(!calls[1][1].includes("-ExecutionPolicy"));
  assert.equal(calls[0][2].windowsHide, true);
  assert.equal(calls[1][2].windowsHide, true);
});

test("resource failures and stale Electron values fail packaging", () => {
  const metadata = resourceMetadata("1.2.0");
  assert.throws(() => applyExecutableResources("tool", "owned", metadata, undefined, () => { throw new Error("write failed"); }), /write failed/);
  for (const key of Object.keys(metadata)) {
    assert.throws(() => verifyResourceMetadata({ ...metadata, [key]: "old" }, metadata), new RegExp(key));
  }
  let calls = 0;
  assert.throws(() => applyExecutableResources("tool", "owned", metadata, undefined, () => ++calls === 1 ? "" : "not JSON"));
});

test("package preflight resolves tool and version before stopping an installed app", () => {
  const source = fs.readFileSync(path.join(__dirname, "package-win.js"), "utf8");
  const stop = source.indexOf("stopPackagedProcesses();");
  const version = source.indexOf("resourceMetadata(packageMetadata.version)");
  const tool = source.indexOf("findResourceTool(root)");
  const apply = source.indexOf("applyExecutableResources(rcedit,");
  assert.ok(stop >= 0 && version >= 0 && version < stop);
  assert.ok(tool >= 0 && tool < stop);
  assert.ok(apply >= 0 && apply < source.indexOf("console.log(`Packaged"));
  assert.ok(!source.includes("will keep the Electron file resources"));
});

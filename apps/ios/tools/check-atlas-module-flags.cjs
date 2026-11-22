// Static Xcode-setting composition audit; does not invoke Xcode or execute tests.
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const projectPath = "apps/ios/GalaxySSI.xcodeproj/project.pbxproj";
function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0) return null;
  assert.ok(process.argv[index + 1], "Missing value for " + name);
  return process.argv[index + 1];
}
function project(ref) {
  return ref ? cp.execFileSync("git", ["show", ref + ":" + projectPath], { cwd: root, encoding: "utf8" }) :
    fs.readFileSync(path.join(root, projectPath), "utf8");
}
function block(source, id) {
  const start = source.indexOf("AA000000000000000000000" + id + " /*");
  assert.ok(start >= 0, "Missing build configuration " + id);
  const end = source.indexOf("      name =", start);
  assert.ok(end > start);
  return source.slice(start, end);
}
function quoted(source, key) {
  const match = source.match(new RegExp("^        " + key + " = (\".*\");$", "m"));
  assert.ok(match, "Missing " + key + "; supply prerequisite refs on an independent branch.");
  return JSON.parse(match[1]);
}
const foundation = project(argument("--foundation-ref"));
const modules = {
  GALAXYSSI_ATLAS_PHYSIOLOGY_FLAGS: project(argument("--physiology-ref")),
  GALAXYSSI_ATLAS_AGENT_CONTEXT_FLAGS: project(argument("--context-ref")),
  GALAXYSSI_ATLAS_OXYGEN_FLAGS: project(argument("--oxygen-ref"))
};
for (const id of [1, 2]) {
  const expression = quoted(block(foundation, id), "OTHER_SWIFT_FLAGS");
  assert.ok(expression.startsWith("$(inherited)"));
  const definitions = Object.fromEntries(Object.entries(modules).map(([key, source]) => [key, quoted(block(source, id), key)]));
  const keys = Object.keys(definitions);
  for (const key of keys) assert.equal(definitions[key], "-D " + key.replace(/_FLAGS$/, ""));
  for (let mask = 0; mask < 8; mask++) {
    const flags = expression.replace(/\$\(([^)]+)\)/g, (_, key) => {
      const index = keys.indexOf(key);
      return index >= 0 && (mask & (1 << index)) ? definitions[key] : "";
    });
    for (let index = 0; index < keys.length; index++) {
      assert.equal(flags.includes(keys[index].replace(/_FLAGS$/, "")), Boolean(mask & (1 << index)));
    }
  }
}
// Target-local values would either hide project inheritance or leave test conditions different from the app.
for (const source of [foundation, ...Object.values(modules)]) {
  for (const id of [3, 4, 5, 6]) assert.ok(!block(source, id).includes("OTHER_SWIFT_FLAGS ="), "Unexpected target override: " + id);
}
const workflow = fs.readFileSync(path.join(root, ".github/workflows/ios-adhoc-ipa.yml"), "utf8");
assert.ok(workflow.includes("SWIFT_ACTIVE_COMPILATION_CONDITIONS=$SWIFT_COMPILATION_CONDITIONS"));
assert.ok(!workflow.includes("OTHER_SWIFT_FLAGS="), "Reaudit the workflow's flag override.");
console.log("Atlas module settings audit passed: project Debug/Release, 8 module subsets, app/test inheritance and current IPA override boundary. Not an Xcode build.");

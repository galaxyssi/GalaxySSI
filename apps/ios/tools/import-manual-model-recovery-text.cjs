// Deterministic original Android #4438 label import, not app execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const assert = require("node:assert/strict"), root = path.resolve(__dirname, "../../..");
const sha = "bf8bb0b2a00930e707c333631dab86124eca0efc", key = "agent_manual_desktop_timeout";
const git = args => cp.execFileSync("git", args, {cwd: root, encoding: "utf8", maxBuffer: 16_000_000});
function content(element) {
  return (element.elements ?? []).map(e => e.type === "text" || e.type === "cdata" ? e.text ?? e.cdata : e.type === "element" ? content(e) : "").join("");
}
function strings(revision, file) {
  const root = xml.xml2js(git(["show", revision + ":" + file]), {compact: false}).elements.find(e => e.name === "resources");
  return new Map(root.elements.filter(e => e.name === "string").map(e => [e.attributes.name, content(e)]));
}
for (const [directory, locale] of [["values", "en"], ["values-zh-rCN", "zh-Hans"]]) {
  const file = "apps/android/app/src/main/res/" + directory + "/strings.xml";
  const previous = strings(sha + "^1", file), current = strings(sha, file);
  const changed = [...current].filter(([name, value]) => previous.get(name) !== value);
  assert.equal(changed.length, 1); assert.equal(changed[0][0], key);
  const value = changed[0][1].replace(/\\'/g, "'").replace(/\\"/g, '"');
  const text = JSON.stringify(key) + " = " + JSON.stringify(value) + ";\n";
  const destination = path.join(root, "apps/ios/GalaxySSI/" + locale + ".lproj/AgentManualModelRecovery.strings");
  if (process.argv.includes("--check")) assert.equal(fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n"), text);
  else fs.writeFileSync(destination, text);
  if (locale === "en") assert(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/AgentManualModelRecoveryPolicy.swift"), "utf8").includes("englishMessage = " + JSON.stringify(value)));
  console.log(locale + ": one exact Android #4438 manual-timeout label; source-only reproduction.");
}

// Deterministic Android #4385 resource delta; does not execute the app.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const checking = process.argv.includes("--check");
const git = args => cp.execFileSync("git", args, {cwd: root, encoding: "utf8", maxBuffer: 16_000_000});
const files = git(["diff", "--name-status", sha + "^1", sha, "--", "apps/android/app/src/main/res/values", "apps/android/app/src/main/res/values-zh"])
  .trim().split(/\r?\n/).map(line => { const [status, file] = line.split("\t"); return {status, file}; });
function text(element) {
  return (element.elements || []).map(e => e.type === "text" || e.type === "cdata" ? e.text ?? e.cdata : e.type === "element" ? text(e) : "").join("");
}
function read(revision, file) {
  const resource = xml.xml2js(git(["show", revision + ":" + file]), {compact: false}).elements.find(e => e.name === "resources");
  return new Map((resource?.elements || []).filter(e => e.name === "string").map(e => [e.attributes.name, text(e)]));
}
const tables = new Map();
for (const [directory, language] of [["values", "en"], ["values-zh", "zh-Hans"]]) {
  const delta = new Map();
  for (const {status, file} of files.filter(f => f.file.includes("/" + directory + "/") && f.file.endsWith(".xml"))) {
    if (!["A", "M"].includes(status)) throw Error("Unexpected resource status " + status);
    const current = read(sha, file), previous = status === "A" ? new Map() : read(sha + "^1", file);
    for (const [key, value] of current) {
      if (value === previous.get(key)) continue;
      if (delta.has(key)) throw Error("Duplicate resource " + key);
      if (value.startsWith("@string/")) throw Error("Resolve alias explicitly: " + key);
      delta.set(key, value.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\\n/g, "\n")
        .replace(/%([0-9]+)\$s/g, "%$1$@").replace(/%([0-9]+)\$d/g, "%$1$lld"));
    }
  }
  tables.set(language, delta);
}
const keys = table => [...table.keys()].sort();
if (JSON.stringify(keys(tables.get("en"))) !== JSON.stringify(keys(tables.get("zh-Hans")))) throw Error("Regional bilingual key mismatch");
for (const [language, table] of tables) {
  const content = keys(table).map(key => JSON.stringify(key) + " = " + JSON.stringify(table.get(key)) + ";").join("\n") + "\n";
  const destination = path.join(root, "apps/ios/GalaxySSI", language + ".lproj/AtlasRegional.strings");
  if (checking) {
    if (fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n") !== content) throw Error("Regional resource drift: " + language);
  } else fs.writeFileSync(destination, content);
  console.log(language + ": " + table.size + " Android #4385 resource deltas, no cross-language fallback.");
}

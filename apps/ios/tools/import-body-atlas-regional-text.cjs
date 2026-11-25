// Deterministic Android #4385 resource delta; does not execute the app.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const exchange = process.argv.includes("--exchange-4410"), phase = process.argv.includes("--phase-4407"), transport = process.argv.includes("--transport-4405"), regional = process.argv.includes("--regional-4402"), organ = process.argv.includes("--organ-4401"), system = process.argv.includes("--system-4399"), teaching = process.argv.includes("--teaching-4397"), anatomy = process.argv.includes("--anatomy-4396"), expanded = process.argv.includes("--expanded-4391"), detail = process.argv.includes("--detail-4389"), complete = process.argv.includes("--complete-4388");
const revision = exchange ? 4410 : phase ? 4407 : transport ? 4405 : regional ? 4402 : organ ? 4401 : system ? 4399 : teaching ? 4397 : anatomy ? 4396 : expanded ? 4391 : detail ? 4389 : complete ? 4388 : 4385, tableName = exchange ? "AtlasExchangeTeaching" : phase ? "AtlasPhaseTeaching" : transport ? "AtlasTransportTeaching" : regional ? "AtlasRegionalTeaching" : organ ? "AtlasOrganTeaching" : system ? "AtlasSystemTeaching" : teaching ? "AtlasTeaching" : anatomy ? "AtlasAnatomy" : expanded ? "AtlasExpanded" : detail ? "AtlasDetail" : complete ? "AtlasComplete" : "AtlasRegional";
const root = path.resolve(__dirname, "../../.."), sha = exchange ? "e8ddebdcc70942880fcfeaacee57474c2d711b32" : phase ? "2b0a455e59948d31606010edf3ddba25d01c180f" : transport ? "82d853f1d3d9c7e3455e732771f876a911fd0ce7" : regional ? "0d0112b055947c3747c7910b255aa299587dfd75" : organ ? "e228e379f307fcd6c1eb93b289126e9c473ddf7e" : system ? "de05fd51ba151789acd24dc4484d7f84d893aea3" : teaching ? "40776e7a67ebfe48c76f98d392849edb9810ac82" : anatomy ? "dbd32a65c73e10d710372c44a7ffa8d1518d1f2c" : expanded ? "165809fc9606ac1ff6b0df6eb9bee73286b415ea" : detail ? "9508d49277cf33ab7f85e65722e7c470930fff7e" : complete ? "6581110ec5c048edebf63821dee839b4818fe663" : "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
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
  const destination = path.join(root, "apps/ios/GalaxySSI", language + ".lproj/" + tableName + ".strings");
  if (checking) {
    if (fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n") !== content) throw Error("Regional resource drift: " + language);
  } else fs.writeFileSync(destination, content);
  console.log(language + ": " + table.size + " Android #" + revision + " resource deltas, no cross-language fallback.");
}

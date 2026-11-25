// Deterministic Android #4385 resource delta; does not execute the app.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), xml = require("xml-js");
const pleural = process.argv.includes("--pleural-4412"), exchange = process.argv.includes("--exchange-4410"), phase = process.argv.includes("--phase-4407"), transport = process.argv.includes("--transport-4405"), regional = process.argv.includes("--regional-4402"), organ = process.argv.includes("--organ-4401"), system = process.argv.includes("--system-4399"), teaching = process.argv.includes("--teaching-4397"), anatomy = process.argv.includes("--anatomy-4396"), expanded = process.argv.includes("--expanded-4391"), detail = process.argv.includes("--detail-4389"), complete = process.argv.includes("--complete-4388");
const revision = pleural ? 4412 : exchange ? 4410 : phase ? 4407 : transport ? 4405 : regional ? 4402 : organ ? 4401 : system ? 4399 : teaching ? 4397 : anatomy ? 4396 : expanded ? 4391 : detail ? 4389 : complete ? 4388 : 4385, tableName = pleural ? "AtlasPleuralTeaching" : exchange ? "AtlasExchangeTeaching" : phase ? "AtlasPhaseTeaching" : transport ? "AtlasTransportTeaching" : regional ? "AtlasRegionalTeaching" : organ ? "AtlasOrganTeaching" : system ? "AtlasSystemTeaching" : teaching ? "AtlasTeaching" : anatomy ? "AtlasAnatomy" : expanded ? "AtlasExpanded" : detail ? "AtlasDetail" : complete ? "AtlasComplete" : "AtlasRegional";
const root = path.resolve(__dirname, "../../.."), sha = pleural ? "c704a171da9336535ab659d65e6c6af0a4ebd9ba" : exchange ? "e8ddebdcc70942880fcfeaacee57474c2d711b32" : phase ? "2b0a455e59948d31606010edf3ddba25d01c180f" : transport ? "82d853f1d3d9c7e3455e732771f876a911fd0ce7" : regional ? "0d0112b055947c3747c7910b255aa299587dfd75" : organ ? "e228e379f307fcd6c1eb93b289126e9c473ddf7e" : system ? "de05fd51ba151789acd24dc4484d7f84d893aea3" : teaching ? "40776e7a67ebfe48c76f98d392849edb9810ac82" : anatomy ? "dbd32a65c73e10d710372c44a7ffa8d1518d1f2c" : expanded ? "165809fc9606ac1ff6b0df6eb9bee73286b415ea" : detail ? "9508d49277cf33ab7f85e65722e7c470930fff7e" : complete ? "6581110ec5c048edebf63821dee839b4818fe663" : "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const completion = process.argv.includes("--completion-4414");
const wholeActions = process.argv.includes("--whole-actions-4417");
const readings = process.argv.includes("--related-readings-4418");
const comparison = process.argv.includes("--model-comparison-4434");
const guided = process.argv.includes("--guided-function-4435");
const cumulative = process.argv.includes("--cumulative-comparison-4436");
const research = process.argv.includes("--research-navigation-4437");
const scenes = process.argv.includes("--synchronized-lessons-4439");
const closeups = process.argv.includes("--mechanism-closeups-4440");
const sourceSHA = closeups ? "5fecc676dac71a5ef7128f6ec5893e69660b5746" : scenes ? "eef7fd41df84c075cbc0ba046cca6ab6a5b59bf7" : research ? "dbbd6554d7cd632c6eb99f705e5a4b38ff42a3cb" : cumulative ? "de63c7dd3c883b8724da0f4366d6e078c1882a75" : guided ? "83188e7ce30a174e766e68fcf4db6f751a046d7a" : comparison ? "3327febe8406fb5ee5cf30dc0734ef6c4e2cbdcc" : readings ? "115d6adeb661fd4357fea57517ca92d02ffe1f51" : wholeActions ? "071062afe8059506c9958906f708780d80437f55" : completion ? "7dd7f35525ed800b74a3439bf708b1793316de42" : sha;
const sourceRevision = closeups ? 4440 : scenes ? 4439 : research ? 4437 : cumulative ? 4436 : guided ? 4435 : comparison ? 4434 : readings ? 4418 : wholeActions ? 4417 : completion ? 4414 : revision;
const sourceTable = closeups ? "AtlasMechanismCloseups" : scenes ? "AtlasSynchronizedLessons" : research ? "AtlasResearchNavigation" : cumulative ? "AtlasCumulativeComparison" : guided ? "AtlasGuidedFunction" : comparison ? "AtlasModelComparison" : readings ? "AtlasRelatedReadings" : wholeActions ? "AtlasWholeActions" : completion ? "AtlasCompletionTeaching" : tableName;
const checking = process.argv.includes("--check");
const git = args => cp.execFileSync("git", args, {cwd: root, encoding: "utf8", maxBuffer: 16_000_000});
const files = git(["diff", "--name-status", sourceSHA + "^1", sourceSHA, "--", "apps/android/app/src/main/res/values", "apps/android/app/src/main/res/values-zh"])
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
    const current = read(sourceSHA, file), previous = status === "A" ? new Map() : read(sourceSHA + "^1", file);
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
  const destination = path.join(root, "apps/ios/GalaxySSI", language + ".lproj/" + sourceTable + ".strings");
  if (checking) {
    if (fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n") !== content) throw Error("Regional resource drift: " + language);
  } else fs.writeFileSync(destination, content);
  console.log(language + ": " + table.size + " Android #" + sourceRevision + " resource deltas, no cross-language fallback.");
}

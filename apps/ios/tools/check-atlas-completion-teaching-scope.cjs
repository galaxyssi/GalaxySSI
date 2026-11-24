// Pinned declarations and source wiring only; not Swift execution or UI acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "7dd7f35525ed800b74a3439bf708b1793316de42";
const read = file => fs.readFileSync(path.join(root, "apps/ios", file), "utf8").replace(/\r\n/g, "\n");
const source = name => read("GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift");
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 32_000_000});
const declarations = JSON.parse(read("ANDROID_4414_MODEL_DECLARATIONS.json"));
const inventory = JSON.parse(read("ANDROID_4414_SOURCE_INVENTORY.json"));
assert.deepEqual(declarations.source, {androidPR: 4414, mergeCommit: sha});
assert.deepEqual(inventory.source, declarations.source);
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 119); assert.equal(inventory.files.length, 119);
for (const [i, [status, file]] of changed.entries()) assert.deepEqual(inventory.files[i], {path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")});
const models = declarations.models, controls = models.flatMap(m => m.inputs), owners = models.flatMap(m => m.entryIDs);
assert.equal(models.length, 28); assert.equal(controls.length, 48); assert.equal(owners.length, 30);
assert.equal(new Set(controls.map(c => c.key)).size, 48); assert.equal(new Set(owners).size, 30);
const metadata = source("TeachingModel"), inputSource = source("TeachingControls"), values = source("TeachingValues"), physiology = source("Physiology");
const q = s => JSON.stringify(s).replace(/[^\x00-\x7f]/g, c => "\\u{" + c.charCodeAt(0).toString(16) + "}");
const normalize = s => s.replace(/\s+/g, "");
const body = (text, id) => [...text.matchAll(/case ([^:]+):([^]*?)(?=\n\s*(?:case |default:)|$)/g)]
  .find(m => [...m[1].matchAll(/\.(\w+)/g)].some(c => c[1] === id))?.[2];
const property = (name, next) => metadata.split("\n  var " + name + ":")[1]?.split("\n  var " + next + ":")[0];
const resourceKeys = new Set(["health_atlas_values", "health_atlas_open_quantitative_model"]);
for (const model of models) {
  const prefix = model.title.replace(/_title$/, "");
  const expect = (propertyName, next, text) => assert(normalize(body(property(propertyName, next), model.id)).startsWith(normalize(text)), model.id + ":" + propertyName);
  expect("axis", "unit", "return " + model.axis); expect("unit", "bounds", "return " + q(model.unit));
  expect("digits", "resourcePrefix", "return " + model.digits); expect("resourcePrefix", "title", "return " + q(prefix));
  if (model.id === "thyroidFollicularFaces") {
    assert.equal(model.maximum, 2 * Math.PI * 6 / 8); expect("bounds", "digits", "return 0...(2 * .pi * 6 / 8)");
  } else if (model.id === "urethralOpeningArea") {
    assert.equal(model.maximum, 16 * Math.PI); expect("bounds", "digits", "return 0...(16 * .pi)");
  } else expect("bounds", "digits", "return " + model.minimum + "..." + model.maximum);
  const companion = body(property("companionTitle", "entryIDs"), model.id)?.match(/suffix = "([^"]+)"/)?.[1] ?? "companion";
  assert.equal(model.companionTitle, prefix + "_" + companion);
  assert.deepEqual(new Set([...body(property("entryIDs", "sources"), model.id).matchAll(/"([^"]+)"/g)].map(m => m[1])), new Set(model.entryIDs));
  assert.deepEqual([...body(property("sources", "unused"), model.id).matchAll(/"(https:[^"]+)"/g)].map(m => m[1]), model.sources);
  for (const key of [model.title, model.scope, model.formula, model.companionTitle]) resourceKeys.add(key);
  for (const control of model.inputs) {
    assert(control.label.startsWith(prefix + "_")); resourceKeys.add(control.label);
    const expected = "control(" + [q(control.key), q(control.label.slice(prefix.length + 1)), control.minimum + "..." + control.maximum,
      control.initial, q(control.unit), ...(control.scale === 1 ? [] : ["scale: " + control.scale]), "digits: " + control.digits].join(", ") + ")";
    assert(normalize(body(inputSource, model.id)).includes(normalize(expected)), control.key);
  }
  assert.equal((physiology.match(new RegExp("\\bcase [^\\n]*\\b" + model.id + "\\b", "g")) || []).length, 1);
  for (const method of ["return teaching!.inputs", "return teaching!.sources[0]", "return kind.teaching!.evaluate(values)",
    "return kind.teaching!.companion(inputs.indices.map(input))"]) {
    const at = physiology.indexOf(method), prior = physiology.slice(0, at).lastIndexOf("case ");
    assert(at >= 0 && physiology.slice(prior, at).includes("." + model.id), model.id + ": delegation");
  }
}
const formulas = {
  accessoryGlandEntry: ["values[0].rounded() + values[1].rounded()", "values[2].rounded()"],
  aiiAmacrineRelay: ["values[0]", "0 - values[0]"],
  astrocyteRecycling: ["values[0] * values[1] / 100", "100 - values[0]"],
  cecalPouchMixing: ["values[1] / 2 * (1 - pow(0.5, values[0].rounded()))", "values[1] - values[1] / 2 * (1 - pow(0.5, values[0].rounded()))"],
  clitoralRouteTrace: ["100 * values[0].rounded() / 4", "4 - values[0].rounded()"],
  clubCellDome: ["let cap = .pi * values[0]\nresult = 100 * cap / (cap + 4 * values[1])", ".pi * values[0]"],
  dendriticCellOutline: ["12 + 2 * values[0].rounded()", "9 + values[0].rounded()"],
  enteroendocrinePolarity: ["100 * values[0] / values[1]", "values[1] - values[0]"],
  intestinalStemRenewal: ["min(12, values[0].rounded() * values[1].rounded())", "12 - min(12, values[0].rounded() * values[1].rounded())"],
  langerhansDendriteReach: ["min(10, values[0].rounded() + values[1].rounded())", "max(0, values[0].rounded() + values[1].rounded() - 10)"],
  macrophageClearanceTally: ["min(values[0].rounded(), values[1].rounded())", "values[0].rounded() - min(values[0].rounded(), values[1].rounded())"],
  mastCellGranuleTally: ["100 * values[0].rounded() / 20", "20 - values[0].rounded()"],
  microgliaSurveillance: ["2 * values[0].rounded() - max(0, values[0].rounded() - values[1].rounded())", "max(0, values[0].rounded() - values[1].rounded())"],
  muscleSatelliteFusionTally: ["values[1].rounded() + values[0].rounded()", "8 - values[0].rounded()"],
  nailPlateAdvance: ["values[0] * values[1]", "4 + values[0] * values[1]"],
  pancreaticAcinarApicalBand: ["let area = values[0] * (2 + (2 + 4 * values[0] / 6)) / 2\nresult = 100 * area / 24", "values[0] * (2 + (2 + 4 * values[0] / 6)) / 2"],
  panethLuminalRelease: ["min(values[0].rounded(), values[1].rounded())", "values[1].rounded() - min(values[0].rounded(), values[1].rounded())"],
  penilePathTrace: ["10 * values[0] / 100", "10 - 10 * values[0] / 100"],
  plasmaCellSecretionTally: ["values[0].rounded() * 3", "3"],
  satelliteGlialSheathGap: [".pi * values[1] * (2 * values[0] + values[1])", "values[0] + values[1]"],
  scrotalHeatTally: ["values[0] * (values[1] / 100)", "values[0] - values[0] * (values[1] / 100)"],
  skullVaultLayers: ["1 + values[0] + 1 + values[1]", "1 + values[0] + 1"],
  splenicSlitSorting: ["Double([1, 2, 2, 3, 3, 3, 4, 4, 5, 6, 7, 8].filter { Double($0) <= values[0] }.count)", "12 - Double([1, 2, 2, 3, 3, 3, 4, 4, 5, 6, 7, 8].filter { Double($0) <= values[0] }.count)"],
  thyroidCCellReleaseGrid: ["values[1].rounded() * values[0].rounded()", "values[1].rounded() * (5 - values[0].rounded())"],
  thyroidFollicularFaces: ["2 * .pi * values[1] / values[0].rounded()", "2 * .pi * (values[1] + 2) / values[0].rounded()"],
  urethralOpeningArea: [".pi * (values[0] / 2) * (values[0] * (values[1] / 100) / 2)", "values[0] * (values[1] / 100)"],
  vaginalRugaSpan: ["2 * sqrt(25 - values[0] * values[0])", "10 - 2 * sqrt(25 - values[0] * values[0])"],
  vestibularGlandVolume: ["values[0] + values[1]", "abs(values[0] - values[1])"]
};
assert.deepEqual(new Set(Object.keys(formulas)), new Set(models.map(m => m.id)));
for (const [id, pair] of Object.entries(formulas)) for (const [index, expression] of pair.entries()) {
  const method = index === 0 ? values.split("func evaluate")[1].split("func companion")[0] : values.split("func companion")[1];
  const expected = expression.startsWith("let ") ? expression : "result = " + expression;
  assert(normalize(body(method, id)).startsWith(normalize(expected)), id + ": formula");
}
assert.equal(resourceKeys.size, 162);
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("GalaxySSI/" + locale + ".lproj/AtlasCompletionTeaching.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), resourceKeys); for (const value of table.values()) assert(value);
  assert.equal(table.get("health_atlas_values"), locale === "en" ? "My metrics" : "\u6211\u7684\u6307\u6807");
}
const oldRoute = s => s.split("static func forEntry(_ id: String)")[1].split("default:")[0];
const previous = git(["show", "2d887e5a44afac865375463d454d02fcfb135100:apps/ios/GalaxySSI/GalaxySSIHealthAtlasPhysiology.swift"]).toString();
assert.equal(oldRoute(physiology), oldRoute(previous));
const oldIDs = [...oldRoute(previous).matchAll(/"([a-z0-9-]+)"/g)].map(m => m[1]);
const allModels = [4397, 4399, 4401, 4402, 4405, 4407, 4410, 4412, 4414].flatMap(n => JSON.parse(read(`ANDROID_${n}_MODEL_DECLARATIONS.json`)).models);
assert.equal(allModels.length, 100); assert.equal(allModels.flatMap(m => m.inputs).length, 198);
const allOwners = allModels.flatMap(m => m.entryIDs); assert.equal(allOwners.length, 246); assert.equal(new Set(allOwners).size, 246);
assert(allOwners.every(id => !oldIDs.includes(id)));
const graph = JSON.parse(git(["show", sha + ":apps/android/app/src/main/assets/health/body-atlas.json"]));
assert.deepEqual(new Set([...oldIDs, ...allOwners]), new Set(graph.entries.map(e => e.id)));
const detail = source("Detail"), state = source("State");
assert(detail.includes('Button(t("simulation"))') === false);
assert(detail.indexOf("numericalModelButton") > detail.indexOf("GalaxySSIHealthAtlasFunctionPanel("));
// #4444 moves related links into the player menu, leaving the model entry after playback.
assert(!detail.includes("GalaxySSIHealthAtlasFunctionRelatedRow("));
assert(detail.includes("currentTab == .function && !hasFunctionPlayer"));
assert(detail.includes("}.id(currentTab)"), "New tabs open at the top without resetting selection state");
for (const token of ['Label(t("open_quantitative_model"), systemImage: "chart.bar")', '"atlas-open-simulation"', "state.openNumericalModel(entry)"])
  assert(detail.includes(token));
for (const token of ["var next = functionSnapshot(entry)", "next.tab = .simulation", "entries[entry.id] = next", "function.save(phase, storyID: storyID", "Physiology.restore(id, inputs: entries[id]?.physiologyInputs)"])
  assert(state.includes(token));
assert(source("FunctionPlayer").includes(".onDisappear { pause() }"));
assert(source("FunctionPlayer").includes("private func pause() { pause(at: GalaxySSIHealthAtlasChapterClock.now) }"));
assert(source("FunctionPlayer").includes("clock.pause(now); publish(clock.sample(now))"));
assert(source("FunctionPlayer").includes("playback.release(playbackID); commit()"));
assert(source("").includes('table: "AtlasCompletionTeaching"'));
assert(read("GalaxySSI.xcodeproj/project.pbxproj").includes("C44140000000000000000001 /* AtlasCompletionTeaching.strings in Resources */"));
const targets = ["TeachingModel", "TeachingControls", "TeachingValues"].map(n => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + n + ".swift");
const counts = {}, files = inventory.files.map(file => {
  let kind, ios, note;
  if (file.path.includes("/src/main/java/")) {
    const name = path.basename(file.path, ".kt");
    if (name === "HealthBodyAtlasActivity") {
      kind = "numerical-entry-and-metrics-navigation"; ios = ["apps/ios/GalaxySSI/GalaxySSIHealthAtlasDetail.swift", "apps/ios/GalaxySSI/GalaxySSIHealthAtlasState.swift"];
      note = "Numerical model action follows playback, before related prose. Snapshot live function phase, preserve selected sliders and existing restore. My metrics localized independently of synthetic models.";
    } else if (name === "HealthAtlasPhysiology") {
      kind = "complete-additive-model-routing"; ios = ["apps/ios/GalaxySSI/GalaxySSIHealthAtlasPhysiology.swift"];
      note = "30 new owners preserve original 67 literal clauses and 216 previous teaching bindings. Source partition reaches 313 catalogue IDs; conditional oxygen exclusion leaves 311. Not runtime coverage certification.";
    } else {
      assert(models.some(m => name === "HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel"));
      kind = "bounded-completion-teaching-model"; ios = targets;
      note = "Exact original control metadata, sources, bindings, formulas and companions. Whole nonnegative diagram counts round at half steps; geometric/ratio/path calculations remain continuous. No personal measurements.";
    }
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasCompletionTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasCompletionTeaching.strings"];
    note = "162 structurally extracted and Xcode-registered English/Chinese pairs, including My metrics and Numerical model. Preserve synthetic scope and original units.";
  } else if (/\/src\/(?:test|androidTest)\//.test(file.path)) {
    kind = "android-test-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"];
    note = "Source fixtures updated for 28 defaults, counts, integer half steps, slit thresholds, continuous geometry, sign/companions and 30-owner tab/restore contracts. Neither Android nor XCTest executed; no native UI or pixel acceptance.";
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts"); kind = "android-version-only"; ios = []; note = "No iOS version bump or IPA.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)));
  counts[kind] = (counts[kind] || 0) + 1; return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(counts["bounded-completion-teaching-model"], 28); assert.equal(counts["exact-bilingual-resource-delta"], 58);
assert.equal(counts["android-test-reference-not-executed"], 30);
const report = JSON.stringify({schema: 1, source: declarations.source, verification: "source-contracts-only-not-native-execution", counts, files}, null, 2) + "\n";
if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, "apps/ios/ANDROID_4414_PORT_COVERAGE.json"), report);
else assert.equal(read("ANDROID_4414_PORT_COVERAGE.json"), report);
if (process.argv.includes("--checks")) for (const command of [
  "import-atlas-teaching-models.cjs --completion-4414 --check", "import-body-atlas-regional-text.cjs --completion-4414 --check",
  ...["--pleural-4412", "--exchange-4410", "--phase-4407", "--transport-4405", "--regional-4402", "--organ-4401", "--system-4399", ""].map(flag => "check-atlas-teaching-model-source.cjs " + flag)
]) {
  const [file, ...args] = command.trim().split(" "); cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4414: 119 hashes/dispositions; 28 declarations, 48 controls, 30 additive owners, 162 bilingual pairs and source partition for 313 entries. Not native execution or acceptance.");

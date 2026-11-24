// Android #4402 file dispositions; source evidence only, no native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4402_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4402_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "bounded-regional-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original controls/defaults/scales/units/precision, axes/bounds, scopes, source URLs and owners are reproduced. Native kernels preserve fractional inputs, signed bone changes and whole-fragment rounding for positive counts. No patient data or native numerical certification."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-model-routing", ios: [swift("Physiology"), swift("State")],
  note: "19 new owners are disjoint from all previous routes. Existing restoration, source links, synthetic context and bounded curves use native model specifications without changing original artwork or function routes."});
business.set("HealthAtlasPhysiologyPanel", {kind: "native-playback-and-controls-placement", ios: [swift("PhysiologyPanel")],
  note: "Bladder view precedes controls; bladder/cilia charts follow sliders. Explicit reset token resets even unchanged inputs. Entry identity isolates playback. Existing generic reset, sliders, outputs, curve and sources remain wired."});
business.set("HealthAtlasMaterialResponseView", {kind: "reactive-cilia-transport-track", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing")],
  note: "Nine lining cells, four quadratic cilia each, marker/conditional arrow, track/progress and original geometry/colors/localized description. No pixel parity claimed."});
business.set("HealthAtlasBladderFillingView", {kind: "native-bladder-filling-playback", ios: [swift("BladderFillingView")],
  note: "Pause/resume/replay with linear 1.8-second full duration, selected-volume-independent progress, zero-added-volume disable, model/reset isolation, background/disappear/reduce-motion pause. Original cubic chambers, sphere-radius scaling, gradient, walls, before/current volumes and accessible descriptions. No runtime/gesture/pixel acceptance."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasRegionalTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasRegionalTeaching.strings"],
      note: "62 English/Chinese resource pairs structurally extracted and registered in Xcode. Existing localized cycles unit also applies to ciliary input."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected Android contracts, not executed. XCTest source covers new defaults/slider pairs, volume/area, signed change, half-step platelet rounding, fractional gastric/cilia outputs, owner restoration and independent artwork/function selections. Playback lifecycle is checked at source level only, not native execution."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Android APK version metadata does not change the iOS version. No IPA."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 43); assert.equal(business.size, 13);
assert.equal(counts["bounded-regional-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 11);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4402_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --regional-4402", "import-atlas-teaching-models.cjs --regional-4402 --check",
  "import-body-atlas-regional-text.cjs --regional-4402 --check", "check-atlas-teaching-model-source.cjs --organ-4401",
  "check-atlas-teaching-model-source.cjs --system-4399", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4402: all 43 files mapped. Not native execution or acceptance.");

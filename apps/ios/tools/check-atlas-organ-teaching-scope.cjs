// Reproducible Android #4401 source dispositions, not native execution or acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4401_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4401_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "bounded-organ-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original Kotlin declarations fix ranges/defaults/scales/units/precision, axis/bounds, source URLs, scopes and owner IDs. Explicit native result/companion formulas preserve synthetic model dimensions. No patient data or native execution."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-owner-routing-and-restoration", ios: [swift("Physiology"), swift("State")],
  note: "42 new owners are disjoint from original literal routes and preceding teaching bindings. Existing per-entry restoration, sources, 121-point curves and reset remain shared; native coverage is not certified."});
business.set("HealthAtlasMaterialResponseView", {kind: "reactive-arterial-section-and-speed", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing")],
  note: "Original 340x156 geometry, diameter-scaled lumen, wall, diameter marks, normalized speed ruler, positive-flow arrow and zero-flow dot, localized legends and accessible description. No pixel or gesture acceptance claimed."});
business.set("HealthAtlasPhysiologyPanel", {kind: "native-arterial-material-placement", ios: [swift("Physiology"), swift("PhysiologyPanel")],
  note: "Arterial continuity joins existing material response placement; native sliders, output, companion, chart, sources and reset remain connected. Existing curve identifier already matches the corrected Android device-test tag."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasOrganTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasOrganTeaching.strings"],
      note: "57 matching English/Chinese pairs structurally extracted and registered in localized Xcode resources. Original mathematical symbols and disclaimers retained."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected source contracts; native XCTest source covers all nine defaults, all new slider pairs, conservation, continuous retinal expectations, unit conversions, scoped routing and 42-owner independent state. Device curve tag corrections match existing iOS curve identifiers. No Android/XCTest/device execution or pixel acceptance."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "APK version metadata is platform-specific; no iOS version change or IPA."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 45); assert.equal(business.size, 12);
assert.equal(counts["bounded-organ-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 14);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4401_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --organ-4401", "import-atlas-teaching-models.cjs --organ-4401 --check",
  "import-body-atlas-regional-text.cjs --organ-4401 --check", "check-atlas-teaching-model-source.cjs --system-4399",
  "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4401: all 45 files mapped, no native acceptance claimed.");

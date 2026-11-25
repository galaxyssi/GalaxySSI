// Android #4410 changed-file dispositions. Source evidence only, not native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4410_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4410_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "bounded-exchange-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues"), swift("ExchangeAmounts")],
    note: "Original controls/ranges/defaults/scales/units/precision, axes/bounds, assumptions, source URLs and owners are reproduced. Native kernels preserve surface pressure/area, two-segment retention, simulated amount budgets and finite continuous chart samples. Not patient data or native numerical certification."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-exchange-routing", ios: [swift("Physiology"), swift("State")],
  note: "22 new owners disjoint from original literal and prior teaching routes. Generic curves, source links, context, reset and entry-local restoration remain wired. Existing kidneys/nephron and capillary models are unchanged."});
business.set("HealthAtlasPhysiologyPanel", {kind: "native-placental-playback-placement", ios: [swift("PhysiologyPanel")],
  note: "Placental playback precedes controls; placental/enamel/tubule charts follow sliders. Reset tokens and entry identity isolate progress and preserve unrelated artwork/function choices."});
business.set("HealthAtlasMaterialResponseView", {kind: "responsive-enamel-and-serial-tubule-diagrams", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing"), swift("ExchangeAmounts")],
  note: "Enamel rim, remainder and thickness marks retain original scale/colors/labels. Three tubule nodes use the same validated serial amounts as numerical kernels and square-root marker area. No native pixel/gesture acceptance."});
business.set("HealthAtlasPlacentalMarkerView", {kind: "separate-lane-marker-exchange-playback", ios: [swift("PlacentalMarkerView"), swift("ExchangeAmounts"), swift("TeachingPlayback")],
  note: "2.3-second shared playback, disabled at zero transfer. Separate maternal/fetal lanes, 13 barrier cells, two eight-slot marker budgets, moving marker and fitted labels retain source geometry/colors. Animation alters presented amounts only, not selected inputs or depicted blood lanes. No native runtime acceptance."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasExchangeTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasExchangeTeaching.strings"],
      note: "70 structurally extracted matching English/Chinese pairs, registered in Xcode with both new Swift files. Original synthetic units, assumptions and format arguments are retained."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected source contracts. Native XCTest source covers defaults/all new slider pairs, conservation/dimensions, signed guards, serial reclaimed amounts, finite phase amounts and 22-owner restoration including separate placenta/trophoblast settings. No Android, XCTest, device, playback, accessibility gesture or pixel execution."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Android APK metadata does not alter iOS version; no IPA."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 44); assert.equal(business.size, 13);
assert.equal(counts["bounded-exchange-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 12);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4410_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --exchange-4410", "import-atlas-teaching-models.cjs --exchange-4410 --check",
  "import-body-atlas-regional-text.cjs --exchange-4410 --check", "check-atlas-teaching-model-source.cjs --phase-4407",
  "check-atlas-teaching-model-source.cjs --transport-4405", "check-atlas-teaching-model-source.cjs --regional-4402",
  "check-atlas-teaching-model-source.cjs --organ-4401", "check-atlas-teaching-model-source.cjs --system-4399", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4410: all 44 files mapped. Not native execution or acceptance.");

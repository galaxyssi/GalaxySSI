// Android #4412 changed-file dispositions. Source contracts only, not native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4412_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4412_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "bounded-pleural-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original controls/ranges/defaults/scales/units/digits, axes/bounds, sources and exact owner IDs are reproduced. Preserve modeled shear/stress, attenuation, positive separated positions, ring/cylinder geometry, clamped projections, signed whole-icon renewal and cumulative/wrapped phase. No patient data or native numerical certification."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-pleural-routing", ios: [swift("Physiology"), swift("State")],
  note: "21 new owners are disjoint from original literal and prior teaching bindings. Native controls, chart/source/context/reset/restoration remain entry-local; existing ventilation, renal and optical models retain their old routes."});
business.set("HealthAtlasPhysiologyPanel", {kind: "pleural-player-and-curve-placement", ios: [swift("PhysiologyPanel")],
  note: "Pleural player precedes controls; pleural/retinal curves follow sliders. Explicit reset token and entry identity preserve per-entry numerical state and unrelated artwork/function choices."});
business.set("HealthAtlasPleuralSlideView", {kind: "layered-pleural-relative-motion-playback", ios: [swift("PleuralSlideView"), swift("TeachingPlayback")],
  note: "2.3-second shared playback disabled at zero speed. Original gap scaling, five tissue/film bands, clipped moving wall features, four tracer rows with linear relative speeds, bracket and labels. Playback phase is separate from selected inputs; lifecycle/Reduce Motion handling retained. No runtime or pixel acceptance."});
business.set("HealthAtlasMaterialResponseView", {kind: "responsive-retinal-attenuation-diagram", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing"), swift("IllustratedDrawing")],
  note: "Original layer thickness, coefficient-dependent alpha, incident/internal/transmitted rays, intensity-dependent arrow alpha/width, marker and legends. Existing UInt32 ARGB decoder preserves transparency. No native render or optical/clinical claim."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasPleuralTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasPleuralTeaching.strings"],
      note: "64 structurally extracted English/Chinese resource pairs registered with the new Swift view. Original synthetic units and assumptions are retained; existing localized cycles output is reused."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected source contracts. Native XCTest source covers nine defaults/all new slider pairs, geometry/conservation, whole-step/half-step renewal, phase wrap, finite linear tracer helpers, pause/settings isolation and 21-owner restoration. No Android, XCTest, native playback, accessibility gesture or pixel test execution."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Android APK metadata does not change iOS version; no IPA."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 44); assert.equal(business.size, 13);
assert.equal(counts["bounded-pleural-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 12);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4412_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --pleural-4412", "import-atlas-teaching-models.cjs --pleural-4412 --check",
  "import-body-atlas-regional-text.cjs --pleural-4412 --check", "check-atlas-teaching-model-source.cjs --exchange-4410",
  "check-atlas-teaching-model-source.cjs --phase-4407", "check-atlas-teaching-model-source.cjs --transport-4405",
  "check-atlas-teaching-model-source.cjs --regional-4402", "check-atlas-teaching-model-source.cjs --organ-4401",
  "check-atlas-teaching-model-source.cjs --system-4399", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4412: all 44 files mapped. Not native execution or acceptance.");

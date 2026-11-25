// Android #4399 file dispositions and reproducible source checks, not native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4399_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4399_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + (m.id === "diaphragmDisplacement" ? "Diaphragm" : m.id[0].toUpperCase() + m.id.slice(1)) + "TeachingModel",
  {kind: "bounded-system-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original Kotlin declarations supply controls, scales, units, bounds, axis, precision, scopes, sources and exact owners. Native result and companion cases preserve the original formulas. No Swift execution claimed."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-routing-and-independent-state", ios: [swift("Physiology"), swift("State")],
  note: "35 new owners, disjoint from preceding teaching owners and existing literal routes. Retains original model precedence, independent entry restoration and generic chart/reset controls."});
business.set("HealthAtlasPhysiologyPanel", {kind: "localized-input-output-and-axis", ios: [swift("PhysiologyPanel")],
  note: "Visible input units, slider accessibility values and axis captions use displayUnit. Diaphragm joins existing material/curve placement; controls still bind to entry-local inputs."});
business.set("HealthAtlasPhysiologyChart", {kind: "localized-chart-unit", ios: [swift("PhysiologyPanel")],
  note: "The native inline chart resolves the output unit through displayUnit, preserving the original 121-point response and axes."});
business.set("HealthAtlasPhysiologyText", {kind: "localized-visible-units-and-public-context", ios: [swift("PhysiologyText"), swift("")],
  note: "Only bpm/cells/cycles are localized; arithmetic units and synthetic DU/min/LU/TU stay unchanged. Native context includes all original model disclaimers and sources."});
business.set("HealthAtlasMaterialResponseView", {kind: "reactive-diaphragm-cross-section", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing")],
  note: "340x156 design coordinates, square-root area width, displacement, cubic chest/domes, gained area, resting dashed/current solid strokes, conditional arrow and localized legends. No native pixel/gesture acceptance performed."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasSystemTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasSystemTeaching.strings"],
      note: "All changed resources extracted structurally from pinned XML, registered as a localized Xcode resource table. No cross-language replacement."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-contract-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected original test contracts. Native XCTest source covers defaults, all new slider pairs, units, conservation, continuous curves, invalid restoration, localization and independent owner state. Neither Android tests nor XCTest/device tests were run."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Android-only APK version metadata is not applied to iOS. No IPA or iOS release version change."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 48); assert.equal(business.size, 14);
assert.equal(counts["bounded-system-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 20);
assert.equal(counts["android-contract-reference-not-executed"], 13);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4399_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --system-4399", "import-atlas-teaching-models.cjs --system-4399 --check",
  "import-body-atlas-regional-text.cjs --system-4399 --check", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4399: all 48 changed files mapped; no native acceptance claimed.");

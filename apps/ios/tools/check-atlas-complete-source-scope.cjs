// Exhaustive file dispositions, not native acceptance or Android/XCTest execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4388_SOURCE_INVENTORY.json");
const app = name => "apps/ios/GalaxySSI/" + name, swift = name => app("GalaxySSIHealthAtlas" + name + ".swift");
const catalogue = app("Assets.xcassets/HealthAtlasCompleteStories.dataset/content.json");
const structures = app("Assets.xcassets/HealthAtlasCompleteStructures.dataset/content.json");
const explicit = new Map();
function map(names, kind, ios, checks, note) {
  for (const name of names) { assert(!explicit.has(name)); explicit.set(name, {kind, ios, checks, ...(note ? {note} : {})}); }
}
map(["AnteriorPituitaryAssignments", "EndocrineCellAssignments", "GonadalSupportAssignments", "IntestinalEpithelialAssignments",
  "LangerhansSentinelAssignment", "MastAndTCellAssignments", "MuscleSatelliteRenewalAssignment", "PericyteCoverageAssignment",
  "RenalBladderCellAssignments", "CellLesson"], "original-kotlin-catalogue-extraction", [catalogue, swift("FunctionCatalogue")], ["check-atlas-complete-catalogue.cjs"]);
map(["FunctionStory"], "complete-catalogue-and-explicit-renderer-dispatch", [catalogue, swift("FunctionArtwork"), swift("FunctionPanel")], ["check-atlas-complete-catalogue.cjs"]);
map(["LoadTransferPlates", "TissueContextPlates"], "original-plate-declaration-extraction-and-runtime-routing",
  [structures, swift("RegionalStructures"), swift("")], ["check-atlas-regional-structures.cjs --complete-4388"]);
const modelFiles = ["Physiology", "PhysiologyPanel", "PhysiologyText", "MaterialResponseView", "MaterialResponseDrawing"].map(swift);
map(["Physiology", "PhysiologyPanel", "PhysiologyText", "MaterialResponseView"], "bounded-models-and-material-diagrams", modelFiles, ["check-atlas-load-transfer-models.cjs"]);
const scenes = [
  ["AdrenalCortex", ["EndocrineZoneView", "AdrenalCortexDrawing"], "endocrine-zone"],
  ["ThyroidCalcitonin", ["EndocrineZoneView", "CalcitoninDrawing"], "endocrine-zone"],
  ["Corticotroph", ["CorticotrophView", "CorticotrophDrawing"], "corticotroph"],
  ["Gonadotroph", ["GonadotrophView", "GonadotrophDrawing"], "gonadotroph"],
  ["Lactotroph", ["LactotrophView", "LactotrophDrawing"], "lactotroph"],
  ["Somatotroph", ["SomatotrophView", "SomatotrophDrawing"], "somatotroph"],
  ["DistalTubular", ["RenalCellLessonView", "DistalTubularDrawing"], "renal-cell"],
  ["Urothelial", ["RenalCellLessonView", "UrothelialDrawing"], "renal-cell"],
  ["EnteroendocrineSignal", ["CryptLessonView", "CryptSignalDrawing"], "crypt-lessons"],
  ["IntestinalStemRenewal", ["CryptLessonView", "CryptStemDrawing"], "crypt-lessons"],
  ["PanethBarrier", ["PanethBarrierView", "CryptWallDrawing"], "paneth"],
  ["PancreaticDelta", ["IsletLessonView", "DeltaSignalDrawing"], "islet"],
  ["PancreaticPp", ["IsletLessonView", "PPSignalDrawing"], "islet"],
  ["LeydigEndocrine", ["GonadalLessonView", "LeydigDrawing"], "gonadal"],
  ["ThecaCooperation", ["GonadalLessonView", "ThecaDrawing"], "gonadal"],
  ["LangerhansSentinel", ["LangerhansView", "LangerhansDrawing"], "langerhans"],
  ["PericyteCoverage", ["PericyteView", "PericyteDrawing"], "pericyte"],
  ["MuscleSatelliteRenewal", ["SatelliteView", "SatelliteDrawing"], "satellite"]
];
for (const [name, targets, check] of scenes) map([name + "StoryView"], "dedicated-native-course-renderer", [...targets.map(swift), swift("FunctionArtwork")], ["check-atlas-" + check + "-source.cjs"]);
map(["PelvicRingStoryView", "SubcutaneousStoryView"], "dedicated-native-load-transfer-renderer",
  [swift("LoadTransferStoryView"), swift("LoadTransferStoryDrawing"), swift("MeshImage"), swift("FunctionArtwork")], ["check-atlas-load-transfer-art.cjs"]);
map(["AnteriorPituitaryArt"], "source-generated-shared-pituitary-geometry", [swift("AnteriorPituitaryGeometry"), swift("AnteriorPituitaryDrawing")], ["import-atlas-endocrine-geometry.cjs --pituitary --check"]);
map(["CryptWallArt"], "source-matched-shared-crypt-wall", [swift("CryptWallDrawing")], ["check-atlas-paneth-source.cjs"]);
map(["EndocrineCellStoryView"], "shared-native-endocrine-drawing-primitives", [swift("IllustratedDrawing"), swift("AnteriorPituitaryDrawing")], ["check-atlas-endocrine-zone-source.cjs", "check-atlas-gonadal-source.cjs"]);
map(["MastAndTCellArt"], "four-native-immune-courses-and-shared-geometry",
  ["ImmuneDrawing", "ImmuneGeometry", "MastGeometry", "MastView", "MastDrawing", "TCellLessonView", "RegulatoryTView", "RegulatoryTDrawing"].map(swift),
  ["check-atlas-mast-source.cjs", "check-atlas-regulatory-t-source.cjs", "check-atlas-helper-cytotoxic-source.cjs"]);
const coverage = [], counts = {};
for (const file of inventory.files) {
  let item;
  if (file.path.includes("/src/main/java/")) {
    const name = path.basename(file.path, ".kt").replace(/^HealthAtlas/, "");
    item = explicit.get(name); assert(item, "Unmapped business source " + name);
  } else if (file.path.includes("/res/drawable/")) {
    const asset = file.path.endsWith("health_atlas_pelvic_ring.xml") ? "HealthAtlasCompletePelvicRing" : "HealthAtlasCompleteSubcutaneousSection";
    item = {kind: "source-vector-with-correct-quadratics-and-even-odd-holes", ios: [app("Assets.xcassets/" + asset + ".imageset/art.pdf")], checks: ["check-atlas-load-transfer-art.cjs"]};
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    item = {kind: "bilingual-resource-delta", ios: [app("en.lproj/AtlasComplete.strings"), app("zh-Hans.lproj/AtlasComplete.strings")], checks: ["import-body-atlas-regional-text.cjs --complete-4388 --check"]};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    item = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"], checks: ["check-atlas-complete-catalogue.cjs", "check-atlas-load-transfer-models.cjs", "check-atlas-regional-structures.cjs --complete-4388"], note: "Platform test scaffolding is not copied. Source checks do not establish native rendering, screenshot, navigation, accessibility or persistence acceptance. No XCTest/device run performed."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    item = {kind: "android-packaging-only", ios: [], checks: [], note: "Android APK version bump is not an iOS feature; no version change or IPA generated here."};
  }
  for (const target of item.ios) assert(fs.existsSync(path.join(root, target)), target);
  for (const check of item.checks) assert(fs.existsSync(path.join(__dirname, check.split(" ")[0])), check);
  counts[item.kind] = (counts[item.kind] || 0) + 1;
  coverage.push({source: file.path, sourceSHA256: file.sha256, ...item});
}
assert.equal(coverage.length, 67); assert.equal(counts["bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 5); assert.equal(counts["android-packaging-only"], 1);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files: coverage};
const output = JSON.stringify(report, null, 2) + "\n", destination = path.join(root, "apps/ios/ANDROID_4388_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(destination, output);
else assert.equal(fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n"), output);
if (process.argv.includes("--checks")) for (const command of new Set(coverage.flatMap(f => f.checks))) {
  console.log("SOURCE CHECK: " + command);
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
}
console.log("All 67 Android #4388 source files have explicit dispositions; not native acceptance.");

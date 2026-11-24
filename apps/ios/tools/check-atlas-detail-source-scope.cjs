// Exhaustive source dispositions only. No device, XCTest or Swift compilation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const anatomy = process.argv.includes("--anatomy-4396"), expanded = anatomy || process.argv.includes("--expanded-4391"), revision = anatomy ? 4396 : expanded ? 4391 : 4389;
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_" + revision + "_SOURCE_INVENTORY.json");
const app = name => "apps/ios/GalaxySSI/" + name, swift = name => app("GalaxySSIHealthAtlas" + name + ".swift");
const dataset = app("Assets.xcassets/" + (anatomy ? "HealthAtlasAnatomyStructures" : expanded ? "HealthAtlasExpandedDetailStructures" : "HealthAtlasDetailStructures") + ".dataset/content.json");
const pack = JSON.parse(fs.readFileSync(path.join(root, dataset)));
const explicit = new Map();
function map(names, kind, ios, note) {
  for (const name of names) { assert(!explicit.has(name)); explicit.set(name, {kind, ios, ...(note ? {note} : {})}); }
}
map(["HealthAtlasCardiacOutflowPlates", "HealthAtlasGallbladderAndSalivaryPlates", "HealthAtlasHearingBalancePlates",
  "HealthAtlasKidneyRegionalPlates", "HealthAtlasLongBoneAndShoulderPlates", "HealthAtlasNeuralRegionalPlates",
  "HealthAtlasOpticsDetailPlates", "HealthAtlasRegionalDetailPlates", "HealthAtlasUpperAirwayBifurcationsPlates",
  "HealthAtlasUrinaryOutflowPlates"], "original-kotlin-declaration-extraction", [dataset, swift("DetailStructures")]);
if (expanded) map(["HealthAtlasSkinLayersDetailPlates", "HealthAtlasHeartChamberDetailPlates", "HealthAtlasHeartValveDetailPlates",
  "HealthAtlasOuterSensoryDetailPlates", "HealthAtlasNephronStructureDetailPlates", "HealthAtlasNeuralConnectionDetailPlates",
  "HealthAtlasReproductiveAnatomyDetailPlates", "HealthAtlasMajorMuscleDetailPlates", "HealthAtlasLimbBoneDetailPlates"],
  "original-kotlin-declaration-extraction", [dataset, swift("DetailStructures")]);
if (anatomy) map(["HealthAtlasSternumAndHandDetailPlates", "HealthAtlasCardiacComparisonDetailPlates", "HealthAtlasVascularInterfaceDetailPlates",
  "HealthAtlasRenalOutletDetailPlates", "HealthAtlasMaleDuctRouteDetailPlates", "HealthAtlasAirwayDiaphragmDetailPlates",
  "HealthAtlasDigestiveDuctDetailPlates", "HealthAtlasPosteriorMuscleTendonDetailPlates", "HealthAtlasPelvicSoftTissueDetailPlates"],
  "original-kotlin-declaration-extraction", [dataset, swift("DetailStructures")]);
map(["AgentRichContentView"], "platform-native-tap-versus-drag-cancellation", [swift("Artwork"), swift("LabeledArtwork")],
  "The Android change is scoped to GalaxySSIPinchZoomViewport, not other transcript content. iOS uses UIScrollView zoom targets containing UIButtons, with touchesShouldCancel allowing a label drag to become a pan. No custom double-tap recognizer is installed over label actions; native pinch, pan and click acceptance remains unverified.");
map(["HealthAtlasAnatomyDialog"], "fullscreen-anatomy-controls-and-local-selection", [swift("Artwork")],
  "Full screen presentation, title/caption, independent zoom/labels, hide/show, scale/offset reset and local feature alerts. Canonical anatomy selection dismisses the presentation. Existing scroll/callout layout permits large text; no device or pixel acceptance performed.");
map(["HealthAtlasLabeledImage"], "label-visibility-and-measured-callout-rails", [swift("Artwork"), swift("LabeledArtwork"), swift("CalloutLayout")],
  "Unlabeled mode removes callout rails/guides; controls stay outside the image/labels. Existing measured rails and dynamic type are retained, without Android's inline control-space inset.");
map(["HealthAtlasPlates"], "detail-first-views-with-preserved-locator-identities", [swift(""), swift("DetailStructures"), dataset]);
map(["HealthAtlasUi", "HealthBodyAtlasActivity"], "selected-plate-fullscreen-and-navigation-wiring", [swift("Artwork"), swift("Detail"), swift("State")]);
const coverage = [], counts = {};
for (const file of inventory.files) {
  let item;
  if (file.path.includes("/src/main/java/")) {
    item = explicit.get(path.basename(file.path, ".kt")); assert(item, file.path);
  } else if (file.path.includes("/res/drawable/")) {
    const plate = pack.plates.find(p => p.drawable === file.path); assert(plate, file.path);
    item = {kind: "preserved-vector-with-normalized-quadratics", ios: [app("Assets.xcassets/" + plate.asset + ".imageset/art.pdf")]};
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    const table = anatomy ? "AtlasAnatomy" : expanded ? "AtlasExpanded" : "AtlasDetail";
    item = {kind: "exact-bilingual-resource-delta", ios: [app("en.lproj/" + table + ".strings"), app("zh-Hans.lproj/" + table + ".strings")]};
  } else if (file.path.includes("/src/androidTest/")) {
    item = {kind: "android-device-test-contract-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift", "apps/ios/tools/check-atlas-detail-source.cjs"],
      note: "Source expectations cover new default cutaways, retained selectable locators, features/links and restoration. Android gesture, alpha/pixel, screenshot, recreation and live accessibility assertions are not certified by source inspection. No Android device test or XCTest run performed."};
    if (anatomy && file.path.endsWith("/AgentRichContentPinchZoomTest.kt")) {
      item.note = "This change adjusts Android instrumentation's synthetic pinch radius to scaledMinimumScalingSpan/scaledTouchSlop. It does not change production behavior. iOS retains UIKit pinch/pan/button cancellation; no Android test-input thresholds are copied into production and no native gesture acceptance is claimed.";
    }
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    item = {kind: "android-apk-version-only", ios: [], note: anatomy ?
      "Pinned merge changes Android versionCode 1726 to 1727 and versionName 0.18.165 to 0.18.166. No iOS version or IPA change belongs in this feature port." : expanded ?
      "Pinned merge changes Android versionCode 1725 to 1726 and versionName 0.18.164 to 0.18.165. No iOS version or IPA change belongs in this feature port." :
      "Pinned merge changes Android versionCode 1724 to 1725 and versionName 0.18.163 to 0.18.164. No iOS version or IPA change belongs in this feature port."};
  }
  for (const target of item.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[item.kind] = (counts[item.kind] || 0) + 1;
  coverage.push({source: file.path, sourceSHA256: file.sha256, ...item});
}
assert.equal(coverage.length, anatomy ? 63 : expanded ? 70 : 72);
assert.equal(coverage.filter(f => f.source.includes("/src/main/java/")).length, expanded ? 10 : 16);
assert.equal(counts["original-kotlin-declaration-extraction"], 10);
assert.equal(counts["preserved-vector-with-normalized-quadratics"], anatomy ? 27 : expanded ? 35 : 26);
assert.equal(counts["exact-bilingual-resource-delta"], expanded ? 18 : 20);
assert.equal(counts["android-device-test-contract-reference-not-executed"], anatomy ? 7 : expanded ? 6 : 9);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files: coverage};
const output = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_" + revision + "_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, output);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), output);
const mode = anatomy ? "--anatomy-4396" : expanded ? "--expanded-4391" : "--detail-4389";
if (process.argv.includes("--checks")) for (const [file, ...args] of [
  ["check-atlas-detail-source.cjs", ...(expanded ? [mode] : [])], ["import-body-atlas-function-structures.cjs", mode, "--check"],
  ["import-body-atlas-regional-text.cjs", mode, "--check"]]) {
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #" + revision + ": all " + coverage.length + " source files explicitly mapped; no native acceptance claimed.");

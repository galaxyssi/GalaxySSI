// Android #4405 changed-file dispositions, source evidence only; not native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4405_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4405_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "bounded-transport-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original controls/ranges/defaults/scales/units/precision, axis/bounds, source URLs, scopes and owners are reproduced. Native formulas preserve whole positive push rounding, Snell refraction, hollow-shell volume, synthetic occupancy and mass/volume accounting. Not native numerical certification."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-model-routing", ios: [swift("Physiology"), swift("State")],
  note: "24 new owners disjoint from previous teaching bindings and existing literal routes. Generic curve/source/context/reset/restoration remains entry-local. No personal health record access."});
business.set("HealthAtlasPhysiologyPanel", {kind: "ureter-playback-and-control-placement", ios: [swift("PhysiologyPanel")],
  note: "Ureter playback precedes controls; ureter and corneal charts follow sliders. Per-entry view identity and reset token isolate playback and reset even unchanged input values."});
business.set("HealthAtlasPhysiologyChart", {kind: "curve-selector-already-native", ios: [swift("PhysiologyPanel")],
  note: "Android removes the stale chart selector and centralizes the curve tag. Native chart already uses atlas-physiology-curve; no duplicate chart implementation is introduced."});
business.set("HealthAtlasMaterialResponseView", {kind: "reactive-corneal-rays", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing")],
  note: "Original surface/normal, incident/refracted vectors with directional arrowheads, angle arcs, original colors/coordinates, localized legends and accessible description. No native pixels or gesture acceptance."});
business.set("HealthAtlasBladderFillingView", {kind: "bladder-shared-playback-migration", ios: [swift("BladderFillingView"), swift("TeachingPlayback")],
  note: "Existing bladder drawing remains intact; linear 1.8-second duration, zero-added-volume disable, selected inputs and localized labels are retained through the shared player."});
business.set("HealthAtlasTeachingPlayback", {kind: "shared-native-play-pause-resume-replay", ios: [swift("TeachingPlayback")],
  note: "Shared finite-duration phase state, final-target reset, pause/resume/replay, zero-duration/Reduce Motion disable, lifecycle pause and play/pause accessibility. State is independent of model inputs. XCTest state contracts added but not run."});
business.set("HealthAtlasUreterTransportView", {kind: "ureter-contraction-versus-fluid-playback", ios: [swift("UreterTransportView")],
  note: "1.1 seconds per selected push; floor-based arrivals plus partial in-transit packet, wave offset behind packet, 106-point tube outline, volume-scaled packet and six arrival markers. Original endpoints, geometry, colors and localized counter/description. No native runtime acceptance."});
business.set("HealthAtlasPlates", {kind: "gut-section-selector-preservation", ios: [swift("")],
  note: "Append original gut section beside context/detail plates unless its asset already exists; stable gut-section owner key and original selector label, while preserving detail-first ordering and all old context views."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasTransportTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasTransportTeaching.strings"],
      note: "66 structurally extracted English/Chinese pairs, registered in Xcode with both new native view files. Original assumptions/disclaimers and symbols retained."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected source contracts; added XCTest source for defaults, all new slider pairs, rounding/conservation, source owner changes, deterministic playback phases/arrivals, 24-owner independent restoration and all 14 gut section selection/restoration paths. No Android, XCTest, emulator/device, zoom/gesture or pixel acceptance was run."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Platform-specific APK metadata does not alter the iOS version. No IPA generated."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 50); assert.equal(business.size, 17);
assert.equal(counts["bounded-transport-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 14);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4405_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --transport-4405", "import-atlas-teaching-models.cjs --transport-4405 --check",
  "import-body-atlas-regional-text.cjs --transport-4405 --check", "check-atlas-teaching-model-source.cjs --regional-4402",
  "check-atlas-teaching-model-source.cjs --organ-4401", "check-atlas-teaching-model-source.cjs --system-4399", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4405: all 50 files mapped. Not native execution or acceptance.");

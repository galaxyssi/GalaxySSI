// Android #4407 changed-file dispositions. Source contracts only, not native acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4407_SOURCE_INVENTORY.json");
const models = require("../ANDROID_4407_MODEL_DECLARATIONS.json").models;
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const business = new Map(models.map(m => ["HealthAtlas" + (m.id === "vocalCycles" ? "VocalCycle" : m.id[0].toUpperCase() + m.id.slice(1)) + "TeachingModel",
  {kind: "bounded-phase-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original controls/defaults/ranges/scales/units/precision, axes/bounds, sources, assumptions and exact owner IDs are reproduced. Explicit native kernels preserve cumulative versus wrapped phase, cubed radius volume shares and synthetic amount budgets. No patient data or native numerical certification."}]));
business.set("HealthAtlasPhysiology", {kind: "additive-model-routing", ios: [swift("Physiology"), swift("State")],
  note: "19 new owners are disjoint from existing literal routes and previous teaching bindings. Generic sliders, curves, sources, localized context, reset and independent per-entry restoration remain wired."});
business.set("HealthAtlasPhysiologyPanel", {kind: "vocal-playback-control-placement", ios: [swift("PhysiologyPanel")],
  note: "Vocal playback precedes controls; vocal/circadian/adipose curves follow sliders. Reset tokens and per-entry identity keep progress separate from selected model inputs and old playback choices."});
business.set("HealthAtlasTeachingPlayback", {kind: "shared-native-seek-with-pause", ios: [swift("TeachingPlayback")],
  note: "Finite seek clamps to [0,1] and pauses. Optional 1000-step position slider uses the same phase as the artwork; touch start pauses and does not auto-resume on release. Bladder/ureter callers retain defaults and existing lifecycle/Reduce Motion handling."});
business.set("HealthAtlasVocalCycleView", {kind: "synchronized-vocal-folds-and-opening-curve", ios: [swift("VocalCycleView")],
  note: "2.4-second playback plus scrubbing, ideal cosine opening, cubic paired folds, square-root gap, 145 waveform samples, common cursor and localized fitted labels. No audio capture/output, sound waveform or clinical voice estimate. No native runtime/pixel acceptance."});
business.set("HealthAtlasMaterialResponseView", {kind: "reactive-circadian-and-adipose-diagrams", ios: [swift("MaterialResponseView"), swift("MaterialResponseDrawing")],
  note: "Circadian light/dark sectors, twelve ticks and wrapped-phase hand; cell droplet radius and tissue sector use separate cubed-volume budgets. Original dimensions/colors/labels/descriptions retained. No pixel parity claimed."});
const files = [], counts = {};
for (const file of inventory.files) {
  let disposition;
  if (file.path.includes("/src/main/java/")) {
    disposition = business.get(path.basename(file.path, ".kt")); assert(disposition, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    disposition = {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasPhaseTeaching.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasPhaseTeaching.strings"],
      note: "67 exact structurally extracted English/Chinese resource pairs registered in Xcode with the vocal Swift view. Existing localized cycles unit is reused; synthetic units match source."};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    disposition = {kind: "android-test-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Inspected original contracts. Native XCTest source covers defaults, all new slider pairs, cumulative/wrapped phase, volume/synthetic conservation, ideal opening extrema, seek/resume/reset, invalid inputs and 19-owner independent state. Android/XCTest/device, accessibility gesture and pixel tests were not run."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    disposition = {kind: "android-version-only", ios: [], note: "Android APK metadata does not change iOS version; no IPA."};
  }
  for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[disposition.kind] = (counts[disposition.kind] || 0) + 1;
  files.push({source: file.path, sourceSHA256: file.sha256, ...disposition});
}
assert.equal(files.length, 45); assert.equal(business.size, 14);
assert.equal(counts["bounded-phase-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-reference-not-executed"], 12);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4407_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of [
  "check-atlas-teaching-model-source.cjs --phase-4407", "import-atlas-teaching-models.cjs --phase-4407 --check",
  "import-body-atlas-regional-text.cjs --phase-4407 --check", "check-atlas-teaching-model-source.cjs --transport-4405",
  "check-atlas-teaching-model-source.cjs --regional-4402", "check-atlas-teaching-model-source.cjs --organ-4401",
  "check-atlas-teaching-model-source.cjs --system-4399", "check-atlas-teaching-model-source.cjs"
]) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4407: all 45 files mapped. Not native execution or acceptance.");

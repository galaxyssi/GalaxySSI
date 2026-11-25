// Exhaustive Android #4397 source dispositions. Does not run XCTest or native app tests.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), inventory = require("../ANDROID_4397_SOURCE_INVENTORY.json");
const app = name => "apps/ios/GalaxySSI/" + name, swift = name => app("GalaxySSIHealthAtlas" + name + ".swift");
const models = require("../ANDROID_4397_MODEL_DECLARATIONS.json").models;
const checks = ["check-atlas-teaching-model-source.cjs", "import-atlas-teaching-models.cjs --check", "import-body-atlas-regional-text.cjs --teaching-4397 --check"];
const business = new Map(models.map(m => ["HealthAtlas" + m.id[0].toUpperCase() + m.id.slice(1) + "TeachingModel",
  {kind: "source-matched-bounded-teaching-model", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
    note: "Original controls, units, axis/bounds, precision, scope, sources and owner bindings are compared to Kotlin-evaluated declarations. Both mathematical outputs have explicit native case implementations; no native execution claimed."}]));
business.set("HealthAtlasTeachingModelSpec", {kind: "native-model-specification-and-guards", ios: [swift("TeachingModel"), swift("TeachingControls"), swift("TeachingValues")],
  note: "Fixed native enum specifications replace Android spec lambdas. Input count/range/finite/scale checks reject invalid values; original source constructor invariants are checked during declaration extraction. No remote/user-supplied specification decoder is added."});
business.set("HealthAtlasPhysiology", {kind: "runtime-model-routing-and-independent-entry-state", ios: [swift("Physiology"), swift("State")],
  note: "Existing 67 route clauses retain precedence; 34 distinct new owners map to nine teaching kinds. Generic evaluation, companion, chart axes/bounds/sources and per-entry restoration use the new controls. Source routing is not proof of running 32-model/101-entry coverage."});
business.set("HealthAtlasPhysiologyPanel", {kind: "native-sliders-curve-reset-and-accessibility-identifiers", ios: [swift("PhysiologyPanel")],
  note: "Retains existing generic numerical UI, with localized controls/results/companion/synthetic scope, sources and chart; adds source-matched identifiers for curve, output, companion, sliders and reset. Native interaction/gesture/screenshot acceptance remains unperformed."});
business.set("HealthAtlasPhysiologyText", {kind: "bilingual-teaching-labels-precision-and-public-context", ios: [swift("PhysiologyText"), swift("TeachingModel"), swift("")],
  note: "Preserves per-control/result precision and original two-digit companion format, localized title/formula/scope/labels, source URLs and synthetic-only context. No health record is read by the models."});
const coverage = [], counts = {};
for (const file of inventory.files) {
  let item;
  if (file.path.includes("/src/main/java/")) {
    item = business.get(path.basename(file.path, ".kt")); assert(item, file.path);
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    item = {kind: "exact-bilingual-resource-delta", ios: [app("en.lproj/AtlasTeaching.strings"), app("zh-Hans.lproj/AtlasTeaching.strings")]};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    item = {kind: "android-test-contract-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasPhysiologyTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
      note: "Original Android tests were inspected, not compiled or run. Native XCTest source includes defaults, scaled units, signed pressure/zero clamp, conservation, bounded curves, invalid restoration, localized public context, ownership and entry-local capillary restore/reset expectations. No numerical/XCTest/device pass is claimed."};
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts");
    item = {kind: "android-apk-version-only", ios: [], note: "Pinned code changes Android 0.18.166 (1727) to 0.18.167 (1728). No iOS version change or IPA is part of this port."};
  }
  for (const target of item.ios) assert(fs.existsSync(path.join(root, target)), target);
  counts[item.kind] = (counts[item.kind] || 0) + 1;
  coverage.push({source: file.path, sourceSHA256: file.sha256, ...item});
}
assert.equal(coverage.length, 46); assert.equal(business.size, 13);
assert.equal(counts["source-matched-bounded-teaching-model"], 9);
assert.equal(counts["exact-bilingual-resource-delta"], 18);
assert.equal(counts["android-test-contract-reference-not-executed"], 14);
const report = {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", counts, files: coverage};
const text = JSON.stringify(report, null, 2) + "\n", target = path.join(root, "apps/ios/ANDROID_4397_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(target, text);
else assert.equal(fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n"), text);
if (process.argv.includes("--checks")) for (const command of checks) {
  const [file, ...args] = command.split(" ");
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: "inherit"});
}
console.log("Android #4397: all 46 source files explicitly mapped. No native acceptance claimed.");

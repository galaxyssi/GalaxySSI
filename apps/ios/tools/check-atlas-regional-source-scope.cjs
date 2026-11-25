// Exhaustive source-file disposition plus serial source-contract checks. No native tests/builds.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const inventory = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/ANDROID_4385_SOURCE_INVENTORY.json")));
assert.deepEqual(inventory.source, {androidPR: 4385, mergeCommit: sha});
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 32_000_000});
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(line => { const [status, file] = line.split("\t"); return {status, path: file}; });
assert.equal(changed.length, 93); assert.deepEqual(inventory.files.map(f => ({status: f.status, path: f.path})), changed);
const app = file => "apps/ios/GalaxySSI/" + file, tool = file => "apps/ios/tools/" + file;
const catalogue = app("Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json"), structures = app("Assets.xcassets/HealthAtlasRegionalStructures.dataset/content.json");
const dispatch = app("GalaxySSIHealthAtlasFunctionArtwork.swift"), structureCode = app("GalaxySSIHealthAtlasRegionalStructures.swift"), atlas = app("GalaxySSIHealthAtlas.swift");
const explicit = new Map();
function map(names, kind, ios, checks, note) { for (const name of names) { assert(!explicit.has(name)); explicit.set(name, {kind, ios, checks, ...(note ? {note} : {})}); } }
map(["AccessoryGlandRoutingAssignment", "AxialProtectionAssignment", "ClitoralVestibularAssignments", "PenileUrinaryAssignment", "ScrotalHeatAssignment", "ShoulderActionAssignments", "TenocyteTendonMatrixAssignment", "UterocervicalAssignment", "VulvarProtectionAssignment"], "original-kotlin-declaration-extraction", [catalogue, structures], ["import-body-atlas-function-catalogue.cjs --regional --check", "import-body-atlas-function-structures.cjs --regional --check"]);
map(["ShoulderActionPlates", "TenocyteTendonMatrixPlate", "TissueContextPlates", "UterocervicalPlates", "VulvarProtectionPlates"], "original-plate-declaration-extraction", [structures, structureCode], ["import-body-atlas-function-structures.cjs --regional --check", "check-atlas-regional-structures.cjs", "check-atlas-regional-runtime.cjs"]);
map(["FunctionStory"], "catalogue-and-dispatch", [catalogue, dispatch, app("GalaxySSIHealthAtlasFunctionCatalogue.swift")], ["import-body-atlas-function-catalogue.cjs --regional --check", "check-atlas-regional-runtime.cjs"]);
map(["Plates"], "view-selection-and-tenocyte-alternate", [atlas, structureCode, structures], ["check-atlas-regional-runtime.cjs", "check-atlas-regional-structures.cjs"]);
const scenes = [
  ["AccessoryGlandRouting", "AccessoryGland", "accessory-gland"], ["AnkleMortise", "Ankle", "ankle-mortise"],
  ["ClitoralSensory", "ClitoralSensory", "clitoral-vestibular"], ["LatissimusAction", "Latissimus", "shoulder-actions"],
  ["PectoralAction", "Pectoral", "shoulder-actions"], ["PenileUrinary", "PenileUrinary", "penile-urinary"],
  ["ScrotalHeat", "ScrotalHeat", "scrotal-heat"], ["SkullProtection", "Skull", "axial-courses"],
  ["TenocyteTendonMatrix", "TenocyteTendon", "tenocyte-tendon"], ["Uterocervical", "Uterocervical", "uterocervical"],
  ["VertebralMotion", "Vertebral", "axial-courses"], ["VestibularGland", "VestibularGland", "clitoral-vestibular"],
  ["VulvarProtection", "Vulvar", "vulvar-protection"]
];
for (const [android, native, check] of scenes) map([android + "StoryView"], "dedicated-native-renderer", [app("GalaxySSIHealthAtlas" + native + "View.swift"), app("GalaxySSIHealthAtlas" + native + "Drawing.swift"), dispatch], ["check-atlas-" + check + ".cjs", "check-atlas-regional-runtime.cjs"]);
map(["ShoulderActionMotion"], "native-pose-and-projection", [app("GalaxySSIHealthAtlasShoulderActionMotion.swift")], ["check-atlas-shoulder-actions.cjs"]);
map(["LigamentGuidanceStoryView"], "first-chapter-footprint-emphasis", [app("GalaxySSIHealthAtlasLigamentDrawing.swift")], ["check-atlas-calf-pump.cjs", "check-body-atlas-ligament.cjs"]);
map(["MaterialResponseView", "Physiology", "PhysiologyPanel", "PhysiologyText"], "calf-pump-model-panel-and-diagram", [app("GalaxySSIHealthAtlasPhysiology.swift"), app("GalaxySSIHealthAtlasPhysiologyText.swift"), app("GalaxySSIHealthAtlasPhysiologyPanel.swift"), app("GalaxySSIHealthAtlasMaterialResponseDrawing.swift"), app("GalaxySSIHealthAtlasMaterialResponseView.swift")], ["check-atlas-calf-pump.cjs", "check-atlas-material-response.cjs"]);
map(["PinealStoryView"], "platform-specific-cache-adaptation", [app("GalaxySSIHealthAtlasPinealGlyphDrawing.swift"), app("Assets.xcassets/HealthAtlasRegionalPinealPlate.imageset/Contents.json")], ["check-atlas-regional-runtime.cjs", "check-atlas-regional-vectors.cjs"], "Android replaces VectorDrawable raster caching. iOS uses its preserved-vector PDF/Image path with corrected quadratic geometry; device zoom/rewind acceptance has not been performed.");
process.argv.push("--regional-4385");
const art = require("./body-atlas-function-artwork.cjs"), counts = {}, coverage = [];
for (const file of inventory.files) {
  const bytes = git(["show", sha + ":" + file.path]);
  assert.equal(crypto.createHash("sha256").update(bytes).digest("hex"), file.sha256, file.path);
  let item;
  if (file.path.includes("/src/main/java/")) {
    const name = path.basename(file.path, ".kt").replace(/^HealthAtlas/, ""); item = explicit.get(name); assert(item, "Unmapped Kotlin source " + name);
  } else if (file.path.includes("/res/drawable/")) {
    const slug = path.basename(file.path, ".xml").replace(/^health_atlas_/, ""), frame = art.frames.find(f => f[0] === slug); assert(frame);
    item = {kind: "source-vector-with-gradients-and-clipping", ios: [app("Assets.xcassets/" + frame[1] + ".imageset/art.pdf")], checks: ["check-atlas-regional-vectors.cjs"]};
  } else if (/\/res\/values(?:-zh)?\//.test(file.path)) {
    item = {kind: "bilingual-resource-delta", ios: [app("en.lproj/AtlasRegional.strings"), app("zh-Hans.lproj/AtlasRegional.strings")], checks: ["import-body-atlas-regional-text.cjs --check"]};
  } else if (/\/src\/(?:androidTest|test)\//.test(file.path)) {
    item = {kind: "android-test-contract-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift", tool("check-atlas-regional-runtime.cjs")], checks: ["check-atlas-regional-runtime.cjs"], note: "Android test scaffolding is not copied into iOS. Focused source contracts are checked; no Android device tests, XCTest or native acceptance were executed."};
  } else if (file.path === "apps/android/app/build.gradle.kts") {
    item = {kind: "android-apk-version-only", ios: [], checks: [], note: "Android packaging/version bump is platform-specific; this iOS feature port does not change the app version or generate an IPA."};
  } else assert.fail("Unclassified source file " + file.path);
  for (const target of item.ios) assert(fs.existsSync(path.join(root, target)), target);
  for (const check of item.checks) assert(fs.existsSync(path.join(__dirname, check.split(" ")[0])), check);
  counts[item.kind] = (counts[item.kind] || 0) + 1;
  coverage.push({source: file.path, status: file.status, sourceSHA256: file.sha256, ...item});
}
assert.equal(coverage.filter(f => f.source.includes("/src/main/java/")).length, 36);
assert.equal(counts["source-vector-with-gradients-and-clipping"], 23); assert.equal(counts["bilingual-resource-delta"], 26);
assert.equal(counts["android-test-contract-reference-not-executed"], 7); assert.equal(counts["android-apk-version-only"], 1);
if (process.argv.includes("--checks")) {
  const commands = [...new Set(coverage.flatMap(f => f.checks))];
  for (const command of commands) {
    console.log("SOURCE CHECK: " + command);
    cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
  }
}
const report = {schema: 1, source: inventory.source, scope: "all-93-android-source-files", verification: "source-contracts-only-not-native-execution", counts, files: coverage};
const text = JSON.stringify(report, null, 2) + "\n", destination = path.join(root, "apps/ios/ANDROID_4385_PORT_COVERAGE.json");
if (process.argv.includes("--write")) fs.writeFileSync(destination, text);
else assert.equal(fs.readFileSync(destination, "utf8").replace(/\r\n/g, "\n"), text);
console.log("Android #4385 scope: all 93 source hashes/dispositions accounted for; 36 business files, 23 vectors, 26 resource XMLs, seven test references and one Android-only packaging bump. Source contracts are not native acceptance.");

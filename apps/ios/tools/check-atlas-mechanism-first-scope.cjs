// Layout/source contracts only; no Swift compilation, view rendering or native test execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "241177bc16b63d1b4da966c9d754144f8506de26";
const base = "7bb6a7acd95fe4aa873b2e99b0a09fcdd75ef804";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const prior = name => git(["show", base + ":" + swift(name)]).toString();
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 4);
const inventory = {schema: 1, source: {androidPR: 4420, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const android = git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSimulationPanel.kt"]).toString();
assert(android.includes("mechanismFirst: Boolean = false"));
assert(android.includes("quantitativeAfterArt = mechanismFirst || gasExchange != null || pancreaticRoutes != null || endocrinePath != null ||"));
assert(android.includes("sweatView != null || (sectionView != null && item.kind != HealthAtlasKind.CELL)"));
const panel = source("SimulationPanel"), research = source("Research"), state = source("State");
let expectedPanel = prior("SimulationPanel").replace("  let destination: (String) -> AnyView\n", "  let destination: (String) -> AnyView\n  var mechanismFirst = false\n")
  .replace("  private var quantitativeAfterSection: Bool { section != nil && entry.kind != .cell }\n", "  private var quantitativeAfterSection: Bool { section != nil && entry.kind != .cell }\n  var quantitativeAfterArt: Bool {\n    mechanismFirst || gasExchange || entry.id == \"pancreas\" || endocrine != nil || sweat || quantitativeAfterSection\n  }\n")
  .replace('      if !gasExchange, entry.id != "pancreas", endocrine == nil, !retinal, !sweat, !quantitativeAfterSection {\n      GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,\n        legacyVentilation: lung ? [simulation.first, simulation.second] : nil)',
    '      if !quantitativeAfterArt {\n        quantitative.accessibilityIdentifier("atlas-quantitative-before-art")');
const oldAfter = expectedPanel.indexOf("      if sweat || quantitativeAfterSection {");
const afterEnd = expectedPanel.indexOf("      #endif", oldAfter);
assert(oldAfter > 0 && afterEnd > oldAfter);
expectedPanel = expectedPanel.slice(0, oldAfter) + '      if quantitativeAfterArt {\n        quantitative.accessibilityIdentifier("atlas-quantitative-after-art")\n      }\n' + expectedPanel.slice(afterEnd);
expectedPanel = expectedPanel.replace("  private var playbackControls: some View {",
  '  #if GALAXYSSI_ATLAS_PHYSIOLOGY\n  private var quantitative: some View {\n    GalaxySSIHealthAtlasPhysiologyPanel(entryID: entry.id, inputs: $physiologyInputs, language: language,\n      legacyVentilation: (lung || entry.id == "alveoli") ? [simulation.first, simulation.second] : nil)\n  }\n  #endif\n  private var playbackControls: some View {');
// #4435 intentionally replaces playback and adds inline controls. Preserve the
// original renderer block and quantitative invocation rather than freezing its old timer.
const rendererBlock = s => s.slice(s.indexOf('      Text(String(format: t("related_process")'), s.indexOf('      ProgressView(value: simulation.phase)'));
assert.equal(rendererBlock(panel), rendererBlock(expectedPanel).replaceAll("playing = false;", "pause();"));
const quantitativeBlock = s => s.split("  private var quantitative: some View {")[1].split("  private var playbackControls:")[0];
assert.equal(quantitativeBlock(panel), quantitativeBlock(expectedPanel));
assert(panel.includes('mechanismFirst || gasExchange || entry.id == "pancreas" || endocrine != nil || sweat || quantitativeAfterSection'));
assert.equal((panel.match(/GalaxySSIHealthAtlasPhysiologyPanel\(/g) || []).length, 1);
const beforeAt = panel.indexOf('quantitative.accessibilityIdentifier("atlas-quantitative-before-art")');
const mechanismAt = panel.indexOf("GalaxySSIHealthAtlasCirculationView(");
const afterAt = panel.indexOf('quantitative.accessibilityIdentifier("atlas-quantitative-after-art")');
assert(beforeAt < mechanismAt && mechanismAt < afterAt);
assert(research.includes("}, mechanismFirst: true)"));
const expectedResearch = prior("Research").replace("            })\n        case .drugs:", "            }, mechanismFirst: true)\n        case .drugs:");
const physiologyCase = s => s.split("        case .physiology:")[1].split("        case .drugs:")[0];
assert.equal(physiologyCase(research), physiologyCase(expectedResearch));
assert.equal(research.split("  private var aging:")[1], expectedResearch.split("  private var aging:")[1]);
assert(source("Detail").includes("mechanismFirst: usesInlineModels, inline: usesInlineModels"));
const restoreBlock = s => s.split("  func restore(_ text:")[1].split("  var serialized:")[0];
assert.equal(restoreBlock(state).replace('      if let entry = atlas.entry(id), let saved = entries[id] { entries[id] = Self.migrated(saved, entry: entry) }\n', ""),
  restoreBlock(prior("State")).replace("decoded.count <= 300", "decoded.count <= max(300, atlas.entries.count)"));
for (const token of ["text.utf8.count <= 256_000", "entries = decoded.filter { atlas.entry($0.key) != nil }", "entries[id]?.simulation.sanitize(id)",
  "Physiology.restore(id, inputs: entries[id]?.physiologyInputs)"]) assert(state.includes(token));
const tests = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift");
for (const token of ["testResearchMechanismFirstPolicyRetainsStandaloneOrderingAndEntryState", "for entry in atlas.entries", "var research = normal; research.mechanismFirst = true",
  "XCTAssertTrue(research.quantitativeAfterArt", "XCTAssertEqual(normal.quantitativeAfterArt, expectedAfter", "XCTAssertEqual(binding.wrappedValue, saved",
  "restored.restore(state.serialized, atlas: atlas)", "XCTAssertEqual(restored.binding(heart).wrappedValue, before)"]) assert(tests.includes(token), token);
const edited = git(["diff", "--name-only", base, "--", "apps/ios/GalaxySSI"]).toString().trim().split(/\r?\n/).filter(Boolean);
const owned = new Set([swift("SimulationPanel"), swift("Research"), swift("State")]);
// Later explicit per-file port dispositions account for cumulative work, not #4420 behavior.
const laterTargets = new Set(fs.readdirSync(path.join(root, "apps/ios")).flatMap(name => {
  const match = name.match(/^ANDROID_(\d+)_PORT_COVERAGE\.json$/);
  return match && Number(match[1]) > 4420 ? JSON.parse(read("apps/ios/" + name)).files.flatMap(file => file.ios ?? []) : [];
}));
assert(edited.every(file => owned.has(file) || laterTargets.has(file)), "Unattributed later iOS change");
assert([...owned].every(file => edited.includes(file)));
const files = inventory.files.map(file => {
  let kind, ios, note;
  if (file.path.endsWith("HealthAtlasSimulationPanel.kt")) {
    kind = "mechanism-first-layout-with-exclusive-quantitative-placement"; ios = [swift("SimulationPanel")];
    note = "Default-false mechanismFirst plus original gas/pancreatic/endocrine/sweat/non-cell-section policy. Research diagram and playback precede exactly one numerical panel; standalone retains Android ordering. Share the same inputs and legacy lung/alveolar migration. Consolidate duplicate slots and remove the old retinal exclusion that could omit its numerical panel. Mechanism renderers, timers, reset/navigation, formulas and artwork are unchanged. No native layout certification.";
  } else if (file.path.endsWith("HealthBodyAtlasActivity.kt")) {
    kind = "physiology-research-opt-in-and-return-state"; ios = [swift("Research"), swift("State")];
    note = "Only physiology research opts into mechanismFirst. Detail/Simulation uses the default. Entry-local simulation and numerical bindings stay shared. A discovered 300-entry cache cap is extended to max(300, current catalogue count), retaining 256KB and all sanitization, so the 313-entry catalogue can restore after navigation.";
  } else if (file.path.includes("/androidTest/")) {
    kind = "android-device-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"];
    note = "Source fixtures compare layout policy for every catalogue entry, preserve phase/speed/controls across surfaces, isolate child entry state and check full-cache restoration. Source checks assert view order/wiring and unchanged mechanism controls. No Android/XCTest/device render, drill-down gesture or pixel execution.";
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts"); kind = "android-version-only"; ios = []; note = "No iOS version bump, resource changes or IPA.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)));
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const name = "apps/ios/ANDROID_4420_" + suffix + ".json", text = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, name), text); else assert.equal(read(name), text);
}
if (process.argv.includes("--checks")) for (const command of ["check-atlas-related-readings-scope.cjs --checks", "check-body-atlas-portrait-cells.cjs"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4420: four source hashes/dispositions, mechanism-first/default ordering, exclusive numerical slot and bounded full-catalogue restoration source contracts. Not native execution or acceptance.");

// Source/resource contracts; no Swift numerical execution or native UI acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "de63c7dd3c883b8724da0f4366d6e078c1882a75";
const base = "2c8fee1360c730248e2d21c7d4023f020773c6e0";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const prior = name => git(["show", base + ":" + swift(name)]).toString();
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 11);
const inventory = {schema: 1, source: {androidPR: 4436, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const android = git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasModelComparison.kt"]).toString();
for (const token of ["-100.0 * expm1(-model.k10 * hours) / model.k10", "if (model.outward == 0) one else model.at(hours).eliminated / model.k10", "val gap get() = two - one"]) assert(android.includes(token), token);
const model = source("ModelComparison"), distribution = source("Distribution"), panel = source("ComparisonPanel");
for (const token of ["struct CentralAmountHours: Equatable, Sendable", "var gap: Double { two - one }", "-100 * expm1(-model.k10 * hours) / model.k10",
  "model.outward == 0 ? one : model.at(hours)!.eliminated / model.k10", "CentralAmountHours(one: one, two: two)",
  "number(model.hours, locale), number(total.one, locale)", "number(total.two, locale), number(total.gap, locale)",
  "includeTotals: Bool = false", 'if includeTotals { lines += [totals(model, locale: locale, text: t), t("compare_total_basis")] }']) assert(model.includes(token), token);
const pointKernel = s => s.split("  func at(_ hours: Double)")[1].split("enum GalaxySSIHealthAtlasComparisonText")[0];
assert.equal(pointKernel(model), pointKernel(prior("ModelComparison")), "Point readout/envelope and cached curves are unchanged");
assert.equal(distribution.split("struct GalaxySSIHealthAtlasDrugState")[0], prior("Distribution").split("struct GalaxySSIHealthAtlasDrugState")[0], "Do not modify the distribution numerical kernel");
for (const token of ["var showComparisonTotals = false", "showComparisonTotals ? 1 : 0", "values.count == 5 || (7...8).contains(values.count)",
  "values.count >= 7 || mode != .comparison", "if values.count >= 7", "let totals = values.count == 8 ? values[7] : 0",
  "guard (0...1).contains(totals)", "showComparisonTotals: totals == 1"]) assert(distribution.includes(token), token);
assert.equal(panel.split("  private var chart:")[1], prior("ComparisonPanel").split("  private var chart:")[1], "Existing plot/cursor/rendering remain unchanged");
for (const token of ["@Binding var showTotals: Bool", "DisclosureGroup(isExpanded: $showTotals)", '"atlas-comparison-totals-toggle"',
  '"atlas-comparison-totals"', '"atlas-comparison-totals-value"', "ComparisonText.totals(model", 't("compare_total_basis")', "Button { model = .standard }"])
  assert(panel.includes(token), token);
assert(!panel.includes("Timer")); assert(!panel.includes(".id(model"));
assert(source("Research").includes("showTotals: drugState.showComparisonTotals"));
for (const name of ["AgentContext", "AgentHandoff"]) {
  const current = source(name);
  assert(current.includes("includeTotals: drugs.showComparisonTotals"));
  assert.equal(current.replaceAll(" includeTotals: drugs.showComparisonTotals,", ""), prior(name), "Only the selected comparison receives visible totals: " + name);
}
// #4437 changes research navigation, not the cumulative model or guided clock.
assert.equal(source("ChapterClock"), prior("ChapterClock"));
assert.equal(source("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1], prior("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1]);
const personalValues = s => s.split("struct GalaxySSIHealthAtlasValues:")[1];
assert.equal(personalValues(source("Detail")), personalValues(prior("Detail")));
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasCumulativeComparison.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), new Set(["title", "result", "basis"].map(k => "health_atlas_compare_total_" + k)));
  assert.equal([...table.get("health_atlas_compare_total_result").matchAll(/%\d+\$@/g)].length, 4);
}
assert(source("").includes('table: "AtlasCumulativeComparison"'));
assert(read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj").includes("C44360000000000000000001 /* AtlasCumulativeComparison.strings in Resources */"));
const tests = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasModelComparisonTests.swift");
const androidTests = git(["show", sha + ":apps/android/app/src/test/java/com/galaxyssi/chat/HealthAtlasModelComparisonTest.kt"]).toString();
for (const number of ["219.6577427940722", "329.6799539643607", "-110.0222111702885", "148.0005412446694"]) { assert(tests.includes(number)); assert(androidTests.includes(number)); }
for (const token of ["testCumulativeValuesMatchThePinnedAugmentedMatrixFixtures", "XCTAssertGreaterThanOrEqual(current.one, previous.one)",
  "XCTAssertGreaterThanOrEqual(current.two, previous.two)", "if scenario == .control { XCTAssertEqual(current.gap, 0) }",
  "testCumulativeDisclosureRestoresAndLegacySelectionsDefaultToClosed", "State.restore([2, 30, 15, 10, 16, 2, 23])", "for flag in [-1, 2, Int.max]",
  "testCumulativeContextIsIncludedOnlyForTheExpandedSelectedComparison", 'expanded.contains(t("compare_total_basis"))',
  'XCTAssertFalse(collapsed.contains(t("compare_total_basis")))', "[GalaxySSIHealthAtlasDrugState.Mode.single, .two]", "restored.restore(state.serialized, atlas: atlas)"])
  assert(tests.includes(token), token);
const targets = {
  "HealthAtlasModelComparison.kt": ["ModelComparison"], "HealthAtlasComparisonPanel.kt": ["ComparisonPanel", "ModelComparison"],
  "HealthAtlasDistribution.kt": ["Distribution"], "HealthAtlasResearchPanel.kt": ["Research", "ComparisonPanel"],
  "HealthAtlasAgentContext.kt": ["AgentContext", "AgentHandoff"]
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path); let kind, ios, note;
  if (targets[name]) {
    kind = "native-cumulative-comparison"; ios = targets[name].map(swift);
    note = "Exact expm1/control and eliminated/k10 integral for fixed synthetic presets; signed gap in percentage-hours, not concentration AUC or clinical exposure. In-place optional disclosure shares scenario/time bindings, persists as bounded eighth integer, restores five/seven legacy forms closed, and enters both Agent build branches only when expanded and selected. Existing point/kernel/chart and unrelated model modes are preserved.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasCumulativeComparison.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasCumulativeComparison.strings", swift(""), "apps/ios/GalaxySSI.xcodeproj/project.pbxproj", "apps/ios/tools/import-body-atlas-regional-text.cjs"];
    note = "Three exact English/Chinese labels/results/scope pairs from pinned XML; four ordered formatted arguments and Xcode membership.";
  } else if (file.path.includes("/androidTest/") || file.path.includes("/test/")) {
    kind = "android-test-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasModelComparisonTests.swift", "apps/ios/tools/check-atlas-cumulative-comparison-scope.cjs"];
    note = "Independent augmented-matrix constants, all-quarter monotonicity/control equality, five/seven/eight restoration, invalid disclosure flags and selected-visible-only bilingual Agent fixtures added as Swift source. No Kotlin/JVM, XCTest, device, in-place identity or pixel tests executed. Numerical constants are source references, not proof of running Swift.";
  } else if (name === "build.gradle.kts") {
    kind = "android-version-only"; ios = []; note = "No iOS version bump or IPA.";
  } else {
    assert.equal(file.path, "docs/architecture/android-body-atlas.md"); kind = "architecture-reference"; ios = ["apps/ios/ANDROID_4436_PORT_STATUS.md"];
    note = "Native scope and source-only verification documented separately from Android's reported execution.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const file = "apps/ios/ANDROID_4436_" + suffix + ".json", content = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --cumulative-comparison-4436 --check", "check-atlas-guided-function-scope.cjs --checks"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4436: eleven original file hashes/dispositions, integral/state/disclosure/context source contracts and three bilingual pairs. No Swift numerical execution or native acceptance.");

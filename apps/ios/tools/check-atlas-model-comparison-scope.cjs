// Pinned production/source contracts only, not numerical execution of Swift or native UI acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "3327febe8406fb5ee5cf30dc0734ef6c4e2cbdcc";
const base = "1a56bcb91185a597389bb20cc49f22bd395aff0b";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const original = name => git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"]).toString();
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 11);
const inventory = {schema: 1, source: {androidPR: 4434, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const model = source("ModelComparison"), panel = source("ComparisonPanel"), distribution = source("Distribution"), research = source("Research");
for (const token of ["CONTROL(0, 0)", "EXCHANGE(30, 15)", "FASTER(100, 40)", "elimination = 10", "val quarterHours: Int = 16",
  "quarterHours in 0..192", "hours.isFinite() && hours in 0.0..48.0", "val centralGap get() = two.central - one", "scenarios.minOf { it.central }", "scenarios.maxOf { it.central }"])
  assert(original("ModelComparison").includes(token), token);
for (const token of ['case control, exchange, faster', 'case .control: rates = (0, 0)', 'case .exchange: rates = (30, 15)', 'case .faster: rates = (100, 40)',
  'return GalaxySSIHealthAtlasDistribution(outward: rates.0, returning: rates.1, elimination: 10)!', 'init?(scenario: Scenario = .exchange, quarterHours: Int = 16)',
  'guard (0...192).contains(quarterHours)', 'guard hours.isFinite, (0...48).contains(hours)', 'Scenario.allCases.map { $0.distribution.at(hours)! }',
  '100 * exp(-scenario.distribution.k10 * hours)', 'two: values[scenario.rawValue]', 'low: values.map(\\.central).min()!', 'high: values.map(\\.central).max()!',
  'var centralGap: Double { two.central - one }', 'private static let profiles: [[Point]]', '(0...192).map { model.at(Double($0) / 4)! }',
  'Self.profiles[scenario.rawValue]', 'https://pmc.ncbi.nlm.nih.gov/articles/PMC6977398/']) assert(model.includes(token), token);
assert(!model.includes("abs(")); assert(!model.includes("GalaxySSIHealthRecords")); assert(!panel.includes("GalaxySSIHealthRecords"));
const beforeDistribution = git(["show", base + ":" + swift("Distribution")]).toString();
assert.equal(distribution.split("struct GalaxySSIHealthAtlasDrugState")[0], beforeDistribution.split("struct GalaxySSIHealthAtlasDrugState")[0], "Two-compartment numerical kernel is unchanged");
for (const token of ['case single, two, comparison', 'var comparison = GalaxySSIHealthAtlasModelComparison.standard',
  'distribution.quarterHours, comparison.scenario.rawValue, comparison.quarterHours', 'values.count == 5 || values.count == 7',
  'values.count == 7 || mode != .comparison', 'Scenario(rawValue: values[5])', 'quarterHours: values[6]',
  'else { comparison = .standard }', 'Self(mode: mode, distribution: distribution, comparison: comparison)']) assert(distribution.includes(token));
for (const token of ['"atlas-drug-model"', 't("drug_single"), t("drug_two"), t("compare_title")', 'drugState.wrappedValue.mode == .comparison',
  'GalaxySSIHealthAtlasComparisonPanel(model: drugState.comparison', 'else if drugState.wrappedValue.mode == .two',
  'GalaxySSIHealthAtlasDistributionPanel(model: drugState.distribution', 'selection.elimination.halfLife', 'selection.elimination.elapsed']) assert(research.includes(token));
for (const token of ['"atlas-comparison-case"', '"atlas-comparison-chart"', '"atlas-comparison-rates"', '"atlas-comparison-time"',
  '"atlas-comparison-elapsed"', '"atlas-comparison-result"', '"atlas-comparison-range"', '"atlas-comparison-evidence"',
  '"atlas-comparison-reset"', '"atlas-source-comparison-equations"', '"atlas-source-comparison-validation"',
  'model = .standard', 'in: 0...192, step: 1', 'model.samples', 'samples[index].high', 'samples[index].low', 'samples.indices.reversed()',
  '42.0 / 255', 'width("100%") + 12', 'size.width - width("48") / 2 - 4', 'size.height - axisFontSize * 2', '144 + 3 * axisFontSize',
  '[0.0, 50, 100]', '[0.0, 24, 48]', 'StrokeStyle(lineWidth: 2.5, dash: dashed ? [6, 4] : [])', 'width: 7, height: 7',
  'series(comparisonColor, dashed: false) { $0.two.central }', 'series(GalaxySSIHealthTheme.accent, dashed: true) { $0.one }',
  '.accessibilityHidden(true)', '.fixedSize(horizontal: false, vertical: true)', '.frame(maxWidth: .infinity, minHeight: 44)']) assert(panel.includes(token), token);
assert(!panel.includes("Timer")); assert(!panel.includes("URLSession")); assert(!panel.includes(".id(model"));
for (const token of ['chartColor(0x8D4D00, 0xFFBD73)', 'chartColor(0x8E8E93, 0xA5ABB6)', 'chartColor(0xE5E5EA, 0x343841)', 'let drawing = context']) assert(panel.includes(token));
for (const [folder, values] of [["values", ["#8D4D00", "#006C56"]], ["values-night", ["#FFBD73", "#87E6BF"]]]) {
  const palette = git(["show", sha + ":apps/android/app/src/main/res/" + folder + "/health_overview_colors.xml"]).toString();
  for (const value of values) assert(palette.includes(value));
}
for (const name of ["AgentContext", "AgentHandoff"]) {
  const text = source(name), drugs = text.split(/\n[ \t]*case \.drugs:/)[1].split(/\n[ \t]*case \.aging:/)[0];
  assert(drugs.indexOf("mode == .comparison") < drugs.indexOf("mode == .two"));
  assert(drugs.includes("GalaxySSIHealthAtlasComparisonText.context(drugs.comparison"));
  assert(drugs.includes("drugs.distribution.context")); assert(drugs.includes('t("elimination_assumptions")'));
}
const beforeHandoff = git(["show", base + ":" + swift("AgentHandoff")]).toString();
assert.equal(source("AgentHandoff").split("struct GalaxySSIHealthAtlasAsk:")[1], beforeHandoff.split("struct GalaxySSIHealthAtlasAsk:")[1], "Existing confirmation/handoff behavior is unchanged");
const keys = ["title", "scope", "control", "exchange", "faster", "legend", "summary", "range", "evidence", "limit", "reference"].map(k => "health_atlas_compare_" + k);
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasModelComparison.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), new Set(keys));
  assert.equal((table.get("health_atlas_compare_summary").match(/%\d+\$@/g) || []).length, 3);
  assert.equal((table.get("health_atlas_compare_range").match(/%\d+\$@/g) || []).length, 2);
}
assert(source("").includes('table: "AtlasModelComparison"'));
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ["GalaxySSIHealthAtlasModelComparison.swift in Sources", "GalaxySSIHealthAtlasComparisonPanel.swift in Sources", "GalaxySSIHealthAtlasModelComparisonTests.swift in Sources", "AtlasModelComparison.strings in Resources"]) assert(pbx.includes(token));
const tests = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasModelComparisonTests.swift");
for (const token of ["31.31146654418996", "23.34020536954366", "-35.72053805937397", "0...192", "model.samples[quarter]", "point.two.values.reduce(0, +)",
  "[2, 63, 20, 10, 41, 2, 23]", "State.restore([1, 63, 20, 10, 41])", 'for language in ["en", "zh-Hans"]',
  'prompt.contains(publicContext)', 'XCTAssertFalse(prompt.contains(t("elimination_assumptions")))', 'restored.restore(state.serialized, atlas: atlas)']) assert(tests.includes(token));
const paths = {
  HealthAtlasModelComparison: [swift("ModelComparison")], HealthAtlasComparisonPanel: [swift("ComparisonPanel"), swift("ModelComparison")],
  HealthAtlasDistribution: [swift("Distribution")], HealthAtlasResearchPanel: [swift("Research"), swift("ComparisonPanel")],
  HealthAtlasAgentContext: [swift("AgentContext"), swift("AgentHandoff")]
};
const files = inventory.files.map(file => {
  let kind, ios, note;
  if (file.path.includes("/src/main/java/")) {
    ios = paths[path.basename(file.path, ".kt")]; assert(ios, file.path); kind = "native-synthetic-comparison-integration";
    note = "Freeze paired rates and shared initial amount/elimination, preserve signed central difference and three-preset envelope, render 193 quarter-hour samples with original axes/colors/dashes/alpha/marker and text, independently restore legacy five/new seven inputs, and include only the selected public model in both Agent context branches. Reuse unchanged two-compartment kernel; do not claim native numerical or experimental validation.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasModelComparison.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasModelComparison.strings", swift("")];
    note = "Eleven exact English/Chinese pairs, including explicit synthetic/evidence/non-confidence-interval limits and equation/validation links, registered in Xcode.";
  } else if (/\/src\/(?:test|androidTest)\//.test(file.path)) {
    kind = "android-test-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasModelComparisonTests.swift"];
    note = "Native test SOURCE covers pinned four-hour fixture, all scenario/time profiles, no-exchange reduction, conservation/common envelope, malformed and legacy state, independent reset/restoration and bilingual selected-only Agent context. Android/XCTest/render/gesture/pixel/VoiceOver tests are not run.";
  } else if (file.path.startsWith("docs/")) {
    kind = "ios-port-scope-and-evidence-documentation"; ios = ["apps/ios/ANDROID_4434_PORT_STATUS.md"];
    note = "Document normalized central amount, three fixed joint scenarios, visible assumptions, distinction between numerical and experimental validation, no patient prediction and remaining native acceptance gaps. Android architecture document is not edited.";
  } else {
    assert.equal(file.path, "apps/android/app/build.gradle.kts"); kind = "android-version-only"; ios = []; note = "No iOS version bump, Android/Desktop edits or IPA.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const name = "apps/ios/ANDROID_4434_" + suffix + ".json", text = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, name), text); else assert.equal(read(name), text);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --model-comparison-4434 --check", "check-atlas-mechanism-first-scope.cjs --checks"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4434: eleven pinned files, eleven bilingual pairs, synthetic comparison/model-state/plot/context source contracts. No native execution or acceptance.");

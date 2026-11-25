// Source contracts only. No native compilation, tests or pixels are produced here.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const crypto = require("node:crypto"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "071062afe8059506c9958906f708780d80437f55";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const source = name => read(swift(name));
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 7);
const inventory = {schema: 1, source: {androidPR: 4417, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const state = source("State"), artwork = source("Artwork"), detail = source("Detail"), card = source("WholeBodyActions");
const trend = read("apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift");
for (const token of ['@Published var wholeFocus = "heart"', 'atlas.entry(wholeFocus) ?? atlas.entry("heart")',
  'guard atlas.entry(id) != nil else { return }', 'wholeFocus = id', 'wholeFocus = entry.id',
  'next.revealTrend = showTrend && tab == .values && !GalaxySSIHealthAtlasMetrics.forEntry(entry.id).isEmpty',
  'var revealTrend: Bool?', '"galaxyssi.health.atlas.whole-focus.v1"',
  'state.wholeFocus = content.entry(savedWholeFocus)?.id ?? "heart"',
  '.onChange(of: state.wholeFocus) { savedWholeFocus = $0 }',
  'entry: kind == "whole" ? state.wholeEntry(in: atlas) : nil',
  'state.openWholeBody(focus, tab: tab, showTrend: trend)', 'quickTarget = focus.id']) assert(state.includes(token), token);
assert(!state.includes('ForEach(["heart", "cell-pancreatic-beta-cell"]'));
assert(state.indexOf("GalaxySSIHealthAtlasWholeBodyActions(") > state.indexOf("GalaxySSIHealthAtlasArtwork(atlas: atlas, entry: nil"));
assert(artwork.includes('if entry == nil, let id { state.rememberWholeSelection(id, in: atlas) }'));
for (const token of ['"atlas-whole-selection"', '"atlas-whole-structure-" + entry.id', '"atlas-whole-actions"',
  '"atlas-whole-action-" + id', 'symbol: "chart.bar", tab: .values, showTrend: true, enabled: hasMetrics',
  'symbol: "person.crop.rectangle", tab: .values', 'symbol: "square.3.layers.3d", tab: .structure',
  'UIImage(named: asset)', '.frame(width: 38, height: 38)', '@ScaledMetric(relativeTo: .caption)',
  '.fixedSize(horizontal: false, vertical: true)', 'minHeight: 48', 'entry.systems.compactMap(atlas.entry)']) assert(card.includes(token), token);
for (const token of ['if tab != .values { selection.wrappedValue.revealTrend = false }',
  'Binding(get: { selection.revealTrend == true }, set: { selection.revealTrend = $0 })']) assert(detail.includes(token));
assert.equal((detail.match(/revealAtlasTrend: revealTrend/g) || []).length, 2);
for (const token of ['ScrollViewReader { proxy in', 'revealAtlasTrend: Binding<Bool>? = nil', 'self.revealAtlasTrend = revealAtlasTrend',
  '.id("atlas-personal-chart")', '.accessibilityIdentifier("atlas-personal-blocked")',
  '.onChange(of: canRevealAtlasTrend)', '.onChange(of: revealAtlasTrend?.wrappedValue)',
  'scene == .active && allowed && !changed && !error &&', 'trend?.minimum != nil && trend?.maximum != nil',
  'guard revealAtlasTrend?.wrappedValue == true, canRevealAtlasTrend else { return }',
  'DispatchQueue.main.async', 'proxy.scrollTo("atlas-personal-chart", anchor: .center)',
  'if let revealAtlasTrend { revealAtlasTrend.wrappedValue = false }']) assert(trend.includes(token), token);
const priorTrend = git(["show", "27cae906cbd1e9948d59e6191142b098178b927a:apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift"]).toString();
// Navigation only: permission/read/filter/invalidation behavior must not change.
const reload = s => s.split("  private func reload() {")[1].split("  private var trendSpec:")[0];
assert.equal(reload(trend), reload(priorTrend));
for (const token of ['allowed = archive.derivesOverview == true', 'guard allowed else { devices = []; resetOrigins(); return }',
  'trend = spec.chart(current)', 'catch { allowed = false; error = true; resetOrigins() }',
  'if phase == .active { reload() }', 'else { trend = nil; selected = nil; focusedDay = nil; allowed = false;',
  'UIApplication.protectedDataWillBecomeUnavailableNotification']) assert(trend.includes(token), token);
assert(!card.includes("TeachingModel")); assert(!card.includes("records.load"));
for (const locale of ["en", "zh-Hans"]) {
  const table = new Map([...read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasWholeActions.strings").matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(new Set(table.keys()), new Set(["health_atlas_quick_metrics", "health_atlas_quick_trend"]));
  for (const value of table.values()) assert(value);
}
assert(source("").includes('table: "AtlasWholeActions"'));
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ['C44170000000000000000001 /* AtlasWholeActions.strings in Resources */',
  'C44170000000000000000005 /* GalaxySSIHealthAtlasWholeBodyActions.swift in Sources */']) assert(pbx.includes(token));
const dispositions = {
  "HealthBodyAtlasActivity.kt": {kind: "whole-body-focus-navigation-and-public-agent-context", ios: [swift("State"), swift("Artwork"), swift("Detail")],
    note: "Remember valid whole-body hotspot/menu focus, default heart, scene-store focus, offer retained focus actions and pass only public structure context to Ask Agent. Existing entry selections and metrics remain scoped."},
  "HealthAtlasUi.kt": {kind: "illustrated-whole-body-quick-actions", ios: [swift("WholeBodyActions")],
    note: "38-point actual structure art or icon fallback, name/system context, structure/metrics/trend buttons, disabled trend without metrics, three equal columns, scalable wrapping labels and minimum 48-point hit heights. No native pixel/large-label certification."},
  "HealthAtlasMeasurements.kt": {kind: "permission-preserving-deferred-chart-reveal", ios: [swift("Detail"), "apps/ios/GalaxySSI/GalaxySSIHealthTrendView.swift"],
    note: "Route the existing entry metric to the existing record-backed trend; only scroll when a permitted foreground chart exists. Recheck readiness after layout dispatch and consume request. Keep original permission/read/filter/invalidation behavior byte-identical; missing/restricted data has no teaching fallback. Empty iOS trends retain their native empty state, not a fabricated chart."},
  "HealthBodyAtlasDeviceTest.kt": {kind: "android-device-reference-not-executed", ios: ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift"],
    note: "Source state fixtures for focus/fallback, actions, disabled unsupported trend, retained controls/window, restoration and public prompt scoping; source assertions preserve privacy checks and deferred chart wiring. Android/XCTest/device/pixel/VoiceOver tests not run."},
  "build.gradle.kts": {kind: "android-version-only", ios: [], note: "No iOS version bump, native build or IPA."}
};
const files = inventory.files.map(file => {
  const disposition = file.path.includes("/res/") ? {kind: "exact-bilingual-resource-delta", ios: ["apps/ios/GalaxySSI/en.lproj/AtlasWholeActions.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasWholeActions.strings"],
    note: "Two exact English/Chinese resource pairs imported from original XML and registered in Xcode."} : dispositions[path.basename(file.path)];
  assert(disposition, file.path); for (const target of disposition.ios) assert(fs.existsSync(path.join(root, target)));
  return {source: file.path, sourceSHA256: file.sha256, ...disposition};
});
for (const [name, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const file = "apps/ios/ANDROID_4417_" + name + ".json", content = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --whole-actions-4417 --check", "check-atlas-completion-teaching-scope.cjs"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4417: seven original hashes/dispositions, two bilingual pairs, focus/action/scroll/privacy source wiring verified. No native execution or acceptance.");

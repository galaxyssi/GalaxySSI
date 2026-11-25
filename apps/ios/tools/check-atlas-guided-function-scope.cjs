// Source and packaging contracts only. Never executes Swift or certifies native UI.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "83188e7ce30a174e766e68fcf4db6f751a046d7a";
const base = "90abe3736bcf95a4ee2891e05d21bcc2a287842e";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 39);
const inventory = {schema: 1, source: {androidPR: 4435, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const clock = source("ChapterClock"), player = source("FunctionPlayer"), panel = source("SimulationPanel"), detail = source("Detail"), state = source("State");
const androidClock = git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasChapterClock.kt"]).toString();
for (const token of ["STEP_MS = 5_000L", "if (elapsed == length) elapsed = 0", "startedAt = null", "length - elapsed"]) assert(androidClock.includes(token), token);
for (const token of ["stepMilliseconds: Int64 = 5_000", "systemUptime", "subtractingReportingOverflow", "elapsed + min(length - elapsed, active)",
  "if elapsed == length { elapsed = 0 }", "startedAt = nil", "phase.isFinite", "if current == length { pause(now) }", "position(now) % Self.stepMilliseconds",
  "changedAt = now", "owner = id", "if owner == id"]) assert(clock.includes(token), token);
assert(!clock.includes("Date(")); assert(!player.includes("story.durationMs")); assert(!player.includes("lastTick"));
for (const token of ["chapters: story.chapters.count", "clock.resume(now)", "clock.pause(now); publish(clock.sample(now))", "playback.owner == playbackID",
  "pause(at: playback.changedAt)", "story.startOf(story.chapter(position))", ".onTapGesture", ".accessibilityAction(named:", "if !previewPresented { toggle() }",
  ".onDisappear { pause() }", "playback.release(playbackID); commit()"])
  assert(player.includes(token), token);
for (const token of ['"atlas-function-outline-stage-"', "seek(story.startOf(index))"]) assert(source("FunctionPlaybackMenu").includes(token));
assert(source("FunctionScene").includes("if showTitle"));
assert(source("FunctionScene").includes("story.chapters.map { t($0.caption) }"));
assert(player.includes('onChange(of: scene) { _ in pause() }'));
assert(player.includes('onChange(of: previewPresented) { if $0 { pause() } }'));
const functionPanel = source("FunctionPanel");
for (const token of ["!(2...3).contains(choices.count)", "story.choiceTitle", 'playbackID: "function|" + entryID + "|" + story.id']) assert(functionPanel.includes(token));
for (const token of ["var modelsExpanded: Bool?", "entry.kind == .system || entry.kind == .organ", "next.tab == .simulation",
  "next.tab = .function; next.modelsExpanded = true", "Self.migrated(saved, entry: entry)", "Self.migrated($0, entry: entry)", "var next = functionSnapshot(entry)"])
  assert(state.includes(token), token);
for (const token of ["GalaxySSIHealthAtlasState.detailTabs", "DisclosureGroup(isExpanded:", "selection.wrappedValue.modelsExpanded = expanded",
  'state.playback.claim("models-disclosure|" + entry.id)', '"atlas-inline-models"', '"atlas-function-principle-toggle"',
  '"atlas-function-principle"', 'Text(t("inline_models"))', "inline: usesInlineModels", ".environmentObject(state.playback)", "state.functionSnapshot(entry)"])
  assert(detail.includes(token), token);
assert(source("Research").includes(".environmentObject(state.playback)"));
for (const token of ["var inline = false", "chapters: model.stages.count", "if !inline {", "clock.resume(now); inlineClock = clock",
  "pause(at: playback.changedAt)", "clock.pause(now); simulation.phase = clock.sample(now)", "playback.owner == playbackID",
  "simulation.speed / 8", ".onDisappear { pause() }", "physiologyInputs = nil"])
  assert(panel.includes(token), token);
assert(!panel.includes("playing = false; simulation.selectStage"));
assert(!panel.includes("playing = false; structure ="));
// Preserve all existing model/rendering bodies and original story catalogue/art assets.
for (const name of ["FunctionArtwork", "Physiology"]) {
  assert.equal(source(name), git(["show", base + ":" + swift(name)]).toString(), name + " changed unexpectedly");
}
const previous = name => git(["show", base + ":" + swift(name)]).toString();
// #4439 adds an immutable catalogue overlay; legacy selection/cache behavior stays frozen.
assert.equal(source("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1], previous("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1]);
assert.equal(source("Distribution").split("struct GalaxySSIHealthAtlasDrugState")[0], previous("Distribution").split("struct GalaxySSIHealthAtlasDrugState")[0]);
const pointKernel = s => s.split("  func at(_ hours: Double)")[1].split("enum GalaxySSIHealthAtlasComparisonText")[0];
assert.equal(pointKernel(source("ModelComparison")), pointKernel(previous("ModelComparison")));
const withoutTotals = s => s.replaceAll(" includeTotals: drugs.showComparisonTotals,", "");
const originalContext = git(["show", base + ":" + swift("AgentContext")]).toString();
assert.equal(withoutTotals(source("AgentContext")).replace("                     inlineModels: Bool = false,\n", "")
  .replace("screen.includesPhysiology || (screen == .function && inlineModels)", "screen.includesPhysiology"), originalContext);
const originalHandoff = git(["show", base + ":" + swift("AgentHandoff")]).toString();
assert.equal(withoutTotals(source("AgentHandoff"))
  .replace('    let inlineModels = !research && selection.tab == .function && selection.modelsExpanded == true &&\n      (entry?.kind == .system || entry?.kind == .organ)\n', "")
  .replace("screen.includesPhysiology || inlineModels", "screen.includesPhysiology")
  .replace("function: function, inlineModels: inlineModels,", "function: function,")
  .replaceAll("!research && (selection.tab == .simulation || inlineModels)", "!research && selection.tab == .simulation"), originalHandoff);
assert(detail.includes("if $0 { state.playback.pause() }"));
assert(source("Research").includes("if $0 { state.playback.pause() }"));
assert(clock.includes("previous?(now)")); assert(clock.includes("callback?(changedAt)"));
for (const locale of ["en", "zh-Hans"]) {
  const text = read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasGuidedFunction.strings");
  assert.equal([...text.matchAll(/^"health_atlas_/gm)].length, 2);
  for (const key of ["health_atlas_function_outline", "health_atlas_inline_models"]) assert(text.includes('"' + key + '" = "'));
}
assert(source("FunctionText").includes('table: "AtlasGuidedFunction"'));
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ["AtlasGuidedFunction.strings in Resources", "GalaxySSIHealthAtlasChapterClock.swift in Sources", "GalaxySSIHealthAtlasChapterClockTests.swift in Sources"]) assert(pbx.includes(token));
const tests = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasChapterClockTests.swift");
for (const token of ["for count in 1...10", "clock.sample(boundary - 1)", "clock.sample(boundary)", "clock.nextStepIn(10_000), 3_000",
  "clock.sample(123_456), 0.8", "clock.sample(132_000), 0", "lesson.pause(group.changedAt)", "clock.seek(.nan)", "clock.sample(999)"])
  assert(tests.includes(token), token);
assert(read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift").includes("testGuidedFunctionMigratesLegacySimulationAndPreservesEveryEntrySelection"));
const targetMap = {
  "HealthAtlasChapterClock.kt": ["ChapterClock"], "HealthAtlasFunctionPlayer.kt": ["FunctionPlayer", "FunctionPanel", "FunctionText"],
  "HealthAtlasSimulationPanel.kt": ["SimulationPanel", "Research"], "HealthAtlasUi.kt": ["Detail", "FunctionPlayer"],
  "HealthBodyAtlasActivity.kt": ["Detail", "State", "FunctionPanel", "ChapterClock", "AgentContext", "AgentHandoff"]
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path); let kind, ios, note;
  if (targetMap[name]) {
    kind = "native-guided-function-behavior"; ios = targetMap[name].map(swift);
    note = "Five-second monotonic chapter clock with fractional pause/resume, accessible artwork toggle and complete localized seekable transcript; three system/organ tabs, remembered inline models and legacy destination migration; mutually exclusive playback. Preserve existing numerical bindings, renderer bodies, research, personal metrics and sources. SwiftUI sampling is 30Hz for lessons and 10Hz for inline models; reduced motion publishes only chapter transitions plus precise pause snapshots. This is not Android callback scheduling or native visual certification.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasGuidedFunction.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasGuidedFunction.strings", swift(""), swift("FunctionText"), "apps/ios/tools/import-body-atlas-regional-text.cjs", "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"];
    note = "Exactly two original English/Chinese labels from the pinned XML delta; native variant group and language lookup registered.";
  } else if (file.path.includes("/androidTest/") || file.path.includes("/test/")) {
    kind = "android-test-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasChapterClockTests.swift", "apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift", "apps/ios/tools/check-atlas-guided-function-scope.cjs"];
    note = name + ": original navigation/retention/clock assertions reviewed as source references. iOS source fixtures cover chapter boundaries, remaining time, pause/seek/replay, handoff timestamp, full-catalogue migration and bilingual captions; source contracts check same-scroll inline wiring and preservation of existing model modules. No Android device tests, XCTest, UI instance identity, pixels, tap timing or VoiceOver execution performed.";
  } else if (name === "build.gradle.kts") {
    kind = "android-version-only"; ios = []; note = "No iOS version bump or IPA in this port.";
  } else {
    assert.equal(file.path, "docs/architecture/android-body-atlas.md"); kind = "architecture-reference"; ios = ["apps/ios/ANDROID_4435_PORT_STATUS.md"];
    note = "Document native behavior, cumulative dependency and verification limits without claiming runtime or screenshot acceptance.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === "native-guided-function-behavior").length, 5);
assert.equal(files.filter(f => f.kind === "android-test-reference-not-executed").length, 30);
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const file = "apps/ios/ANDROID_4435_" + suffix + ".json", content = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --guided-function-4435 --check", "check-atlas-model-comparison-scope.cjs --checks", "check-body-atlas-function-player.cjs", "check-atlas-function-context.cjs"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4435: 39 original file hashes/dispositions; chapter clock, transcript, inline navigation, migration and resource source contracts. Not Swift compilation or native execution.");

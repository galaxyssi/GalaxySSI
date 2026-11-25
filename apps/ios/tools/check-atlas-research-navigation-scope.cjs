// Source/packaging contracts only; this does not run Swift or validate native scroll pixels.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "dbbd6554d7cd632c6eb99f705e5a4b38ff42a3cb";
const base = "9018d27befa6e393330b3502a8020b176a538b70";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift";
const source = name => read(swift(name));
const prior = name => git(["show", base + ":" + swift(name)]).toString();
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 19);
const inventory = {schema: 1, source: {androidPR: 4437, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const android = git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthBodyAtlasActivity.kt"]).toString();
for (const token of ["inlineModels && researchTopic == HealthAtlasResearchTopic.PHYSIOLOGY", "mechanismFirst = true, inline = true",
  "listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING)", "scrollY = researchReturnScroll", "topics[index].name.lowercase(Locale.ROOT)",
  "researchReturnScroll = scroller?.scrollY ?: 0", 'tag = "atlas-source-physiology"']) assert(android.includes(token), token);
const state = source("State"), detail = source("Detail"), research = source("Research"), scroll = source("ScrollAnchor");
for (const token of ["var researchPresented: Bool?", "var researchReturnScroll: Double?", "usesInlineModels(entry) ? [.drugs, .aging] : Research.allCases",
  "next.research = Self.usesInlineModels(entry) ? .drugs : .physiology", "next.researchReturnScroll = Self.safeScroll(returnScroll)",
  "next.researchPresented = true", "next.researchPresented = false", "next.researchPresented == true, next.research == .physiology",
  "next.tab = .function; next.modelsExpanded = true", "value.isFinite ? min(1_000_000, max(0, value)) : 0"])
  assert(state.includes(token), token);
const openResearch = state.split("  func openResearch(")[1].split("  func closeResearch(")[0];
assert(openResearch.indexOf("playback.pause()") < openResearch.indexOf("var next = functionSnapshot(entry)"));
assert(openResearch.indexOf("functionSnapshot(entry)") < openResearch.indexOf("next.researchPresented = true"));
assert(!openResearch.includes("physiologyInputs =")); assert(!openResearch.includes("simulation ="));
const restore = s => s.split("  func restore(_ text:")[1];
assert.equal(restore(state), restore(prior("State")), "Existing cache decoding bounds and all sanitizers are retained");
for (const token of ["selection.wrappedValue.researchPresented == true", "state.closeResearch(entry)",
  "state.openResearch(entry, returnScroll: scrollMemory.offset)", "if tab == .function { scrollMemory.restore(0) }",
  "GalaxySSIHealthAtlasScrollAnchor(memory: scrollMemory, revision: scrollMemory.revision)",
  "selection.wrappedValue.researchReturnScroll { scrollMemory.restore(offset) }", "NavigationLink(isActive: research)",
  "mechanismFirst: usesInlineModels, inline: usesInlineModels", '"atlas-source-physiology"',
  't(usesInlineModels ? "targeted_research" : "research")'])
  assert(detail.includes(token), token);
const inlineBody = detail.split("state.playback.claim(\"models-disclosure|\" + entry.id)")[1].split('Text(t("inline_models"))')[0];
assert(inlineBody.includes("simulationPanel") && !inlineBody.includes("mechanismSource"));
assert(source("SimulationPanel").split("private var referenceNotes:")[1].includes('"atlas-source-physiology"'));
for (const token of ["GalaxySSIHealthAtlasState.researchTopics(entry)", "GalaxySSIHealthAtlasCompactTabs(options: topics, selection: topic",
  'key: { $0.rawValue }, identifier: "atlas-research-tab"', "switch topic.wrappedValue", "topics.contains(selection.wrappedValue.research)",
  "state.openNumericalModel(entry); state.closeResearch(entry); dismiss()", '.navigationTitle(title)', '"targeted_research"'])
  assert(research.includes(token), token);
assert.equal(research.split("  private var drugs:")[1], prior("Research").split("  private var drugs:")[1], "Drug, comparison and aging modules are not rewritten");
for (const token of ["UIViewRepresentable", "private weak var scroll: UIScrollView?", "view.superview", "ancestor = current.superview",
  "!(current is UIScrollView)", "containing.observe(\\.contentOffset", "containing.observe(\\.contentSize", "DispatchQueue.main.async",
  "scroll.isDragging || scroll.isDecelerating { pending = nil }", "scroll.adjustedContentInset.top", "scroll.adjustedContentInset.bottom",
  "scroll.contentSize.height", "scroll.bounds.height", "scroll.setContentOffset", "animated: false", "maximum >= CGFloat(pending)",
  "observations.forEach { $0.invalidate() }", "coordinator.detach()", "GalaxySSIHealthAtlasState.safeScroll(value)"])
  assert(scroll.includes(token), token);
assert(!scroll.includes(".delegate =")); assert(!scroll.includes("@Published var offset"));
assert(!scroll.includes("asyncAfter")); assert(!scroll.includes("URLSession"));
// #4439 replaces the player layout, not its clock/lifecycle implementation.
assert.equal(source("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1], prior("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1]);
for (const name of ["ChapterClock", "Physiology", "ModelComparison", "Distribution", "ComparisonPanel", "AgentContext", "AgentHandoff", "Aging"]) assert.equal(source(name), prior(name), name + " must remain unchanged");
// #4442 reorganizes scene/layout only; the playback and lifecycle block stays exact.
const simulationLifecycle = s => s.split(".onReceive(timer)")[1].split(".onDisappear { pause() }")[0];
assert.equal(simulationLifecycle(source("SimulationPanel")), simulationLifecycle(prior("SimulationPanel")));
assert.equal(detail.split("struct GalaxySSIHealthAtlasValues:")[1], prior("Detail").split("struct GalaxySSIHealthAtlasValues:")[1]);
for (const locale of ["en", "zh-Hans"]) {
  const table = read("apps/ios/GalaxySSI/" + locale + ".lproj/AtlasResearchNavigation.strings");
  assert.equal([...table.matchAll(/^"health_atlas_/gm)].length, 1);
  assert(table.includes('"health_atlas_targeted_research" = "'));
}
assert(source("").includes('table: "AtlasResearchNavigation"'));
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ["AtlasResearchNavigation.strings in Resources", "GalaxySSIHealthAtlasScrollAnchor.swift in Sources"]) assert(pbx.includes(token));
const tests = read("apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift");
for (const token of ["testResearchTopicsUseSemanticCasesAndKeepMicroscopyPhysiology", "testResearchReturnRestoresFunctionInputsLessonAndPixelOffset",
  "testOnlyActiveLegacyPhysiologyResearchMigratesIntoInlineFunction", "testResearchScrollMemoryIsBoundedAndCaptureDoesNotTriggerRestoration",
  "for entry in atlas.entries", "restored.closeResearch(entry)", "after.researchReturnScroll, 887.5", "preferenceOnly.tab, .structure",
  "memory.revision, initial", "memory.restore(2_000_000)", "XCTAssertEqual(after.functionSelection, before.functionSelection)"])
  assert(tests.includes(token), token);
const files = inventory.files.map(file => {
  const name = path.basename(file.path); let kind, ios, note;
  if (name === "HealthBodyAtlasActivity.kt") {
    kind = "native-single-physiology-location-and-navigation"; ios = ["State", "Detail", "Research", "ScrollAnchor"].map(swift);
    note = "System/organ inline models opt into mechanism-first and retain their evidence link. Research opens Drugs then Aging only; microscopy retains all three topics. Persist explicit open state and bounded return offset, migrate active old physiological destinations into expanded Function, synchronously pause/snapshot before navigation and restore Function pixels via the containing iOS 15 scroll view after layout. Existing iOS caches stored topic preference but not active research location: do not reinterpret ordinary default preferences as active locations. Native pixel restoration has not been executed.";
  } else if (name === "HealthAtlasUi.kt") {
    kind = "semantic-research-tab-identity"; ios = [swift("Research"), swift("State")];
    note = "Filtered topics carry semantic raw-value picker tags and atlas-research-tab-drugs/aging/physiology accessibility identities rather than positional indices.";
  } else if (file.path.includes("/androidTest/")) {
    kind = "android-device-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift", "apps/ios/tools/check-atlas-research-navigation-scope.cjs"];
    note = name + ": navigation/source-order/retained-model/research-return assertions audited as source references. Added full-catalogue topic and active-location migration fixtures, entry-scoped return/phase/input preservation and bounded scroll memory. No Android/XCTest/device tests, tap timing, native view identity, pixels, gesture or VoiceOver acceptance claimed.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-resource-delta"; ios = ["apps/ios/GalaxySSI/en.lproj/AtlasResearchNavigation.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AtlasResearchNavigation.strings", swift(""), "apps/ios/tools/import-body-atlas-regional-text.cjs", "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"];
    note = "One exact English/Chinese targeted-research label pair from original XML, registered in Xcode and native locale chain.";
  } else if (name === "build.gradle.kts") {
    kind = "android-version-only"; ios = []; note = "No iOS version bump or IPA.";
  } else {
    assert.equal(file.path, "docs/architecture/android-body-atlas.md"); kind = "architecture-reference"; ios = ["apps/ios/ANDROID_4437_PORT_STATUS.md"];
    note = "Document native navigation/state and source-only verification separately from Android's execution evidence.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === "android-device-reference-not-executed").length, 13);
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const file = "apps/ios/ANDROID_4437_" + suffix + ".json", content = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes("--checks")) for (const command of ["import-body-atlas-regional-text.cjs --research-navigation-4437 --check", "check-atlas-cumulative-comparison-scope.cjs --checks"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4437: nineteen original hashes/dispositions, filtered research/single inline physiology/active-location migration/scroll source contracts and one bilingual pair. Not native execution or pixel acceptance.");

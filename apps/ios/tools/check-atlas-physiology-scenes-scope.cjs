// Source/packaging contracts only, never native layout, Swift execution or acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), sha = 'd1b5f1d3c5abba4c086157d358e712cedebc9487';
const base = 'f32614eb269ef1f34e2f1449d384410d8d99eaeb';
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/GalaxySSIHealthAtlas' + name + '.swift';
const source = name => read(swift(name));
const prior = name => git(['show', base + ':' + swift(name)]).toString().replace(/\r\n/g, '\n');
const android = name => git(['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + name + '.kt']).toString();
const requireTokens = (text, tokens) => { for (const token of tokens) assert(text.includes(token), token); };
const changed = git(['diff', '--name-status', '--no-renames', sha + '^1', sha]).toString().trim().split(/\r?\n/).map(line => line.split('\t'));
assert.equal(changed.length, 11);
const inventory = {schema: 1, source: {androidPR: 4442, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash('sha256').update(git(['show', sha + ':' + file])).digest('hex')}))};
requireTokens(android('HealthAtlasSceneFrame'), ['require(texts.isNotEmpty())', 'texts.maxOf', 'view.minimumHeight = lines + view.totalPaddingTop + view.totalPaddingBottom', 'view.totalPaddingStart', 'view.totalPaddingEnd']);
requireTokens(source('SceneFrame'), ['clipShape(RoundedRectangle(cornerRadius: 8))', 'content().padding(inset)', 'ForEach(values.indices', '.hidden().accessibilityHidden(true).allowsHitTesting(false)', 'fixedSize(horizontal: false, vertical: true)', 'min(values.count - 1, max(0, selected))']);
requireTokens(source('FunctionScene'), ['GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-function-frame"', 'GalaxySSIHealthAtlasReservedCaption(values: labels', 'values: story.chapters.map { t($0.caption) }']);
assert.equal(source("FunctionScene").replace(/^  @Environment.*private var colorScheme\n/m, "").split('  var body:')[0], prior('FunctionScene').split('  var body:')[0]);
assert.equal(source("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1], prior("FunctionPlayer").split('}.accessibilityIdentifier("atlas-function-player")')[1]);
const panel = source('SimulationPanel'), processStages = source('ProcessStages');
requireTokens(android('HealthAtlasSimulationPanel'), ['HealthAtlasProcessView(activity, mechanism, showLabels = !inline)', 'HealthAtlasSceneFrame(activity, "atlas-simulation-frame")', 'scene.reserveCaption(caption', 'tag = "atlas-simulation-references"', '"atlas-simulation-references-toggle"']);
requireTokens(panel, ['@State private var referencesExpanded = false', 'GalaxySSIHealthAtlasSceneFrame(identifier: "atlas-simulation-frame", inset: 8)', 'GalaxySSIHealthAtlasReservedCaption(values: stageCaptions', 'compact: inline', 'if !retinal && endocrine == nil', 'atlas-simulation-figure', 'processArtwork.padding(.bottom, GalaxySSIHealthAtlasFigureLayout.overlap)', 'if !inline && (hasDiagram || hasCloseup) { playbackControls }', 'if inline || (!hasDiagram && !hasCloseup) { playbackControls }', 'DisclosureGroup(isExpanded: $referencesExpanded)', '"atlas-simulation-references-toggle"', '"atlas-simulation-progress"', 'private var referenceNotes:', '"atlas-source-physiology"']);
const sceneAt = panel.indexOf('GalaxySSIHealthAtlasSceneFrame(identifier:'), before = panel.indexOf('quantitative.accessibilityIdentifier("atlas-quantitative-before-art")'), after = panel.indexOf('quantitative.accessibilityIdentifier("atlas-quantitative-after-art")');
assert(before < sceneAt && sceneAt < after);
// #4445 places the reserved stage caption in the process figure, after specialized closeups.
assert(panel.indexOf('          simulationArtwork') < panel.indexOf('identifier: "atlas-simulation-figure"'));
requireTokens(processStages, ['if stages.count == 4', 'if compact', 'HStack(spacing: 0)', 'if !compact', 'minHeight: compact ? 48 : 64', '.accessibilityLabel(label(stage))', '"atlas-process-stage-"', '[0, 1, 3, 2]', 'selected(stage)']);
// Preserve every renderer, callbacks and numerical inputs; child details move, not disappear.
const artwork = panel.split('  @ViewBuilder private var simulationArtwork:')[1].split('  private func openStructure')[0];
const priorBody = prior('SimulationPanel');
for (const name of [...priorBody.matchAll(/(GalaxySSIHealthAtlas\w+(?:View|Panel|Phagocytosis))\(/g)].map(m => m[1])) assert(panel.includes(name + '('), name);
requireTokens(artwork, ['phase: simulation.phase', 'stage: simulation.stage', 'flow: cardiac ? simulation.output : nil', 'selected: { pause(); simulation.selectStage($0) }', 'showsScope: false', 'showsDetails: false', 'open: openStructure']);
requireTokens(panel, ['private func openStructure(_ id: String) { pause(); structure = id }', 'GalaxySSIHealthAtlasCellSceneRelatedRow', 'GalaxySSIHealthAtlasGasExchange.source', 'GalaxySSIHealthAtlasCirculation.source', 'GalaxySSIHealthAtlasGermline.source', 'GalaxySSIHealthAtlasPancreatic.source', 'GalaxySSIHealthAtlasRetinaPath.source', 'section.notes']);
const inlineDetail = source('Detail').split('state.playback.claim("models-disclosure|" + entry.id)')[1].split('Text(t("inline_models"))')[0];
assert(inlineDetail.includes('simulationPanel')); assert(!inlineDetail.includes('mechanismSource'));
const lifecycle = text => text.split('.onReceive(timer)')[1].split('.onDisappear { pause() }')[0];
assert.equal(lifecycle(panel), lifecycle(priorBody));
assert.equal(panel.split('  private var quantitative:')[1], priorBody.split('  private var quantitative:')[1], 'Numerical invocation, all controls, reset, pause and parameter handlers stay exact');
for (const name of ['FunctionArtwork', 'ChapterClock', 'Physiology', 'AgentContext', 'AgentHandoff', 'GasExchange', 'Circulation', 'EndocrinePathView', 'RetinaPathView', 'SectionLessonView', 'CrossBridgeDrawing', 'GlucoseTransportDrawing', 'PotassiumTraceDrawing']) assert.equal(source(name), prior(name), name);
// #4444 changes navigation/related menu only, not the player clock, cache sanitizers or personal metric renderer.
const navigationPlayerCore = s => s.split('}.accessibilityIdentifier("atlas-function-player")')[1];
assert.equal(navigationPlayerCore(source("FunctionPlayer")), navigationPlayerCore(prior("FunctionPlayer")));
const restoreSelectionCore = s => s.split("  func restore(_ text:")[1].split("  var serialized:")[0];
assert.equal(restoreSelectionCore(source("State")), restoreSelectionCore(prior("State")));
// #4445 adds contextual search/navigation and scroll tracking; preserve every research domain view.
assert.equal(source("Research").split("  private var drugs:")[1], prior("Research").split("  private var drugs:")[1]);
const physiologyCase = s => s.split("        case .physiology:")[1].split("        case .drugs:")[0];
assert.equal(physiologyCase(source("Research")), physiologyCase(prior("Research")));
assert(source("Research").includes("state.detailBinding(entry, depth: depth)"));
// #4443 adds one immutable reference overlay, not new selection/cache semantics.
assert.equal(source("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1], prior("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1]);
for (const [name, field] of [['Germline', 'showsDetails'], ['BloodDefenseView', 'showsDetails'], ['ImmuneLink', 'showsDetails'], ['PancreaticPanel', 'showsScope']]) requireTokens(source(name), ['var ' + field + ' = true', 'if ' + field]);
requireTokens(source('SimulationPlate'), ['GalaxySSIHealthAtlasLabeledArtwork', '.sheet(isPresented:', 'preview(true)', 'preview(false)', 'Slider(value: $zoom, in: 1...4)']);
// Pinned Android entry IDs and the native immutable route pack agree for all 313 entries.
const entries = JSON.parse(git(['show', sha + ':apps/android/app/src/main/assets/health/body-atlas.json']).toString()).entries;
const catalogue = JSON.parse(read('apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasCompleteStories.dataset/content.json'));
assert.equal(entries.length, 313); assert.deepEqual(entries.map(e => e.id).sort(), Object.keys(catalogue.routes).sort());
const registry = source('FunctionArtwork'), sets = new Map([...registry.matchAll(/static let (\w+): Set<String> = \[([^\]]+)\]/g)].map(m => [m[1], [...m[2].matchAll(/"([^"]+)"/g)].map(x => x[1])]));
const implemented = registry.match(/static let implemented = ([^\n]+)/)[1];
const names = [implemented.match(/^\w+/)[0], ...[...implemented.matchAll(/\.union\((\w+)\)/g)].map(m => m[1])];
const ids = new Set(names.flatMap(name => { assert(sets.has(name), name); return sets.get(name); }));
assert.equal(ids.size, 138);
for (const entry of entries) { assert(catalogue.routes[entry.id]?.length > 0, entry.id); for (const id of catalogue.routes[entry.id]) assert(ids.has(id), id); }
requireTokens(read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift'), ['testEveryBundledEntryResolvesToAnimatedLessonsWithLocalizedCaptions', 'atlas.entries.count, 313', 'for language in ["en", "zh-CN"]', 'XCTAssertNotEqual(value, key']);
const mapping = {
  HealthAtlasFunctionPlayer: ['FunctionScene', 'SceneFrame'], HealthAtlasSceneFrame: ['SceneFrame'],
  HealthAtlasProcessView: ['ProcessStages'], HealthAtlasSimulationPanel: ['SimulationPanel', 'ProcessStages', 'SimulationPlate', 'Germline', 'ImmuneLink', 'BloodDefenseView', 'PancreaticPanel'],
  HealthBodyAtlasActivity: ['Detail']
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path), key = name.replace(/\.kt$/, ''); let kind, ios, note;
  if (mapping[key]) {
    kind = 'native-production-port'; ios = mapping[key].map(swift);
    note = 'Shared native scene frame and longest wrapped caption reservation; framed physiology artwork/stage/control grouping, compact numbered inline process targets with complete semantic accessibility labels, collapsible notes/related destinations/source links and single physiology evidence location. Preserve numerical input placement and exact playback/lifecycle handlers. Existing iOS child-owned scopes are explicitly hoisted with default-compatible detail flags. Native layout/interaction not executed.';
  } else if (file.path.includes('/androidTest/') || file.path.includes('/test/')) {
    kind = 'android-test-source-reference'; ios = ['apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift', 'apps/ios/tools/check-atlas-physiology-scenes-scope.cjs'];
    note = name + ': source-reference audit only. Compare all 313 pinned Android IDs to native lesson routes and all 138 registered renderers; add native fixture sources for full-catalogue bilingual captions. Android scene containment/height/source disclosure/route selection/device assertions are NOT native iOS execution evidence.';
  } else { assert.equal(name, 'build.gradle.kts'); kind = 'android-version-only'; ios = []; note = 'No new localization strings, iOS version bump or IPA.'; }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === 'native-production-port').length, 5);
assert.equal(files.filter(f => f.kind === 'android-test-source-reference').length, 5);
for (const [suffix, value] of [['SOURCE_INVENTORY', inventory], ['PORT_COVERAGE', {schema: 1, source: inventory.source, verification: 'source-contracts-only-not-native-execution', files}]]) {
  const file = 'apps/ios/ANDROID_4442_' + suffix + '.json', content = JSON.stringify(value, null, 2) + '\n';
  if (process.argv.includes('--write')) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes('--checks')) cp.execFileSync(process.execPath, [path.join(__dirname, 'check-atlas-cellular-closeups-scope.cjs'), '--checks'], {cwd: root, stdio: 'inherit'});
console.log('Android #4442: eleven source hashes/dispositions, shared scene/caption/inline targets/evidence contracts, all 313 pinned routes and 138 registrations. Not native execution, pixels or Swift compilation.');

// Pinned source/resource contracts. Does not execute Swift or certify native UI.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const sha = 'eef7fd41df84c075cbc0ba046cca6ab6a5b59bf7', base = 'c4913f5c79b0aee7989774ae2f8b3e9a972257f7';
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 20_000_000});
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/GalaxySSIHealthAtlas' + name + '.swift';
const source = name => read(swift(name));
const prior = name => git(['show', base + ':' + swift(name)]).toString().replace(/\r\n/g, '\n');
const changed = git(['diff', '--name-status', '--no-renames', sha + '^1', sha]).toString().trim().split(/\r?\n/).map(line => line.split('\t'));
assert.equal(changed.length, 20);
const inventory = {schema: 1, source: {androidPR: 4439, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash('sha256').update(git(['show', sha + ':' + file])).digest('hex')}))};
const requireTokens = (text, tokens) => { for (const token of tokens) assert(text.includes(token), token); };
const android = name => git(['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + name + '.kt']).toString();
requireTokens(android('HealthAtlasFunctionPlayer'), ['StaticLayout.Builder.obtain', 'chapterLabel.minimumHeight', 'caption.minimumHeight', 'pause()', 'PopupMenu', 'atlas-function-subtitles', 'setSingleChoiceItems']);
requireTokens(source('FunctionScene'), ['"atlas-function-frame"', '"atlas-function-subtitles"', 'ForEach(values.indices', '.hidden().accessibilityHidden(true).allowsHitTesting(false)', 'fixedSize(horizontal: false, vertical: true)', '@ScaledMetric', 'story.chapters.map { t($0.caption) }']);
const player = source('FunctionPlayer'), menu = source('FunctionPlaybackMenu'), detail = source('Detail'), state = source('State');
assert(player.indexOf('GalaxySSIHealthAtlasFunctionScene') < player.indexOf('Slider(value:'));
assert(player.indexOf('Slider(value:') < player.indexOf('control("backward.step"'));
requireTokens(menu, ['pause(); menu = true', 'panel = .chapters', 'seek(0)', 'panel = .evidence', 'seek(story.startOf(index)); panel = nil', 'Text(t(story.scope))', 'openURL(reference.url)', 'health_atlas_scene_sources']);
assert(!player.includes('DisclosureGroup')); assert(!player.includes('story.references'));
assert.equal(player.split('}.accessibilityIdentifier("atlas-function-player")')[1], prior('FunctionPlayer').split('}.accessibilityIdentifier("atlas-function-player")')[1]);
assert.equal(source('ChapterClock'), prior('ChapterClock'));
requireTokens(state, ['static let detailTabs: [Tab] = [.structure, .function, .values]', 'func closeStandaloneModel', 'next.researchPresented = false']);
const open = state.split('  func openNumericalModel(')[1].split('  func closeStandaloneModel')[0];
assert(open.indexOf('playback.pause()') < open.indexOf('functionSnapshot(entry)'));
requireTokens(detail, ['tab == .simulation ? .function', 'NavigationLink(isActive: standalone)', 'GalaxySSIHealthAtlasStandaloneModels', 'currentTab == .function && !hasFunctionPlayer', '}.id(currentTab)']);
assert(!detail.includes('showFunctionStructurePreview'));
requireTokens(source('StandaloneModels'), ['state.closeStandaloneModel(entry, destination: $0)', '"atlas-standalone-models"', 'NavigationLink(isActive: research)', 'state.openResearch(entry, returnScroll: scrollMemory.offset)', 'atlas-source-physiology', 'state.functionSnapshot(entry)']);
requireTokens(source('CompactTabs'), ['minHeight: 42', '.frame(height: 2).padding(.horizontal, 24)', 'identifier + "-" + key(option)', 'fixedSize(horizontal: false, vertical: true)']);
for (const name of ['Detail', 'FunctionPanel', 'Research']) assert(source(name).includes('GalaxySSIHealthAtlasCompactTabs'));
requireTokens(source('SynchronizedCatalogue'), ['health_atlas_beat_choice', 'health_atlas_breathe_choice', '12-4-the-action-potential', 'references.insert(reference, at: 0)', 'routes: routes, entryPhases: entryPhases']);
requireTokens(source('FunctionCatalogue'), ['revision: Int = 4439', 'original.synchronizedLessons()', '== 321']);
requireTokens(source('SignalMotion'), ['0.30 * input(0.24, 0.25)', '- 0.24 * input(0.47, 0.17)', '0.35 * input(0.81, 0.27)', '(0...64).map', 'duration > 0']);
requireTokens(source('SynapticChannelsDrawing'), ['0.58 * height', 'Motion.potential[i]', 't * 1.55', 'Double(segment) * 0.29', '(0.04...0.69)', '(local - 0.32) / 0.37']);
requireTokens(source('SynapseDrawing'), ['gradedPotential(t)', 'membraneRelay(t)', 'gateProgress', 'receptorOpen', 'clearing']);
requireTokens(source('BreathingView'), ['motion.stage == .diffuse', 'membrane(in: drawing']);
requireTokens(source('RespiratoryMembraneDrawing'), ['band(144, 159, 0xDFA98F)', 'band(160, 165, 0xECD8BA)', 'band(166, 180, 0xA9C5C0)', '34 + 275 * time', 'time * 1.6 + Double(particle) / 3']);
// Numerical-model calculations, patient-metric privacy and cache sanitization are not rewritten.
for (const name of ['SimulationPanel', 'Physiology', 'ModelComparison', 'AgentContext', 'AgentHandoff', 'MyelinDrawing', 'ThyroidDrawing']) assert.equal(source(name), prior(name), name);
assert.equal(detail.split('struct GalaxySSIHealthAtlasValues:')[1], prior('Detail').split('struct GalaxySSIHealthAtlasValues:')[1]);
assert.equal(state.split('  func restore(_ text:')[1], prior('State').split('  func restore(_ text:')[1]);
for (const locale of ['en', 'zh-Hans']) assert.equal([...read('apps/ios/GalaxySSI/' + locale + '.lproj/AtlasSynchronizedLessons.strings').matchAll(/^"health_atlas_/gm)].length, 19);
requireTokens(read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift'), ['testSynchronizedLessonOverlayPreservesAllOtherCatalogueFields', 'testSynapticGradedPotentialRetainsInhibitionAndThreshold', 'testStandaloneModelBackReturnsToFunctionAndPreservesInputs']);
const mappings = {
  HealthAtlasBreathingView: ['BreathingView', 'RespiratoryMembraneDrawing'],
  HealthAtlasFunctionArt: ['FunctionViewport'],
  HealthAtlasFunctionPlayer: ['FunctionPlayer', 'FunctionScene', 'FunctionPlaybackMenu'],
  HealthAtlasFunctionStory: ['FunctionCatalogue', 'SynchronizedCatalogue'],
  HealthAtlasSignalStoryView: ['SignalMotion', 'SynapseDrawing', 'SynapticChannelsDrawing'],
  HealthAtlasUi: ['CompactTabs'], HealthBodyAtlasActivity: ['Detail', 'State', 'StandaloneModels', 'Research', 'FunctionPanel']
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path), key = name.replace(/\.kt$/, '');
  let kind, ios, note;
  if (mappings[key]) {
    kind = 'native-production-port'; ios = mappings[key].map(swift);
    note = 'Pinned implementation comparison: synchronized fixed-height wrapped subtitles, paused scene menu, three compact semantic tabs and explicit standalone back behavior; richer synaptic channels/graded inhibition and respiratory membrane diffusion as applicable. Native layout, accessibility and navigation require Apple-platform verification.';
  } else if (file.path.includes('/androidTest/')) {
    kind = 'android-device-source-reference'; ios = ['apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift', 'apps/ios/tools/check-atlas-synchronized-lessons-scope.cjs'];
    note = name + ': source-reference audit only; native Swift fixtures added for overlay, mechanism phases and navigation state. No Android/device/XCTest execution, timing or pixel acceptance.';
  } else if (file.path.includes('/res/')) {
    kind = 'exact-bilingual-resource-delta'; ios = ['apps/ios/GalaxySSI/en.lproj/AtlasSynchronizedLessons.strings', 'apps/ios/GalaxySSI/zh-Hans.lproj/AtlasSynchronizedLessons.strings', swift('FunctionText'), swift(''), 'apps/ios/tools/import-body-atlas-regional-text.cjs', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];
    note = 'Nineteen exact English/Chinese pairs imported from original XML and registered, including chapter captions, mechanism labels, menu labels and Metrics. No fallback translation.';
  } else {
    assert.equal(name, 'build.gradle.kts'); kind = 'android-version-only'; ios = []; note = 'No iOS marketing-version change or IPA.';
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === 'native-production-port').length, 7);
assert.equal(files.filter(f => f.kind === 'android-device-source-reference').length, 4);
for (const [suffix, value] of [['SOURCE_INVENTORY', inventory], ['PORT_COVERAGE', {schema: 1, source: inventory.source, verification: 'source-contracts-only-not-native-execution', files}]]) {
  const file = 'apps/ios/ANDROID_4439_' + suffix + '.json', content = JSON.stringify(value, null, 2) + '\n';
  if (process.argv.includes('--write')) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes('--checks')) for (const command of ['import-body-atlas-regional-text.cjs --synchronized-lessons-4439 --check', 'check-atlas-function-viewport.cjs', 'check-manual-model-recovery-scope.cjs --checks']) {
  const [file, ...args] = command.split(' ');
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: 'inherit'});
}
console.log('Android #4439: twenty pinned source hashes/dispositions, nineteen exact bilingual pairs, synchronized lesson/navigation/mechanism source contracts. Not Swift compilation or native acceptance.');

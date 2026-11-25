// Pinned source/resource contracts, not Swift execution, native measurement or pixels.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto'), xml = require('xml-js');
const root = path.resolve(__dirname, '../../..'), sha = 'c63bffe14e00a4c60e52aec68b6753f7547be308';
const base = '2f5427312748cdf8188ad13c1d462106ce98a4da';
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/GalaxySSIHealthAtlas' + name + '.swift';
const source = name => read(swift(name));
const prior = name => git(['show', base + ':' + swift(name)]).toString().replace(/\r\n/g, '\n');
const android = name => git(['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + name + '.kt']).toString();
const requireTokens = (text, tokens) => { for (const token of tokens) assert(text.includes(token), token); };
const changed = git(['diff', '--name-status', '--no-renames', sha + '^1', sha]).toString().trim().split(/\r?\n/).map(line => line.split('\t'));
assert.equal(changed.length, 11);
const inventory = {schema: 1, source: {androidPR: 4443, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash('sha256').update(git(['show', sha + ':' + file])).digest('hex')}))};
requireTokens(android('HealthAtlasFunctionPlayer'), ['R.color.health_atlas_film_ground', '2 * ui.dp(14)', 'R.color.health_atlas_film_caption', 'R.color.health_atlas_film_text']);
requireTokens(android('HealthAtlasSceneFrame'), ['val probe = TextView(context)', 'paint.set(view.paint)', 'probe.measure(widthSpec, heightSpec)', 'view.minHeight = reserved', 'isFallbackLineSpacing']);
const scene = source('FunctionScene'), frame = source('SceneFrame');
requireTokens(scene, ['colorScheme == .dark', 'colors.ground', 'colors.chapter', 'colors.text', '.padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 12)', '.background(GalaxySSIHealthAtlasFilmPalette.color(colors.caption))', 'VStack(alignment: .leading, spacing: 0)']);
assert(scene.includes('artwork.frame(maxWidth: .infinity)'));
requireTokens(frame, ['ground: Color? = nil', 'ForEach(values.indices', '.hidden().accessibilityHidden(true).allowsHitTesting(false)']);
assert.equal((frame.match(/\.lineLimit\(nil\)\.fixedSize\(horizontal: false, vertical: true\)/g) || []).length, 2);
// The same native Text type, modifiers, inherited font and constrained width measure
// both hidden probes and the displayed caption; no alternate-font estimate or line cap.
assert(!frame.includes('lineLimit(1)')); assert(!frame.includes('maxHeight:'));
const colorXML = directory => xml.xml2js(git(['show', sha + ':apps/android/app/src/main/res/' + directory + '/health_atlas_scene_colors.xml']).toString(), {compact: false}).elements.find(e => e.name === 'resources').elements.filter(e => e.name === 'color');
const colors = new Map(colorXML('values').map(e => [e.attributes.name, e.elements[0].text]));
const night = new Map(colorXML('values-night').map(e => [e.attributes.name, e.elements[0].text]));
const expected = {ground: ['#E7EFED', '#263537'], caption: ['#223A3D', '#192C30'], chapter: ['#AFE2D0', '#AFE2D0'], text: ['#FFFFFF', '#FFFFFF']};
for (const [key, pair] of Object.entries(expected)) {
  assert.equal(colors.get('health_atlas_film_' + key), pair[0]);
  assert.equal(night.get('health_atlas_film_' + key) || colors.get('health_atlas_film_' + key), pair[1]);
  for (const value of new Set(pair)) assert(source('FilmPalette').includes('0x' + value.slice(1)));
}
function luminance(hex) { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(x => x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4); return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722; }
for (const background of expected.caption) for (const foreground of [expected.chapter[0], expected.text[0]]) assert((luminance(foreground) + 0.05) / (luminance(background) + 0.05) > 4.5);
requireTokens(android('HealthAtlasVisionStoryView'), ['transition(t, .24f, .36f)', '.86f * transition(t, .30f, .61f)', 'transition(t, .38f, .72f)', '.77f * transition(t, .56f, .92f)']);
requireTokens(source('RodResponse'), ['start: 0.24, end: 0.36', '1 - 0.86 * transition(t, start: 0.30, end: 0.61)', 'start: 0.38, end: 0.72', '1 - 0.77 * transition(t, start: 0.56, end: 0.92)', 'f * f * (3 - 2 * f)']);
requireTokens(source('VisionMotion'), ['max(1, Int(6 * GalaxySSIHealthAtlasRodResponse.release(fraction)))']);
requireTokens(source('VisionView'), ['rodCapture(in: context, time: motion.fraction, count: motion.captureCount)']);
requireTokens(source('RodMembraneDrawing'), ['l: 4, t: 43, r: 142, b: 290', '(0.10...0.24).contains(time)', '26 + 66 * incident', '284 + move * 17', 'gap = 9 * gate', '0..<Int(gate * 4 + 0.5)', 'Double(index) < messenger * 7', 'gate <= 0.22 ? "hyperpolarized" : "resting"']);
const vision = source('VisionView'), normalizeVisibility = text => text.replaceAll('  private func ', '  func ').replaceAll('  private static ', '  static ');
assert.equal(normalizeVisibility(vision.split('  private func capture(')[0]), normalizeVisibility(prior('VisionView').split('  private func capture(')[0]));
assert.equal(normalizeVisibility(vision.split('  private func relay(')[1]), normalizeVisibility(prior('VisionView').split('  private func relay(')[1]), 'Optics, retinal relay, axons and adaptation drawing remain exact');
requireTokens(source('RodCatalogue'), ['story.id == "VISION"', 'https://pubmed.ncbi.nlm.nih.gov/2578616/', 'story.references + [reference]', 'routes: routes, entryPhases: entryPhases']);
requireTokens(source('FunctionCatalogue'), ['revision: Int = 4443', 'original.rodPhototransduction()', '== 324']);
assert.equal(source('FunctionCatalogue').split('struct GalaxySSIHealthAtlasFunctionSelection:')[1], prior('FunctionCatalogue').split('struct GalaxySSIHealthAtlasFunctionSelection:')[1]);
for (const name of ['ChapterClock', 'SimulationPanel', 'Physiology', 'AgentContext', 'AgentHandoff', 'ProcessStages', 'CrossBridgeDrawing', 'GlucoseTransportDrawing', 'PotassiumTraceDrawing']) assert.equal(source(name), prior(name), name);
// #4444 changes navigation/related menu only, not the player clock, cache sanitizers or personal metric renderer.
const navigationPlayerCore = s => s.split('}.accessibilityIdentifier("atlas-function-player")')[1];
assert.equal(navigationPlayerCore(source("FunctionPlayer")), navigationPlayerCore(prior("FunctionPlayer")));
const restoreSelectionCore = s => s.split("  func restore(_ text:")[1].split("  var serialized:")[0];
assert.equal(restoreSelectionCore(source("State")), restoreSelectionCore(prior("State")));
assert.equal(source("Research").replace(/^    \.background\(GalaxySSIHealthAtlasRestoredDetailLink.*\n/m, ""), prior("Research"));
for (const locale of ['en', 'zh-Hans']) {
  const table = read('apps/ios/GalaxySSI/' + locale + '.lproj/AtlasFilmCaptions.strings');
  assert.equal([...table.matchAll(/^"health_atlas_/gm)].length, 10);
  for (const key of ['cgmp', 'dark_current']) assert(table.includes('"health_atlas_vision_story_' + key + '" = "'));
}
requireTokens(source('FunctionText'), ['table: "AtlasFilmCaptions"']);
requireTokens(source(''), ['table: "AtlasFilmCaptions"']);
requireTokens(read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift'), ['testRodResponseOrdersLightMessengerGateAndReleaseAndClamps', 'testFilmPaletteUsesExactLightAndDarkAndroidCaptionBands', 'testRodEvidenceOverlayIsOrderedIdempotentAndPreservesEveryOtherLesson']);
const mapping = {
  HealthAtlasFunctionPlayer: ['FunctionScene', 'FilmPalette'], HealthAtlasSceneFrame: ['SceneFrame'],
  HealthAtlasFunctionStory: ['FunctionCatalogue', 'RodCatalogue'], HealthAtlasVisionStoryView: ['VisionMotion', 'VisionView', 'RodResponse', 'RodMembraneDrawing']
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path), key = name.replace(/\.kt$/, ''); let kind, ios, note;
  if (mapping[key]) {
    kind = 'native-production-port'; ios = mapping[key].map(swift);
    note = 'Continuous full-width caption band with exact source day/night colors and 14-point insets; reserve complete captions with the same native SwiftUI Text rendering type/width/font and Dynamic Type, not Android-specific TextView APIs. Rod light/cGMP/gate/release sequence and magnified membrane plus immutable ordered evidence overlay as applicable. Native layout/pixels remain unexecuted.';
  } else if (file.path.includes('/androidTest/') || file.path.includes('/test/')) {
    kind = 'android-test-source-reference'; ios = ['apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift', 'apps/ios/tools/check-atlas-film-captions-scope.cjs'];
    note = name + ': source-reference review. Added pure native fixture sources for rod ordering/clamping/monotonicity, exact palette and reference-overlay preservation. Narrow mixed-script/large-type containment, unchanged height, moving-region hashes and screenshots require native execution. Original PR reports unresolved playback/multi-entry device failures; do not turn those into an iOS acceptance claim.';
  } else if (name === 'health_atlas_scene_colors.xml') {
    kind = 'exact-theme-color-resources'; ios = [swift('FilmPalette'), swift('FunctionScene'), swift('SceneFrame')];
    note = 'Four day colors and two night overrides reproduced exactly; inherited mint chapter and white prose preserved. Computed foreground/background contrast above 4.5 is source math only, not actual rendered pixel inspection.';
  } else if (file.path.includes('/res/')) {
    kind = 'exact-resource-delta-with-explicit-shared-names'; ios = ['apps/ios/GalaxySSI/en.lproj/AtlasFilmCaptions.strings', 'apps/ios/GalaxySSI/zh-Hans.lproj/AtlasFilmCaptions.strings', swift('FunctionText'), swift(''), 'apps/ios/tools/import-body-atlas-regional-text.cjs', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];
    note = 'Eight translated English/Chinese pairs plus two original XML-declared translatable=false scientific names shared unchanged; ten entries per table, not ten translated pairs.';
  } else { assert.equal(name, 'build.gradle.kts'); kind = 'android-version-only'; ios = []; note = 'No iOS version bump or IPA.'; }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === 'native-production-port').length, 4);
assert.equal(files.filter(f => f.kind === 'android-test-source-reference').length, 2);
assert.equal(files.filter(f => f.kind === 'exact-theme-color-resources').length, 2);
for (const [suffix, value] of [['SOURCE_INVENTORY', inventory], ['PORT_COVERAGE', {schema: 1, source: inventory.source, verification: 'source-contracts-only-not-native-execution', files}]]) {
  const file = 'apps/ios/ANDROID_4443_' + suffix + '.json', content = JSON.stringify(value, null, 2) + '\n';
  if (process.argv.includes('--write')) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes('--checks')) for (const command of ['import-body-atlas-regional-text.cjs --film-captions-4443 --check', 'check-atlas-physiology-scenes-scope.cjs --checks']) {
  const [file, ...args] = command.split(' ');
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: 'inherit'});
}
console.log('Android #4443: eleven hashes/dispositions, six theme colors, complete native-Text caption reservation, rod sequence and eight translated pairs plus two shared names. Not native layout or execution.');

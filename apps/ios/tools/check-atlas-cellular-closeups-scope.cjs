// Source/resource contracts only; does not execute Swift, XCTest or native art.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto'), xml = require('xml-js');
const root = path.resolve(__dirname, '../../..'), sha = '94d3e3a33be621a5ae17c62c7082a6ea912bdfd2';
const base = 'df3ccec2e062e2623954104d7a773a74beaca360';
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/GalaxySSIHealthAtlas' + name + '.swift';
const source = name => read(swift(name));
const prior = name => git(['show', base + ':' + swift(name)]).toString().replace(/\r\n/g, '\n');
const android = name => git(['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + name + '.kt']).toString();
const requireTokens = (text, tokens) => { for (const token of tokens) assert(text.includes(token), token); };
const changed = git(['diff', '--name-status', '--no-renames', sha + '^1', sha]).toString().trim().split(/\r?\n/).map(line => line.split('\t'));
assert.equal(changed.length, 12);
const inventory = {schema: 1, source: {androidPR: 4441, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash('sha256').update(git(['show', sha + ':' + file])).digest('hex')}))};
requireTokens(android('HealthAtlasMovementStoryView'), ['ACTIN_LENGTH = 80f', 'MYOSIN_LENGTH = 122f', 'BIND(', 'PULL(', 'DETACH(', 'RESET(', 't.coerceIn(0f, 1f) * 4f', 'clipRect(38f, 238f, 223f, 305f)']);
requireTokens(source('MovementMotion'), ['actinLength = 80.0, myosinLength = 122.0', 'case bind, pull, detach, reset', 'min(3, Int(phase * 4))', '111 - 33 * ease(t)', 'progress: ease(min(1, max(0, t * 4 - Double(stage.rawValue))))', 'CGPoint(x: 139 - 22 * progress, y: 280)']);
requireTokens(source('MuscleDrawing'), ['stride(from: 104, through: 168, by: 28)', 'line(left, 199, right, 199', 'crossBridge(t)']);
requireTokens(source('CrossBridgeDrawing'), ['Motion.bridgePose(time)', 'CGRect(x: 38, y: 238, width: 185, height: 67)', 'pose.actinOffset', 'tip.x + 8, tip.y + 4', 'label(170, 320, pose.stage.title)']);
assert.equal(source('MuscleDrawing').split('  private func sliding(')[0], prior('MuscleDrawing').split('  private func sliding(')[0]);
assert.equal(source('MuscleDrawing').split('  private func elbow(')[1], prior('MuscleDrawing').split('  private func elbow(')[1]);
requireTokens(android('HealthAtlasInsulinStoryView'), ['relativeDepolarization(t: Float) = ease(interval(t, .19f, .85f))', 'for (i in 1..24)', '338f - 26f * trace(it)']);
requireTokens(source('InsulinMotion'), ['relativeDepolarization(_ t: Double) -> Double { ease(interval(t, 0.19, 0.85)) }']);
assert.equal(source('InsulinMotion').replace(/^  static func relativeDepolarization.*\n/m, ''), prior('InsulinMotion'));
requireTokens(source('InsulinScenes'), ['label(243, 264, "energy")', 'potassiumTrace(t)']);
assert.equal(source('InsulinScenes').split('  private func calciumGate(')[1], prior('InsulinScenes').split('  private func calciumGate(')[1]);
requireTokens(source('PotassiumTraceDrawing'), ['Motion.potassiumOpen', 'Motion.relativeDepolarization', 'for index in 1...24', '338 - 26 * trace(time)', '39 + 282 * fraction', 'particle(39 + 282 * t, y(t)', '"k_opening"', '"voltage"']);
requireTokens(source('AbsorptionMotion'), ['c.count == 2 ? .line', 'route(240, 89, [251,102,251,123], [251,260])', 'route(271, 89, [261,102,261,123], [261,167,282,175], [307,187,307,212], [307,252])']);
const absorption = source('AbsorptionDrawing');
assert(absorption.indexOf('if step == 2 {') < absorption.indexOf('absorptionInset(progress:'));
requireTokens(absorption, ['absorptionFlow(AbsorptionMotion.bloodRoute, t)\n      glucoseTransport(t)\n      return', 'if step == 4 {']);
assert.equal(absorption.split('  private func absorptionVillus(')[1], prior('AbsorptionDrawing').split('  private func absorptionVillus(')[1]);
requireTokens(source('GlucoseTransportDrawing'), ['Motion.glucoseTrack', 'Motion.sodiumTrack', 'arrow(251, 245, 251, 260', 'arrow(307, 241, 307, 252', 'arrow(323, 251, 323, 206', 't + Double(index) * 0.5', 'absorption_story_sglt1', 'absorption_story_glut2', 'absorption_story_pump']);
for (const name of ['CloseupCatalogue', 'ChapterClock', 'AgentContext', 'AgentHandoff', 'Physiology', 'BeatPressure', 'PressureDrawing', 'TipLinkDrawing', 'RenalCloseupDrawing', 'BoneDrawing', 'IllustratedDrawing']) assert.equal(source(name), prior(name), name);
// #4444 changes navigation/related menu only, not the player clock, cache sanitizers or personal metric renderer.
const navigationPlayerCore = s => s.split('}.accessibilityIdentifier("atlas-function-player")')[1];
assert.equal(navigationPlayerCore(source("FunctionPlayer")), navigationPlayerCore(prior("FunctionPlayer")));
const restoreSelectionCore = s => s.split("  func restore(_ text:")[1].split("  var serialized:")[0];
assert.equal(restoreSelectionCore(source("State")), restoreSelectionCore(prior("State")));
// #4445 adds scoped search/scroll state while leaving research domain views exact.
assert.equal(source("Research").split("  private var drugs:")[1], prior("Research").split("  private var drugs:")[1]);
const physiologyCase = s => s.split("        case .physiology:")[1].split("        case .drugs:")[0];
assert.equal(physiologyCase(source("Research")), physiologyCase(prior("Research")));
assert(source("Research").includes("state.detailBinding(entry, depth: depth)"));
// #4443 adds one immutable reference overlay, not new selection/cache semantics.
assert.equal(source("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1], prior("FunctionCatalogue").split("struct GalaxySSIHealthAtlasFunctionSelection:")[1]);
// #4442 reorganizes scene/layout only; the playback and lifecycle block stays exact.
const simulationLifecycle = s => s.split(".onReceive(timer)")[1].split(".onDisappear { pause() }")[0];
assert.equal(simulationLifecycle(source("SimulationPanel")), simulationLifecycle(prior("SimulationPanel")));
assert.equal(source("FunctionScene").replace(/^  @Environment.*private var colorScheme\n/m, "").split("  var body:")[0], prior("FunctionScene").split("  var body:")[0]);
assert(source("FunctionScene").includes("GalaxySSIHealthAtlasFigureFrame")); // #4445 replaces the caption band, not the renderer.
assert(source("FunctionScene").includes("GalaxySSIHealthAtlasReservedCaption"));
assert.equal(source("Detail").split("struct GalaxySSIHealthAtlasValues:")[1], prior("Detail").split("struct GalaxySSIHealthAtlasValues:")[1]);
// Four XML-declared scientific names are intentionally locale-independent, not translations.
const originalXML = xml.xml2js(git(['show', sha + ':apps/android/app/src/main/res/values/health_atlas_absorption_story.xml']).toString(), {compact: false});
const declarations = originalXML.elements.find(e => e.name === 'resources').elements.filter(e => e.name === 'string' && e.attributes.translatable === 'false');
assert.deepEqual(declarations.map(e => e.attributes.name).sort(), ['glut2', 'potassium', 'sglt1', 'sodium'].map(x => 'health_atlas_absorption_story_' + x).sort());
for (const locale of ['en', 'zh-Hans']) {
  const table = read('apps/ios/GalaxySSI/' + locale + '.lproj/AtlasCellularCloseups.strings');
  assert.equal([...table.matchAll(/^"health_atlas_/gm)].length, 15);
  const values = new Map([...table.matchAll(/^"([^"]+)" = (".*");$/gm)].map(m => [m[1], JSON.parse(m[2])]));
  for (const declaration of declarations) assert.equal(values.get(declaration.attributes.name), declaration.elements.map(e => e.text || '').join(''));
}
requireTokens(source('FunctionText'), ['table: "AtlasCellularCloseups"']);
requireTokens(source(''), ['table: "AtlasCellularCloseups"']);
requireTokens(read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift'), ['testCrossBridgeCycleUsesBindingStrokeAtpDetachmentAndRecovery', 'testBetaCellDepolarizationFollowsPotassiumClosureAndIsMonotonic', 'testIntestinalGlucoseAndSodiumTracksCrossTheirNativeTransporters', 'for index in 1...100']);
const mapping = {
  HealthAtlasMovementStoryView: ['MovementMotion', 'MuscleDrawing', 'CrossBridgeDrawing'],
  HealthAtlasInsulinStoryView: ['InsulinMotion', 'InsulinScenes', 'PotassiumTraceDrawing'],
  HealthAtlasIntestinalAbsorptionStoryView: ['AbsorptionMotion', 'AbsorptionDrawing', 'GlucoseTransportDrawing']
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path), key = name.replace(/\.kt$/, ''); let kind, ios, note;
  if (mapping[key]) {
    kind = 'native-production-port'; ios = mapping[key].map(swift);
    note = 'Native chapter-scoped myosin binding/stroke/ATP detach/reset, SGLT1/GLUT2 and sodium-potassium transport tracks, or KATP/membrane-potential trace as applicable. Preserve original filament lengths, other chapters, lesson catalogue and privacy/numerical state. Illustrative values only; no native visual acceptance.';
  } else if (file.path.includes('/androidTest/') || file.path.includes('/test/')) {
    kind = 'android-test-source-reference'; ios = ['apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift', 'apps/ios/tools/check-atlas-cellular-closeups-scope.cjs'];
    note = name + ': reviewed as source reference. Swift fixture sources cover cross-bridge phase/pose/boundaries and fixed lengths, delayed monotonic depolarization and transport routes. Android native frame/caption/moving-region screenshot checks are not executed iOS evidence; no XCTest run.';
  } else if (file.path.includes('/res/')) {
    kind = 'exact-resource-delta-with-explicit-shared-names'; ios = ['apps/ios/GalaxySSI/en.lproj/AtlasCellularCloseups.strings', 'apps/ios/GalaxySSI/zh-Hans.lproj/AtlasCellularCloseups.strings', swift('FunctionText'), swift(''), 'apps/ios/tools/import-body-atlas-regional-text.cjs', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];
    note = 'Eleven original translated English/Chinese pairs plus four explicitly translatable=false names (SGLT1, GLUT2, Na+, K+ rendered with original source glyphs) shared unchanged in both locales; fifteen entries per table. No invented translations or implicit cross-language fallback.';
  } else {
    assert.equal(name, 'build.gradle.kts'); kind = 'android-version-only'; ios = []; note = 'No iOS version bump or IPA.';
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === 'native-production-port').length, 3);
assert.equal(files.filter(f => f.kind === 'android-test-source-reference').length, 2);
for (const [suffix, value] of [['SOURCE_INVENTORY', inventory], ['PORT_COVERAGE', {schema: 1, source: inventory.source, verification: 'source-contracts-only-not-native-execution', files}]]) {
  const file = 'apps/ios/ANDROID_4441_' + suffix + '.json', content = JSON.stringify(value, null, 2) + '\n';
  if (process.argv.includes('--write')) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes('--checks')) for (const command of ['import-body-atlas-regional-text.cjs --cellular-closeups-4441 --check', 'check-atlas-mechanism-closeups-scope.cjs --checks']) {
  const [file, ...args] = command.split(' ');
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: 'inherit'});
}
console.log('Android #4441: twelve source hashes/dispositions, three cellular closeups, eleven translated pairs plus four explicit non-translatable names. Source contracts only, no Swift execution or pixel acceptance.');

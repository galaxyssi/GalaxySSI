// Pinned source and packaging audit, never native execution or pixel acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), sha = '5fecc676dac71a5ef7128f6ec5893e69660b5746';
const base = 'ed1442c82d9a173c4079e979b3a56d5edbad93ba';
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/GalaxySSIHealthAtlas' + name + '.swift';
const source = name => read(swift(name));
const prior = name => git(['show', base + ':' + swift(name)]).toString().replace(/\r\n/g, '\n');
const android = name => git(['show', sha + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + name + '.kt']).toString();
const requireTokens = (text, tokens) => { for (const token of tokens) assert(text.includes(token), token); };
const changed = git(['diff', '--name-status', '--no-renames', sha + '^1', sha]).toString().trim().split(/\r?\n/).map(line => line.split('\t'));
assert.equal(changed.length, 15);
const inventory = {schema: 1, source: {androidPR: 4440, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash('sha256').update(git(['show', sha + ':' + file])).digest('hex')}))};
const pressure = source('BeatPressure');
const androidTuples = [...android('HealthAtlasBeatStage').matchAll(/HealthAtlasBeatPressure\((\.[\d]+)f, (\.[\d]+)f, (\.[\d]+)f\)/g)].map(m => m.slice(1).map(Number));
const iosTuples = [...pressure.matchAll(/\.init\(atrium: ([\d.]+), ventricle: ([\d.]+), aorta: ([\d.]+)\)/g)].map(m => m.slice(1).map(Number));
assert.equal(androidTuples.length, 11); assert.deepEqual(iosTuples, androidTuples);
requireTokens(pressure, ['Story.safePhase(fraction)', 'time: 2 * t)', 'time: 2 * t - 1)']);
requireTokens(source('PressureDrawing'), ['top = 277.0, bottom = 330.0', 'Double(stage.rawValue) + fraction', 'for sample in 0...12', 'baseline: 271', 'sample(chapter, fraction: local)', '0x247B72', '0xAB304C', '0xA36624']);
requireTokens(source('HeartbeatView'), ['width: 256 * scale', 'offset(x: 44 * scale', '256.0 / 1254', 'baseline: 239', 'pressures(in: drawing']);
requireTokens(source('HearingMotion'), ['0.19 + 0.76 * min(1, max(0, t)) + 0.16 * min(0, max(-1, t))', 'let shift = 8 * motion', 'x: 12 + 145 * x + shift, y: 27 + 240 * y']);
requireTokens(android('HealthAtlasSoundStage'), ['.19f + .76f * towardTallest.coerceIn(0f, 1f) + .16f * towardTallest.coerceIn(-1f, 0f)']);
requireTokens(source('HearingView'), ['Motion.relativeChannelOpening(motion.motion)', 'if opening > 0.32', 'tipLink(in: context']);
requireTokens(source('TipLinkDrawing'), ['253 + 16 * motion, tall = 293 + 24 * motion', '1 + opening * 5', 'time * 5 + Double(index) / 3', 'right - gap', 'right + gap', 'key: "potassium"']);
requireTokens(source('NephronView'), ['motion.stage == .filter || motion.stage == .loop', 'art.translateBy(x: 96, y: 2)', 'art.scaleBy(x: 0.13, y: 0.13)', 'filtrationBarrier(in: drawing', 'loopCutaway(in: drawing']);
requireTokens(source('RenalCloseupDrawing'), ['121, 245, 321, 251, 0xDFBB89', '137 + 109 * time', 'health_atlas_nephron_barrier_endothelium', 'health_atlas_nephron_barrier_slits', '121, y, 74, y, Ink.crosses.rawValue', '223, y, 269, y, Ink.salt.rawValue', 'time * 1.27', 'health_atlas_nephron_loop_gradient']);
requireTokens(source('CloseupCatalogue'), ['https://doi.org/10.1073/pnas.2318270121', 'https://pmc.ncbi.nlm.nih.gov/articles/PMC4010685/', 'references.insert(reference, at: min(1, references.count))', 'routes: routes, entryPhases: entryPhases']);
requireTokens(source('FunctionCatalogue'), ['revision: Int = 4440', 'original.mechanismCloseups()', '== 323']);
for (const name of ['BeatMotion', 'NephronMotion', 'FunctionPlayer', 'FunctionScene', 'FunctionPlaybackMenu', 'ChapterClock', 'SimulationPanel', 'Physiology', 'AgentContext', 'AgentHandoff', 'Detail', 'State']) assert.equal(source(name), prior(name), name);
for (const locale of ['en', 'zh-Hans']) assert.equal([...read('apps/ios/GalaxySSI/' + locale + '.lproj/AtlasMechanismCloseups.strings').matchAll(/^"health_atlas_/gm)].length, 20);
requireTokens(source('FunctionText'), ['table: "AtlasMechanismCloseups"']);
requireTokens(source(''), ['table: "AtlasMechanismCloseups"']);
requireTokens(read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift'), ['testPressureTraceRespectsValvesAndReplaysContinuously', 'for index in 1...19', 'testTipLinkOpeningRespondsInBothDirectionsAndClamps', 'testCloseupReferenceOverlayChangesOnlyHearingAndNephronReferences']);
const mapping = {
  HealthAtlasBeatStage: ['BeatPressure'], HealthAtlasHeartbeatView: ['HeartbeatView', 'PressureDrawing'],
  HealthAtlasHearingStoryView: ['HearingView', 'TipLinkDrawing', 'HearingMotion'], HealthAtlasSoundStage: ['HearingMotion'],
  HealthAtlasNephronStoryView: ['NephronView', 'RenalCloseupDrawing'], HealthAtlasFunctionStory: ['FunctionCatalogue', 'CloseupCatalogue']
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path), key = name.replace(/\.kt$/, '');
  let kind, ios, note;
  if (mapping[key]) {
    kind = 'native-production-port'; ios = mapping[key].map(swift);
    note = 'Exact pinned qualitative pressure nodes/interpolation, resized heart plus synchronized traces; bidirectional tip-link opening and potassium entry; renal three-layer filtration and countercurrent loop closeups; two ordered evidence references as applicable. Other chapters, original trajectories and measurements are not replaced. Native art pixels not certified.';
  } else if (file.path.includes('/androidTest/') || file.path.includes('/test/')) {
    kind = 'android-test-source-reference'; ios = ['apps/ios/GalaxySSITests/GalaxySSIHealthAtlasTests.swift', 'apps/ios/tools/check-atlas-mechanism-closeups-scope.cjs'];
    note = name + ': audited as source reference. Added Swift fixture sources for interior valve inequalities, cyclic pressure continuity, channel opening/clamping and idempotent reference overlay. Android pixel/animation/device assertions are NOT reproduced as executed iOS evidence; no XCTest run.';
  } else if (file.path.includes('/res/')) {
    kind = 'exact-bilingual-resource-delta'; ios = ['apps/ios/GalaxySSI/en.lproj/AtlasMechanismCloseups.strings', 'apps/ios/GalaxySSI/zh-Hans.lproj/AtlasMechanismCloseups.strings', swift('FunctionText'), swift(''), 'apps/ios/tools/import-body-atlas-regional-text.cjs', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];
    note = 'Twenty exact English/Chinese deltas from six original XML files: caption, legend, membrane-layer and new evidence labels. Registered in native locale chain and Xcode.';
  } else {
    assert.equal(name, 'build.gradle.kts'); kind = 'android-version-only'; ios = []; note = 'No iOS version bump or IPA.';
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
assert.equal(files.filter(f => f.kind === 'native-production-port').length, 6);
assert.equal(files.filter(f => f.kind === 'android-test-source-reference').length, 2);
for (const [suffix, value] of [['SOURCE_INVENTORY', inventory], ['PORT_COVERAGE', {schema: 1, source: inventory.source, verification: 'source-contracts-only-not-native-execution', files}]]) {
  const file = 'apps/ios/ANDROID_4440_' + suffix + '.json', content = JSON.stringify(value, null, 2) + '\n';
  if (process.argv.includes('--write')) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes('--checks')) for (const command of ['import-body-atlas-regional-text.cjs --mechanism-closeups-4440 --check', 'check-atlas-synchronized-lessons-scope.cjs --checks']) {
  const [file, ...args] = command.split(' ');
  cp.execFileSync(process.execPath, [path.join(__dirname, file), ...args], {cwd: root, stdio: 'inherit'});
}
console.log('Android #4440: fifteen original source hashes/dispositions, eleven exact pressure tuples, twenty bilingual pairs and native mechanism source contracts. No Swift compilation, XCTest or pixels claimed.');

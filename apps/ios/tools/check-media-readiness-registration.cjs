// Source contracts only; no Swift, media, playback, FFmpeg or runtime execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '39f7c9071eb6a39980f3af765deacc5e189ea3ff';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function retained(file, s) {
  if (file.endsWith('/AgentIOSMediaNativeTools.swift') && s.includes('  static let uncheckedAvailability =')) {
    assert.equal(s, show(approved, file), 'Only exact deferred/live media catalog delta');
    return show(base, file);
  }
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && s.includes('initialAvailability: AgentIOSMediaNativeToolCatalog.uncheckedAvailability')) {
    s = once(s, '      mediaExecutableDefinitions(provider: resolvedMediaProvider, nowMillis: nowMillis,\n' +
      '        initialAvailability: AgentIOSMediaNativeToolCatalog.uncheckedAvailability) +',
      '      mediaExecutableDefinitions(provider: resolvedMediaProvider, nowMillis: nowMillis) +');
    const first = '  static func mediaExecutableDefinitions(', last = '  private static func defaultMediaProvider(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Only exact media executable forwarding');
    s = once(s, block, section(show(base, file), first, last));
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const mediaFile = app + 'AgentIOSMediaNativeTools.swift', media = read(mediaFile);
  assert.equal(retained(mediaFile, media), show(base, mediaFile));
  const executor = 'struct AgentIOSMediaNativeToolExecutor {';
  assert.equal(media.slice(media.indexOf(executor)), show(base, mediaFile).slice(show(base, mediaFile).indexOf(executor)),
    'Actual media executor is byte-for-byte retained');
  assert.equal((media.match(/        initialAvailability: initialAvailability,/g) || []).length, 3);
  assert(media.includes('availability: initialAvailability ?? provider.availability(kind: kind)'));
  const hook = '      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in\n        provider.availability(kind: kind)\n      }';
  assert(media.includes(hook));
  const catalogFile = app + 'AgentPhoneNativeToolCatalog.swift', catalog = read(catalogFile);
  let unchanged = retained(catalogFile, catalog);
  const mcp = path.join(__dirname, 'check-mcp-readiness-preparation-scope.cjs');
  if (fs.existsSync(mcp)) unchanged = require(mcp).retained(catalogFile, unchanged);
  assert.equal(unchanged, show(base, catalogFile), 'All other catalog/default/provider construction retained');
  const allowed = (f, s) => { try { return retained(f, s) === show(base, f); } catch { return false; } };
  for (const changed of [media.replace(hook, '      availabilityProvider: .constant(.available)'),
    media.replace(hook, hook.replace('provider.availability(kind: kind)', 'descriptor.availability')),
    media.replace('availability: initialAvailability ?? provider.availability(kind: kind)', 'availability: provider.availability(kind: kind)'),
    media.replace('initialAvailability: AgentNativeToolAvailability? = nil', 'initialAvailability: AgentNativeToolAvailability? = .available'),
    media.replace('        kind: .playback,', '        kind: .metadata,'),
    media.replace('        initialAvailability: initialAvailability,', '        initialAvailability: nil,'),
    media + '\n// unrelated mutation\n']) {
    assert.notEqual(changed, media); assert(!allowed(mediaFile, changed));
  }
  const pinnedCatalog = show(approved, catalogFile);
  for (const changed of [pinnedCatalog.replace('initialAvailability: AgentIOSMediaNativeToolCatalog.uncheckedAvailability', 'initialAvailability: .available'),
    pinnedCatalog.replace('      initialAvailability: initialAvailability).map(executor.executableDefinition)', '      initialAvailability: nil).map(executor.executableDefinition)')]) {
    assert.notEqual(changed, pinnedCatalog); assert(!allowed(catalogFile, changed));
  }
  for (const name of ['AgentIOSFfmpegMediaProvider', 'AgentIOSFfmpegRuntimeAdapter', 'AgentIOSAVFoundationMediaProvider',
    'AgentIOSDefaultOnDeviceRuntimeProvider', 'AgentIOSQemuRuntime', 'AgentPhoneNativeTools', 'AgentNativeToolExecutionModels', 'AgentNativeToolCore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const testsFile = 'apps/ios/GalaxySSITests/AgentIOSMediaNativeToolTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile));
  const authored = section(tests, '// Readiness fixtures do not inspect media', 'extension GalaxySSIStoreTests {');
  assert.equal((authored.match(/  func test/g) || []).length, 8);
  assert.equal(once(tests, authored), show(base, testsFile), 'Existing media fixtures retained');
  assert(!/\p{Script=Han}/u.test(authored));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert(project.includes('AgentIOSMediaNativeToolTests.swift'));
  console.log('Media deferred registration/live readiness, exact executor/provider scope, nine negative source mutations and eight authored fixtures checked; no native execution.');
}

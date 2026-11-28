// Source contracts only; no Swift, camera, microphone or permission execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '86b00e64cc8143a31e44cf18cac03f27bdf96053';
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
  if (file.endsWith('/AgentIOSVisibleCaptureNativeTools.swift') && s.includes('  static let uncheckedAvailability =')) {
    assert.equal(s, show(approved, file), 'Only exact deferred/live capture catalog delta');
    return show(base, file);
  }
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && s.includes('initialAvailability: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability')) {
    s = once(s, '      visibleCaptureExecutableDefinitions(provider: visibleCaptureProvider,\n' +
      '        initialAvailability: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability) +',
      '      visibleCaptureExecutableDefinitions(provider: visibleCaptureProvider) +');
    const first = '  static func visibleCaptureExecutableDefinitions(', last = '  static func webIntelligenceExecutableDefinitions(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact capture helper forwarding');
    s = once(s, block, section(show(base, file), first, last));
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const captureFile = app + 'AgentIOSVisibleCaptureNativeTools.swift', capture = read(captureFile);
  assert.equal(retained(captureFile, capture), show(base, captureFile));
  const executor = 'struct AgentIOSVisibleCaptureNativeToolExecutor {';
  assert.equal(capture.slice(capture.indexOf(executor)), show(base, captureFile).slice(show(base, captureFile).indexOf(executor)),
    'Actual capture executor is byte-for-byte retained');
  assert.equal((capture.match(/        initialAvailability: initialAvailability,/g) || []).length, 2);
  assert(capture.includes('availability: initialAvailability ?? provider.availability(kind: kind)'));
  const hook = '      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in\n        provider.availability(kind: kind)\n      }';
  assert(capture.includes(hook));
  const catalogFile = app + 'AgentPhoneNativeToolCatalog.swift', catalog = read(catalogFile);
  let unchanged = retained(catalogFile, catalog);
  const mcp = path.join(__dirname, 'check-mcp-readiness-preparation-scope.cjs');
  if (fs.existsSync(mcp)) unchanged = require(mcp).retained(catalogFile, unchanged);
  assert.equal(unchanged, show(base, catalogFile), 'All other catalog/default/provider construction retained');
  const allowed = (f, s) => { try { return retained(f, s) === show(base, f); } catch { return false; } };
  for (const changed of [capture.replace(hook, '      availabilityProvider: .constant(.available)'),
    capture.replace(hook, hook.replace('provider.availability(kind: kind)', 'descriptor.availability')),
    capture.replace('availability: initialAvailability ?? provider.availability(kind: kind)', 'availability: provider.availability(kind: kind)'),
    capture.replace('initialAvailability: AgentNativeToolAvailability? = nil', 'initialAvailability: AgentNativeToolAvailability? = .available'),
    capture.replace('        kind: .audio,', '        kind: .photo,'),
    capture.replace('        initialAvailability: initialAvailability,', '        initialAvailability: nil,'),
    capture + '\n// unrelated mutation\n']) {
    assert.notEqual(changed, capture); assert(!allowed(captureFile, changed));
  }
  const pinnedCatalog = show(approved, catalogFile);
  for (const changed of [pinnedCatalog.replace('initialAvailability: AgentIOSVisibleCaptureNativeToolCatalog.uncheckedAvailability', 'initialAvailability: .available'),
    pinnedCatalog.replace('      initialAvailability: initialAvailability).map(executor.executableDefinition)', '      initialAvailability: nil).map(executor.executableDefinition)')]) {
    assert.notEqual(changed, pinnedCatalog); assert(!allowed(catalogFile, changed));
  }
  for (const name of ['AgentIOSForegroundVisibleCaptureProvider', 'AgentIOSVisibleCaptureUIKitSurfaces', 'AgentIOSVisibleCaptureArtifactStore',
    'AgentPhoneNativeTools', 'AgentNativeToolExecutionModels', 'AgentNativeToolCore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const testsFile = 'apps/ios/GalaxySSITests/AgentIOSVisibleCaptureNativeToolTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile));
  const authored = section(tests, '// Readiness-only fixtures never open a permission dialog', 'extension GalaxySSIStoreTests {');
  assert.equal((authored.match(/  func test/g) || []).length, 8);
  assert.equal(once(tests, authored), show(base, testsFile), 'Existing capture fixtures retained');
  assert(!/\p{Script=Han}/u.test(authored));
  assert(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').includes('AgentIOSVisibleCaptureNativeToolTests.swift'));
  console.log('Capture live/deferred readiness, exact provider/permission/executor scope, nine negative mutations and eight authored fixtures checked; no native execution.');
}

// Source contracts only. No Swift/XCTest, transport, storage fault or privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '0c178e6ccc7b357d7ff81441680e140fbad2990e';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const cache = new Map();
function show(ref, file) {
  const key = ref + ':' + file;
  if (!cache.has(key)) cache.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return cache.get(key);
}
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, 'Unique transport hook: ' + first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function restore(s, file, first, last) {
  const actual = section(s, first, last), prior = section(show(base, file), first, last);
  if (actual === prior) return s;
  assert.equal(actual, section(show(approved, file), first, last), 'Only the exact approved transport section may be normalized');
  return s.replace(actual, prior);
}
function retained(file, s) {
  if (file.endsWith('/GlobalRealtimeContext.swift')) {
    s = restore(s, file, 'struct GlobalAutonomousAction:', 'struct GlobalRunReplanDecision:');
    return restore(s, file, 'struct GlobalAutonomousRunReview:', 'enum GlobalAutonomousRunStatus:');
  }
  if (file.endsWith('/GlobalAgentDeliberationStore.swift'))
    return restore(s, file, '  func updateAutonomousRun(', '  func claimAutonomousWork(');
  if (file.endsWith('/GalaxySSIGlobalAutonomousRuntime.swift')) {
    s = restore(s, file, '  @MainActor\n  static func resourceAuthorized(', '\n}\n\nenum GalaxySSIGlobalAutonomousRunPlanner');
    const line = '          GlobalAutonomousSourceScope.transport(for: response, run: run) == request.transport,\n';
    assert(s.split(line).length <= 2); return s.replace(line, '');
  }
  if (file.endsWith('/GalaxySSIGlobalAutonomousModelRuntime.swift')) {
    s = restore(s, file, '  static func dispatchAction(', '  static func dispatchPlanReview(');
    s = restore(s, file, '  static func dispatchPlanReview(', '  private static func selectResource(');
    for (const [indent, run] of [['            ', 'reviewRun'], ['          ', 'run']]) {
      const call = indent + 'GlobalAutonomousSourceScope.resourceAuthorized(response.contactId,\n' + indent +
        '  transport: GlobalAutonomousSourceScope.transport(for: response, run: ' + run + '), store: appStore) else { return false }';
      assert(s.split(call).length <= 2);
      s = s.replace(call, indent + 'GlobalAutonomousSourceScope.resourceAuthorized(response.contactId, store: appStore) else { return false }');
    }
    return s;
  }
  if (file.endsWith('/GlobalAgentDeliberationStoreTests.swift') && s.includes('  func testAutonomousActionTransportRoundtripAndLegacyAbsence()')) {
    for (const [first, last] of [
      ['  func testAutonomousActionTransportRoundtripAndLegacyAbsence()', '  func testAutonomousSourcesIncludeMetadataAndSelectedCognitionContext()'],
      ['private final class AutonomousTransportFailureFileManager:', 'private extension Array {']
    ]) {
      const block = section(s, first, last);
      assert.equal(block, section(show(approved, file), first, last)); s = s.replace(block, '');
    }
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const files = ['GlobalRealtimeContext', 'GlobalAgentDeliberationStore', 'GalaxySSIGlobalAutonomousRuntime', 'GalaxySSIGlobalAutonomousModelRuntime']
    .map(name => app + name + '.swift').concat('apps/ios/GalaxySSITests/GlobalAgentDeliberationStoreTests.swift');
  for (const file of files) {
    const current = read(file);
    assert.equal(retained(file, current), show(base, file), file + ': all code outside exact approved hooks retained');
    assert.equal(retained(file, show(base, file)), show(base, file), 'Baseline normalization is a no-op');
  }
  const runtime = read(app + 'GalaxySSIGlobalAutonomousRuntime.swift');
  for (const token of ['guard let transport else { return false }', 'if transport == .onDeviceModel',
    'guard id != "phone-local-model"', 'contact.deliveryMode == .cloudAPI', 'contact.trustState == .verified',
    'guard matches(response, run: run)', 'run.review.resourceTransport', '== request.transport,']) assert(runtime.includes(token), token);
  const model = read(app + 'GalaxySSIGlobalAutonomousModelRuntime.swift');
  for (const token of ['running.resourceTransport = resource.transport', 'next.review.resourceTransport = resource.transport',
    'guard let updated = saved, deliberationStore.lastErrorDescription.isEmpty',
    'transport: GlobalAutonomousSourceScope.transport(for: response, run: reviewRun)',
    'transport: GlobalAutonomousSourceScope.transport(for: response, run: run)']) assert(model.includes(token), token);
  for (const [first, last] of [['  static func dispatchAction(', '  static func dispatchPlanReview('],
    ['  static func dispatchPlanReview(', '  private static func selectResource(']]) {
    const body = section(model, first, last);
    assert(body.indexOf('guard let updated = saved') < body.indexOf('let request = GalaxySSIGlobalAutonomousDispatchRequest('));
    assert(!body.includes('} ?? run'));
  }
  const consumer = section(model, '  static func consumeAutonomousResponse(', '  private static func consumePlanReview(');
  assert(consumer.indexOf('transport: GlobalAutonomousSourceScope.transport(for: response, run: run)') < consumer.indexOf('GalaxySSIGlobalAutonomousBudgetRuntime.complete('));
  for (const file of files.slice(0, 4)) {
    const current = read(file);
    const marker = file.endsWith('GlobalAgentDeliberationStore.swift') ? '  func updateAutonomousRun(' :
      file.endsWith('GlobalRealtimeContext.swift') ? 'struct GlobalAutonomousAction:' :
      file.endsWith('GalaxySSIGlobalAutonomousModelRuntime.swift') ? '  static func dispatchAction(' : '  static func resourceAuthorized(';
    assert.throws(() => retained(file, current.replace(marker, marker + '\n// synthetic unauthorized mutation')), assert.AssertionError);
    const changed = current.replace('import Foundation', 'import Foundation\n// unrelated synthetic mutation');
    assert.notEqual(changed, current);
    assert.notEqual(retained(file, changed), show(base, file), 'Unrelated changes remain visible');
  }
  const tests = 'apps/ios/GalaxySSITests/GlobalAgentDeliberationStoreTests.swift';
  assert.equal((read(tests).match(/  func test/g) || []).length - (show(base, tests).match(/  func test/g) || []).length, 9);
  assert(!/\p{Script=Han}/u.test(read(tests)));
  for (const name of ['GlobalBackgroundCognitionScope', 'GlobalResearchExecutorModels', 'GlobalAutonomousReplanPolicy',
    'GlobalAutonomousActionGraph', 'GalaxySSIGlobalAutonomousBudgetRuntime', 'GalaxySSIGlobalAutonomousResearchRuntime'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const checker = 'apps/ios/tools/check-autonomous-source-scope.cjs';
  const expectedChecker = show(base, checker)
    .replace("  clean(fs.readFileSync(path.join(root, f), 'utf8')));",
      "  require('./check-autonomous-transport-scope.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8'))));")
    .replace('function retained(file, s) {\n', 'function retained(file, s) {\n' +
      "  s = require('./check-autonomous-transport-scope.cjs').retained(file, s);\n");
  assert.equal(read(checker), expectedChecker, 'Every historical assertion retained');
  console.log('Persisted autonomous action/review transport, failure admission and exact scope contracts passed; nine XCTest methods authored, not executed.');
}

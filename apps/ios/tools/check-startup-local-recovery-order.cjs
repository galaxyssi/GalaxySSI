// Source contracts only; no Swift, startup, planner, native tools or OS execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '6aac1bb8b0d3ffb4e0e84578885a2dc548fd01d9';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => {
  const source = clean(fs.readFileSync(path.join(root, f), 'utf8'));
  const ownership = path.join(__dirname, 'check-planning-recovery-ownership.cjs');
  return f === app + 'GalaxySSIServices.swift' && fs.existsSync(ownership)
    ? require(ownership).retainedServices(source) : source;
};
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
function retained(f, s) {
  if (f.endsWith('/AgentRunPolicyTests.swift') && s.includes('  // Startup local-stage ordering fixtures;')) {
    const first = '  // Startup local-stage ordering fixtures;',
      last = '  @MainActor\n  func testAgentStartupRecoveryReconcilesBeforeDispatchAndFailsClosed()';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, f), first, last), 'Exact four authored startup-order fixtures only');
    return once(s, block);
  }
  if (f.endsWith('/AgentRunRecoveryCoordinator.swift') && s.includes('  static func reconcileLocal(')) {
    const first = '  @MainActor\n  static func reconcileLocal(', last = '  @MainActor\n  static func run(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, f), first, last), 'Exact staged local-recovery sequence only');
    return once(s, block);
  }
  if (f.endsWith('/GalaxySSIViews.swift') && s.includes('await AgentStartupRecoverySequence.reconcileLocal(')) {
    const first = '          reconcileLocalTasks: {', last = '          completion: {';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, f), first, last), 'Exact real root callback ordering only');
    return once(s, block, section(show(base, f), first, last));
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const sequenceFile = app + 'AgentRunRecoveryCoordinator.swift', sequence = read(sequenceFile);
  const rootFile = app + 'GalaxySSIViews.swift', view = read(rootFile);
  assert.equal(retained(sequenceFile, sequence), show(base, sequenceFile), 'Outer recovery, dispatch and retry unchanged');
  assert.equal(retained(rootFile, view), show(base, rootFile), 'All other root/startup/lifecycle code unchanged');
  const stages = section(sequence, '  @MainActor\n  static func reconcileLocal(', '  @MainActor\n  static func run(');
  const order = ['var reconciled = cancellations()', 'reconciled += cloud()', 'reconciled += interruptedNodes()', 'await planning()'];
  for (let i = 1; i < order.length; i++) assert(stages.indexOf(order[i - 1]) < stages.indexOf(order[i]));
  assert.equal((stages.match(/guard !Task.isCancelled/g) || []).length, 4);
  assert(!stages.slice(0, stages.indexOf('await planning()')).includes('await '), 'Old scans finish synchronously before new planning work');
  const allowed = (f, s) => { try { return retained(f, s) === show(base, f); } catch { return false; } };
  for (const changed of [sequence.replace('    guard !Task.isCancelled else { return 0 }\n', ''),
    sequence.replace('    guard !Task.isCancelled else { return reconciled }\n', ''),
    sequence.replace('reconciled += interruptedNodes()', 'reconciled += cloud()'),
    sequence.replace('return reconciled + (await planning())', 'return await planning()'),
    sequence + '\n// unrelated recovery mutation\n']) {
    assert.notEqual(changed, sequence); assert(!allowed(sequenceFile, changed));
  }
  assert(!allowed(rootFile, view.replace('planning: { await runtime.coordinator.recoverInterruptedInitialPlanning() }',
    'planning: { 0 }')));
  const servicesFile = app + 'GalaxySSIServices.swift';
  const planning = s => section(s, '  func recoverInterruptedInitialPlanning() async -> Int {', '  func resumePendingAgentDelivery() {');
  const actualPlanning = planning(read(servicesFile));
  assert.equal(actualPlanning, planning(show(base, servicesFile)), 'Planner recovery and dispatch permissions unchanged');
  assert(actualPlanning.includes('_ = applyLocalNativeActions('), 'Production planning recovery really can dispatch new native work');
  const testsFile = 'apps/ios/GalaxySSITests/AgentRunPolicyTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile));
  const authored = section(tests, '  // Startup local-stage ordering fixtures;',
    '  @MainActor\n  func testAgentStartupRecoveryReconcilesBeforeDispatchAndFailsClosed()');
  assert.equal((authored.match(/  func test/g) || []).length, 4);
  assert.equal(once(tests, authored), show(base, testsFile), 'Existing startup and run-policy fixtures retained');
  assert(!/\p{Script=Han}/u.test(authored));
  assert(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').includes('AgentRunPolicyTests.swift'));
  console.log('Real root recovery stage order, four cancellation fences, unchanged outer/planning paths, six negative mutations and four authored fixtures checked; no native execution.');
}

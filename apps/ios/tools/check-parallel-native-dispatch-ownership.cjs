// Source contracts only; no Swift, native dispatch, storage fault or concurrency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'aa1c2c3e7b95ad0b4407142c83875913e3d2ff5f';
const file = app + 'GalaxySSIServices.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
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
function retainedServices(s) {
  if (!s.includes('    let dispatchProfile = store.profile.identityFingerprint')) return s;
  const first = '  private func executeParallelLocalNativeActions(', last = '  private func preparedLocalNativeAction(';
  const block = section(s, first, last);
  assert.equal(block, section(show(approved, file), first, last), 'Only exact checked parallel ownership/projection hooks');
  return once(s, block, section(show(base, file), first, last));
}
function retained(f, s) {
  if (f === file) return retainedServices(s);
  if (f === app + 'GalaxySSIStoreTaskMutations.swift' && s.includes('  func commitNativeAgentTaskState(')) {
    const first = '  func commitNativeAgentTaskState(', last = '  private func projectLocalToolWorkspace(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, f), first, last), 'Exact checked Store normalization/projection only');
    return once(s, block);
  }
  return s;
}
module.exports = {retainedServices, retained};
if (require.main === module) {
  const services = read(file); let unchanged = retainedServices(services);
  for (const [name, method] of [['check-native-recovery-query-ownership', 'retainedServices'],
    ['check-native-observation-expiry-scope', 'retainedServices'], ['check-observation-job-lifecycle-scope', 'retainedServices'],
    ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-pairing-history', 'retainedPairingServices']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) unchanged = require(optional)[method](unchanged);
  }
  assert.equal(unchanged, show(base, file), 'All other coordinator paths retained');
  const parallel = section(services, '  private func executeParallelLocalNativeActions(', '  private func preparedLocalNativeAction(');
  const nativeWork = s => section(s, '    let executionActions = actions.map', '    guard results.count == actions.count,');
  assert.equal(nativeWork(parallel), nativeWork(section(show(base, file), '  private func executeParallelLocalNativeActions(', '  private func preparedLocalNativeAction(')),
    'Prepared input, encrypted node claim, executor and observation writes are unchanged');
  assert(parallel.indexOf('commitNativeAgentTaskState(expected: previous, updated: task)') < parallel.indexOf('Task.detached'));
  assert(parallel.indexOf('let proposedScope = AgentParallelNativeDispatchScope') < parallel.indexOf('commitNativeAgentTaskState(expected: previous, updated: task)'));
  assert.equal((parallel.match(/guard commitResults\(&task\) else \{ return \}/g) || []).length, 4);
  assert.equal((parallel.match(/dispatchScope.matches\(/g) || []).length, 3);
  assert(!parallel.includes('store.upsertAgentTask(task)'));
  const commit = section(parallel, '    func commitResults(', '    var updatedPlan = journaledPlan');
  assert(commit.indexOf('commitNativeAgentTaskState(expected: dispatchScope.task, updated: projected)') < commit.indexOf('AgentIOSNativeToolHandoffPresenter.openIfNeeded'));
  assert.equal((parallel.match(/AgentIOSNativeToolHandoffPresenter.openIfNeeded/g) || []).length, 1);
  const storeFile = app + 'GalaxySSIStoreTaskMutations.swift', store = read(storeFile);
  assert.equal(retained(storeFile, store), show(base, storeFile));
  const storeCommit = section(store, '  func commitNativeAgentTaskState(', '  private func projectLocalToolWorkspace(');
  assert(storeCommit.indexOf('AgentOutcomeContinuation.guardCompletion(') < storeCommit.indexOf('guard commitOwnedAgentTaskState('));
  assert(storeCommit.indexOf('guard commitOwnedAgentTaskState(') < storeCommit.indexOf('projectLocalToolWorkspace('));
  const helperFile = app + 'AgentParallelNativeDispatchScope.swift', helper = read(helperFile);
  assert.equal(helper, show(approved, helperFile));
  for (const token of ['task.phase == .executing, !task.blocked', 'task.localOperationProcessId == processId',
    'plan.executionMode != .planOnly', 'Set(actions.map(\\.id)).count == actions.count', 'action.kind == .callNativeTool',
    'owner.owns(action)', 'plan.actions.contains(running)', '!cancelled, profile == self.profile, task == self.task',
    'source.richOutputJson == self.source.richOutputJson', 'source.voiceTranscript == self.source.voiceTranscript']) assert(helper.includes(token), token);
  assert(!/FileManager|UserDefaults|URLSession|\.execute\(|\.publish\(|\.claim\(|\.remove\(/.test(helper));
  const mutations = [parallel.replace('          task.activePlan == plan,\n', ''),
    parallel.replace('cancelled: PhoneExecutionAuthority.isCancelled(taskId: taskId)', 'cancelled: false'),
    parallel.replace('profile: store.profile.identityFingerprint', 'profile: dispatchProfile'),
    parallel.replace('guard commitResults(&task) else { return }', '_ = commitResults(&task)'),
    parallel.replace('expected: dispatchScope.task, updated: projected', 'expected: store.agentTask(id: taskId)!, updated: projected'),
    parallel.replace('      projected = committed', '      projected = committed\n      store.upsertAgentTask(projected)')];
  for (const mutation of mutations) {
    assert.notEqual(mutation, parallel); assert.throws(() => retainedServices(services.replace(parallel, mutation)), assert.AssertionError);
  }
  assert.throws(() => retained(storeFile, store.replace('guard commitOwnedAgentTaskState(expected: expected, updated: guarded) else { return nil }',
    '_ = commitOwnedAgentTaskState(expected: expected, updated: guarded)')), assert.AssertionError);
  for (const name of ['AgentPlanNodeJournal', 'AgentActionEffectExecutor', 'AgentNativeToolExecutionModels', 'AgentToolCoordination', 'GalaxySSIStore']) {
    let source = read(app + name + '.swift');
    const pairing = path.join(__dirname, 'check-pairing-history.cjs');
    if (name === 'GalaxySSIStore' && fs.existsSync(pairing)) source = require(pairing).retainedPairingStore(source);
    assert.equal(source, show(base, app + name + '.swift'), name + ' unchanged outside exact pairing history hooks');
  }
  const testsFile = 'apps/ios/GalaxySSITests/AgentParallelNativeDispatchScopeTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 8);
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentParallelNativeDispatchScope(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Checked parallel dispatch, exact post-await ownership, four durable result branches, retained executor/store guards and eight authored fixtures checked; no native execution.');
}

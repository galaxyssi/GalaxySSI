// Source-only contracts. Not native scheduling, filesystem consistency or UI acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ec8f06067464ff05fbcee608139c1cda4d5ca3de';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) {
  assert.equal(s.split(from).length, 2, 'One dashboard hook: ' + from);
  return s.replace(from, to);
}
function retainedDashboardView(file, s) {
  const center = file.endsWith('/GalaxySSIControlCenterView.swift') || file === 'GalaxySSIControlCenterView.swift';
  const control = file.endsWith('/GalaxySSIGlobalAgentControlView.swift') || file === 'GalaxySSIGlobalAgentControlView.swift';
  if ((!center && !control) || !s.includes('@StateObject private var globalRuntime = GlobalAgentDashboardLoader()')) return s;
  s = once(s, '  @StateObject private var globalRuntime = GlobalAgentDashboardLoader()\n', center ? '' :
    '  @State private var cognitionTasks: [GlobalCognitionTask] = []\n  @State private var autonomousRuns: [GlobalAutonomousRun] = []\n  @State private var longHorizonGoals: [GlobalLongHorizonGoal] = []\n  @State private var researchState = GlobalResearchExecutorState()\n');
  s = once(s, '  private let globalRefreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()\n', '');
  s = once(s, '    .onChange(of: store.profile.identityFingerprint) { identity in\n      globalRuntime.refreshIfActive(identity: identity)\n    }\n    .onReceive(globalRefreshTimer) { _ in\n      globalRuntime.refreshIfActive(identity: store.profile.identityFingerprint)\n    }\n    .onDisappear { globalRuntime.invalidate() }\n', '');
  if (center) {
    s = once(s, '  var onBackToAgent:', '  private let globalAgentDeliberationStore = GlobalAgentDeliberationStore()\n  private let globalAgentLongHorizonStore = GlobalLongHorizonGoalStore()\n  var onBackToAgent:');
    s = once(s, '      globalRuntime.refresh(identity: store.profile.identityFingerprint)\n', '');
  } else {
    s = once(s, '  private var snapshot: GalaxySSIGlobalAgentDashboardSnapshot {', '  private let deliberationStore = GlobalAgentDeliberationStore()\n  private let longHorizonStore = GlobalLongHorizonGoalStore()\n\n  private var snapshot: GalaxySSIGlobalAgentDashboardSnapshot {');
    s = once(s, '    let verifiedResearch = globalRuntime.snapshot.researchState.tasks.filter {', '    let verifiedResearch = researchState.tasks.filter {');
    s = once(s, '    globalRuntime.refresh(identity: store.profile.identityFingerprint)\n', '    cognitionTasks = deliberationStore.cognitionTasks()\n    autonomousRuns = deliberationStore.autonomousRuns()\n    longHorizonGoals = longHorizonStore.goals()\n    researchState = GalaxySSIGlobalAgentRuntimeBridge.researchState()\n');
  }
  for (const [key, prior] of [
    ['cognitionTasks', center ? 'globalAgentDeliberationStore.cognitionTasks()' : 'cognitionTasks'],
    ['autonomousRuns', center ? 'globalAgentDeliberationStore.autonomousRuns()' : 'autonomousRuns'],
    ['longHorizonGoals', center ? 'globalAgentLongHorizonStore.goals()' : 'longHorizonGoals'],
    ['researchState', center ? 'GalaxySSIGlobalAgentRuntimeBridge.researchState()' : 'researchState'],
  ]) s = once(s, key + ': globalRuntime.snapshot.' + key, key + ': ' + prior);
  return s;
}
function validateDashboardRefresh() {
  for (const name of ['GalaxySSIControlCenterView', 'GalaxySSIGlobalAgentControlView']) {
    const file = app + name + '.swift', source = read(file);
    assert.equal(retainedDashboardView(file, source), old(file), 'Only declared runtime snapshot/lifecycle hooks: ' + name);
    assert(source.includes('.onDisappear { globalRuntime.invalidate() }'));
    assert(source.includes('globalRuntime.refreshIfActive(identity: store.profile.identityFingerprint)'));
    for (const field of ['cognitionTasks', 'autonomousRuns', 'longHorizonGoals', 'researchState'])
      assert(source.includes(field + ': globalRuntime.snapshot.' + field));
    assert(!source.includes('GlobalAgentDeliberationStore()') && !source.includes('GlobalLongHorizonGoalStore()'));
    assert(!source.includes('GalaxySSIGlobalAgentRuntimeBridge.researchState()'));
  }
  const source = read(app + 'GlobalAgentDashboardLoader.swift');
  for (const token of ['@MainActor\nfinal class GlobalAgentDashboardLoader', 'qos: .utility',
    'queue.async { [weak self]', 'let result = read()', 'Task { @MainActor [weak self] in',
    'guard token == completed else { return (false, nil) }', 'guard completion.accepted else { return }',
    'guard state.identity != nil else { return }', 'if let result { snapshot = result }',
    'refreshFailed = result == nil', 'if let next = completion.next { launch(next) }',
    'guard token == nil else { pending = true; return nil }']) assert(source.includes(token), token);
  assert.equal((source.match(/lastErrorDescription.isEmpty else \{ return nil \}/g) || []).length, 4);
  assert(!source.includes('GalaxySSIStore') && !source.includes('MessageCoordinator') && !source.includes('agentRouting'));
  for (const name of ['GalaxySSIServices', 'GalaxySSIGlobalAgentRuntime', 'GlobalRealtimeContextProvider',
    'GlobalAgentDeliberationStore', 'GlobalLongHorizonGoalStore', 'GalaxySSIStoreGlobalAgentInbox',
    'GalaxySSIGlobalAgentControlModels', 'GalaxySSIDeviceIdentity']) assert.equal(name === 'GalaxySSIDeviceIdentity'
      ? require('./check-local-workspace-device-scope.cjs').retainedLocalDeviceIdentity(read(app + name + '.swift'))
      : read(app + name + '.swift'), old(app + name + '.swift'), name);
  const android = clean(cp.execFileSync('git', ['diff', '65655f0c79c6ab04121150229a65b089180f82f2^1',
    '65655f0c79c6ab04121150229a65b089180f82f2', '--', 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityGlobalAgent.kt'], {cwd: root, encoding: 'utf8'}));
  assert(android.includes('-        agentRoutingExecutor.execute {'));
  assert(android.includes('+        navigationContentExecutor.execute {'));
  const tests = read('apps/ios/GalaxySSITests/GlobalAgentDashboardLoaderTests.swift');
  for (const name of ['BurstRequestsCoalesceIntoOneTrailingRefresh', 'InvalidationRejectsOldCompletion',
    'IdentityChangeRejectsOldResultWithoutClearingNewWork', 'DuplicateCompletionCannotAcceptOrScheduleTwice',
    'RefreshDoesNotReadSourcesOnCaller', 'FailedReadKeepsLastCompleteSnapshot', 'OffscreenPollingDoesNotReactivateLoader'])
    assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['GlobalAgentDashboardLoader', 'GlobalAgentDashboardLoaderTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name + ' target registration');
}
module.exports = {retainedDashboardView, validateDashboardRefresh};
if (require.main === module) { validateDashboardRefresh(); console.log('Dashboard background snapshot/lifecycle source contracts passed; no native acceptance'); }

// Exact source contracts, not Swift concurrency, timer, cancellation or transport execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'd072820ca5ab630badea6e38d1ea62229c4bcc8b';
const file = app + 'GalaxySSIServices.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function retainedServices(s) {
  if (!s.includes('  private func cancelNativeConnectorObservation(key: String)')) return s;
  for (const [first, last, originalFirst = first] of [
    ['  private func installForegroundRecoveryWake()', '  private func resumePendingIncomingAttachmentDownloads('],
    ['  func cancelLocalAgentTask(', '  @discardableResult\n  func endLocalAgentSession('],
    ['  private func cancelNativeConnectorObservation(key:', '  private func recordNativeConnectorObservation(', '  private func scheduleNativeConnectorObservation('],
    ['  private func resumeWaitingNativeConnectors(', '  private func permitsVerifiedTimerStart(']
  ]) {
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Only exact approved lifecycle hooks normalize');
    s = once(s, block, section(show(base, file), originalFirst, last));
  }
  return once(s, '  private var nativeConnectorObservationJobs: [String: (token: UUID, clock: String, profile: String, task: Task<Void, Never>)] = [:]',
    '  private var nativeConnectorObservationJobs: [String: (token: UUID, clock: String, task: Task<Void, Never>)] = [:]');
}
module.exports = {retainedServices};
if (require.main === module) {
  const service = read(file); let unchanged = retainedServices(service);
  for (const [name, method] of [['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-pairing-history', 'retainedPairingServices']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) unchanged = require(optional)[method](unchanged);
  }
  assert.equal(unchanged, show(base, file), 'All other coordinator policy and effect code retained');
  const schedule = section(service, '  private func scheduleNativeConnectorObservation(', '  private func observeWaitingNativeConnector(');
  assert(!schedule.includes('self.nativeConnectorObservationJobs.removeValue(forKey: key)'));
  assert(schedule.includes('nativeConnectorObservationJobs.count < 200'));
  assert(schedule.includes('nativeConnectorObservationJobs[key]?.clock == wake.clock'));
  const observe = section(service, '  private func observeWaitingNativeConnector(', '  private func recordNativeConnectorObservation(');
  const fence = 'guard !Task.isCancelled, nativeConnectorObservationJobs[key]?.token == token else { return }';
  assert.equal(observe.split(fence).length - 1, 2, 'Ownership checked before query and after suspension');
  assert(observe.indexOf(fence) < observe.indexOf('nativeConnectorObservationContext('));
  assert(observe.lastIndexOf(fence) > observe.indexOf('await sweepDesktopReplyRecovery()'));
  assert(observe.lastIndexOf(fence) < observe.lastIndexOf('nativeConnectorObservationJobs.removeValue(forKey: key)'));
  const cancel = section(service, '  private func cancelNativeConnectorObservation(key:', '  private func scheduleNativeConnectorObservation(');
  for (const token of ['.task.cancel()', 'nativeConnectorObservationLastWake.removeValue(forKey: key)',
    'retainingProfile == job.profile', 'nativeConnectorObservationLastWake.removeAll()',
    'AgentIOSConnectorDispatch(action: action, receipt: pending)', 'task.activePlan?.actions ?? []']) assert(cancel.includes(token), token);
  const resume = section(service, '  private func resumeWaitingNativeConnectors(', '  private func permitsVerifiedTimerStart(');
  assert(resume.indexOf('store.commitOwnedAgentTaskState(expected: previous, updated: task)') <
    resume.indexOf('cancelNativeConnectorObservation(action: action, pending: pending)'));
  const userCancel = section(service, '  func cancelLocalAgentTask(', '  @discardableResult\n  func endLocalAgentSession(');
  assert(userCancel.indexOf('guard store.persistLocalWorkspaceCancellation') < userCancel.indexOf('cancelNativeConnectorObservations(for: task)'));
  const lifecycle = section(service, '  private func installForegroundRecoveryWake()', '  private func resumePendingIncomingAttachmentDownloads(');
  for (const token of ['UIApplication.willResignActiveNotification', 'UIApplication.protectedDataWillBecomeUnavailableNotification',
    '.galaxySSIRuntimePlaintextWillClear', 'self?.cancelNativeConnectorObservations()', 'UIApplication.didBecomeActiveNotification',
    'self.resumeWaitingNativeConnectors()']) assert(lifecycle.includes(token), token);
  const mutations = [
    service.replace(fence, 'guard !Task.isCancelled else { return }'),
    service.replace(observe, observe.replace(observe.slice(observe.lastIndexOf(fence), observe.lastIndexOf(fence) + fence.length), '')),
    service.replace('await self.observeWaitingNativeConnector(', 'self.nativeConnectorObservationJobs.removeValue(forKey: key)\n      await self.observeWaitingNativeConnector('),
    service.replace('retainingProfile == job.profile', 'true'),
    service.replace('self?.cancelNativeConnectorObservations()', 'self?.clearSupervisedAnswerPreviews()'),
    service.replace('self.resumeWaitingNativeConnectors()', 'self.refreshAgentHomeState()'),
    service.replace('cancelNativeConnectorObservations(for: task)', 'cancelNativeConnectorObservations()'),
    service.replace('      cancelNativeConnectorObservation(action: action, pending: pending)\n      var executed', '      var executed')
  ];
  for (const mutation of mutations) {
    assert.notEqual(mutation, service);
    assert.throws(() => retainedServices(mutation), assert.AssertionError);
  }
  for (const name of ['AgentAutomationModels', 'AgentConnectorTimeoutResolver', 'AgentDesktopReplyRecovery',
    'AgentIOSConnectorDispatch', 'AgentConnectorResponseResolver', 'AgentControlPlaneActionExecutorModels'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  assert(!/handleConnectorTimeout\(|connectorFallbackAction\(|\.publish\(|enqueueLinkPayload\(/.test(observe));
  const android = show('e7c6af6ef3eed21c7fb697b4458d1cf742833dc4',
    'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityAgentExecution.kt');
  assert(android.includes('internal fun MainActivity.cancelConnectorTimeouts(sourceMessageId: Long)'));
  assert(android.includes('agentConnectorTimeoutCallbacks.remove(callbackKey, callback)'));
  console.log('Observation query lifetime, token replacement fences, cancellation/foreground hooks, exact coordinator scope and eight negative source mutations passed; no native execution.');
}

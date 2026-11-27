// Source contracts only; no Swift, native recovery, clock, MQTT or storage execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'd83f2c41d709f3f2a667871a1530021d00b50760';
const serviceFile = app + 'GalaxySSIServices.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
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
  if (!s.includes('AgentNativeConnectorObservationExpiry.project(')) return s;
  const first = '  private func preserveNativeConnectorObservation(', last = '  private func markQueuedConnectorUnknown(';
  const block = section(s, first, last);
  assert.equal(block, section(show(approved, serviceFile), first, last), 'Only exact owned expiry presentation/commit hooks');
  s = once(s, block, section(show(base, serviceFile), first, last));
  s = once(s, '!preserveNativeConnectorObservation(source, observation: record, nowMillis: now)', '!preserveNativeConnectorObservation(source)');
  return once(s, 'preserveNativeConnectorObservation(managed, observation: record, nowMillis: now)', 'preserveNativeConnectorObservation(managed)');
}
module.exports = {retainedServices};
if (require.main === module) {
  const services = read(serviceFile); let unchanged = retainedServices(services);
  for (const [name, method] of [['check-observation-job-lifecycle-scope', 'retainedServices'],
    ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-pairing-history', 'retainedPairingServices']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) unchanged = require(optional)[method](unchanged);
  }
  assert.equal(unchanged, show(base, serviceFile), 'All other coordinator behavior retained');
  const file = app + 'AgentNativeConnectorObservationExpiry.swift', helper = read(file);
  assert.equal(helper, show(approved, file));
  for (const token of ['managed.state == .pending, managed.response == nil', 'binding.isValid', 'binding.teamSource == nil',
    'owner.ownerRunId == managed.ownerRunId', 'owner.sourceMessageId == managed.sourceMessageId',
    'owner.executionGeneration == managed.executionGeneration', 'pending.metadata["awaiting_response"] == "true"',
    'observation.expiryReason(now: nowMillis)', 'AgentRemoteOutcomePolicy.isTerminal(observation.status)',
    'observation.generation == managed.executionGeneration', 'observation.sequence >= 0',
    'observation.lastResponseAt <= nowMillis', 'native_connector_observation_expiry_clock',
    'updated.metadata["non_retriable"] = "true"', 'updated.metadata["effect_outcome_unknown"] = "true"',
    '"observed_failure": .bool(false)', '"terminal_failure": .bool(false)']) assert(helper.includes(token), token);
  assert(!/FileManager|UserDefaults|URLSession|\.execute\(|\.publish\(|\.release\(|AgentDesktopReplyRecovery\./.test(helper));
  const owned = section(services, '  private func preserveNativeConnectorObservation(', '  private func markQueuedConnectorUnknown(');
  for (const token of ['store.canReadAgentTranscript', 'desktopReplyRecovery.record(for: observation.binding) == observation',
    'currentManagedDesktopReply(observation.binding) == record', '!PhoneExecutionAuthority.isCancelled',
    '!session.privateMode, !session.trackingPaused', 'else { return true }', 'if expiry.missingResult',
    'updated.phase = .blocked', 'updated.blocked = true', 'updated.result = updated.verification',
    'store.commitOwnedAgentTaskState(expected: task, updated: updated)']) assert(owned.includes(token), token);
  assert(!/connectorResponseBus.publish|\.retire\(|\.release\(|connectorFallbackAction\(/.test(owned));
  const accepted = s => { try { retainedServices(s); return true; } catch { return false; } };
  for (const changed of [owned.replace('currentManagedDesktopReply(observation.binding) == record,', ''),
    owned.replace('desktopReplyRecovery.record(for: observation.binding) == observation,', ''),
    owned.replace('    if expiry.missingResult {', '    if true {'),
    owned.replace('      updated.phase = .blocked', '      updated.phase = .failed'),
    owned.replace('var plan = task.activePlan, let index = plan.actions.firstIndex(where: { $0.id == waiting.id }) else { return true }',
      'var plan = task.activePlan, let index = plan.actions.firstIndex(where: { $0.id == waiting.id }) else { return false }')]) {
    assert.notEqual(changed, owned); assert(!accepted(services.replace(owned, changed)));
  }
  for (const name of ['AgentDesktopReplyRecovery', 'AgentConnectorResponseResolver', 'AgentIOSConnectorDispatch',
    'AgentControlPlaneActionExecutorModels', 'AgentManagedResponseModels', 'AgentConnectorTaskStatusRecorder'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentNativeConnectorObservationExpiryTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 8);
  assert(!/\p{Script=Han}/u.test(helper + tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentNativeConnectorObservationExpiry(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  const android = show(base, 'apps/android/app/src/main/java/com/galaxyssi/chat/AndroidAgentRemoteSilence.kt');
  assert(android.includes('terminalDeliveryExpired(context, delivery.sourceMessageId, now)'));
  assert(android.includes('R.string.agent_desktop_result_unavailable'));
  console.log('Owned observation stage escalation, unknown-result blocking, exact commit/transport scope and eight authored fixtures checked as source; no native execution.');
}

// Source contracts only; no Swift, SQLite, MQTT or connector execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '5a56704e593dbd94c4aa41dce3bc3dd69ec24f21';
const file = app + 'GalaxySSIServices.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => {
  const source = clean(fs.readFileSync(path.join(root, f), 'utf8'));
  const deadline = path.join(__dirname, 'check-connector-deadline-checkpoint.cjs');
  return fs.existsSync(deadline) ? require(deadline).retained(f, source) : source;
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
function retainedServices(s) {
  const deadline = path.join(__dirname, 'check-connector-deadline-checkpoint.cjs');
  if (fs.existsSync(deadline)) s = require(deadline).retainedServices(s);
  if (!s.includes('  private func managedNativeRecoveryMayQuery(')) return s;
  const first = '  private func managedNativeRecoveryMayQuery(', last = '  private func nativeConnectorObservationContext(';
  const block = section(s, first, last);
  assert.equal(block, section(show(approved, file), first, last), 'Only exact native query authorization normalizes');
  s = once(s, block);
  s = once(s, '    guard managedNativeRecoveryMayQuery(source) else { return false }\n    if let reason = record.expiryReason(now: now),',
    '    if let reason = record.expiryReason(now: now),');
  return once(s, '      if record.binding.managedSource != nil {\n        guard let managed = currentManagedDesktopReply(record.binding, allowCommitted: true),\n              managedNativeRecoveryMayQuery(managed) else { continue }\n      }\n      guard requests.count < 4, ready(record.binding) else { continue }',
    '      guard requests.count < 4, ready(record.binding) else { continue }');
}
function retained(f, s) {
  const deadline = path.join(__dirname, 'check-connector-deadline-checkpoint.cjs');
  if (fs.existsSync(deadline)) s = require(deadline).retained(f, s);
  if (f === file) return retainedServices(s);
  if ([app + 'AgentManagedResponseModels.swift', app + 'UserDefaultsAgentManagedResponseLedger.swift'].includes(f)) {
    if (!s.includes('nativeQueryScope')) return s;
    assert.equal(s, show(approved, f), 'Exact scope persistence/copy/migration delta only');
    return show(base, f);
  }
  if (f === app + 'AgentControlPlaneActionExecutorModels.swift' && s.includes('var nativeQueryScope:')) {
    const first = '        var nativeQueryScope: AgentNativeConnectorQueryScope?', last = '        try managedResponseLedger.register(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, f), first, last), 'Exact producer capture before register/start');
    s = once(s, block);
    return once(s, '            executionGeneration: executionGeneration,\n            nativeQueryScope: nativeQueryScope',
      '            executionGeneration: executionGeneration');
  }
  return s;
}
module.exports = {retainedServices, retained};
if (require.main === module) {
  const services = read(file), gate = section(services, '  private func managedNativeRecoveryMayQuery(', '  private func nativeConnectorObservationContext(');
  let unchanged = retainedServices(services);
  for (const [name, method] of [['check-native-observation-expiry-scope', 'retainedServices'],
    ['check-observation-job-lifecycle-scope', 'retainedServices'],
    ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-pairing-history', 'retainedPairingServices']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) unchanged = require(optional)[method](unchanged);
  }
  assert.equal(unchanged, show(base, file), 'All other coordinator policy, result reception and commits retained');
  for (const name of ['AgentManagedResponseModels', 'UserDefaultsAgentManagedResponseLedger', 'AgentControlPlaneActionExecutorModels']) {
    const f = app + name + '.swift'; assert.equal(retained(f, read(f)), show(base, f), name);
  }
  for (const token of ['record.nativeQueryScope == nil', 'candidates.count == 1',
    'record.nativeQueryScope == nil || record.nativeQueryScope == scope',
    'scope.profile == store.profile.identityFingerprint', 'UIApplication.shared.applicationState == .active',
    '!store.agentSafetySettings.executionPaused, store.agentSafetySettings.connectorCallsAllowed',
    'taskExecutionMode != .planOnly', '[AgentPermissionMode.observeOnly, .suggestOnly]',
    'waiting.parameters[AgentIOSConnectorDispatch.permissionKey] == store.agentSafetySettings.permissionMode.rawValue',
    '!PhoneExecutionAuthority.isCancelled', 'task.phase == .waitingResponse', 'task.phase == .blocked',
    '!session.privateMode, !session.trackingPaused', 'session.mergedIntoConversationId.isBlank',
    'dispatch.sourceMessageId == record.sourceMessageId', 'dispatch.owner == record.ownerRunId',
    'pending.metadata["control_plane_agent_id"] == record.agentId', 'dispatch.taskId == record.taskId',
    'record.executionGeneration', 'store.persistedMessage(id: scope.outgoingId, contactId: "hermes")',
    'AgentNativeConnectorContinuation.waitingAction(']) assert(gate.includes(token), token);
  assert(!/\.publish\(|\.retire\(|\.release\(|\.execute\(|\.cancel\(|commitOwnedAgentTaskState/.test(gate));
  const legacy = section(services, '  private func sweepManagedDesktopReply(', '  private func persistRecoveredManagedDesktopResult(');
  const journal = section(services, '  private func journalBackedDesktopRecoveryQueries(', '  private func commitJournalBackedDesktopResult(');
  assert(legacy.indexOf('managedNativeRecoveryMayQuery(source)') < legacy.indexOf('record.expiryReason(now: now)'),
    'Unauthorized native waits cannot be converted to synthetic failures by the legacy expiry branch');
  for (const [block, local, query] of [[legacy, 'persistRecoveredManagedDesktopResult(', 'desktopReplyRecovery.request('],
    [journal, 'commitJournalBackedDesktopResult(', 'let request = terminal']]) {
    assert(block.indexOf(local) < block.indexOf('managedNativeRecoveryMayQuery('));
    assert(block.indexOf('managedNativeRecoveryMayQuery(') < block.indexOf(query));
  }
  const mutations = [
    ['scope.profile == store.profile.identityFingerprint,', 'true,'],
    ['record.nativeQueryScope == nil || record.nativeQueryScope == scope,', 'true,'],
    ['!session.privateMode, !session.trackingPaused,', 'true,'],
    ['!store.agentSafetySettings.executionPaused, store.agentSafetySettings.connectorCallsAllowed,', 'true,'],
    ['dispatch.sourceMessageId == record.sourceMessageId,', 'true,'],
    ['pending.metadata["control_plane_agent_id"] == record.agentId,', 'true,'],
    ['UIApplication.shared.applicationState == .active,', 'true,']
  ];
  for (const [from, to] of mutations) {
    assert(gate.includes(from)); assert.throws(() => retainedServices(services.replace(gate, gate.replace(from, to))), assert.AssertionError);
  }
  for (const hook of ['managedNativeRecoveryMayQuery(source)', 'managedNativeRecoveryMayQuery(managed)'])
    assert.throws(() => retainedServices(once(services, hook, 'true')), assert.AssertionError);
  const testsFile = 'apps/ios/GalaxySSITests/AgentManagedResponseTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile));
  const first = '// Native query ownership fixtures;', last = 'extension GalaxySSIStoreTests {\n  func testManagedCollaborationRepliesRecoverAfterExtendedOfflineReopen()';
  const authored = section(tests, first, last);
  assert.equal((authored.match(/  func test/g) || []).length, 6);
  assert.equal(once(tests, authored), show(base, testsFile));
  for (const name of ['AgentIOSConnectorDispatch', 'AgentConnectorResponseResolver', 'AgentDesktopReplyRecovery',
    'AgentConnectorTaskStatusRecorder'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').includes('AgentManagedResponseTests.swift'), true);
  console.log('Exact native query ownership, two publication gates, nine negative source mutations and six authored fixtures checked; no native execution.');
}

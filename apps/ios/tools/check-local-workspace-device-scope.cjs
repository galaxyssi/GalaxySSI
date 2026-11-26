// Source contracts, not native identity, workspace migration or cancellation acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '93e3ef38e6f4c14357d89ae19ca0a4040196574a';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) {
  assert.equal(s.split(from).length, 2, 'One local device hook: ' + from);
  return s.replace(from, to);
}
function retainedLocalDeviceMutations(s) {
  const identity = '    let localDeviceId = GalaxySSIDeviceIdentity.localDeviceId(profile: profile)\n';
  assert.equal(s.split(identity).length, 4);
  s = s.split(identity).join('');
  for (const name of ['current', '$0', 'base'])
    s = once(s, 'Self.isLocalWorkspace(' + name + ', for: task, localDeviceId: localDeviceId)', 'Self.isLocalWorkspace(' + name + ', for: task)');
  s = once(s, '  private static func isLocalWorkspace(_ workspace: AgentWorkspace, for task: AgentTaskRecord,\n                                       localDeviceId: String) -> Bool {',
    '  private static func isLocalWorkspace(_ workspace: AgentWorkspace, for task: AgentTaskRecord) -> Bool {');
  s = once(s, '      workspace.parentRunId.isBlank && workspace.agentId.isBlank &&\n      (workspace.deviceId.isBlank || workspace.deviceId == localDeviceId) &&',
    '      workspace.parentRunId.isBlank && workspace.agentId.isBlank && workspace.deviceId.isBlank &&');
  s = once(s, '        conversationId: task.sessionId, taskId: task.taskId, goal: task.goal,\n        deviceId: localDeviceId, createdAtMillis: task.createdAtMillis)',
    '        conversationId: task.sessionId, taskId: task.taskId, goal: task.goal, createdAtMillis: task.createdAtMillis)');
  s = once(s, '      if base.deviceId.isBlank { base.deviceId = localDeviceId }\n', '');
  return once(s, '        next.deviceId == existing.deviceId &&\n', '');
}
function retainedLocalDeviceProjection(s) {
  return once(s, '    if (!workspace.deviceId.isBlank && workspace.deviceId != GalaxySSIDeviceIdentity.localDeviceId(profile: profile)) ||\n        routeKind == .desktopAgent {',
    '    if !workspace.deviceId.isBlank || routeKind == .desktopAgent {');
}
function retainedLocalDeviceIdentity(identity) {
  if (!identity.includes('  static func localDeviceId(profile: GalaxySSIProfile) -> String {')) return identity;
  const getter = '  static func localDeviceId(profile: GalaxySSIProfile) -> String {\n    let fingerprint = clean(profile.identityFingerprint)\n    return "ios-\\(fingerprint.prefix(16))"\n  }\n\n';
  identity = once(identity, getter, '');
  return once(identity, '      deviceId: localDeviceId(profile: profile),', '      deviceId: "ios-\\(fingerprint.prefix(16))",');
}
function validateLocalWorkspaceDevice() {
  const mutations = read(app + 'GalaxySSIStoreTaskMutations.swift'), projection = read(app + 'GalaxySSIStoreTaskProjection.swift');
  assert.equal(retainedLocalDeviceMutations(mutations), old(app + 'GalaxySSIStoreTaskMutations.swift'),
    'Only device attribution/legacy stamp/owned-device cancellation hooks; unchanged route, privacy, scope, revision retry and terminal controls');
  assert.equal(retainedLocalDeviceProjection(projection), old(app + 'GalaxySSIStoreTaskProjection.swift'),
    'Only local device location classification; remote run/agent route and merged record rules retained');
  assert(mutations.indexOf('guard Self.isLocalWorkspace(base, for: task, localDeviceId: localDeviceId)') <
    mutations.indexOf('if base.deviceId.isBlank { base.deviceId = localDeviceId }'));
  assert(mutations.includes('workspace.parentRunId.isBlank && workspace.agentId.isBlank &&'));
  assert(mutations.includes('workspace.remoteRunId.isBlank && workspace.deliveryMode == AgentDeliveryMode.respond.rawValue'));
  assert(read(app + 'GalaxySSIDeviceIdentity.swift').includes('  static func localDeviceId(profile: GalaxySSIProfile) -> String {'));
  assert.equal(retainedLocalDeviceIdentity(read(app + 'GalaxySSIDeviceIdentity.swift')), old(app + 'GalaxySSIDeviceIdentity.swift'), 'Existing device ID algorithm/name/pairing metadata unchanged; getter reads only cached profile');
  for (const name of ['GalaxySSIStore', 'GalaxySSIStoreSessions', 'GalaxySSIServices',
    'AgentWorkspaceModels', 'AgentWorkspaceStore', 'AgentTaskWorkspaceControlReducer',
    'AgentWorkspaceExecutionSnapshotReducer', 'AgentPlanNodeJournal', 'AgentSequentialPlanNodeDispatch'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const android = clean(cp.execFileSync('git', ['diff', '65655f0c79c6ab04121150229a65b089180f82f2^1',
    '65655f0c79c6ab04121150229a65b089180f82f2', '--', 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityAgentExecution.kt'], {cwd: root, encoding: 'utf8'}));
  assert(android.includes('+        deviceId = AppStore.localDeviceRouteId(this),'));
  const tests = read('apps/ios/GalaxySSITests/AgentLocalWorkspaceDeviceTests.swift');
  for (const name of ['FastDeviceGetterPreservesTheExistingPairingIdentifier', 'NewLocalProjectionUsesExistingPhoneDeviceIdentity', 'LegacyBlankDeviceIsStampedEvenWithoutToolOrStatusChanges',
    'ForeignDeviceWorkspaceIsNotRelabeledByLocalTaskProjection', 'CurrentAndLegacyDeviceWorkspacesRemainCancellable',
    'ForeignOrRemoteScopesCannotBeCancelledAsLocal', 'InterruptedCancellationRecoveryAcceptsOnlyCurrentOrLegacyDevices',
    'WorkspaceOnlyPhoneProjectionDoesNotBecomeDesktopWhenDeviceIsSet', 'PrivateAndTrackingPausedSessionsStillDoNotProjectWorkspaces'])
    assert(tests.includes('func test' + name + '('), name);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('AgentLocalWorkspaceDeviceTests.swift in Sources */').length, 3);
}
module.exports = {retainedLocalDeviceMutations, retainedLocalDeviceProjection, retainedLocalDeviceIdentity, validateLocalWorkspaceDevice};
if (require.main === module) { validateLocalWorkspaceDevice(); console.log('Local workspace device attribution, projection and cancellation source contracts passed; no native acceptance'); }

// Source contracts only, not executed Swift, authenticated delivery or restart acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), base = '4c7529b9c';
const app = 'apps/ios/GalaxySSI/';
const read = file => require('./check-connector-document-input-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const show = (ref, file) => cp.execFileSync('git', ['show', `${ref}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const statusAnchor = '\n// The caller must supply an already authenticated, durably accepted recovery observation.';
const translation = '"galaxyssi.agent.connector.waiting_original_result" = "\u6b63\u5728\u7b49\u5f85\u539f\u8fde\u63a5\u5668\u4efb\u52a1\u7684\u7ed3\u679c\u3002";\n';
function retained(file, source) {
  source = require('./check-managed-raw-attachments-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentNativeConnectorStatusObservationTests.swift')).join('\n');
  if (file.endsWith('AgentConnectorTaskStatusRecorder.swift') && source.includes(statusAnchor)) return source.slice(0, source.indexOf(statusAnchor));
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func recordNativeConnectorObservation(')) {
    source = source.replace(section(source, '  private func recordNativeConnectorObservation(', '  private func preserveNativeConnectorObservation('), '');
    return source.split('\n').filter(line => line.trim() !== 'recordNativeConnectorObservation(record)').join('\n');
  }
  if (file.endsWith('zh-Hans.lproj/Localizable.strings')) return source.replace(translation, '');
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'AgentConnectorTaskStatusRecorder.swift',
    app + 'zh-Hans.lproj/Localizable.strings', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'])
    assert.equal(retained(file, read(file)), show(base, file), file);
  const service = read(app + 'GalaxySSIServices.swift');
  assert.equal(service.split('\n').filter(line => line.trim() === 'recordNativeConnectorObservation(record)').length, 4);
  for (const [start, end] of [
    ['  private func sweepManagedDesktopReply(', '  private func persistRecoveredManagedDesktopResult('],
    ['  private func receiveJournalBackedDesktopRecovery(', '  private func journalBackedDesktopBindingIsCurrent('],
    ['  private func journalBackedDesktopRecoveryQueries(', '  private func commitJournalBackedDesktopResult(']
  ]) assert(section(service, start, end).includes('recordNativeConnectorObservation(record)'));
  const receive = service.lastIndexOf('if let record = desktopReplyRecovery.receive(appPayload, authenticatedDesktopId: link.desktopId,');
  assert(receive >= 0 && service.slice(receive, receive + 260).includes('recordNativeConnectorObservation(record)'));
  const commit = section(service, '  private func recordNativeConnectorObservation(', '  private func preserveNativeConnectorObservation(');
  for (const token of ['UIApplication.shared.isProtectedDataAvailable', 'desktopReplyRecoveryOwner == store.profile.identityFingerprint',
    'desktopReplyRecovery.record(for: observation.binding) == observation', 'currentManagedDesktopReply(observation.binding)',
    'session.status == .active', '!session.privateMode', '!session.trackingPaused', 'session.mergedIntoConversationId.isBlank',
    'task.phase == .paused', 'matches.count == 1', 'task.lastNativeActionResult?.actionId == pending.actionId',
    'AgentIOSConnectorDispatch.profileKey', 'record.correlates(dispatch.response(', 'AgentNativeConnectorStatusObservation.apply(',
    'AgentNativeConnectorContinuation.waitingAction(', 'updated.planContext = AgentTaskPlanContext(plan: plan)',
    'store.commitOwnedAgentTaskState(expected: task, updated: updated)']) assert(commit.includes(token), token);
  for (const token of ['enqueueLinkPayload', 'startQueuedConnector', '.release(', 'continueFailedNativeConnector',
    'finishLocalNativeAction(', 'connectorResponseBus.publish(', 'updated.phase =']) assert(!commit.includes(token), token);
  const policy = read(app + 'AgentConnectorTaskStatusRecorder.swift').split(statusAnchor)[1];
  for (const token of ['binding.isValid', 'managed.state == .pending', 'managed.response == nil', 'owner.ownerRunId == managed.ownerRunId',
    'owner.sourceMessageId == managed.sourceMessageId', 'owner.executionGeneration == managed.executionGeneration',
    'pending.metadata["control_plane_agent_id"] == managed.agentId', 'observation.generation == managed.executionGeneration',
    'observation.sequence > previousSequence', 'observation.lastResponseAt >= previousTime',
    '!AgentRemoteOutcomePolicy.isTerminal', 'AgentConnectorTaskStatusRecorder.record(',
    'native_connector_observation_overdue', 'return result']) assert(policy.includes(token), token);
  for (const token of ['effect_outcome_unknown', 'non_retriable']) assert(!policy.includes(token), token);
  assert(!/metadata\["(?:awaiting_response|completion_verified)"\]\s*=(?!=)/.test(policy));
  const reference = show('e7c6af6ef3eed21c7fb697b4458d1cf742833dc4',
    'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityConnectorTimeoutRecovery.kt');
  assert(reference.includes('runtime.canAcceptConnectorResponse(') && reference.includes('runtime.recordConnectorTaskStatus('));
  assert(reference.indexOf('runtime.recordConnectorTaskStatus(') < reference.indexOf('runtime.persistSession()'));
  for (const name of ['AgentDesktopReplyRecovery', 'AgentManagedResponseModels', 'AgentConnectorResponseResolver',
    'AgentConnectorTimeoutResolver', 'AgentControlPlaneActionExecutorModels', 'AgentNetworkRoutingModels',
    'AgentAutomationModels', 'AgentConnectorTerminalStatusResolver']) {
    const file = app + name + '.swift'; assert.equal(read(file), show(base, file), name);
  }
  const test = 'apps/ios/GalaxySSITests/AgentNativeConnectorStatusObservationTests.swift';
  const tests = read(test); assert.equal((tests.match(/  func test/g) || []).length, 9);
  for (const token of ['testDuplicateAndOlderSequenceDoNotRefreshStaleClock', 'testForeignBindingAndGenerationCannotUpdateOriginalWait',
    'testTerminalStatusAloneNeitherSettlesNorErasesUnknownEffectEvidence', 'testObservedStatusRoundTripsInTheOriginalWaitingReceipt',
    'testMalformedSequenceAndBackwardClockAreRejectedWithoutDefaulting']) assert(tests.includes(token), token);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes('AgentNativeConnectorStatusObservationTests.swift')).length, 4);
  const oldGuard = 'apps/ios/tools/check-pre-shadow-routing-scope.cjs';
  const stripGuard = read(oldGuard).replace("const read = file => require('./check-native-status-observation-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
    "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-native-status-observation-scope.cjs').retained(file, source);\n", '');
  assert.equal(stripGuard, show(base, oldGuard));
  const addressGuard = 'apps/ios/tools/check-special-use-address-scope.cjs';
  assert.equal(read(addressGuard).replace("require('./check-pre-shadow-routing-scope.cjs').retained(project, read(project))",
    'read(project)'), show('2e4db3d46', addressGuard));
  console.log('Exact owned Desktop status projection, durable wait retention and monotonic observation source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

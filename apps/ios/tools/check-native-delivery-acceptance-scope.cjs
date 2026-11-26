// Source contracts only; not executed Swift, receipt delivery or persistence/fault acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const property = '  var recordManagedTransportAccepted: ((MqttDeliveryCompletions.Event, AgentTaskIdentity, MqttPeerChatProjection.Destination) throws -> Void)? = nil\n';
const gate = `    guard let id = UUID(uuidString: event.sourceMessageID) else {
      guard let source = Int64(event.sourceMessageID), source > 0, String(source) == event.sourceMessageID,
            let recordManagedTransportAccepted else { throw MqttDeliveryDispatch.Failure.unavailable }
      try recordManagedTransportAccepted(event, identity, target)
      return
    }`;
const callback = `      }, recordManagedTransportAccepted: { [weak self] event, identity, target in
        guard let self else { throw MqttDeliveryDispatch.Failure.unavailable }
        try self.recordNativeConnectorTransportAccepted(event, identity: identity, target: target)
`;
const policyAnchor = '\n// Only the authenticated, durably journaled message-delivery completion may call this policy.\n';
const testAnchor = '// Journal native-delivery acceptance fixtures; source only unless executed by XCTest.\n';
function retained(file, source) {
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func recordNativeConnectorTransportAccepted(')) return source
    .replace(section(source, '  private func recordNativeConnectorTransportAccepted(', '  private func preserveNativeConnectorObservation('), '')
    .replace(callback, '');
  if (file.endsWith('MqttDesktopConnectorProjection.swift')) return source.replace(property, '')
    .replace(gate, '    guard let id = UUID(uuidString: event.sourceMessageID) else { return }');
  if (file.endsWith('AgentConnectorTransportReceiptRecorder.swift') && source.includes(policyAnchor))
    return source.slice(0, source.indexOf(policyAnchor));
  if (file.endsWith('AgentConnectorTransportReceiptRecorderTests.swift') && source.includes(testAnchor))
    return source.replace(section(source, testAnchor, 'final class AgentConnectorTransportReceiptRecorderTests:'), '');
  if (file.endsWith('check-desktop-probe-owner-scope.cjs')) return source
    .replace("const read = file => require('./check-native-delivery-acceptance-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-native-delivery-acceptance-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'MqttDesktopConnectorProjection.swift',
    app + 'AgentConnectorTransportReceiptRecorder.swift', 'apps/ios/GalaxySSITests/AgentConnectorTransportReceiptRecorderTests.swift',
    'apps/ios/tools/check-desktop-probe-owner-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const source = read(app + 'GalaxySSIServices.swift');
  assert.equal(source.split(callback).length, 2);
  assert(read(app + 'MqttDesktopConnectorProjection.swift').includes(gate));
  const commit = section(source, '  private func recordNativeConnectorTransportAccepted(', '  private func preserveNativeConnectorObservation(');
  for (const token of ['UIApplication.shared.isProtectedDataAvailable', 'store.canReadAgentTranscript',
    'contact.trustState == .verified', 'event.identity == (try MqttBusinessIdentity(target.peer.binding))',
    'target.routeId == identity.clientRouteId', '!PhoneExecutionAuthority.isCancelled', 'session.status == .active',
    '!session.privateMode', '!session.trackingPaused', 'matches.count == 1',
    'task.lastNativeActionResult?.metadata["control_plane_run_id"]', 'AgentIOSConnectorDispatch.profileKey',
    'AgentNativeConnectorContinuation.waitingAction(', 'try managedDesktopReplyLedger.recoveryRecord(',
    'try AgentNativeConnectorTransportAcceptance.apply(', 'saved.planContext = AgentTaskPlanContext(plan: plan)',
    'guard store.commitOwnedAgentTaskState(expected: task, updated: saved) else { throw MqttChunkStorageError.databaseFailure }']) assert(commit.includes(token), token);
  for (const token of ['.release(', 'connectorResponseBus.publish(', 'continueFailedNativeConnector(',
    'finishLocalNativeAction(', 'enqueueLinkPayload(', 'saved.phase =']) assert(!commit.includes(token), token);
  const policy = read(app + 'AgentConnectorTransportReceiptRecorder.swift').split(policyAnchor)[1];
  for (const token of ['event.isPending', 'event.identity == expectedIdentity', 'event.topic == expectedTopic',
    'event.traffic == MqttMultipathPolicy.Traffic.message.rawValue', 'event.attachmentTransferID.isEmpty',
    'taskIdentity.clientRouteId == expectedRouteID', 'managed.state == .pending', 'managed.response == nil',
    'managed.ownerRunId == dispatch.owner', 'managed.sourceMessageId == dispatch.sourceMessageId',
    'managed.contactId == dispatch.contactId', 'managed.conversationId == dispatch.conversationId',
    'managed.turnId == dispatch.turnId', 'managed.taskId == dispatch.taskId',
    'managed.executionGeneration == Int64', 'event.messageID == messageID', 'event.receivedAt >= started',
    'native_connector_attachment_body_id', 'UUID(uuidString: dispatch.taskId)',
    'guard pending.metadata["transport_accepted_at"] == nil else { return nil }']) assert(policy.includes(token), token);
  assert(!/metadata\["(?:awaiting_response|completion_verified|effect_outcome_unknown|non_retriable)"\]\s*=/.test(policy));
  for (const name of ['MqttBusinessTransportRuntime', 'MqttDeliveryCompletions', 'MqttBusinessOutbox',
    'MqttBusinessReceipts', 'MqttSignalStateJournal', 'AgentIOSConnectorDispatch', 'AgentAutomationModels',
    'AgentConnectorTaskStatusRecorder', 'AgentConnectorResponseResolver', 'AgentManagedResponseModels'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const drain = read(app + 'MqttBusinessReceipts.swift');
  assert(drain.indexOf('try await apply(current)') >= 0 &&
    drain.indexOf('try await apply(current)') < drain.indexOf('journal.outbox.completions.consume('));
  const tests = section(read('apps/ios/GalaxySSITests/AgentConnectorTransportReceiptRecorderTests.swift'), testAnchor,
    'final class AgentConnectorTransportReceiptRecorderTests:');
  assert.equal((tests.match(/  func test/g) || []).length, 7);
  for (const token of ['testNativeJournalDeliveryReplayDoesNotRefreshAcceptance',
    'testNativeJournalDeliveryPreservesLaterRemoteStatusAndItsClock', 'testNativeJournalDeliveryRejectsForeignManagedAndTaskScopes',
    'testNativeJournalAttachmentDeliveryRequiresTheSavedFinalBody',
    'testNativeNumericCompletionInvokesTheRegisteredWriterAndPropagatesFailure', '("consumedAt", 3_000)', 'JSONDecoder()']) assert(tests.includes(token), token);
  console.log('Native numeric delivery-completion wiring, exact ownership, durable receipt commit, preserved replay clocks and seven authored fixtures source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

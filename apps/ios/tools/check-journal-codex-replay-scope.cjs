// Source contracts only, not native MQTT delivery, restart, replay or authorization acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '26e82a54754c11aab4e32c09fc1c389ff1b13628';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const cache = new Map();
function old(file) {
  if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(file);
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  if (file.endsWith('check-managed-raw-attachments-scope.cjs')) return source
    .replace("const read = file => require('./check-journal-codex-replay-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-journal-codex-replay-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('MqttJournalCodexReplayTests.swift')).join('\n');
  if (file.endsWith('AgentRemoteTaskStatusPolicy.swift') && source.includes('enum AgentJournalCodexReplayPolicy {'))
    return source.replace(section(source, 'enum AgentJournalCodexReplayPolicy {', 'enum AgentCodexSilenceRecoveryPolicy {'), '');
  if (file.endsWith('MqttDesktopConnectorProjection.swift') && source.includes('AgentJournalCodexReplayPolicy.')) return source
    .replace('    var codexReplay: AgentDesktopReplyRecoveryRecord? = nil\n', '')
    .replace('      if let codexReplay { return AgentJournalCodexReplayPolicy.matchesRequest(payload, record: codexReplay, source: message) }\n', '')
    .replace('  var resolveCodexReplayOwner: ((String, GalaxySSIContact, AgentTaskIdentity, MqttPeerChatProjection.Destination) throws -> TaskOwner?)? = nil\n', '')
    .replace('    if !requiresTeam, let replay = try resolveCodexReplayOwner?(source, contact, identity, target),\n       replay.codexReplay != nil { return replay }\n', '')
    .replace(section(source, '    let presentation: MqttDeliveryCompletions.Event\n', '    catch GalaxySSIChatHistoryError.locallyDeleted'),
      '    do { try store.persistTransportDelivery(event, messageContactID: owner.message.contactId) }\n');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func journalCodexReplayOwner(')) return source
    .replace(section(source, '  private func journalCodexReplayOwner(', '  private func dispatchScheduledCodexReplay('), '')
    .replace('if published < 8, (usesLegacyMqtt ? mqttClient.relationshipSubscriptionsReady : journalMqttRuntime != nil) {',
      'if published < 8, mqttClient.relationshipSubscriptionsReady {')
    .replace('guard journalMqttRuntime != nil, teamContext?.isManagedCollaboration != false else {',
      'guard journalMqttRuntime != nil, teamContext?.isManagedCollaboration != false, codexReplay == nil else {')
    .replace('        _ = try runtime.enqueueDesktopConnectorRequest(payload, desktopId: link.desktopId,\n          ownerContactID: codexReplay == nil ? nil : outgoing.contactId)',
      '        _ = try runtime.enqueueDesktopConnectorRequest(payload, desktopId: link.desktopId)')
    .replace('      }, resolveCodexReplayOwner: { [weak self] source, contact, identity, target in\n        self?.journalCodexReplayOwner(source, contact: contact, identity: identity, target: target)\n', '');
  return source;
}
function validate() {
  for (const file of [app + 'AgentRemoteTaskStatusPolicy.swift', app + 'MqttDesktopConnectorProjection.swift',
    app + 'GalaxySSIServices.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    'apps/ios/tools/check-managed-raw-attachments-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const service = read(app + 'GalaxySSIServices.swift');
  assert(service.includes('if published < 8, (usesLegacyMqtt ? mqttClient.relationshipSubscriptionsReady : journalMqttRuntime != nil) {'));
  const owner = section(service, '  private func journalCodexReplayOwner(', '  private func dispatchScheduledCodexReplay(');
  for (const token of ['UIApplication.shared.isProtectedDataAvailable', 'desktopReplyRecoveryOwner == store.profile.identityFingerprint',
    '!store.agentSafetySettings.executionPaused', 'store.agentSafetySettings.connectorCallsAllowed', 'contact.trustState == .verified',
    'AgentModelSelectionSettings.selection(for: identity.conversationId).mode == .automatic', 'records.count == 1',
    '$0.binding.sourceIdentity == source', '$0.binding.identity == identity', '!record.isManualTargetLocked',
    'record.terminalObservedAt == 0', 'replay.budget.expectedTarget == contact.id', 'currentDesktopReplySource(record.binding)',
    '!session.privateMode', '!session.trackingPaused', 'session.collaborationRoster == nil', 'PhoneExecutionAuthority.isCancelled',
    'contact.connectorInvocationProfile.models.contains']) assert(owner.includes(token), token);
  assert(!owner.includes('.budget.next('), 'Projection never creates or spends a new retry budget');
  const policy = section(read(app + 'AgentRemoteTaskStatusPolicy.swift'), 'enum AgentJournalCodexReplayPolicy {', 'enum AgentCodexSilenceRecoveryPolicy {');
  for (const token of ['binding.attemptSourceId != nil', 'binding.managedSource == nil', 'binding.teamSource == nil',
    'replay.matches(source)', 'payload.string("message_id") == binding.sourceIdentity',
    'payload.string("content") == source.content', 'AgentTaskExecutionMode.planOnly.rawValue', 'replay.transportContext',
    'payload["attachments"] == nil', 'payload["voice_session_id"] == nil', 'payload["run_id"] == nil',
    'payload["agent_invocation"] as? [String: String] == expected', 'sourceMessageID: source.id.uuidString',
    'messageID: event.messageID, wireHash: event.wireHash']) assert(policy.includes(token), token);
  const projection = read(app + 'MqttDesktopConnectorProjection.swift');
  assert(projection.includes('if !requiresTeam, let replay = try resolveCodexReplayOwner?'));
  assert(projection.includes('store.persistTransportDelivery(presentation, messageContactID: owner.message.contactId)'));
  for (const name of ['AgentDesktopReplyRecovery', 'MqttBusinessTransportRuntime', 'MqttSignalStateJournal',
    'MqttBusinessOutbox', 'MqttSignalSendRequest', 'MqttDeliveryCompletions', 'GalaxySSIChatHistoryDatabase',
    'AgentDataDisclosureLedger', 'AgentTaskBudgetModels', 'AgentConnectorTimeoutResolver'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const testFile = 'apps/ios/GalaxySSITests/MqttJournalCodexReplayTests.swift';
  assert.equal((read(testFile).match(/  func test/g) || []).length, 7);
  for (const token of ['projection.outgoingRequest(', 'projection.isCurrentSendOwner(', 'projection.projectCompletion(',
    'store.persistedMessage(id: original.id', 'seed.budget.next(', 'AgentJournalCodexReplayPolicy.presentationEvent(']) assert(read(testFile).includes(token), token);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes('MqttJournalCodexReplayTests.swift')).length, 4);
  console.log('Journal Codex replay identity, current owner, immutable original payload and local delivery mapping source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

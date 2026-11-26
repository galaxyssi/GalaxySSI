// Source contracts only; not Swift compilation, device presentation or Blob delivery acceptance.
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
    .replace("const read = file => require('./check-native-rich-reply-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-native-rich-reply-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentNativeConnectorRichReplyTests.swift')).join('\n');
  if (file.endsWith('AgentConnectorResponseResolver.swift') && source.includes('\nenum AgentNativeConnectorRichReplyPolicy {'))
    return source.slice(0, source.indexOf('\nenum AgentNativeConnectorRichReplyPolicy {'));
  if (file.endsWith('GalaxySSIPeerAttachmentTransferProgress.swift') && source.includes('  static func matchesArtifactUpdate('))
    return source.replace(section(source, '  static func matchesArtifactUpdate(', '  static func applying('), '');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('AgentNativeConnectorRichReplyPolicy.validated')) {
    source = source.replace('localNativeRichOutput(result: result, responseText: reply,\n        action: executionAction, outgoing: outgoing, task: task)',
      'localNativeRichOutput(result: result, responseText: reply)');
    source = source.replace('      let nativeIncoming = store.appendIncoming(', '      _ = store.appendIncoming(');
    source = source.replace(section(source, '      if executionAction.kind == .callConnector, !richOutput.isBlank,', '    }\n    if shouldReviewOutcome'), '');
    source = source.replace('    responseText: String,\n    action: AgentAction,\n    outgoing: ChatMessage,\n    task: AgentTaskRecord\n', '    responseText: String\n');
    source = source.replace(section(source, '    if action.kind == .callConnector {\n      let record = try? managedDesktopReplyLedger.recoveryRecord', '    let toolId = result.metadata["native_tool_id"]'), '');
    source = source.replace('    let presentationOwner = store.profile.identityFingerprint\n', '')
      .replace('      guard store.profile.identityFingerprint == presentationOwner else { return }\n', '');
    source = source.replace(section(source, '      if UUID(uuidString: source) == nil,\n         try AgentTeamExecutionHistoryStore.shared.recoveryContext', '      if try AgentTeamExecutionHistoryStore.shared.recoveryContext'), '');
    const begin = '      let messages = store.messages(for: contactId)\n      let match = update.peerChat ?', end = '      guard let match else { continue }';
    source = source.replace(section(source, begin, end), section(old(file), '      let match = store.messages(for: contactId).reversed().first { message in', end));
  }
  return source;
}
function validate() {
  for (const file of [app + 'AgentConnectorResponseResolver.swift', app + 'GalaxySSIPeerAttachmentTransferProgress.swift',
    app + 'GalaxySSIServices.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    'apps/ios/tools/check-managed-raw-attachments-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const policy = read(app + 'AgentConnectorResponseResolver.swift').split('\nenum AgentNativeConnectorRichReplyPolicy {')[1];
  for (const token of ['action.id == result.actionId', 'outgoing.isMine', 'task.taskId == turn',
    'AgentIOSConnectorDispatch.sourceKey', 'AgentIOSConnectorDispatch.profileKey', 'record.state != .pending',
    'response.success', 'response.deliveryFailureCode.isEmpty', 'response.taskStatus == "completed"',
    'record.ownerRunId == AgentControlPlaneActionExecutor.connectorRunId', 'effect_outcome_unknown',
    'response.content == result.message', 'response.richOutputJson == result.metadata["rich_output"]',
    'response.executionGeneration == record.executionGeneration', 'String(numeric) == source',
    'numeric <= 9_007_199_254_740_991', 'record.executionGeneration == generation', 'record.response == nil']) assert(policy.includes(token), token);
  for (const token of ['URLSession', 'UserDefaults', 'FileManager', 'ledger.complete', 'register(']) assert(!policy.includes(token), token);
  const service = read(app + 'GalaxySSIServices.swift');
  for (const token of ['richContentMaterializer.materialize(rich)', 'store.persistedMessage(id: nativeIncoming.id',
    'hydrateBlobArtifactPresentation(message: nativeIncoming, contactId: result.metadata["contact_id"]',
    'guard store.profile.identityFingerprint == presentationOwner else { return }',
    'AgentManagedArtifactScopePolicy.authorizes(manifest, record: record)',
    'GalaxySSIPeerAttachmentTransferProgress.agentArtifactMessage(update, messages: messages)']) assert(service.includes(token), token);
  const matcher = section(read(app + 'GalaxySSIPeerAttachmentTransferProgress.swift'), '  static func matchesArtifactUpdate(', '  static func applying(');
  for (const token of ['guard !update.peerChat', '!$0.isMine', '$0.conversationId == update.conversationId',
    '$0.turnId == update.turnId', 'scopedMetadata(', 'JSONDecoder().decode([String: String].self']) assert(matcher.includes(token), token);
  for (const name of ['AgentRichContentModels', 'AgentRichContentMaterializer', 'AgentBlobArtifactReceiver',
    'AgentManagedResponseModels', 'MqttBusinessTransportRuntime', 'MqttSignalStateJournal'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/AgentNativeConnectorRichReplyTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 7);
  assert(tests.includes('AgentNativeConnectorContinuation.settle('));
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n')
    .filter(line => line.includes('AgentNativeConnectorRichReplyTests.swift')).length, 4);
  console.log('Owned native rich reply, exact artifact matching, profile hydration and retained transport source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

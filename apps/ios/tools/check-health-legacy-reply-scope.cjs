'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const prefix = 'apps/ios/GalaxySSI/';
const baseline = '6b975ce39b14a29da89c0bd138adac9631b383ef';
const clean = text => text.replace(/\r\n/g, '\n');
const read = name => clean(fs.readFileSync(path.join(root, prefix + name), 'utf8'));
function replaceUnique(source, before, after = '') {
  assert.equal(source.split(before).length - 1, 1, 'Unique declared legacy Health presentation hook');
  return source.replace(before, after);
}
function retainedLegacyHost(input) {
  let source = clean(input);
  source = replaceUnique(source, `              conversation: session.id, visible: homeVisible, legacyMessages: transcriptMessages,
              legacyRuntimeTurns: Set(activeAgentTasks.map(\\.taskId))
                .union(scopedHealthRemoteTurns).union(scopedHealthVoiceTurns).union(scopedHealthCommittedTurns))`,
  '              conversation: session.id, visible: homeVisible)');
  return replaceUnique(source, `  private var scopedHealthRemoteTurns: Set<String> {
    Set(coordinator.remoteAgentTaskStatuses.values.filter { $0.conversationId == store.activeAgentConversationId }
      .flatMap { [$0.turnId, $0.taskId] })
  }

  private var scopedHealthVoiceTurns: Set<String> {
    Set(voiceAgentRunRecovery.activeSnapshots.filter { $0.conversationId == store.activeAgentConversationId }
      .flatMap { [$0.turnId, $0.taskId] })
  }

  private var scopedHealthCommittedTurns: Set<String> {
    committedTurnProgress.conversationID == store.activeAgentConversationId ? Set(committedTurnProgress.turns.keys) : []
  }

`);
}
function retainedLegacyMessages(input) {
  let source = clean(input);
  source = replaceUnique(source, `    let privateHealth = store.agentSession(id: store.activeAgentConversationId)
      .map { GalaxySSIHealthCareAgentScope.concernID($0) != nil } == true
`);
  return replaceUnique(source, '            !(privateHealth && GalaxySSIHealthCareLegacyReplyPresentation.isControl(message)),\n');
}
module.exports = { retainedLegacyHost, retainedLegacyMessages };

if (require.main === module) {
  const old = name => clean(cp.execFileSync('git', ['show', baseline + ':' + prefix + name],
    { cwd: root, encoding: 'utf8', maxBuffer: 20_000_000 }));
  assert.equal(retainedLegacyHost(read('GalaxySSIAgentHomeOutputView.swift')), old('GalaxySSIAgentHomeOutputView.swift'));
  assert.equal(retainedLegacyMessages(read('GalaxySSIAgentTranscriptMessagesView.swift')), old('GalaxySSIAgentTranscriptMessagesView.swift'));
  for (const name of ['GalaxySSIServices.swift', 'AgentConnectorResponseModels.swift', 'AgentConnectorResponseResolver.swift',
    'AgentReplyWaitingIndicator.swift', 'AgentTranscriptRenderPolicy.swift', 'GalaxySSIHealthCareTaskRuntime.swift',
    'GalaxySSIHealthCareAgentTranscriptProjection.swift']) {
    assert.equal(read(name), old(name), name + ': no response consumption, task or clock reducer changes');
  }
  const reader = `  func verifiedHealthLegacyWindow(conversationId: String) throws -> [ChatMessage] {
    try locked {
      guard !conversationId.isBlank, let statement = prepare("""
        SELECT message_id, encrypted_payload, created_at FROM chat_messages
        WHERE contact_id = 'hermes' AND conversation_id = ?
        ORDER BY created_at DESC, message_id DESC LIMIT 500
        """) else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      bind(conversationId, at: 1, to: statement)
      var messages: [ChatMessage] = []
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return messages }
        guard step == SQLITE_ROW, let rawID = sqlite3_column_text(statement, 0),
              let message = decode(statement, id: String(cString: rawID), payloadColumn: 1),
              message.contactId == "hermes", message.conversationId == conversationId,
              message.createdAt.timeIntervalSinceReferenceDate.isFinite,
              (-62_135_596_800...253_402_300_799).contains(message.createdAt.timeIntervalSince1970),
              Self.millis(message.createdAt) == sqlite3_column_int64(statement, 2) else {
          throw MqttChunkStorageError.databaseFailure
        }
        messages.append(message)
      }
    }
  }

`;
  assert.equal(replaceUnique(read('GalaxySSIChatHistoryDatabase.swift'), reader), old('GalaxySSIChatHistoryDatabase.swift'),
    'Database unchanged outside bounded, strict read-only snapshot');
  assert.doesNotMatch(reader, /\b(?:INSERT|UPDATE|DELETE|ALTER|CREATE|PRAGMA)\b/);
  const policy = read('GalaxySSIHealthCareLegacyReplyPresentation.swift');
  for (const fence of ['!hasRecovery, !hasAnswer', 'turn == original.id, !domainTurns.contains(turn)',
    'original.conversationId == conversation.id, receipt.conversationId == conversation.id',
    'original.sourceConversationId.isBlank, receipt.sourceConversationId.isBlank',
    'original.contactId == "hermes", receipt.contactId == "hermes"',
    'original.requestKind == .conversation, receipt.requestKind == .conversation',
    '!original.readOnlyAnalysis, !receipt.readOnlyAnalysis', '[.delivered, .read].contains(receipt.deliveryStatus)',
    'receipt.content.utf8.count <= 128_000', 'receipt.richOutputJson.utf8.count <= 128_000',
    '!receipt.remoteMessageId.hasPrefix("agent-stream-") || final != nil',
    'received >= original.createdAt, received <= now']) {
    assert(policy.includes(fence), 'Legacy receipt scope: ' + fence);
  }
  const marker = policy.slice(policy.indexOf('  struct Marker:'), policy.indexOf('  static func marker('));
  assert.doesNotMatch(marker, /content|richOutput|question|payload|String/);
  assert.doesNotMatch(policy, /UserDefaults|URLSession|persist|\.send\(|appendIncoming|remove\(|markTerminal/);
  const view = read('GalaxySSIHealthCareAgentTranscriptView.swift');
  for (const fence of ['verified.contains(receipt)', 'verified.first(where:',
    'store.agentTask(id: receipt.turnId) == nil', 'store.agentWorkspaceStore.find(receipt.turnId) == nil',
    'legacyRuntimeTurns.contains(receipt.turnId)', 'let hasAnswer = verified.contains',
    'legacyMarkers = []', 'legacyMessages', 'domainTurns: Set(thread.turns.map(\\.id))']) {
    assert(view.includes(fence), 'Retained source/recovery context: ' + fence);
  }
  assert.doesNotMatch(view, /Text\(verbatim: receipt\.|appendIncoming|updateMessageContent|\.remove\(|\.publish\(/);
  const tests = clean(fs.readFileSync(path.join(root, 'apps/ios/GalaxySSITests/GalaxySSIHealthCareLegacyReplyTests.swift'), 'utf8'));
  assert.equal((tests.match(/func test/g) || []).length, 10);
  console.log('Health legacy reply presentation source scope passed (not native execution or typechecking).');
}

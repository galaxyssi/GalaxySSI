// Source wiring only. Does not execute Swift, UIKit, encryption or model requests.
const assert = require('node:assert/strict');
const fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '4d24af48643352ea03c5603f4f1b160afbeacc85';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function has(file, tokens) { const s = read(app + file + '.swift'); for (const token of tokens) assert(s.includes(token), file + ': ' + token); return s; }
function validate() {
  const policy = has('AgentSessionRequirement', ['maximumUTF16 = 320', 'clean.utf16.count <= maximumUTF16',
    'result.utf16.count + String(character).utf16.count', 'conversation?.id == owner', 'not tool authorization',
    'AgentMcpJSONCodec.stringify(.string(clean))', 'context.conversationId == owner',
    'message.sourceConversationId.isBlank', 'message.conversationId == active', 'agent-voice-transcription:']);
  assert(!policy.includes('grantedPermissions'));
  has('AgentConversationModels', ['case sessionRequirement = "user_session_requirement"',
    'decodeIfPresent(String.self, forKey: .sessionRequirement) ?? ""',
    'if !sessionRequirement.isEmpty { try container.encode(sessionRequirement, forKey: .sessionRequirement) }',
    'lines.append(sessionRequirementPrompt)', 'hasGlobalContext || !sessionRequirementPrompt.isEmpty',
    'payload["user_session_requirement"]', '.replacingOccurrences(of: Self.transportFooter,',
    'sessionRequirement: sessionRequirement']);
  const sessions = has('GalaxySSIStoreSessions', ['func setSessionRequirement(id: String, expected: String, text: String)',
    'current.sessionRequirement == expected', 'current.mergedIntoConversationId.isBlank',
    'current.sessionRequirement = clean', 'let saved = read(id) == nil ? saveDraft(current) : upsert(current)',
    'guard saved, !Task.isCancelled, execute("COMMIT")',
    'canReadAgentTranscript, profile.identityFingerprint == owner, activeAgentConversationId == id',
    'agentConversationDatabase.setSessionRequirement(id: id, expected: expected, text: text)', 'cacheAgentConversation(saved)']);
  const patch = sessions.slice(sessions.indexOf('  func setSessionRequirement('), sessions.indexOf('  static func defaultFileURL'));
  assert(patch.includes('execute("BEGIN IMMEDIATE")') && patch.includes('execute("ROLLBACK")'));
  assert(!/current\.(?:updatedAt|title|summary|privateMode)\s*=/.test(patch));
  const services = has('GalaxySSIServices', ['conversation = AgentSessionRequirement.refresh(conversation, owner: outgoing.conversationId,',
    'sessionRequirement: AgentSessionRequirement.value(session, owner: outgoing.conversationId)',
    'sessionRequirement: AgentSessionRequirement.value(session, owner: conversationId)',
    'owner: outgoing.conversationId).isEmpty,', 'let requirement = AgentSessionRequirement.prompt(sessionRequirement)']);
  assert.equal((services.match(/sessionRequirement: AgentSessionRequirement.value\(store.agentSession/g) || []).length, 3);
  has('AgentModelPlanningPrompt', ['"User goal: \\(request.planRequest.goal.prefixStringForPlanning(2_000))\\n" + request.conversationContext.sessionRequirementPrompt',
    'let latest = context.sessionRequirementPrompt +']);
  has('CloudModelClientStreaming', ['guard store.canReadAgentTranscript else { return "" }',
    'AgentSessionRequirement.value(store.agentSession(id: turns.last?.conversationId ?? "")',
    'systemPrompt: systemPrompt + "\\n" + AgentSessionRequirement.prompt(requirement)']);
  has('GalaxySSIAgentTranscriptMessagesView', ['.sheet(item: $requirementDraft)',
    '.environment(\\.peerTextSelection, requirementSelection(message))',
    'store.canReadAgentTranscript', 'generation: store.runtimePlaintextGeneration',
    'expected: session.sessionRequirement, seed: selected']);
  has('GalaxySSISessionRequirementEditor', ['draft.expected.isEmpty ? AgentSessionRequirement.seed(draft.seed) : draft.expected',
    'value.utf16.count > AgentSessionRequirement.maximumUTF16', 'save("")', 'runtimePlaintextGeneration == draft.generation',
    'expected: draft.expected, text: value, owner: draft.owner', '.galaxySSIRuntimePlaintextWillClear',
    '.onChange(of: store.activeAgentConversationId)', '.onChange(of: store.profile.identityFingerprint)']);
  has('GalaxySSIPeerTextSelectionView', ['if view.onSessionRequirement != nil', 'UIAction(title: view.requirementTitle',
    'if #unavailable(iOS 16.0), onMoreMessage != nil || onSessionRequirement != nil',
    'UIMenuItem(title: requirementTitle, action: requirementAction)', 'let selected = source.substring(with: range)',
    'range.length <= source.length - range.location', 'view.onSessionRequirement = nil']);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentSessionRequirement', 'GalaxySSISessionRequirementEditor', 'AgentSessionRequirementTests']) {
    assert.equal((project.match(new RegExp(name + '\\.swift in Sources \\*\\/', 'g')) || []).length, 2);
    assert.equal((project.match(new RegExp('path = ' + name + '\\.swift;', 'g')) || []).length, 1);
  }
  assert.equal((read('apps/ios/GalaxySSITests/AgentSessionRequirementTests.swift').match(/func test/g) || []).length, 14);
  for (const key of ['agent_session_requirement', 'agent_session_requirement_remove', 'agent_session_requirement_unavailable']) {
    assert.equal(read(app + 'zh-Hans.lproj/Localizable.strings').split('"' + key + '" =').length, 2);
  }
  for (const file of ['AgentNativeToolExecutionModels.swift',
    'GalaxySSIEncryptedStateStore.swift', 'GalaxySSIAttachmentAtRestCipher.swift', 'AgentInitialPlanningJournal.swift']) {
    assert.equal(read(app + file), old(app + file), file + ' unchanged');
  }
  console.log('Conversation-owned session preference source wiring, encrypted metadata CAS, menu/editor gates, transport/planner/local/cloud hooks and 14 authored-only fixtures checked; no native acceptance.');
}
module.exports = {validate};
if (require.main === module) validate();

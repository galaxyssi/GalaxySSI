// Source contracts for the goal pipeline. These do not compile Swift or execute native/background work.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const read = f => fs.readFileSync(path.join(root, 'apps/ios', f), 'utf8').replace(/\r\n/g, '\n');
const model = read('GalaxySSI/AgentConversationGoal.swift');
const store = read('GalaxySSI/AgentConversationGoalStore.swift');
for (const token of ['static let roundBudget = 6', 'guard !inFlight else { throw Failure.interrupted }',
  'guard rounds < allowance', 'value.generation += 1', 'value.allowance = rounds + Self.roundBudget',
  'Set(object.keys) == ["state", "result", "next"]', 'guard review, !checkpoints.isEmpty, work.isEmpty, pending.isEmpty',
  '!(review && state == "done")', 'return try halt(.repeatedProgress)',
  'value.phase = .paused', 'Array(value.checkpoints.suffix(15))', 'checkpoints.count <= 16',
  'objective.utf16.count <= 4_000', 'work.utf16.count <= 12_000', 'pending.utf16.count <= 1_000']) assert(model.includes(token), token);
for (const token of ['NSRecursiveLock()', 'AgentTurnReceiptEvidence.hash(owner)', 'AgentTurnReceiptEvidence.hash(conversation)',
  'GalaxySSIEncryptedUserDefaultsStore.load', 'GalaxySSIEncryptedUserDefaultsStore.write',
  'try read(goal.conversation) == expected', 'goal.objective == expected.objective, goal.route == expected.route',
  'goal.revision > expected.revision, goal.generation >= expected.generation', 'goal.id == expected.id || expected.terminal',
  'throw AgentConversationGoal.Failure.unavailable', 'key + ".deleted"', 'object: nil']) assert(store.includes(token), token);
assert(!/CloudModelClient|GalaxySSIHealthRecords|enqueueDesktop|MessageCoordinator/.test(model + store),
  'State/persistence must not imply provider or health authority');
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentConversationGoal', 'AgentConversationGoalStore', 'AgentConversationGoalTests',
  'AgentConversationGoalInference', 'AgentConversationGoalRuntime', 'AgentConversationGoalBackground',
  'AgentConversationGoalLifecycle', 'GalaxySSIConversationGoalView', 'AgentConversationGoalInferenceTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registration');
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source), name + ' localized resource placement');
}
assert.equal((read('GalaxySSITests/AgentConversationGoalTests.swift').match(/func test/g) || []).length, 14);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
for (const command of ['status', 'help', 'pause', 'stop', 'resume']) {
  assert(strings.includes(`"galaxyssi.conversation_goal.command_${command}" = `), command + ' alias');
}
const inference = read('GalaxySSI/AgentConversationGoalInference.swift');
const runtime = read('GalaxySSI/AgentConversationGoalRuntime.swift');
const background = read('GalaxySSI/AgentConversationGoalBackground.swift');
const ui = read('GalaxySSI/GalaxySSIConversationGoalView.swift');
for (const token of ['contact.deliveryMode == .cloudAPI', 'isCurrent(goal.route, store: store)',
  'workClass: .background', 'cancellation: cancellation.token', 'maximumTokens: 2_048', 'turns: [only]',
  'AgentSingleFileRead.isolatedRequest', 'historyCount: goal.checkpoints.count', 'route.artifactSHA == fingerprint(profile: $0)',
  'case .toolCallDelta, .failed', '131_072', 'remaining_rounds', 'FINAL REVIEW', 'max_completion_tokens']) assert(inference.includes(token), token);
assert(!/recentLocalConversationContext|GalaxySSIHealthRecords|enqueueDesktop|conversationContext:|send\(/.test(inference),
  'Model inputs must not acquire ordinary conversation, tool, health or Desktop authority');
for (const token of ['!session.privateMode && !session.trackingPaused', 'session.collaborationRoster == nil',
  'store.profile.identityFingerprint', 'Self.eligible(store.agentSession', 'try repository.replace(next, expected: goal)',
  'try repository.replace(result, expected: next)', 'guard current(next, store: store, ticket: ticket)',
  'try goal.halt(.interrupted)', 'ProcessInfo.processInfo.systemUptime - started >= 180', 'GalaxySSIStore.canRestoreConversationGoalState()',
  'guard backgroundGrant == grant else { return }', 'guard self.graceToken == token else { return }',
  'goal.review && goal.phase == .running', 'store.hasIncomingDuplicate', 'beginBackgroundTask',
  'guard let initial = try repository.read(queued.conversation)', 'try repository.read(goal.conversation) == goal']) assert(runtime.includes(token), token);
for (const token of ['BGProcessingTaskRequest(identifier: identifier)', 'task.expirationHandler', 'worker.cancel()',
  'generation != expected', 'AgentKnowledgeBackgroundCompletion']) assert(background.includes(token), token);
for (const token of ['actual?.id == goal?.id, actual?.generation == goal?.generation', 'try repository.replace(next, expected: actual)',
  'choices[selected]', 'AgentConversationGoalInference.routes', 'Authorize six rounds', 'Reopen this panel',
  'UIApplication.protectedDataWillBecomeUnavailableNotification', 'goal.phase == .running']) assert(ui.includes(token), token);
const submission = read('GalaxySSI/GalaxySSIAgentHomeMessageSubmission.swift');
assert(submission.indexOf('offerConversationGoal(') < submission.indexOf('coordinator.send('), 'Commands precede ordinary model routing');
const views = read('GalaxySSI/GalaxySSIViews.swift');
assert(views.includes('AgentConversationGoalBackground.register()') && views.includes('AgentConversationGoalLifecycle(store:'), 'App lifecycle registration');
assert(read('GalaxySSI/GalaxySSIStoreSessions.swift').includes('secrets: secrets).remove(id)'), 'Session deletion invalidates goals');
assert(read('GalaxySSI/GalaxySSIStore.swift').includes('AgentConversationGoalStore.destroyAll'), 'Private-data erasure covers goals');
const plist = read('GalaxySSI/BackgroundModes.plist');
assert(plist.includes('<key>BGTaskSchedulerPermittedIdentifiers</key>\n  <array>'), 'System identifiers must be a plist array');
for (const id of ['agent-refresh', 'workflow-trigger-refresh', 'knowledge-index', 'knowledge-storage', 'original-page-archive', 'conversation-goal']) {
  assert(plist.includes(`<string>com.galaxyssi.chat.ios.${id}</string>`), id + ' preserved');
}
assert(plist.includes('<string>audio</string>') && plist.includes('<string>processing</string>'), 'Existing modes retained');
assert(!project.includes('INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers ='), 'Do not override the typed array with a generated string');
const keys = new Set();
for (const match of strings.matchAll(/^"galaxyssi\.conversation_goal\.([^"\n]+)" = ("(?:[^"\\]|\\.)*");$/gm)) {
  assert(!keys.has(match[1]), 'Duplicate localization key: ' + match[1]); keys.add(match[1]); JSON.parse(match[2]);
}
for (const match of ui.matchAll(/\b(?:t|get)\("([a-z_]+)",/g)) assert(keys.has(match[1]), 'Localized UI: ' + match[1]);
assert.equal((read('GalaxySSITests/AgentConversationGoalInferenceTests.swift').match(/func test/g) || []).length, 6);
console.log('Conversation goal state, inference, UI and background source contracts passed; no Swift compilation, XCTest or system execution.');

// Source-only state and persistence contracts. Model execution and background/UI wiring remain separate work.
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
for (const name of ['AgentConversationGoal', 'AgentConversationGoalStore', 'AgentConversationGoalTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registration');
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source), name + ' localized resource placement');
}
assert.equal((read('GalaxySSITests/AgentConversationGoalTests.swift').match(/func test/g) || []).length, 14);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
for (const command of ['status', 'help', 'pause', 'stop', 'resume']) {
  assert(strings.includes(`"galaxyssi.conversation_goal.command_${command}" = `), command + ' alias');
}
console.log('Conversation goal state/store source contracts passed; provider, UI and background integration pending; no native execution.');

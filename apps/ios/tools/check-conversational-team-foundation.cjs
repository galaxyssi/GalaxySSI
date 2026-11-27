// Source contracts only. This does not execute Swift, validate live concurrency or complete the UI/job pipeline.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const read = file => fs.readFileSync(path.join(root, 'apps/ios', file), 'utf8').replace(/\r\n/g, '\n');
const contract = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
for (const token of ['maximumRoles = 10', 'maximumParallel = 3', 'maximumCalls = 12',
  'Set(parents).count == parents.count', 'parents.allSatisfy(roleID)', 'ids.count == roles.count',
  'role.parents.allSatisfy(ids.contains)', '!role.parents.contains(role.id)',
  'roles.filter { $0.parents.contains(role.id) }.count <= 3',
  'AgentSkillManifestValidator.topologicalSteps', 'fields.count == 5', 'tail.count == 2',
  'rows.count == 3', 'rows[2] == "END"', 'raw.utf16.count <= 6_000',
  '(1...2_000).contains(finding.utf16.count)', '(1...600).contains(dissent.utf16.count)',
  'body.utf16.count <= 8_000', 'never private reasoning', 'No tools, commands, file access, or further delegation']) assert(contract.includes(token), token);
for (const token of ['calls < Contract.maximumCalls', 'running.count == Contract.maximumParallel',
  'role.parents.allSatisfy({ reports[$0] != nil })', 'role.parents.map { parent',
  'withThrowingTaskGroup(of: Contract.Report.self)', 'let report = try await group.next()',
  'defer { group.cancelAll() }', 'Task.checkCancellation()', '120_000_000_000',
  'let ordered = try plan.roles.map', 'ordered.map(\\.json)', 'report.dissent.map',
  'onEvent(.interrupted)', 'onEvent(.stopped)']) assert(engine.includes(token), token);
assert(!/GalaxySSIHealthRecords|MessageCoordinator|enqueueDesktop|AgentNativeToolRegistry|URLSession|AgentSkillRuntime/.test(engine + contract),
  'Core orchestration must not acquire a provider, tool, health, desktop or Skill execution authority');
const event = engine.slice(engine.indexOf('  enum Event:'), engine.indexOf('  struct Outcome:'));
assert(!/String|objective|assignment|finding/.test(event), 'Progress must contain only bounded metadata');
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentConversationalTeamProtocol', 'AgentConversationalTeamEngine', 'AgentConversationalTeamCommand',
  'AgentConversationalTeamJob', 'AgentConversationalTeamStore', 'AgentConversationalTeamJobTests',
  'AgentConversationalTeamProtocolTests', 'AgentConversationalTeamEngineTests', 'AgentConversationalTeamCommandTests']) {
  const file = `${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`;
  const source = read(file);
  assert(!/\p{Script=Han}/u.test(source), name + ' localized resource placement');
  assert(Buffer.byteLength(source) < 32_768, name + ' scoped file size');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registration');
}
assert.equal((read('GalaxySSITests/AgentConversationalTeamProtocolTests.swift').match(/func test/g) || []).length, 8);
assert.equal((read('GalaxySSITests/AgentConversationalTeamEngineTests.swift').match(/func test/g) || []).length, 7);
assert.equal((read('GalaxySSITests/AgentConversationalTeamCommandTests.swift').match(/func test/g) || []).length, 8);
const command = read('GalaxySSI/AgentConversationalTeamCommand.swift');
for (const token of ['case start(String), stop, help, tooLong, privateObjective', 'text.hasPrefix("/")',
  'text.prefix(5).lowercased() == "/team"', 'quoted.stringByReplacingMatches', 'NSRange(prefix.startIndex..., in: prefix)',
  'matches(visible, key: "negative"', '!matches(value, key: "meta"', 'requested ? makeStart(text) : nil',
  'objective.utf16.count <= 4_000', 'key: "health"', 'language: LanguagePolicySettings.zhCN']) assert(command.includes(token), token);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
const keys = new Set();
for (const match of strings.matchAll(/^"galaxyssi\.conversation_team\.([^"\n]+)" = ("(?:[^"\\]|\\.)*");$/gm)) {
  assert(!keys.has(match[1]), 'Duplicate team resource: ' + match[1]); keys.add(match[1]);
  const value = JSON.parse(match[2]);
  if (match[1].startsWith('pattern_')) new RegExp(value, 'i');
}
for (const key of ['help_alias', 'stop_alias', 'pattern_stop', 'pattern_negative', 'pattern_meta', 'pattern_request', 'pattern_with_team', 'pattern_health']) {
  assert(keys.has(key), 'Localized command rule: ' + key);
}
const job = read('GalaxySSI/AgentConversationalTeamJob.swift');
const store = read('GalaxySSI/AgentConversationalTeamStore.swift');
for (const token of ['case queued, running, finished, stopped', 'state == .queued', 'state == .running',
  'calls < AgentConversationalTeamProtocol.maximumCalls', 'value.calls += 1', 'answer.utf16.count <= 64_000']) assert(job.includes(token), token);
for (const token of ['NSRecursiveLock()', 'AgentTurnReceiptEvidence.hash(owner)', 'AgentTurnReceiptEvidence.hash(conversation)',
  'try read(job.conversation) == expected', 'job.objective == expected.objective, job.route == expected.route',
  'job.revision == expected.revision + 1', 'guard !expected.active, job.state == .queued',
  'GalaxySSIEncryptedUserDefaultsStore.load', 'GalaxySSIEncryptedUserDefaultsStore.write', '".deleted"']) assert(store.includes(token), token);
const wire = read('GalaxySSI/AgentConversationGoalInference.swift');
assert(wire.includes('prompt: String? = nil') && wire.includes('system: system, prompt: prompt'), 'Exact shared text payload path');
assert.equal((read('GalaxySSITests/AgentConversationalTeamJobTests.swift').match(/func test/g) || []).length, 5);
console.log('Conversational team command/protocol/engine/job source contracts passed; confirmation, worker and background integration pending; no native execution.');

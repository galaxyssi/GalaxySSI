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
for (const name of ['AgentConversationalTeamProtocol', 'AgentConversationalTeamEngine',
  'AgentConversationalTeamProtocolTests', 'AgentConversationalTeamEngineTests']) {
  const file = `${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`;
  const source = read(file);
  assert(!/\p{Script=Han}/u.test(source), name + ' localized resource placement');
  assert(Buffer.byteLength(source) < 32_768, name + ' scoped file size');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registration');
}
assert.equal((read('GalaxySSITests/AgentConversationalTeamProtocolTests.swift').match(/func test/g) || []).length, 8);
assert.equal((read('GalaxySSITests/AgentConversationalTeamEngineTests.swift').match(/func test/g) || []).length, 7);
console.log('Conversational team protocol/engine source contracts passed; command, confirmation, persistence and background integration pending; no native execution.');

// Source contracts only. No Swift/native test execution or local server acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const wire = read('GalaxySSI/AgentTeamPlanWire.swift');
for (const token of ['system == AgentConversationalTeamProtocol.planner', 'apiStyle == .openAICompatible',
  'canonicalEndpoint(endpoint)', 'url.user == nil, url.password == nil, url.query == nil, url.fragment == nil',
  'url.percentEncodedPath == "/v1/chat/completions"', '(1...65_535).contains',
  'var requestFormat: AgentMcpJSONObject? { constrained ? format : nil }',
  'if !constrained, ["ROLE", "WORK", "REVIEW", "CRITIC", "SYNTHESIS"].contains(prefix)',
  'AgentTeamPlanJSONPreflight(reply); try preflight.validate()', 'Set(object.keys) == ["roles", "synthesis"]',
  'Set(role.keys) == ["kind", "parents", "task"]', 'guard case .int(let number) = value',
  '[.control, .format, .lineSeparator, .paragraphSeparator]', 'let plan = try AgentConversationalTeamProtocol.plan(text)',
  '"maxLength": .int(400)', '"maximum": .int(10)', 'max: 3', 'max: 10']) assert(wire.includes(token), token);
const preflight = read('GalaxySSI/AgentTeamPlanJSONPreflight.swift');
for (const token of ['cursor == bytes.count', 'depth <= limits.depth, nodes <= limits.nodes',
  'Limits(depth: 5, nodes: 100, entries: 10, string: 400)', 'limits: Limits = .plan',
  'keys.insert(key).inserted', 'keys.count <= limits.entries', 'entries <= limits.entries',
  'String($0) == token', 'JSONDecoder().decode(String.self, from: token)', 'value.utf16.count <= limits.string']) assert(preflight.includes(token), token);
const command = read('GalaxySSI/AgentConversationalTeamCommand.swift');
assert(command.includes('static func requestsFinalAudit') && command.includes('regex.stringByReplacingMatches'));
assert(command.includes('!matches(value, key: "negative"') && command.includes('!matches(value, key: "meta"'));
assert(command.includes('matches(value, key: "final_audit"'));
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
assert(engine.includes('fields: finalAuditRequired ? ["final_review_required": true] : [:]'));
const gate = engine.indexOf('if finalAuditRequired && editor == nil { throw Contract.Failure.finalAuditMissing }');
assert(gate > 0 && gate < engine.indexOf('withThrowingTaskGroup(of: Contract.Report.self)'), 'Missing final editor stops before any worker');
const transport = read('GalaxySSI/AgentConversationGoalInference.swift');
for (const token of ['AgentTeamPlanWire.select(system: system, endpoint: model.endpoint, apiStyle: model.apiStyle',
  'constrained: model.teamPlanConstrainedDecoding == true', 'let actualSystem = wire?.system ?? system',
  'text: actualSystem + "\\n" + prompt', 'systemPrompt: actualSystem', 'wire?.apply(to: isolated)',
  'let decoded = try wire?.decode(body) ?? body', 'if model.teamPlanConstrainedDecoding == true { fields["team_plan_schema"] = "true" }']) assert(transport.includes(token), token);
assert(transport.indexOf('if route.kind == .local') < transport.indexOf('let wire = AgentTeamPlanWire.select'), 'On-device routing unchanged');
const store = read('GalaxySSI/GalaxySSIStore.swift');
assert(store.includes('teamPlanConstrainedDecoding: Bool = false'));
assert(store.includes('!teamPlanConstrainedDecoding || (apiStyle == .openAICompatible && AgentTeamPlanWire.canonicalEndpoint(cleanEndpoint))'));
assert(read('GalaxySSI/GalaxySSICloudModelOnboardingView.swift').includes('teamPlanConstrainedDecoding: preset.teamPlanConstrainedDecoding'));
const models = read('GalaxySSI/GalaxySSICoreModels.swift');
assert(models.includes('var teamPlanConstrainedDecoding: Bool? = nil') && models.includes('name: "llama.cpp (JSON Schema)"'));
assert(read('GalaxySSI/AgentConversationalTeamRuntime.swift').includes('catch AgentConversationalTeamProtocol.Failure.finalAuditMissing'));
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentTeamPlanWire', 'AgentTeamPlanJSONPreflight', 'AgentTeamPlanWireTests']) {
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source)); assert(Buffer.byteLength(source) < 32_768);
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
}
assert.equal((read('GalaxySSITests/AgentTeamPlanWireTests.swift').match(/func test/g) || []).length, 13);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
for (const key of ['pattern_final_audit', 'final_audit_missing', 'schema_endpoint']) {
  assert.equal(strings.split(`"galaxyssi.conversation_team.${key}" =`).length - 1, 1);
}
console.log('Required final-review gate and local JSON plan wire source contracts passed; 13 synthetic XCTest methods authored, not executed.');

// Source contracts only, not native execution or a live review-quality acceptance test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const protocol = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
const narrow = protocol.slice(protocol.indexOf('  struct Objection:'), protocol.indexOf('  static func renderObjections'));
assert(narrow.includes('["id": id, "dissent": dissent]'));
assert(!/finding|assignment|reports|objective/.test(narrow), 'Only explicit role-attributed reservations cross the non-parent boundary');
assert(protocol.includes('var objection: Objection? { dissent.map'));
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
for (const token of ['let objections = ordered.compactMap(\\.objection)',
  'let additional = objections.filter { !editor.parents.contains($0.id) }',
  'if !additional.isEmpty { auditFields["additional_objections"] = additional.map(\\.json) }',
  'AgentTeamDraftAudit.Rejected(issue: issue, objections: objections)',
  'Contract.renderObjections(reports.compactMap(\\.objection), title: disagreementsTitle)']) assert(engine.includes(token), token);
const workerStart = engine.indexOf('let payload = try input("role"');
const workerEnd = engine.indexOf('group.addTask {', workerStart);
assert(!engine.slice(workerStart, workerEnd).includes('additional_objections'), 'Independent workers retain parent-only isolation');
assert(engine.includes('calls < Contract.maximumCalls'), 'No extra objection synthesis call');
const audit = read('GalaxySSI/AgentTeamDraftAudit.swift');
assert(audit.includes('additional_objections as well as assigned reports'));
assert(audit.includes('they do not override source arithmetic'));
const rejection = audit.slice(audit.indexOf('  struct Rejected:'), audit.indexOf('  struct Result {'));
assert(rejection.includes('let issue: Failure') && rejection.includes('[AgentConversationalTeamProtocol.Objection]'));
assert(!/draft|Report\]|assignment|finding/.test(rejection), 'Rejected draft/full reports must not be retained in the error receipt');
const runtime = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
assert(runtime.includes('catch let rejection as AgentTeamDraftAudit.Rejected'));
assert(runtime.includes('auditFailure(rejection.issue, store: store) + AgentConversationalTeamProtocol.renderObjections'));
assert(runtime.includes('Host-calculated values and model reservations are listed separately:'));
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
assert.equal(project.split('AgentTeamPublicObjectionTests.swift in Sources').length - 1, 2);
const tests = read('GalaxySSITests/AgentTeamPublicObjectionTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 4);
assert(!/\p{Script=Han}/u.test(tests));
console.log('Public review objection isolation, preserved rejection and source contracts passed; four native test methods authored, not executed.');

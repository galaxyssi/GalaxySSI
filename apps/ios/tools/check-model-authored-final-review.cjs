// Source contracts only, not native or live-model execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const protocol = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
for (const token of ['static let finalReviewPlanner', 'roles, synthesis, and final_review', 'Use zero to nine contributors',
  'Do not list that reviewer as a contributor']) assert(protocol.includes(token), token);
const wire = read('GalaxySSI/AgentTeamPlanWire.swift');
for (const token of ['system == AgentConversationalTeamProtocol.finalReviewPlanner',
  'if finalReview { return AgentConversationalTeamProtocol.finalReviewPlanner }',
  '"anyOf": .array([brief, role])', 'max: 9), "synthesis": brief, "final_review": brief',
  'if finalReview && plan.finalEditor == nil', 'let hasFinalBrief = finalReview && object["final_review"] != nil',
  'Set(object.keys) == ["roles", "synthesis", "final_review"]', 'Set(object.keys) == ["roles", "synthesis"]',
  '!hasFinalBrief || roles.count <= 9', 'if finalReview, let assignment = value.strictStringValue',
  'guard hasFinalBrief else', 'lines.append("REVIEW|-|" + (try brief(object, "final_review")))',
  'return try checked(lines.joined(separator: "\\n"))']) assert(wire.includes(token), token);
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
assert(engine.includes('finalAuditRequired ? Contract.finalReviewPlanner : Contract.planner'));
assert(engine.includes('AgentTeamPlanWire(constrained: false, finalReview: true).decode(planReply)'));
assert(engine.includes('catch let error as Contract.Failure { throw error }'), 'Missing-editor failures retain their specific receipt');
assert(engine.includes('calls < Contract.maximumCalls') && engine.includes('"draft": draft'));
const tests = read('GalaxySSITests/AgentModelAuthoredFinalReviewTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 8);
assert(tests.includes('Actual finding from role1') && tests.includes('The actual unreviewed schedule draft'));
assert(tests.includes('XCTAssertEqual(outcome.calls, 12)'));
assert(!/\p{Script=Han}/u.test(tests));
assert.equal(read('GalaxySSI.xcodeproj/project.pbxproj').split('AgentModelAuthoredFinalReviewTests.swift in Sources').length - 1, 2);
console.log('Model-authored final editor and actual draft handoff source contracts passed; eight native test methods authored, not executed.');

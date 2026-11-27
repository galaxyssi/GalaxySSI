// Structural contracts, not native execution, model quality or on-device certification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const proposal = read('GalaxySSI/AgentLocalTeamReviewProposal.swift');
for (const token of ['static let field = "propose_team_review"', 'guard value.hasPrefix("{")',
  'JSONDecoder().decode(AgentMcpJSONObject.self', 'root[field] == .bool(true)',
  'Set(root.keys) == ["answer", "tool_calls", field]', 'root["tool_calls"] == .array([])',
  'Set(root.keys) == ["disposition", "final_response", field]', 'root["disposition"] == .string("respond")',
  'private static var windows:', 'weak var value:', '!window.requested, window.usable()',
  'candidate.objective == objective', 'candidate.selection.targetId == "local-llm"',
  'candidate.selection.modelId == profile', 'window.proposed = false; window.proposal = candidate',
  'func claim() -> Candidate?', 'Self.windows.removeValue(forKey: key)', 'original.content == objective']) assert(proposal.includes(token), token);
assert(!/AgentConversationalTeamRuntime|\.run\(|URLSession|generateAsync/.test(proposal), 'Suggestion state has no dispatch authority');
const local = read('GalaxySSI/LocalModelAgentPlanningProvider.swift');
for (const token of ['invocation.request.permitsAnswerOnlyResponse && !invocation.request.hasAttachments',
  'await AgentLocalTeamReviewWindow.request', 'AgentLocalTeamReviewProposal.plannerInstruction',
  'result.profileId == profile.id', 'AgentLocalTeamReviewProposal.proposed(object, planner: true)',
  'object.removeValue(forKey: AgentLocalTeamReviewProposal.field)', 'return AgentMcpJSONCodec.stringify(object)']) assert(local.includes(token), token);
assert.equal((local.match(/runtime.generateAsync\(/g) || []).length, 1, 'No extra proposal inference');
const adapter = read('GalaxySSI/AgentIOSLocalModelWebToolAdapter.swift');
for (const token of ['request.round == 1 && !goalAssessmentOnly', 'let calls = reviewEnvelope ? []',
  'AgentLocalTeamReviewProposal.proposed(whole)', 'offerTeamReview && !hasAttachments && !readOnlyAnalysis && owner == nil',
  'managedBrowser == nil && managedInput == nil && managedJournal == nil',
  'goalWorkMilestone == nil && workInputPublisher == nil', 'proposedTeamReview: session.proposedTeamReview']) assert(adapter.includes(token), token);
const home = read('GalaxySSI/GalaxySSIAndroidParityUI.swift');
assert(home.includes('@StateObject var modelTeamReview = AgentLocalTeamReviewWindow()'));
assert(home.includes('if phase != .active { modelTeamReview.invalidate() }'));
assert(home.includes('await Task.yield(); offerModelTeamReview()'), 'Read Published state only after assignment');
const submit = read('GalaxySSI/GalaxySSIAgentHomeMessageSubmission.swift');
assert(submit.includes('hasExtras: isVoiceSubmission || !outgoingAttachments.isEmpty || assistantRunID != nil'));
const ui = read('GalaxySSI/GalaxySSIConversationalTeamView.swift');
for (const token of ['launch.source?.matches(store', 'if launch.source == nil {', 'next.source = launch.source',
  'modelTeamReview.bind(submitted)', 'submitted.source.matches(store', 'modelTeamReview.claim()',
  'source: candidate.source', 'draft.isBlank, attachments.isEmpty']) assert(ui.includes(token), token);
const runtime = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
assert(runtime.includes('actual.source == original.source') && runtime.includes('original.source?.matches(store'));
assert(runtime.includes('turnId: job.source?.turn ?? job.id.uuidString'));
const contract = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
for (const token of ['WORK|parents|task, REVIEW|parents|task, or CRITIC|parents|task',
  'Roles are numbered automatically from 1', 'if !legacy', 'number >= 1, number <= index, String(number) == ref',
  'Set(parents).count == parents.count', 'JSONDecoder().decode(AgentMcpJSONObject.self',
  'Set(object.keys).isSubset(of: ["finding", "dissent"])', 'object.count == 1',
  'A criterion or simulated response is not a measured property']) assert(contract.includes(token), token);
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentLocalTeamReviewProposal', 'AgentLocalTeamReviewTests']) {
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source));
  assert(Buffer.byteLength(source) < 32_768);
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
}
assert.equal((read('GalaxySSITests/AgentLocalTeamReviewTests.swift').match(/func test/g) || []).length, 10);
assert.equal((read('GalaxySSITests/AgentConversationalTeamProtocolTests.swift').match(/func test/g) || []).length, 13);
console.log('Local team review source contracts passed; 15 new synthetic XCTest methods authored, not executed.');

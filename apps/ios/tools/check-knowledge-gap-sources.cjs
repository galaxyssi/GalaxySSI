// Source-only gap provenance contracts; no Swift compilation/native test execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ca36efb28c5e2e72c620e20c4e88ccfe30e1549a';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => require('./check-autonomous-source-scope.cjs').retained(f,
  require('./check-research-context-provenance.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8'))));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first); return s.slice(a, b);
}
function retained(file, s) {
  if (file.endsWith('AgentCognitiveGovernance.swift') && s.includes('  var sourceConversationIds: Set<String>?')) {
    s = once(s, '  var sourceConversationIds: Set<String>?\n', '');
    s = once(s, ',\n    sourceConversationIds: Set<String>? = nil', '');
    s = once(s, '    self.sourceConversationIds = sourceConversationIds\n', '');
    s = once(s, ',\n      sourceConversationIds: gap.sourceConversationIds', '');
    s = once(s, '    guard sample.runId == run.runId else { return nil }\n', '');
    s = once(s, section(s, '    let conversationId = run.conversationId.trimmingCharacters', '    let gap = AgentKnowledgeGap('), '');
    return once(s, ',\n      sourceConversationIds: sources', '');
  }
  if (file.endsWith('AgentCognitiveGovernanceRuntime.swift') && s.includes('  private func observeLocked(_ gap: AgentKnowledgeGap)')) {
    const first = 'final class AgentKnowledgeGapResearchBridge {', last = 'struct AgentProtocolEndpointGrant:';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  return s;
}
function validate() {
  for (const name of ['AgentCognitiveGovernance', 'AgentCognitiveGovernanceRuntime']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), old(file), name + ': retained code outside declared gap hooks');
  }
  const model = read(app + 'AgentCognitiveGovernance.swift');
  for (const token of ['var sourceConversationIds: Set<String>?', 'sourceConversationIds: gap.sourceConversationIds',
    'guard sample.runId == run.runId', 'sources = existing.sourceConversationIds.map { $0.union([conversationId]) }',
    'AgentEvalSideEffectPolicy.allowsPersonalLearning(conversationId: conversationId)', 'sourceConversationIds: sources']) assert(model.includes(token), token);
  const detector = section(model, 'enum AgentKnowledgeGapDetector {', 'enum AgentStandardProtocol:');
  assert(detector.indexOf('guard sample.runId') < detector.indexOf('let topic'));
  const runtime = read(app + 'AgentCognitiveGovernanceRuntime.swift');
  const bridge = section(runtime, 'final class AgentKnowledgeGapResearchBridge {', 'struct AgentProtocolEndpointGrant:');
  for (const token of ['locked { observeLocked(gap) }', 'guard let sources = gap.sourceConversationIds, !sources.isEmpty',
    'sources.allSatisfy', 'sourceConversationId: sources.sorted().first ?? ""', 'sourceConversationIds: sources',
    'guard researchStore.lastErrorDescription.isEmpty else { return }']) assert(bridge.includes(token), token);
  assert(!bridge.includes('sourceConversationId: "agent-evalops"'));
  const save = bridge.indexOf('researchStore.save(state)');
  const saveGuard = bridge.indexOf('guard researchStore.lastErrorDescription.isEmpty', save);
  assert(save >= 0 && saveGuard > save && saveGuard < bridge.indexOf('governance.updateGapStatus'));
  assert(bridge.indexOf('guard let sources') < bridge.indexOf('var state = researchStore.state()'));
  assert(bridge.indexOf('guard researchStore.lastErrorDescription.isEmpty') < bridge.indexOf('let sourceEventId'));
  const tests = 'apps/ios/GalaxySSITests/AgentEvalOpsTests.swift';
  assert.equal((read(tests).match(/  func test/g) || []).length - (old(tests).match(/  func test/g) || []).length, 10);
  for (const file of ['GalaxySSIServices', 'AgentObservationModels', 'AgentRecordedRunStore', 'AgentEvalOpsStore',
    'AgentTrajectoryLearning', 'GlobalResearchExecutorModels', 'GlobalResearchExecutorPolicy', 'GalaxySSIGlobalAgentRuntime']) {
    assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file + ': unchanged dependency');
  }
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'));
  console.log('Knowledge-gap source union, legacy quarantine, research production and retained source contracts passed; no native acceptance');
}
if (require.main === module) validate();
module.exports = {retained, validate};

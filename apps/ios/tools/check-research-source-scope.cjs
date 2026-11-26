// Source contracts only: does not compile Swift or execute native fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '17441c5c98b4a1d20eef6b9ac8c8aa3f20ae638f';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => require('./check-knowledge-gap-sources.cjs').retained(f,
  require('./check-autonomous-source-scope.cjs').retained(f,
    require('./check-research-context-provenance.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8')))));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) {
  assert.equal(s.split(from).length, 2, from);
  return s.replace(from, to);
}
function section(s, first, last) {
  const start = s.indexOf(first), end = s.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(s.split(first).length, 2, first);
  return s.slice(start, end);
}
function retained(file, s) {
  const prior = old(file);
  if (file.endsWith('GalaxySSIGlobalAgentRuntime.swift')) {
    for (const [first, last] of [
      ['  static func processResearchCycle(', '  private static func researchResources('],
      ['  private static func researchContext(', '  static func compiledConversationContext(']
    ]) s = once(s, section(s, first, last), section(prior, first, last));
  } else if (file.endsWith('GalaxySSIServices.swift')) {
    s = once(s, 'contactId: request.contactId.ifBlank(request.resourceId),\n          content: "Global research',
      'contactId: request.contactId,\n          content: "Global research');
    const first = '  private func dispatchGlobalResearchRequest(', last = '  func publicAttentionLink(';
    s = once(s, section(s, first, last), section(prior, first, last));
  } else if (file.endsWith('GlobalRealtimeContext.swift')) {
    const research = section(s, 'struct GlobalResearchTask:', 'enum GlobalRunReviewStatus:');
    let restored = once(research, '  var sourceConversationIds: Set<String>?\n', '');
    restored = once(restored, ',\n    sourceConversationIds: Set<String>? = nil', '');
    restored = once(restored, '    self.sourceConversationIds = sourceConversationIds\n', '');
    s = once(s, research, restored);
  } else if (file.endsWith('GlobalResearchExecutorModels.swift')) {
    s = once(s, section(s, 'enum GlobalResearchSourceScope {', 'struct GlobalResearchExecutionResult:'), '');
    s = once(s, ',\n      sourceConversationIds: task.sourceConversationIds', '');
  } else if (file.endsWith('GlobalResearchExecutorPolicy.swift')) {
    s = once(s, 'nowMillis: Int64,\n    eligible: (GlobalResearchTask) -> Bool = { _ in true })', 'nowMillis: Int64)');
    s = once(s, ',\n    eligible: (GlobalResearchTask) -> Bool = { _ in true }', '');
    s = once(s, 'nowMillis: nowMillis, eligible: eligible)', 'nowMillis: nowMillis)');
    s = once(s, '      .filter(eligible)\n', '');
  }
  return s;
}
function validate() {
  for (const name of ['GalaxySSIGlobalAgentRuntime', 'GalaxySSIServices', 'GlobalRealtimeContext',
    'GlobalResearchExecutorModels', 'GlobalResearchExecutorPolicy']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), old(file), name + ': unchanged outside declared research hooks');
  }
  const runtime = read(app + 'GalaxySSIGlobalAgentRuntime.swift');
  const process = section(runtime, '  static func processResearchCycle(', '  @discardableResult\n  static func consumeResearchResponse(');
  assert.equal(process.split('eligible: { GlobalResearchSourceScope.allows($0, scope: scope) }').length, 3);
  assert(process.includes('into: &state, scope: scope'));
  const consume = section(runtime, '  static func consumeResearchResponse(', '  static func researchState()');
  assert(consume.indexOf('owned.count == 1') < consume.indexOf('GlobalResearchExecutorPolicy.consumeConnectorResponse('));
  assert(consume.includes('request.taskId == task.id'));
  assert(consume.includes('permitsResearchRequest(store: store, request: request)'));
  assert(consume.includes('stateStore.save(step.state)\n    guard stateStore.lastErrorDescription.isEmpty else { return false }'));
  const permits = section(runtime, '  static func permitsResearchRequest(', '  private static func seedResearchTasks(');
  for (const token of ['settings.autonomousResearchEnabled', 'state.dispatchRequests.contains(request)',
    'GlobalResearchSourceScope.allows(task, scope: scope)', 'PublicAttentionResearchPolicy.allows(request, settings: settings)',
    'request.contactId == request.resourceId', 'contact.trustState == .verified', 'settings.allowCloudCognition']) assert(permits.includes(token), token);
  const context = section(runtime, '  private static func researchContext(', '  static func compiledConversationContext(');
  for (const token of ['GlobalResearchSourceScope.allows(task, scope: scope)', 'excludedConversationIds: scope.excludedConversationIds',
    'allowedConversationIds: scope.allowedConversationIds', 'state.tasks.filter']) assert(context.includes(token), token);
  assert(context.indexOf('guard let task') < context.indexOf('store.agentSessionMessages'));
  const models = read(app + 'GlobalResearchExecutorModels.swift');
  for (const token of ['sensitivity != .sessionPrivate', 'metadata["source_conversation_ids"] != nil',
    'metadata["long_horizon_goal_id"] == goalId', 'sources.isSubset(of: scope.allowedConversationIds)',
    'ids.formUnion(cognition.contextConversationIds ?? [])', 'guard cognition.contextConversationIds != nil',
    'sources.contains(task.sourceConversationId)', 'response.sourceMessageId > 0',
    'response.contactId == request.resourceId', 'sourceConversationIds: task.sourceConversationIds']) assert(models.includes(token), token);
  const claim = section(read(app + 'GlobalResearchExecutorPolicy.swift'), '  static func claimTask(', '  private static func isClaimable(');
  assert(claim.indexOf('.filter(eligible)') < claim.indexOf('.map { GlobalResearchTaskPolicy.recoverIfStale'));
  const services = section(read(app + 'GalaxySSIServices.swift'), '  private func dispatchGlobalResearchRequest(', '  func publicAttentionLink(');
  assert.equal(services.split('permitsResearchRequest(store: store, request: request)').length, 4);
  assert(services.includes('stillAuthorized: { GalaxySSIGlobalAgentRuntimeBridge.permitsResearchRequest(store: self.store, request: request) }'));
  const fixtures = read('apps/ios/GalaxySSITests/GlobalResearchExecutorPolicyTests.swift');
  assert.equal((fixtures.match(/  func test/g) || []).length - (old('apps/ios/GalaxySSITests/GlobalResearchExecutorPolicyTests.swift').match(/  func test/g) || []).length, 8);
  for (const name of ['GlobalRealtimePlanningScope', 'GlobalRealtimeContextProvider', 'PublicAttentionPreferences',
    'GalaxySSIGlobalAutonomousRuntime', 'AgentCognitiveGovernanceRuntime']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ': frozen dependency');
  console.log('Research source inheritance, dual selection, dispatch/consume and retained source contracts passed; no native acceptance');
}
if (require.main === module) validate();
module.exports = {validate, retained};

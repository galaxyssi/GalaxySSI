// Source contracts only; not Swift compilation or native privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '0bdfc81662cc27f638f0b3360f13c399ad2ba704';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => require('./check-provider-resource-ranking-scope.cjs').retained(f,
  require('./check-routing-health-scope.cjs').retained(f,
    require('./check-routing-usage-scope.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8')))));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first); return s.slice(a, b);
}
function retained(file, s) {
  s = require('./check-routing-usage-scope.cjs').retained(file, s);
  s = require('./check-routing-health-scope.cjs').retained(file, s);
  s = require('./check-provider-resource-ranking-scope.cjs').retained(file, s);
  s = require('./check-connector-observation-timing-scope.cjs').retained(file, s);
  if (file.endsWith('GalaxySSIGlobalAutonomousResearchRuntime.swift') && s.includes('next.sourceConversationIds = current.sourceConversationIds.map')) {
    return once(s, '      next.sourceConversationIds = current.sourceConversationIds.map { $0.union(researchSources) }\n', '');
  }
  if (file.endsWith('GlobalResearchExecutorPolicyTests.swift') && s.includes('  func testResearchDispatchContextProofRoundtripAndLegacyQuarantine()')) {
    return once(s, section(s, '  func testResearchDispatchContextProofRoundtripAndLegacyQuarantine()',
      '  func testResearchScopeRequiresCompleteKnownEligibleSources()'), '');
  }
  if (file.endsWith('GlobalRealtimeContext.swift') && s.includes('guard let eventSources =')) {
    const first = '  static func project(', last = '  static func select(';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  if (file.endsWith('GlobalRealtimeContextProvider.swift') && s.includes('    let researchTasks = allowedConversationIds == nil')) {
    s = once(s, section(s, '    let researchTasks = allowedConversationIds == nil', '    let allowedGoals ='), '');
    s = once(s, '      researchTasks: researchTasks,', '      researchTasks: snapshot.researchTasks,');
    return once(s, '      autonomousRuns: autonomousRuns,', '      autonomousRuns: snapshot.autonomousRuns,');
  }
  if (file.endsWith('GlobalResearchExecutorModels.swift') && s.includes('  static func allowsContext(')) {
    s = once(s, section(s, '  static func allowsContext(', '  static func sourceIds('), '');
    const req = section(s, 'struct GlobalResearchDispatchRequest:', 'struct GlobalResearchExecutorBudgetLimits:');
    let restored = once(req, '  var contextConversationIds: Set<String>?\n', '');
    restored = once(restored, ',\n    contextConversationIds: Set<String>? = nil', '');
    restored = once(restored, '    self.contextConversationIds = contextConversationIds\n', '');
    restored = once(restored, '    case contextConversationIds = "context_conversation_ids"\n', '');
    s = once(s, req, restored);
    const context = section(s, 'struct GlobalResearchExecutionContext:', 'struct GlobalResearchResourceHealthUpdate:');
    restored = once(context, '  var conversationIds: Set<String>?\n', '');
    restored = once(restored, ',\n    conversationIds: Set<String>? = nil', '');
    restored = once(restored, '    self.conversationIds = conversationIds\n', '');
    restored = once(restored, '    case conversationIds = "conversation_ids"\n', '');
    return once(s, context, restored);
  }
  if (file.endsWith('GlobalResearchExecutorPolicy.swift') && s.includes('contextConversationIds: PublicAttentionResearchPolicy')) {
    for (const variable of ['running', 'synthesizing']) s = once(s,
      ',\n      contextConversationIds: PublicAttentionResearchPolicy.isPublicTask(' + variable + '.id) ? [] : context.conversationIds', '');
    return s;
  }
  if (file.endsWith('GalaxySSIGlobalAgentRuntime.swift') && s.includes('GlobalResearchSourceScope.allowsContext(request,')) {
    s = once(s, section(s, '    guard var step else { return false }', '    stateStore.save(step.state)'), '    guard let step else { return false }\n');
    s = once(s, 'GlobalResearchSourceScope.allows(task, scope: scope),\n          GlobalResearchSourceScope.allowsContext(request, scope: scope)', 'GlobalResearchSourceScope.allows(task, scope: scope)');
    const first = '  private static func researchContext(', last = '  static func compiledConversationContext(';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  return s;
}
function validate() {
  for (const name of ['GlobalRealtimeContext', 'GlobalRealtimeContextProvider', 'GlobalResearchExecutorModels', 'GlobalResearchExecutorPolicy', 'GalaxySSIGlobalAgentRuntime', 'GalaxySSIGlobalAutonomousResearchRuntime']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), old(file), name + ': unchanged outside declared projection/context hooks');
  }
  const projection = section(read(app + 'GlobalRealtimeContext.swift'), '  static func project(', '  static func select(');
  assert.equal((projection.match(/conversationIds: sources,/g) || []).length, 3);
  assert.equal((projection.match(/!sources.isDisjoint\(with: excludedConversationIds\)/g) || []).length, 3);
  assert(projection.includes('eventSources.union(task.contextConversationIds ?? [])'));
  assert(projection.includes('!goal.sourceConversationIds.isDisjoint(with: excludedConversationIds)'));
  assert(!projection.includes('.subtracting(excludedConversationIds)'));
  const provider = read(app + 'GlobalRealtimeContextProvider.swift');
  assert.equal((provider.match(/filter \{ \$0.sourceConversationIds != nil \}/g) || []).length, 2);
  assert(provider.includes('item.conversationIds.isSubset(of: $0)'));
  const models = read(app + 'GlobalResearchExecutorModels.swift');
  for (const token of ['let sources = request.contextConversationIds', 'sources.isSubset(of: scope.allowedConversationIds)',
    'sources.isEmpty', 'case contextConversationIds = "context_conversation_ids"', 'case conversationIds = "conversation_ids"']) assert(models.includes(token), token);
  const policy = read(app + 'GlobalResearchExecutorPolicy.swift');
  assert.equal((policy.match(/contextConversationIds: PublicAttentionResearchPolicy/g) || []).length, 2);
  const runtime = read(app + 'GalaxySSIGlobalAgentRuntime.swift');
  const consume = section(runtime, '  static func consumeResearchResponse(', '  static func researchState(');
  assert(consume.indexOf('updated.sourceConversationIds = existingSources.union(contextSources)') < consume.indexOf('stateStore.save(step.state)'));
  assert(consume.includes('permitsResearchRequest(store: store, request: request)'));
  assert(read(app + 'GalaxySSIGlobalAutonomousResearchRuntime.swift').includes('next.sourceConversationIds = current.sourceConversationIds.map { $0.union(researchSources) }'));
  const permits = section(runtime, '  static func permitsResearchRequest(', '  private static func seedResearchTasks(');
  assert(permits.indexOf('GlobalResearchSourceScope.allowsContext(request, scope: scope)') < permits.indexOf('if PublicAttentionResearchPolicy.isPublicTask'));
  const context = section(runtime, '  private static func researchContext(', '  static func compiledConversationContext(');
  assert(context.includes(').buildProjection('));
  assert(context.includes('conversationIds: realtime.conversationIds.union('));
  for (const [name, count] of [['GlobalRealtimeContextTests', 6], ['GlobalResearchExecutorPolicyTests', 4]]) {
    const file = 'apps/ios/GalaxySSITests/' + name + '.swift';
    assert.equal((read(file).match(/  func test/g) || []).length - (old(file).match(/  func test/g) || []).length, count);
  }
  for (const name of ['GalaxySSIServices', 'GlobalBackgroundCognitionScope', 'GalaxySSIGlobalAutonomousRuntime',
    'AgentCognitiveGovernance', 'AgentRecordedRunStore', 'GlobalResearchPromptBuilder']) assert.equal(
      require('./check-connector-observation-timing-scope.cjs').retained(app + name + '.swift', read(app + name + '.swift')),
      old(app + name + '.swift'), name + ': unchanged dependency outside observation timing metadata');
  console.log('Complete context source unions, recorded dispatch proof and accepted-source retention contracts passed; no native acceptance');
}
if (require.main === module) validate();
module.exports = {retained, validate};

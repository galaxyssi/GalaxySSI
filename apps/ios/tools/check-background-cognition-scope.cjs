// Incremental source contracts only, not native privacy/transport/storage acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '49c2522d05cef989f00fcde7474bb38d117bc7fb';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first);
  return s.slice(a, b);
}
function retainedBackgroundCognitionFile(file, s) {
  if (file.endsWith('GalaxySSIServices.swift') && s.includes('    stillAuthorized: () -> Bool = { true }')) {
    const before = old(app + 'GalaxySSIServices.swift');
    s = once(s, '        guard let self else { return }\n        let consumed = GalaxySSIGlobalAgentRuntimeBridge.consumeCognitionResponse(store: self.store, response: response) != nil\n        if consumed {\n          self.refreshAgentHomeState()',
      '        let consumed = GalaxySSIGlobalAgentRuntimeBridge.consumeCognitionResponse(response) != nil\n        if consumed {\n          self?.refreshAgentHomeState()');
    const first = '  @discardableResult\n  func runGlobalCognitionCycle(', last = '  /// Mirrors Android\'s profile update fan-out';
    return once(s, section(s, first, last), section(before, first, last));
  }
  if (file.endsWith('GalaxySSIGlobalAgentRuntime.swift') && s.includes('  static func permitsCognitionRequest(')) {
    const first = '  @discardableResult\n  static func processCognitionCycle(', last = '  private static func cognitionCorrelationId(';
    return once(s, section(s, first, last), section(old(app + 'GalaxySSIGlobalAgentRuntime.swift'), first, last));
  }
  if (file.endsWith('GlobalRealtimeContext.swift') && s.includes('  var contextConversationIds: Set<String>?')) {
    s = once(s, '  var contextConversationIds: Set<String>?\n  var resourceTransport: GlobalResearchResourceTransport?\n', '');
    s = once(s, '    updatedAtMillis: Int64 = GlobalRealtimeClock.nowMillis(),\n    contextConversationIds: Set<String>? = nil,\n    resourceTransport: GlobalResearchResourceTransport? = nil', '    updatedAtMillis: Int64 = GlobalRealtimeClock.nowMillis()');
    s = once(s, '    self.contextConversationIds = contextConversationIds\n    self.resourceTransport = resourceTransport\n', '');
    s = once(s, '    case contextConversationIds\n    case resourceTransport\n', '');
    return once(s, '      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? GlobalRealtimeClock.nowMillis(),\n      contextConversationIds: try container.decodeIfPresent(Set<String>.self, forKey: .contextConversationIds),\n      resourceTransport: try container.decodeIfPresent(GlobalResearchResourceTransport.self, forKey: .resourceTransport)',
      '      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? GlobalRealtimeClock.nowMillis()');
  }
  if (file.endsWith('GlobalAgentDeliberationStore.swift') && s.includes('    expected: GlobalCognitionTask? = nil,')) {
    s = once(s, '    expected: GlobalCognitionTask? = nil,\n', '');
    s = once(s, '      guard expected == nil || snapshot.cognitionTasks[index] == expected else { return nil }\n', '');
    s = once(s, '      return lastErrorDescription.isEmpty ? updated : nil', '      return updated');
    s = once(s, '  func claimCognitionTask(nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),\n                          eligible: (GlobalCognitionTask) -> Bool = { _ in true }) -> GlobalCognitionTask? {',
      '  func claimCognitionTask(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> GlobalCognitionTask? {');
    return once(s, '          eligible(tasks[$0]) && [.queued, .waitingForResource].contains(tasks[$0].status) &&',
      '          [.queued, .waitingForResource].contains(tasks[$0].status) &&');
  }
  if (file.endsWith('GlobalLongHorizonCoordinator.swift') && s.includes('        "source_conversation_ids": goal.sourceConversationIds.sorted().joined(separator: ","),')) {
    return once(s, '        "source_conversation_ids": goal.sourceConversationIds.sorted().joined(separator: ","),\n', '');
  }
  if (file.endsWith('GlobalRealtimeContextProvider.swift') && s.includes('struct GlobalRealtimeContextProjection {')) {
    const before = old(app + 'GlobalRealtimeContextProvider.swift');
    s = once(s, 'struct GlobalRealtimeContextProjection {\n  var text: String\n  var conversationIds: Set<String>\n}\n\n', '');
    const first = '  func build(', last = '  /// Returns the last complete snapshot';
    s = once(s, section(s, first, last), section(before, first, last));
    s = once(s, '    ).text\n  }\n\n  func prewarm(', '    )\n  }\n\n  func prewarm(');
    s = once(s, '    allowedConversationIds: Set<String>? = nil,\n    captureConversationIds: Bool = false\n  ) -> GlobalRealtimeContextProjection {',
      '    allowedConversationIds: Set<String>? = nil\n  ) -> String {');
    return once(s, '    return GlobalRealtimeContextProjection(text: GlobalRealtimeContextPolicy.render(selected, maximumCharacters: maximumCharacters),\n      conversationIds: captureConversationIds ? Set(selected.flatMap(\\.conversationIds)) : [])',
      '    return GlobalRealtimeContextPolicy.render(selected, maximumCharacters: maximumCharacters)');
  }
  return s;
}
function validateBackgroundCognition() {
  for (const name of ['GalaxySSIServices', 'GalaxySSIGlobalAgentRuntime', 'GlobalRealtimeContext', 'GlobalAgentDeliberationStore', 'GlobalRealtimeContextProvider', 'GlobalLongHorizonCoordinator'])
    assert.equal(retainedBackgroundCognitionFile(name + '.swift', read(app + name + '.swift')), old(app + name + '.swift'), name + ' only declared cognition/provenance hooks');
  const scope = read(app + 'GlobalBackgroundCognitionScope.swift'), runtime = read(app + 'GalaxySSIGlobalAgentRuntime.swift');
  const services = read(app + 'GalaxySSIServices.swift'), provider = read(app + 'GlobalRealtimeContextProvider.swift');
  const queue = read(app + 'GlobalAgentDeliberationStore.swift');
  for (const token of ['task.sourceEvent.sensitivity != .sessionPrivate', 'source_conversation_ids',
    'ids.isSubset(of: conversations.allowedConversationIds)', 'let contextIds = task.contextConversationIds',
    'contextIds.isSubset(of: conversations.allowedConversationIds)', 'task.resourceTransport != nil',
    'task.sourceMessageId > 0', 'task.resourceId == response.contactId', 'task.resourceTransport == request.transport',
    'request.conversationId == "global-cognition:', 'response.conversationId.isEmpty ||']) assert(scope.includes(token), token);
  assert(scope.includes('primary == "global-goal:\\(goalId)"'));
  assert(scope.includes('task.sourceEvent.metadata["source_conversation_ids"] != nil'));
  assert(read(app + 'GlobalLongHorizonCoordinator.swift').includes('"source_conversation_ids": goal.sourceConversationIds.sorted().joined(separator: ",")'));
  for (const token of ['eligible: scope.allowsSource', 'running.contextConversationIds = context.conversationIds',
    'running.resourceTransport = resource.transport', 'expected: claimed', 'prepared == running',
    'scope.accepts(task, response: response)', 'scope.accepts(task, request: request)',
    'matches.count == 1', 'requiredResourceId: request.resourceId', 'cognitionResourceAuthorized(task, store: store)']) assert(runtime.includes(token), token);
  const process = section(runtime, '  static func processCognitionCycle(', '  @discardableResult\n  static func consumeCognitionResponse(');
  assert(process.indexOf('running.contextConversationIds = context.conversationIds') < process.indexOf('expected: claimed'));
  assert(process.indexOf('prepared == running') < process.indexOf('return GalaxySSIGlobalCognitionDispatchRequest('));
  const consume = section(runtime, '  static func consumeCognitionResponse(', '  static func permitsCognitionRequest(');
  assert(consume.indexOf('scope.accepts(task, response: response)') < consume.indexOf('GalaxySSIGlobalModelUnderstandingParser.parse'));
  assert.equal((consume.match(/expected: task/g) || []).length, 2);
  const originalConsume = section(old(app + 'GalaxySSIGlobalAgentRuntime.swift'), '    guard response.success,', '  private static func cognitionResource(');
  assert.equal(section(consume, '    guard response.success,', '  }\n\n').length > 0, true);
  const unchangedEffects = consume.slice(consume.indexOf('    guard response.success,')).replaceAll('taskId: task.id, expected: task)', 'taskId: task.id)');
  assert.equal(unchangedEffects, originalConsume, 'Original parsing/retry/result/autonomous-run promotion body retained after new guards');
  assert(queue.includes('guard expected == nil || snapshot.cognitionTasks[index] == expected else { return nil }'));
  assert(queue.includes('return lastErrorDescription.isEmpty ? updated : nil'));
  assert(provider.includes('captureConversationIds: true'));
  assert(provider.includes('captureConversationIds ? Set(selected.flatMap(\\.conversationIds)) : []'));
  assert(services.includes('consumeCognitionResponse(store: self.store, response: response)'));
  assert(!services.includes('consumeCognitionResponse(response)'));
  const dispatch = section(services, '  private func dispatchGlobalCognitionRequest(', '  private func dispatchGlobalLocalModelRequest(');
  assert(dispatch.indexOf('permitsCognitionRequest(store: store, request: request)') < dispatch.indexOf('switch request.transport'));
  assert(dispatch.includes('stillAuthorized: { GalaxySSIGlobalAgentRuntimeBridge.permitsCognitionRequest('));
  assert.equal((dispatch.match(/requireAvailable: false/g) || []).length, 4);
  const local = section(services, '  private func dispatchGlobalLocalModelRequest(', '  /// Mirrors Android\'s profile update fan-out');
  assert.equal((local.match(/stillAuthorized\(\)/g) || []).length, 3);
  for (const name of ['GlobalRealtimePlanningScope', 'GlobalResearchExecutorPolicy', 'GlobalResearchExecutorModels',
    'GlobalAgentEvidenceLifecycle', 'AgentModelToolLoop', 'GalaxySSIStore', 'GalaxySSIStoreSessions', 'GalaxySSIDeviceIdentity'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/GlobalBackgroundCognitionScopeTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 14);
  for (const token of ['testPrimaryAndMetadataSourcesMustAllRemainEligible', 'testLegacyRunningTasksWithoutProvenanceOrTransportAreNotInferredAuthorized',
    'testARevokedContextSourceBlocksCompletionEvenWhenPrimarySourceStaysPublic', 'testUnrelatedNewConversationDoesNotInvalidateSelectedContextProvenance',
    'testOptionalProvenanceRoundTripsAndLegacyJSONRemainsReadableButUntrusted', 'testQueueClaimSkipsIneligibleHigherPriorityTaskWithoutConsumingItsAttempt',
    'testExpectedTaskUpdateRejectsAnObservedInterveningChange', 'testProjectionCapturesSelectedSourcesNotEveryKnownConversation']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['GlobalBackgroundCognitionScope', 'GlobalBackgroundCognitionScopeTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedBackgroundCognitionFile, validateBackgroundCognition};
if (require.main === module) { validateBackgroundCognition(); console.log('Background cognition live source/projection provenance, owned preparation and callback source contracts passed; no native acceptance'); }

// Source contracts only; not native execution, billing or privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), base = '387929097036560b483482e3590451190e7640db';
const read = file => require('./check-pre-shadow-routing-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const git = (...args) => cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
const old = file => git('show', `${base}:${file}`).replace(/\r\n/g, '\n');
function once(source, from, to = '') { assert.equal(source.split(from).length, 2, from); return source.replace(from, to); }
function section(source, first, last) {
  const a = source.indexOf(first), b = source.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); return source.slice(a, b);
}
const startHook = '    let routingUsageAllowed = await MainActor.run {\n' +
  '      store.profile.identityFingerprint == disclosureOwner && AgentRoutingUsageEligibility.allows(store.agentSession(id: conversationId))\n    }\n';
const invalidHook = '                routingUsageValid = routingUsageValid && value.requestId == roundRequest.requestId && AgentRoutingUsageStore.validUsage(value.usage)\n';
const commitHook = '        if routingUsageAllowed, routingUsageValid, let usage = observedUsage, !Task.isCancelled {\n' +
  '          await MainActor.run {\n' +
  '            guard !Task.isCancelled, store.profile.identityFingerprint == disclosureOwner,\n' +
  '                  AgentRoutingUsageEligibility.allows(store.agentSession(id: conversationId)) else { return }\n' +
  '            _ = AgentRoutingUsageStore(owner: disclosureOwner, defaults: store.defaults, secrets: store.secrets)\n' +
  '              .record(resourceId: contact.id, conversationId: conversationId, observationId: roundId,\n' +
  '                usage: usage, nowMillis: AgentControlPlaneClock.nowMillis())\n' +
  '          }\n        }\n';
function retained(file, source) {
  source = require('./check-pre-shadow-routing-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentRoutingUsageStore.swift') && !line.includes('AgentRoutingUsageStoreTests.swift')).join('\n');
  if (file.endsWith('AgentProviderResourceRanking.swift') && source.includes('observedUsage: AgentRoutingUsageSummary? = nil')) {
    source = once(source, ',\n    observedUsage: AgentRoutingUsageSummary? = nil');
    return once(source, section(source, '    if let observedUsage, observedUsage.samples > 0', '    let preference = preferenceBonus('));
  }
  if (file.endsWith('AgentQualityRouting.swift') && source.includes('routingUsage: AgentRoutingUsageSnapshot? = nil')) {
    return once(once(source, ',\n    routingUsage: AgentRoutingUsageSnapshot? = nil'), ', observedUsage: routingUsage?.resources[resource.targetId]');
  }
  if ((file.endsWith('AgentNetworkRoutingModels.swift') || file.endsWith('AgentRemoteTaskStatusPolicy.swift')) &&
      source.includes('routingUsage: AgentRoutingUsageSnapshot? = nil')) {
    const spaces = file.endsWith('AgentNetworkRoutingModels.swift') ? '    ' : '                                 ';
    return once(source, ',\n' + spaces + 'routingUsage: AgentRoutingUsageSnapshot? = nil').replaceAll(', routingUsage: routingUsage', '');
  }
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func automaticRoutingUsage()')) {
    source = once(source, section(source, '  private func automaticRoutingUsage()', '  private func automaticRouteSelection('));
    return source.replaceAll(', routingUsage: automaticRoutingUsage()', '');
  }
  if (file.endsWith('CloudConversationStreamEngine.swift') && source.includes(startHook)) {
    source = once(source, startHook);
    source = once(source, '        var routingUsageValid = true\n');
    return once(once(source, invalidHook), commitHook);
  }
  if (file.endsWith('CloudModelStreamProviderAdapters.swift') && source.includes('  private var usageFields:')) {
    source = once(source, section(source, '  private var usageFields:', '  func parse(data: String, eventName: String?)'), '\n');
    source = once(source, '      usageFields.removeAll()\n');
    source = once(source, 'usage: cumulativeUsage(json.object("message")?.object("usage")),',
      'usage: json.object("message")?.object("usage")?.anthropicUsage(),');
    source = once(source, 'usage: cumulativeUsage(json.object("usage")),', 'usage: json.object("usage")?.anthropicUsage(),');
    return once(source, section(source, '  func anthropicUsage() -> ModelUsage {', '  func geminiUsage() -> ModelUsage {'),
      section(old(file), '  func anthropicUsage() -> ModelUsage {', '  func geminiUsage() -> ModelUsage {'));
  }
  return source;
}
function validate() {
  const app = 'apps/ios/GalaxySSI/';
  for (const name of ['AgentProviderResourceRanking.swift', 'AgentQualityRouting.swift', 'AgentNetworkRoutingModels.swift',
    'AgentRemoteTaskStatusPolicy.swift', 'GalaxySSIServices.swift', 'CloudConversationStreamEngine.swift', 'CloudModelStreamProviderAdapters.swift']) {
    const file = app + name; assert.equal(retained(file, read(file)), old(file), name);
  }
  const store = read(app + 'AgentRoutingUsageStore.swift');
  for (const token of ['GalaxySSIEncryptedUserDefaultsStore.write(', 'GalaxySSIEncryptedUserDefaultsStore.contains(',
    'GalaxySSIEncryptedUserDefaultsStore.load(', 'private static let lock = NSRecursiveLock()',
    'eligibleConversationIds.contains($0.conversationId)', 'session.status == .active && !session.privateMode && !session.trackingPaused',
    'session.mergedIntoConversationId.isBlank', 'usage.inputTokens <= Int64.max - usage.outputTokens',
    'JSONEncoder().encode([resourceId, conversationId, observationId])', 'prior.reportedCostMicros == reportedCostMicros',
    'state.version == 1', 'state.entries.allSatisfy(\\.valid)', 'Set(state.entries.map(\\.key)).count == state.entries.count',
    'costs.isEmpty ? nil : Self.average(costs)', 'values.reduce(Int64(0)) { $0 + $1 / count }',
    'values.reduce(Int64(0)) { $0 + $1 % count }', 'maximumEntries = 1_000', '30 * 24 * 60 * 60 * 1_000',
    '$0.observedAtMillis <= nowMillis', 'nowMillis - $0.observedAtMillis <= Self.retentionMillis']) assert(store.includes(token), token);
  for (const token of ['defaults.set(', 'apiKey', 'prompt:', 'message.content', 'estimateTokens(', 'URLSession']) assert(!store.includes(token), token);
  const engine = read(app + 'CloudConversationStreamEngine.swift');
  assert(engine.includes(startHook) && engine.includes(commitHook) && engine.includes(invalidHook));
  const completionGate = engine.indexOf('        guard roundCompleted else {');
  assert(completionGate > 0 && engine.indexOf(commitHook) > completionGate);
  assert(engine.indexOf(commitHook) < engine.indexOf('        let visibleTail = inlineProtocolGuard.finishVisibleText()'));
  assert(!commitHook.includes('reportedCostMicros:'));
  const adapters = read(app + 'CloudModelStreamProviderAdapters.swift');
  for (const token of ['if let value = update[key] { usageFields[key] = value }', 'usageFields.removeAll()',
    'guard case .int(let count) = value, count >= 0', 'input.addingReportingOverflow(written)',
    'first.partialValue.addingReportingOverflow(cached)', 'guard !first.overflow, !total.overflow',
    'cachedInputTokens: cached', 'return ModelUsage(inputTokens: -1)']) assert(adapters.includes(token), token);
  const rank = read(app + 'AgentProviderResourceRanking.swift');
  const android = git('show', 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4:apps/android/app/src/main/java/com/galaxyssi/chat/AgentResourceRouter.kt');
  for (const token of ['observedUsage.averageTotalTokens / 1_000L', 'observedUsage.averageReportedCostMicros / 5_000L',
    'coerceAtMost(60L)', 'coerceAtMost(120L)']) assert(android.includes(token), token);
  for (const token of ['requirements.mode == .economy ? 2 : 1', 'observedUsage.averageTotalTokens) / 1_000, 60',
    'observedUsage.reportedCostSamples > 0, let cost', 'max(0, cost) / 5_000, 120']) assert(rank.includes(token), token);
  const services = read(app + 'GalaxySSIServices.swift');
  assert.equal((services.match(/routingUsage: automaticRoutingUsage\(\)/g) || []).length, 4);
  assert(services.includes('.filter { AgentRoutingUsageEligibility.allows($0) }.map(\\.id)'));
  assert(services.includes('owner: store.profile.identityFingerprint, defaults: store.defaults, secrets: store.secrets'));
  assert.equal((read(app + 'AgentNetworkRoutingModels.swift').match(/routingUsage: routingUsage/g) || []).length, 2);
  for (const name of ['AgentTaskBudgetModels.swift', 'AgentProviderHealth.swift', 'AgentControlPlaneActionExecutorModels.swift',
    'AgentConnectorResponseResolver.swift', 'AgentConnectorTimeoutResolver.swift', 'CloudModelClientStreaming.swift',
    'GalaxySSIEncryptedUserDefaultsStore.swift', 'AgentModelToolProtocolAnthropicAdapter.swift']) {
    const file = app + name; assert.equal(read(file), old(file), name);
  }
  const tests = read('apps/ios/GalaxySSITests/AgentRoutingUsageStoreTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 10);
  for (const token of ['Int64.max', 'reportedCostSamples, 1', 'owner: "owner-b"', 'eligibleConversationIds: []',
    'Data([0, 1, 2])', 'cachedInputTokens: 30', '9223372036854775808', 'baseline.score - ranked.score, 360']) assert(tests.includes(token), token);
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(read(project).split('\n').filter(line => /AgentRoutingUsageStore(?:Tests)?\.swift/.test(line)).length, 8);
  assert.equal(retained(project, read(project)), old(project));
  console.log('Scoped reported round usage, encryption/source filters, ranking and Anthropic usage source contracts passed; no native acceptance.');
}
if (require.main === module) validate();
module.exports = {retained, validate};

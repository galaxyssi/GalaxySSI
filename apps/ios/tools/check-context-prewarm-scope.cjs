// Source contracts only; not native dispatch/concurrency, profile ownership, OS scheduling or XCTest acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '502412a0f60fe9bad28d909f94d2a1fd8c640992';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, 'One retained-context hook: ' + from);
  return source.replace(from, to);
}
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(source.split(first).length, 2, first);
  return source.slice(start, end);
}
function retainedPrewarmServices(source) {
  if (!source.includes('  private var globalRealtimeContextIdentity = ""')) return source;
  source = once(source, section(source, '  private var globalRealtimeContextIdentity = ""', '  private lazy var localConfirmationConsentStore:'), '');
  source = once(source, '    if store.globalAgentSettings.enabled { scopedGlobalRealtimeContextProvider().prewarm() }\n', '');
  source = once(source, '        scopedGlobalRealtimeContextProvider().buildNonBlocking(', '        globalRealtimeContextProvider.buildNonBlocking(');
  source = once(source, '      turnId: outgoing.turnId,\n      realtimeProvider: scopedGlobalRealtimeContextProvider()', '      turnId: outgoing.turnId');
  return once(source, '        runId: taskId,\n        realtimeProvider: scopedGlobalRealtimeContextProvider()', '        runId: taskId');
}
function retainedPrewarmRuntime(source) {
  if (!source.includes('    realtimeProvider: GlobalRealtimeContextProvider? = nil')) return source;
  source = once(source, '    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),\n    realtimeProvider: GlobalRealtimeContextProvider? = nil', '    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()');
  source = once(source, 'let realtime = realtimeProvider?.buildNonBlocking(', 'let realtime = GlobalRealtimeContextProvider().buildNonBlocking(');
  return once(source, '      nowMillis: nowMillis,\n      allowedConversationIds: Set(sessions.filter { !$0.privateMode && !$0.trackingPaused }.map(\\.id))\n    ) ?? ""', '      nowMillis: nowMillis\n    )');
}
function retainedPrewarmProvider(source) {
  const prior = old(app + 'GlobalRealtimeContextProvider.swift');
  source = once(source, '  private var refreshToken: UUID?', '  private var refreshInProgress = false');
  source = source.replace(section(source, '  func buildNonBlocking(', '  private func render('), section(prior, '  func buildNonBlocking(', '  private func render('));
  source = once(source, '    nowMillis: Int64,\n    allowedConversationIds: Set<String>? = nil', '    nowMillis: Int64');
  source = once(source, '      items: items.filter { item in\n        allowedConversationIds.map { item.conversationIds.isSubset(of: $0) } ?? true\n      },', '      items: items,');
  return source.replace(section(source, '  private func refreshAsync(', '  private func loadSnapshot('), section(prior, '  private func refreshAsync(', '  private func loadSnapshot('));
}
function validateContextPrewarm() {
  const services = read(app + 'GalaxySSIServices.swift'), runtime = read(app + 'GalaxySSIGlobalAgentRuntime.swift'), provider = read(app + 'GlobalRealtimeContextProvider.swift');
  assert.equal(retainedPrewarmServices(services), old(app + 'GalaxySSIServices.swift'), 'Only retained scoped-provider/prewarm/call-site hooks change; startup recovery, catalog initialization, planning and task execution retained');
  assert.equal(retainedPrewarmRuntime(runtime), old(app + 'GalaxySSIGlobalAgentRuntime.swift'), 'Only optional retained realtime source and current eligible conversations change; durable/core memory/prompt/scope kernels retained');
  assert.equal(retainedPrewarmProvider(provider), old(app + 'GlobalRealtimeContextProvider.swift'), 'Only nonblocking/prewarm/invalidation/refresh and optional output scope change; sources, explicit sync build, projection, ranking, redaction and bounds retained');
  assert.equal(services.split('realtimeProvider: scopedGlobalRealtimeContextProvider()').length, 3);
  const initial = section(services, '  private func initialPlanningConversation(', '  private func initialPlannerConfigurationSha256(');
  assert(initial.includes('let globalContext = selectedProviderOnly ? "" : GalaxySSIGlobalAgentRuntimeBridge.compiledConversationContext('));
  assert(initial.includes('turnId: outgoing.turnId,\n      realtimeProvider: scopedGlobalRealtimeContextProvider()'));
  assert(services.includes('if globalRealtimeContextIdentity != identity {\n      globalRealtimeContextProvider.invalidate()'));
  assert(!runtime.includes('GlobalRealtimeContextProvider().buildNonBlocking('));
  for (const token of ['refreshQueue.async { [weak self]', 'guard refreshToken == nil', 'let token = UUID()',
    'refreshToken = token', 'let current = self.refreshToken == token', 'guard current else { return }',
    'guard refreshToken == token else { return }', 'cachedSnapshot = nil', 'refreshToken = nil',
    'nowMillis.subtractingReportingOverflow(snapshot.capturedAtMillis)', 'age.partialValue < 0',
    'allowedConversationIds.map { item.conversationIds.isSubset(of: $0) } ?? true']) assert(provider.includes(token), token);
  const warm = section(provider, '  func prewarm(', '  func invalidate(');
  assert(warm.includes('refreshAsync(nowMillis: nowMillis)') && !warm.includes('loadSnapshot'));
  for (const name of ['GalaxySSIStore', 'GalaxySSIStoreSessions', 'GlobalRealtimeContext', 'AgentModelToolLoop', 'GalaxySSIDeviceIdentity'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const android = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/MainActivity.kt'], {cwd: root, encoding: 'utf8'}));
  assert(android.includes('navigationContentExecutor.execute {\n            runCatching { globalSuperAgentRuntime.prewarmContextSnapshot() }'));
  const tests = read('apps/ios/GalaxySSITests/GlobalRealtimePrewarmTests.swift');
  for (const name of ['PrewarmReturnsBeforeSourceIOAndCoalescesConcurrentRequests', 'LastCompleteSnapshotSurvivesBackgroundRefreshAndTTLBoundary',
    'InvalidatedOldProducerCannotPublishOrClearTheNewRefreshToken', 'AllowedAndExcludedConversationSetsApplyToEveryCachedRender',
    'ClockRollbackAndOverflowRefreshWithoutTrapping', 'InvalidationDropsWarmSnapshotUntilFreshSourceCompletes',
    'InvalidatedQueuedRefreshSkipsSourceIOWithoutClearingNewWork', 'ExplicitSynchronousBuildRetainsItsOriginalContract']) assert(tests.includes('func test' + name + '('), name);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('GlobalRealtimePrewarmTests.swift in Sources */').length, 3);
}
module.exports = {retainedPrewarmServices, retainedPrewarmRuntime, validateContextPrewarm};
if (require.main === module) {
  validateContextPrewarm();
  console.log('iOS retained realtime context, utility prewarm, generation-fenced refresh and dynamic conversation scope source contracts passed; no native acceptance');
}

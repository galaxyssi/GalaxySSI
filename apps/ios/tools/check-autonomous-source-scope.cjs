// Source contracts only; no Swift compilation, native tests or runtime acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ca36efb28c5e2e72c620e20c4e88ccfe30e1549a';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => require('./check-research-context-provenance.cjs').retained(f,
  require('./check-autonomous-transport-scope.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8'))));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first); return s.slice(a, b);
}
function retained(file, s) {
  s = require('./check-autonomous-transport-scope.cjs').retained(file, s);
  if (file.endsWith('GlobalBackgroundCognitionScope.swift') && s.includes('  static func sourceConversationIds(')) {
    const first = '  func allowsSource(', last = '  func allowsRunning(';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  if (file.endsWith('GlobalRealtimeContext.swift')) {
    const run = section(s, 'struct GlobalAutonomousRun:', 'enum GlobalLongHorizonGoalStatus:');
    if (!run.includes('  var sourceConversationIds: Set<String>?')) return s;
    let prior = once(run, '  var sourceConversationIds: Set<String>?\n', '');
    prior = once(prior, ',\n    sourceConversationIds: Set<String>? = nil', '');
    prior = once(prior, '    self.sourceConversationIds = sourceConversationIds\n', '');
    return once(s, run, prior);
  }
  if (file.endsWith('GlobalAgentDeliberationStore.swift') && s.includes('eligible: (GlobalAutonomousRun)')) {
    s = once(s, '      guard lastErrorDescription.isEmpty else { return nil }\n      var runs = snapshot.autonomousRuns.map', '      var runs = snapshot.autonomousRuns.map');
    s = once(s, ',\n    eligible: (GlobalAutonomousRun) -> Bool = { _ in true }', '');
    s = once(s, 'eligible($0) ? GlobalAutonomousRunPolicy.recoverIfStale(run: $0, nowMillis: nowMillis) : $0', 'GlobalAutonomousRunPolicy.recoverIfStale(run: $0, nowMillis: nowMillis)');
    s = once(s, 'eligible(run) && (reviewReady(run, nowMillis: nowMillis) || actionReady(run, nowMillis: nowMillis))', 'reviewReady(run, nowMillis: nowMillis) || actionReady(run, nowMillis: nowMillis)');
    return once(s, '      guard lastErrorDescription.isEmpty else { return nil }\n      return GlobalAutonomousWorkClaim(', '      return GlobalAutonomousWorkClaim(');
  }
  if (file.endsWith('GalaxySSIGlobalAutonomousRuntime.swift') && s.includes('enum GlobalAutonomousSourceScope {')) {
    const first = 'enum GlobalAutonomousSourceScope {', last = '  @discardableResult\n  static func processAutonomousCycle(';
    s = once(s, section(s, first, last), section(old(file), 'enum GalaxySSIGlobalAutonomousRunPlanner {', last));
    const queueFirst = '  private static func queueResearch(', queueLast = '  private static func waitForResearchEvidence(';
    s = once(s, section(s, queueFirst, queueLast), section(old(file), queueFirst, queueLast));
    s = once(s, '    let scope = GlobalAutonomousSourceScope.liveScope(store)\n', '');
    return once(s, 'deliberationStore.claimAutonomousWork(nowMillis: nowMillis,\n      eligible: { GlobalAutonomousSourceScope.allows($0, scope: scope) })', 'deliberationStore.claimAutonomousWork(nowMillis: nowMillis)');
  }
  if (file.endsWith('GalaxySSIGlobalAutonomousModelRuntime.swift') && s.includes('    let scope = GlobalAutonomousSourceScope.liveScope(appStore)')) {
    s = once(s, '    let owned = store.autonomousRuns().filter { GlobalAutonomousSourceScope.matches(response, run: $0) }\n    guard store.lastErrorDescription.isEmpty, owned.count == 1 else { return false }\n', '');
    s = once(s, 'if let reviewRun = owned.first(where:', 'if let reviewRun = store.autonomousRuns().first(where:');
    s = once(s, 'guard let run = owned.first(where:', 'guard let run = store.autonomousRuns().first(where:');
    s = once(s, '    appStore: GalaxySSIStore,\n    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()', '    settings: GlobalAgentSettings = .default,\n    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()');
    s = once(s, '    let settings = appStore.globalAgentSettings\n    let scope = GlobalAutonomousSourceScope.liveScope(appStore)\n    guard scope.canRead, response.sourceMessageId > 0 else { return false }\n', '');
    s = once(s, '      guard store.lastErrorDescription.isEmpty, GlobalAutonomousSourceScope.allows(reviewRun, scope: scope),\n            GlobalAutonomousSourceScope.matches(response, run: reviewRun),\n            GlobalAutonomousSourceScope.resourceAuthorized(response.contactId, store: appStore) else { return false }\n', '');
    return once(s, '    guard store.lastErrorDescription.isEmpty, GlobalAutonomousSourceScope.allows(run, scope: scope),\n          GlobalAutonomousSourceScope.matches(response, run: run),\n          GlobalAutonomousSourceScope.resourceAuthorized(response.contactId, store: appStore) else { return false }\n\n', '');
  }
  if (file.endsWith('GalaxySSIGlobalAutonomousResearchRuntime.swift') && s.includes('    appStore: GalaxySSIStore,')) {
    const first = '  static func consumeAutonomousResearchResponse(', last = '    let evidence = GlobalActionEvidence(';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  if (file.endsWith('GalaxySSIServices.swift') && s.includes('permitsAutonomousRequest(store:')) {
    const first = '  func runGlobalAutonomousCycle(', last = '  @discardableResult\n  func runGlobalResearchCycle(';
    s = once(s, section(s, first, last), section(old(file), first, last));
    for (const name of ['consumeAutonomousResearchResponse', 'consumeAutonomousResponse']) {
      s = once(s, name + '(\n          response,\n          appStore: self.store', name + '(\n          response,\n          settings: self.store.globalAgentSettings');
    }
    return once(s, 'consumeAutonomousResearchResponse(\n          failure,\n          appStore: store,', 'consumeAutonomousResearchResponse(\n          failure,\n          settings: store.globalAgentSettings,');
  }
  return s;
}
function validate() {
  for (const name of ['GlobalBackgroundCognitionScope', 'GlobalRealtimeContext', 'GlobalAgentDeliberationStore',
    'GalaxySSIGlobalAutonomousRuntime', 'GalaxySSIGlobalAutonomousModelRuntime', 'GalaxySSIGlobalAutonomousResearchRuntime', 'GalaxySSIServices']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), old(file), name + ': unchanged outside declared autonomous hooks');
  }
  const runtime = read(app + 'GalaxySSIGlobalAutonomousRuntime.swift');
  for (const token of ['let contextIds = task.contextConversationIds', 'sources.union(contextIds)',
    'existing.sourceConversationIds == sources', 'sourceConversationIds: sources',
    'sources.isSubset(of: scope.allowedConversationIds)', 'eligible: { GlobalAutonomousSourceScope.allows($0, scope: scope) }',
    'response.sourceMessageId > 0', 'actions.count == 1', 'resourceAuthorized(_ id:', 'contact.trustState == .verified']) assert(runtime.includes(token), token);
  const claim = section(read(app + 'GlobalAgentDeliberationStore.swift'), '  func claimAutonomousWork(', '  func exportCognitionTasks(');
  assert(claim.includes('eligible($0) ? GlobalAutonomousRunPolicy.recoverIfStale'));
  assert(claim.includes('eligible(run) && (reviewReady'));
  assert(claim.includes('persist(snapshot)\n      guard lastErrorDescription.isEmpty else { return nil }'));
  const queue = section(runtime, '  private static func queueResearch(', '  private static func waitForResearchEvidence(');
  for (const token of ['guard let sources = run.sourceConversationIds', 'existing.sourceConversationIds == sources',
    'sourceConversationIds: sources', 'researchStore.lastErrorDescription.isEmpty ? task : nil']) assert(queue.includes(token), token);
  const consumer = section(read(app + 'GalaxySSIGlobalAutonomousModelRuntime.swift'), '  static func consumeAutonomousResponse(', '  private static func consumePlanReview(');
  assert(consumer.includes('owned.count == 1'));
  assert(consumer.indexOf('GlobalAutonomousSourceScope.matches(response, run: run)') < consumer.indexOf('GalaxySSIGlobalAutonomousBudgetRuntime.complete('));
  assert(consumer.indexOf('GlobalAutonomousSourceScope.matches(response, run: reviewRun)') < consumer.indexOf('return consumePlanReview('));
  const research = read(app + 'GalaxySSIGlobalAutonomousResearchRuntime.swift');
  for (const token of ['GlobalAutonomousSourceScope.allows(run, scope: scope)', 'action.status == .running, action.resourceId == task.id',
    'GlobalResearchSourceScope.allows(task, scope: scope)', 'runSources.isSubset(of: researchSources)',
    'let result = task.result.ifBlank(task.lastError)', 'guard !result.isBlank']) assert(research.includes(token), token);
  assert(!research.includes('.ifBlank(response.content)'));
  const services = read(app + 'GalaxySSIServices.swift');
  const dispatch = section(services, '  private func dispatchGlobalAutonomousRequest(', '  @discardableResult\n  func runGlobalResearchCycle(');
  assert.equal(dispatch.split('permitsAutonomousRequest(store: store, request: request)').length, 4);
  assert(dispatch.includes('stillAuthorized: { GalaxySSIGlobalAgentRuntimeBridge.permitsAutonomousRequest(store: self.store, request: request) }'));
  const testFile = 'apps/ios/GalaxySSITests/GlobalAgentDeliberationStoreTests.swift';
  assert.equal((read(testFile).match(/  func test/g) || []).length - (old(testFile).match(/  func test/g) || []).length, 9);
  console.log('Autonomous source inheritance, eligible claims, callback/consumer source contracts passed; no native acceptance');
}
if (require.main === module) validate();
module.exports = {retained, validate};

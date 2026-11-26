// Source-only foreground context contracts; not native privacy, model or concurrency acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '5f6297c3cf8348fa777e5c80cdee5f46cf7c10a1';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => require('./check-background-cognition-scope.cjs').retainedBackgroundCognitionFile(f,
  require('./check-research-source-scope.cjs').retained(f,
    require('./check-autonomous-source-scope.cjs').retained(f,
      require('./check-research-context-provenance.cjs').retained(f, clean(fs.readFileSync(path.join(root, f), 'utf8'))))));
const old = f => clean(cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first);
  assert.equal(s.split(first).length, 2, first);
  return s.slice(a, b);
}
function retainedLivePlanningServices(s) {
  if (!s.includes('    let suppressGlobalContext = GlobalRealtimePlanningScope.suppressesGlobalContext(')) return s;
  const prior = old(app + 'GalaxySSIServices.swift');
  const first = '    let suppressGlobalContext = GlobalRealtimePlanningScope.suppressesGlobalContext(';
  const last = '    let hasAttachments = hasAttachmentsOverride ?? !attachments.isEmpty';
  const oldStart = '    if selectedForPhoneTurn {\n      conversation.globalContext = ""';
  s = once(s, section(s, first, last), section(prior, oldStart, last));
  return once(s, section(s, '      globalRealtimeContext: GlobalRealtimePlanningScope(', '      hasAttachments: hasAttachments,'),
    section(prior, '      globalRealtimeContext: selectedForPhoneTurn ? "" : conversationOverride?.globalContext ??', '      hasAttachments: hasAttachments,'));
}
function retainedLivePlanningRuntime(s) {
  if (!s.includes('    let scope = GlobalRealtimePlanningScope(enabled: true, conversations: sessions)')) return s;
  return once(s, section(s, '    let scope = GlobalRealtimePlanningScope(enabled: true, conversations: sessions)', '    return String([core, durable, realtime]'),
    section(old(app + 'GalaxySSIGlobalAgentRuntime.swift'), '    let excluded = Set(sessions.filter', '    return String([core, durable, realtime]'));
}
function retainedLivePlanningProvider(s) {
  if (!s.includes('    let allowedGoals = allowedConversationIds.map')) return s;
  s = once(s, '    let allowedGoals = allowedConversationIds.map { allowed in\n      snapshot.longHorizonGoals.filter { $0.sourceConversationIds.isSubset(of: allowed) }\n    } ?? snapshot.longHorizonGoals\n', '');
  return once(s, '      longHorizonGoals: allowedGoals,', '      longHorizonGoals: snapshot.longHorizonGoals,');
}
function retainedLivePlanningFile(file, s) {
  if (file.endsWith('GalaxySSIServices.swift')) return retainedLivePlanningServices(s);
  if (file.endsWith('GalaxySSIGlobalAgentRuntime.swift')) return retainedLivePlanningRuntime(s);
  if (file.endsWith('GlobalRealtimeContextProvider.swift')) return retainedLivePlanningProvider(s);
  return s;
}
function validateLivePlanningContext() {
  const services = read(app + 'GalaxySSIServices.swift'), runtime = read(app + 'GalaxySSIGlobalAgentRuntime.swift'), provider = read(app + 'GlobalRealtimeContextProvider.swift');
  for (const name of ['GalaxySSIServices', 'GalaxySSIGlobalAgentRuntime', 'GlobalRealtimeContextProvider'])
    assert.equal(retainedLivePlanningFile(name + '.swift', read(app + name + '.swift')), old(app + name + '.swift'),
      name + ' complete file unchanged outside live foreground context hooks');
  const scope = read(app + 'GlobalRealtimePlanningScope.swift');
  for (const token of ['canRead = enabled && !suppressed', 'conversations: @autoclosure () -> [AgentConversation]',
    'provider: @autoclosure () -> GlobalRealtimeContextProvider', 'guard canRead else { return "" }',
    '!$0.privateMode && !$0.trackingPaused', '$0.privateMode || $0.trackingPaused',
    'allowedConversationIds: allowedConversationIds', 'excludedConversationIds: excludedConversationIds',
    'overrideGlobalContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true']) assert(scope.includes(token), token);
  assert(scope.indexOf('guard canRead else {') < scope.indexOf('let sessions = conversations()'));
  assert(scope.indexOf('guard canRead else { return "" }') < scope.indexOf('return provider().buildNonBlocking'));
  assert(provider.indexOf('let allowedGoals =') < provider.indexOf('let items = GlobalRealtimeContextPolicy.project('));
  assert(provider.includes('$0.sourceConversationIds.isSubset(of: allowed)'));
  const refresh = section(services, '    let suppressGlobalContext = GlobalRealtimePlanningScope.suppressesGlobalContext(', '    let hasAttachments = hasAttachmentsOverride');
  assert(refresh.includes('if suppressGlobalContext {\n      conversation.globalContext = ""\n    } else if conversationOverride != nil {'));
  assert(refresh.includes('conversation.globalContext = GalaxySSIGlobalAgentRuntimeBridge.compiledConversationContext('));
  assert(!services.includes('globalRealtimeContext: selectedForPhoneTurn ? "" : conversationOverride?.globalContext ??'));
  assert(services.includes('GlobalRealtimePlanningScope(enabled: store.globalAgentSettings.enabled,\n        suppressed: suppressGlobalContext,'));
  assert(runtime.indexOf('guard store.globalAgentSettings.enabled else {') < runtime.indexOf('let scope = GlobalRealtimePlanningScope('));
  assert(runtime.includes('return String(core.prefix(maximumCharacters))'));
  for (const name of ['GalaxySSIStore', 'GalaxySSIStoreSessions', 'GlobalRealtimeContext', 'AgentConversationModels',
    'AgentModelPlanningPrompt', 'AgentModelToolLoop', 'GalaxySSIDeviceIdentity', 'AgentSequentialPlanNodeDispatch'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/GlobalRealtimePlanningScopeTests.swift');
  for (const name of ['DisabledScopeDoesNotLoadConversationsOrAccessProvider', 'ExplicitSuppressionDoesNotLoadConversationsOrAccessProvider',
    'BlankOverridesAndSelectedProviderRemainExplicitlySuppressed', 'OneCurrentConversationSnapshotDefinesAllowedAndExcludedIds',
    'CachedProjectionRechecksPrivatePausedAndRemovedConversationsWithoutRefresh', 'MixedConversationItemsRequireEveryScopeAndGlobalItemsStayEligible',
    'DisabledWarmCacheDoesNotScheduleAnotherSourceReadAndCanBeReenabled', 'MixedGoalCannotLoseItsPrivateSourceBeforeAllowlistValidation',
    'CallerCharacterLimitIsForwardedToCachedFormatter']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['GlobalRealtimePlanningScope', 'GlobalRealtimePlanningScopeTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedLivePlanningServices, retainedLivePlanningRuntime, retainedLivePlanningProvider, retainedLivePlanningFile, validateLivePlanningContext};
if (require.main === module) { validateLivePlanningContext(); console.log('Live foreground planning scope, override rebuild and preprojection source-set contracts passed; no native acceptance'); }

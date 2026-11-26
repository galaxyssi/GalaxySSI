// Source contracts only; not native context/database/OSLog execution or a latency benchmark.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '3f7935863e151e18780f4fbaf9a5792782c4e161';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, 'One context-timing hook: ' + from);
  return source.replace(from, to);
}
function retainedPlanningServices(source) {
  if (!source.includes('let started = AgentPlanningContextTiming.monotonicMillis()')) return source;
  for (const label of ['started', 'metadataRead', 'historyRead', 'globalRead'])
    source = once(source, '    let ' + label + ' = AgentPlanningContextTiming.monotonicMillis()\n', '');
  source = once(source, '    AgentPlanningContextTiming.log(.sample(turnId: outgoing.turnId.ifBlank(outgoing.id.uuidString),\n      started: started, metadataRead: metadataRead, historyRead: historyRead, globalRead: globalRead,\n      finished: AgentPlanningContextTiming.monotonicMillis()))\n    return context\n', '');
  source = once(source, '    let summary = recentLocalConversationContext(\n      contactId: outgoing.contactId,\n      excluding: outgoing.id,\n      conversationId: outgoing.conversationId\n    )\n', '');
  source = once(source, '    let globalContext = selectedProviderOnly ? "" : GalaxySSIGlobalAgentRuntimeBridge.compiledConversationContext(\n      store: store,\n      query: requestText,\n      conversationId: outgoing.conversationId,\n      turnId: outgoing.turnId\n    )\n', '');
  source = once(source, '    let context = AgentConversationContext(\n      conversationId: outgoing.conversationId,\n      summary: summary,',
    '    return AgentConversationContext(\n      conversationId: outgoing.conversationId,\n      summary: recentLocalConversationContext(\n        contactId: outgoing.contactId,\n        excluding: outgoing.id,\n        conversationId: outgoing.conversationId\n      ),');
  return once(source, '      globalContext: globalContext,\n      trackingPaused: session?.trackingPaused ?? false',
    '      globalContext: selectedProviderOnly ? "" : GalaxySSIGlobalAgentRuntimeBridge.compiledConversationContext(\n        store: store,\n        query: requestText,\n        conversationId: outgoing.conversationId,\n        turnId: outgoing.turnId\n      ),\n      trackingPaused: session?.trackingPaused ?? false');
}
function validatePlanningContextTiming() {
  const services = read(app + 'GalaxySSIServices.swift');
  assert.equal(retainedPlanningServices(services), show(base, app + 'GalaxySSIServices.swift'),
    'Only timing and exact once-only local values change; original session/history/global expressions, private defaults, query scope and all other services retained');
  const helper = read(app + 'AgentPlanningContextTiming.swift');
  for (const token of ['DispatchTime.now().uptimeNanoseconds / 1_000_000', 'Int64(clamping:', 'started >= 0',
    'metadataRead >= started', 'historyRead >= metadataRead', 'globalRead >= historyRead', 'finished >= globalRead',
    'metadataMillis: valid ? metadataRead - started : 0', 'historyMillis: valid ? historyRead - metadataRead : 0',
    'globalMillis: valid ? globalRead - historyRead : 0', 'assemblyMillis: valid ? finished - globalRead : 0',
    'totalMillis: valid ? finished - started : 0', 'SHA256.hash(data: Data(turnId.utf8)).prefix(12)',
    'privacy: .private(mask: .hash)', 'category: "planning-context-latency"', 'context_loaded', 'read_ms=']) assert(helper.includes(token), token);
  const fields = helper.slice(helper.indexOf('  struct Sample:'), helper.indexOf('  private static let logger'));
  for (const token of ['turnId', 'conversation', 'request', 'body', 'prompt', 'query', 'message', 'url', 'key']) assert(!fields.includes(token), token);
  assert(!/Date\(|URLSession|UserDefaults|FileManager|Task\.detached|DispatchQueue/.test(helper));
  for (const name of ['GalaxySSIStore', 'GalaxySSIStoreSessions', 'GalaxySSIGlobalAgentRuntime',
    'AgentConversationModels', 'LanguagePolicySettings', 'AgentModelToolLoop', 'CloudModelToolLoopAgentPlanningProvider', 'GalaxySSIDeviceIdentity'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  assert(read(app + 'GalaxySSIStore.swift').includes('@Published private(set) var profile: GalaxySSIProfile {'));
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivityAgentPage.kt');
  assert(reference.includes('val contextReadStartedAt = SystemClock.elapsedRealtime()'));
  assert(reference.includes('read_ms=${SystemClock.elapsedRealtime() - contextReadStartedAt}'));
  const androidStore = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/AppStore.kt');
  assert(androidStore.includes('internal fun localDeviceRouteId(context: Context): String'));
  assert(androidStore.includes('if (GalaxySSILinkProtocol.validRouteId(routeId)) return routeId'));
  const tests = read('apps/ios/GalaxySSITests/AgentPlanningContextTimingTests.swift');
  for (const name of ['SeparatesReadAndAssemblyPhases', 'InvalidClockDoesNotInventPhaseDurations',
    'EqualBoundariesAndMaximumElapsedAreRepresentable', 'CorrelationIsBoundedAndContainsNoRawIdentifier']) assert(tests.includes('func testPlanningContextTiming' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentPlanningContextTiming', 'AgentPlanningContextTimingTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedPlanningServices, validatePlanningContextTiming};
if (require.main === module) {
  validatePlanningContextTiming();
  console.log('iOS actual planning context-read phase timing and unchanged scoped/context expressions source contracts passed; no native or latency acceptance');
}

// Source contracts only; no Swift, MQTT, native storage or privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'cfa3cdc37e4b30dcf5541d2b71451a8294be2a11';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function retainedServices(s) {
  if (!s.includes('    learningScope: AgentLearningOutboxScope? = nil')) return s;
  const file = app + 'GalaxySSIServices.swift';
  for (const [first, last] of [
    ['  private func dispatchGlobalAutonomousRequest(', '  @discardableResult\n  func runGlobalResearchCycle('],
    ['  private func dispatchGlobalResearchRequest(', '  func publicAttentionLink('],
    ['  private func dispatchGlobalCognitionRequest(', '  private func dispatchGlobalLocalModelRequest('],
    ['  func enqueueLinkPayload(', '  func makeJournalBackedMqttRuntime(']
  ]) {
    const current = section(s, first, last);
    assert.equal(current, section(show(approved, file), first, last), 'Only exact approved outbox producer hooks normalize');
    s = once(s, current, section(show(base, file), first, last));
  }
  return s;
}
function retained(file, s) {
  if (file.endsWith('/GalaxySSIServices.swift')) return retainedServices(s);
  if (file.endsWith('/GalaxySSIServices+Outbox.swift') && s.includes('struct AgentLearningOutboxScope:')) {
    const added = section(s, 'struct AgentLearningOutboxScope:', 'struct LinkOutboxReceiptWindow {');
    assert.equal(added, section(show(approved, file), 'struct AgentLearningOutboxScope:', 'struct LinkOutboxReceiptWindow {'));
    s = once(s, added);
    s = once(s, '      if let scope = item.learningScope,\n' +
      '         !scope.permits(item, store: store, now: GlobalRealtimeClock.nowMillis()) {\n' +
      '        deliveryStore.discard(messageId: item.messageId)\n        continue\n      }\n');
    return once(s, '        guard expiry > GlobalRealtimeClock.nowMillis(), item.learningScope != nil else {',
      '        guard expiry > GlobalRealtimeClock.nowMillis() else {');
  }
  if (file.endsWith('/GalaxySSILinkReliability.swift') && s.includes('AgentLearningOutboxScope')) {
    for (const [from, to] of [
      ['  var learningScope: AgentLearningOutboxScope?\n', ''],
      ['    fileReadScope: String? = nil,\n    learningScope: AgentLearningOutboxScope? = nil', '    fileReadScope: String? = nil'],
      ['    self.learningScope = learningScope\n', ''],
      ['    case learningScope = "learning_scope"\n', ''],
      ['    learningScope = try container.decodeIfPresent(AgentLearningOutboxScope.self, forKey: .learningScope)\n', ''],
      ['  var learningScope: AgentLearningOutboxScope? = nil\n', ''],
      ['    learningScope: AgentLearningOutboxScope? = nil,\n', ''],
      ['          backgroundLearning: backgroundLearning,\n          learningScope: learningScope', '          backgroundLearning: backgroundLearning'],
      ['          attachmentDeclaration: request.attachmentDeclaration,\n          learningScope: request.learningScope', '          attachmentDeclaration: request.attachmentDeclaration']
    ]) s = once(s, from, to);
  }
  if (file.endsWith('/GalaxySSILinkReliabilityTests.swift') && s.includes('  func testLearningScopeBindsTheOpaqueQueueIdentityWithoutSavingPromptText()')) {
    const block = section(s, '  func testLearningScopeBindsTheOpaqueQueueIdentityWithoutSavingPromptText()',
      '  func testCutoverRequiresReadableAndEmptyLegacyReceiptJournal()');
    assert.equal(block, section(show(approved, file), '  func testLearningScopeBindsTheOpaqueQueueIdentityWithoutSavingPromptText()',
      '  func testCutoverRequiresReadableAndEmptyLegacyReceiptJournal()'));
    return once(s, block);
  }
  return s;
}
module.exports = {retainedServices, retained};
function optional(name) {
  const file = path.join(__dirname, name + '.cjs');
  return fs.existsSync(file) ? require(file) : null;
}
if (require.main === module) {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'GalaxySSIServices+Outbox.swift',
    app + 'GalaxySSILinkReliability.swift', 'apps/ios/GalaxySSITests/GalaxySSILinkReliabilityTests.swift']) {
    let source = retained(file, read(file));
    if (file.endsWith('/GalaxySSIServices.swift')) {
      const unplanned = optional('check-unplanned-native-dispatch');
      if (unplanned) source = unplanned.retainedUnplannedDispatchServices(source);
      const browser = optional('check-browser-view-ownership');
      if (browser) source = browser.retainedBrowserServices(source);
      const pairingFile = path.join(__dirname, 'check-pairing-history.cjs');
      if (fs.existsSync(pairingFile) && fs.readFileSync(pairingFile, 'utf8').includes('function retainedPairingStore('))
        source = require(pairingFile).retainedPairingServices(source);
    }
    assert.equal(source, show(base, file), file + ': all code outside declared hooks retained');
  }
  const file = app + 'GalaxySSIServices+Outbox.swift', outbox = read(file);
  const metadata = section(outbox, 'struct AgentLearningOutboxScope:', '  private var valid: Bool');
  assert(!/let (prompt|systemPrompt|content|text)\b/.test(metadata), 'No prompt copied into persisted scope');
  for (const token of ['UUID(uuidString: messageID)', 'item.messageId == messageID', 'self.profile == profile',
    'item.topic == topic', 'item.clientSourceMessageId == String(source)', 'item.contactId == resource',
    'scope.accepts(current, request: request)', 'GlobalAutonomousSourceScope.allows(run, scope: scope)',
    'GlobalResearchSourceScope.allowsContext(request, scope: scope)', 'current.status == .running',
    'request.leaseId == leaseID', 'request.stage == stage', 'current.researchPlan.synthesisLeaseExpiresAtMillis > now',
    'permitsCognitionRequest(store: store, request: request, requireAvailable: false)',
    'permitsAutonomousRequest(store: store, request: request)', 'permitsResearchRequest(store: store, request: request)']) assert(outbox.includes(token), token);
  assert(outbox.indexOf('scope.permits(item, store: store') < outbox.indexOf('deliveryStore.markAttempt(messageId: item.messageId'));
  assert(outbox.indexOf('scope.permits(item, store: store') < outbox.indexOf('await mqttClient.publishDurable('));
  assert(outbox.indexOf('let scope = item.learningScope') < outbox.indexOf('PublicNewsPairedHeadlineBatch.outboxPrefix'),
    'A scoped message cannot bypass its binding by acquiring a public/ordinary classification');
  assert.throws(() => retained(file, outbox.replace('scope.accepts(current, request: request)', 'true')), assert.AssertionError);
  const changed = outbox.replace('import Foundation', 'import Foundation\n// unrelated synthetic mutation');
  assert.notEqual(retained(file, changed), show(base, file));
  const tests = 'apps/ios/GalaxySSITests/GalaxySSILinkReliabilityTests.swift';
  assert.equal((read(tests).match(/  func test/g) || []).length - (show(base, tests).match(/  func test/g) || []).length, 9);
  assert(!/\p{Script=Han}/u.test(read(tests)));
  const transport = optional('check-autonomous-transport-scope');
  for (const name of ['AgentIOSBackgroundCognition', 'GlobalBackgroundCognitionScope', 'GlobalResearchExecutorModels',
    'GalaxySSIGlobalAgentRuntime', 'GalaxySSIGlobalAutonomousRuntime', 'GlobalRealtimeContext', 'GlobalAgentDeliberationStore']) {
    const file = app + name + '.swift', source = read(file);
    assert.equal(transport ? transport.retained(file, source) : source, show(base, file), name + ' retained');
  }
  console.log('Owner-bound learning queue codec, producer binding and live pre-publish authorization source contracts passed; nine XCTest methods authored, not executed.');
}

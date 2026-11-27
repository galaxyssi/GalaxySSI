// Source contracts only; no Swift, CryptoKit, UserDefaults or XCTest acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'a72b0985904205a718c5bce4cd360d9ceb8233c6';
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
function restore(s, file, first, last) {
  const current = section(s, first, last);
  assert.equal(current, section(show(approved, file), first, last), 'Only exact approved governance sections normalize');
  return s.replace(current, section(show(base, file), first, last));
}
function retained(file, s) {
  if (file.endsWith('/AgentCognitiveGovernance.swift') && s.includes('"governance_read_failed"')) {
    s = restore(s, file, 'final class AgentCognitiveGovernanceStore {', 'enum AgentKnowledgeGapDetector {');
    const guard = '    guard store.lastErrorDescription.isEmpty else { return nil }\n';
    assert.equal(s.split(guard).length, 2); return s.replace(guard, '');
  }
  if (file.endsWith('/AgentCognitiveGovernanceRuntime.swift') && s.includes('  private func observeLocked(_ observed:'))
    return restore(s, file, '  private func observeLocked(', '  private func locked<T>');
  if (file.endsWith('/AgentEvalOpsTests.swift') && s.includes('  func testGovernanceMissingStateIsDistinctFromCorruptCiphertext()')) {
    const block = section(s, '  func testGovernanceMissingStateIsDistinctFromCorruptCiphertext()', '  func testKnowledgeGapSourceProofRoundtripAndLegacyDecode()');
    assert.equal(block, section(show(approved, file), '  func testGovernanceMissingStateIsDistinctFromCorruptCiphertext()', '  func testKnowledgeGapSourceProofRoundtripAndLegacyDecode()'));
    s = s.replace(block, '');
    const first = '\nprivate final class GovernanceCheckedSecrets:';
    const helper = s.slice(s.indexOf(first));
    const pinned = show(approved, file);
    assert.equal(s.split(first).length, 2); assert.equal(helper, pinned.slice(pinned.indexOf(first)));
    return s.slice(0, s.indexOf(first));
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const files = [app + 'AgentCognitiveGovernance.swift', app + 'AgentCognitiveGovernanceRuntime.swift',
    'apps/ios/GalaxySSITests/AgentEvalOpsTests.swift'];
  for (const file of files) {
    assert.equal(retained(file, read(file)), show(base, file), file + ': all other source retained');
    assert.equal(retained(file, show(base, file)), show(base, file), 'Unchanged main is a no-op');
  }
  const store = read(files[0]);
  for (const token of ['private func load() -> State?', 'GalaxySSIEncryptedUserDefaultsStore.contains',
    'guard defaults.object(forKey: key) == nil', 'governance_read_failed', 'governance_encode_failed', 'governance_write_failed',
    'guard var state = load() else { return nil }', 'return save(state) ? normalized : nil', 'return save(state) ? current : nil',
    'return save(state) ? gap : nil', 'func gap(id: String)', 'guard store.lastErrorDescription.isEmpty else { return nil }']) assert(store.includes(token), token);
  const bridge = read(files[1]);
  for (const token of ['let gap = governance.gap(id: observed.id)', 'existing.count == 1', 'task.sourceConversationIds == sources',
    'task.question == String(gap.unknownQuestions.joined', 'recordQueuedResearch(gap)',
    'guard governance.updateGapStatus(id: gap.id, status: .researching) != nil',
    'id: "knowledge-gap-research:', 'decisions.contains(where:']) assert(bridge.includes(token), token);
  assert(bridge.indexOf('governance.gap(id: observed.id)') < bridge.indexOf('var state = researchStore.state()'));
  const bookkeeping = section(bridge, '  private func recordQueuedResearch(', '  private func locked<T>');
  assert(bookkeeping.indexOf('guard governance.updateGapStatus') < bookkeeping.indexOf('governance.appendDecision('));
  assert(!bookkeeping.includes('researchStore.save('), 'Repair never creates or dispatches another task');
  for (const [file, from, to] of [
    [files[0], 'return save(state) ? normalized : nil', 'return normalized'],
    [files[0], 'guard var state = load() else { return nil }', 'var state = load() ?? State()'],
    [files[1], 'task.sourceConversationIds == sources', 'true']
  ]) assert.throws(() => retained(file, read(file).replace(from, to)), assert.AssertionError);
  for (const name of ['GalaxySSIEncryptedUserDefaultsStore', 'AgentEvalOpsStore', 'GlobalResearchExecutorModels',
    'GlobalResearchExecutorPolicy', 'GalaxySSIGlobalAgentRuntime'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  assert.equal((read(files[2]).match(/  func test/g) || []).length - (show(base, files[2]).match(/  func test/g) || []).length, 10);
  assert(!/\p{Script=Han}/u.test(read(files[2])));
  console.log('Checked governance reads/writes and owned research-bookkeeping reconciliation source contracts passed; ten XCTest methods authored, not executed.');
}

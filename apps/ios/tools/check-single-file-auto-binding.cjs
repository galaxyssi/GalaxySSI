// Source contracts only; does not execute Swift, providers, storage or transport.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '214feeeba';
const serviceFile = app + 'GalaxySSIServices.swift', first = '  func readAgentFile(', last = '  func resumeAgentFile(';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})));
  return memo.get(key);
}
function section(source, start = first, end = last) {
  assert.equal(source.split(start).length, 2, 'Unique production entry: ' + start);
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(b > a, end); return source.slice(a, b);
}
function validateSource(source) {
  const owned = section(source);
  assert.equal(owned, section(show(approved, serviceFile)), 'Exact reviewed isolated file dispatch');
  assert.equal(owned.split('automaticRouteSelection(').length - 1, 1);
  assert.equal(owned.split('automaticTargetId: automaticTargetId').length - 1, 3);
  const begin = owned.indexOf('store.beginAgentAutoRouteTurn(for: outgoing'), choice = owned.indexOf('let automaticTargetId =');
  assert(begin >= 0 && begin < choice);
  for (const [binding, dispatch] of [
    ['"local-llm"', 'raw = try await AgentSingleFileRead.local('],
    ['cloud.id', 'raw = try await AgentSingleFileRead.cloud('],
    ['agent.id', 'raw = try await readSingleFileOnDesktop(']
  ]) {
    const record = owned.indexOf('try recordAutomaticDispatch(targetId: ' + binding + ', outgoing: outgoing)');
    assert(record > choice && record < owned.indexOf(dispatch), 'Commit binding before provider entry');
  }
  assert(owned.includes('goal: goal)?.target.id ?? ""'), 'No-route must be explicit, not recomputed');
  assert(owned.includes('== readSelection else { return false }'), 'Selection changes invalidate callbacks');
  for (const token of ['blocks: [block], matchExactIDs: true', 'attachments: [file]', 'permitScopedRead: true'])
    assert(owned.includes(token), token);
  for (const token of ['await send(', 'original.content', 'recentLocalConversationContext(']) assert(!owned.includes(token), token);
  return owned;
}
function retainedServices(source) {
  const current = section(source), original = section(show(base, serviceFile));
  if (current === original) return source;
  validateSource(source);
  return source.replace(current, original);
}
function retained(file, source) { return file === serviceFile ? retainedServices(source) : source; }
module.exports = {retained, retainedServices, validateSource};
if (require.main === module) {
  const source = read(serviceFile); validateSource(source);
  let restored = retainedServices(source);
  const baseline = path.join(__dirname, 'observation-scope-baseline.cjs');
  if (fs.existsSync(baseline)) restored = require(baseline).normalizePending(serviceFile, restored);
  assert.equal(restored, show(base, serviceFile), 'Other coordinator paths are outside this increment');
  for (const file of ['AgentSingleFileRead.swift', 'AgentSingleFileDesktopIntent.swift', 'AgentFileReceipt.swift',
    'CloudModelRequestRoutingPolicy.swift']) assert.equal(read(app + file), show(base, app + file), file);
  const mutations = [
    ['readSelection.mode == .automatic', 'readSelection.mode == .manual'],
    ['guard store.beginAgentAutoRouteTurn', 'if store.beginAgentAutoRouteTurn'],
    ['throw AgentModelLoopRecoveryError(code: "auto_route_turn_not_committed")', 'return true'],
    ['goal: goal)?.target.id ?? ""', 'goal: goal)?.target.id'],
    ['automaticTargetId: automaticTargetId', 'automaticTargetId: nil'],
    ['try recordAutomaticDispatch(targetId: "local-llm", outgoing: outgoing)', ''],
    ['try recordAutomaticDispatch(targetId: cloud.id, outgoing: outgoing)', ''],
    ['try recordAutomaticDispatch(targetId: agent.id, outgoing: outgoing)', ''],
    ['== readSelection else { return false }', '!= readSelection else { return false }'],
    ['blocks: [block], matchExactIDs: true', 'blocks: [block], matchExactIDs: false'],
    ['attachments: [file]', 'attachments: []'],
    ['permitScopedRead: true', 'permitScopedRead: false']
  ];
  const owned = section(source);
  for (const [from, to] of mutations) {
    assert(owned.includes(from), from);
    const changed = source.replace(owned, owned.replace(from, to));
    assert.throws(() => validateSource(changed), undefined, from);
    assert.throws(() => retainedServices(changed), undefined, 'Composition must reject ' + from);
  }
  assert.throws(() => validateSource(source.replace(first, first + '\n' + first)));
  console.log('Single-file Auto source contracts passed; 13 negative source mutations rejected. No Swift execution.');
}

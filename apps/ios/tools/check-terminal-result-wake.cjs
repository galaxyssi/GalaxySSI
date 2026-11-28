// Source contracts only; no Swift, native timers, transport or storage is executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'a0f0b80ccbcf6c57c69d48a89c90867a0cf926bf';
const serviceFile = app + 'GalaxySSIServices.swift', marker = '  private func nativeConnectorRecoveryWake(';
const clean = source => source.replace(/\r\n/g, '\n'), read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function retainedServices(source) {
  if (!source.includes(marker)) return source;
  const patch = git(['diff', '--no-ext-diff', '--no-color', '--unified=0', base, approved, '--', serviceFile]);
  let previous = [], current = [], active = false;
  const hunks = new Map();
  function flush() {
    if (!active) return;
    const from = '\n' + current.join('\n') + '\n';
    const to = '\n' + (previous.length ? previous.join('\n') + '\n' : '');
    const existing = hunks.get(from);
    if (existing) { assert.equal(existing.to, to); existing.count++; }
    else hunks.set(from, {to, count: 1});
    previous = []; current = [];
  }
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith('-')) previous.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected diff format');
  }
  flush(); assert(active);
  for (const [from, {to, count}] of hunks) {
    assert.equal(source.split(from).length - 1, count, 'Exact terminal wake hunk count: ' + from.slice(0, 140));
    source = source.split(from).join(to);
  }
  return source;
}
function retained(file, source) { return file === serviceFile ? retainedServices(source) : source; }
module.exports = {retained, retainedServices};
function canonical(file, source) {
  const baseline = path.join(__dirname, 'observation-scope-baseline.cjs');
  return fs.existsSync(baseline) ? require(baseline).normalizePending(file, source) : source;
}
function section(source, first, last) {
  const a = source.indexOf(first), b = source.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); return source.slice(a, b);
}
if (require.main === module) {
  const services = read(serviceFile);
  assert.equal(canonical(serviceFile, retainedServices(services)), show(base, serviceFile), 'Every other coordinator line retained');
  const policyFile = app + 'AgentNativeConnectorRecoveryWake.swift', policy = read(policyFile);
  const fixtureFile = 'apps/ios/GalaxySSITests/AgentNativeConnectorRecoveryWakeTests.swift', fixtures = read(fixtureFile);
  assert.equal(policy, show(approved, policyFile)); assert.equal(fixtures, show(approved, fixtureFile));
  assert.equal((fixtures.match(/  func test/g) || []).length, 10);
  const resolver = section(services, marker, '  private func scheduleNativeConnectorObservation(');
  const gates = ['desktopReplyRecoveryOwner == store.profile.identityFingerprint',
    'identity.conversationId == dispatch.conversationId, identity.turnId == dispatch.turnId, identity.taskId == dispatch.taskId',
    'currentManagedDesktopReply(binding) == record', 'let observation = desktopReplyRecovery.record(for: binding)',
    'AgentNativeConnectorRecoveryWake.terminalResult(pending: pending, managed: record'];
  for (const token of gates) assert(resolver.includes(token), token);
  assert.equal(services.split('let wake = nativeConnectorRecoveryWake(dispatch: context.dispatch, pending: context.pending,').length - 1, 2);
  for (const token of ['AgentNativeConnectorObservationWakePolicy.next(', 'managed.state == .pending, managed.response == nil',
    'owner.ownerRunId == managed.ownerRunId, owner.sourceMessageId == managed.sourceMessageId',
    'observation.generation == managed.executionGeneration', 'Int64(pending.metadata["remote_task_status_seq"] ?? "") == observation.sequence',
    'observation.acceptedReply == nil, observation.pinnedTeamReply == nil',
    'observation.terminalObservedAt > 0, observation.terminalObservedAt <= nowMillis',
    'projectedAt >= observation.terminalObservedAt, projectedAt <= observation.lastResponseAt',
    'startedAtMillis: observation.terminalObservedAt', 'delayMillis: remaining == 0 ? throttle : min(remaining, throttle)']) assert(policy.includes(token), token);
  assert(!/\.execute\(|\.generate\(|\.publish\(|\.release\(|writeControl|UserDefaults|FileManager|URLSession/.test(policy + resolver));
  const calls = section(services, '  private func observeWaitingNativeConnector(', '  private func recordNativeConnectorObservation(');
  assert(calls.includes('await sweepDesktopReplyRecovery()'));
  assert(!/handleConnectorTimeout\(|connectorFallbackAction\(|enqueueLinkPayload\(|startQueuedConnector\(/.test(calls));
  let negatives = 0;
  for (const token of gates) {
    const mutated = services.replace(resolver, resolver.replace(token, 'REMOVED_TERMINAL_OWNER_GATE'));
    assert.throws(() => assert.equal(canonical(serviceFile, retainedServices(mutated)), show(base, serviceFile)), assert.AssertionError);
    negatives++;
  }
  for (const token of ['managed.state == .pending', 'observation.acceptedReply == nil',
    'observation.terminalObservedAt <= nowMillis', 'owner.executionGeneration == managed.executionGeneration',
    'AgentRemoteOutcomePolicy.isTerminal(observation.status)', 'remaining == 0 ? throttle : min(remaining, throttle)']) {
    assert(policy.includes(token));
    assert.throws(() => assert.equal(policy.replace(token, 'REMOVED_TERMINAL_POLICY_GATE'), show(approved, policyFile)), assert.AssertionError);
    negatives++;
  }
  for (const name of ['AgentDesktopReplyRecovery', 'AgentManagedResponseModels', 'AgentAutomationModels', 'AgentConnectorResponseResolver']) {
    const file = app + name + '.swift'; assert.equal(canonical(file, read(file)), show(base, file), name);
  }
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const entries = source => source.split('\n').filter(line => /AgentNativeConnectorRecoveryWake(?:Tests)?\.swift/.test(line));
  assert.equal(entries(read(project)).length, 8); assert.deepEqual(entries(read(project)), entries(show(approved, project)));
  const android = show('0e709fbbc84d8fc5bca82b854e248066098badbd', 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentRemoteSilencePolicy.kt');
  assert(android.includes('TERMINAL_DELIVERY_LIMIT = 15 * 60_000L') && android.includes('PROBE_INTERVAL = 30_000L'));
  assert(!/\p{Script=Han}/u.test(policy + fixtures));
  console.log(`Owned terminal-result wake, unchanged stage/recovery kernels, bounded expired pacing and ${negatives} negative source mutations checked. Ten Swift fixtures authored, not executed; no native timer/result acceptance.`);
}

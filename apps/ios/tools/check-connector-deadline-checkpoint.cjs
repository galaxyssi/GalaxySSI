// Source contracts only; no Swift, timers, storage faults or transport are executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '4478b0e69bd1b824ad2a066196707dabc01aa56f';
const clean = s => s.replace(/\r\n/g, '\n'), read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32_000_000})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
const markers = {
  'GalaxySSIServices.swift': '  private func recordNativeConnectorDeadlineObservation(',
  'AgentConnectorTaskStatusRecorder.swift': 'enum AgentNativeConnectorDeadlineObservation {',
  'AgentNativeConnectorStatusObservationTests.swift': '  private func deadlinePending('
};
function retained(file, source) {
  const marker = markers[path.basename(file)];
  if (!marker || !source.includes(marker)) return source;
  const patch = git(['diff', '--no-ext-diff', '--no-color', '--unified=0', base, approved, '--', file]);
  let old = [], current = [], active = false;
  function flush() {
    if (!active) return;
    const from = '\n' + current.join('\n') + '\n';
    assert.equal(source.split(from).length, 2, 'Unique exact deadline checkpoint: ' + from.slice(0, 160));
    source = source.replace(from, '\n' + (old.length ? old.join('\n') + '\n' : ''));
    old = []; current = [];
  }
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith('-')) old.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected zero-context patch line');
  }
  flush(); assert(active, file); return source;
}
const retainedServices = source => retained(app + 'GalaxySSIServices.swift', source);
module.exports = {retained, retainedServices};
function optional(name, method, source) {
  const location = path.join(__dirname, name + '.cjs');
  return fs.existsSync(location) ? require(location)[method](source) : source;
}
function canonical(file, source) {
  if (file.endsWith('/GalaxySSIServices.swift')) {
    for (const [name, method] of [['check-scoped-member-recall', 'retainedServices'],
      ['check-pinned-desktop-team', 'retainedServices'], ['check-browser-view-ownership', 'retainedBrowserServices'],
      ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'], ['check-pairing-history', 'retainedPairingServices']]) {
      source = optional(name, method, source);
    }
  }
  return source;
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
if (require.main === module) {
  const files = [app + 'GalaxySSIServices.swift', app + 'AgentConnectorTaskStatusRecorder.swift',
    'apps/ios/GalaxySSITests/AgentNativeConnectorStatusObservationTests.swift'];
  for (const file of files) assert.equal(canonical(file, retained(file, read(file))), show(base, file), file);
  const service = read(files[0]), recorder = read(files[1]), tests = read(files[2]);
  const checkpoint = section(service, '  private func recordNativeConnectorDeadlineObservation(', '  private func recordNativeConnectorObservation(');
  for (const token of ['nativeConnectorObservationContext(action: action, pending: pending)',
    'current.task.phase == .waitingResponse, current.pending == context.pending',
    'current.task.lastNativeActionResult == current.pending', 'matches.count == 1, let index = matches.first',
    'AgentNativeConnectorContinuation.waitingAction(', 'updated.activePlan = plan',
    'updated.lastNativeActionResult = observed', 'updated.pendingActions = updated.pendingActions.map',
    'store.commitOwnedAgentTaskState(expected: current.task, updated: updated)']) assert(checkpoint.includes(token), token);
  assert(service.includes('    recordNativeConnectorDeadlineObservation(action: action, pending: context.pending)\n'));
  assert(service.indexOf('recordNativeConnectorDeadlineObservation(action: action, pending: context.pending)') <
    service.indexOf('await sweepDesktopReplyRecovery()', service.indexOf('recordNativeConnectorDeadlineObservation(action: action, pending: context.pending)')));
  const policy = recorder.slice(recorder.indexOf('enum AgentNativeConnectorDeadlineObservation {'));
  for (const token of ['AgentNativeConnectorObservationWakePolicy.next(', 'wake.delayMillis == 0',
    'nowMillis.subtractingReportingOverflow(wake.startedAt)', 'guard !elapsed.overflow',
    'pending.metadata["native_connector_observation_deadline_clock"] != wake.clock',
    'result.metadata["native_connector_observation_deadline_clock"] = wake.clock']) assert(policy.includes(token), token);
  assert(!/result\.(?:success|message|actionId)\s*=|\.execute\(|\.generate\(|UserDefaults|FileManager|URLSession|\.publish\(|\.release\(/.test(policy + checkpoint));
  const writes = [...policy.matchAll(/result\.metadata\["([^"]+)"\] = /g)].map(match => match[1]);
  assert.equal(writes.length, 6);
  assert(writes.every(key => key.startsWith('native_connector_observation_')));
  for (const key of ['native_connector_observation_deadline_clock', 'native_connector_observation_deadline_observed_at']) {
    assert(recorder.slice(0, recorder.indexOf('enum AgentNativeConnectorDeadlineObservation {')).includes('"' + key + '"'));
  }
  const addedTests = section(tests, '  private func deadlinePending(', '  func testMalformedSequenceAndBackwardClockAreRejectedWithoutDefaulting');
  assert.equal((addedTests.match(/  func test/g) || []).length, 8);
  assert(!/\p{Script=Han}/u.test(policy + checkpoint + addedTests));
  let negatives = 0;
  for (const [file, tokens] of [[files[0], ['!Task.isCancelled,', 'current.pending == context.pending',
    'current.task.lastNativeActionResult == current.pending', 'matches.count == 1, let index = matches.first',
    'store.commitOwnedAgentTaskState(expected: current.task, updated: updated)',
    'recordNativeConnectorDeadlineObservation(action: action, pending: context.pending)']],
    [files[1], ['wake.delayMillis == 0', '!elapsed.overflow',
      'pending.metadata["native_connector_observation_deadline_clock"] != wake.clock',
      'nowMillis.subtractingReportingOverflow(wake.startedAt)']]]) {
    for (const token of tokens) {
      const source = read(file), start = file === files[0] && token !== 'recordNativeConnectorDeadlineObservation(action: action, pending: context.pending)'
        ? source.indexOf('  private func recordNativeConnectorDeadlineObservation(') : 0;
      const at = source.indexOf(token, start); assert(at >= 0, token);
      const changed = source.slice(0, at) + 'REMOVED_DEADLINE_GATE' + source.slice(at + token.length);
      assert.throws(() => assert.equal(canonical(file, retained(file, changed)), show(base, file)), assert.AssertionError);
      negatives++;
    }
  }
  for (const name of ['AgentIOSConnectorDispatch', 'AgentConnectorResponseResolver', 'AgentConnectorTimeoutResolver',
    'AgentConnectorTransportReceiptRecorder', 'AgentAutomationModels']) assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  console.log(`Owned deadline checkpoint, current task commit, bounded metadata-only policy, status cleanup and ${negatives} negative source mutations checked. Eight new Swift fixtures authored, not executed; no native/timer/failover acceptance.`);
}

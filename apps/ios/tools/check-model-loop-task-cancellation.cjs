// Source contracts only. No Swift, concurrency, provider, tool or journal execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '69ff5a8514c26f020ca6ff2355319a8062cdba37';
const loopFile = app + 'AgentModelToolLoop.swift', testsFile = 'apps/ios/GalaxySSITests/AgentModelToolLoopTests.swift';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function inverse(file, source) {
  const marker = file === loopFile ? '    let taskCancellation: AgentModelToolLoopCancellationSource' :
    '  func testSwiftTaskCancellationBeforeRunDoesNotRequestModelOrTool()';
  if (!source.includes(marker)) return source;
  const diff = git(['diff', '--no-ext-diff', '--no-color', '--unified=0', base, approved, '--', file]);
  let previous = [], current = [], active = false;
  function flush() {
    if (!active) return;
    const from = '\n' + current.join('\n') + '\n', to = '\n' + (previous.length ? previous.join('\n') + '\n' : '');
    assert.equal(source.split(from).length, 2, 'Exact task-cancellation delta: ' + from.slice(0, 120));
    source = source.replace(from, to); previous = []; current = [];
  }
  for (const line of diff.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith('-')) previous.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected diff format');
  }
  flush(); assert(active); return source;
}
const retainedLoop = source => inverse(loopFile, source), retainedTests = source => inverse(testsFile, source);
module.exports = {retainedLoop, retainedTests};
function validateLoop(source) {
  assert.equal(source.split('withTaskCancellationHandler(operation:').length - 1, 2);
  let restored = retainedLoop(source);
  const planning = path.join(__dirname, 'check-planning-recovery-ownership.cjs');
  if (fs.existsSync(planning)) restored = require(planning).retainedLoop(restored);
  assert.equal(restored, show(base, loopFile), 'All existing execution/retry/approval/recovery logic retained');
}
if (require.main === module) {
  const loop = read(loopFile); validateLoop(loop);
  const tests = read(testsFile); let restoredTests = retainedTests(tests);
  const ownedStart = '  func testOwnedLoopRejectsBeforeModelOrToolExecution()', end = '  func testHistorySnapshotFiltersAndUTF16Chunks()';
  if (restoredTests.includes(ownedStart)) {
    const reviewed = show('85908f850e5d0cc2954080a8247bb20b69995188', testsFile);
    const block = reviewed.slice(reviewed.indexOf(ownedStart), reviewed.indexOf(end));
    assert.equal(restoredTests.split(block).length, 2, 'Retain exact previously reviewed ownership fixtures');
    restoredTests = restoredTests.replace(block, '');
  }
  assert.equal(restoredTests, show(base, testsFile), 'Other fixtures retained');
  assert.equal((tests.match(/  func test(?:SwiftTaskCancellation|TaskBridgeSurvives)/g) || []).length, 6);
  for (const name of ['AgentModelToolLoopModels', 'AgentModelLoopJournal'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const mutations = [
    ['await advance(state, initialCalls: [])', 'await advance(state, initialCalls: pending.remainingCalls)'],
    ['onCancel: { state.taskCancellation.cancel() }', 'onCancel: {}'],
    ['onCancel: { pending.state.taskCancellation.cancel() }', 'onCancel: {}'],
    ['await resumeOwned(pending, handle: handle, decision: decision)', 'await advance(pending.state, initialCalls: [])'],
    ['self.taskCancellation = taskCancellation', 'self.taskCancellation = AgentModelToolLoopCancellationSource()'],
    ['request.cancellationToken.isCancellationRequested || taskCancellation.token.isCancellationRequested',
      'request.cancellationToken.isCancellationRequested && taskCancellation.token.isCancellationRequested'],
    ['request.cancellationToken.isCancellationRequested || ', ''],
    [' || taskCancellation.token.isCancellationRequested', ''],
    ['if state.request.cancellationToken.isCancellationRequested {', 'if false {'],
    ['cancellationRequested: { state.request.cancellationToken.isCancellationRequested }', 'cancellationRequested: { false }']
  ];
  for (const [from, to] of mutations) {
    assert(loop.includes(from), from); assert.throws(() => validateLoop(loop.replace(from, to)), undefined, from);
  }
  const fixture = 'try DispatchQueue.global(qos: .utility).sync { try invocation.checkpoint() }';
  assert(tests.includes(fixture)); assert.throws(() => retainedTests(tests.replace(fixture, '')));
  console.log('Task-cancellation source contracts and 11 negative source mutations passed; six Swift fixtures authored, not executed.');
}

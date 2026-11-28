// Source contracts only; no Swift, model, threading, queue or native execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '303ea378c82dc48e9a10157cdba3f9c887808758';
const files = {
  runtime: app + 'LocalModelInferenceRuntime.swift', cooperative: app + 'LocalModelCooperativeRuntime.swift',
  adapter: app + 'AgentIOSLocalModelWebToolAdapter.swift', tests: 'apps/ios/GalaxySSITests/LocalModelRuntimePreflightTests.swift'
};
const markers = {
  runtime: '    let taskCancellation = AgentModelToolLoopCancellationSource()',
  cooperative: '  private static func checkCancellation(',
  adapter: '      taskId: taskID,\n      cancellation: AgentModelToolLoopCancellationToken',
  tests: '  func testCancelledTokenRejectsQueuedLocalInferenceBeforeModelReadiness()'
};
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function retained(file, source) {
  const kind = Object.keys(files).find(key => files[key] === file);
  if (!kind || !source.includes(markers[kind])) return source;
  const diff = git(['diff', '--no-ext-diff', '--no-color', '--unified=0', base, approved, '--', file]);
  let previous = [], current = [], active = false;
  const hunks = new Map();
  function flush() {
    if (!active) return;
    const from = '\n' + current.join('\n') + '\n', to = '\n' + (previous.length ? previous.join('\n') + '\n' : '');
    const existing = hunks.get(from);
    if (existing) { assert.equal(existing.to, to); existing.count++; }
    else hunks.set(from, {to, count: 1});
    previous = []; current = [];
  }
  for (const line of diff.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith('-')) previous.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected diff format');
  }
  flush(); assert(active);
  for (const [from, {to, count}] of hunks) {
    assert.equal(source.split(from).length - 1, count, 'Exact local cancellation hunk count: ' + from.slice(0, 100));
    source = source.split(from).join(to);
  }
  return source;
}
module.exports = {retained};
function validate(file, source) {
  const kind = Object.keys(files).find(key => files[key] === file);
  assert(kind && source.includes(markers[kind]), file + ': required cancellation entry');
  let restored = retained(file, source);
  if (file === files.adapter) {
    const planning = path.join(__dirname, 'check-planning-recovery-ownership.cjs');
    if (fs.existsSync(planning)) {
      assert.equal(typeof require(planning).retainedAdapter, 'function', 'Ownership guard must expose its exact adapter inverse');
      restored = require(planning).retainedAdapter(restored);
    }
  }
  assert.equal(restored, show(base, file), file + ': other behavior retained');
}
if (require.main === module) {
  for (const file of Object.values(files)) validate(file, read(file));
  const runtime = read(files.runtime), cooperative = read(files.cooperative), adapter = read(files.adapter);
  assert(runtime.includes('onCancel: { taskCancellation.cancel() }'));
  assert.equal(runtime.split('guard !combined.isCancellationRequested').length - 1, 2);
  assert(runtime.includes('if combined.isCancellationRequested {\n                continuation.resume(throwing: CancellationError())'));
  assert.equal(cooperative.split('try Self.checkCancellation(cancellation)').length - 1, 5);
  assert.equal(cooperative.split('cancellation: cancellation').length - 1, 2);
  assert.equal(adapter.split('cancellation.isCancellationRequested || self.inferenceCancellation.isCancellationRequested').length - 1, 2);
  const tests = read(files.tests);
  assert.equal((tests.match(/  func test(?:Cancelled|Uncancelled)/g) || []).length, 5);
  for (const file of ['AgentModelToolLoopModels.swift', 'LocalModelInferenceModels.swift', 'GalaxySSILlamaNativeBackend.swift'])
    assert.equal(read(app + file), show(base, app + file), file + ': original backend/token API retained');
  const mutations = [
    [files.runtime, 'onCancel: { taskCancellation.cancel() }', 'onCancel: {}'],
    [files.runtime, 'cancellation.isCancellationRequested || taskCancellation.token.isCancellationRequested', 'cancellation.isCancellationRequested'],
    [files.runtime, 'cancellation.isCancellationRequested || taskCancellation.token.isCancellationRequested', 'taskCancellation.token.isCancellationRequested'],
    [files.runtime, 'guard !combined.isCancellationRequested else { throw CancellationError() }', ''],
    [files.runtime, 'if combined.isCancellationRequested {', 'if false {'],
    [files.cooperative, 'try Self.checkCancellation(cancellation)', ''],
    [files.cooperative, '    try Self.checkCancellation(cancellation)\n\n    let answerPrompt:', '\n    let answerPrompt:'],
    [files.cooperative, '      } catch {\n        try Self.checkCancellation(cancellation)', '      } catch {'],
    [files.cooperative, 'cancellation: cancellation', 'cancellation: .none'],
    [files.cooperative, 'try Task.checkCancellation()', ''],
    [files.adapter, '      taskId: taskID,\n      cancellation: AgentModelToolLoopCancellationToken {\n        cancellation.isCancellationRequested || self.inferenceCancellation.isCancellationRequested\n      }', '      taskId: taskID'],
    [files.tests, 'withUnsafeCurrentTask { $0?.cancel() }', ''],
    [files.tests, 'cancellation.cancel()', '']
  ];
  for (const [file, from, to] of mutations) {
    const source = read(file); assert(source.includes(from), from);
    assert.throws(() => validate(file, source.replace(from, to)), undefined, from);
  }
  console.log('Local inference cancellation source contracts and 13 negative source mutations passed; five Swift fixtures authored, not executed.');
}

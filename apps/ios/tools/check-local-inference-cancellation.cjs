// Source contracts only; no Swift, model, threading, queue or native execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '87b005960e7f2ad75f85e76a180bb2cf0e8cc9f7';
const files = {
  runtime: app + 'LocalModelInferenceRuntime.swift', cooperative: app + 'LocalModelCooperativeRuntime.swift',
  adapter: app + 'AgentIOSLocalModelWebToolAdapter.swift', tests: 'apps/ios/GalaxySSITests/LocalModelRuntimePreflightTests.swift',
  models: app + 'LocalModelInferenceModels.swift', backend: app + 'GalaxySSILlamaNativeBackend.swift',
  planner: app + 'LocalModelAgentPlanningProvider.swift',
  header: 'apps/ios/GalaxySSILlamaRuntime/GalaxySSILlamaRuntime.h', native: 'apps/ios/GalaxySSILlamaRuntime/galaxyssi_llama.mm'
};
const markers = {
  runtime: '    let taskCancellation = AgentModelToolLoopCancellationSource()',
  cooperative: '  private static func checkCancellation(',
  adapter: '      taskId: taskID,\n      cancellation: AgentModelToolLoopCancellationToken',
  tests: '  func testCancelledTokenRejectsQueuedLocalInferenceBeforeModelReadiness()',
  models: 'extension LocalModelInferenceBackend {', backend: 'private final class GalaxySSILlamaCancellationContext',
  planner: '    } catch is CancellationError {',
  header: 'char *galaxyssi_llama_generate_cancellable(', native: 'extern "C" char *galaxyssi_llama_generate_cancellable('
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
  if (kind === 'adapter') {
    const call = text => {
      const start = '    let result = try await LocalModelCooperativeRuntime.shared.generateAsync(', end = '\n    )\n';
      assert.equal(text.split(start).length, 2);
      const a = text.indexOf(start), b = text.indexOf(end, a);
      assert(b > a); return text.slice(a, b + end.length);
    };
    const oldCall = call(show(base, file)), newCall = call(show(approved, file));
    let expected = source.includes('  private let validateOwner: (() async throws -> Void)?')
      ? show('85908f850e5d0cc2954080a8247bb20b69995188', file) : show(base, file);
    assert.equal(expected.split(oldCall).length, 2);
    expected = expected.replace(oldCall, newCall);
    assert.equal(source, expected, 'Complete adapter with only reviewed ownership and cancellation increments');
  } else {
    assert.equal(source, show(approved, file), 'Complete reviewed local cancellation source: ' + file);
  }
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
  assert.equal((tests.match(/  func testBackend/g) || []).length, 6);
  assert.equal(read(app + 'AgentModelToolLoopModels.swift'), show(base, app + 'AgentModelToolLoopModels.swift'));
  for (const file of ['apps/ios/build-galaxyssi-llama.sh', 'apps/ios/GalaxySSILlamaRuntime/CMakeLists.txt'])
    assert.equal(read(file), show(base, file), file + ': existing pinned static native build retained');
  const native = read(files.native), backend = read(files.backend), header = read(files.header);
  for (const token of ['withExtendedLifetime(cancellationContext)', 'Unmanaged.passUnretained(cancellationContext).toOpaque()',
    'guard let context else { return 1 }', 'takeUnretainedValue()', 'observed = observed || requested',
    '@convention(c) (UnsafeMutableRawPointer?) -> Int32', '@_silgen_name("galaxyssi_llama_generate_cancellable")']) assert(backend.includes(token), token);
  assert(header.includes('typedef int32_t (*galaxyssi_llama_cancel_callback)(void *context);'));
  assert.equal(native.split('check_generation_cancelled(callback, context);').length - 1, 2);
  assert.equal(native.split('check_generation_cancelled(cancellation_requested, cancellation_context);').length - 1, 4);
  const oldEntry = native.slice(native.indexOf('extern "C" char *galaxyssi_llama_generate('),
    native.indexOf('extern "C" char *galaxyssi_llama_generate_cancellable('));
  assert(oldEntry.includes('maximum_tokens, temperature, nullptr, nullptr)'));
  assert(!oldEntry.includes('runtime_mutex'), 'Only the delegated native entry acquires the runtime mutex');
  const cancelled = native.slice(native.indexOf('    } catch (const GenerationCancelled &error)'),
    native.indexOf('    } catch (const std::exception &error)', native.indexOf('    } catch (const GenerationCancelled &error)')));
  for (const token of ['llama_sampler_free(sampler)', 'if (memory != nullptr) llama_memory_clear(memory, true)', 'return nullptr;']) assert(cancelled.includes(token), token);
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
    [files.tests, 'cancellation.cancel()', ''],
    [files.runtime, 'cancellation: combined', 'cancellation: .none'],
    [files.runtime, 'temperature: max(0, temperature),\n          cancellation: cancellation', 'temperature: max(0, temperature)'],
    [files.runtime, '} catch is CancellationError {', '} catch is SyntheticInferenceFailure {'],
    [files.models, 'cancellation: AgentModelToolLoopCancellationToken\n  ) throws -> String\n  func unload()', 'cancellation: AgentModelToolLoopCancellationToken\n  ) throws -> String { "" }\n  func unload()'],
    [files.backend, '@_silgen_name("galaxyssi_llama_generate_cancellable")', '@_silgen_name("galaxyssi_llama_generate")'],
    [files.backend, 'withExtendedLifetime(cancellationContext)', 'withExtendedLifetime(0)'],
    [files.backend, 'Unmanaged.passUnretained(cancellationContext)', 'Unmanaged.passRetained(cancellationContext)'],
    [files.backend, 'guard let context else { return 1 }', 'guard let context else { return 0 }'],
    [files.backend, 'observed = observed || requested', 'observed = requested'],
    [files.header, 'typedef int32_t (*galaxyssi_llama_cancel_callback)', 'typedef int64_t (*galaxyssi_llama_cancel_callback)'],
    [files.native, 'callback(context) != 0', 'callback(context) == 0'],
    [files.native, '        check_generation_cancelled(callback, context);', ''],
    [files.native, 'for (int32_t generated = 0; generated < generation_limit; ++generated) {\n            check_generation_cancelled(cancellation_requested, cancellation_context);',
      'for (int32_t generated = 0; generated < generation_limit; ++generated) {'],
    [files.native, 'const int32_t decode_result = llama_decode(loaded_context, batch);\n            check_generation_cancelled(cancellation_requested, cancellation_context);',
      'const int32_t decode_result = llama_decode(loaded_context, batch);'],
    [files.native, '        check_generation_cancelled(cancellation_requested, cancellation_context);\n        llama_sampler_free(sampler);', '        llama_sampler_free(sampler);'],
    [files.native, 'if (memory != nullptr) llama_memory_clear(memory, true)', 'if (memory != nullptr) llama_memory_clear(memory, false)'],
    [files.native, 'return nullptr;\n    } catch (const std::exception &error)', 'return copy_string("");\n    } catch (const std::exception &error)'],
    [files.tests, 'XCTAssertEqual(fixture.awareExecutions, 1)', 'XCTAssertEqual(fixture.awareExecutions, 0)'],
    [files.cooperative, '} catch is CancellationError {', '} catch is SyntheticInferenceFailure {'],
    [files.planner, '} catch is CancellationError {', '} catch is SyntheticInferenceFailure {']
  ];
  for (const [file, from, to] of mutations) {
    const source = read(file); assert(source.includes(from), from);
    assert.throws(() => validate(file, source.replace(from, to)), undefined, from);
  }
  const moved = cooperative.replace('    try Self.checkCancellation(cancellation)\n\n    let answerPrompt:', '\n    let answerPrompt:')
    .replace('    let startedAt = Date()', '    try Self.checkCancellation(cancellation)\n    let startedAt = Date()');
  assert.notEqual(moved, cooperative);
  assert.equal(moved.split('try Self.checkCancellation(cancellation)').length - 1, 5);
  assert.throws(() => retained(files.cooperative, moved), undefined, 'Correct count at wrong stage must fail');
  assert.equal(mutations.length + 1, 34);
  console.log('Local/native inference cancellation source contracts and 34 negative source mutations passed; eleven Swift fixtures authored, not executed.');
}

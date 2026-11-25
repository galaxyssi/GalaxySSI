// Source comparisons only, not Swift compilation or runtime acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = 'a66d7cfc13fdc8ce72fdb64b9215d56d969eae05';
const swift = name => `apps/ios/GalaxySSI/${name}.swift`;
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const budget = read(swift('CloudResearchRuntimeBudget'));
const identity = `      var identity = AgentMcpJSONCodec.sha256([
        "url": .string(canonical), "content_sha256": .string(hash),
        "evidence_level": .string(item["evidence_level"]?.stringValue ?? ""),
        "images": .array(item["images"]?.arrayValue ?? [])
      ])`;
assert(budget.includes(identity));
assert.equal(budget.replace(identity, '      var identity = canonical + "\\n" + hash'), old(swift('CloudResearchRuntimeBudget')),
  'Only evidence identity changes; configured limits, reading-window identity, retrieval gate, stop/finalization/recovery/deadline behavior retained');
const provider = read(swift('AgentIOSURLSessionWebMediaProvider'));
let retained = require('./check-image-search-fusion-scope.cjs').retainedProvider(provider);
for (const [before, after] of [
  ['  var monotonicNowNanoseconds: () -> UInt64\n', ''],
  ['    },\n    monotonicNowNanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }', '    }'],
  ['    self.monotonicNowNanoseconds = monotonicNowNanoseconds\n', ''],
  ['      let resolutionStarted = monotonicNowNanoseconds()\n', ''],
  ['      let resolutionEnded = monotonicNowNanoseconds()\n      let resolutionMillis = resolutionEnded >= resolutionStarted ? Int64((resolutionEnded - resolutionStarted) / 1_000_000) : 0\n', ''],
  ['        output["duration_millis"] = .int(resolutionMillis)\n', ''],
  ['        resultMetadata["duration_millis"] = .int(resolutionMillis)\n', '']
]) {
  assert(retained.includes(before), before);
  retained = retained.replace(before, after);
}
assert.equal(retained, old(swift('AgentIOSURLSessionWebMediaProvider')),
  'Only total resolution timing is added; HTTP/request policy, parser, cancellation/fallback selection, timestamps, renderer duration and evidence unchanged');
const executeStart = provider.indexOf('  private func executeWeb(');
const begin = provider.indexOf('let resolutionStarted =', executeStart);
const resolve = provider.indexOf('let resolution = try resolvedResource(', executeStart);
const end = provider.indexOf('let resolutionEnded =', executeStart);
assert(begin < resolve && resolve < end, 'Measure the whole static plus fallback resolution, including caught render failure');
for (const name of ['CloudConversationStreamEngine', 'CloudConversationNonStreamingToolEngine', 'CloudConversationStreamToolRounds',
  'AgentIOSDynamicWebRenderer', 'AgentIOSWebEvidenceVerification', 'AgentMcpCoreModels']) {
  const file = swift(name);
  assert.equal(read(file), old(file), name + ' unchanged');
}
const engine = read(swift('CloudConversationStreamEngine'));
assert(engine.includes('newResearchEvidence = research.observe(tool: outcome.call.name, output: output) || newResearchEvidence'));
assert(engine.includes('research.finishRetrievalBatch(madeProgress: newResearchEvidence)'));
const codec = read(swift('AgentMcpCoreModels'));
assert(codec.includes('object.keys.sorted().map'));
assert(codec.includes('SHA256.hash(data: Data(stringify(object).utf8))'));
const engineTests = read('apps/ios/GalaxySSITests/CloudConversationStreamEngineTests.swift');
for (const name of ['testResearchProgressCountsChangedImagesAndEvidenceLevelWithoutCountingMetadata',
  'testResearchProgressRetainsReadingWindowsAndExcludesNonRetrievalCalls']) assert(engineTests.includes('func ' + name + '('));
const renderTests = read('apps/ios/GalaxySSITests/AgentIOSDynamicWebRendererTests.swift');
for (const name of ['testFailedDynamicFallbackDurationIncludesBothAttemptsWithoutChangingStaticTimestamp',
  'testSuccessfulFallbackKeepsRendererDurationSeparateFromTotalDuration',
  'testUnavailableRendererPreservesStaticDurationAndSkipsRendering']) assert(renderTests.includes('func ' + name + '('));
console.log('Web evidence-progress and complete fallback-duration source contracts passed; no native build, XCTest or network acceptance.');

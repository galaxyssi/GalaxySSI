// Source contracts only, not native provider execution, latency, ranking or XCTest acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '912a8a07e063d3cc7da77f153f017d20fbed5304';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => require('./check-image-request-count-scope.cjs').retained(file, clean(fs.readFileSync(path.join(root, file), 'utf8')));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(source.split(first).length, 2, first);
  return source.slice(start, end);
}
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, from);
  return source.replace(from, to);
}
function retainedFastGrounding(source) {
  source = require('./check-image-request-count-scope.cjs').retained(app + 'CloudWebGrounding.swift', source);
  if (!source.includes('let ordinaryAlias = name.trimmingCharacters')) return source;
  source = source.replace(section(source, '  static func normalizeArguments(', '  static func boundedModelJson('),
    section(show(base, app + 'CloudWebGrounding.swift'), '  static func normalizeArguments(', '  static func boundedModelJson('));
  return once(source, 'description: "Search current public web sources with snippets. Fast lookup queries three preferred sources, not every engine. " +\n          "Review relevance and refine the query when evidence is insufficient; choose balanced for extra " +\n          "cross-engine corroboration or deep for comprehensive research. Set read_pages=true when ranked source text is needed in the same operation.",',
    'description: "Search and locally rerank current public web sources. Set read_pages=true when ranked source " +\n          "text is needed in the same operation.",');
}
function validateFastSearchDefaults() {
  const source = read(app + 'CloudWebGrounding.swift');
  assert.equal(retainedFastGrounding(source), show(base, app + 'CloudWebGrounding.swift'),
    'Only ordinary model alias defaults and its description change; native descriptors, evidence, failures, cache, prompts and other operations retained');
  const normalize = section(source, '  static func normalizeArguments(', '  static func boundedModelJson(');
  for (const token of ['let ordinaryAlias = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "web_search"',
    'if result["profile"] == nil', 'imageSearch || ordinaryAlias ? "fast" : "balanced"',
    'if ordinaryAlias, result["profile"] == .string("fast"),', 'result["engine_fanout"] == nil, result["engines"] == nil',
    'result["engine_fanout"] = .int(3)', 'result["limit"] == nil', 'result.removeValue(forKey: "max_results")']) assert(normalize.includes(token), token);
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/CloudWebGrounding.kt');
  for (const token of ['if (!result.containsKey("profile")) result["profile"] = "fast"',
    'result["profile"] == "fast" && !result.containsKey("engine_fanout") && !result.containsKey("engines")',
    'result["engine_fanout"] = 3', 'Fast lookup queries three preferred sources, not every engine.']) assert(reference.includes(token), token);
  for (const name of ['AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebIntelligenceNativeTools',
    'AgentIOSWebExecutionBudget', 'AgentIOSIndexedWebSourceCatalog', 'AgentIOSWebSearchCapacity', 'CloudWebToolFailurePolicy'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  const older = 'apps/ios/GalaxySSITests/CloudWebGroundingTests.swift';
  assert.equal(once(read(older), 'XCTAssertEqual(provider.inputs.first?["profile"], .string("fast"))\n    XCTAssertEqual(provider.inputs.first?["engine_fanout"], .int(3))',
    'XCTAssertEqual(provider.inputs.first?["profile"], .string("balanced"))'), show(base, older), 'Only obsolete default-profile fixture expectation changes');
  const tests = read('apps/ios/GalaxySSITests/CloudWebFastSearchTests.swift');
  for (const name of ['OrdinaryAliasDefaultsToFastThreeSourcesAndTenResults', 'ExplicitProfilesAndFanoutAreNeverOverwritten',
    'ExplicitEnginePresenceOrderAndEmptySelectionRemainIntact', 'NativeSearchImageAliasAndResearchDefaultsRemainDistinct',
    'ActualRegistryPathReceivesFastDefaultsWithoutNewGrants', 'ActualRegistryPathPreservesBalancedAndExplicitEngineRequests']) assert(tests.includes('func test' + name + '('), name);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('CloudWebFastSearchTests.swift in Sources */').length, 3);
}
module.exports = {retainedFastGrounding, validateFastSearchDefaults};
if (require.main === module) {
  validateFastSearchDefaults();
  console.log('iOS ordinary model-search fast/three-source defaults and explicit-selection preservation source contracts passed; no native acceptance');
}

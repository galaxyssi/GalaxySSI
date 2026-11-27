// Source contracts only; no Swift execution, network or performance acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const show = (ref, file) => cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function retainedImmutableRouting(source) {
  if (!source.includes('  private static let orderedSources:')) return source;
  const changes = [
    ['    let ranked = eligible.enumerated().filter { !blocked.contains($0.element.id) }.map {\n      (source: $0.element, ordinal: $0.offset, score: score($0.element))\n    }.sorted {\n      $0.score == $1.score ? $0.ordinal < $1.ordinal : $0.score > $1.score\n    }.map { $0.source }',
      '    let ranked = eligible.enumerated().filter { !blocked.contains($0.element.id) }.sorted {\n      let left = score($0.element), right = score($1.element)\n      return left == right ? $0.offset < $1.offset : left > right\n    }.map(\\.element)'],
    ['  private static let orderedSources: [AgentIOSWebIntelligenceSourceSpec] = {', '  private static var orderedSources: [AgentIOSWebIntelligenceSourceSpec] {'],
    ['    return base + AgentIOSWebIntelligenceSourceCatalog.indexedSources\n  }()', '    return base + AgentIOSWebIntelligenceSourceCatalog.indexedSources\n  }']
  ];
  for (const [from, to] of changes) { assert.equal(source.split(from).length, 2, from); source = source.replace(from, to); }
  return source;
}
module.exports = {retainedImmutableRouting};
if (require.main === module) {
  const catalog = read(app + 'AgentIOSWebIntelligenceSourceCatalog.swift');
  assert.equal(retainedImmutableRouting(catalog), show(base, app + 'AgentIOSWebIntelligenceSourceCatalog.swift'),
    'Only immutable catalog lifetime and per-request score materialization change');
  const body = catalog.slice(catalog.indexOf('  private static let orderedSources:'), catalog.indexOf('  static func queryLanguage('));
  assert(!/health|learnedSources|profile|credential|Date\(/.test(body), 'Only immutable bundled/public specs may be shared');
  const rank = catalog.slice(catalog.indexOf('    let ranked ='), catalog.indexOf('    var selected:', catalog.indexOf('    let ranked =')));
  assert.equal(rank.split('score($0.element)').length - 1, 1);
  assert(rank.indexOf('score: score($0.element)') < rank.indexOf('.sorted {'));
  assert(rank.includes('$0.ordinal < $1.ordinal'));
  for (const token of ['let catalog = orderedSources + learned', 'health[source.id]', 'circuitState(now: nowMillis)',
    'requestedEngineOrder.isEmpty', 'for category in categories.sorted()', 'for vertical in requestedVerticals.sorted']) assert(catalog.includes(token), token);
  const android = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  const entries = android.slice(android.indexOf('val entries: List<AgentWebIntelligenceEngineSpec> = listOf('), android.indexOf(') + indexedSources.mapIndexed'));
  const ids = [...entries.matchAll(/\bspec\(\s*"([^"]+)"/g)].map(match => match[1]);
  const order = JSON.parse('[' + catalog.match(/static let baseSourceOrder = \[([\s\S]*?)\n  \]/)[1] + ']');
  assert.equal(ids.length, 41); assert.deepEqual(order, ids);
  assert(android.includes('Triple(score, -index, spec.id)'));
  assert(android.indexOf('val score = spec.weight') < android.indexOf('.sortedWith(compareByDescending<Triple<Double, Int, String>>'));
  for (const name of ['AgentIOSWebSourceHealth', 'AgentIOSWebSourceLearning', 'AgentIOSIndexedWebSourceCatalog',
    'AgentIOSJSONWebSearchAdapter', 'AgentIOSHTMLWebSearchAdapter', 'AgentIOSArxivSearchAdapter', 'AgentIOSDevDocsSearchAdapter',
    'AgentIOSURLSessionWebMediaProvider', 'AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSWebSearchFusion', 'AgentIOSWebIntelligenceCache'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const tests = read('apps/ios/GalaxySSITests/AgentImmutableWebSourceRoutingTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 6);
  for (const token of ['testLiveCircuitAndClockAreNotCapturedByTheSharedCatalog', 'testLearnedSourcesAppearDisappearAndDisableBetweenRequests',
    'testExplicitDisabledAndOpenSourcesRetainOrderAndValueIsolation', 'first.selected[0].title', 'fanout: Int.max']) assert(tests.includes(token), token);
  assert(!/\p{Script=Han}/u.test(tests));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split('AgentImmutableWebSourceRoutingTests.swift in Sources').length - 1, 2);
  assert.equal(project.split('path = AgentImmutableWebSourceRoutingTests.swift;').length - 1, 1);
  console.log('Immutable 41-source catalog and once-per-request stable scoring source contracts passed; six XCTest methods authored, not executed.');
}

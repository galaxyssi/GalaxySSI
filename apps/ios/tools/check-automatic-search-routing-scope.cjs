// Source scope guard only. No Swift execution, live search or performance acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'b0d299157e8035b1b7849831bae31697d81753cc', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const norm = value => value.replace(/\r\n/g, '\n');
const read = file => {
  const hooks = require('./check-search-response-cache-scope.cjs');
  return hooks.retainedResponseCache(hooks.retainedResponseSearch(norm(fs.readFileSync(path.join(root, file), 'utf8'))));
};
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const providerHooks = [
  [
    "        learnedSources: imageSearch ? [] : learned",
    "        learnedSources: imageSearch ? [] : learned,\n        requestedEngineOrder: requestedEngines,\n        health: sourceSnapshot?.health ?? [:],\n        fanout: Int(min(max(input[\"engine_fanout\"]?.intValue ?? 6, 1), 32)),\n        nowMillis: nowMillis()"
  ],
  [
    "      let selection = AgentIOSWebSourceHealthRouting.select(providers: candidates.map(\\.provider),\n        preferred: Set(routing.selected.map(\\.id)), health: health ?? [:], explicit: explicitSources,\n        fanout: Int(min(max(input[\"engine_fanout\"]?.intValue ?? 6, 1), 32)), now: nowMillis())",
    "      let selection = imageSearch\n        ? AgentIOSWebSourceHealthRouting.select(providers: candidates.map(\\.provider),\n          preferred: [], health: health ?? [:], explicit: explicitSources,\n          fanout: Int(min(max(input[\"engine_fanout\"]?.intValue ?? 6, 1), 32)), now: nowMillis())\n        : AgentIOSWebSourceHealthRouting.Selection(selected: routing.selected.map(\\.id), skipped: routing.skipped)"
  ],
  [
    "    var endpoints = try routing.selected.map { source -> AgentIOSWebSearchEndpoint in",
    "    let selectedRootIDs = Set(routing.selected.map(\\.id)).intersection([\"bing\", \"baidu\", \"duckduckgo\"])\n    var endpoints = try routing.selected.filter { !selectedRootIDs.contains($0.id) }.map { source -> AgentIOSWebSearchEndpoint in"
  ],
  [
    "    endpoints += try orderedProviders.map { provider in",
    "    endpoints += try orderedProviders.filter { selectedRootIDs.contains($0) }.map { provider in"
  ],
  [
    "    return endpoints",
    "    let byID = Dictionary(uniqueKeysWithValues: endpoints.map { ($0.provider, $0) })\n    return routing.selected.compactMap { byID[$0.id] }"
  ]
];
function retainedAutoRoutingProvider(source) {
  if (!source.includes('let selectedRootIDs =')) return source;
  for (const [before, after] of providerHooks) {
    assert.equal(source.split(after).length, 2, 'One declared routing hook: ' + after);
    source = source.replace(after, before);
  }
  return source;
}
function retainedAutoRoutingCatalog(source) {
  const before = show(base, app + 'AgentIOSWebIntelligenceSourceCatalog.swift');
  const section = value => value.slice(value.indexOf('  static func select('), value.indexOf('  static func queryLanguage('));
  source = source.replace(section(source), section(before));
  assert.equal(source.split('  var skipped: [AgentIOSWebSourceHealth] = []\n').length, 2);
  return source.replace('  var skipped: [AgentIOSWebSourceHealth] = []\n', '');
}
module.exports = {retainedAutoRoutingProvider, retainedAutoRoutingCatalog};
if (require.main === module) {
  const providerFile = app + 'AgentIOSURLSessionWebMediaProvider.swift', catalogFile = app + 'AgentIOSWebIntelligenceSourceCatalog.swift';
  assert.equal(retainedAutoRoutingProvider(read(providerFile)), show(base, providerFile),
    'Only declared text selection/endpoint-order hooks; network, image, parsing, cache, evidence and budgets retained');
  assert.equal(retainedAutoRoutingCatalog(read(catalogFile)), show(base, catalogFile),
    'Only declared source selection kernel and skipped-health projection');
  const catalog = read(catalogFile), provider = read(providerFile);
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  const entries = reference.slice(reference.indexOf('val entries: List<AgentWebIntelligenceEngineSpec> = listOf('), reference.indexOf(') + indexedSources.mapIndexed'));
  const ids = [...entries.matchAll(/\bspec\(\s*"([^"]+)"/g)].map(m => m[1]);
  const order = JSON.parse('[' + catalog.match(/static let baseSourceOrder = \[([\s\S]*?)\n  \]/)[1] + ']');
  assert.equal(ids.length, 41); assert.deepEqual(order, ids);
  for (const token of ['requestedEngineOrder: requestedEngines', 'health: sourceSnapshot?.health ?? [:]',
    ': AgentIOSWebSourceHealthRouting.Selection(selected: routing.selected.map(\\.id), skipped: routing.skipped)',
    'orderedProviders.filter { selectedRootIDs.contains($0) }', 'return routing.selected.compactMap { byID[$0.id] }'])
    assert(provider.includes(token), token);
  for (const token of ['let catalog = orderedTextSources + learned', 'let limit = min(32, max(1, fanout))',
    'if !requestedEngineIds.isEmpty {', 'strategy: "explicit_sources"', '$0.enabledByDefault && ((',
    'baseSearchEngineIDs.contains($0.id) && general.contains($0.vertical)', 'source.languages.contains(language)',
    '1.05 : (source.id == "bing_news" ? 1.1 : 1)', 'requestedVerticals.contains(source.vertical) ? 2.5 : 0',
    '!categories.isDisjoint(with: source.categoryTags) ? 2.0 : 0', 'general.contains(source.vertical) ? 1.0 : 0',
    'languageMatch + source.authority * 0.5', '.routingScore', '.circuitState(now: nowMillis) == "open"',
    'for category in categories.sorted()', 'for vertical in requestedVerticals.sorted', 'selected.count >= limit',
    '!seen.contains($0.id)', '$0.offset < $1.offset', 'inferredVerticals: []']) assert(catalog.includes(token), token);
  for (const file of ['AgentIOSWebSourceHealth.swift', 'AgentIOSWebIntelligenceCache.swift',
    'AgentIOSImageSearchRequestPolicy.swift', 'AgentIOSWebExecutionBudget.swift', 'AgentIOSPublicSearchParser.swift',
    'AgentIOSWebSearchFusion.swift', 'AgentIOSURLSessionWebIntelligenceProvider.swift'])
    assert.equal(read(app + file), show(base, app + file), file + ' unchanged');
  const tests = read('apps/ios/GalaxySSITests/AgentIOSIndexedWebSourceCatalogTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 14);
  for (const token of ['testAutomaticBroadRoutingIncludesEnabledRegionalAndGeneralAdapters',
    'testCircuitFilteringPrecedesCategoryCoverage', 'testExplicitOrderBypassesDisabledAndOpenCircuit',
    'testFanoutBoundsAndStableBaseTieOrder', 'testActualAutomaticRegistryDispatchesRankedRootWithoutSiteScope',
    'testActualAutomaticRegistryDoesNotReadUnconsentedHealth', 'circuitOpenUntilMillis: 10_000'])
    assert(tests.includes(token), token);
  console.log('Pinned 41-source order, text scoring/coverage/health/explicit hooks and unchanged network/image/cache guards checked as source only.');
}

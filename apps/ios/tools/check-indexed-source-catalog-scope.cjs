// Source/data contracts only. This does not execute Swift or perform network acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = 'ee17e7cac043350e3f65c10ba025ecf55cde10c7';
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const normalize = value => value.replace(/\r\n/g, '\n');
const read = file => normalize(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => normalize(cp.execFileSync('git', ['show', ref + ':' + file],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const app = 'apps/ios/GalaxySSI/';
const reference = show(android, 'apps/desktop/core/galaxyssi-link/backend/web_source_sites.tsv');
// Use a structured TSV parser, not a second hand-maintained source list.
const parse = "$rows = [Console]::In.ReadToEnd() | ConvertFrom-Csv -Delimiter \"`t\"; @($rows) | ConvertTo-Json -Depth 5 -Compress";
const rows = JSON.parse(cp.execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', parse],
  {cwd: root, input: reference, encoding: 'utf8', maxBuffer: 2_000_000}).replace(/^\uFEFF/, ''));
const expected = rows.map(row => ({id: row.id, title: row.title, vertical: row.vertical,
  host: row.host, scope: row.scope, languages: row.languages.split(','), authority: Number(row.authority)}));
const resource = JSON.parse(read(app + 'web-indexed-sources.json'));
assert.deepEqual(resource, {version: 1, sources: expected}, 'All pinned indexed source fields and order retained');
assert.equal(expected.length, 247);
assert.equal(new Set(expected.map(row => row.id)).size, 247);
assert.equal(expected.filter(row => row.vertical === 'docs').length, 5);
assert.equal(expected.find(row => row.id === 'openai_agents_sdk').scope, 'openai.github.io/openai-agents-python');
assert(fs.statSync(path.join(root, app, 'web-indexed-sources.json')).size < 131_072);

function replaceOnce(value, before, after) {
  assert.equal(value.split(before).length, 2, 'Exactly one declared hook: ' + before);
  return value.replace(before, after);
}
const providerFile = app + 'AgentIOSURLSessionWebMediaProvider.swift';
let provider = require('./check-json-search-adapters-scope.cjs').retainedJSONProvider(read(providerFile));
for (const [before, after] of [
  ['maxResults: maxResults, allowedHosts: endpoint.allowedHosts, siteScope: endpoint.siteScope)',
    'maxResults: maxResults, allowedHosts: endpoint.allowedHosts)'],
  ['site:\\(source.scope ?? host) \\(query)', 'site:\\(host) \\(query)'],
  ['allowedHosts: source.allowedHosts,\n        siteScope: source.scope', 'allowedHosts: source.allowedHosts'],
  ['allowedHosts: [String] = [],\n    siteScope: String? = nil', 'allowedHosts: [String] = []'],
  ['(allowedHosts.isEmpty || allowedHosts.contains { allowedHost in', 'allowedHosts.isEmpty || allowedHosts.contains { allowedHost in'],
  ['}) && AgentIOSIndexedWebSourceCatalog.allowsResult(result.url, scope: siteScope)', '}'],
  ['  var siteScope: String? = nil\n', '']
]) provider = replaceOnce(provider, before, after);
assert.equal(provider, show(base, providerFile), 'All provider behavior outside site query/result scope retained');
const engineFile = app + 'AgentIOSWebExecutionBudget.swift';
assert.equal(replaceOnce(read(engineFile),
  'AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.union(\n      AgentIOSWebIntelligenceSourceCatalog.indexedSources.map(\\.id))',
  'Set(["bing", "baidu", "duckduckgo", "sogou_image", "brave_image", "duckduckgo_image"] +\n      AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.map(\\.id))'),
show(base, engineFile), 'Execution budget and validation unchanged except registered source set');
for (const file of ['AgentIOSImageSearchRequestPolicy.swift', 'AgentIOSPublicSearchParser.swift',
  'AgentIOSWebSourceHealth.swift', 'AgentIOSWebIntelligenceCache.swift']) {
  const current = read(app + file).replace('    var retrievalStatus: String? = nil\n', '');
  assert.equal(current, show(base, app + file), file + ' unchanged except optional local-reference hit metadata');
}
const loader = read(app + 'AgentIOSIndexedWebSourceCatalog.swift');
for (const token of ['Bundle.main.url(forResource: "web-indexed-sources", withExtension: "json")',
  'else { return [] }', 'data.count <= 131_072', 'envelope.version == 1', 'ids.insert(record.id).inserted',
  'scope.host == record.host', 'scope.port == nil, scope.query == nil, scope.fragment == nil',
  'index % 2 == 0 ? "duckduckgo" : "bing"', 'languages: Set(record.languages)',
  'result.path == path || result.path.hasPrefix(path + "/")']) assert(loader.includes(token), token);
const catalog = read(app + 'AgentIOSWebIntelligenceSourceCatalog.swift');
for (const token of ['SourceCatalog.indexedSources + learned', 'queryLanguage(query)', 'source.languages.contains(language)',
  'for category in categories.sorted()', 'for vertical in requestedVerticals.sorted', 'seen.insert(source.id).inserted',
  'indexedSourceCount: Int { indexedSources.count }', 'sourceCount: Int { baseSearchEngineCount + indexedSourceCount }']) assert(catalog.includes(token), token);
assert(!catalog.includes('= 40') && !catalog.includes('= 247') && !catalog.includes('wigoloAdapterCount'));
const learning = read(app + 'AgentIOSWebSourceLearning.swift');
assert(learning.includes('!AgentIOSWebSourceLearningPolicy.isBuiltInHost(host)'));
assert(learning.includes('SourceCatalog.indexedSources.flatMap(\\.allowedHosts)'));
assert(learning.includes('!isBuiltInHost(host)'));
const view = read(app + 'GalaxySSIWebIntelligenceSourcesView.swift');
assert(view.includes('Native search adapters'));
assert(!view.includes('18 / 18'));
const tests = read('apps/ios/GalaxySSITests/AgentIOSIndexedWebSourceCatalogTests.swift');
assert.equal((tests.match(/  func test/g) || []).length, 8);
for (const token of ['XCTAssertTrue(saved.isValid)', 'XCTAssertFalse(saved.isSearchEligible)',
  'XCTAssertTrue(transport.requests.isEmpty)', 'XCTAssertEqual(transport.requests.count, 1)',
  'openai-agents-python-impostor', 'testRequestedCategoryAndVerticalCoverage']) assert(tests.includes(token), token);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const token of ['C3007D000000000000000001 /* AgentIOSIndexedWebSourceCatalog.swift in Sources */',
  'C3007D000000000000000003 /* web-indexed-sources.json in Resources */',
  'C3007D000000000000000005 /* AgentIOSIndexedWebSourceCatalogTests.swift in Sources */']) {
  assert.equal(project.split(token).length, 3, 'Build-file declaration and phase membership: ' + token);
}
console.log('Pinned 247-row catalog, scoped routing hooks, retained provider/budget policies and fixture/project source contracts passed. No Swift typecheck, XCTest, live network or device acceptance.');

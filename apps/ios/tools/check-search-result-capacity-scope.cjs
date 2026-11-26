// Source contracts only. No Swift typecheck, XCTest, live search or performance evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'd6793a31dc7bfedfdf50372101b8fc4f377e8249';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function undo(source, changes) {
  for (const [before, after] of changes) {
    assert.equal(source.split(before).length, 2, 'Exactly one capacity hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}
function retainedCapacityMedia(source) {
  source = require('./check-web-crawl-scope.cjs').retainedCrawlMedia(source);
  if (!source.includes('  var searchScope: AgentIOSWebSearchCapacity.Scope')) return source;
  return undo(source, [
    ['  var searchScope: AgentIOSWebSearchCapacity.Scope = .webMedia\n', ''],
    ['string(input, "query", limit: searchScope.queryCharacters)', 'string(input, "query", limit: 1_024)'],
    ['min(requestedMaxResults, searchScope.maximumResults)', 'min(requestedMaxResults, Int64(24))'],
    ['results = try imageSearchResults(endpoint: endpoint, resource: resource, query: query,\n                limit: searchScope.imageCandidates(maxResults), invocation: searchInvocation)',
      'results = try imageSearchResults(endpoint: endpoint, resource: resource, query: query, invocation: searchInvocation)'],
    ['URLQueryItem(name: "count", value: String(searchScope.imageCandidates(maxResults)))', 'URLQueryItem(name: "count", value: "20")'],
    ['query: String, limit: Int, invocation: AgentNativeToolInvocation) throws -> [AgentIOSWebSearchResult]',
      'query: String, invocation: AgentNativeToolInvocation) throws -> [AgentIOSWebSearchResult]'],
    ['sogouImages(decodedText(resource).text, limit: limit)', 'sogouImages(decodedText(resource).text, limit: 20)'],
    ['imageRows(resource.body, brave: true, limit: limit)', 'imageRows(resource.body, brave: true, limit: 20)'],
    ['imageRows(response.body, brave: false, limit: limit)', 'imageRows(response.body, brave: false, limit: 20)']
  ]);
}
function retainedCapacityProvider(source) {
  source = require('./check-web-crawl-scope.cjs').retainedCrawlProvider(source);
  if (!source.includes('"result_policy": .string("ios_intelligence_capacity_v1")')) return source;
  return undo(source, [
    ['"limit": .int(Int64(limit)), "engine_fanout": .int(12)', '"limit": .int(Int64(min(limit, 24))), "engine_fanout": .int(12)'],
    ['defaultValue: int(input, "evidence_limit", defaultValue: AgentIOSWebSearchCapacity.defaultResults,\n        minimum: 1, maximum: AgentIOSWebSearchCapacity.maximumResults),\n      minimum: 1,\n      maximum: AgentIOSWebSearchCapacity.maximumResults',
      'defaultValue: int(input, "evidence_limit", defaultValue: 5, minimum: 1, maximum: 24),\n      minimum: 1,\n      maximum: 24'],
    ['      "result_policy": .string("ios_intelligence_capacity_v1"),\n', ''],
    ['      native.searchScope = .intelligence\n', '']
  ]);
}
function retainedCapacityCache(source) {
  source = require('./check-web-watch-scope.cjs').retainedWatchCache(source);
  if (!source.includes('<= AgentIOSWebSearchCapacity.maximumResults')) return source;
  return undo(source, [
    ['<= AgentIOSWebSearchCapacity.maximumResults', '<= 24'],
    ['$0 <= AgentIOSWebSearchCapacity.maximumCachedResponseBytes', '$0 <= 262_144']
  ]);
}
function validateSearchCapacity() {
  for (const [name, normalize] of [['AgentIOSURLSessionWebMediaProvider', retainedCapacityMedia],
    ['AgentIOSURLSessionWebIntelligenceProvider', retainedCapacityProvider], ['AgentIOSWebIntelligenceCache', retainedCapacityCache]])
    assert.equal(normalize(read(app + name + '.swift')), old(app + name + '.swift'),
      name + ': transport, credentials, permission, ranking, research, output budgeting and encrypted storage remain unchanged outside declared capacity hooks');
  for (const name of ['AgentIOSWebIntelligenceNativeTools', 'AgentIOSWebMediaNativeTools', 'AgentIOSWebSearchFusion',
    'AgentIOSPublicSearchParser', 'AgentIOSImageSearchRequestPolicy', 'AgentIOSWebEvidencePack', 'AgentIOSWebEvidenceReader',
    'AgentIOSWebCacheIndex', 'AgentIOSWebExecutionBudget']) assert.equal(name === 'AgentIOSWebIntelligenceNativeTools'
      ? require('./check-web-page-diff-scope.cjs').retainedDiffCatalog(read(app + name + '.swift')) : require('./check-web-watch-scope.cjs').retainedWatchFile(name, read(app + name + '.swift')), old(app + name + '.swift'), name);
  const limits = read(app + 'AgentIOSWebSearchCapacity.swift');
  for (const token of ['maximumResults = 100', 'defaultResults = 10', 'maximumCachedResponseBytes = 2_000_000',
    'case webMedia, intelligence', 'self == .intelligence', ': 24', '? 4_096 : 1_024', ': 20']) assert(limits.includes(token), token);
  const reference = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt'], {cwd: root, encoding: 'utf8'}));
  for (const token of ['arguments.integer("limit", 10, 1, 100)', 'arguments.integer("evidence_limit", if (autonomous) 12 else 8, 2, 24)',
    '"limit" to limit', 'store.putSearch(cacheKey, response']) assert(reference.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebSearchCapacityTests.swift');
  for (const name of ['IntelligenceRegistryReturnsAndCachesOneHundredTextResults', 'DefaultTenAndLongQueryReachTheNativeAdapter',
    'ImageAndMixedRequestsAreNotCutAtTwenty', 'RawWebMediaCannotSelectCapacityFromJSON',
    'FindSimilarCanFillBeyondTwentyFourWithScopedRemoteSearch', 'ExactCacheAllowsLargeHundredRowsButRejectsOverBounds',
    'ResearchEvidenceSchemaRemainsTwentyFour']) assert(tests.includes('func test' + name + '('), name);
  const updatedFixture = require('./check-search-retention-scope.cjs').retainedSearchFixture(read('apps/ios/GalaxySSITests/AgentIOSWebSearchFusionTests.swift'));
  assert.equal(updatedFixture.replace('count: AgentIOSWebSearchCapacity.maximumCachedResponseBytes + 1', 'count: 262_145'),
    old('apps/ios/GalaxySSITests/AgentIOSWebSearchFusionTests.swift'), 'Only obsolete fixture byte ceiling changed');
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebSearchCapacity', 'AgentIOSWebSearchCapacityTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedCapacityMedia, retainedCapacityProvider, retainedCapacityCache, validateSearchCapacity};
if (require.main === module) {
  validateSearchCapacity();
  console.log('iOS scoped 100-result intelligence/default-10, media candidate and exact-cache capacity source contracts passed; no native acceptance');
}

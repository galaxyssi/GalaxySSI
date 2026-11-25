// Source scope only: does not execute Swift, encryption recovery or native fixtures.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '9f4feefba48581c9177d9674f10238bfc64e04fe', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const norm = value => value.replace(/\r\n/g, '\n');
const read = file => norm(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const cacheHooks = [
  [
    "    var sourceHealth: [AgentIOSWebSourceHealth]? = nil",
    "    var sourceHealth: [AgentIOSWebSourceHealth]? = nil\n    var searchResponses: [SearchResponse]? = nil"
  ],
  [
    "  static let maxDocuments = 64",
    "  private struct SearchResponse: Codable {\n    var key: String\n    var storedAtMillis: Int64\n    var expiresAtMillis: Int64\n    var result: AgentNativeToolExecutionResult\n\n    var isValid: Bool {\n      key.count == 64 && key.allSatisfy { \"0123456789abcdef\".contains($0) } &&\n        storedAtMillis >= 0 && expiresAtMillis > storedAtMillis &&\n        expiresAtMillis - storedAtMillis <= 30 * 24 * 60 * 60_000 && result.isSuccess &&\n        !(result.output[\"results\"]?.arrayValue ?? []).isEmpty &&\n        (result.output[\"results\"]?.arrayValue?.count ?? 0) <= 24 &&\n        (try? JSONEncoder().encode(self).count).map { $0 <= 262_144 } == true\n    }\n  }\n\n  static let maxSearchResponses = 32\n\n  func searchResponse(key: String) -> AgentNativeToolExecutionResult? {\n    lock.lock()\n    defer { lock.unlock() }\n    let now = nowMillis()\n    return readUnlocked()?.searchResponses?.first {\n      $0.key == key && $0.storedAtMillis <= now && now < $0.expiresAtMillis\n    }?.result\n  }\n\n  func searchCacheGeneration() -> UUID {\n    lock.lock()\n    defer { lock.unlock() }\n    return state.generation\n  }\n\n  @discardableResult\n  func putSearchResponse(key: String, result: AgentNativeToolExecutionResult, ttlMillis: Int64,\n    expectedGeneration: UUID? = nil) -> Bool {\n    let now = max(0, nowMillis())\n    let ttl = min(max(ttlMillis, 60_000), 30 * 24 * 60 * 60_000)\n    guard now <= Int64.max - ttl else { return false }\n    let entry = SearchResponse(key: key, storedAtMillis: now, expiresAtMillis: now + ttl, result: result)\n    guard entry.isValid else { return false }\n    lock.lock()\n    defer { lock.unlock() }\n    guard expectedGeneration == nil || expectedGeneration == state.generation,\n      var snapshot = readUnlocked() else { return false }\n    do {\n      var responses = (snapshot.searchResponses ?? []).filter { $0.key != key && $0.expiresAtMillis > now }\n      responses.append(entry)\n      snapshot.searchResponses = Array(responses.sorted {\n        $0.storedAtMillis == $1.storedAtMillis ? $0.key < $1.key : $0.storedAtMillis > $1.storedAtMillis\n      }.prefix(Self.maxSearchResponses))\n    }\n    return writeUnlocked(snapshot)\n  }\n\n  static let maxDocuments = 64"
  ],
  [
    "      \"entry_count\": .int(Int64(snapshot.documents.count)),",
    "      \"entry_count\": .int(Int64(snapshot.documents.count)),\n      \"search_count\": .int(Int64(snapshot.searchResponses?.count ?? 0)),"
  ],
  [
    "    var learnedRemoved = 0",
    "    var learnedRemoved = 0\n    var searchesRemoved = 0"
  ],
  [
    "      removed = before - snapshot.documents.count",
    "      let searchesBefore = snapshot.searchResponses?.count ?? 0\n      if expiredOnly {\n        snapshot.searchResponses?.removeAll { $0.expiresAtMillis <= now }\n      } else {\n        snapshot.searchResponses = []\n      }\n      searchesRemoved = searchesBefore - (snapshot.searchResponses?.count ?? 0)\n      removed = before - snapshot.documents.count"
  ],
  [
    "      \"learned_sources_removed\": .int(Int64(committed ? learnedRemoved : 0))]",
    "      \"learned_sources_removed\": .int(Int64(committed ? learnedRemoved : 0)),\n      \"searches_removed\": .int(Int64(committed ? searchesRemoved : 0))]"
  ],
  [
    "          (snapshot.sourceHealth ?? []).allSatisfy(\\.isValid),",
    "          (snapshot.sourceHealth ?? []).allSatisfy(\\.isValid),\n          (snapshot.searchResponses?.count ?? 0) <= Self.maxSearchResponses,\n          (snapshot.searchResponses ?? []).allSatisfy(\\.isValid),\n          Set((snapshot.searchResponses ?? []).map(\\.key)).count == (snapshot.searchResponses?.count ?? 0),"
  ]
];
function retainedResponseCache(source) {
  source = require('./check-feature-hash-similarity-scope.cjs').retainedEmbeddingCache(source);
  if (!source.includes('    var searchResponses: [SearchResponse]? = nil')) return source;
  for (const [before, after] of cacheHooks) {
    assert.equal(source.split(after).length, 2, 'One exact response cache hook: ' + before);
    source = source.replace(after, before);
  }
  return source;
}
function retainedResponseSearch(source) {
  source = require('./check-feature-hash-similarity-scope.cjs').retainedEmbeddingProvider(source);
  if (!source.includes('let cacheGeneration = cacheScope ?')) return source;
  const old = show(base, app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  const section = value => value.slice(value.indexOf('  private func search('), value.indexOf('  func fetchCapturingHTML('));
  return source.replace(section(source), section(old));
}
module.exports = {retainedResponseCache, retainedResponseSearch};
if (require.main === module) {
  const cacheFile = app + 'AgentIOSWebIntelligenceCache.swift', providerFile = app + 'AgentIOSURLSessionWebIntelligenceProvider.swift';
  const cache = read(cacheFile), provider = read(providerFile);
  assert.equal(retainedResponseCache(cache), show(base, cacheFile), 'Only optional response records, bounds, stats, clear and guarded operations');
  assert.equal(retainedResponseSearch(provider), show(base, providerFile), 'Only search response caching kernel; fetch/research/watch/extract and other behavior unchanged');
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt');
  for (const token of ['"fanout" to fanout', '"profile" to profile.wireValue', '"engines" to engines.sorted()',
    '"verticals" to verticals.map { it.wireValue }.sorted()', '"categories" to categoryTags.sorted()',
    'store.getSearch(cacheKey)', 'store.putSearch(cacheKey, response', 'DEFAULT_CACHE_TTL_MILLIS = 6L * 60L * 60L'])
    assert(reference.includes(token), token);
  for (const token of ['"query": .string(query)', '"limit": .int(Int64(limit))', '"fanout": .int(',
    '"profile": .string(profile.rawValue)', '"engines": .array(requestedEngines.map',
    '"verticals": .array(Set(requestedVerticals).sorted()', 'requestedCategories.compactMap(',
    '"model": .string(AgentIOSWebSearchFusion.modelID)', '"url_normalization":', '"image_routing":', '"web_routing":',
    '"provider": .string(webMediaProvider.implementationId)', '"credential_scope": .string(credentialScope)',
    'imageCredentials.credential(.githubToken)', 'imageCredentials.credential(.braveAPIKey)',
    'if cacheScope, input["use_cache"]?.boolValue ?? true', 'let cached = cacheStore.searchResponse(key: cacheKey)',
    'response.metadata["response_cache_original_receipts"] = .bool(true)',
    'cache["network_attempted"] = .bool(false)', 'expectedGeneration: cacheGeneration',
    'guard webResult.isSuccess else { return webResult }', 'cacheHit: false',
    '(canReadCache ? cacheStore.stats() : [:])', 'if cacheScope, !invocation.isCancellationRequested, !resultObjects.isEmpty'])
    assert(provider.includes(token), token);
  assert(!provider.includes('mergeSearchResults(') && !provider.includes('cachedSearchResults(') && !provider.includes('cacheSearchResults('));
  for (const token of ['var searchResponses: [SearchResponse]? = nil', 'static let maxSearchResponses = 32',
    '$0 <= 262_144', 'now < $0.expiresAtMillis', '$0.storedAtMillis <= now',
    'expectedGeneration == state.generation', 'var snapshot = readUnlocked() else { return false }',
    'return writeUnlocked(snapshot)', 'snapshot.searchResponses?.removeAll { $0.expiresAtMillis <= now }',
    'snapshot.searchResponses = []', '(snapshot.searchResponses ?? []).allSatisfy(\\.isValid)',
    'Set((snapshot.searchResponses ?? []).map(\\.key)).count']) assert(cache.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebSearchFusionTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 14);
  for (const token of ['testExactResponseCachePreservesScoresAndReceiptsWithoutAnotherRequest',
    'testExactSearchIdentitySeparatesQueryProfileFanoutAndTopics', 'testForcedRefreshUnconsentedSearchAndCredentialRotationDoNotHitOldResponse',
    'testSearchResponseExpiryAndClearInvalidateInFlightGeneration', 'testSearchResponseBoundsRejectEmptyFailedAndOversizedEntries',
    'testSearchResponseFailedWriteAndCorruptReadDoNotErasePriorData', 'testLegacySnapshotWithoutSearchResponsesRemainsReadableAndRetained',
    'XCTAssertEqual(second.output["source_receipts"], first.output["source_receipts"])', '262_145']) assert(tests.includes(token), token);
  for (const file of ['AgentIOSURLSessionWebMediaProvider.swift', 'AgentIOSWebIntelligenceSourceCatalog.swift',
    'AgentIOSWebSourceHealth.swift', 'AgentIOSPublicSearchParser.swift', 'AgentIOSImageSearchRequestPolicy.swift',
    'AgentIOSWebSearchFusion.swift', 'AgentIOSWebExecutionBudget.swift'])
    assert.equal(read(app + file), show(base, app + file), file);
  console.log('Pinned exact-response cache identity, optional encrypted schema/bounds, clear generation, scope/provenance and unchanged raw search source guards passed. No native or fault acceptance.');
}

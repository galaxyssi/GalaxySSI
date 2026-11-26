// Source/data guard only; not Swift execution or native retrieval/performance acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '9219ef03d9e20cae8d4e4083f392274d1eab4384', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const norm = value => value.replace(/\r\n/g, '\n');
const read = file => norm(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const cacheHooks = [
  [
    "  var metadata: [String: String]",
    "  var metadata: [String: String]\n  var vector: [Float]? = nil\n  var embeddingModelID: String? = nil"
  ],
  [
    "      bounded.removeAll { $0.url == document.url }",
    "      document.vector = AgentIOSWebFeatureHashEmbedder.standard.embedDocument(title: document.title, content: document.content)\n      document.embeddingModelID = AgentIOSWebFeatureHashEmbedder.standard.modelID\n      bounded.removeAll { $0.url == document.url }"
  ],
  [
    "  func stats() -> AgentMcpJSONObject {",
    "  struct SimilarityHit {\n    var document: AgentIOSWebIntelligenceCacheDocument\n    var score: Double\n  }\n\n  func similarDocuments(query: String, limit: Int, excludingURL: String = \"\", target: [Float]? = nil) -> [SimilarityHit] {\n    let embedder = AgentIOSWebFeatureHashEmbedder.standard\n    let queryVector = target ?? embedder.embed(query)\n    let excluded = excludingURL.isEmpty ? \"\" : canonicalURL(excludingURL)\n    return read().documents.enumerated().filter { excluded.isEmpty || canonicalURL($0.element.url) != excluded }\n      .map { offset, document -> (Int, SimilarityHit) in\n        let vector: [Float]\n        if document.embeddingModelID == embedder.modelID, let saved = document.vector,\n          saved.count == embedder.dimensions, saved.allSatisfy(\\.isFinite) { vector = saved }\n        else { vector = embedder.embedDocument(title: document.title, content: document.content) }\n        let score = (embedder.cosine(queryVector, vector) + 1) / 2\n        return (offset, SimilarityHit(document: document, score: score))\n      }.sorted {\n        if $0.1.score != $1.1.score { return $0.1.score > $1.1.score }\n        if $0.1.document.retrievedAtMillis != $1.1.document.retrievedAtMillis {\n          return $0.1.document.retrievedAtMillis > $1.1.document.retrievedAtMillis\n        }\n        return $0.0 < $1.0\n      }.prefix(max(1, min(limit, Self.maxDocuments))).map { $0.1 }\n  }\n\n  func stats() -> AgentMcpJSONObject {"
  ],
  [
    "          (snapshot.learnedSources?.count ?? 0) <= AgentIOSWebSourceLearningPolicy.maximumSources,",
    "          snapshot.documents.count <= Self.maxDocuments,\n          snapshot.documents.allSatisfy({ ($0.vector?.count ?? 0) <= 2048 && ($0.vector ?? []).allSatisfy(\\.isFinite) }),\n          (snapshot.learnedSources?.count ?? 0) <= AgentIOSWebSourceLearningPolicy.maximumSources,"
  ]
];
function retainedEmbeddingCache(source) {
  if (require('./check-web-cache-index-scope.cjs').isIndexedCache(source)) return source;
  source = require('./check-source-health-index-scope.cjs').retainedHealthCache(source);
  if (!source.includes('  var embeddingModelID: String? = nil')) return source;
  for (const [before, after] of cacheHooks) {
    assert.equal(source.split(after).length, 2, 'Exactly one embedding cache hook: ' + before);
    source = source.replace(after, before);
  }
  return source;
}
const queryHook = [
  "    case \"query\":\n      documents = cacheStore.search(\n        query: string(input, \"query\", limit: 4_096),\n        limit: int(input, \"limit\", defaultValue: 10, minimum: 1, maximum: 100)\n      ).map { $0.value(includeContent: false) }\n      results = documents",
  "    case \"query\":\n      let query = string(input, \"query\", limit: 4_096)\n      guard !query.isEmpty else { return failure(\"invalid_query\", \"Cache similarity query requires non-empty text\") }\n      results = similarityResults(cacheStore.similarDocuments(query: query,\n        limit: int(input, \"limit\", defaultValue: 10, minimum: 1, maximum: 100)))\n      actionMetadata[\"embedding_model\"] = .string(AgentIOSWebFeatureHashEmbedder.standard.modelID)"
];
function retainedEmbeddingProvider(source) {
  source = require('./check-mixed-media-search-scope.cjs').retainedMixedSource(source);
  if (!source.includes('let local = cacheStore.similarDocuments(')) return source;
  const previous = show(base, app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  assert.equal(source.split(queryHook[1]).length, 2, 'One cache query vector projection hook');
  source = source.replace(queryHook[1], queryHook[0]);
  const section = value => value.slice(value.indexOf('  private func findSimilar('), value.indexOf('  private func watch('));
  return source.replace(section(source), section(previous));
}
module.exports = {retainedEmbeddingCache, retainedEmbeddingProvider};
if (require.main === module) {
  const cacheFile = app + 'AgentIOSWebIntelligenceCache.swift', providerFile = app + 'AgentIOSURLSessionWebIntelligenceProvider.swift';
  const indexed = require('./check-web-cache-index-scope.cjs');
  if (indexed.isIndexedCache(read(cacheFile))) indexed.validateIndexedCache();
  else assert.equal(retainedEmbeddingCache(read(cacheFile)), show(base, cacheFile), 'Only optional vectors, bounded validation, write embedding and local cosine lookup');
  assert.equal(retainedEmbeddingProvider(read(providerFile)), show(base, providerFile), 'Only find_similar projection/query/fallback changed');
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  for (const token of ['val dimensions: Int = 192', 'dimensions in 32..2_048', 'galaxyssi-feature-hash-$dimensions-v1',
    'normalized.substring(index, index + 3)', 'raw and Long.MAX_VALUE', 'sign * (1.0 + ln(1.0 + count)).toFloat()',
    'vector[it] /= norm', 'left[it].toDouble() * right[it].toDouble()']) assert(reference.includes(token), token);
  const service = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt');
  for (const token of ['document.content.take(32_000)', 'clean.take(64_000)', '(embedder.cosine(target, document.vector) + 1.0) / 2.0',
    'values.size < maxOf(3, limit / 2)', '"engine_fanout" to 12', '"embedding_model" to embedder.modelId']) assert(service.includes(token), token);
  const embedder = read(app + 'AgentIOSWebFeatureHashEmbedder.swift');
  for (const token of ['init(dimensions: Int = 192)', '(32...2048).contains(dimensions)', 'var modelID:',
    'NSRegularExpression(pattern: "[a-z0-9][a-z0-9_+.-]{1,}")', 'bodyLimit: Int = 64_000',
    'counts[feature, default: 0] += 1', 'for feature in order', 'isJVMWhitespace', 'SHA256.hash(data: Data(Self.jvmUTF8(feature)))',
    'raw & 0x7fff_ffff_ffff_ffff', 'raw & 0x8000_0000_0000_0000', 'Float(1 + log(1 + Double(counts[feature] ?? 0)))',
    'Double($1) * Double($1)', 'return vector.map { $0 / denominator }', 'scalar = 63', 'precomposedStringWithCompatibilityMapping.lowercased()'])
    assert(embedder.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebFeatureHashTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 10);
  for (const token of ['testJDKReferenceSparseFloatBits', 'testLegacyDocumentsReembed', 'testActualRegistryLocalSimilarity',
    'testURLSelectionOverridesQuery', 'testCacheOnlyScopeCannotFetchUncachedURLOrRunOptionalSearch', 'testActualCacheQueryUsesSameLocalCosineScores', 'testEncryptedDocumentVectors', 'XCTAssertNil(match.document.vector)',
    'XCTAssertEqual(Set(urls).count, urls.count)', 'doubleForSchema']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  const provider = read(providerFile);
  for (const token of ['guard networkAllowed else {', '?? true, networkAllowed {',
    'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent)',
    'resultMetadata["network_fallback_skipped"] = .string("public_web_scope_required")']) assert(provider.includes(token), token);
  for (const name of ['AgentIOSWebFeatureHashEmbedder', 'AgentIOSWebFeatureHashTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
  // The JDK generator emits reference data, not an execution of the iOS implementation.
  const goldens = JSON.parse(cp.execFileSync('java', ['apps/ios/tools/WebFeatureHashReference.java'], {cwd: root, encoding: 'utf8'}));
  assert.equal(goldens.length, 8);
  for (const golden of goldens) {
    const row = tests.split('\n').find(line => line.includes('"' + golden.label + '": ['));
    assert(row, golden.label);
    for (const [index, bits] of golden.bits) assert(row.includes(index + ': ' + bits), golden.label + ' Float32 bit vector');
    assert.equal((row.match(/: \d+/g) || []).length, golden.bits.length);
  }
  for (const file of ['AgentIOSURLSessionWebMediaProvider.swift', 'AgentIOSWebIntelligenceSourceCatalog.swift',
    'AgentIOSWebSourceHealth.swift', 'AgentIOSWebSearchFusion.swift', 'AgentIOSImageSearchRequestPolicy.swift',
    'AgentIOSWebExecutionBudget.swift', 'AgentIOSPublicSearchParser.swift']) assert.equal(
      require('./check-mixed-media-search-scope.cjs').retainedMixedSource(read(app + file)), show(base, app + file), file);
  console.log('Pinned hash arithmetic/tokens, 8 JDK reference datasets, optional vector storage, cosine wiring and retained transport/cache response source guards passed. No native execution or speed/relevance acceptance.');
}

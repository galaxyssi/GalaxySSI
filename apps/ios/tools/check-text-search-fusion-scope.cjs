// Source contracts only, not Swift execution or statistical/live-search acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ef89c182b8dd9ac2c8cca1d403ba22af90bb0ba9', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const norm = text => text.replace(/\r\n/g, '\n');
const read = file => norm(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
function once(text, before, after = '') {
  assert.equal(text.split(before).length, 2, 'One declared fusion hook: ' + before);
  return text.replace(before, after);
}
function section(text, start, end) {
  const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start); return text.slice(first, last);
}
function retainedFusionHit(text) {
  return text.replace('    var publishedAt = ""\n    var searchScore: AgentIOSWebSearchFusion.Score? = nil\n    var searchEngines: [String] = []\n', '');
}
function retainedTextFusionProvider(text) {
  text = require('./check-automatic-search-routing-scope.cjs').retainedAutoRoutingProvider(text);
  const before = show(base, app + 'AgentIOSURLSessionWebMediaProvider.swift');
  text = once(text, '      var merged: [AgentIOSWebSearchResult] = []\n', '      var merged: [AgentIOSWebSearchResult] = []\n      var seenURLs: Set<String> = []\n');
  text = once(text, section(text, '      if !imageSearch {\n        merged = AgentIOSWebSearchFusion.fuse', '      var output = first.resource'),
    section(before, '      for attempt in attempts where !imageSearch', '      var output = first.resource'));
  text = once(text, '        if !result.publishedAt.isBlank { value["published_at"] = .string(String(result.publishedAt.prefix(64))) }\n        if let score = result.searchScore {\n          value["score"] = .object(score.value)\n          value["engines"] = .array(result.searchEngines.map(AgentMcpJSONValue.string))\n        }\n');
  return once(text, '      else { resultMetadata["text_ranker"] = .string(AgentIOSWebSearchFusion.modelID) }\n');
}
function retainedTextFusionIntelligence(text) {
  text = require('./check-search-response-cache-scope.cjs').retainedResponseSearch(text);
  text = once(text, '      var result: AgentMcpJSONObject = [\n        "rank": .int(Int64(rank)),\n        "title": .string(document.title),', '      let result: AgentMcpJSONObject = [\n        "rank": .int(Int64(rank)),\n        "title": .string(document.title),');
  text = once(text, '      var evidence: AgentMcpJSONObject = [\n        "id": .string(evidenceId(url: document.url, rank: rank)),', '      let evidence: AgentMcpJSONObject = [\n        "id": .string(evidenceId(url: document.url, rank: rank)),');
  for (const block of [
    '      if let published = document.metadata["published_at"], !published.isBlank {\n        result["published_at"] = .string(String(published.prefix(64)))\n        evidence["published_at"] = result["published_at"]\n      }\n',
    '      var documentMetadata = ["source": "web_search"]\n      if let published = item.result["published_at"]?.stringValue, !published.isBlank {\n        documentMetadata["published_at"] = String(published.prefix(64))\n      }\n',
    '      if let published = object["published_at"]?.stringValue, !published.isBlank {\n        result["published_at"] = .string(String(published.prefix(64)))\n        evidence["published_at"] = result["published_at"]\n      }\n      if let score = object["score"]?.objectValue {\n        result["score"] = .object(score)\n        evidence["score"] = .object(score)\n        result["engines"] = object["engines"]\n        evidence["engines"] = object["engines"]\n      }\n'
  ]) text = once(text, block);
  text = once(text, 'links: [], metadata: documentMetadata', 'links: [], metadata: ["source": "web_search"]');
  return once(text, '"selected_learned_sources", "official_sources", "text_ranker"', '"selected_learned_sources", "official_sources"');
}
module.exports = {retainedFusionHit, retainedTextFusionProvider, retainedTextFusionIntelligence};
if (require.main === module) {
  const providerFile = app + 'AgentIOSURLSessionWebMediaProvider.swift';
  assert.equal(retainedTextFusionProvider(read(providerFile)), show(base, providerFile), 'Only text fusion/output metadata changes; transport, image, routes and health retained');
  const intelligenceFile = app + 'AgentIOSURLSessionWebIntelligenceProvider.swift';
  assert.equal(retainedTextFusionIntelligence(read(intelligenceFile)), show(base, intelligenceFile), 'Only publication metadata and current-result score projection');
  const parserFile = app + 'AgentIOSPublicSearchParser.swift';
  assert.equal(retainedFusionHit(read(parserFile)), show(base, parserFile), 'Only optional hit metadata, no generic parser relaxation');
  let json = read(app + 'AgentIOSJSONWebSearchAdapter.swift');
  json = once(json, section(json, '    func publication(', '    func first('));
  json = once(json, 'var title = "", url = "", excerpt = "", publishedAt = ""', 'var title = "", url = "", excerpt = ""');
  for (const line of ['        publishedAt = publication(row["updated_at"])', '        publishedAt = publication(repo["updated_at"])',
    '        publishedAt = publication(row["last_activity_at"])', '        publishedAt = publication(row["last_activity_date"])',
    '        publishedAt = publication(row["created_at"])', '        if source == "lobsters" { publishedAt = publication(row["created_at"]) }',
    '        publishedAt = publication(row["created_utc"])', '        publishedAt = publication(row["year"])', '        publishedAt = publication(row["date"])']) {
    assert(json.includes(line), line); json = json.replaceAll(line + '\n', '');
  }
  json = once(json, ', publishedAt: publishedAt)', ')');
  assert.equal(json, show(base, app + 'AgentIOSJSONWebSearchAdapter.swift'), 'Other JSON/header/validation logic retained');
  let atom = read(app + 'AgentIOSArxivSearchAdapter.swift');
  atom = once(atom, '["title", "summary", "id", "published"]', '["title", "summary", "id"]');
  atom = once(atom, '.text().prefix(2048)),\n                  publishedAt: String((fields["published"] ?? "").prefix(64))))', '.text().prefix(2048))))');
  assert.equal(atom, show(base, app + 'AgentIOSArxivSearchAdapter.swift'), 'Only Atom publication captured; XML guards unchanged');
  const asset = JSON.parse(show(android, 'apps/android/app/src/main/assets/web-intelligence/ranker-v1.json'));
  const image = read(app + 'AgentIOSImageSearchFusion.swift');
  assert.deepEqual(JSON.parse('[' + image.match(/static let weights = \[([^\]]+)\]/)[1] + ']'), asset.weights);
  const fusion = read(app + 'AgentIOSWebSearchFusion.swift');
  for (const token of ['AgentIOSImageSearchFusion.rankerScore([rrf, lexical, consensus, item.authority, recency,',
    'exactness, max(titleOverlap, bodyOverlap), urlQuality(item.hit.url), penalty]', '0.28 * rrf + 0.21 * lexical + 0.14 * consensus',
    '0.10 * item.authority + 0.07 * recency + 0.20 * local', 'item.ranks.keys.sorted().reduce', 'Double(item.ranks.count - 8) / 16',
    'number > 10_000_000_000 ? number / 1000 : number', 'return 0.35', '.prefix(min(limit, 100))']) assert(fusion.includes(token), token);
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  for (const token of ['0.28 * reciprocalRank', '0.21 * lexical', '0.14 * consensus', '0.10 * item.authority', '0.07 * freshness', '0.20 * localModel']) assert(reference.includes(token), token);
  for (const name of ['AgentIOSImageSearchFusion', 'AgentIOSImageSearchRequestPolicy', 'AgentIOSWebExecutionBudget', 'AgentIOSWebSourceHealth',
    'AgentIOSWebIntelligenceCache', 'AgentIOSWebIntelligenceSourceCatalog', 'AgentIOSHTMLWebSearchAdapter']) {
    const current = require('./check-search-response-cache-scope.cjs').retainedResponseCache(read(app + name + '.swift'));
    assert.equal(name === 'AgentIOSWebIntelligenceSourceCatalog'
      ? require('./check-automatic-search-routing-scope.cjs').retainedAutoRoutingCatalog(current) : current,
      show(base, app + name + '.swift'), name);
  }
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebSearchFusionTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 14);
  for (const token of ['testActualRegistryRanksWithinOneProvider', 'testCachedPublicationIsPreserved', 'XCTAssertNil(row["published_at"])', 'String(year)', 'weight: .nan']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebSearchFusion', 'AgentIOSWebSearchFusionTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3);
  console.log('Pinned text fusion/date/cache metadata source contracts passed; image/transport/selection/cache-store policies retained. No native build, XCTest, relevance or performance acceptance.');
}

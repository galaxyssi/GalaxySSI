// Source contracts only: no Swift execution or live media/relevance acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '6ce96ba0fefa4a22697a39058a870fb583b251a6', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const norm = value => value.replace(/\r\n/g, '\n');
const read = file => norm(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const hooks = {
  "raw": [
    [
      "      let imageSearch = verticalIds.contains(\"image\") || engineIds.contains(where: { $0.hasSuffix(\"_image\") })\n      if imageSearch, (!engineIds.isEmpty && !engineIds.isSubset(of: AgentIOSImageSearchRequestPolicy.supported)) ||\n         (!verticalIds.isEmpty && verticalIds != [\"image\"]) {\n        throw AgentIOSURLSessionWebError.unsupportedImageEngine\n      }",
      "      let imageSearch = (engineIds.isEmpty && verticalIds == [\"image\"]) ||\n        (!engineIds.isEmpty && engineIds.isSubset(of: AgentIOSImageSearchRequestPolicy.supported))"
    ],
    [
      "        learnedSources: imageSearch ? [] : learned,",
      "        learnedSources: learned,"
    ],
    [
      "        nowMillis: nowMillis()\n      )",
      "        nowMillis: nowMillis(),\n        braveImageKeyAvailable: (verticalIds.contains(\"image\") || engineIds.contains(\"brave_image\")) &&\n          AgentIOSImageSearchRequestPolicy.validBraveKey(imageCredentials.credential(.braveAPIKey))\n      )"
    ],
    [
      "        requestedEngineIds: requestedEngines\n      )",
      "        requestedEngineIds: imageSearch ? routing.selected.map(\\.id) : requestedEngines\n      )"
    ],
    [
      "      let selection = imageSearch\n        ? AgentIOSWebSourceHealthRouting.select(providers: candidates.map(\\.provider),\n          preferred: [], health: health ?? [:], explicit: explicitSources,\n          fanout: Int(min(max(input[\"engine_fanout\"]?.intValue ?? 6, 1), 32)), now: nowMillis())\n        : AgentIOSWebSourceHealthRouting.Selection(selected: routing.selected.map(\\.id), skipped: routing.skipped)",
      "      let selection = AgentIOSWebSourceHealthRouting.Selection(selected: routing.selected.map(\\.id), skipped: routing.skipped)"
    ],
    [
      "          let attemptStarted = nowMillis()",
      "          if endpoint.provider == \"brave_image\",\n            !AgentIOSImageSearchRequestPolicy.validBraveKey(imageCredentials.credential(.braveAPIKey)) {\n            accumulator.append(AgentIOSWebSearchAttempt(index: index, provider: endpoint.provider, error: .sourceCredentialRequired))\n            return\n          }\n          let attemptStarted = nowMillis()"
    ],
    [
      "      var merged: [AgentIOSWebSearchResult] = []\n      if imageSearch {\n        merged = AgentIOSImageSearchFusion.fuse(query: query, groups: attempts.filter { $0.resource != nil }.map {\n          .init(sourceID: $0.provider, results: $0.results,\n            weight: AgentIOSImageSearchRequestPolicy.weight($0.provider), authority: AgentIOSImageSearchRequestPolicy.authority($0.provider))\n        }, limit: maxResults)\n      }\n      if !imageSearch {\n        merged = AgentIOSWebSearchFusion.fuse(query: query, groups: attempts.filter { $0.resource != nil || $0.localIndex }.map {\n          AgentIOSWebSearchFusion.group(sourceID: $0.provider, results: $0.results)\n        }, limit: maxResults, nowMillis: nowMillis())\n      }",
      "      let merged = AgentIOSWebSearchFusion.fuse(query: query,\n        groups: attempts.filter { $0.resource != nil || $0.localIndex }.map { attempt in\n          AgentIOSWebSearchFusion.group(sourceID: attempt.provider, results: attempt.results,\n            verticalOverride: routing.selected.first { $0.id == attempt.provider }?.vertical)\n        }, limit: maxResults, nowMillis: nowMillis(), includeImages: true)"
    ],
    [
      "        if let image = result.image {\n          value[\"vertical\"] = .string(\"image\")",
      "        if let vertical = result.vertical { value[\"vertical\"] = .string(vertical) }\n        if let image = result.image {\n          value[\"vertical\"] = .string(result.vertical ?? \"image\")"
    ],
    [
      "      if imageSearch { resultMetadata[\"image_ranker\"] = .string(AgentIOSImageSearchFusion.modelID) }\n      else { resultMetadata[\"text_ranker\"] = .string(AgentIOSWebSearchFusion.modelID) }",
      "      let hasMediaResults = merged.contains { $0.image != nil }\n      let hasPageResults = merged.contains { $0.image == nil }\n      if hasMediaResults { resultMetadata[\"image_ranker\"] = .string(AgentIOSImageSearchFusion.modelID) }\n      if hasPageResults { resultMetadata[\"text_ranker\"] = .string(AgentIOSWebSearchFusion.modelID) }\n      if hasMediaResults && hasPageResults {\n        resultMetadata[\"mixed_ranker\"] = .string(AgentIOSWebSearchFusion.modelID)\n      }"
    ],
    [
      "        : requestedEngineIds\n      if providers.contains(\"brave_image\"), !AgentIOSImageSearchRequestPolicy.validBraveKey(braveKey) {\n        throw AgentIOSURLSessionWebError.sourceCredentialRequired\n      }\n      return try providers.map { provider in",
      "        : requestedEngineIds\n      return try providers.map { provider in"
    ],
    [
      "    var endpoints = try routing.selected.filter { !selectedRootIDs.contains($0.id) }.map { source -> AgentIOSWebSearchEndpoint in",
      "    var endpoints = try routing.selected.filter { !selectedRootIDs.contains($0.id) }.map { source -> AgentIOSWebSearchEndpoint in\n      if AgentIOSImageSearchRequestPolicy.supported.contains(source.id) {\n        return try searchEndpoints(query: query, maxResults: maxResults, routing: routing,\n          imageSearch: true, requestedEngineIds: [source.id])[0]\n      }"
    ]
  ],
  "catalog": [
    [
      "    nowMillis: Int64 = 0",
      "    nowMillis: Int64 = 0,\n    braveImageKeyAvailable: Bool = false"
    ],
    [
      "    let eligible = catalog.filter {\n      $0.enabledByDefault && ((AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.contains($0.id) && general.contains($0.vertical)) ||\n        requestedVerticals.contains($0.vertical) || !categories.isDisjoint(with: $0.categoryTags))\n    }",
      "    let imageOnly = requestedVerticals == [.image]\n    let eligible = catalog.filter {\n      $0.enabledByDefault && (imageOnly ||\n        (AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.contains($0.id) && general.contains($0.vertical)) ||\n        requestedVerticals.contains($0.vertical) || !categories.isDisjoint(with: $0.categoryTags))\n    }.filter { !imageOnly || AgentIOSImageSearchRequestPolicy.supported.contains($0.id) }\n      .filter { $0.id != \"brave_image\" || braveImageKeyAvailable }"
    ],
    [
      "      let weight = [\"bing\", \"baidu\", \"duckduckgo\"].contains(source.id) ? 1.05 : (source.id == \"bing_news\" ? 1.1 : 1)",
      "      let weight = source.id == \"sogou_image\" ? 1.2 :\n        ([\"bing\", \"baidu\", \"duckduckgo\"].contains(source.id) ? 1.05 : (source.id == \"bing_news\" ? 1.1 : 1))"
    ],
    [
      "      .init(id: \"baidu\", title: \"Baidu\", vertical: .regional, allowedHosts: [], authority: 0.5, languages: [\"zh\"])",
      "      .init(id: \"baidu\", title: \"Baidu\", vertical: .regional, allowedHosts: [], authority: 0.5, languages: [\"zh\"]),\n      .init(id: \"sogou_image\", title: \"Sogou Images\", vertical: .image, allowedHosts: [], authority: 0.75),\n      .init(id: \"brave_image\", title: \"Brave Image\", vertical: .image, allowedHosts: [], authority: 0.8),\n      .init(id: \"duckduckgo_image\", title: \"DuckDuckGo Image\", vertical: .image, allowedHosts: [], authority: 0.75)"
    ],
    [
      "    let catalog = orderedTextSources + learned",
      "    let catalog = orderedSources + learned"
    ],
    [
      "  private static var orderedTextSources: [AgentIOSWebIntelligenceSourceSpec] {",
      "  private static var orderedSources: [AgentIOSWebIntelligenceSourceSpec] {"
    ]
  ],
  "fusion": [
    [
      "    var authority: Double = 0.5\n  }",
      "    var authority: Double = 0.5\n    var vertical: AgentIOSWebIntelligenceVertical = .general\n  }"
    ],
    [
      "  static func group(sourceID: String, results: [Hit]) -> Group {",
      "  static func group(sourceID: String, results: [Hit], verticalOverride: AgentIOSWebIntelligenceVertical? = nil) -> Group {"
    ],
    [
      "    let weight = [\"bing\", \"baidu\", \"duckduckgo\"].contains(sourceID) ? 1.05 : (sourceID == \"bing_news\" ? 1.1 : 1)\n    // Android fusion's immutable catalog uses the unknown-source prior for learned adapters.\n    return Group(sourceID: sourceID, results: results, weight: weight, authority: spec?.authority ?? 0.5)",
      "    let imageSource = AgentIOSImageSearchRequestPolicy.supported.contains(sourceID)\n    let weight = imageSource ? AgentIOSImageSearchRequestPolicy.weight(sourceID) :\n      ([\"bing\", \"baidu\", \"duckduckgo\"].contains(sourceID) ? 1.05 : (sourceID == \"bing_news\" ? 1.1 : 1))\n    // Learned adapters retain the immutable catalog's unknown-source fusion authority prior.\n    return Group(sourceID: sourceID, results: results, weight: weight,\n      authority: imageSource ? AgentIOSImageSearchRequestPolicy.authority(sourceID) : spec?.authority ?? 0.5,\n      vertical: verticalOverride ?? (imageSource ? .image : spec?.vertical ?? .general))"
    ],
    [
      "  static func fuse(query: String, groups: [Group], limit: Int, nowMillis: Int64) -> [Hit] {",
      "  static func fuse(query: String, groups: [Group], limit: Int, nowMillis: Int64, includeImages: Bool = false) -> [Hit] {"
    ],
    [
      "        guard hit.image == nil, !hit.title.isBlank, let parts = URLComponents(string: hit.url),",
      "        guard (includeImages || hit.image == nil), !hit.title.isBlank, let parts = URLComponents(string: hit.url),"
    ],
    [
      "        let key = AgentIOSWebEvidencePack.canonicalURL(hit.url)",
      "        let page = AgentIOSWebEvidencePack.canonicalURL(hit.url)\n        let media = (hit.image?[\"url\"]?.stringValue).flatMap(AgentIOSWebEvidencePack.mediaURL)\n        if hit.image != nil && media == nil { continue }\n        let key = media.map(AgentIOSWebEvidencePack.canonicalURL) ?? page"
    ],
    [
      "          var canonical = hit; canonical.url = key",
      "          var canonical = hit; canonical.url = page\n          canonical.vertical = hit.vertical ?? group.vertical.rawValue\n          if canonical.vertical == \"image\", canonical.image == nil { canonical.retrievalStatus = \"image_topic_page_reference\" }"
    ],
    [
      "        if item.hit.publishedAt.isBlank { item.hit.publishedAt = hit.publishedAt }",
      "        if item.hit.publishedAt.isBlank { item.hit.publishedAt = hit.publishedAt }\n        if item.hit.vertical == \"general\", group.vertical != .general { item.hit.vertical = group.vertical.rawValue }\n        if item.hit.image == nil { item.hit.image = hit.image }\n        else if let incoming = hit.image {\n          var merged = item.hit.image ?? [:]\n          if merged[\"thumbnail_url\"]?.stringValue?.isEmpty ?? true, let thumbnail = incoming[\"thumbnail_url\"] {\n            merged[\"thumbnail_url\"] = thumbnail\n          }\n          for dimension in [\"width\", \"height\"] where (merged[dimension]?.intValue ?? 0) <= 0 {\n            if let value = incoming[dimension] { merged[dimension] = value }\n          }\n          item.hit.image = merged\n        }\n        if item.hit.image != nil, item.hit.retrievalStatus == \"image_topic_page_reference\" { item.hit.retrievalStatus = nil }"
    ],
    [
      "      let final = min(1, max(0, 0.28 * rrf + 0.21 * lexical + 0.14 * consensus + 0.10 * item.authority + 0.07 * recency + 0.20 * local))",
      "      let webScore = min(1, max(0, 0.28 * rrf + 0.21 * lexical + 0.14 * consensus + 0.10 * item.authority + 0.07 * recency + 0.20 * local))\n      let specificity = titles.isEmpty ? 0 : Double(queryTokens.intersection(titles).count) / Double(titles.count)\n      let final = item.hit.vertical == \"image\" ? 0.45 * webScore + 0.35 * titleOverlap + 0.20 * specificity : webScore"
    ],
    [
      "    return candidates.sorted {",
      "    let ranked = candidates.sorted {"
    ],
    [
      "    }.prefix(min(limit, 100)).map(\\.hit)",
      "    }\n    if !ranked.isEmpty && ranked.allSatisfy({ $0.hit.vertical == \"image\" }) {\n      var pages = Set<String>(), first: [Candidate] = [], remaining: [Candidate] = []\n      for item in ranked {\n        if pages.insert(item.hit.url).inserted { first.append(item) } else { remaining.append(item) }\n      }\n      return (first + remaining).prefix(min(limit, 100)).map(\\.hit)\n    }\n    return ranked.prefix(min(limit, 100)).map(\\.hit)"
    ]
  ],
  "upper": [
    [
      "      \"image_routing\": .string(\"direct_media_subject_v2\"),\n      \"web_routing\": .string(\"language_scoped_result_cards_v5\"),",
      "      \"image_routing\": .string(\"ios_mixed_media_subject_v3\"),\n      \"web_routing\": .string(\"ios_mixed_typed_cards_v6\"),"
    ],
    [
      "      if object[\"vertical\"] == .string(\"image\"), let images = object[\"images\"]?.arrayValue {\n        result[\"vertical\"] = .string(\"image\")",
      "      if let vertical = object[\"vertical\"] { result[\"vertical\"] = vertical; evidence[\"vertical\"] = vertical }\n      if let images = object[\"images\"]?.arrayValue, !images.isEmpty {\n        result[\"vertical\"] = object[\"vertical\"] ?? .string(\"image\")"
    ],
    [
      "                  \"selected_learned_sources\", \"official_sources\", \"text_ranker\"] {",
      "                  \"selected_learned_sources\", \"official_sources\", \"text_ranker\", \"image_ranker\", \"mixed_ranker\"] {"
    ],
    [
      "      if object[\"retrieval_status\"] == .string(\"local_index_reference\") {",
      "      if object[\"retrieval_status\"] == .string(\"local_index_reference\") ||\n        object[\"retrieval_status\"] == .string(\"image_topic_page_reference\") {"
    ],
    [
      "        result[\"retrieval_status\"] = .string(\"local_index_reference\")\n        evidence[\"retrieval_status\"] = .string(\"local_index_reference\")",
      "        result[\"retrieval_status\"] = object[\"retrieval_status\"]\n        evidence[\"retrieval_status\"] = object[\"retrieval_status\"]"
    ]
  ],
  "parser": [
    [
      "    var image: AgentMcpJSONObject? = nil",
      "    var image: AgentMcpJSONObject? = nil\n    var vertical: String? = nil"
    ]
  ],
  "learning": [
    [
      "    return isValid && !AgentIOSWebSourceLearningPolicy.isBuiltInHost(host) && status == \"verified\" && vertical != \"image\" &&",
      "    return isValid && !AgentIOSWebSourceLearningPolicy.isBuiltInHost(host) && status == \"verified\" &&"
    ]
  ]
};
function retainedMixedSource(source) {
  source = require('./check-public-address-policy-scope.cjs').retainedAddressProvider(source);
  let kind;
  if (source.includes('let merged = AgentIOSWebSearchFusion.fuse')) kind = 'raw';
  else if (source.includes('braveImageKeyAvailable: Bool = false')) kind = 'catalog';
  else if (source.includes('includeImages: Bool = false')) kind = 'fusion';
  else if (source.includes('ios_mixed_typed_cards_v6')) kind = 'upper';
  else if (source.includes('enum AgentIOSPublicSearchParser') && source.includes('    var vertical: String? = nil')) kind = 'parser';
  else if (source.includes('struct AgentIOSLearnedWebSource') &&
    source.includes('status == "verified" &&\n      observations')) kind = 'learning';
  if (!kind) return source;
  for (const [before, after] of hooks[kind]) {
    assert(after.length > 0);
    assert.equal(source.split(after).length, 2, 'One declared mixed ' + kind + ' hook: ' + after);
    source = source.replace(after, before);
  }
  return source;
}
module.exports = {retainedMixedSource};
if (require.main === module) {
  const files = ['AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebIntelligenceSourceCatalog',
    'AgentIOSWebSearchFusion', 'AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSPublicSearchParser', 'AgentIOSWebSourceLearning'];
  for (const name of files) assert.equal(retainedMixedSource(read(app + name + '.swift')), show(base, app + name + '.swift'), name);
  const ref = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  for (const token of ['desired != setOf(AgentWebIntelligenceVertical.IMAGE)', 'spec.parser in AgentPublicImageSearchParser.directParsers',
    'spec.requiresKey.isBlank()', '0.45 * webScore + 0.35 * titleOverlap + 0.20 * titleSpecificity',
    'ranked.all { it.vertical == AgentWebIntelligenceVertical.IMAGE }',
    'raw.vertical == AgentWebIntelligenceVertical.IMAGE && raw.imageUrl.isNotBlank()']) assert(ref.includes(token), token);
  const provider = read(app + 'AgentIOSURLSessionWebMediaProvider.swift');
  for (const token of ['learnedSources: learned', 'braveImageKeyAvailable:', 'let selection = AgentIOSWebSourceHealthRouting.Selection',
    'error: .sourceCredentialRequired', 'imageSearch ? routing.selected.map(\\.id) : requestedEngines',
    'verticalOverride: routing.selected.first', 'includeImages: true', 'value["vertical"] = .string(result.vertical ?? "image")'])
    assert(provider.includes(token), token);
  assert(!provider.includes('if imageSearch, (!engineIds.isEmpty'));
  const fusion = read(app + 'AgentIOSWebSearchFusion.swift');
  for (const token of ['media.map(AgentIOSWebEvidencePack.canonicalURL) ?? page', 'canonical.url = page',
    'item.hit.vertical == "image" ? 0.45 * webScore', 'ranked.allSatisfy({ $0.hit.vertical == "image" })',
    'item.ranks.keys.sorted()', 'image_topic_page_reference', 'AgentIOSWebEvidencePack.mediaURL',
    'if hit.image != nil && media == nil { continue }']) assert(fusion.includes(token), token);
  const upper = read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  for (const token of ['ios_mixed_media_subject_v3', 'ios_mixed_typed_cards_v6',
    'if let images = object["images"]?.arrayValue, !images.isEmpty',
    'result["retrieval_status"] = object["retrieval_status"]']) assert(upper.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSMixedWebSearchTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const token of ['testImageOnlyRoutingUsesDirectParsers', 'testMixedFusionUsesOneConsensusDenominator',
    'testPageDiversityAppliesOnlyWhenAllCandidatesAreImageVertical', 'testActualMixedRegistryPreservesTextAndTypedImages',
    'testUnconfiguredImageSourceDoesNotPreventRequestedTextResults', 'testActualLearnedImageTopicIndexDoesNotInventMedia',
    'XCTAssertNil(row["images"])', 'XCTAssertNil(row["lead_image_url"])', 'XCTAssertNil(request.headers["X-Subscription-Token"])'])
    assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split('AgentIOSMixedWebSearchTests.swift in Sources */').length, 3);
  for (const file of ['AgentIOSWebIntelligenceCache.swift', 'AgentIOSWebExecutionBudget.swift', 'AgentIOSWebSourceHealth.swift',
    'AgentIOSImageSearchRequestPolicy.swift', 'AgentIOSJSONWebSearchAdapter.swift', 'AgentIOSImageSearchFusion.swift',
    'AgentIOSWebFeatureHashEmbedder.swift']) assert.equal(read(app + file), show(base, app + file), file);
  console.log('Pinned mixed/direct/learned-image routing, one global fusion score, typed-media/topic distinction and unchanged network/header/cache controls checked as source. No native execution or live media acceptance.');
}

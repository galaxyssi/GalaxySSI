// Source contracts only. Not Swift type checking, XML security or live search acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '964a57a7139f410391ed38a0a0fe4cb8f326278c', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const normalize = value => value.replace(/\r\n/g, '\n');
const read = file => {
  const hooks = require('./check-search-response-cache-scope.cjs');
  return hooks.retainedResponseCache(hooks.retainedResponseSearch(normalize(fs.readFileSync(path.join(root, file), 'utf8'))));
};
const show = (ref, file) => normalize(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
function retainedAdditionalProvider(source) {
  if (source.includes('merged = AgentIOSWebSearchFusion.fuse')) {
    source = require('./check-text-search-fusion-scope.cjs').retainedTextFusionProvider(source);
  }
  for (const [before, after] of [
    ['          if endpoint.localIndex {\n            accumulator.append(AgentIOSWebSearchAttempt(index: index, provider: endpoint.provider,\n              results: AgentIOSDevDocsSearchAdapter.search(query, limit: maxResults), didStart: true,\n              durationMillis: AgentIOSWebSourceHealth.elapsed(from: attemptStarted, to: nowMillis()), localIndex: true))\n            return\n          }\n', ''],
    ['            } else if endpoint.specialistParser == "arxiv" {\n              results = try AgentIOSArxivSearchAdapter.parse(resource.body, limit: maxResults,\n                isCancelled: { searchInvocation.isCancellationRequested })\n              if searchInvocation.isTimedOut { throw AgentIOSURLSessionWebError.timeout }\n            } else if let parser = endpoint.specialistParser {\n              results = try AgentIOSHTMLWebSearchAdapter.parse(html, id: parser, baseURL: resource.finalURL, limit: maxResults)\n', ''],
    ['      guard let first = attempts.first(where: { !$0.results.isEmpty }) else {', '      guard let first = attempts.first(where: { !$0.results.isEmpty }),\n            let resource = first.resource else {'],
    ['for attempt in attempts where !imageSearch && (attempt.resource != nil || attempt.localIndex)', 'for attempt in attempts where !imageSearch && attempt.resource != nil'],
    ['      var output = first.resource.map(commonOutput) ?? ["retrieval_status": .string("local_index_reference")]', '      var output = commonOutput(resource)'],
    ['        if let status = result.retrievalStatus { value["retrieval_status"] = .string(status) }\n', ''],
    ['      if source.id == AgentIOSDevDocsSearchAdapter.entry.id {\n        guard let url = URL(string: AgentIOSDevDocsSearchAdapter.entry.template) else { throw AgentIOSURLSessionWebError.invalidURL }\n        return AgentIOSWebSearchEndpoint(provider: source.id, url: url, localIndex: true)\n      }\n      if let adapter = AgentIOSHTMLWebSearchAdapter.entry(source.id) ??\n        (source.id == AgentIOSArxivSearchAdapter.entry.id ? AgentIOSArxivSearchAdapter.entry : nil) {\n        let url = try AgentIOSJSONWebSearchAdapter.requestURL(adapter, query: query, limit: maxResults)\n        return AgentIOSWebSearchEndpoint(provider: source.id,\n          url: try validatedPublicHTTPSURL(url.absoluteString), specialistParser: source.id)\n      }\n', ''],
    ['  var specialistParser: String? = nil\n  var localIndex = false\n', ''],
    ['  var localIndex: Bool\n', ''],
    ['    durationMillis: Int64 = 0,\n    localIndex: Bool = false', '    durationMillis: Int64 = 0'],
    ['    self.localIndex = localIndex\n', ''],
    ['        result.metadata["local_index_only"] = .bool(endpoints.allSatisfy(\\.localIndex))\n', '']
  ]) {
    assert.equal(source.split(before).length, 2, 'Exactly one additional adapter hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}
module.exports = {retainedAdditionalProvider};
if (require.main === module) {
  const file = app + 'AgentIOSURLSessionWebMediaProvider.swift', provider = read(file);
  assert.equal(retainedAdditionalProvider(provider), show(base, file), 'Only specialist/local-index dispatch and truthful result hooks changed');
  const ref = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  const html = read(app + 'AgentIOSHTMLWebSearchAdapter.swift'), atom = read(app + 'AgentIOSArxivSearchAdapter.swift'), local = read(app + 'AgentIOSDevDocsSearchAdapter.swift');
  const json = read(app + 'AgentIOSJSONWebSearchAdapter.swift');
  const entryBlock = ref.slice(ref.indexOf('val entries: List<AgentWebIntelligenceEngineSpec> = listOf('), ref.indexOf(') + indexedSources.mapIndexed'));
  const referenceIDs = [...entryBlock.matchAll(/\bspec\(\s*"([^"]+)"/g)].map(match => match[1]);
  assert.equal(referenceIDs.length, 41, 'Pinned implementation has 41 entries, not the obsolete 40 count');
  const ids = [...(html + json).matchAll(/\.init\(id: "([^"]+)"/g)].map(match => match[1]);
  const registered = ['bing', 'baidu', 'duckduckgo', 'sogou_image', 'brave_image', 'duckduckgo_image', 'arxiv', 'devdocs', ...ids];
  assert.deepEqual([...registered].sort(), [...referenceIDs].sort(), 'Every pinned base engine registered exactly once');
  assert.equal(new Set(registered).size, 41);
  const indexed = JSON.parse(read(app + 'web-indexed-sources.json')).sources;
  assert.equal(new Set([...registered, ...indexed.map(row => row.id)]).size, 288);
  const templates = [...(html + atom).matchAll(/template: "([^"]+)"/g)].map(match => match[1]);
  assert.equal(templates.length, 18);
  for (const template of templates) assert(entryBlock.includes('"' + template + '"'), template);
  const docs = [...local.matchAll(/\.init\(title: "([^"]+)", slug: "([^"]+)", aliases: \[([^\]]+)\]\)/g)];
  assert.equal(docs.length, 22);
  for (const [, title, slug, aliases] of docs) assert(ref.includes('DevDocsEntry("' + title + '", "' + slug + '", setOf(' + aliases + '))'), title);
  const catalog = read(app + 'AgentIOSWebIntelligenceSourceCatalog.swift');
  assert(catalog.includes('$0.enabledByDefault && ((AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.contains'));
  assert(html.includes('enabledByDefault: false'));
  assert(html.includes('.filter { accepts($0.url, id: id) }.prefix(min(limit, 100))'));
  for (const token of ['"/status/"', '"mp.weixin.qq.com"', '"zhuanlan.zhihu.com"', '"/explore/"', '"/discovery/item/"']) assert(html.includes(token), token);
  for (const token of ['XMLParser(data: data)', 'parser.shouldResolveExternalEntities = false', '"<!DOCTYPE"', 'data.count <= 2_097_152',
    'depth <= 32', 'value.utf8.count <= 32_768', 'resolveExternalEntityName', 'if delegate.cancelled']) assert(atom.includes(token), token);
  assert(provider.indexOf('if endpoint.localIndex') < provider.indexOf('let resource = try requestResource(', provider.indexOf('if endpoint.localIndex')), 'Local branch exits before request');
  assert(local.includes('retrievalStatus: "local_index_reference"'));
  assert(!local.includes('URLSession') && !local.includes('Data(contentsOf:'));
  const policy = 'struct AgentIOSJSONWebSearchRequestPolicy';
  assert.equal(json.slice(json.indexOf(policy)), show(base, app + 'AgentIOSJSONWebSearchAdapter.swift').slice(show(base, app + 'AgentIOSJSONWebSearchAdapter.swift').indexOf(policy)), 'Exact credential/header policy retained');
  assert(json.includes('parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")'));
  for (const name of ['AgentIOSWebExecutionBudget.swift', 'AgentIOSImageSearchRequestPolicy.swift', 'AgentIOSWebIntelligenceCache.swift', 'AgentIOSWebSourceHealth.swift']) {
    const current = read(app + name), indexed = require('./check-web-cache-index-scope.cjs');
    if (indexed.isIndexedCache(current)) indexed.validateIndexedCache();
    else assert.equal(current, show(base, app + name), name);
  }
  const parserFile = app + 'AgentIOSPublicSearchParser.swift';
  assert.equal(require('./check-text-search-fusion-scope.cjs').retainedFusionHit(read(parserFile)).replace('    var retrievalStatus: String? = nil\n', ''), show(base, parserFile), 'Existing HTML/image/redirect parsing unchanged');
  const tests = read('apps/ios/GalaxySSITests/AgentIOSAdditionalWebSearchAdapterTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  const intelligenceFile = app + 'AgentIOSURLSessionWebIntelligenceProvider.swift';
  let intelligence = read(intelligenceFile);
  if (intelligence.includes('var documentMetadata = ["source": "web_search"]')) {
    intelligence = require('./check-text-search-fusion-scope.cjs').retainedTextFusionIntelligence(intelligence);
  }
  intelligence = intelligence.replace('    let networkAttempted = !(searchProvider is AgentIOSURLSessionWebMediaToolProvider && webResult.metadata["local_index_only"] == .bool(true))\n', '');
  assert.equal(intelligence.split('networkAttempted: networkAttempted\n').length, 3);
  intelligence = intelligence.replaceAll('networkAttempted: networkAttempted\n', 'networkAttempted: true\n');
  intelligence = intelligence.replace('      if object["retrieval_status"] == .string("local_index_reference") {\n        result["retrieval_status"] = .string("local_index_reference")\n        evidence["retrieval_status"] = .string("local_index_reference")\n      }\n', '');
  assert.equal(intelligence, show(base, intelligenceFile), 'Only pure-native-local network flag and untrusted reference metadata propagation changed');
  for (const token of ['transport.requests.isEmpty', '"%2B"', 'isCancelled: { true }', 'file:///private/fixture', '"local_index_reference"']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSHTMLWebSearchAdapter', 'AgentIOSArxivSearchAdapter', 'AgentIOSDevDocsSearchAdapter', 'AgentIOSAdditionalWebSearchAdapterTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
  console.log('All 41 pinned base IDs +247 sites, 19 added adapters, 22 local documentation aliases, bounded XML/social/local dispatch and retained network/header policies checked as source. No native or live search acceptance.');
}

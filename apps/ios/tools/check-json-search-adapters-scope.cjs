// Source contracts only. No native execution, authentication or live API acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'fb9dda39ef15f411297ec9500c61870f8a03810c';
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const normalize = value => value.replace(/\r\n/g, '\n');
const read = file => normalize(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => normalize(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
function replaceOnce(value, before, after) {
  assert.equal(value.split(before).length, 2, 'Exactly one declared JSON adapter hook: ' + before);
  return value.replace(before, after);
}
function retainedJSONProvider(source) {
  for (const [before, after] of [
    ['            } else if let parser = endpoint.jsonParser {\n              results = try AgentIOSJSONWebSearchAdapter.parse(resource.body, source: parser, limit: maxResults)\n', ''],
    ['      if let api = AgentIOSJSONWebSearchAdapter.entry(source.id) {\n        let url = try AgentIOSJSONWebSearchAdapter.requestURL(api, query: query, limit: maxResults)\n        return AgentIOSWebSearchEndpoint(provider: source.id,\n          url: try validatedPublicHTTPSURL(url.absoluteString), jsonParser: source.id)\n      }\n', ''],
    ['  var jsonParser: String? = nil\n', '']
  ]) source = replaceOnce(source, before, after);
  return source;
}
module.exports = {retainedJSONProvider};
if (require.main === module) {
  const file = app + 'AgentIOSURLSessionWebMediaProvider.swift';
  assert.equal(retainedJSONProvider(read(file)), show(base, file), 'Only JSON endpoint/dispatch hooks changed since indexed catalog increment');
  const adapter = read(app + 'AgentIOSJSONWebSearchAdapter.swift');
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  const templates = [...adapter.matchAll(/template: "([^"]+)"/g)].map(match => match[1]);
  assert.equal(templates.length, 16);
  for (const template of templates) assert(reference.includes('"' + template + '"'), 'Exact pinned Android API template: ' + template);
  const ids = [...adapter.matchAll(/\.init\(id: "([^"]+)"/g)].map(match => match[1]);
  assert.deepEqual(ids, ['marginalia', 'wikipedia', 'wikipedia_zh', 'github', 'github_code', 'gitlab', 'stackoverflow',
    'hacker_news', 'lobsters', 'reddit', 'crossref', 'semantic_scholar', 'pubmed', 'crates_io', 'npm', 'mdn']);
  for (const id of ids) assert(reference.includes('"' + id + '"'), id);
  const indexed = JSON.parse(read(app + 'web-indexed-sources.json')).sources;
  assert.equal(new Set([...ids, ...indexed.map(row => row.id)]).size, 263, 'API/site IDs cannot collide');
  for (const token of ['URLQueryItem(name:', 'parts.queryItems = parts.queryItems?.map', 'min(max(limit, 1), 100)',
    'JSONSerialization.jsonObject(with: data)', 'guard let rows = rawRows as? [Any]', 'rows.prefix(100)',
    'parts.user == nil, parts.password == nil', 'AgentIOSWebSourceLearningPolicy.validHost(host)',
    'CFGetTypeID(number) != CFBooleanGetTypeID()', 'number.doubleValue < Double(Int64.max)',
    'seen.insert(cleanURL).inserted', 'SwiftSoup.parse(String(title.prefix(8192)))', 'hits.count >= min(limit, 100)']) assert(adapter.includes(token), token);
  assert(adapter.indexOf('replacingOccurrences(of: "GALAXYSSI_LIMIT"', adapter.indexOf('parts.queryItems =')) <
    adapter.indexOf('replacingOccurrences(of: "GALAXYSSI_QUERY"', adapter.indexOf('parts.queryItems =')), 'Never rewrite a sentinel inside user query text');
  assert(!adapter.includes('Authorization') && !/\bURLSession\b/.test(adapter), 'Use existing transport without implicit credentials');
  for (const name of ['AgentIOSWebExecutionBudget.swift', 'AgentIOSImageSearchRequestPolicy.swift',
    'AgentIOSPublicSearchParser.swift', 'AgentIOSWebIntelligenceCache.swift', 'AgentIOSWebSourceHealth.swift']) {
    assert.equal(read(app + name), show(base, app + name), name + ' retained');
  }
  const tests = read('apps/ios/GalaxySSITests/AgentIOSJSONWebSearchAdapterTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 6);
  for (const id of ids) assert(tests.includes('"' + id + '": #"'), 'Response fixture for ' + id);
  for (const token of ['permissions: false', 'status: 401', 'XCTAssertTrue(denied.requests.isEmpty)',
    'GALAXYSSI_LIMIT', 'pageid":true', '"https://127.0.0.1/a"']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const token of ['C3007E000000000000000001 /* AgentIOSJSONWebSearchAdapter.swift in Sources */',
    'C3007E000000000000000003 /* AgentIOSJSONWebSearchAdapterTests.swift in Sources */']) assert.equal(project.split(token).length, 3);
  console.log('16 pinned API endpoints, JSON dispatch, query/shape bounds, retained transport/security and fixture/project source contracts passed. No Swift typecheck, XCTest or live API acceptance.');
}

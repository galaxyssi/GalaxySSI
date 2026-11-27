// Source contracts only; does not execute Foundation, HTTP, Swift or XCTest.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'fe0940f0cc538bfc6659a49588b066ea560917b8';
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], { cwd: root, encoding: 'utf8', maxBuffer: 8_000_000 }));
const hooks = [
  ['githubToken: ["github", "github_code"].contains($0) ? imageCredentials.credential(.githubToken) : "") },\n              htmlSearchPolicy: AgentIOSHTMLSearchRequestPolicy(source: endpoint.provider)',
    'githubToken: ["github", "github_code"].contains($0) ? imageCredentials.credential(.githubToken) : "") }'],
  ['    htmlSearchPolicy: AgentIOSHTMLSearchRequestPolicy? = nil,\n', ''],
  ['            .merging(htmlSearchPolicy?.headers(for: currentURL) ?? [:]) { _, search in search }\n', '']
];
function retainedBaiduProvider(source) {
  if (!source.includes('htmlSearchPolicy:')) return source;
  for (const [from, to] of hooks) {
    assert.equal(source.split(from).length, 2, 'Exactly one Baidu representation hook: ' + from);
    source = source.replace(from, to);
  }
  return source;
}
module.exports = { retainedBaiduProvider };
if (require.main === module) {
  const provider = read(app + 'AgentIOSURLSessionWebMediaProvider.swift');
  assert.equal(retainedBaiduProvider(provider), show(base, app + 'AgentIOSURLSessionWebMediaProvider.swift'),
    'Only search request policy argument, optional default and per-hop header merge change');
  assert.throws(() => retainedBaiduProvider(provider.replace(hooks[2][0], hooks[2][0].replace('currentURL', 'requestedURL'))),
    'Cannot normalize away a policy evaluated only at the original URL');
  const policy = read(app + 'AgentIOSHTMLSearchRequestPolicy.swift');
  for (const token of ['source == "baidu"', 'parts.scheme == "https"', 'parts.host?.lowercased() == "www.baidu.com"',
    'parts.user == nil, parts.password == nil', 'parts.port == nil || parts.port == 443',
    'parts.percentEncodedPath == "/s"', 'return ["User-Agent": Self.baiduUserAgent]']) assert(policy.includes(token), token);
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt');
  const userAgent = [...policy.matchAll(/^    "([^"]+)"/gm)].map(match => match[1]);
  assert.equal(userAgent.length, 2);
  for (const part of userAgent) assert(reference.includes(part), 'Exact pinned desktop User-Agent');
  for (const name of ['AgentIOSPublicArticleRequestPolicy', 'AgentIOSImageSearchRequestPolicy', 'AgentIOSJSONWebSearchAdapter',
    'AgentIOSPublicSearchParser', 'AgentIOSWebExecutionBudget', 'AgentIOSWebIntelligenceCache', 'AgentIOSURLSessionWebIntelligenceProvider']) {
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  }
  const tests = read('apps/ios/GalaxySSITests/AgentIOSHTMLSearchRequestTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 6);
  for (const token of ['testActualRegistrySearchRequestsBaiduCardsAndPreservesQueryEncoding',
    'testCrossOriginAndDifferentPathRedirectsDoNotRetainSearchUserAgent',
    'testSameSearchEndpointRedirectReevaluatesThePolicyAndKeepsTheOriginalDeadline',
    'testOrdinaryFetchToBaiduDoesNotAcquireSearchHeaders', 'testSearchPermissionDenialStillPreventsEveryRequest',
    'https://www.baidu.com/%73', 'https://www.baidu.com:8443/s', 'https://user@www.baidu.com/s',
    'XCTAssertTrue(transport.requests.isEmpty)']) assert(tests.includes(token), token);
  assert(!/\p{Script=Han}/u.test(tests + policy));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSHTMLSearchRequestPolicy', 'AgentIOSHTMLSearchRequestTests']) {
    assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
  }
  const entry = "  source = require('./check-baidu-search-request-scope.cjs').retainedBaiduProvider(source);\n";
  for (const [file, signature] of [
    ['check-web-tool-failure-scope.cjs', 'function retainedFailureMedia(source) {\n'],
    ['check-json-search-adapters-scope.cjs', 'function retainedJSONProvider(source) {\n'],
    ['check-image-source-adapters-scope.cjs', 'function retainedProvider(source) {\n']
  ]) {
    assert.equal(read('apps/ios/tools/' + file), show(base, 'apps/ios/tools/' + file).replace(signature, signature + entry),
      file + ' retains every prior assertion with only the explicit new-hook normalization');
  }
  console.log('Pinned Baidu card request, per-hop confinement and whole-provider scope contracts passed; six synthetic native tests authored, not executed.');
}

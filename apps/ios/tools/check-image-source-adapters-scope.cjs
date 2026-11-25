// Source contracts only; no native credentials/network/deadline/redirect acceptance.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = '2b772addaa10dc4573b21b56c9e4d56ee8aff248';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const section = (source, start, end, after = 0) => {
  const first = source.indexOf(start, after), last = source.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return source.slice(first, last);
};
function retainedProvider(source) {
  if (!source.includes('  var imageCredentials: AgentIOSWebIntelligenceCredentials\n')) return source;
  const original = old('apps/ios/GalaxySSI/AgentIOSURLSessionWebMediaProvider.swift');
  const endpointStart = '  private func searchEndpoints(';
  const imageStart = '    if imageSearch {\n', imageEnd = '    let orderedProviders:';
  const changedImageEndpoints = section(source, imageStart, imageEnd, source.indexOf(endpointStart));
  const priorImageEndpoints = section(original, imageStart, imageEnd, original.indexOf(endpointStart));
  source = source.replace(changedImageEndpoints, priorImageEndpoints);
  source = source.replace(section(source, '  private func imageSearchResults(', '  private func searchComponents('), '');
  const replacements = [
    ['  var imageCredentials: AgentIOSWebIntelligenceCredentials\n', ''],
    ['    imageCredentials: AgentIOSWebIntelligenceCredentials = AgentIOSWebIntelligenceCredentials(),\n', ''],
    ['    self.imageCredentials = imageCredentials\n', ''],
    ['  case sourceCredentialRequired\n  case imageSearchTokenUnavailable\n', ''],
    ['(!engineIds.isEmpty && !engineIds.isSubset(of: AgentIOSImageSearchRequestPolicy.supported))', '(!engineIds.isEmpty && engineIds != ["sogou_image"])'],
    ['              invocation: searchInvocation,\n              imagePolicy: endpoint.imageSearch ? AgentIOSImageSearchRequestPolicy(source: endpoint.provider,\n                braveKey: endpoint.provider == "brave_image" ? imageCredentials.credential(.braveAPIKey) : "") : nil',
      '              invocation: searchInvocation'],
    ['results = try imageSearchResults(endpoint: endpoint, resource: resource, query: query, invocation: searchInvocation)', 'results = try AgentIOSPublicSearchParser.sogouImages(html, limit: 20)'],
    ['          .init(sourceID: $0.provider, results: $0.results,\n            weight: AgentIOSImageSearchRequestPolicy.weight($0.provider), authority: AgentIOSImageSearchRequestPolicy.authority($0.provider))',
      '          .init(sourceID: $0.provider, results: $0.results, weight: 1.2, authority: 0.75)'],
    ['    imagePolicy: AgentIOSImageSearchRequestPolicy? = nil,\n', ''],
    ['AgentIOSPublicArticleRequestPolicy.headers(for: currentURL).merging(imagePolicy?.headers(for: currentURL) ?? [:]) { _, image in image }',
      'AgentIOSPublicArticleRequestPolicy.headers(for: currentURL)'],
    ['    case .sourceCredentialRequired:\n      return failure("search_source_credential_required", "Brave image search requires a configured valid API key.")\n    case .imageSearchTokenUnavailable:\n      return failure("invalid_engine_response", "DuckDuckGo Image did not return a bounded search token.", retryable: true)\n', '']
  ];
  for (const [before, after] of replacements) {
    assert.equal(source.split(before).length, 2, 'Exactly one scoped adapter hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}
module.exports = { retainedProvider };
if (require.main === module) {
  const providerFile = 'apps/ios/GalaxySSI/AgentIOSURLSessionWebMediaProvider.swift';
  const provider = read(providerFile);
  assert.equal(retainedProvider(provider), old(providerFile), 'Only declared image adapter/credential/scoped-header hooks change; all generic transport, routing, budget, learning and result policy retained');
  const parserFile = 'apps/ios/GalaxySSI/AgentIOSPublicSearchParser.swift', parser = read(parserFile);
  assert.equal(parser.replace(section(parser, '  static func imageRows(', '  static func parse('), ''), old(parserFile), 'Existing Sogou/HTML/redirect parser unchanged');
  assert(parser.includes('AgentIOSWebRenderURLPolicy.allows(image)'));
  assert(parser.includes('AgentIOSWebRenderURLPolicy.allows(preview)'));
  const engineFile = 'apps/ios/GalaxySSI/AgentIOSWebExecutionBudget.swift';
  assert.equal(read(engineFile).replace(', "brave_image", "duckduckgo_image"', ''), old(engineFile), 'Only explicitly supported source IDs added; research budget/validation unchanged');
  const policy = read('apps/ios/GalaxySSI/AgentIOSImageSearchRequestPolicy.swift');
  for (const token of ['parts.scheme == "https"', 'parts.user == nil, parts.password == nil', 'parts.port == nil || parts.port == 443',
    'parts.host?.lowercased() == "api.search.brave.com"', 'parts.percentEncodedPath == "/res/v1/images/search"',
    'Self.validBraveKey(braveKey)', '"X-Subscription-Token": braveKey', '(33...126).contains($0.value)', 'value.utf8.count <= 8192',
    'parts.host?.lowercased() == "duckduckgo.com"', 'landing.user == nil, landing.password == nil', 'parts.percentEncodedPath == "/i.js"']) assert(policy.includes(token), token);
  assert(provider.includes('headers(for: currentURL).merging(imagePolicy?.headers(for: currentURL) ?? [:])'), 'Revalidate credential headers on every redirect hop');
  const second = section(provider, '  private func imageSearchResults(', '  private func searchComponents(');
  for (const token of ['host: "duckduckgo.com", path: "/i.js"', 'URLQueryItem(name: "vqd", value: token)',
    'let remaining = invocation.remainingTimeMillis', 'guard remaining > 0', 'deadlineEpochMillis: invocation.deadlineEpochMillis',
    'cancellationRequested: { invocation.isCancellationRequested }', 'brave: false, limit: 20']) assert(second.includes(token), token);
  assert(!second.includes('timeoutMillis: 4_000'), 'Do not reset the second request budget');
  const endpoints = section(provider, '  private func searchEndpoints(', '    let orderedProviders:');
  for (const token of ['host: "pic.sogou.com", path: "/pics"', 'host: "api.search.brave.com", path: "/res/v1/images/search"',
    'host: "duckduckgo.com", path: "/"', 'imageCredentials.credential(.braveAPIKey)',
    'providers.contains("brave_image"), !AgentIOSImageSearchRequestPolicy.validBraveKey(braveKey)',
    'AgentIOSURLSessionWebError.sourceCredentialRequired', 'URLQueryItem(name: "safesearch", value: "moderate")']) assert(endpoints.includes(token), token);
  assert(policy.includes('static let supported: Set<String> = ["sogou_image", "brave_image", "duckduckgo_image"]'));
  const tests = read('apps/ios/GalaxySSITests/AgentIOSImageSearchAdapterTests.swift');
  for (const name of ['testBraveHeadersAreConfinedToExactHTTPSAPIEndpoint',
    'testImageJSONParsersRetainDimensionsAndRejectUnsafeSourceRatherThanInventCitation',
    'testDuckDuckGoTokenIsBoundedInertText', 'testBraveUsesStoredCredentialAndDoesNotForwardItAcrossRedirect',
    'testExplicitUnconfiguredBraveFailsWithoutNetworkOrFallback',
    'testDuckDuckGoUsesFixedSecondEndpointAndDoesNotPublishTokenURL',
    'testDuckDuckGoMissingTokenAndSpentBudgetDoNotStartSecondRequest']) assert(tests.includes('func ' + name + '('));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSImageSearchRequestPolicy', 'AgentIOSImageSearchAdapterTests']) assert(project.includes(name + '.swift in Sources'));
  console.log('Image adapter/header/compound-deadline source contracts passed; no native build, credential/network/redirect/cancellation or UI acceptance.');
}

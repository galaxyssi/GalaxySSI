// Source contracts only, not Foundation URL, URLSession, XCTest or live signed-link acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c8a48aaa9c24427d606b32d894848b9bdd48c648', android = '65655f0c79c6ab04121150229a65b089180f82f2';
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => {
  let source = clean(fs.readFileSync(path.join(root, file), 'utf8'));
  source = require('./check-web-network-assurance-scope.cjs').retained(file, source);
  if (file.endsWith('AgentIOSPublicAddressPolicy.swift')) source = require('./check-special-use-address-scope.cjs').retainedPolicy(source);
  return source;
};
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, 'One encoded-address hook: ' + from);
  return source.replace(from, to);
}
function retainedEncodedMedia(source) {
  source = require('./check-web-tool-failure-scope.cjs').retainedFailureMedia(source);
  const hook = '    components.host = host.lowercased()\n    components.fragment = nil\n    if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }\n';
  if (!source.includes(hook)) return source;
  source = once(source, hook, '');
  return once(source, '    // Authority is normalized during validation; paths and signed queries are case-sensitive.\n    url.absoluteString\n', '    url.absoluteString.lowercased()\n');
}
function validateEncodedWebRequest() {
  const provider = read(app + 'AgentIOSURLSessionWebMediaProvider.swift');
  assert.equal(retainedEncodedMedia(provider), show(base, app + 'AgentIOSURLSessionWebMediaProvider.swift'),
    'Only validated authority/fragment/empty-path and redirect identity change; HTTP, grants, DNS, headers, credentials, bytes, parsing, renderer and deadlines retained');
  const begin = provider.indexOf('  private func validatedPublicHTTPSURL('), end = provider.indexOf('  private func isLocalOrPrivateHost(', begin);
  assert(begin >= 0 && end > begin);
  const validation = provider.slice(begin, end);
  for (const token of ['URLComponents(string: trimmed)', 'components.user == nil', 'components.password == nil',
    'isLocalOrPrivateHost(host)', 'components.scheme = "https"', 'components.host = host.lowercased()',
    'components.fragment = nil', 'components.percentEncodedPath.isEmpty', 'guard let url = components.url']) assert(validation.includes(token), token);
  assert(!/removingPercentEncoding|addingPercentEncoding|queryItems\s*=|\.path\s*=|percentEncodedQuery\s*=/.test(validation), 'Do not rebuild path/query from decoded components');
  assert(provider.includes('var visited: Set<String> = [canonicalURL(requestedURL)]'));
  assert(provider.includes('let nextURL = try validatedPublicHTTPSURL(nextCandidate.absoluteString)'));
  assert(provider.includes('let canonical = canonicalURL(nextURL)'));
  assert(provider.includes('guard !visited.contains(canonical)'));
  for (const name of ['AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSWebMediaNativeTools', 'AgentIOSPublicAddressPolicy',
    'AgentIOSImageSearchRequestPolicy', 'AgentIOSJSONWebSearchAdapter', 'AgentIOSDynamicWebRenderer', 'AgentIOSWebIntelligenceCache', 'AgentIOSWebCacheIndex'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  const reference = show(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebMediaNativeTools.kt');
  for (const token of ['val origin = URI("https", null, asciiHost, parsed.port, null, null, null).toASCIIString()',
    'return URI(origin + parsed.rawPath.ifBlank { "/" } +', '(parsed.rawQuery?.let { "?$it" } ?: ""))',
    'if (!visited.add(next.toString()))']) assert(reference.includes(token), token);
  const androidTest = show(android, 'apps/android/app/src/test/java/com/galaxyssi/chat/AgentWebMediaNativeToolsTest.kt');
  const tests = read('apps/ios/GalaxySSITests/AgentIOSEncodedWebRequestTests.swift');
  for (const sample of ['https://public.example.test/a%2Fb/%E4%B8%AD?q=%E5%B0%8F+fish&x=%25%26%3D%2B#fragment',
    'https://public.example.test/image?name=%E4%B8%AD&sig=a%2Fb%3D%3D']) assert(androidTest.includes(sample) && tests.includes(sample), sample);
  for (const name of ['PinnedAndroidEncodedPathAndSignedRedirectReachTransportUnchanged',
    'RelativeRedirectPreservesEncodedSeparatorsAndQueryOrder', 'CaseSensitivePathAndQueryRedirectsAreNotFalseLoops',
    'FragmentOnlyRedirectStillStopsAsLoopWithoutRedispatch', 'EmptyPathAndAuthorityNormalizeWithoutTouchingEncodedQuery',
    'CommonStatelessOperationsUseTheSamePreservedRequestAddress', 'PrivateCredentialedAndInsecureRedirectsStillStopBeforeNextDispatch']) assert(tests.includes('func test' + name + '('), name);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('AgentIOSEncodedWebRequestTests.swift in Sources */').length, 3);
}
module.exports = {retainedEncodedMedia, validateEncodedWebRequest};
if (require.main === module) {
  validateEncodedWebRequest();
  console.log('iOS encoded request/redirect identity and fragment source contracts passed; no native URL or transport acceptance');
}

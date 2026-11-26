// Source contracts only; not DNS, URLSession, WebKit or Swift execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '1b2327faafedad2b5044e5fb3f688fc61c413313';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + app + file + '.swift'],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function replaceOnce(source, before, after) {
  assert.equal(source.split(before).length, 2, 'Exactly one public-address policy hook: ' + before);
  return source.replace(before, after);
}
function section(source, first, last) {
  const begin = source.indexOf(first), end = source.indexOf(last, begin + first.length);
  assert(begin >= 0 && end > begin, first);
  return source.slice(begin, end);
}
function retainedAddressProvider(source) {
  const hook = '  private func isLocalOrPrivateHost(_ host: String) -> Bool {\n    AgentIOSPublicAddressPolicy.blocksHost(host)\n  }\n\n';
  if (!source.includes('AgentIOSPublicAddressPolicy.blocksHost(host)')) return source;
  const prior = section(old('AgentIOSURLSessionWebMediaProvider'),
    '  private func isLocalOrPrivateHost(', '  private func commonOutput(');
  return replaceOnce(source, hook, prior);
}
function retainedAddressRenderer(source) {
  if (!source.includes('AgentIOSPublicAddressPolicy.blocksHost(value)')) return source;
  const hook = '  private static func isLocalOrPrivateHost(_ value: String) -> Bool {\n    AgentIOSPublicAddressPolicy.blocksHost(value)\n  }\n}\n\n';
  source = replaceOnce(source, hook, section(old('AgentIOSDynamicWebRenderer'),
    '  private static func isLocalOrPrivateHost(', '#if canImport(WebKit) && canImport(UIKit)\nfinal class'));
  source = replaceOnce(source,
    '    if AgentIOSPublicAddressPolicy.isNumericHost(host) { return !isLocalOrPrivateHost(host) }',
    '    if host.contains(":" ) || isIPv4(host) { return !isLocalOrPrivateHost(host) }');
  return replaceOnce(source, '#else\n    return false\n#endif\n  }\n\n  static func allowsSubresource',
    '#else\n    return true\n#endif\n  }\n\n  static func allowsSubresource');
}
module.exports = {retainedAddressProvider, retainedAddressRenderer};
if (require.main === module) {
  const provider = read(app + 'AgentIOSURLSessionWebMediaProvider.swift');
  assert.equal(retainedAddressProvider(provider), old('AgentIOSURLSessionWebMediaProvider'), 'Only address classifier delegation changed');
  assert.equal(retainedAddressRenderer(read(app + 'AgentIOSDynamicWebRenderer.swift')), old('AgentIOSDynamicWebRenderer'),
    'Only shared numeric classification and unsupported-platform fail-closed behavior changed');
  const policy = read(app + 'AgentIOSPublicAddressPolicy.swift');
  for (const token of ['inet_pton(AF_INET,', 'inet_pton(AF_INET6,', 'withUnsafeBytes(of: address)',
    'CharacterSet.controlCharacters.contains', 'host.hasSuffix(".localhost")', 'host.hasSuffix(".local")',
    'bytes[0] == 0xff', 'bytes[0] & 0xfe == 0xfc', 'bytes[1] & 0xc0 == 0x80', 'bytes[1] & 0xc0 == 0xc0',
    'bytes[10] == 0xff, bytes[11] == 0xff', 'blocksIPv4(Array(bytes.suffix(4)))',
    'host.split(separator: ".", omittingEmptySubsequences: false)']) assert(policy.includes(token), token);
  assert(!policy.includes('host.hasPrefix("fc")'));
  assert(read(app + 'AgentMarkdownImageStore.swift').includes('AgentIOSWebRenderURLPolicy.allows(url.absoluteString)'));
  assert(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').includes('AgentIOSPublicAddressPolicy.swift in Sources'));
  const tests = read('apps/ios/GalaxySSITests/AgentIOSDynamicWebRendererTests.swift');
  for (const name of ['RejectsEquivalentAndScopedIPv6Forms', 'PreservesPublicIPv6AndDNS64',
    'DoesNotConfuseDomainPrefixesWithIPv6', 'PreservesExistingIPv4Restrictions']) {
    assert(tests.includes('func testPublicAddressClassification' + name + '('), name);
  }
  assert(read('apps/ios/GalaxySSITests/AgentIOSWebMediaNativeToolTests.swift').includes('func testStaticWebFetchRejectsNonPublicIPv6BeforeTransport('));
  console.log('iOS shared public-address classifier source checks passed; no native or network execution');
}

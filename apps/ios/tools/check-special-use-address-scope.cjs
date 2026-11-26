// Source contracts only; not executed Swift, DNS, URLSession or WebKit acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const base = 'f2b671fa9a9728bfc6e1c94697bec0bdf89c943e';
const app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const show = (ref, file) => cp.execFileSync('git', ['show', `${ref}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function once(source, from, to = '') {
  assert.equal(source.split(from).length, 2, from);
  return source.replace(from, to);
}
const v4 = '    if first == 192 && second == 0 && (third == 0 || third == 2) { return true }\n' +
  '    if first == 192 && second == 88 && third == 99 { return true }\n' +
  '    if first == 198 && second == 51 && third == 100 { return true }\n' +
  '    if first == 203 && second == 0 && third == 113 { return true }\n';
const v6 = '    if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 { return true }\n';
function retainedPolicy(source) {
  if (!source.includes(v6)) return source;
  return once(once(once(source, v6), v4),
    'let first = bytes[0], second = bytes[1], third = bytes[2]', 'let first = bytes[0], second = bytes[1]');
}
function validate() {
  const policy = read(app + 'AgentIOSPublicAddressPolicy.swift');
  assert(policy.includes(v4) && policy.includes(v6));
  assert.equal(retainedPolicy(policy), show(base, app + 'AgentIOSPublicAddressPolicy.swift'));
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2',
    'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebMediaNativeTools.kt');
  for (const token of ['a == 192 && b == 0 && c == 0', 'a == 192 && b == 0 && c == 2',
    'a == 192 && b == 88 && c == 99', 'a == 198 && b == 51 && c == 100',
    'a == 203 && b == 0 && c == 113', '(bytes[2].toInt() and 0xff) == 0x0d',
    '(bytes[3].toInt() and 0xff) == 0xb8']) assert(reference.includes(token), token);
  const testsPath = 'apps/ios/GalaxySSITests/AgentIOSDynamicWebRendererTests.swift';
  const tests = read(testsPath), start = tests.indexOf('  func testSpecialUseAddressRangesMatchAndroid'),
    end = tests.indexOf('  func testPublicAddressClassificationRejectsEquivalentAndScopedIPv6Forms');
  assert(start >= 0 && end > start);
  assert.equal(tests.slice(0, start) + tests.slice(end), show(base, testsPath));
  const added = tests.slice(start, end);
  assert.equal((added.match(/  func test/g) || []).length, 6);
  for (const token of ['[0, 1, 127, 254, 255]', '2001:db8:ffff:ffff:ffff:ffff:ffff:ffff',
    '2001:db7:ffff::1', '2001:db9::1', '192.0.2.example.com', '::ffff:c058:6301',
    '64:ff9b::cb00:7101', 'allowsSubresource(url)', 'resolvesToPublicAddress(url)',
    'AgentMarkdownImageStore.publicURL', 'XCTAssertEqual(calls, 0)', 'XCTAssertEqual(renderer.calls, 0)',
    'XCTAssertEqual(calls, 1, host)', 'result.error?.code, "local_host_blocked"']) assert(added.includes(token), token);
  for (const name of ['AgentIOSURLSessionWebMediaProvider', 'AgentIOSDynamicWebRenderer', 'AgentMarkdownImageStore',
    'AgentIOSWebCrawlPolicy', 'AgentIOSWebMediaNativeTools', 'AgentIOSWebIntelligenceNativeTools',
    'AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSWebIntelligenceCache', 'AgentIOSWebExecutionBudget']) {
    const file = app + name + '.swift'; assert.equal(read(file), show(base, file), name);
  }
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(require('./check-pre-shadow-routing-scope.cjs').retained(project, read(project)), show(base, project));
  assert(read(project).includes('AgentIOSDynamicWebRendererTests.swift in Sources'));
  for (const name of ['check-encoded-web-request-scope.cjs', 'check-web-crawl-scope.cjs']) {
    const file = 'apps/ios/tools/' + name;
    assert.equal(once(read(file), "  if (file.endsWith('AgentIOSPublicAddressPolicy.swift')) source = require('./check-special-use-address-scope.cjs').retainedPolicy(source);\n"),
      show(base, file).replace("const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));",
        "const read = file => {\n  let source = clean(fs.readFileSync(path.join(root, file), 'utf8'));\n  return source;\n};"));
  }
  console.log('Special-use subnet, mapped/NAT64 inheritance and shared consumer source contracts passed; no native/network acceptance.');
}
module.exports = {retainedPolicy, validate};
if (require.main === module) validate();

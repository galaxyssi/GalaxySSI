// Source contracts only; not native execution, image relevance or latency evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const intent = '      "Finding or showing existing pictures is retrieval, not a request to generate new artwork. Generate or edit " +\n      "images only when the user requests creation or transformation; do not substitute fan art for existing images. " +\n';
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  if (f === app + 'CloudWebGrounding.swift') return s.replace(intent, '')
    .replace('min(max(result["max_results"]?.intValue ?? 3, 1), 12)', 'min(max(result["max_results"]?.intValue ?? 12, 6), 12)');
  if (f === tests + 'CloudWebGroundingTests.swift' && s.includes('  func testDedicatedImageAliasPreservesEverySupportedRequestedCount()'))
    return s.replace(section(s, '  func testDedicatedImageAliasPreservesEverySupportedRequestedCount()', '  func testParsesDeepSeekDSMLCallsWithoutExposingProtocolText()'), '');
  if (f === tests + 'CloudWebFastSearchTests.swift') return s.replace('XCTAssertEqual(image["limit"], .int(1))', 'XCTAssertEqual(image["limit"], .int(6))');
  return s;
}
function validate() {
  for (const f of [app + 'CloudWebGrounding.swift', tests + 'CloudWebGroundingTests.swift', tests + 'CloudWebFastSearchTests.swift']) assert.equal(retained(f, read(f)), old(f), f);
  const source = read(app + 'CloudWebGrounding.swift');
  assert(source.includes(intent));
  const alias = section(source, '    if name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "web_image_search" {', '    if operation(forToolName: name) == .search {');
  assert(alias.includes('min(max(result["max_results"]?.intValue ?? 3, 1), 12)'));
  for (const token of ['"profile": .string("fast")', '"verticals": .array([.string("image")])', '"engine_fanout": .int(3)', '"query": result["query"]']) assert(alias.includes(token), token);
  assert(source.includes('input: normalizeArguments(name: name, arguments: arguments)'));
  const fixture = section(read(tests + 'CloudWebGroundingTests.swift'), '  func testDedicatedImageAliasPreservesEverySupportedRequestedCount()', '  func testParsesDeepSeekDSMLCallsWithoutExposingProtocolText()');
  assert.equal((fixture.match(/func test/g) || []).length, 5);
  for (const token of ['for count in 1...12', '(Int64.min, 1)', '(Int64.max, 12)', 'provider.inputs.count, 1',
    'provider.inputs.first?["limit"], .int(2)', 'context: AgentNativeToolInvocationContext()',
    'testImageCountFixDoesNotDowngradeExplicitResearchPlansOrOptions', 'testImageRetrievalIntentAndSchemaAgreeWithCountNormalization']) assert(fixture.includes(token), token);
  for (const name of ['AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSImageSearchFusion',
    'CloudImageSearchEvidence', 'URLSessionCloudModelStreamClient', 'GalaxySSIMqttClient', 'AgentRichMarkdownParser',
    'AgentIOSWebSearchCapacity', 'GalaxySSIHealthCareTaskRuntime']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'));
  const fast = 'apps/ios/tools/check-fast-search-defaults-scope.cjs';
  assert.equal(read(fast), old(fast)
    .replace("const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));", "const read = file => require('./check-image-request-count-scope.cjs').retained(file, clean(fs.readFileSync(path.join(root, file), 'utf8')));")
    .replace('function retainedFastGrounding(source) {\n', "function retainedFastGrounding(source) {\n  source = require('./check-image-request-count-scope.cjs').retained(app + 'CloudWebGrounding.swift', source);\n"));
  const android = cp.execFileSync('git', ['show', 'cef237557f5f8f422f93832a535e3d63e3ba81ed:apps/android/app/src/main/java/com/galaxyssi/chat/CloudWebGrounding.kt'], {cwd: root, encoding: 'utf8'});
  assert(android.includes('source.optInt("max_results", 3).coerceIn(1, 12)'));
  console.log('Image alias 1..12/default-three normalization, retrieval intent, retained research/provider/transport and five authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

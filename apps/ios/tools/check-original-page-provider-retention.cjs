// Exact approved-hook composition, not Swift execution or transport acceptance.
const assert = require('node:assert/strict'), cp = require('node:child_process');
const fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const file = 'apps/ios/GalaxySSI/AgentIOSURLSessionWebMediaProvider.swift';
const approved = '5e6167ab76ee808fa271504fb324c879916bb86b';
const clean = text => text.replace(/\r\n/g, '\n');
const show = ref => clean(cp.execFileSync('git', ['show', ref + ':' + file],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const start = '  func originalPageAsset(', end = '  private func executeWeb(';
let approvedMethod;
function method(source) {
  assert.equal(source.split(start).length, 2, 'One original-page asset method');
  const begin = source.indexOf(start), finish = source.indexOf(end, begin);
  assert(finish > begin, 'Original-page method ends at the existing dispatcher');
  return source.slice(begin, finish);
}
function retainedOriginalPageProvider(source) {
  if (!source.includes(start)) return source;
  approvedMethod ??= method(show(approved));
  const actual = method(source);
  assert.equal(actual, approvedMethod, 'Only the exact approved original-page method may be normalized');
  return source.replace(actual, '');
}
module.exports = {retainedOriginalPageProvider};
if (require.main === module) {
  const source = clean(fs.readFileSync(path.join(root, file), 'utf8'));
  const pinned = show(approved);
  assert.equal(retainedOriginalPageProvider(pinned), show(approved + '^'), 'Complete approved increment is one additive method');
  assert.equal(method(source), method(pinned), 'Current method remains the approved implementation');
  const stripped = retainedOriginalPageProvider(source);
  assert.equal(retainedOriginalPageProvider(stripped), stripped, 'Historical providers remain unchanged');
  for (const [before, after] of [
    ['guard maxBytes > 0,', 'guard maxBytes >= 0,'],
    ['grantedPermissions.contains', 'grantedConsents.contains'],
    ['grantedConsents.contains', 'grantedPermissions.contains'],
    ['startedAt + 15_000', 'startedAt + 30_000'],
    ['hardDeadlineEpochMillis: invocation.deadlineEpochMillis', 'hardDeadlineEpochMillis: Int64.max'],
    ['{ invocation.isCancellationRequested }', '{ false }'],
    ['validatedPublicHTTPSURL(address)', 'URL(string: address)!'],
    ['8 * 1_024 * 1_024', '80 * 1_024 * 1_024'],
    ['guard !resource.isPartial,', 'guard resource.isPartial,'],
    ['"image/avif"', '"text/html"']
  ]) {
    const altered = method(source).replace(before, after);
    assert.notEqual(altered, method(source), before);
    assert.throws(() => retainedOriginalPageProvider(source.replace(method(source), altered)), assert.AssertionError, before);
  }
  const unrelated = source.replace('import Foundation', 'import Foundation\n// synthetic unrelated mutation');
  assert.notEqual(unrelated, source);
  assert.equal(retainedOriginalPageProvider(unrelated), stripped.replace('import Foundation', 'import Foundation\n// synthetic unrelated mutation'),
    'Unrelated changes must remain visible to historical whole-provider assertions');
  const checker = 'apps/ios/tools/check-encoded-web-request-scope.cjs';
  const prior = clean(cp.execFileSync('git', ['show', 'c6bad3465c673dfb2dcecb23b095185c129c7447:' + checker],
    {cwd: root, encoding: 'utf8'}));
  const expected = prior.replace(
    "  source = require('./check-web-network-assurance-scope.cjs').retained(file, source);\n",
    "  source = require('./check-web-network-assurance-scope.cjs').retained(file, source);\n" +
      "  source = require('./check-search-response-size-parity.cjs').retained(file, source);\n"
  ).replace('function retainedEncodedMedia(source) {\n', 'function retainedEncodedMedia(source) {\n' +
    "  source = require('./check-original-page-provider-retention.cjs').retainedOriginalPageProvider(source);\n");
  assert.notEqual(expected, prior);
  assert.equal(clean(fs.readFileSync(path.join(root, checker), 'utf8')), expected,
    'All historical encoded-request assertions retained with only two read-normalization hooks');
  console.log('Exact original-page provider retention and ten negative source mutations passed; no native acceptance.');
}

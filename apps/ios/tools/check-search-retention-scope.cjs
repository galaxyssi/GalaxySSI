// Source contracts only, not SQLite/CryptoKit/XCTest execution or native acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const base = 'b42b5f77f87b2b8359b5dd4a51c81c32591bb7ea';
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => require('./check-search-response-size-parity.cjs').retained(file, clean(fs.readFileSync(path.join(root, file), 'utf8')));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, 'One declared retention hook: ' + from);
  return source.replace(from, to);
}
function retainedSearchCache(source) {
  source = require('./check-search-response-size-parity.cjs').retained(app + 'AgentIOSWebIntelligenceCache.swift', source);
  if (!source.includes('row.updated == entry.storedAtMillis, row.expires == entry.expiresAtMillis')) return source;
  return once(source, 'entry.key == key, row.updated == entry.storedAtMillis, row.expires == entry.expiresAtMillis,\n      entry.storedAtMillis <= now, now <= entry.expiresAtMillis',
    'entry.key == key, entry.storedAtMillis <= now, now < entry.expiresAtMillis');
}
function retainedSearchIndex(source) {
  source = require('./check-search-response-size-parity.cjs').retained(app + 'AgentIOSWebCacheIndex.swift', source);
  if (!source.includes('// Match Android: retain independent search keys until explicit cache cleanup.')) return source;
  source = once(source, 'guard entry.kind == .search, now >= 0 else { throw Failure.corrupt }', 'guard entry.kind == .search else { throw Failure.corrupt }');
  source = once(source, '      // Match Android: retain independent search keys until explicit cache cleanup.\n      try put(entry)',
    '      _ = try remove(.search, before: now)\n      try put(entry); try prune(.search, limit: 32)');
  return once(source, 'let searches = try remove(.search, before: expiredOnly ? now : nil, inclusive: false)',
    'let searches = try remove(.search, before: expiredOnly ? now : nil)');
}
function retainedSearchFixture(source) {
  source = require('./check-search-response-size-parity.cjs').retained(tests + 'AgentIOSWebSearchFusionTests.swift', source);
  if (!source.includes('clock = 61_001')) return source;
  source = once(source, 'clock = 61_001', 'clock = 61_000');
  return once(source, 'XCTAssertEqual(cache.stats()["search_count"], .int(33))\n    XCTAssertNotNil(cache.searchResponse(key: String(repeating: "a", count: 62) + "00"))',
    'XCTAssertEqual(cache.stats()["search_count"], .int(32))\n    XCTAssertNil(cache.searchResponse(key: String(repeating: "a", count: 62) + "00"))');
}
function validateSearchRetention() {
  const cache = read(app + 'AgentIOSWebIntelligenceCache.swift'), index = read(app + 'AgentIOSWebCacheIndex.swift');
  assert.equal(retainedSearchCache(cache), old(app + 'AgentIOSWebIntelligenceCache.swift'), 'Only response point-read expiry/authenticated timestamp checks change');
  assert.equal(retainedSearchIndex(index), old(app + 'AgentIOSWebCacheIndex.swift'), 'Only search write retention and clear expiry change; watch CAS, documents, crypto, migration and metadata retained');
  assert.equal(retainedSearchFixture(read(tests + 'AgentIOSWebSearchFusionTests.swift')), old(tests + 'AgentIOSWebSearchFusionTests.swift'), 'Only obsolete retention/expiry expectations change');
  const updatedIndexFixture = read(tests + 'AgentIOSWebCacheIndexTests.swift');
  assert.equal(once(updatedIndexFixture, 'XCTAssertEqual(counts.searches, 0)\n      XCTAssertNotNil(try index.entry(.search, id: "equal"))', 'XCTAssertEqual(counts.searches, 1)'),
    old(tests + 'AgentIOSWebCacheIndexTests.swift'), 'Only equality boundary fixture changes');
  for (const name of ['AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebWatchPolicy',
    'AgentIOSWebSearchCapacity', 'AgentIOSWebIntelligenceNativeTools', 'AgentIOSWebPageDiff'])
    assert.equal(name === 'AgentIOSURLSessionWebMediaProvider' ? require('./check-encoded-web-request-scope.cjs').retainedEncodedMedia(read(app + name + '.swift'))
      : read(app + name + '.swift'), old(app + name + '.swift'), name);
  const start = index.indexOf('  func putSearch('), end = index.indexOf('  func compareAndPutWatch(', start);
  assert(start >= 0 && end > start);
  const put = index.slice(start, end);
  assert(put.includes('try transaction {') && put.includes('try put(entry)') && put.includes('throw Failure.staleGeneration'));
  assert(!put.includes('remove(') && !put.includes('prune('), 'No runtime search count eviction or implicit expiry deletion');
  assert(cache.includes('row.updated == entry.storedAtMillis, row.expires == entry.expiresAtMillis'));
  assert(cache.includes('now <= entry.expiresAtMillis'));
  assert(index.includes('remove(.search, before: expiredOnly ? now : nil, inclusive: false)'));
  assert(cache.includes('(snapshot.searchResponses?.count ?? 0) <= Self.maxSearchResponses'), 'Legacy archive import bound remains independent of runtime row count');
  const android = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt'], {cwd: root, encoding: 'utf8'}));
  const a = android.indexOf('    override fun putSearch('), b = android.indexOf('    override fun sourceHealth(', a);
  assert(a >= 0 && b > a);
  const reference = android.slice(a, b);
  for (const token of ['database.writeString(', 'if (root.optLong("expires_at_millis") < clock()) return null']) assert(reference.includes(token), token);
  assert(!/prune|take\(|MAX_SEARCH|remove\(/.test(reference));
  assert(android.includes('if (!expiredOnly || expires < now) key else null'));
  const fixture = read(tests + 'AgentIOSWebSearchRetentionTests.swift');
  for (const name of ['FacadeRetainsNinetySixKeysAcrossReopenAndReplacement', 'EqualityExpiryBoundaryAndExplicitCleanupMatchReference',
    'FailedWriteAndClearRetainAllKeysAndGeneration', 'IndexedCountsAndPointLookupSupportMoreThanTwoThousandSearchKeys',
    'AuthenticatedRowAndInnerResponseTimestampsMustAgree', 'InvalidAndOversizedResponsesStillDoNotReplaceRetainedData']) assert(fixture.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split('AgentIOSWebSearchRetentionTests.swift in Sources */').length, 3);
}
module.exports = {retainedSearchCache, retainedSearchIndex, retainedSearchFixture, validateSearchRetention};
if (require.main === module) {
  validateSearchRetention();
  console.log('iOS independent indexed search-key retention, inclusive expiry, explicit cleanup and response timestamp source contracts passed; no native acceptance');
}

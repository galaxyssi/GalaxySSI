// Source-only cache-size contracts. No SQLite/CryptoKit/XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const base = '0bdfc81662cc27f638f0b3360f13c399ad2ba704';
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const git = (ref, f) => clean(cp.execFileSync('git', ['show', ref + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
const old = f => git(base, f);
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first); return s.slice(a, b);
}
function retained(file, s) {
  if (file.endsWith('AgentIOSWebSearchCapacity.swift') && !s.includes('maximumCachedResponseBytes')) {
    return once(s, '  static let defaultResults = 10\n', '  static let defaultResults = 10\n  static let maximumCachedResponseBytes = 2_000_000\n');
  }
  if (file.endsWith('AgentIOSWebIntelligenceCache.swift') && !s.includes('JSONEncoder().encode(self).count')) {
    return once(s, '        (result.output["results"]?.arrayValue?.count ?? 0) <= AgentIOSWebSearchCapacity.maximumResults\n',
      '        (result.output["results"]?.arrayValue?.count ?? 0) <= AgentIOSWebSearchCapacity.maximumResults &&\n        (try? JSONEncoder().encode(self).count).map { $0 <= AgentIOSWebSearchCapacity.maximumCachedResponseBytes } == true\n');
  }
  if (file.endsWith('AgentIOSWebCacheIndex.swift') && s.includes('  private func rowByteLimit(')) {
    s = once(s, ', maximumRowBytes: Int32? = nil', '');
    s = once(s, '    if let maximumRowBytes {\n      guard maximumRowBytes > 0 else { throw Failure.corrupt }\n      sqlite3_limit(database, SQLITE_LIMIT_LENGTH, maximumRowBytes)\n    }\n', '');
    s = once(s, '    let maximumBytes = try rowByteLimit(kind)\n', '');
    s = once(s, 'blob(statement, 5, maximumBytes: maximumBytes)', 'blob(statement, 5)');
    s = once(s, 'entry.kind == .search || entry.payload.count <= 3_000_000', 'entry.payload.count <= 3_000_000');
    s = once(s, '    let maximumBytes = try rowByteLimit(entry.kind)\n    guard entry.payload.count <= maximumBytes else { throw Failure.corrupt }\n', '');
    s = once(s, '    // CryptoKit\'s combined AES-GCM box adds a 12-byte nonce and 16-byte tag.\n', '');
    s = once(s, 'guard encoded.count <= (entry.kind == .search ? maximumBytes - 28 : min(4_099_000, maximumBytes - 28))', 'guard encoded.count <= 4_099_000');
    s = once(s, '    guard data.count <= maximumBytes else { throw Failure.corrupt }\n', '');
    s = once(s, section(s, '  private func rowByteLimit(', '  private func blob('), '');
    s = once(s, ', maximumBytes: Int = 4_100_000', '');
    s = once(s, 'count > 0, count <= maximumBytes', '(1...4_100_000).contains(count)');
    s = once(s, '    guard let length = Int32(exactly: data.count) else { throw Failure.corrupt }\n', '');
    return once(s, 'sqlite3_bind_blob(s, index, $0.baseAddress, length, Self.transient)', 'sqlite3_bind_blob(s, index, $0.baseAddress, Int32($0.count), Self.transient)');
  }
  if (file.endsWith('AgentIOSWebSearchFusionTests.swift') && s.includes('testSearchResponseBoundsRejectEmptyFailedAndRetainLargeEntries')) {
    const last = '  func testSearchResponseFailedWriteAndCorruptReadDoNotErasePriorData()';
    return once(s, section(s, '  func testSearchResponseBoundsRejectEmptyFailedAndRetainLargeEntries()', last),
      section(old(file), '  func testSearchResponseBoundsRejectEmptyFailedAndOversizedEntries()', last));
  }
  if (file.endsWith('AgentIOSWebSearchCapacityTests.swift') && s.includes('var large = response')) {
    const first = '  func testExactCacheAllowsLargeHundredRowsButRejectsOverBounds()', last = '  func testResearchEvidenceSchemaRemainsTwentyFour()';
    return once(s, section(s, first, last), section(old(file), first, last));
  }
  if (file.endsWith('AgentIOSWebSearchRetentionTests.swift') && s.includes('  func testInvalidResponsesStillDoNotReplaceRetainedData()')) {
    const last = '  private func key(';
    return once(s, section(s, '  func testInvalidResponsesStillDoNotReplaceRetainedData()', last),
      section(old(file), '  func testInvalidAndOversizedResponsesStillDoNotReplaceRetainedData()', last));
  }
  if (file.endsWith('AgentIOSWebCacheIndexTests.swift') && s.includes('  func testSearchRowsCrossLegacyBlobLimitWhileOtherKindsKeepTheirBounds()')) {
    return once(s, section(s, '  func testSearchRowsCrossLegacyBlobLimitWhileOtherKindsKeepTheirBounds()', '  func testIndexedCountsAndPointReadsDoNotDecodeOtherBodies()'), '');
  }
  return s;
}
function validate() {
  for (const f of ['AgentIOSWebSearchCapacity', 'AgentIOSWebIntelligenceCache', 'AgentIOSWebCacheIndex']) {
    assert.equal(retained(app + f + '.swift', read(app + f + '.swift')), old(app + f + '.swift'), f + ': complete file retained outside declared size hooks');
  }
  const source = git(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt');
  const encrypted = section(source, 'class AgentEncryptedWebIntelligenceStore(', 'class AgentInMemoryWebIntelligenceStore(');
  const reference = section(encrypted, '    override fun putSearch(', '    override fun sourceHealth(');
  assert(reference.includes('database.writeString(') && reference.includes('JSONObject(AgentNativeJsonCodec.stringify(response))'));
  assert(!/take\(|MAX_|limit|length|size/.test(reference));
  const storage = git(android, 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentEncryptedStorage.kt');
  const write = section(storage, '    fun writeString(key: String, value: String) = withStorage', '    fun mutateStrings(');
  assert(write.includes('insertWithOnConflict(') && !/take\(|MAX_|length|size/.test(write));
  assert(!read(app + 'AgentIOSWebSearchCapacity.swift').includes('maximumCachedResponseBytes'));
  const cache = read(app + 'AgentIOSWebIntelligenceCache.swift');
  assert(!cache.includes('JSONEncoder().encode(self).count'));
  for (const token of ['result.isSuccess', '<= AgentIOSWebSearchCapacity.maximumResults', 'guard entry.isValid']) assert(cache.includes(token), token);
  const index = read(app + 'AgentIOSWebCacheIndex.swift');
  for (const token of ['sqlite3_limit(database, SQLITE_LIMIT_LENGTH, -1)', 'return kind == .search ? limit : min(limit, 4_100_000)',
    'entry.kind == .search || entry.payload.count <= 3_000_000', 'guard entry.payload.count <= maximumBytes',
    'guard data.count <= maximumBytes', 'Int32(exactly: data.count)', 'count > 0, count <= maximumBytes',
    'blob(statement, 5, maximumBytes: maximumBytes)']) assert(index.includes(token), token);
  for (const name of ['AgentIOSWebSearchFusionTests', 'AgentIOSWebSearchCapacityTests', 'AgentIOSWebSearchRetentionTests', 'AgentIOSWebCacheIndexTests']) {
    const f = tests + name + '.swift';
    assert.equal(retained(f, read(f)), old(f), name + ': only declared size fixture changes');
  }
  for (const name of ['AgentIOSWebSearchFusionTests', 'AgentIOSWebCacheIndexTests']) {
    const f = tests + name + '.swift';
    assert.equal((read(f).match(/  func test/g) || []).length - (old(f).match(/  func test/g) || []).length, 2);
  }
  for (const name of ['AgentIOSURLSessionWebIntelligenceProvider', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebSourceHealth', 'AgentIOSWebWatchPolicy']) {
    const f = app + name + '.swift'; assert.equal(read(f), old(f), name + ': unchanged');
  }
  console.log('Pinned Android no-app-size-cap reference and SQLite-bounded search response source contracts passed; no native acceptance');
}
if (require.main === module) validate();
module.exports = {retained, validate};

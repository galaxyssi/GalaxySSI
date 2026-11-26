// Source contracts only; not SQLite/CryptoKit execution, crash or performance evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'd2df30844078b4cdcfbe281a76478b528eab6b1d';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const oldCache = () => cp.execFileSync('git', ['show', base + ':' + app + 'AgentIOSWebIntelligenceCache.swift'],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  return source.slice(start, end);
}
function replaceOnce(source, first, replacement) {
  assert.equal(source.split(first).length, 2, 'One declared source health hook: ' + first);
  return source.replace(first, replacement);
}
function retainedHealthCache(source) {
  if (require('./check-web-cache-index-scope.cjs').isIndexedCache(source)) return source;
  if (!source.includes('  private func healthIndexUnlocked()')) return source;
  const prior = oldCache();
  for (const line of ['  private let healthBeforeCommit: () throws -> Void\n',
    '    healthBeforeCommit: @escaping () throws -> Void = {},\n', '    self.healthBeforeCommit = healthBeforeCommit\n'])
    source = replaceOnce(source, line, '');
  for (const [first, last] of [
    ['  func stats()', '  func clear('],
    ['  func sourceHealth(', '  func learnSourceCandidates(']
  ]) source = replaceOnce(source, section(source, first, last), section(prior, first, last));
  source = replaceOnce(source,
    '    guard createIfMissing, !fileManager.fileExists(atPath: Self.sourceHealthDatabaseURL(for: fileURL).path),\n      secrets.string(account: healthImportAccount) == nil else { return nil }',
    '    guard createIfMissing else { return nil }');
  return replaceOnce(source, section(source, '  static func sourceHealthDatabaseURL(', '  private func canonicalURL('), '');
}
module.exports = {retainedHealthCache};
if (require.main === module) {
  const cache = read(app + 'AgentIOSWebIntelligenceCache.swift');
  const indexed = require('./check-web-cache-index-scope.cjs');
  if (indexed.isIndexedCache(cache)) indexed.validateIndexedCache();
  else assert.equal(retainedHealthCache(cache), oldCache(), 'Only health domain delegation, statistics, migration and missing-key fences changed');
  for (const [first, last] of [['  func sourceHealth(', '  func sourceRoutingSnapshot('],
    ['  func recordSourceReceipts(', '  func resetSourceHealth('], ['  func resetSourceHealth(', '  func learnSourceCandidates(']]) {
    const method = section(cache, first, last);
    assert(!method.includes('readUnlocked()') && !method.includes('mutate {'), first);
    assert(method.includes('healthIndexUnlocked()'), first);
  }
  assert(cache.includes('receipt == nil || fileManager.fileExists(atPath: url.path)'));
  assert(cache.includes('secrets.string(account: healthImportAccount) == nil'));
  assert(cache.includes('if receipt == nil { try secrets.setString("pending", account: healthImportAccount) }'));
  assert(cache.includes('initialize(allowLegacyImport: receipt != "1")'));
  assert(cache.includes('if receipt != "1" { try secrets.setString("1", account: healthImportAccount) }'));
  const database = read(app + 'AgentIOSWebSourceHealthDatabase.swift');
  for (const token of ['SQLITE_OPEN_FULLMUTEX', 'PRAGMA synchronous = FULL', 'PRAGMA fullfsync = ON',
    'BEGIN IMMEDIATE TRANSACTION', 'if !committed { try? execute("ROLLBACK") }', 'try beforeCommit()',
    'web_health_recency ON web_health(updated_at DESC,source_key)', ' WHERE source_key IN (',
    'SELECT COUNT(*) FROM web_health', 'LIMIT 513', 'OFFSET 512',
    'HKDF<SHA256>.deriveKey', 'HMAC<SHA256>.authenticationCode', 'authenticating: self.purpose(purpose)',
    'value.lastAttemptAtMillis == sqlite3_column_int64', 'if try initialized() { return }',
    'guard allowLegacyImport else { throw Failure.corrupt }',
    'CREATE TABLE IF NOT EXISTS web_health_migration', 'purpose: "migration"',
    'isExcludedFromBackup = true', 'FileProtectionType.completeUntilFirstUserAuthentication', 'typeSymbolicLink'])
    assert(database.includes(token), token);
  assert(!database.includes('Snapshot') && !database.includes('readUnlocked'));
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebSourceHealthDatabaseTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 9);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebSourceHealthDatabase', 'AgentIOSWebSourceHealthDatabaseTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
  console.log('iOS indexed encrypted source-health migration, scoped reads and batch transaction source contracts passed; no native execution');
}

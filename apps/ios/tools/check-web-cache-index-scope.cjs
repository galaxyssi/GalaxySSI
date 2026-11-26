// Source checks only. This does not execute SQLite, CryptoKit, XCTest or a migration.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'b8a15bb0a25d2e9605161305c382f061fd581c05';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const isIndexedCache = source => source.includes('  private func cacheIndexUnlocked()');
function retainedMetadataProvider(source) {
  source = require('./check-search-result-capacity-scope.cjs').retainedCapacityProvider(source);
  if (!source.includes('struct AgentIOSURLSessionWebIntelligenceProvider') || !source.includes('cacheStore.cacheMetadata()')) return source;
  return source.replaceAll('cacheStore.cacheMetadata()', 'cacheStore.stats()')
    .replace('    case "status":\n      cacheMetadata = cacheStore.stats()', '    case "status":\n      break');
}
function validateIndexedCache() {
  const cache = read(app + 'AgentIOSWebIntelligenceCache.swift'), index = read(app + 'AgentIOSWebCacheIndex.swift');
  assert(isIndexedCache(cache));
  const prior = cp.execFileSync('git', ['show', base + ':' + app + 'AgentIOSWebIntelligenceCache.swift'],
    {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
  const section = (text, start, end) => text.slice(text.indexOf(start), text.indexOf(end, text.indexOf(start) + start.length));
  assert.equal(cache.slice(0, cache.indexOf('final class AgentIOSWebIntelligenceCacheStore')),
    prior.slice(0, prior.indexOf('final class AgentIOSWebIntelligenceCacheStore')), 'Document/watch public projections retained');
  assert.equal(section(cache, '  private struct Snapshot:', '  private struct SearchResponse:'),
    section(prior, '  private struct Snapshot:', '  private struct SearchResponse:'), 'Legacy decoder schemas retained');
  assert.equal(section(require('./check-search-result-capacity-scope.cjs').retainedCapacityCache(cache), '  private struct SearchResponse:', '  func searchResponse('),
    section(prior, '  private struct SearchResponse:', '  func searchResponse('), 'Exact response validation and bounds retained');
  for (const token of ['static let maxDocuments = 2_000', 'snapshot.documents.count <= 64',
    'cacheIndexUnlocked().entry(.search, id: key)', 'cacheIndexUnlocked().entry(.document, id: cleanURL)',
    'cacheIndexUnlocked().putSearch', 'expected: expectedGeneration', 'cacheIndexUnlocked().generation()',
    'index.prune(.document, limit: Self.maxDocuments)', 'cacheIndexUnlocked().forEach(.document)',
    'Int64(value.content.utf16.count)', 'ranked.count > max(1, min(limit, 100))',
    'cacheIndexUnlocked().clear(expiredOnly:', 'index.entries(.learned, limit:',
    'index.entry(.learned, id: observation.sourceID)', 'index.prune(.learned, limit:',
    'cacheIndexUnlocked().entry(.watch, id: id)', 'index.remove(.watch, id: id)',
    'cacheIndexUnlocked().metadata(now:', 'healthIndexUnlocked().count()',
    'initialize(allowImport: receipt != "1")', 'secrets.setString("pending", account: cacheImportAccount)',
    'secrets.setString("1", account: cacheImportAccount)', 'secrets.string(account: cacheImportAccount) == nil',
    'try? fileManager.removeItem(at: fileURL)', '"legacy_cleanup_pending"', 'healthIndexUnlocked(legacyHealth: snapshot.sourceHealth ?? [])',
    'let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self', 'AES.GCM.open(sealed, using: key)',
    'entry.key == key, entry.storedAtMillis <= now, now < entry.expiresAtMillis']) assert(cache.includes(token), token);
  assert.equal((cache.match(/readLegacyUnlocked\(\)/g) || []).length, 3, 'Legacy decoder only in its declaration and the two domain import closures');
  assert(!cache.includes('writeUnlocked') && !cache.includes('writeFile'));
  for (const token of ['case document, search, watch, learned', 'UNIQUE(kind,entry_key)',
    'cache_insertion ON cache_rows(kind,row_id DESC)', 'INSERT OR REPLACE INTO cache_rows',
    'cache_recency ON cache_rows(kind,updated DESC,entry_key)', 'cache_expiry ON cache_rows(kind,expires)',
    'BEGIN IMMEDIATE TRANSACTION', 'if !committed { try? execute("ROLLBACK") }', 'try beforeCommit()',
    'if let expected, try generation() != expected', 'throw Failure.staleGeneration',
    'remove(.document, before: expiredOnly ? now : nil, inclusive: false)',
    'remove(.search, before: expiredOnly ? now : nil)', 'expiredOnly ? 0 : try remove(.learned)',
    'if !expiredOnly { try writeMarker', 'HKDF<SHA256>.deriveKey', 'HMAC<SHA256>.authenticationCode',
    'authenticating: aad(purpose)', 'entry.updated == sqlite3_column_int64', 'entry.characters == sqlite3_column_int64',
    'COALESCE(SUM(characters),0)', 'SELECT COUNT(*)', 'guard allowImport else', 'PRAGMA synchronous=FULL',
    'PRAGMA fullfsync=ON', 'resources.isExcludedFromBackup = true', 'FileProtectionType.completeUntilFirstUserAuthentication'])
    assert(index.includes(token), token);
  assert(!index.includes('remove(.watch') && !index.includes('remove(.sourceHealth'));
  const provider = read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  assert.equal(retainedMetadataProvider(provider), cp.execFileSync('git', ['show', base + ':' + app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'],
    {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n'), 'Only indexed metadata calls and explicit detailed-status selection changed');
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebCacheIndexTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 7);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebCacheIndex', 'AgentIOSWebCacheIndexTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {isIndexedCache, retainedMetadataProvider, validateIndexedCache};
if (require.main === module) {
  validateIndexedCache();
  console.log('iOS indexed cache rows, shared clear/generation, bounded scans and migration source checks passed; no native execution');
}

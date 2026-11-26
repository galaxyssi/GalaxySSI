// Static source contracts only; no Swift, native SQLite, filesystem or crash execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '2931b3745de15e95f917d306f7adb15ac54cafdd';
const app = 'apps/ios/GalaxySSI/', primaryFile = app + 'AgentKnowledgePrimaryPartitions.swift';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) { const a = source.indexOf(start), b = source.indexOf(end, a + start.length); assert(a >= 0 && b > a, start); return source.slice(a, b); }
const wrapper = `    var result = Data()
    try walkFrames(database, reference: reference, itemHash: itemHash, partition: partition, checkActive: checkActive) {
      _, plain, _ in result.append(plain)
    }
    return result
  }

  // Authenticate and hash bounded frames; consumers need not retain complete bodies.
  private func walkFrames(_ database: OpaquePointer, reference: Reference, itemHash: String, partition: String,
                          checkActive: () throws -> Void, consume: (Data, Data, Int) throws -> Void) throws {
`;
let pinnedPrimary;
function retained(f, source) {
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgePrimaryCompaction(?:Tests)?\.swift/.test(l)).join('\n');
  if (f !== primaryFile || !source.includes('  private func compactExclusively(')) return source;
  pinnedPrimary ??= old(primaryFile);
  source = source.replace('    var moved: Int = 0\n', '').replace('    try AgentKnowledgePrimaryCompaction.setup(catalog)\n', '')
    .replace(', deferred: false, moved: retired.moved)', ', deferred: false)')
    .replace(', deferred: false, moved: moved)', ', deferred: false)');
  const header = '  private func reference(itemHash: String, catalog: OpaquePointer) throws -> Reference? {\n';
  const helper = section(source, header, '  private func readPayload(');
  const body = helper.slice(header.length).replace('    return reference\n  }\n\n', '');
  source = source.replace(helper, '').replace('    guard let reference = try reference(itemHash: itemHash, catalog: catalog) else { return nil }\n    let partition = reference.partition\n', body)
    .replace(wrapper, '')
    .replace('SELECT ordinal,substr(sealed,1,196609) FROM frames', 'SELECT ordinal,sealed FROM frames')
    .replace('    var plainBytes: Int64 = 0, ordinal = 0\n    var hash = SHA256()\n', '    var result = Data(), ordinal = 0\n')
    .replace('reference.plainBytes - plainBytes)', 'reference.plainBytes - Int64(result.count))')
    .replace('      hash.update(data: plain)\n      try consume(encoded, plain, ordinal)\n      plainBytes += Int64(plain.count)\n', '      result.append(plain)\n')
    .replace('    guard ordinal == reference.frames, plainBytes == reference.plainBytes,\n          hash.finalize().map({ String(format: "%02x", $0) }).joined() == reference.sha256 else {\n      throw AgentKnowledgeDatabaseError.corruptRecord\n    }\n',
      '    guard ordinal == reference.frames, Int64(result.count) == reference.plainBytes,\n          Self.sha256(result) == reference.sha256 else { throw AgentKnowledgeDatabaseError.corruptRecord }\n    return result\n');
  source = source.replace(section(source, '  // Already inside withExclusiveAccess:', '  private func reclaimExclusively('), '');
  source = source.replace('  private func reclaimExclusively(catalog: OpaquePointer, pageSize: Int, checkActive: () throws -> Void) throws -> ReclaimPage {\n    let moved = try compactExclusively(catalog: catalog, checkActive: checkActive)\n',
    section(pinnedPrimary, '  private func reclaimExclusively(', '    let queued = try prepare('));
  source = source.replace(section(source, '  private func reclaimPending(', '  private func unlinkRetired('),
    section(pinnedPrimary, '  private func reclaimPending(', '  private func unlinkRetired('));
  return source;
}
function validate() {
  const primary = read(primaryFile);
  assert.equal(retained(primaryFile, primary), old(primaryFile), 'Retain namespace/crypto/schema/append/batching/slots/cache/leases/unlink except declared compaction and streaming hooks');
  assert(primary.includes('try AgentKnowledgePrimaryCompaction.setup(catalog)'));
  assert(primary.includes(wrapper));
  assert(primary.includes('try AgentKnowledgePrimaryCompaction.pending(catalog)'));
  assert(primary.includes('let moved = try compactExclusively(catalog: catalog, checkActive: checkActive)'));
  const compact = section(primary, '  private func compactExclusively(', '  private func relocate(');
  for (const text of ['writeBatch == nil, sqlite3_get_autocommit(catalog) != 0', 'BEGIN IMMEDIATE TRANSACTION',
    'writeBatch = batch', 'if !committed { try? execute(catalog, "ROLLBACK") }', 'writers.removeAll(); writeBatch = nil',
    'AgentKnowledgePrimaryCompaction.advance(catalog, checkActive: checkActive)', 'try relocate(itemHash: key, source: source',
    'for bucket in writers.keys.sorted() { try flushWriter', 'if batch.hasWrites { try syncRoot(); try beforeCatalogPublication() }',
    'try AgentKnowledgePrimaryDurability.verify(catalog, role: .catalog)', 'try execute(catalog, "COMMIT")']) assert(compact.includes(text), text);
  assert(compact.indexOf('try flushWriter') < compact.indexOf('try beforeCatalogPublication()'));
  assert(compact.indexOf('try beforeCatalogPublication()') < compact.indexOf('try execute(catalog, "COMMIT")'));
  const relocate = section(primary, '  private func relocate(', '  private func reclaimExclusively(');
  for (const text of ['old.partition == source', 'destination != source', 'batch.pending.insert(destination)', 'batch.hasWrites = true',
    'readerSlots.acquire(checkActive: checkActive)', 'readConnections.read(root: root', 'try walkFrames(reader',
    'cipher.encrypt(encoded, purpose: framePurpose(itemHash, partition: destination', 'sqlite3_reset(insert) == SQLITE_OK',
    'WHERE item_hash=? AND partition_id=?', 'plainBytes: old.plainBytes, sha256: old.sha256', 'sqlite3_changes(catalog) == 1',
    'Int64.max - storedBytes']) assert(relocate.includes(text), text);
  for (const text of ['ensureSharedLease()', 'writerLock.lock()', 'beginWriteBatch(', 'readPayload(', 'readFrames(', 'appendFrames(', 'var result = Data()']) {
    assert(!relocate.includes(text), text); assert(!compact.includes(text), text);
  }
  const walk = section(primary, '  private func walkFrames(', '  // Independent catalog snapshots');
  for (const text of ['substr(sealed,1,196609)', 'maximum: Self.maximumSealedFrame', 'framePurpose(itemHash, partition: partition',
    'AgentKnowledgePrimaryFrameCodec.decode(encoded)', 'hash.update(data: plain)', 'try consume(encoded, plain, ordinal)',
    'ordinal == reference.frames, plainBytes == reference.plainBytes', 'hash.finalize()', 'reference.sha256']) assert(walk.includes(text), text);
  assert(!walk.includes('result.append'));
  const queue = read(app + 'AgentKnowledgePrimaryCompaction.swift');
  for (const text of ['CREATE TABLE IF NOT EXISTS knowledge_primary_dirty', 'after_partition TEXT NOT NULL',
    'knowledge_primary_dirty_insert', 'knowledge_primary_dirty_delete', 'knowledge_primary_dirty_move', 'OLD.partition_id<>NEW.partition_id',
    'sqlite3_get_autocommit(db) == 0', 'partition_id>? ORDER BY partition_id LIMIT 32',
    'knowledge_primary_dirty ORDER BY partition_id LIMIT 8', 'partition_id=? ORDER BY item_hash LIMIT 8',
    'live <= records / 2', 'SET sealed=1', 'SET source=?', 'SET source=\'\'', 'try relocate(key, source)',
    'INSERT OR IGNORE INTO knowledge_primary_retired', 'WHERE discovered=0 OR source<>\'\'',
    'keys.last ?? after, keys.count < 32 ? "1" : "0"', 'AgentKnowledgeSQLiteStatements.shared.prepare',
    'sqlite3_step($0) == SQLITE_DONE']) assert(queue.includes(text), text);
  const guard = 'apps/ios/tools/check-knowledge-read-connections-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-primary-compaction-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-primary-compaction-scope.cjs').retained(f, source);\n"));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(retained(project, read(project)), old(project));
  for (const name of ['AgentKnowledgeDatabase', 'AgentKnowledgePrimaryReadConnections', 'AgentKnowledgeReadConnectionPool',
    'AgentKnowledgeSQLiteStatements', 'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgePrimaryAllocations',
    'AgentKnowledgePrimaryDurability', 'AgentKnowledgePrimaryFrameCodec', 'AgentKnowledgeStorageBackground'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgePrimaryCompactionTests.swift');
  assert.equal((fixture.match(/  func test/g) || []).length, 15);
  for (const text of ['testEightRecordPagesResumeFromRemainingSourceReferences', 'testBetweenPageDeletionAndReplacementWinWithoutResurrection',
    'testPhysicalCommitBeforeCatalogFailureKeepsOldReferenceAuthoritative', 'testCompactionNeverDowngradesExclusivePhysicalLease',
    'testExistingBackgroundStorageSlicePreservesLogicalSourceRevision', 'testLegacyDiscoveryAndCandidateSelectionUseBoundedKeysetPages',
    'testCatalogCommitSurvivesFailureBeforePhysicalUnlink', 'testCorruptAndOversizedFrameRejectWithoutPublishingDestination',
    'AgentKnowledgePrimaryPartitionsTests.Fixture', 'maximumPages: 8']) assert(fixture.includes(text), text);
  console.log('Bounded dirty discovery/selection, streaming authenticated relocation, physical-before-catalog publication, retained EX/snapshot/cache barriers and 15 authored-only fixtures passed source contracts; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

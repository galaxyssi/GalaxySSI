// Source contracts only; not Swift/native SQLite/device/recovery acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '3b8340ced4f3779daaaa2e8ec9ae3cca5e84c983', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
const headerEncoding = `    let sealedHeader: Data, encrypted: Data
    do {
      let header = AgentKnowledgePrimaryMetadata.Header(itemHash: itemHash, sourceHash: keyedHash(sourceIdentity(item)),
        updatedAtMillis: item.updatedAtMillis, bodySHA256: SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined())
      sealedHeader = try cipher.encrypt(JSONEncoder().encode(header), purpose: AgentKnowledgePrimaryMetadata.purpose(itemHash))
      encrypted = try AgentKnowledgePrimaryMetadata.pointer(sealedHeader)
    } catch { return false }
`;
const finalMetadata = `      if old.headerHash != nil {
        guard let prefix = Int(job.key.prefix(2), radix: 16) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        let database = try writer(id: job.destination, bucket: prefix & 3)
        try execute(database, "BEGIN IMMEDIATE TRANSACTION")
        batch.pending.insert(job.destination); batch.hasWrites = true
        let bytes = try copyHeader(old, target: target, catalog: catalog, database: database, checkActive: { try Self.finishCheckpoint(checkActive) })
        try AgentKnowledgePrimaryCopyStore.accountMetadata(catalog, job, previous: state.storedBytes, added: bytes)
      }
`;
function retained(f, source) {
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgePrimaryMetadata(?:Integration)?(?:Tests)?\.swift/.test(l)).join('\n');
  if (f === app + 'AgentKnowledgePrimaryCopyStore.swift' && source.includes('  static func accountMetadata(')) return source.replace(section(source, '  static func accountMetadata(', '  static func checkpoint('), '');
  if (f === app + 'AgentKnowledgeDatabase.swift' && source.includes('  private func validatePrimaryHeader(')) return source
    .replace(headerEncoding, '    let encrypted = Data([0])\n')
    .replace('primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database, header: sealedHeader)', 'primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database)')
    .replace('    if let header = try primaryPayloads.resolveHeader(itemHash: itemHash, catalog: catalog, stored: encrypted) {\n      try validatePrimaryHeader(header, item: item, itemHash: itemHash, catalog: catalog)\n    }\n', '')
    .replace(section(source, '  private func validatePrimaryHeader(', '  private func insertExternalPayload('), '');
  if (f !== app + 'AgentKnowledgePrimaryPartitions.swift' || !source.includes('  func resolveHeader(')) return source;
  return source.replace('    var headerHash: String? = nil\n', '')
    .replace('catalog: OpaquePointer, header: Data? = nil, checkActive:', 'catalog: OpaquePointer, checkActive:')
    .replace('catalog: catalog, batch: batch, header: header, checkActive:', 'catalog: catalog, batch: batch, checkActive:')
    .replace('catalog: OpaquePointer, batch: WriteBatch?, header: Data?,', 'catalog: OpaquePointer, batch: WriteBatch?,')
    .replace('    let headerHash = try header.map { try AgentKnowledgePrimaryMetadata.hash($0) }\n', '')
    .replace('      if let header { storedBytes = try AgentKnowledgePrimaryMetadata.write(database, entry: entry, encrypted: header) }\n', '')
    .replace('Reference(version: headerHash == nil ? 1 : 2, partition: id, entry: entry, frames: frameCount,\n      plainBytes: Int64(plain.count), sha256: Self.sha256(plain), headerHash: headerHash)',
      'Reference(version: 1, partition: id, entry: entry, frames: frameCount,\n      plainBytes: Int64(plain.count), sha256: Self.sha256(plain))')
    .replace(section(source, '  func resolveHeader(', '  private func reference('), '')
    .replace('    guard (reference.version == 1 && reference.headerHash == nil) ||\n            (reference.version == 2 && reference.headerHash.map(AgentKnowledgePrimaryMetadata.digest) == true),\n          Self.token(partition)', '    guard reference.version == 1, Self.token(partition)')
    .replaceAll('sha256: old.sha256, headerHash: old.headerHash)', 'sha256: old.sha256)')
    .replace('    let headerBytes = try copyHeader(old, target: next, catalog: catalog, database: database, checkActive: { try Self.finishCheckpoint(checkActive) })\n    guard storedBytes <= Int64.max - headerBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }\n    storedBytes += headerBytes\n', '')
    .replace(finalMetadata, '')
    .replace('      try AgentKnowledgePrimaryMetadata.configure(database, writable: false)\n', '')
    .replace('      try AgentKnowledgePrimaryMetadata.configure(database, writable: true)\n', '');
}
function validate() {
  for (const f of [app + 'AgentKnowledgeDatabase.swift', app + 'AgentKnowledgePrimaryPartitions.swift', app + 'AgentKnowledgePrimaryCopyStore.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) assert.equal(retained(f, read(f)), old(f), f);
  const guard = 'apps/ios/tools/check-knowledge-primary-copy-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-primary-metadata-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-primary-metadata-scope.cjs').retained(f, source);\n"));
  const database = read(app + 'AgentKnowledgeDatabase.swift'), primary = read(app + 'AgentKnowledgePrimaryPartitions.swift');
  assert(database.includes(headerEncoding));
  assert(database.includes('primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database, header: sealedHeader)'));
  assert(database.includes('primaryPayloads.resolveHeader(itemHash: itemHash, catalog: catalog, stored: encrypted)'));
  const validation = section(database, '  private func validatePrimaryHeader(', '  private func insertExternalPayload(');
  for (const text of ['expectedPurpose: AgentKnowledgePrimaryMetadata.purpose(itemHash)', 'header.version == 1', 'header.itemHash == itemHash',
    'header.sourceHash == keyedHash(sourceIdentity(item))', 'header.updatedAtMillis == item.updatedAtMillis',
    'header.bodySHA256 == resolved.bodySHA256', 'prepare(catalog, "SELECT source_hash,updated_at',
    'String(cString: source) == header.sourceHash', 'sqlite3_column_int64(row, 1) == header.updatedAtMillis']) assert(validation.includes(text), text);
  for (const text of ['headerHash: headerHash', 'reference.version == 1 && reference.headerHash == nil',
    'reference.version == 2 && reference.headerHash.map', 'AgentKnowledgePrimaryMetadata.write(database, entry: entry, encrypted: header)',
    'sha256: old.sha256, headerHash: old.headerHash)', finalMetadata]) assert(primary.includes(text), text);
  const resolver = section(primary, '  func resolveHeader(', '  private func reference(');
  for (const text of ['writerLock.lock()', 'readerLock.lock()', 'try ensureSharedLease()', 'guard expected == nil', 'guard hash == expected',
    'batch.thread === Thread.current, !batch.failed', 'batch.pending.contains(reference.partition)',
    'readerSlots.acquire(checkActive: checkActive)', 'readConnections.read(root: root',
    'source.headerHash == target.headerHash', 'AgentKnowledgePrimaryMetadata.read(database, entry: target.entry, expected: hash) == encrypted']) assert(resolver.includes(text), text);
  assert(!section(resolver, '  private func copyHeader(', '    return bytes').includes('ensureSharedLease'));
  const metadata = read(app + 'AgentKnowledgePrimaryMetadata.swift');
  for (const text of ['Data("khp1:".utf8)', 'stored.count == 69', 'maximumHeaderBytes = 4_096',
    'guard sqlite3_get_autocommit(db) == 0', '(0...2).contains(version)', 'if writable && version < 2',
    'CREATE TABLE headers(entry_id TEXT PRIMARY KEY,sealed BLOB NOT NULL) WITHOUT ROWID',
    'PRAGMA user_version=2', 'AgentKnowledgePrimaryDurability.verify(db, role: .primary)',
    'DELETE FROM headers WHERE entry_id=?', 'INSERT INTO headers(entry_id,sealed)', 'substr(sealed,1,4097)', 'hash(encrypted) == expected']) assert(metadata.includes(text), text);
  const open = section(primary, '  private func open(_ id:', '  private func prepare(');
  assert(open.indexOf('Metadata.configure(database, writable: true)') < open.indexOf('FileManager.default.setAttributes'));
  assert(open.includes('Metadata.configure(database, writable: false)'));
  const store = read(app + 'AgentKnowledgePrimaryCopyStore.swift');
  assert(store.includes('SET bytes=bytes+? WHERE partition_id=? AND bytes=? AND sealed=1 AND records=1'));
  assert(primary.indexOf('CopyStore.accountMetadata(catalog') < primary.indexOf('CopyStore.publish(catalog'));
  const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgePrimaryMetadataTests.swift');
  assert.equal((fixture.match(/  func test/g) || []).length, 15);
  for (const name of ['testHeaderOnlyResolutionDoesNotMaterializeBodyFrames', 'testPendingOwnedBatchReadsHeaderWithoutIndependentReaderSlot',
    'testLegacyVersionZeroReadsUnchangedThenUpgradesOnWrite', 'testCheckpointedCopyCopiesHeaderBeforeFinalPublicationAndReplaysIdempotently',
    'testActualDatabaseUsesPointersAndRejectsIndexTampering', 'testActualDatabaseRelocationPreservesSourceAndVectorRevisionIdentity',
    'testFailureAfterStagingHeaderAndFramesDoesNotPublishEither', 'testLegacyInlineRecordRemainsReadableWithoutForcedHeaderRewrite']) assert(fixture.includes(name), name);
  for (const name of ['AgentKnowledgePrimaryCompaction', 'AgentKnowledgePrimaryCopyState', 'AgentKnowledgePrimaryReadConnections',
    'AgentKnowledgeReadConnectionPool', 'AgentKnowledgeSQLiteStatements', 'AgentKnowledgePrimaryReaderSlots',
    'AgentKnowledgePrimaryAllocations', 'AgentKnowledgePrimaryDurability', 'AgentKnowledgePrimaryFrameCodec', 'AgentKnowledgeStorageBackground'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const integration = read('apps/ios/GalaxySSITests/AgentKnowledgePrimaryMetadataIntegrationTests.swift');
  assert.equal((integration.match(/  func test/g) || []).length, 4);
  for (const name of ['PreparedSourceWritesHeaderPointerAndReopensWithAuthenticatedBody',
    'PreparationRejectsCatalogTimestampTamperingAgainstPhysicalHeader',
    'PostPreparationIndexMutationFailsGenerationFenceBeforePublishingHeader',
    'PreparedPrecommitFailureKeepsOriginalHeaderPointerBodyAndOutbox']) assert(integration.includes('func test' + name + '('), name);
  assert(read('apps/ios/GalaxySSITests/AgentKnowledgePrimarySourceIntegrationTests.swift').includes("length(encrypted_payload)=69 AND CAST(substr(encrypted_payload,1,5) AS TEXT)='khp1:'"));
  console.log('Actual authenticated primary headers/pointers, snapshot-index validation, header-before-reference copy publication, checked physical schema upgrade and 15 authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

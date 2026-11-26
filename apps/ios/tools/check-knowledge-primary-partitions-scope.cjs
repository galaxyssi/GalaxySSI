// Source contracts only. No Swift/Compression/CryptoKit/SQLite or XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const names = ['AgentKnowledgePrimaryFrameCodec.swift', 'AgentKnowledgePrimaryPartitions.swift', 'AgentKnowledgePrimaryPartitionsTests.swift'];
const properties = '  private let primaryPayloads: AgentKnowledgePrimaryPartitions\n' +
  '  private let primaryMigrationQueue = DispatchQueue(label: "galaxyssi.knowledge.primary-migration", qos: .utility)\n' +
  '  private let primaryMigrationControl = NSLock()\n' +
  '  private var primaryMigrationRunning = false\n';
function retained(file, source) {
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line => !names.some(name => line.includes(name))).join('\n');
  if (file.endsWith('GalaxySSIServices.swift')) return source.replace('    store.agentKnowledgeDatabase.startPrimaryPayloadMigration()\n', '');
  if (file.endsWith('AgentKnowledgeDatabase.swift') && source.includes('  struct PrimaryMigrationPage:')) {
    const original = old(file);
    source = source.replace(properties, '')
      .split('    let primarySnapshotLease = try primaryPayloads.snapshotLease()\n    defer { withExtendedLifetime(primarySnapshotLease) {} }\n').join('')
      .replace('    var deferred: Bool = false\n', '')
      .replace('    primaryPayloads = AgentKnowledgePrimaryPartitions(catalogURL: fileURL, secrets: secrets)\n', '')
      .replace(section(source, '  struct PrimaryMigrationPage:', '  @discardableResult\n  func maintainExternalPayloads('), '')
      .split('      try primaryPayloads.checkSharedAccess()\n').join('')
      .replace('        WHERE item_hash > ? AND NOT EXISTS(SELECT 1 FROM knowledge_primary_refs p WHERE p.item_hash=knowledge_items.item_hash)\n        ORDER BY item_hash ASC LIMIT ?',
        '        WHERE item_hash > ? ORDER BY item_hash ASC LIMIT ?')
      .replace('    guard let database else { return }\n    do { try primaryPayloads.setup(catalog: database) }\n    catch { sqlite3_close_v2(database); self.database = nil; return }\n', '');
    const start = '  private func insert(_ item:', end = '  private func validateIdentities(';
    const actual = section(source, start, end), prior = section(original, start, end);
    const external = section(prior, '    let external = plaintext.count', '    guard let statement = prepare(');
    source = source.replace(actual, actual.replace('    let encrypted = Data([0])\n', external)
      .replace('    guard let database else { return false }\n    do { try primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database) }\n    catch { return false }',
        '    if external, !insertExternalPayload(plaintext, itemHash: itemHash) { return false }'));
    const decodeStart = '    guard let catalog = sqlite3_db_handle(statement)', decodeEnd = '          keyedHash(item.id) == itemHash else';
    source = source.replace(section(source, decodeStart, decodeEnd),
      section(original, '    let external = readExternalPayload(itemHash: itemHash, database: sqlite3_db_handle(statement))', decodeEnd));
    const reclaimStart = '  @discardableResult\n  func reclaimExternalPayloadFiles(', reclaimEnd = '  @discardableResult\n  func replaceAll(';
    const actualReclaim = section(source, reclaimStart, reclaimEnd);
    const helperPrefix = '  private func reclaimExternalPayloadFilesExclusively(\n    pageSize: Int,\n    minimumAge: TimeInterval\n  ) throws -> ExternalPayloadReclamation {\n    do {\n';
    const helperOffset = actualReclaim.indexOf(helperPrefix);
    assert(helperOffset > 0);
    const wrapper = actualReclaim.slice(0, helperOffset);
    assert.equal(wrapper, '  @discardableResult\n  func reclaimExternalPayloadFiles(\n    pageSize: Int = 32,\n    minimumAge: TimeInterval = 3_600\n  ) throws -> ExternalPayloadReclamation {\n    try locked {\n      guard let database else { throw AgentKnowledgeDatabaseError.unavailable }\n      return try primaryPayloads.withExclusiveAccess(catalog: database) {\n        try reclaimExternalPayloadFilesExclusively(pageSize: pageSize, minimumAge: minimumAge)\n      } ?? ExternalPayloadReclamation(removedFiles: 0, removedBytes: 0, complete: false, deferred: true)\n    }\n  }\n\n');
    const restoredReclaim = actualReclaim.slice(helperOffset)
      .replace(helperPrefix, '  @discardableResult\n  func reclaimExternalPayloadFiles(\n    pageSize: Int = 32,\n    minimumAge: TimeInterval = 3_600\n  ) throws -> ExternalPayloadReclamation {\n    try locked {\n')
      .replace('      guard try FileManager.default.attributesOfItem(atPath: payloadDirectory.path)[.type] as? FileAttributeType == .typeDirectory else {\n        throw AgentKnowledgeDatabaseError.corruptRecord\n      }\n', '')
      .replace('let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),\n              values.isRegularFile == true, values.isSymbolicLink == false,',
        'let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),');
    assert.equal(restoredReclaim, section(original, reclaimStart, reclaimEnd));
    source = source.replace(actualReclaim, restoredReclaim);
    return source;
  }
  if (file.endsWith('AgentKnowledgeDatabaseTests.swift')) {
    for (const [start, end] of [['  func testKnowledgePayloadsExternalizeAndMigrateWithoutChangingLogicalRows()', '  func testExternalPayloadReclamationRemovesOnlyOldUnreferencedFiles()'],
      ['  func testExternalPayloadReclamationRemovesOnlyOldUnreferencedFiles()', '  func testKnowledgeSearchSnapshotReturnsOnlyCurrentRows()']]) {
      const actual = section(source, start, end);
      source = source.replace(actual, actual
        .replace('    let secrets = InMemorySecretStore()\n    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)',
          '    let database = AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore())')
        .split('\n').filter(line => !line.includes('try seedLegacyKnowledgePayloads(')).join('\n'));
    }
    return source;
  }
  if (file.endsWith('AgentKnowledgeAsyncRAGTests.swift')) return source.replace('".payloads", ".primary", ".native"', '".payloads", ".native"');
  if (file.endsWith('check-desktop-probe-owner-scope.cjs')) return source
    .replace("const read = file => require('./check-knowledge-primary-partitions-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-knowledge-primary-partitions-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'AgentKnowledgeDatabase.swift', app + 'GalaxySSIServices.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    'apps/ios/GalaxySSITests/AgentKnowledgeDatabaseTests.swift', 'apps/ios/GalaxySSITests/AgentKnowledgeAsyncRAGTests.swift',
    'apps/ios/tools/check-desktop-probe-owner-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const inventory = JSON.parse(read('apps/ios/ANDROID_3037_SOURCE_INVENTORY.json'));
  assert.equal(inventory.productionFiles.length, 8);
  for (const entry of inventory.productionFiles) {
    const value = cp.execFileSync('git', ['show', inventory.androidCommit + ':apps/android/app/src/main/java/com/galaxyssi/chat/' + entry.name + '.kt'], {cwd: root, maxBuffer: 32 * 1024 * 1024});
    assert.equal(crypto.createHash('sha256').update(value).digest('hex'), entry.sha256, entry.name);
  }
  const database = read(app + 'AgentKnowledgeDatabase.swift');
  const insert = section(database, '  private func insert(_ item:', '  private func validateIdentities(');
  assert(insert.includes('let encrypted = Data([0])') && insert.includes('try primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database)'));
  assert(!insert.includes('insertExternalPayload(') && !insert.includes('cipher.encrypt(plaintext'));
  const decode = section(database, '  private func decode(\n', '  private func insertExternalPayload(');
  assert(decode.includes('if let primary = try primaryPayloads.read(itemHash: itemHash, catalog: catalog)'));
  assert(!decode.includes('try? primaryPayloads.read'));
  const worker = section(database, '  func startPrimaryPayloadMigration(', '  @discardableResult\n  func maintainExternalPayloads(');
  for (const token of ['guard !primaryMigrationRunning, database != nil', '.milliseconds(100)', '[weak self]',
    'self.maintainPrimaryPayloads(pageSize: 8)', 'self.primaryMigrationRunning = false']) assert(worker.includes(token), token);
  assert.equal(read(app + 'GalaxySSIServices.swift').split('    store.agentKnowledgeDatabase.startPrimaryPayloadMigration()\n').length, 2);
  const migration = section(database, '  func maintainPrimaryPayloads(', '  func startPrimaryPayloadMigration(');
  for (const token of ['execute("BEGIN IMMEDIATE TRANSACTION")', 'pageSize: Int = 8', 'try primaryPayloads.append(',
    'try primaryPayloads.read(', 'UPDATE knowledge_items SET encrypted_payload=x\'00\'', 'UPDATE knowledge_primary_migration',
    'defer { if !committed { _ = execute("ROLLBACK") } }']) assert(migration.includes(token), token);
  for (const token of ['replaceAll(', 'nativeFiles.invalidate(', 'UPDATE knowledge_source', 'UPDATE knowledge_vector', 'revision = revision +']) assert(!migration.includes(token), token);
  const storage = read(app + names[1]);
  for (const token of ['partitionBytes: Int64 = 64 * 1_024 * 1_024', 'partitionRecords: Int64 = 65_536', 'let bucket = prefix & 3',
    'sqlite3_get_autocommit(catalog) == 0', 'try beforeCatalogPublication()',
    'reference.frames', 'Self.sha256(result) == reference.sha256']) assert(storage.includes(token), token);
  assert(storage.indexOf('try execute(database, "COMMIT")') < storage.indexOf('try beforeCatalogPublication()'));
  assert(storage.indexOf('try beforeCatalogPublication()') < storage.indexOf('INSERT INTO knowledge_primary_refs'));
  const rotation = section(storage, '  private func partition(catalog:', '  private func writer(id:');
  assert(rotation.indexOf('writers.removeValue(forKey: bucket)') >= 0 &&
    rotation.indexOf('writers.removeValue(forKey: bucket)') < rotation.indexOf('try open(id, create: true, readOnly: false)'));
  assert(storage.includes('resources.isExcludedFromBackup = false'));
  assert(storage.includes('catalogURL.lastPathComponent') && storage.includes('CREATE TABLE IF NOT EXISTS knowledge_primary_namespace'));
  for (const token of ['private let writerLock = NSLock()', 'private let readerLock = NSLock()',
    'expectedPurpose: framePurpose(itemHash, partition: partition, entry: reference.entry, ordinal: ordinal)',
    'guard ordinal == reference.frames', 'ordinal < reference.frames', 'sqlite3_close_v2(prior.database)',
    'SQLITE_OPEN_READONLY', 'FileProtectionType.completeUntilFirstUserAuthentication']) assert(storage.includes(token), token);
  assert(!storage.includes('removeItem(')); // No recursive/path-based removal of the private root.
  for (const token of ['CREATE TABLE IF NOT EXISTS knowledge_primary_retired', 'func snapshotLease()',
    'Self.flock(accessDescriptor, LOCK_EX)', 'sharedLease = false', 'try ensureSharedLease()',
    'O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC', 'Darwin.openat(directoryDescriptor, ".access.lock"',
    'AT_SYMLINK_NOFOLLOW', 'Darwin.unlinkat(directoryDescriptor, name, 0)', 'Darwin.fsync(directoryDescriptor)',
    'guard state == SQLITE_DONE', 'try beforeRetiredUnlink()', 'try afterRetiredUnlink()']) assert(storage.includes(token), token);
  const reclaim = section(storage, '  private func reclaimExclusively(', '  private func reclaimPending(');
  assert(reclaim.indexOf('try execute(catalog, "COMMIT")') < reclaim.indexOf('try unlinkRetired(id)'));
  assert(reclaim.indexOf('try afterRetiredUnlink()') < reclaim.indexOf('DELETE FROM knowledge_primary_retired'));
  const exclusive = section(storage, '  func withExclusiveAccess<T>(', '  func reclaimLegacyCopies(');
  assert(exclusive.includes('sqlite3_get_autocommit(catalog) != 0'));
  assert(exclusive.indexOf('Self.flock(accessDescriptor, LOCK_EX)') < exclusive.indexOf('return try operation()'));
  const legacy = section(storage, '  func reclaimLegacyCopies(', '  private func reclaimExclusively(');
  for (const token of ['withExclusiveAccess(catalog: catalog)', 'pageSize: Int = 8', 'WHERE item_hash>? ORDER BY item_hash LIMIT ?',
    'sqlite3_bind_int(select, 2, Int32(pageSize + 1))', 'keys.prefix(pageSize)', 'try readPayload(itemHash: key, catalog: catalog)',
    'DELETE FROM knowledge_external_payloads', 'UPDATE knowledge_primary_legacy_reclaim', 'try execute(catalog, "COMMIT")']) assert(legacy.includes(token), token);
  assert(legacy.indexOf('try readPayload(') < legacy.indexOf('DELETE FROM knowledge_external_payloads'));
  assert(!legacy.includes('DELETE FROM knowledge_items') && !legacy.includes('removeItem('));
  for (const token of ['self.reclaimPrimaryLegacyCopies(pageSize: 8)', 'self.reclaimExternalPayloadFiles(pageSize: 16)',
    'legacy.deferred ? .seconds(5)', 'files.deferred ? .seconds(5)']) assert(worker.includes(token), token);
  assert.equal(database.split('let primarySnapshotLease = try primaryPayloads.snapshotLease()').length, 3);
  for (const token of ['self.reclaimPrimaryPartitions(pageSize: 8)', 'reclaim.deferred ? .seconds(5) : .milliseconds(100)']) assert(worker.includes(token), token);
  const codec = read(app + names[0]);
  for (const token of ['maximumPlainBytes = 64 * 1_024', 'maximumEncodedBytes = 128 * 1_024', 'COMPRESSION_ZLIB',
    'frame.plainBytes + 1', 'guard count == frame.plainBytes', 'codec: compressed ? "zlib" : "raw"']) assert(codec.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/' + names[2]);
  assert.equal((tests.match(/  func test/g) || []).length, 19);
  for (const token of ['testCatalogPublicationFailureLeavesThePreviousRecordReadable', 'testOldCatalogSnapshotStillReadsTheOriginalImmutableFrames',
    'testMissingAndCorruptedFramesRejectAnOtherwiseValidReference', 'testPersistentNamespaceSurvivesAContainerPathChange',
    'testPrimaryMigrationResumesWithoutChangingSourcesVectorsOrLogicalRecords',
    'testReclaimDefersUntilTheOldCatalogSnapshotCloses', 'testAnotherStoreLeaseDefersReclaimWithoutBreakingReads',
    'testRetirementQueueResumesBeforeAndAfterPhysicalUnlink', 'testReclaimRejectsLiveReferencesTraversalAndSymlinkTargets',
    'testReclaimIsPagedAndNeverDropsALivePartitionOrUnknownFile', 'testLegacyReferenceReleaseIsPagedVerifiedAndSnapshotDeferred',
    'testLegacyReferenceReleaseRollsBackIfAnyPrimaryIsCorrupt', 'testExportPinsLegacyFilesThroughMigrationAndLaterReclamation',
    'testLegacyFileCleanupSkipsDirectoriesAndSymlinksAndHonorsAge']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of names) assert.equal(project.split('\n').filter(line => line.includes(name)).length, 4, name);
  console.log('Pinned Android #3037 storage, primary writer/read/migration/reclamation hooks, verified legacy release, retained logical/vector code and nineteen authored fixtures source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

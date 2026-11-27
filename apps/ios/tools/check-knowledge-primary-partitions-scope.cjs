// Source contracts only. No Swift/Compression/CryptoKit/SQLite or XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
// Exact retained baseline now includes the independently reviewed #3031/#3033-36
// chain. Only declared primary hooks may differ from that pinned source.
const base = 'bf3933c65b5963a5b0c5cbe7d826a8eea8366919';
// Retain the already merged connector increments when comparing the independent knowledge baseline.
const read = file => require('./check-model-failure-evidence-scope.cjs').retained(file,
  require('./check-connector-acceptance-evidence-scope.cjs').retained(file,
    fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n')));
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const names = ['AgentKnowledgePrimaryFrameCodec.swift', 'AgentKnowledgePrimaryPartitions.swift', 'AgentKnowledgePrimaryPartitionsTests.swift',
  'AgentKnowledgeStorageBackground.swift', 'AgentKnowledgeStorageMaintenanceTests.swift',
  'AgentKnowledgePrimaryReaderSlots.swift', 'AgentKnowledgePrimaryReaderSlotsTests.swift',
  'AgentKnowledgePrimarySourceIntegrationTests.swift'];
const properties = '  private let primaryPayloads: AgentKnowledgePrimaryPartitions\n';
function retained(file, source) {
  source = require('./check-model-failure-evidence-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line => !names.some(name => line.includes(name))).join('\n')
    .split(' com.galaxyssi.chat.ios.knowledge-storage').join('');
  if (file.endsWith('GalaxySSIViews.swift')) return source
    .replace('    AgentKnowledgeStorageBackground.register()\n', '')
    .replace('    AgentKnowledgeStorageBackground.bind(database: store.agentKnowledgeDatabase)\n', '');
  if (file.endsWith('GalaxySSIServices.swift')) return source.replace('    store.agentKnowledgeDatabase.startPrimaryPayloadMigration()\n', '');
  if (file.endsWith('AgentKnowledgeCommittedReadView.swift')) return source
    .replace('  private var primarySnapshotLease: AgentKnowledgePrimaryPartitions.SnapshotLease?\n', '')
    .replace('  init(fileURL: URL, primarySnapshotLease: AgentKnowledgePrimaryPartitions.SnapshotLease? = nil,\n    checkActive: @escaping () throws -> Void) throws {\n    self.primarySnapshotLease = primarySnapshotLease',
      '  init(fileURL: URL, checkActive: @escaping () throws -> Void) throws {')
    .replace('      // No active callback remains; do not release retention on a zombie handle.\n      while let statement = sqlite3_next_stmt(database, nil) { sqlite3_finalize(statement) }\n', '')
    .replace('\n    // Release physical retention only after statements, WAL and handle are closed.\n    primarySnapshotLease = nil', '');
  if (file.endsWith('AgentKnowledgeDatabase.swift') && source.includes('  struct PrimaryMigrationPage:')) {
    const original = old(file);
    source = source.replace(properties, '')
      .split('    let primarySnapshotLease = try primaryPayloads.snapshotLease()\n    defer { withExtendedLifetime(primarySnapshotLease) {} }\n').join('')
      .replace('    let primarySnapshotLease = try primaryPayloads.snapshotLease()\n', '')
      .replace('AgentKnowledgeCommittedReadView(fileURL: fileURL, primarySnapshotLease: primarySnapshotLease)',
        'AgentKnowledgeCommittedReadView(fileURL: fileURL)')
      .replace('          guard let database, execute("BEGIN IMMEDIATE")', '          guard execute("BEGIN IMMEDIATE")')
      .replace('          try primaryPayloads.beginWriteBatch(catalog: database)\n          defer { primaryPayloads.endWriteBatch(catalog: database) }\n', '')
      .replace('          try primaryPayloads.prepareBatchCommit(catalog: database, checkActive: { try prepared.checkActive() })\n', '')
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
    const replaceStart = '  @discardableResult\n  func replaceAll(', replaceEnd = '  private func insert(_ item:';
    const replacement = section(source, replaceStart, replaceEnd);
    const restoredReplacement = replacement
      .replace('guard validateIdentities(items), let database, execute("BEGIN IMMEDIATE TRANSACTION")', 'guard validateIdentities(items), execute("BEGIN IMMEDIATE TRANSACTION")')
      .replace('      do { try primaryPayloads.beginWriteBatch(catalog: database) }\n      catch { _ = execute("ROLLBACK"); return false }\n      defer { primaryPayloads.endWriteBatch(catalog: database) }\n', '')
      .replace('            execute("UPDATE knowledge_browse_revision SET revision = revision + 1 WHERE id = 1") else {\n        _ = execute("ROLLBACK")\n        return false\n      }\n      do { try primaryPayloads.prepareBatchCommit(catalog: database) }\n      catch { _ = execute("ROLLBACK"); return false }\n      guard execute("COMMIT") else {',
        '            execute("UPDATE knowledge_browse_revision SET revision = revision + 1 WHERE id = 1"),\n            execute("COMMIT") else {');
    assert.equal(restoredReplacement, section(original, replaceStart, replaceEnd));
    source = source.replace(replacement, restoredReplacement);
    const reclaimStart = '  @discardableResult\n  func reclaimExternalPayloadFiles(', reclaimEnd = '  @discardableResult\n  func replaceAll(';
    const actualReclaim = section(source, reclaimStart, reclaimEnd);
    const checkedReclaim = actualReclaim
      .replace('    minimumAge: TimeInterval = 3_600,\n    checkActive: () throws -> Void = {}', '    minimumAge: TimeInterval = 3_600')
      .replace('    minimumAge: TimeInterval,\n    checkActive: () throws -> Void', '    minimumAge: TimeInterval')
      .replace('minimumAge: minimumAge, checkActive: checkActive)', 'minimumAge: minimumAge)')
      .split('\n').filter(line => !['try Task.checkCancellation()', 'try checkActive()'].includes(line.trim())).join('\n');
    const helperPrefix = '  private func reclaimExternalPayloadFilesExclusively(\n    pageSize: Int,\n    minimumAge: TimeInterval\n  ) throws -> ExternalPayloadReclamation {\n    do {\n';
    const helperOffset = checkedReclaim.indexOf(helperPrefix);
    assert(helperOffset > 0);
    const wrapper = checkedReclaim.slice(0, helperOffset);
    assert.equal(wrapper, '  @discardableResult\n  func reclaimExternalPayloadFiles(\n    pageSize: Int = 32,\n    minimumAge: TimeInterval = 3_600\n  ) throws -> ExternalPayloadReclamation {\n    try locked {\n      guard let database else { throw AgentKnowledgeDatabaseError.unavailable }\n      return try primaryPayloads.withExclusiveAccess(catalog: database) {\n        try reclaimExternalPayloadFilesExclusively(pageSize: pageSize, minimumAge: minimumAge)\n      } ?? ExternalPayloadReclamation(removedFiles: 0, removedBytes: 0, complete: false, deferred: true)\n    }\n  }\n\n');
    const restoredReclaim = checkedReclaim.slice(helperOffset)
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
  if (file.endsWith('AgentKnowledgeReadAdmissionTests.swift')) {
    source = source.split('      try seedLegacyKnowledgePayloads([item()], url: url, secrets: secrets)\n').join('');
    const block = section(source, '  func testValidationAuthenticatesCiphertextRatherThanTrustingStableSQLIdentity()',
      '  func testViewRejectsCloseDuringReadAndLifecycleInvalidation()');
    return source.replace(block, block.replace('try fixture { database, url, secrets in', 'try fixture { database, url, _ in'));
  }
  if (file.endsWith('check-desktop-probe-owner-scope.cjs')) return source
    .replace("const read = file => require('./check-knowledge-primary-partitions-scope.cjs').retained(file,\n  require('./check-connector-acceptance-evidence-scope.cjs').retained(file,\n    fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-knowledge-primary-partitions-scope.cjs').retained(file,\n    require('./check-connector-acceptance-evidence-scope.cjs').retained(file, source));\n", '')
    .replace("const read = file => require('./check-knowledge-primary-partitions-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-knowledge-primary-partitions-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'AgentKnowledgeDatabase.swift', app + 'GalaxySSIServices.swift', app + 'GalaxySSIViews.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    app + 'AgentKnowledgeCommittedReadView.swift', 'apps/ios/GalaxySSITests/AgentKnowledgeReadAdmissionTests.swift',
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
  const worker = section(database, '  func maintainPrimaryStorageSlice(', '  @discardableResult\n  func maintainExternalPayloads(');
  for (const token of ['maximumPages: Int = 8', '(1...32).contains(maximumPages)', 'for _ in 0..<maximumPages',
    'maintainPrimaryPayloads(pageSize: 8, checkActive: checkActive)', 'reclaimPrimaryLegacyCopies(pageSize: 8, checkActive: checkActive)',
    'reclaimPrimaryPartitions(pageSize: 8, checkActive: checkActive)', 'reclaimExternalPayloadFiles(pageSize: 16, checkActive: checkActive)',
    'if legacy.deferred { return true }', 'if primary.deferred { return true }', 'if files.deferred { return true }']) assert(worker.includes(token), token);
  assert(!database.includes('primaryMigrationQueue') && !database.includes('schedulePrimaryPayloadMigration('));
  const migration = section(database, '  func maintainPrimaryPayloads(', '  func reclaimPrimaryPartitions(');
  for (const token of ['execute("BEGIN IMMEDIATE TRANSACTION")', 'pageSize: Int = 8', 'try primaryPayloads.append(',
    'try primaryPayloads.read(', 'UPDATE knowledge_items SET encrypted_payload=x\'00\'', 'UPDATE knowledge_primary_migration',
    'defer { if !committed { _ = execute("ROLLBACK") } }']) assert(migration.includes(token), token);
  for (const token of ['replaceAll(', 'nativeFiles.invalidate(', 'UPDATE knowledge_source', 'UPDATE knowledge_vector', 'revision = revision +']) assert(!migration.includes(token), token);
  const storage = read(app + names[1]);
  for (const token of ['partitionBytes: Int64 = 64 * 1_024 * 1_024', 'partitionRecords: Int64 = 65_536', 'let bucket = prefix & 3',
    'sqlite3_get_autocommit(catalog) == 0', 'try beforeCatalogPublication()',
    'reference.frames', 'Self.sha256(result) == reference.sha256']) assert(storage.includes(token), token);
  const append = section(storage, '  private func appendFrames(', '  func read(');
  assert(append.indexOf('try execute(database, "COMMIT")') < append.indexOf('if batch == nil { try syncRoot(); try beforeCatalogPublication() }'));
  assert(append.indexOf('if batch == nil { try syncRoot(); try beforeCatalogPublication() }') < append.indexOf('INSERT INTO knowledge_primary_refs'));
  assert(append.includes('if batch == nil {\n        try checkActive()') && append.includes('batch?.pending.insert(id)'));
  const barrier = section(storage, '  func prepareBatchCommit(', '  func endWriteBatch(');
  assert(barrier.indexOf('for bucket in writers.keys.sorted()') < barrier.indexOf('try beforeCatalogPublication()'));
  assert(barrier.indexOf('try beforeCatalogPublication()') < barrier.indexOf('batch.prepared = true'));
  assert(barrier.includes('batch.failed = true'));
  const flush = section(storage, '  private func flushWriter(', '  private func partition(');
  assert(flush.indexOf('try execute(writer.database, "COMMIT")') < flush.indexOf('batch.pending.remove(writer.id)'));
  assert(flush.indexOf('batch.pending.remove(writer.id)') < flush.indexOf('sqlite3_close_v2(writer.database)'));
  const batchEnd = section(storage, '  func endWriteBatch(', '  private func ownedBatch(');
  for (const token of ['batch.catalog == catalog', 'batch.thread === Thread.current', '"ROLLBACK"', 'writeBatch = nil']) assert(batchEnd.includes(token), token);
  const pendingRead = section(storage, '  private func readPayload(', '  // Independent catalog snapshots');
  for (const token of ['batch.catalog == catalog, batch.thread === Thread.current', 'batch.pending.contains(partition)',
    'if pending == nil { sqlite3_close_v2(database) }']) assert(pendingRead.includes(token), token);
  const acquire = pendingRead.indexOf('readerLease = try readerSlots.acquire(checkActive: checkActive)'),
    release = pendingRead.indexOf('defer { readerLease?.end() }'),
    open = pendingRead.indexOf('let database = try pending ?? open(partition, create: false, readOnly: true)'),
    close = pendingRead.indexOf('defer { if pending == nil { sqlite3_close_v2(database) } }');
  assert(acquire >= 0 && acquire < release && release < open && open < close);
  assert(pendingRead.includes('if pending == nil { readerLease = try readerSlots.acquire(checkActive: checkActive) }'));
  assert(storage.includes('readerSlots: AgentKnowledgePrimaryReaderSlots = .shared'));
  const slots = read(app + names[5]);
  for (const token of ['static let shared = AgentKnowledgePrimaryReaderSlots(capacity: 8)', 'DispatchSemaphore(value: capacity)',
    'semaphore.wait(timeout: .now() + .milliseconds(50))', 'try Task.checkCancellation()', 'try checkActive()',
    'release = nil', 'action?()', 'deinit { end() }', 'return Lease { _ = self.semaphore.signal() }',
    '} catch {\n        semaphore.signal()\n        throw error']) assert(slots.includes(token), token);
  assert(slots.indexOf('release = nil') < slots.indexOf('action?()'));
  assert.equal((read('apps/ios/GalaxySSITests/' + names[6]).match(/  func test/g) || []).length, 6);
  const rotation = section(storage, '  private func partition(catalog:', '  private func writer(id:');
  assert(rotation.indexOf('try flushWriter(bucket: bucket, checkActive: checkActive)') >= 0 &&
    rotation.indexOf('try flushWriter(bucket: bucket, checkActive: checkActive)') < rotation.indexOf('try open(id, create: true, readOnly: false)'));
  assert(rotation.includes('try physicalBytes(id) < partitionBytes'));
  const actualReplacement = section(database, '  func replaceAll(', '  private func insert(_ item:');
  for (const owner of [actualReplacement, migration]) {
    for (const token of ['primaryPayloads.beginWriteBatch(catalog: database)', 'defer { primaryPayloads.endWriteBatch(catalog: database) }',
      'primaryPayloads.prepareBatchCommit(catalog: database']) assert(owner.includes(token), token);
    assert(owner.lastIndexOf('primaryPayloads.prepareBatchCommit(') < owner.lastIndexOf('execute("COMMIT")'));
  }
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
    'sqlite3_bind_int(select, 2, Int32(pageSize + 1))', 'keys.prefix(pageSize)', 'try readPayload(itemHash: key, catalog: catalog, checkActive: checkActive)',
    'DELETE FROM knowledge_external_payloads', 'UPDATE knowledge_primary_legacy_reclaim', 'try execute(catalog, "COMMIT")']) assert(legacy.includes(token), token);
  assert(legacy.indexOf('try readPayload(') < legacy.indexOf('DELETE FROM knowledge_external_payloads'));
  assert(!legacy.includes('DELETE FROM knowledge_items') && !legacy.includes('removeItem('));
  assert.equal(database.split('let primarySnapshotLease = try primaryPayloads.snapshotLease()').length, 3);
  const background = read(app + names[3]);
  for (const token of ['BGProcessingTaskRequest(identifier: taskIdentifier)', 'Date().addingTimeInterval(15 * 60)',
    'requiresNetworkConnectivity = false', 'requiresExternalPower = false', 'UserDefaults.standard.set(pending, forKey: pendingKey)',
    'generation != expectedGeneration', 'schedule(pending: pending, expectedGeneration: ticket)',
    'GalaxySSIStore.existingAgentKnowledgeDatabase()', 'Task.detached(priority: .utility)', 'maximumPages: 8',
    'UIApplication.didBecomeActiveNotification', 'UIApplication.protectedDataWillBecomeUnavailableNotification',
    'control.onCancellation { worker.cancel() }', 'control.onCancellation { work.cancel() }',
    'task.expirationHandler = { control.finish(success: false, pending: true) }',
    'control.finish(success: true, pending: true)', 'isLowPowerModeEnabled', 'thermalState']) assert(background.includes(token), token);
  for (const token of ['!foreground && protectedData && !lowPower', '(thermal == .nominal || thermal == .fair)',
    'now >= started, now < deadline', 'seconds: TimeInterval = 10', 'UIApplication.shared.applicationState != .background',
    'UIApplication.willEnterForegroundNotification']) assert(background.includes(token), token);
  assert(storage.includes('while offset < plain.count {\n        try Task.checkCancellation()\n        try checkActive()'));
  assert(storage.includes('while true {\n      try Task.checkCancellation()\n      try checkActive()'));
  assert(migration.includes('catalog: database, checkActive: checkActive)'));
  for (const token of ['AgentKnowledgeSemanticController', 'EmbeddingRuntime', 'startDownload(', 'GalaxySSIStore()']) assert(!background.includes(token), token);
  const views = read(app + 'GalaxySSIViews.swift');
  assert.equal(views.split('    AgentKnowledgeStorageBackground.register()\n').length, 2);
  assert.equal(views.split('    AgentKnowledgeStorageBackground.bind(database: store.agentKnowledgeDatabase)\n').length, 2);
  const maintenanceTests = read('apps/ios/GalaxySSITests/' + names[4]);
  assert.equal((maintenanceTests.match(/  func test/g) || []).length, 6);
  const codec = read(app + names[0]);
  for (const token of ['maximumPlainBytes = 64 * 1_024', 'maximumEncodedBytes = 128 * 1_024', 'COMPRESSION_ZLIB',
    'frame.plainBytes + 1', 'guard count == frame.plainBytes', 'codec: compressed ? "zlib" : "raw"']) assert(codec.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/' + names[2]);
  assert.equal((tests.match(/  func test/g) || []).length, 27);
  for (const token of ['testCatalogPublicationFailureLeavesThePreviousRecordReadable', 'testOldCatalogSnapshotStillReadsTheOriginalImmutableFrames',
    'testMissingAndCorruptedFramesRejectAnOtherwiseValidReference', 'testPersistentNamespaceSurvivesAContainerPathChange',
    'testPrimaryMigrationResumesWithoutChangingSourcesVectorsOrLogicalRecords',
    'testReclaimDefersUntilTheOldCatalogSnapshotCloses', 'testAnotherStoreLeaseDefersReclaimWithoutBreakingReads',
    'testRetirementQueueResumesBeforeAndAfterPhysicalUnlink', 'testReclaimRejectsLiveReferencesTraversalAndSymlinkTargets',
    'testReclaimIsPagedAndNeverDropsALivePartitionOrUnknownFile', 'testLegacyReferenceReleaseIsPagedVerifiedAndSnapshotDeferred',
    'testLegacyReferenceReleaseRollsBackIfAnyPrimaryIsCorrupt', 'testExportPinsLegacyFilesThroughMigrationAndLaterReclamation',
    'testLegacyFileCleanupSkipsDirectoriesAndSymlinksAndHonorsAge', 'testCancellationBetweenFramesDoesNotPublishAReplacement',
    'testBatchStagesOwnerReadbackAndCommitsOncePerBucketBeforePublication',
    'testBatchRotationFlushesEachSealedPredecessorAndKeepsAllReferencesReadable',
    'testCaughtBatchAppendFailurePoisonsPreparationAndRollsBackEarlierStaging',
    'testPartialPhysicalCommitFailureCannotPublishCatalogReferences', 'testCatalogFailureAfterBatchPreparePreservesTheOldSnapshot',
    'testBatchScopeRejectsAutocommitNestedForeignAndPostPrepareWrites',
    'testRotationIncludesPhysicalBytesLeftByUnreferencedFrames']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split(' com.galaxyssi.chat.ios.knowledge-storage').length, 3);
  for (const name of names) assert.equal(project.split('\n').filter(line => line.includes(name)).length, 4, name);
  console.log('Pinned Android #3037 storage, shared eight-reader slots, owned batch barriers, periodic maintenance and twenty-seven primary plus six maintenance plus six reader-slot authored fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();

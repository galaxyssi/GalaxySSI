import CryptoKit
import Darwin
import Foundation
import SQLite3

final class AgentKnowledgePrimaryPartitions {
  final class SnapshotLease {
    fileprivate let descriptor: Int32
    fileprivate init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }
  }

  struct ReclaimPage {
    var removed: Int
    var complete: Bool
    var deferred: Bool
  }

  struct LegacyReclaimPage {
    var visited: Int
    var released: Int
    var complete: Bool
    var deferred: Bool
  }
  struct Reference: Codable {
    var version: Int
    var partition: String
    var entry: String
    var frames: Int
    var plainBytes: Int64
    var sha256: String
  }

  private final class WriteBatch {
    let catalog: OpaquePointer
    let thread = Thread.current
    var pending: Set<String> = []
    var failed = false
    var prepared = false
    var hasWrites = false
    init(catalog: OpaquePointer) { self.catalog = catalog }
  }

  let root: URL
  private var namespace: String?
  private let namespacePurpose: String
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let partitionBytes: Int64
  private let partitionRecords: Int64
  private let readerSlots: AgentKnowledgePrimaryReaderSlots
  private let writerLock = NSLock()
  private let readerLock = NSLock()
  private let leaseLock = NSLock()
  private var directoryDescriptor: Int32 = -1
  private var accessDescriptor: Int32 = -1
  private var sharedLease = false
  private var writers: [Int: (id: String, database: OpaquePointer)] = [:]
  private var writeBatch: WriteBatch?
  private let beforePartitionCommit: (String) throws -> Void
  private let beforeCatalogPublication: () throws -> Void
  private let beforeRetiredUnlink: () throws -> Void
  private let afterRetiredUnlink: () throws -> Void
  private static let maximumSealedFrame = 192 * 1_024
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(catalogURL: URL, secrets: GalaxySSISecretStore, partitionBytes: Int64 = 64 * 1_024 * 1_024,
       partitionRecords: Int64 = 65_536, beforeCatalogPublication: @escaping () throws -> Void = {},
       beforeRetiredUnlink: @escaping () throws -> Void = {}, afterRetiredUnlink: @escaping () throws -> Void = {},
       beforePartitionCommit: @escaping (String) throws -> Void = { _ in },
       readerSlots: AgentKnowledgePrimaryReaderSlots = .shared) {
    root = URL(fileURLWithPath: catalogURL.path + ".primary", isDirectory: true)
    let identity = Self.sha256(Data(catalogURL.lastPathComponent.utf8))
    namespacePurpose = "knowledge-primary.namespace.v1:\(identity)"
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.knowledge.primary.aes256.v1.\(identity)")
    self.partitionBytes = partitionBytes
    self.partitionRecords = partitionRecords
    self.beforeCatalogPublication = beforeCatalogPublication
    self.beforeRetiredUnlink = beforeRetiredUnlink
    self.afterRetiredUnlink = afterRetiredUnlink
    self.beforePartitionCommit = beforePartitionCommit
    self.readerSlots = readerSlots
  }

  deinit {
    writers.values.forEach { sqlite3_close_v2($0.database) }
    if accessDescriptor >= 0 { Darwin.close(accessDescriptor) }
    if directoryDescriptor >= 0 { Darwin.close(directoryDescriptor) }
  }

  func setup(catalog: OpaquePointer) throws {
    guard partitionBytes > 0, partitionRecords > 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let existed = FileManager.default.fileExists(atPath: root.path)
    if existed {
      guard try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o700])
    var directory = root, resources = URLResourceValues()
    resources.isExcludedFromBackup = false
    try directory.setResourceValues(resources)
    try setupLease()
    if !existed {
      let parent = Darwin.open(root.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard parent >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { Darwin.close(parent) }
      guard Darwin.fsync(parent) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    try execute(catalog, "BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute(catalog, "ROLLBACK") } }
    for sql in [
      "CREATE TABLE IF NOT EXISTS knowledge_primary_namespace(id INTEGER PRIMARY KEY CHECK(id=1),sealed BLOB NOT NULL)",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_partitions(partition_id TEXT PRIMARY KEY,bucket INTEGER NOT NULL CHECK(bucket BETWEEN 0 AND 3),bytes INTEGER NOT NULL CHECK(bytes>=0),records INTEGER NOT NULL CHECK(records>=0),sealed INTEGER NOT NULL CHECK(sealed IN (0,1)))",
      "CREATE UNIQUE INDEX IF NOT EXISTS knowledge_primary_active ON knowledge_primary_partitions(bucket) WHERE sealed=0",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_refs(item_hash TEXT PRIMARY KEY,partition_id TEXT NOT NULL,sealed_ref BLOB NOT NULL)",
      "CREATE INDEX IF NOT EXISTS knowledge_primary_references ON knowledge_primary_refs(partition_id)",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_retired(partition_id TEXT PRIMARY KEY)",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_legacy_reclaim(id INTEGER PRIMARY KEY CHECK(id=1),after_item_hash TEXT NOT NULL DEFAULT '')",
      "INSERT OR IGNORE INTO knowledge_primary_legacy_reclaim(id) VALUES(1)",
      "CREATE TRIGGER IF NOT EXISTS knowledge_primary_delete AFTER DELETE ON knowledge_items BEGIN DELETE FROM knowledge_primary_refs WHERE item_hash=OLD.item_hash; END",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_migration(id INTEGER PRIMARY KEY CHECK(id=1),after_item_hash TEXT NOT NULL DEFAULT '',complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0,1)))",
      "INSERT OR IGNORE INTO knowledge_primary_migration(id) VALUES(1)"
    ] { try execute(catalog, sql) }
    let marker = try prepare(catalog, "SELECT sealed FROM knowledge_primary_namespace WHERE id=1")
    defer { sqlite3_finalize(marker) }
    let state = sqlite3_step(marker)
    let resolved: String
    if state == SQLITE_ROW {
      let plain = try cipher.decrypt(blob(marker, column: 0, maximum: 8 * 1_024), expectedPurpose: namespacePurpose)
      guard let value = String(data: plain, encoding: .utf8), Self.token(value) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      resolved = value
    } else if state == SQLITE_DONE {
      resolved = UUID().uuidString.lowercased()
      let insert = try prepare(catalog, "INSERT INTO knowledge_primary_namespace(id,sealed) VALUES(1,?)")
      defer { sqlite3_finalize(insert) }
      try bind(cipher.encrypt(Data(resolved.utf8), purpose: namespacePurpose), index: 1, statement: insert)
      guard sqlite3_step(insert) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    } else { throw AgentKnowledgeDatabaseError.unavailable }
    try execute(catalog, "COMMIT")
    namespace = resolved
    committed = true
  }

  func beginWriteBatch(catalog: OpaquePointer) throws {
    writerLock.lock()
    defer { writerLock.unlock() }
    guard writeBatch == nil, sqlite3_get_autocommit(catalog) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    try ensureSharedLease()
    writeBatch = WriteBatch(catalog: catalog)
  }

  // Flush every physical participant before the caller can commit its catalog transaction.
  func prepareBatchCommit(catalog: OpaquePointer, checkActive: () throws -> Void = {}) throws {
    writerLock.lock()
    defer { writerLock.unlock() }
    guard let batch = try ownedBatch(catalog: catalog), sqlite3_get_autocommit(catalog) == 0 else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    do {
      for bucket in writers.keys.sorted() { try flushWriter(bucket: bucket, checkActive: checkActive) }
      try Task.checkCancellation()
      try checkActive()
      if batch.hasWrites { try syncRoot(); try beforeCatalogPublication() }
      try Task.checkCancellation()
      try checkActive()
      batch.prepared = true
    } catch { batch.failed = true; throw error }
  }

  // Always called by the same synchronous owner, after catalog commit or on any error path.
  func endWriteBatch(catalog: OpaquePointer) {
    writerLock.lock()
    defer { writerLock.unlock() }
    guard let batch = writeBatch, batch.catalog == catalog, batch.thread === Thread.current else { return }
    for writer in writers.values {
      if batch.pending.contains(writer.id) { try? execute(writer.database, "ROLLBACK") }
      sqlite3_close_v2(writer.database)
    }
    writers.removeAll()
    writeBatch = nil
  }

  private func ownedBatch(catalog: OpaquePointer) throws -> WriteBatch? {
    guard let batch = writeBatch else { return nil }
    guard batch.catalog == catalog, batch.thread === Thread.current, !batch.failed, !batch.prepared else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return batch
  }

  // References can be staged in the catalog, but none may be published before prepareBatchCommit.
  func append(_ plain: Data, itemHash: String, catalog: OpaquePointer, checkActive: () throws -> Void = {}) throws {
    writerLock.lock()
    defer { writerLock.unlock() }
    let batch = try ownedBatch(catalog: catalog)
    do { try appendFrames(plain, itemHash: itemHash, catalog: catalog, batch: batch, checkActive: checkActive) }
    catch { batch?.failed = true; throw error }
  }

  private func appendFrames(_ plain: Data, itemHash: String, catalog: OpaquePointer, batch: WriteBatch?,
                            checkActive: () throws -> Void) throws {
    try checkActive()
    try ensureSharedLease()
    guard Self.digest(itemHash), !plain.isEmpty, sqlite3_get_autocommit(catalog) == 0,
          let prefix = Int(itemHash.prefix(2), radix: 16) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let bucket = prefix & 3
    let id = try partition(catalog: catalog, bucket: bucket, checkActive: checkActive)
    let database = try writer(id: id, bucket: bucket)
    let entry = UUID().uuidString.lowercased()
    var frameCount = 0, offset = 0
    var storedBytes: Int64 = 0
    do {
      if batch?.pending.contains(id) != true {
        try execute(database, "BEGIN IMMEDIATE TRANSACTION")
        batch?.pending.insert(id)
      }
      var committed = false
      defer { if batch == nil && !committed { try? execute(database, "ROLLBACK") } }
      let statement = try prepare(database, "INSERT INTO frames(entry_id,ordinal,sealed) VALUES(?,?,?)")
      defer { sqlite3_finalize(statement) }
      while offset < plain.count {
        try Task.checkCancellation()
        try checkActive()
        let end = offset + min(AgentKnowledgePrimaryFrameCodec.maximumPlainBytes, plain.count - offset)
        let encoded = try AgentKnowledgePrimaryFrameCodec.encode(plain.subdata(in: offset..<end))
        let sealed = try cipher.encrypt(encoded, purpose: framePurpose(itemHash, partition: id, entry: entry, ordinal: frameCount))
        guard sealed.count <= Self.maximumSealedFrame,
              storedBytes <= Int64.max - Int64(sealed.count) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(entry, index: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, Int64(frameCount))
        try bind(sealed, index: 3, statement: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
        storedBytes += Int64(sealed.count)
        offset = end
        frameCount += 1
      }
      if batch == nil {
        try checkActive()
        try Task.checkCancellation()
        try beforePartitionCommit(id)
        try execute(database, "COMMIT")
        committed = true
      }
    } catch {
      if batch == nil { writers.removeValue(forKey: bucket); sqlite3_close_v2(database) }
      throw error
    }
    batch?.hasWrites = true
    if batch == nil { try syncRoot(); try beforeCatalogPublication() }
    try Task.checkCancellation()
    try checkActive()
    let reference = Reference(version: 1, partition: id, entry: entry, frames: frameCount,
      plainBytes: Int64(plain.count), sha256: Self.sha256(plain))
    let sealedReference = try cipher.encrypt(JSONEncoder().encode(reference), purpose: referencePurpose(itemHash))
    guard sealedReference.count <= 8 * 1_024 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let insert = try prepare(catalog, "INSERT INTO knowledge_primary_refs(item_hash,partition_id,sealed_ref) VALUES(?,?,?)")
    defer { sqlite3_finalize(insert) }
    try bind(itemHash, index: 1, statement: insert)
    try bind(id, index: 2, statement: insert)
    try bind(sealedReference, index: 3, statement: insert)
    guard sqlite3_step(insert) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    let update = try prepare(catalog, "UPDATE knowledge_primary_partitions SET bytes=bytes+?,records=records+1 WHERE partition_id=? AND bytes<=? AND records<?")
    defer { sqlite3_finalize(update) }
    sqlite3_bind_int64(update, 1, storedBytes)
    try bind(id, index: 2, statement: update)
    sqlite3_bind_int64(update, 3, Int64.max - storedBytes)
    sqlite3_bind_int64(update, 4, Int64.max)
    guard sqlite3_step(update) == SQLITE_DONE, sqlite3_changes(catalog) == 1 else { throw AgentKnowledgeDatabaseError.corruptRecord }
  }

  func read(itemHash: String, catalog: OpaquePointer, checkActive: () throws -> Void = {}) throws -> Data? {
    writerLock.lock()
    defer { writerLock.unlock() }
    readerLock.lock()
    defer { readerLock.unlock() }
    try ensureSharedLease()
    return try readPayload(itemHash: itemHash, catalog: catalog, checkActive: checkActive)
  }

  private func readPayload(itemHash: String, catalog: OpaquePointer, checkActive: () throws -> Void = {}) throws -> Data? {
    try checkActive()
    if let batch = writeBatch, batch.catalog == catalog {
      guard batch.thread === Thread.current, !batch.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }
    guard Self.digest(itemHash) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let lookup = try prepare(catalog, "SELECT partition_id,sealed_ref FROM knowledge_primary_refs WHERE item_hash=?")
    defer { sqlite3_finalize(lookup) }
    try bind(itemHash, index: 1, statement: lookup)
    let status = sqlite3_step(lookup)
    if status == SQLITE_DONE { return nil }
    guard status == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
    let partition = try text(lookup, column: 0)
    let encrypted = try blob(lookup, column: 1, maximum: 8 * 1_024)
    let reference = try JSONDecoder().decode(Reference.self,
      from: cipher.decrypt(encrypted, expectedPurpose: referencePurpose(itemHash)))
    guard reference.version == 1, Self.token(partition), partition == reference.partition, Self.token(reference.entry),
          reference.frames > 0, reference.plainBytes > 0, reference.plainBytes <= Int64(Int.max),
          Int64(reference.frames) == 1 + (reference.plainBytes - 1) / Int64(AgentKnowledgePrimaryFrameCodec.maximumPlainBytes),
          Self.digest(reference.sha256) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let pending: OpaquePointer?
    if let batch = writeBatch, batch.catalog == catalog, batch.thread === Thread.current {
      guard !batch.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
      pending = batch.pending.contains(partition) ? writers.values.first(where: { $0.id == partition })?.database : nil
      if batch.pending.contains(partition), pending == nil { throw AgentKnowledgeDatabaseError.corruptRecord }
    } else { pending = nil }
    let readerLease: AgentKnowledgePrimaryReaderSlots.Lease?
    if pending == nil { readerLease = try readerSlots.acquire(checkActive: checkActive) }
    else { readerLease = nil }
    defer { readerLease?.end() }
    let database = try pending ?? open(partition, create: false, readOnly: true)
    defer { if pending == nil { sqlite3_close_v2(database) } }
    let frames = try prepare(database, "SELECT ordinal,sealed FROM frames WHERE entry_id=? ORDER BY ordinal")
    defer { sqlite3_finalize(frames) }
    try bind(reference.entry, index: 1, statement: frames)
    var result = Data(), ordinal = 0
    while true {
      try Task.checkCancellation()
      try checkActive()
      let step = sqlite3_step(frames)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW, ordinal < reference.frames, sqlite3_column_int64(frames, 0) == Int64(ordinal) else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let sealed = try blob(frames, column: 1, maximum: Self.maximumSealedFrame)
      let encoded = try cipher.decrypt(sealed,
        expectedPurpose: framePurpose(itemHash, partition: partition, entry: reference.entry, ordinal: ordinal))
      let plain = try AgentKnowledgePrimaryFrameCodec.decode(encoded)
      let expected = min(Int64(AgentKnowledgePrimaryFrameCodec.maximumPlainBytes), reference.plainBytes - Int64(result.count))
      guard Int64(plain.count) == expected else { throw AgentKnowledgeDatabaseError.corruptRecord }
      result.append(plain)
      ordinal += 1
    }
    guard ordinal == reference.frames, Int64(result.count) == reference.plainBytes,
          Self.sha256(result) == reference.sha256 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return result
  }

  // Independent catalog snapshots pin files until their SQLite transaction has closed.
  func snapshotLease() throws -> SnapshotLease {
    leaseLock.lock()
    defer { leaseLock.unlock() }
    guard directoryDescriptor >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
    let descriptor = try openLeaseDescriptor()
    do {
      guard try Self.flock(descriptor, LOCK_SH) else { throw AgentKnowledgeDatabaseError.unavailable }
      return SnapshotLease(descriptor)
    } catch { Darwin.close(descriptor); throw error }
  }

  // Caller serializes catalog access, outside any transaction. Never waits for another snapshot.
  func reclaim(catalog: OpaquePointer, pageSize: Int = 8, checkActive: () throws -> Void = {}) throws -> ReclaimPage {
    try checkActive()
    guard (1...32).contains(pageSize), sqlite3_get_autocommit(catalog) != 0 else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    if try reclaimPending(catalog) == false { return ReclaimPage(removed: 0, complete: true, deferred: false) }
    return try withExclusiveAccess(catalog: catalog) {
      try reclaimExclusively(catalog: catalog, pageSize: pageSize, checkActive: checkActive)
    } ?? ReclaimPage(removed: 0, complete: false, deferred: true)
  }

  func checkSharedAccess() throws { try ensureSharedLease() }

  // Legacy file maintenance shares the same exclusion boundary as physical partition retirement.
  func withExclusiveAccess<T>(catalog: OpaquePointer, _ operation: () throws -> T) throws -> T? {
    guard sqlite3_get_autocommit(catalog) != 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    writerLock.lock()
    defer { writerLock.unlock() }
    guard writeBatch == nil else { throw AgentKnowledgeDatabaseError.corruptRecord }
    readerLock.lock()
    defer { readerLock.unlock() }
    leaseLock.lock()
    defer { leaseLock.unlock() }
    guard accessDescriptor >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
    writers.values.forEach { sqlite3_close_v2($0.database) }
    writers.removeAll()
    // flock conversion may release SH even when nonblocking EX fails; all I/O rechecks SH.
    sharedLease = false
    defer { sharedLease = (try? Self.flock(accessDescriptor, LOCK_SH)) == true }
    guard try Self.flock(accessDescriptor, LOCK_EX) else {
      return nil
    }
    return try operation()
  }

  func reclaimLegacyCopies(catalog: OpaquePointer, pageSize: Int = 8, checkActive: () throws -> Void = {}) throws -> LegacyReclaimPage {
    try checkActive()
    guard (1...32).contains(pageSize) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return try withExclusiveAccess(catalog: catalog) {
      try execute(catalog, "BEGIN IMMEDIATE TRANSACTION")
      var committed = false
      defer { if !committed { try? execute(catalog, "ROLLBACK") } }
      let state = try prepare(catalog, "SELECT after_item_hash FROM knowledge_primary_legacy_reclaim WHERE id=1")
      defer { sqlite3_finalize(state) }
      guard sqlite3_step(state) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let cursor = try text(state, column: 0)
      guard cursor.isEmpty || Self.digest(cursor) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let select = try prepare(catalog, """
        SELECT item_hash FROM knowledge_external_payloads WHERE item_hash>? ORDER BY item_hash LIMIT ?
        """)
      defer { sqlite3_finalize(select) }
      try bind(cursor, index: 1, statement: select)
      sqlite3_bind_int(select, 2, Int32(pageSize + 1))
      var keys: [String] = []
      while true {
        let state = sqlite3_step(select)
        if state == SQLITE_DONE { break }
        guard state == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
        keys.append(try text(select, column: 0))
      }
      var released = 0
      for key in keys.prefix(pageSize) {
        try Task.checkCancellation()
        try checkActive()
        // Do not discard the last usable copy on a malformed reference, missing file or bad frame.
        if try readPayload(itemHash: key, catalog: catalog, checkActive: checkActive) == nil { continue }
        let remove = try prepare(catalog, "DELETE FROM knowledge_external_payloads WHERE item_hash=?")
        defer { sqlite3_finalize(remove) }
        try bind(key, index: 1, statement: remove)
        guard sqlite3_step(remove) == SQLITE_DONE, sqlite3_changes(catalog) == 1 else {
          throw AgentKnowledgeDatabaseError.unavailable
        }
        released += 1
      }
      let visited = min(keys.count, pageSize), finished = keys.count <= pageSize
      let advance = try prepare(catalog, "UPDATE knowledge_primary_legacy_reclaim SET after_item_hash=? WHERE id=1")
      defer { sqlite3_finalize(advance) }
      try bind(finished ? "" : (keys.prefix(pageSize).last ?? cursor), index: 1, statement: advance)
      guard sqlite3_step(advance) == SQLITE_DONE, sqlite3_changes(catalog) == 1 else { throw AgentKnowledgeDatabaseError.unavailable }
      try checkActive()
      try Task.checkCancellation()
      try execute(catalog, "COMMIT")
      committed = true
      return LegacyReclaimPage(visited: visited, released: released, complete: finished, deferred: false)
    } ?? LegacyReclaimPage(visited: 0, released: 0, complete: false, deferred: true)
  }

  private func reclaimExclusively(catalog: OpaquePointer, pageSize: Int, checkActive: () throws -> Void) throws -> ReclaimPage {
    try checkActive()
    try execute(catalog, "BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute(catalog, "ROLLBACK") } }
    let retire = try prepare(catalog, """
      INSERT OR IGNORE INTO knowledge_primary_retired(partition_id)
      SELECT p.partition_id FROM knowledge_primary_partitions p
      WHERE NOT EXISTS(SELECT 1 FROM knowledge_primary_refs r WHERE r.partition_id=p.partition_id)
      ORDER BY p.partition_id LIMIT MAX(0, ? - (SELECT COUNT(*) FROM knowledge_primary_retired))
      """)
    defer { sqlite3_finalize(retire) }
    sqlite3_bind_int(retire, 1, Int32(pageSize))
    guard sqlite3_step(retire) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    try execute(catalog, """
      DELETE FROM knowledge_primary_partitions WHERE partition_id IN(SELECT partition_id FROM knowledge_primary_retired)
      AND NOT EXISTS(SELECT 1 FROM knowledge_primary_refs r WHERE r.partition_id=knowledge_primary_partitions.partition_id)
      """)
    try checkActive()
    try Task.checkCancellation()
    try execute(catalog, "COMMIT")
    committed = true
    let queued = try prepare(catalog, "SELECT partition_id FROM knowledge_primary_retired ORDER BY partition_id LIMIT ?")
    defer { sqlite3_finalize(queued) }
    sqlite3_bind_int(queued, 1, Int32(pageSize))
    var ids: [String] = []
    while true {
      let status = sqlite3_step(queued)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
      let id = try text(queued, column: 0)
      guard Self.token(id) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      ids.append(id)
    }
    for id in ids {
      try Task.checkCancellation()
      try checkActive()
      let live = try prepare(catalog, "SELECT 1 FROM knowledge_primary_refs WHERE partition_id=? LIMIT 1")
      defer { sqlite3_finalize(live) }
      try bind(id, index: 1, statement: live)
      let state = sqlite3_step(live)
      guard state == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.corruptRecord }
      try beforeRetiredUnlink()
      try checkActive()
      try unlinkRetired(id)
      try afterRetiredUnlink()
      let remove = try prepare(catalog, "DELETE FROM knowledge_primary_retired WHERE partition_id=?")
      defer { sqlite3_finalize(remove) }
      try bind(id, index: 1, statement: remove)
      guard sqlite3_step(remove) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    return ReclaimPage(removed: ids.count, complete: try !reclaimPending(catalog), deferred: false)
  }

  private func reclaimPending(_ catalog: OpaquePointer) throws -> Bool {
    let statement = try prepare(catalog, """
      SELECT 1 FROM knowledge_primary_retired UNION ALL
      SELECT 1 FROM knowledge_primary_partitions p WHERE NOT EXISTS(
        SELECT 1 FROM knowledge_primary_refs r WHERE r.partition_id=p.partition_id) LIMIT 1
      """)
    defer { sqlite3_finalize(statement) }
    let state = sqlite3_step(statement)
    guard state == SQLITE_ROW || state == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    return state == SQLITE_ROW
  }

  private func unlinkRetired(_ id: String) throws {
    guard Self.token(id), directoryDescriptor >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    for suffix in ["-wal", "-shm", ""] {
      let name = id + ".sqlite" + suffix
      var info = stat()
      if Darwin.fstatat(directoryDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
        if errno == ENOENT { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if Darwin.unlinkat(directoryDescriptor, name, 0) != 0, errno != ENOENT {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    }
    try syncRoot()
  }

  private func syncRoot() throws {
    guard directoryDescriptor >= 0, Darwin.fsync(directoryDescriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private func setupLease() throws {
    leaseLock.lock()
    defer { leaseLock.unlock() }
    if directoryDescriptor < 0 {
      directoryDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard directoryDescriptor >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    if accessDescriptor < 0 { accessDescriptor = try openLeaseDescriptor() }
    sharedLease = try Self.flock(accessDescriptor, LOCK_SH)
    guard sharedLease else { throw AgentKnowledgeDatabaseError.unavailable }
  }

  private func openLeaseDescriptor() throws -> Int32 {
    let descriptor = Darwin.openat(directoryDescriptor, ".access.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    guard descriptor >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
    var info = stat()
    guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1 else {
      Darwin.close(descriptor)
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return descriptor
  }

  private func ensureSharedLease() throws {
    leaseLock.lock()
    defer { leaseLock.unlock() }
    guard accessDescriptor >= 0 else { throw AgentKnowledgeDatabaseError.unavailable }
    if !sharedLease { sharedLease = try Self.flock(accessDescriptor, LOCK_SH) }
    guard sharedLease else { throw AgentKnowledgeDatabaseError.unavailable }
  }

  private static func flock(_ descriptor: Int32, _ mode: Int32) throws -> Bool {
    while Darwin.flock(descriptor, mode | LOCK_NB) != 0 {
      let code = errno
      if code == EINTR { continue }
      if code == EWOULDBLOCK || code == EAGAIN { return false }
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    return true
  }

  private func flushWriter(bucket: Int, checkActive: () throws -> Void) throws {
    guard let writer = writers[bucket] else { return }
    if let batch = writeBatch, batch.pending.contains(writer.id) {
      guard batch.thread === Thread.current, !batch.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
      try Task.checkCancellation()
      try checkActive()
      try beforePartitionCommit(writer.id)
      try execute(writer.database, "COMMIT")
      batch.pending.remove(writer.id)
    }
    writers.removeValue(forKey: bucket)
    sqlite3_close_v2(writer.database)
  }

  private func partition(catalog: OpaquePointer, bucket: Int, checkActive: () throws -> Void) throws -> String {
    let lookup = try prepare(catalog, "SELECT partition_id,bytes,records FROM knowledge_primary_partitions WHERE bucket=? AND sealed=0")
    defer { sqlite3_finalize(lookup) }
    sqlite3_bind_int(lookup, 1, Int32(bucket))
    let status = sqlite3_step(lookup)
    if status == SQLITE_ROW {
      let id = try text(lookup, column: 0)
      let bytes = sqlite3_column_int64(lookup, 1), records = sqlite3_column_int64(lookup, 2)
      guard Self.token(id), bytes >= 0, records >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if bytes < partitionBytes, records < partitionRecords, try physicalBytes(id) < partitionBytes { return id }
      try flushWriter(bucket: bucket, checkActive: checkActive)
      let seal = try prepare(catalog, "UPDATE knowledge_primary_partitions SET sealed=1 WHERE partition_id=?")
      defer { sqlite3_finalize(seal) }
      try bind(id, index: 1, statement: seal)
      guard sqlite3_step(seal) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    } else if status != SQLITE_DONE { throw AgentKnowledgeDatabaseError.unavailable }
    try flushWriter(bucket: bucket, checkActive: checkActive)
    let id = UUID().uuidString.lowercased()
    let database = try open(id, create: true, readOnly: false)
    sqlite3_close_v2(database)
    let insert = try prepare(catalog, "INSERT INTO knowledge_primary_partitions(partition_id,bucket,bytes,records,sealed) VALUES(?,?,0,0,0)")
    defer { sqlite3_finalize(insert) }
    try bind(id, index: 1, statement: insert)
    sqlite3_bind_int(insert, 2, Int32(bucket))
    guard sqlite3_step(insert) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    return id
  }

  private func writer(id: String, bucket: Int) throws -> OpaquePointer {
    if let current = writers[bucket], current.id == id { return current.database }
    if let prior = writers[bucket] {
      guard writeBatch?.pending.contains(prior.id) != true else { throw AgentKnowledgeDatabaseError.corruptRecord }
      writers.removeValue(forKey: bucket)
      sqlite3_close_v2(prior.database)
    }
    let database = try open(id, create: false, readOnly: false)
    writers[bucket] = (id, database)
    return database
  }

  private func physicalBytes(_ id: String) throws -> Int64 {
    guard Self.token(id) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    var total: Int64 = 0
    for suffix in ["", "-wal"] {
      let path = root.appendingPathComponent(id + ".sqlite" + suffix).path
      if suffix == "-wal", !FileManager.default.fileExists(atPath: path) { continue }
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber, size.int64Value >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let (sum, overflow) = total.addingReportingOverflow(size.int64Value)
      guard !overflow else { throw AgentKnowledgeDatabaseError.corruptRecord }
      total = sum
    }
    return total
  }

  private func open(_ id: String, create: Bool, readOnly: Bool) throws -> OpaquePointer {
    guard Self.token(id) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let url = root.appendingPathComponent(id + ".sqlite")
    let exists = FileManager.default.fileExists(atPath: url.path)
    guard create ? !exists : exists else { throw AgentKnowledgeDatabaseError.corruptRecord }
    for suffix in ["", "-wal", "-shm"] {
      let path = url.path + suffix
      if FileManager.default.fileExists(atPath: path) {
        guard try FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType == .typeRegular else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
      }
    }
    var handle: OpaquePointer?
    let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let database = handle else {
      if let handle { sqlite3_close_v2(handle) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    var ready = false
    defer { if !ready { sqlite3_close_v2(database) } }
    sqlite3_busy_timeout(database, 5_000)
    try execute(database, "PRAGMA cache_size=-1024")
    try execute(database, "PRAGMA mmap_size=0")
    if readOnly {
      try execute(database, "PRAGMA query_only=ON")
    } else {
      try execute(database, "PRAGMA journal_mode=WAL")
      try execute(database, "PRAGMA synchronous=FULL")
      try execute(database, "PRAGMA fullfsync=ON")
      if create {
        try execute(database, "CREATE TABLE frames(entry_id TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),sealed BLOB NOT NULL,PRIMARY KEY(entry_id,ordinal)) WITHOUT ROWID")
      }
      for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
          .posixPermissions: 0o600], ofItemAtPath: url.path + suffix)
      }
    }
    ready = true
    return database
  }

  private func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let result = statement else {
      if let statement { sqlite3_finalize(statement) }
      throw AgentKnowledgeDatabaseError.unavailable
    }
    return result
  }
  private func execute(_ database: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func bind(_ value: String, index: Int32, statement: OpaquePointer) throws {
    guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, Self.transient) }) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
  }
  private func bind(_ value: Data, index: Int32, statement: OpaquePointer) throws {
    guard let count = Int32(exactly: value.count), value.withUnsafeBytes({ sqlite3_bind_blob(statement, index,
      $0.baseAddress, count, Self.transient) }) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func text(_ statement: OpaquePointer, column: Int32) throws -> String {
    guard let value = sqlite3_column_text(statement, column) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return String(cString: value)
  }
  private func blob(_ statement: OpaquePointer, column: Int32, maximum: Int) throws -> Data {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard (1...maximum).contains(count), let bytes = sqlite3_column_blob(statement, column) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return Data(bytes: bytes, count: count)
  }
  private func referencePurpose(_ key: String) throws -> String {
    guard let namespace else { throw AgentKnowledgeDatabaseError.unavailable }
    return "knowledge-primary.v1:\(namespace):reference:\(key)"
  }
  private func framePurpose(_ key: String, partition: String, entry: String, ordinal: Int) throws -> String {
    guard let namespace else { throw AgentKnowledgeDatabaseError.unavailable }
    return "knowledge-primary.v1:\(namespace):frame:\(key):\(partition):\(entry):\(ordinal)"
  }
  private static func token(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
  private static func digest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  private static func sha256(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
}

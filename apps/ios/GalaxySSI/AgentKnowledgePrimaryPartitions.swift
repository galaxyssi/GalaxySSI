import CryptoKit
import Foundation
import SQLite3

final class AgentKnowledgePrimaryPartitions {
  struct Reference: Codable {
    var version: Int
    var partition: String
    var entry: String
    var frames: Int
    var plainBytes: Int64
    var sha256: String
  }

  let root: URL
  private var namespace: String?
  private let namespacePurpose: String
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let partitionBytes: Int64
  private let partitionRecords: Int64
  private let writerLock = NSLock()
  private let readerLock = NSLock()
  private var writers: [Int: (id: String, database: OpaquePointer)] = [:]
  private let beforeCatalogPublication: () throws -> Void
  private static let maximumSealedFrame = 192 * 1_024
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(catalogURL: URL, secrets: GalaxySSISecretStore, partitionBytes: Int64 = 64 * 1_024 * 1_024,
       partitionRecords: Int64 = 65_536, beforeCatalogPublication: @escaping () throws -> Void = {}) {
    root = URL(fileURLWithPath: catalogURL.path + ".primary", isDirectory: true)
    let identity = Self.sha256(Data(catalogURL.lastPathComponent.utf8))
    namespacePurpose = "knowledge-primary.namespace.v1:\(identity)"
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.knowledge.primary.aes256.v1.\(identity)")
    self.partitionBytes = partitionBytes
    self.partitionRecords = partitionRecords
    self.beforeCatalogPublication = beforeCatalogPublication
  }

  deinit { writers.values.forEach { sqlite3_close_v2($0.database) } }

  func setup(catalog: OpaquePointer) throws {
    guard partitionBytes > 0, partitionRecords > 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if FileManager.default.fileExists(atPath: root.path) {
      guard try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .posixPermissions: 0o700])
    var directory = root, resources = URLResourceValues()
    resources.isExcludedFromBackup = false
    try directory.setResourceValues(resources)
    try execute(catalog, "BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute(catalog, "ROLLBACK") } }
    for sql in [
      "CREATE TABLE IF NOT EXISTS knowledge_primary_namespace(id INTEGER PRIMARY KEY CHECK(id=1),sealed BLOB NOT NULL)",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_partitions(partition_id TEXT PRIMARY KEY,bucket INTEGER NOT NULL CHECK(bucket BETWEEN 0 AND 3),bytes INTEGER NOT NULL CHECK(bytes>=0),records INTEGER NOT NULL CHECK(records>=0),sealed INTEGER NOT NULL CHECK(sealed IN (0,1)))",
      "CREATE UNIQUE INDEX IF NOT EXISTS knowledge_primary_active ON knowledge_primary_partitions(bucket) WHERE sealed=0",
      "CREATE TABLE IF NOT EXISTS knowledge_primary_refs(item_hash TEXT PRIMARY KEY,partition_id TEXT NOT NULL,sealed_ref BLOB NOT NULL)",
      "CREATE INDEX IF NOT EXISTS knowledge_primary_references ON knowledge_primary_refs(partition_id)",
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

  // Caller owns a catalog write transaction. Immutable frames commit before any reference is published.
  func append(_ plain: Data, itemHash: String, catalog: OpaquePointer) throws {
    writerLock.lock()
    defer { writerLock.unlock() }
    guard Self.digest(itemHash), !plain.isEmpty, sqlite3_get_autocommit(catalog) == 0,
          let prefix = Int(itemHash.prefix(2), radix: 16) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let bucket = prefix & 3
    let id = try partition(catalog: catalog, bucket: bucket)
    let database = try writer(id: id, bucket: bucket)
    let entry = UUID().uuidString.lowercased()
    var frameCount = 0, offset = 0
    var storedBytes: Int64 = 0
    do {
      try execute(database, "BEGIN IMMEDIATE TRANSACTION")
      var committed = false
      defer { if !committed { try? execute(database, "ROLLBACK") } }
      let statement = try prepare(database, "INSERT INTO frames(entry_id,ordinal,sealed) VALUES(?,?,?)")
      defer { sqlite3_finalize(statement) }
      while offset < plain.count {
        try Task.checkCancellation()
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
      try execute(database, "COMMIT")
      committed = true
    } catch {
      writers.removeValue(forKey: bucket)
      sqlite3_close_v2(database)
      throw error
    }
    try beforeCatalogPublication()
    try Task.checkCancellation()
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

  func read(itemHash: String, catalog: OpaquePointer) throws -> Data? {
    readerLock.lock()
    defer { readerLock.unlock() }
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
    let database = try open(partition, create: false, readOnly: true)
    defer { sqlite3_close_v2(database) }
    let frames = try prepare(database, "SELECT ordinal,sealed FROM frames WHERE entry_id=? ORDER BY ordinal")
    defer { sqlite3_finalize(frames) }
    try bind(reference.entry, index: 1, statement: frames)
    var result = Data(), ordinal = 0
    while true {
      try Task.checkCancellation()
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

  private func partition(catalog: OpaquePointer, bucket: Int) throws -> String {
    let lookup = try prepare(catalog, "SELECT partition_id,bytes,records FROM knowledge_primary_partitions WHERE bucket=? AND sealed=0")
    defer { sqlite3_finalize(lookup) }
    sqlite3_bind_int(lookup, 1, Int32(bucket))
    let status = sqlite3_step(lookup)
    if status == SQLITE_ROW {
      let id = try text(lookup, column: 0)
      let bytes = sqlite3_column_int64(lookup, 1), records = sqlite3_column_int64(lookup, 2)
      guard Self.token(id), bytes >= 0, records >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if bytes < partitionBytes, records < partitionRecords { return id }
      let seal = try prepare(catalog, "UPDATE knowledge_primary_partitions SET sealed=1 WHERE partition_id=?")
      defer { sqlite3_finalize(seal) }
      try bind(id, index: 1, statement: seal)
      guard sqlite3_step(seal) == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    } else if status != SQLITE_DONE { throw AgentKnowledgeDatabaseError.unavailable }
    if let prior = writers.removeValue(forKey: bucket) { sqlite3_close_v2(prior.database) }
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
    if let prior = writers.removeValue(forKey: bucket) { sqlite3_close_v2(prior.database) }
    let database = try open(id, create: false, readOnly: false)
    writers[bucket] = (id, database)
    return database
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

import CryptoKit
import Foundation
import SQLite3

// SQLite owns bounded-page external ordering. Only authenticated ciphertext keys
// reach its B-tree; collation decrypts at most two small metadata keys at a time.
final class AgentKnowledgeProjectionOrder {
  fileprivate final class Cipher {
    private var key: SymmetricKey? = SymmetricKey(size: .bits256)
    private var fixture: GalaxySSIAttachmentAtRestCipher?
    init(fixture: GalaxySSIAttachmentAtRestCipher?) { self.fixture = fixture }
    func encrypt(_ bytes: Data, purpose: String) throws -> Data {
      if let fixture { return try fixture.encrypt(bytes, purpose: purpose) }
      guard let key, let sealed = try AES.GCM.seal(bytes, using: key, authenticating: Data(purpose.utf8)).combined else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      return sealed
    }
    func decrypt(_ bytes: Data, expectedPurpose: String) throws -> Data {
      if let fixture { return try fixture.decrypt(bytes, expectedPurpose: expectedPurpose) }
      guard let key else { throw AgentKnowledgeDatabaseError.unavailable }
      return try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key, authenticating: Data(expectedPurpose.utf8))
    }
    func close() { key = nil; fixture = nil }
  }
  fileprivate struct Key: Codable { let id: String; let chunk: Int; let bodyHash: String }
  private final class Collation {
    var cipher: Cipher?
    let job: String
    var failed = false
    init(_ cipher: Cipher, _ job: String) { self.cipher = cipher; self.job = job }
    func key(_ bytes: UnsafeRawPointer?, _ count: Int32) throws -> Key {
      guard let cipher, (1...32_768).contains(count), let bytes,
            let encrypted = Data(base64Encoded: Data(bytes: bytes, count: Int(count))) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let value = try JSONDecoder().decode(Key.self, from: cipher.decrypt(encrypted, expectedPurpose: "obsidian-order-key:v2:\(job)"))
      guard !value.id.isEmpty, value.id.utf16.count <= 4_096, value.chunk >= 0,
            AgentKnowledgePrimaryMetadata.digest(value.bodyHash) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return value
    }
    func compare(_ a: UnsafeRawPointer?, _ ac: Int32, _ b: UnsafeRawPointer?, _ bc: Int32) -> Int32 {
      let left = try? key(a, ac), right = try? key(b, bc)
      if let left, let right {
        if left.chunk != right.chunk { return left.chunk < right.chunk ? -1 : 1 }
        if left.id.utf16.elementsEqual(right.id.utf16) { return 0 }
        return left.id.utf16.lexicographicallyPrecedes(right.id.utf16) ? -1 : 1
      }
      // Even malformed keys need a stable total preorder inside SQLite. Do not
      // switch comparison rules after the failure flag or cancellation changes.
      failed = true
      if left != nil { return -1 }; if right != nil { return 1 }
      if ac != bc { return ac < bc ? -1 : 1 }
      guard ac > 0 else { return 0 }
      guard let a else { return b == nil ? 0 : -1 }; guard let b else { return 1 }
      let size = min(Int(ac), 32_768)
      let aa = UnsafeRawBufferPointer(start: a, count: size), bb = UnsafeRawBufferPointer(start: b, count: size)
      if aa.elementsEqual(bb) { return 0 }
      return aa.lexicographicallyPrecedes(bb) ? -1 : 1
    }
  }
  let lease: AgentKnowledgeProjectionLease
  private let collation: Collation
  private var database: OpaquePointer?
  private var count: Int64 = 0
  private var sealed = false, failed = false
  private var activeStatements = 0, closing = false
  private let beforeScan: ((OpaquePointer) throws -> Void)?

  init(parent: URL? = nil, cipher: GalaxySSIAttachmentAtRestCipher? = nil,
       beforeScan: ((OpaquePointer) throws -> Void)? = nil) throws {
    try Task.checkCancellation()
    lease = try parent.map { try AgentKnowledgeProjectionLease(parent: $0) } ?? AgentKnowledgeProjectionLease()
    collation = Collation(Cipher(fixture: cipher), lease.id)
    self.beforeScan = beforeScan
    do {
      guard sqlite3_open_v2(lease.databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            let database else { throw AgentKnowledgeDatabaseError.unavailable }
      let context = Unmanaged.passRetained(collation).toOpaque()
      let code = sqlite3_create_collation_v2(database, "ENCRYPTED_SOURCE_ORDER", SQLITE_UTF8, context, { pointer, ac, a, bc, b in
        guard let pointer else { return 0 }
        return Unmanaged<Collation>.fromOpaque(pointer).takeUnretainedValue().compare(a, ac, b, bc)
      }, { pointer in if let pointer { Unmanaged<Collation>.fromOpaque(pointer).release() } })
      guard code == SQLITE_OK else { Unmanaged<Collation>.fromOpaque(context).release(); throw AgentKnowledgeDatabaseError.unavailable }
      for sql in ["PRAGMA journal_mode=DELETE", "PRAGMA synchronous=FULL", "PRAGMA cache_size=-512", "PRAGMA mmap_size=0", "PRAGMA temp_store=FILE",
        "CREATE TABLE ordered_parts(sort_key TEXT COLLATE ENCRYPTED_SOURCE_ORDER PRIMARY KEY,encrypted_item BLOB NOT NULL) WITHOUT ROWID"] { try execute(sql) }
      for (sql, expected) in [("PRAGMA journal_mode", "delete"), ("PRAGMA synchronous", "2"), ("PRAGMA cache_size", "-512"), ("PRAGMA mmap_size", "0"), ("PRAGMA temp_store", "1")] {
        try statement(sql) { row in
          guard sqlite3_step(row) == SQLITE_ROW, let text = sqlite3_column_text(row, 0), String(cString: text) == expected else {
            throw AgentKnowledgeDatabaseError.unavailable
          }
        }
      }
      try execute("BEGIN IMMEDIATE")
    } catch { close(); throw error }
  }
  deinit { close() }
  func close() {
    if activeStatements > 0 { closing = true; failed = true; return }
    if let database { sqlite3_close_v2(database); self.database = nil }
    collation.cipher?.close(); collation.cipher = nil
    lease.close()
  }
  func append(_ item: AgentKnowledgeItem) throws {
    try Task.checkCancellation()
    guard let cipher = collation.cipher, !sealed, !failed, !collation.failed, count < Int64.max,
          !item.id.isEmpty, item.id.utf16.count <= 4_096, item.chunkIndex >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    do {
      let plain = try JSONEncoder.galaxySSI.encode(item)
      let encrypted = try cipher.encrypt(plain, purpose: bodyPurpose(item.id, item.chunkIndex))
      let key = Key(id: item.id, chunk: item.chunkIndex, bodyHash: Self.hash(encrypted))
      let encoded = try cipher.encrypt(JSONEncoder().encode(key), purpose: "obsidian-order-key:v2:\(lease.id)").base64EncodedString()
      guard encoded.utf8.count <= 32_768, let size = Int32(exactly: encrypted.count) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      try statement("INSERT INTO ordered_parts VALUES(?,?)") { row in
        guard encoded.withCString({ sqlite3_bind_text(row, 1, $0, -1, Self.transient) }) == SQLITE_OK,
              encrypted.withUnsafeBytes({ sqlite3_bind_blob(row, 2, $0.baseAddress, size, Self.transient) }) == SQLITE_OK,
              sqlite3_step(row) == SQLITE_DONE, !collation.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
      }
      count += 1
    } catch { failed = true; throw error }
  }
  func finish() throws {
    try Task.checkCancellation()
    guard !sealed, !failed, !collation.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    do { try execute("COMMIT"); sealed = true }
    catch { failed = true; throw error }
  }
  func scan(_ consume: (AgentKnowledgeItem) throws -> Void) throws {
    guard let cipher = collation.cipher, sealed, !failed, !collation.failed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    do {
      if let database { try beforeScan?(database) }
      try statement("SELECT substr(sort_key,1,32769),encrypted_item FROM ordered_parts ORDER BY sort_key COLLATE ENCRYPTED_SOURCE_ORDER") { row in
        var seen: Int64 = 0
        var previous: Key?
        while true {
          try Task.checkCancellation()
          guard !closing else { throw AgentKnowledgeDatabaseError.unavailable }
          let status = sqlite3_step(row)
          if status == SQLITE_DONE { break }
          guard status == SQLITE_ROW, !collation.failed, seen < count else { throw AgentKnowledgeDatabaseError.corruptRecord }
          let key = try collation.key(sqlite3_column_text(row, 0), sqlite3_column_bytes(row, 0))
          if let previous {
            guard previous.chunk < key.chunk || (previous.chunk == key.chunk && previous.id.utf16.lexicographicallyPrecedes(key.id.utf16)) else {
              throw AgentKnowledgeDatabaseError.corruptRecord
            }
          }
          previous = key
          let size = sqlite3_column_bytes(row, 1)
          guard size > 0, let bytes = sqlite3_column_blob(row, 1) else { throw AgentKnowledgeDatabaseError.corruptRecord }
          let encrypted = Data(bytes: bytes, count: Int(size))
          guard Self.hash(encrypted) == key.bodyHash else { throw AgentKnowledgeDatabaseError.corruptRecord }
          let item = try JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self,
            from: cipher.decrypt(encrypted, expectedPurpose: bodyPurpose(key.id, key.chunk)))
          guard item.id.utf8.elementsEqual(key.id.utf8), item.chunkIndex == key.chunk else { throw AgentKnowledgeDatabaseError.corruptRecord }
          try consume(item); seen += 1
        }
        guard seen == count, !collation.failed, sqlite3_stmt_status(row, SQLITE_STMTSTATUS_SORT, 0) == 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
      }
    } catch { failed = true; throw error }
  }
  private func bodyPurpose(_ id: String, _ chunk: Int) -> String {
    "obsidian-order-body:v2:" + Self.hash(Data("\(lease.id):\(Self.hash(Data(id.utf8))):\(chunk)".utf8))
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private static func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  private func statement<T>(_ sql: String, _ action: (OpaquePointer) throws -> T) throws -> T {
    guard let database, !closing else { throw AgentKnowledgeDatabaseError.unavailable }
    var raw: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &raw, nil) == SQLITE_OK, let row = raw else {
      if let raw { sqlite3_finalize(raw) }; throw AgentKnowledgeDatabaseError.unavailable
    }
    activeStatements += 1
    defer {
      sqlite3_finalize(row); activeStatements -= 1
      if closing { close() }
    }
    return try action(row)
  }
}

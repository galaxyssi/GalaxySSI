import Foundation
import SQLite3

// Database and cipher access are serialized by lock, including nested transaction reads.
final class GalaxySSIHealthActivityHistoryStore: @unchecked Sendable {
  enum Failure: Error { case database, invalid, corrupt }
  private var database: OpaquePointer?
  private let lock = NSRecursiveLock()
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let owner: String
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(file: URL, owner: String, secrets: GalaxySSISecretStore) throws {
    guard file.isFileURL, !owner.isEmpty else { throw Failure.invalid }
    self.owner = owner
    cipher = .init(secrets: secrets, keyAccount: "health.activity.rows.v1." + owner)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }; database = nil
      throw Failure.database
    }
    do {
      sqlite3_busy_timeout(database, 5_000)
      try execute("PRAGMA journal_mode = WAL")
      try execute("PRAGMA synchronous = FULL")
      try execute("PRAGMA secure_delete = ON")
      try execute("CREATE TABLE IF NOT EXISTS days(kind INTEGER NOT NULL, day TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind,day)) WITHOUT ROWID")
      for url in [file, URL(fileURLWithPath: file.path + "-wal"), URL(fileURLWithPath: file.path + "-shm")] {
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
      }
    } catch {
      if let database { sqlite3_close_v2(database) }; database = nil
      throw error
    }
  }

  deinit { if let database { sqlite3_close_v2(database) } }

  func save(_ rows: [GalaxySSIHealthActivityDay]) throws {
    lock.lock(); defer { lock.unlock() }
    guard !rows.isEmpty else { return }
    for row in rows {
      guard GalaxySSIHealthActivityComparison.validDay(row.day), (0...row.kind.maximum).contains(row.total) else { throw Failure.invalid }
    }
    try execute("BEGIN IMMEDIATE")
    do {
      for row in rows {
        if let previous = try read(kind: row.kind, first: row.day, last: row.day).first, previous.total >= row.total { continue }
        var plaintext = try JSONEncoder().encode(row.total)
        defer { plaintext.wipeSensitive() }
        let encrypted = try cipher.encrypt(plaintext, purpose: purpose(row.kind, row.day))
        let statement = try prepare("INSERT OR REPLACE INTO days(kind,day,payload) VALUES(?,?,?)")
        defer { sqlite3_finalize(statement) }
        try bind(row.kind.rawValue, statement, 1)
        try bind(row.day, statement, 2)
        let result = encrypted.withUnsafeBytes { bytes in
          sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), transient)
        }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw Failure.database }
      }
      try execute("COMMIT")
    } catch { try? execute("ROLLBACK"); throw error }
  }

  func read(kind: GalaxySSIHealthActivityKind, first: String, last: String) throws -> [GalaxySSIHealthActivityDay] {
    lock.lock(); defer { lock.unlock() }
    guard let days = GalaxySSIHealthActivityComparison.rangeSize(first: first, last: last), (1...732).contains(days) else {
      throw Failure.invalid
    }
    // The index bounds database work as well as the decoded result, not just the UI.
    let statement = try prepare("SELECT day,payload FROM days WHERE kind=? AND day>=? AND day<=? ORDER BY day LIMIT 733")
    defer { sqlite3_finalize(statement) }
    try bind(kind.rawValue, statement, 1); try bind(first, statement, 2); try bind(last, statement, 3)
    var rows: [GalaxySSIHealthActivityDay] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW, let dayBytes = sqlite3_column_text(statement, 0),
            let bytes = sqlite3_column_blob(statement, 1) else { throw Failure.database }
      let day = String(cString: dayBytes)
      let count = Int(sqlite3_column_bytes(statement, 1))
      guard count > 0, count < 2_048, rows.count < 732 else { throw Failure.invalid }
      var plaintext = try cipher.decrypt(Data(bytes: bytes, count: count), expectedPurpose: purpose(kind, day))
      defer { plaintext.wipeSensitive() }
      let total = try JSONDecoder().decode(Int64.self, from: plaintext)
      guard (0...kind.maximum).contains(total) else { throw Failure.corrupt }
      rows.append(.init(kind: kind, day: day, total: total))
    }
    return rows
  }

  private func purpose(_ kind: GalaxySSIHealthActivityKind, _ day: String) -> String {
    "health-activity-v1:\(owner):\(kind.rawValue):\(day)"
  }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.database }
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      if let statement { sqlite3_finalize(statement) }; throw Failure.database
    }
    return statement
  }
  private func bind(_ value: Int, _ statement: OpaquePointer, _ index: Int32) throws {
    guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else { throw Failure.database }
  }
  private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) throws {
    guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, transient) }) == SQLITE_OK else { throw Failure.database }
  }
}

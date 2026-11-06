import Foundation
import SQLite3

final class PublicNewsRowArchive {
  struct Loaded {
    let snapshot: PublicNewsArchiveStorage.Snapshot
    let revision: Int64
  }

  enum Failure: Error { case unavailable, invalid, stale }

  private struct State: Codable {
    let refreshedAt: Date?
    let pushCursor: PublicNewsPushCursor?
    let notRelevantIDs: Set<String>?
    let publisherState: PublicNewsPublisherState?

    init(_ snapshot: PublicNewsArchiveStorage.Snapshot) {
      refreshedAt = snapshot.refreshedAt
      pushCursor = snapshot.pushCursor
      notRelevantIDs = snapshot.notRelevantIDs
      publisherState = snapshot.publisherState
    }
  }

  private enum Value {
    case text(String), integer(Int64), real(Double), data(Data)
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private let db: OpaquePointer

  static func directory(for legacyURL: URL) -> URL {
    legacyURL.appendingPathExtension("rows")
  }

  private static func url(for legacyURL: URL) -> URL {
    directory(for: legacyURL).appendingPathComponent("archive.sqlite3")
  }

  private init(url: URL, writable: Bool) throws {
    if writable {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }
    var pointer: OpaquePointer?
    let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
    guard sqlite3_open_v2(url.path, &pointer, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let pointer else {
      if let pointer { sqlite3_close_v2(pointer) }
      throw Failure.unavailable
    }
    sqlite3_busy_timeout(pointer, writable ? 750 : 100)
    if writable {
      do {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: url.path)
        guard sqlite3_exec(pointer, "PRAGMA synchronous = FULL", nil, nil, nil) == SQLITE_OK else {
          throw Failure.unavailable
        }
      } catch {
        sqlite3_close_v2(pointer)
        throw error
      }
    }
    db = pointer
  }

  deinit { sqlite3_close_v2(db) }

  static func load(legacyURL: URL) throws -> Loaded {
    if let saved = try read(legacyURL: legacyURL, { try $0.snapshot() }) { return saved }
    // Decode before touching the new database. A malformed source is never replaced with an empty archive.
    let legacy = try PublicNewsArchiveStorage.readSnapshot(from: legacyURL) ?? .init(articles: [])
    let archive = try Self(url: url(for: legacyURL), writable: true)
    return try archive.transaction(writable: true) {
      let version = try archive.scalar("PRAGMA user_version")
      if version == 0 {
        try archive.execute("""
          CREATE TABLE article (
            id TEXT PRIMARY KEY NOT NULL, anchor TEXT NOT NULL, sort_date REAL NOT NULL,
            read INTEGER NOT NULL, saved INTEGER NOT NULL, hidden INTEGER NOT NULL, payload BLOB NOT NULL
          );
          CREATE UNIQUE INDEX article_anchor ON article(anchor);
          CREATE INDEX article_order ON article(sort_date DESC, id ASC);
          CREATE INDEX article_visible ON article(sort_date DESC, id ASC) WHERE hidden = 0;
          CREATE INDEX article_unread ON article(sort_date DESC, id ASC) WHERE hidden = 0 AND read = 0;
          CREATE INDEX article_saved ON article(sort_date DESC, id ASC) WHERE hidden = 0 AND saved = 1;
          CREATE TABLE archive_state (
            id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL, unread INTEGER NOT NULL, payload BLOB NOT NULL
          );
          """)
        let ids = Set(legacy.articles.map(\.id))
        guard ids.count == legacy.articles.count else { throw Failure.invalid }
        let hidden = legacy.notRelevantIDs ?? []
        for article in legacy.articles { try archive.put(article, hidden: hidden.contains(article.id)) }
        try archive.putState(legacy, revision: 1)
        try archive.execute("PRAGMA user_version = 1")
      } else if version != 1 {
        throw Failure.invalid
      }
      return try archive.snapshot()
    }
  }

  static func unreadCount(legacyURL: URL) throws -> Int? {
    try read(legacyURL: legacyURL) {
      let count = try $0.scalar("SELECT unread FROM archive_state WHERE id = 1")
      guard count >= 0 else { throw Failure.invalid }
      return Int(count)
    }
  }

  static func firstPage(legacyURL: URL, filter: PublicNewsTimeline.Filter, anchor: String,
                        retaining: Set<String>) throws -> [PublicNewsArticle]? {
    try read(legacyURL: legacyURL) { archive in
      var predicate = "hidden = 0"
      var values: [Value] = []
      switch filter {
      case .all: break
      case .saved: predicate += " AND saved = 1"
      case .unread:
        let retained = retaining.filter(PublicNewsSpeechBookmark.isKey).sorted().prefix(2)
        if retained.isEmpty { predicate += " AND read = 0" }
        else {
          predicate += " AND (read = 0 OR anchor IN (" + retained.map { _ in "?" }.joined(separator: ",") + "))"
          values += retained.map(Value.text)
        }
      }
      let total = try archive.scalar("SELECT COUNT(*) FROM article WHERE " + predicate, values)
      var rank: Int?
      if PublicNewsSpeechBookmark.isKey(anchor) {
        let position = try archive.statement(
          "SELECT sort_date, id FROM article WHERE " + predicate + " AND anchor = ?", values + [.text(anchor)]
        ) { row -> (Double, String)? in
          let step = sqlite3_step(row)
          if step == SQLITE_DONE { return nil }
          guard step == SQLITE_ROW, let id = sqlite3_column_text(row, 1) else { throw Failure.invalid }
          return (sqlite3_column_double(row, 0), String(cString: id))
        }
        if let (date, id) = position {
          rank = Int(try archive.scalar("SELECT COUNT(*) FROM article WHERE " + predicate +
            " AND (sort_date > ? OR (sort_date = ? AND id < ?))", values + [.real(date), .real(date), .text(id)]))
        }
      }
      let page = PublicNewsPageWindow.initialRange(count: Int(total), anchor: rank)
      return try archive.articles("SELECT payload FROM article WHERE " + predicate +
        " ORDER BY sort_date DESC, id ASC LIMIT ? OFFSET ?",
        values + [.integer(Int64(page.count)), .integer(Int64(page.lowerBound))])
    }
  }

  static func save(legacyURL: URL, revision: Int64, previous: [PublicNewsArticle],
                   previousHidden: Set<String>, next: PublicNewsArchiveStorage.Snapshot) throws -> Int64 {
    let archive = try Self(url: url(for: legacyURL), writable: true)
    return try archive.transaction(writable: true) {
      guard try archive.scalar("PRAGMA user_version") == 1 else { throw Failure.invalid }
      guard try archive.scalar("SELECT revision FROM archive_state WHERE id = 1") == revision else { throw Failure.stale }
      guard revision < Int64.max else { throw Failure.invalid }
      let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      let after = Set(next.articles.map(\.id))
      guard after.count == next.articles.count else { throw Failure.invalid }
      let hidden = next.notRelevantIDs ?? []
      for id in before.keys where !after.contains(id) {
        try archive.write("DELETE FROM article WHERE id = ?", [.text(id)])
      }
      for article in next.articles {
        let isHidden = hidden.contains(article.id)
        if before[article.id] != article {
          try archive.put(article, hidden: isHidden)
        } else if previousHidden.contains(article.id) != isHidden {
          try archive.write("UPDATE article SET hidden = ? WHERE id = ?",
            [.integer(isHidden ? 1 : 0), .text(article.id)])
        }
      }
      try archive.putState(next, revision: revision + 1)
      return revision + 1
    }
  }

  private static func read<T>(legacyURL: URL, _ operation: (PublicNewsRowArchive) throws -> T) throws -> T? {
    let databaseURL = url(for: legacyURL)
    guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
    let archive = try Self(url: databaseURL, writable: false)
    return try archive.transaction(writable: false) {
      let version = try archive.scalar("PRAGMA user_version")
      if version == 0 { return nil }
      guard version == 1 else { throw Failure.invalid }
      return try operation(archive)
    }
  }

  private func snapshot() throws -> Loaded {
    let (state, revision) = try statement("SELECT payload, revision FROM archive_state WHERE id = 1") { row in
      guard sqlite3_step(row) == SQLITE_ROW else { throw Failure.invalid }
      return (try JSONDecoder().decode(State.self, from: Self.blob(row)), sqlite3_column_int64(row, 1))
    }
    return Loaded(snapshot: .init(articles: try articles("SELECT payload FROM article ORDER BY sort_date DESC, id ASC"),
      refreshedAt: state.refreshedAt, pushCursor: state.pushCursor,
      notRelevantIDs: state.notRelevantIDs, publisherState: state.publisherState), revision: revision)
  }

  private func articles(_ sql: String, _ values: [Value] = []) throws -> [PublicNewsArticle] {
    try statement(sql, values) { row in
      let decoder = JSONDecoder()
      var items: [PublicNewsArticle] = []
      var step = sqlite3_step(row)
      while step == SQLITE_ROW {
        items.append(try decoder.decode(PublicNewsArticle.self, from: Self.blob(row)))
        step = sqlite3_step(row)
      }
      guard step == SQLITE_DONE else { throw Failure.unavailable }
      return items
    }
  }

  private func put(_ article: PublicNewsArticle, hidden: Bool) throws {
    try write("""
      INSERT INTO article(id, anchor, sort_date, read, saved, hidden, payload) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET sort_date = excluded.sort_date, read = excluded.read,
        saved = excluded.saved, hidden = excluded.hidden, payload = excluded.payload
      """, [.text(article.id), .text(PublicNewsSpeechBookmark.key(for: article.id)),
        .real(article.sortDate.timeIntervalSince1970), .integer(article.read ? 1 : 0), .integer(article.saved ? 1 : 0),
        .integer(hidden ? 1 : 0), .data(try JSONEncoder().encode(article))])
  }

  private func putState(_ snapshot: PublicNewsArchiveStorage.Snapshot, revision: Int64) throws {
    let unread = try scalar("SELECT COUNT(*) FROM article WHERE hidden = 0 AND read = 0")
    try write("INSERT OR REPLACE INTO archive_state(id, revision, unread, payload) VALUES (1, ?, ?, ?)",
      [.integer(revision), .integer(unread), .data(try JSONEncoder().encode(State(snapshot)))])
  }

  private func transaction<T>(writable: Bool, _ operation: () throws -> T) throws -> T {
    try execute(writable ? "BEGIN IMMEDIATE" : "BEGIN")
    do {
      let result = try operation()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable }
  }

  private func scalar(_ sql: String, _ values: [Value] = []) throws -> Int64 {
    try statement(sql, values) { row in
      guard sqlite3_step(row) == SQLITE_ROW else { throw Failure.unavailable }
      return sqlite3_column_int64(row, 0)
    }
  }

  private func write(_ sql: String, _ values: [Value]) throws {
    try statement(sql, values) { row in
      guard sqlite3_step(row) == SQLITE_DONE else { throw Failure.unavailable }
    }
  }

  private func statement<T>(_ sql: String, _ values: [Value] = [], _ operation: (OpaquePointer) throws -> T) throws -> T {
    var pointer: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw Failure.unavailable }
    defer { sqlite3_finalize(pointer) }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case .text(let text): status = sqlite3_bind_text(pointer, index, text, -1, Self.transient)
      case .integer(let number): status = sqlite3_bind_int64(pointer, index, number)
      case .real(let number): status = sqlite3_bind_double(pointer, index, number)
      case .data(let data):
        guard data.count <= Int(Int32.max) else { throw Failure.invalid }
        status = data.withUnsafeBytes { sqlite3_bind_blob(pointer, index, $0.baseAddress, Int32(data.count), Self.transient) }
      }
      guard status == SQLITE_OK else { throw Failure.unavailable }
    }
    return try operation(pointer)
  }

  private static func blob(_ row: OpaquePointer) throws -> Data {
    let size = Int(sqlite3_column_bytes(row, 0))
    guard size > 0, let data = sqlite3_column_blob(row, 0) else { throw Failure.invalid }
    return Data(bytes: data, count: size)
  }
}

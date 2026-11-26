import Foundation
import SQLite3

final class AgentKnowledgeStatementPool {
  enum Failure: Error { case closed, empty, invalidBounds, sqlite(Int32) }
  struct Stats { var prepared: Int64; var reused: Int64; var evicted: Int64; var idle: Int; var sqlChars: Int; var active: Int }
  fileprivate final class Entry {
    let sql: String
    let chars: Int
    let statement: OpaquePointer
    var failed = false
    init(_ sql: String, _ statement: OpaquePointer) { self.sql = sql; chars = sql.utf16.count; self.statement = statement }
  }
  final class Lease {
    fileprivate let pool: AgentKnowledgeStatementPool
    fileprivate let entry: Entry
    fileprivate var released = false
    fileprivate init(_ pool: AgentKnowledgeStatementPool, _ entry: Entry) { self.pool = pool; self.entry = entry }
    func access<T>(_ body: (OpaquePointer) throws -> T) throws -> T { try pool.access(self, body) }
    func markFailed() { pool.markFailed(self) }
    @discardableResult func close() -> Int32 { pool.release(self) }
    deinit { close() }
  }

  private let database: OpaquePointer
  private let capacity: Int
  private let maximumSQLCharacters: Int
  private let lock = NSRecursiveLock()
  private var closed = false
  private var idle: [Entry] = []
  private var active: [OpaquePointer: Entry] = [:]
  private var sqlChars = 0
  private var prepared: Int64 = 0, reused: Int64 = 0, evicted: Int64 = 0

  init(database: OpaquePointer, capacity: Int = 32, maximumSQLCharacters: Int = 65_536) throws {
    guard capacity >= 0, maximumSQLCharacters >= 0 else { throw Failure.invalidBounds }
    self.database = database; self.capacity = capacity; self.maximumSQLCharacters = maximumSQLCharacters
  }
  deinit { close() }
  var stats: Stats {
    lock.lock(); defer { lock.unlock() }
    return Stats(prepared: prepared, reused: reused, evicted: evicted, idle: idle.count, sqlChars: sqlChars, active: active.count)
  }

  func acquire(_ sql: String) throws -> Lease {
    lock.lock(); defer { lock.unlock() }
    guard !closed else { throw Failure.closed }
    let entry: Entry
    if let index = idle.firstIndex(where: { $0.sql == sql }) {
      entry = idle.remove(at: index); sqlChars -= entry.chars; reused += 1
    } else {
      var statement: OpaquePointer?
      let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
      guard code == SQLITE_OK else {
        if let statement { sqlite3_finalize(statement) }
        throw Failure.sqlite(code)
      }
      guard let statement else { throw Failure.empty }
      entry = Entry(sql, statement); prepared += 1
    }
    active[entry.statement] = entry
    return Lease(self, entry)
  }

  func close() {
    lock.lock(); defer { lock.unlock() }
    guard !closed else { return }
    closed = true
    for entry in idle { sqlite3_finalize(entry.statement) }
    idle.removeAll(); sqlChars = 0
    // Active lease access is now invalid. Keep its native statement until its
    // owner returns it, preserving sqlite3_close_v2's deferred-close lifetime.
  }

  private func access<T>(_ lease: Lease, _ body: (OpaquePointer) throws -> T) throws -> T {
    lock.lock(); defer { lock.unlock() }
    guard !closed, !lease.released, active[lease.entry.statement] === lease.entry else { throw Failure.closed }
    do { return try body(lease.entry.statement) }
    catch { lease.entry.failed = true; throw error }
  }
  private func markFailed(_ lease: Lease) {
    lock.lock(); defer { lock.unlock() }
    if !lease.released { lease.entry.failed = true }
  }
  private func cacheable(_ sql: String) -> Bool {
    let keyword = sql.split(whereSeparator: { $0.isWhitespace }).first?.uppercased() ?? ""
    return ["SELECT", "INSERT", "UPDATE", "DELETE", "REPLACE"].contains(keyword)
  }
  private func release(_ lease: Lease) -> Int32 {
    lock.lock(); defer { lock.unlock() }
    guard !lease.released else { return SQLITE_OK }
    lease.released = true
    let entry = lease.entry
    active.removeValue(forKey: entry.statement)
    if closed { return sqlite3_finalize(entry.statement) }
    let reset = sqlite3_reset(entry.statement)
    let cleared = sqlite3_clear_bindings(entry.statement)
    guard !entry.failed, reset == SQLITE_OK, cleared == SQLITE_OK, capacity > 0,
          entry.chars <= maximumSQLCharacters, cacheable(entry.sql) else {
      let finalized = sqlite3_finalize(entry.statement)
      return reset != SQLITE_OK ? reset : (cleared != SQLITE_OK ? cleared : finalized)
    }
    if let duplicate = idle.firstIndex(where: { $0.sql == entry.sql }) { evict(duplicate) }
    while !idle.isEmpty && (idle.count >= capacity || sqlChars > maximumSQLCharacters - entry.chars) { evict(0) }
    idle.append(entry); sqlChars += entry.chars
    return SQLITE_OK
  }
  private func evict(_ index: Int) {
    let entry = idle.remove(at: index)
    sqlChars -= entry.chars; evicted += 1
    sqlite3_finalize(entry.statement)
  }
}

// Compatibility boundary for the existing connection-serialized knowledge C API.
// A returned pointer is borrowed until release(), never an owned cached object.
final class AgentKnowledgeSQLiteStatements {
  static let shared = AgentKnowledgeSQLiteStatements()
  private let lock = NSRecursiveLock()
  private var connections: [OpaquePointer: AgentKnowledgeStatementPool] = [:]
  private var borrowed: [OpaquePointer: AgentKnowledgeStatementPool.Lease] = [:]
  private var direct: [OpaquePointer: OpaquePointer] = [:]

  func prepare(_ handle: OpaquePointer?, _ sql: String, _ bytes: Int32, _ statement: inout OpaquePointer?,
               _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32 {
    statement = nil
    guard let handle else { return SQLITE_MISUSE }
    // Preserve the full C API for callers requesting an explicit byte span/tail.
    guard bytes == -1, tail == nil else {
      let code = sqlite3_prepare_v2(handle, sql, bytes, &statement, tail)
      if let statement { lock.lock(); direct[statement] = handle; lock.unlock() }
      return code
    }
    do {
      lock.lock()
      let pool: AgentKnowledgeStatementPool
      if let existing = connections[handle] { pool = existing }
      else {
        do { pool = try AgentKnowledgeStatementPool(database: handle) }
        catch { lock.unlock(); throw error }
        connections[handle] = pool
      }
      lock.unlock()
      let lease = try pool.acquire(sql)
      let pointer = try lease.access { $0 }
      lock.lock(); borrowed[pointer] = lease; lock.unlock()
      statement = pointer
      return SQLITE_OK
    } catch AgentKnowledgeStatementPool.Failure.empty { return SQLITE_OK }
    catch AgentKnowledgeStatementPool.Failure.sqlite(let code) { return code }
    catch { return SQLITE_MISUSE }
  }

  @discardableResult func release(_ statement: OpaquePointer?) -> Int32 {
    guard let statement else { return SQLITE_OK }
    lock.lock()
    let lease = borrowed.removeValue(forKey: statement)
    let unpooled = direct.removeValue(forKey: statement)
    lock.unlock()
    if let lease { return lease.close() }
    return unpooled != nil ? sqlite3_finalize(statement) : SQLITE_MISUSE
  }
  func markFailed(_ statement: OpaquePointer?) {
    guard let statement else { return }
    lock.lock(); let lease = borrowed[statement]; lock.unlock()
    lease?.markFailed()
  }
  @discardableResult func close(_ handle: OpaquePointer?) -> Int32 {
    guard let handle else { return SQLITE_OK }
    lock.lock()
    let pool = connections.removeValue(forKey: handle)
    let loans = borrowed.filter { $0.value.pool === pool }.map(\.key)
    let leases = loans.compactMap { borrowed.removeValue(forKey: $0) }
    let raw = direct.filter { $0.value == handle }.map(\.key)
    for statement in raw { direct.removeValue(forKey: statement) }
    lock.unlock()
    pool?.close()
    for lease in leases { lease.close() }
    for statement in raw { sqlite3_finalize(statement) }
    return sqlite3_close_v2(handle)
  }
  func stats(for handle: OpaquePointer) -> AgentKnowledgeStatementPool.Stats? {
    lock.lock(); let pool = connections[handle]; lock.unlock()
    return pool?.stats
  }
}

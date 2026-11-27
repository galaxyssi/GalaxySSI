import Darwin
import Foundation
import SQLite3
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryReadConnectionsTests: XCTestCase {
  private enum Fault: Error { case injected }
  private final class Fixture {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var root: URL { parent.appendingPathComponent("primary", isDirectory: true) }
    var file: URL { root.appendingPathComponent("body.sqlite") }
    let center = NotificationCenter()
    let queue = DispatchQueue(label: "test.knowledge.readers.trim")
    let cache: AgentKnowledgePrimaryReadConnections
    var descriptor: Int32 = -1
    init() throws {
      cache = AgentKnowledgePrimaryReadConnections(capacity: 1, center: center, cleanup: queue)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw Fault.injected }
      try create(file, value: 1)
    }
    deinit {
      try? cache.clear(root: root)
      if descriptor >= 0 { Darwin.close(descriptor) }
      try? FileManager.default.removeItem(at: parent)
    }
    func create(_ path: URL, value: Int) throws {
      var database: OpaquePointer?
      guard sqlite3_open(path.path, &database) == SQLITE_OK, let database else { throw Fault.injected }
      defer { AgentKnowledgeSQLiteStatements.shared.close(database) }
      guard sqlite3_exec(database, "CREATE TABLE body(value INTEGER); INSERT INTO body VALUES(\(value))", nil, nil, nil) == SQLITE_OK else {
        throw Fault.injected
      }
    }
    func open() throws -> OpaquePointer {
      var database: OpaquePointer?
      guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
        if let database { AgentKnowledgeSQLiteStatements.shared.close(database) }
        throw Fault.injected
      }
      return database
    }
    func read(_ action: ((OpaquePointer) throws -> Int)? = nil) throws -> Int {
      try cache.read(root: root, file: file, directoryDescriptor: descriptor, checkActive: {}, open: open) { db in
        if let action { return try action(db) }
        var raw: OpaquePointer?
        guard AgentKnowledgeSQLiteStatements.shared.prepare(db, "SELECT value FROM body", -1, &raw, nil) == SQLITE_OK,
              let statement = raw else { throw Fault.injected }
        defer { AgentKnowledgeSQLiteStatements.shared.release(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw Fault.injected }
        return Int(sqlite3_column_int(statement, 0))
      }
    }
  }

  func testReadReusesHandleAndManagedStatement() throws {
    let f = try Fixture()
    XCTAssertEqual(try f.read(), 1)
    XCTAssertEqual(try f.read(), 1)
    XCTAssertEqual(f.cache.stats.opened, 1)
    XCTAssertEqual(f.cache.stats.reused, 1)
    XCTAssertEqual(f.cache.stats.idle, 1)
    _ = try f.read { db in
      XCTAssertGreaterThan(try XCTUnwrap(AgentKnowledgeSQLiteStatements.shared.stats(for: db)).reused, 0)
      return 0
    }
  }

  func testReplacedRegularFileReopensInsteadOfServingOldInode() throws {
    let f = try Fixture()
    XCTAssertEqual(try f.read(), 1)
    let replacement = f.root.appendingPathComponent("replacement.sqlite")
    try f.create(replacement, value: 2)
    try FileManager.default.removeItem(at: f.file)
    try FileManager.default.moveItem(at: replacement, to: f.file)
    XCTAssertEqual(try f.read(), 2)
    XCTAssertEqual(f.cache.stats.opened, 2)
    XCTAssertEqual(f.cache.stats.reused, 0)
  }

  func testMissingAndSymlinkedMainFilesRejectAndDisposeOldReader() throws {
    for symlink in [false, true] {
      let f = try Fixture()
      XCTAssertEqual(try f.read(), 1)
      let saved = f.root.appendingPathComponent("saved.sqlite")
      try FileManager.default.moveItem(at: f.file, to: saved)
      if symlink { try FileManager.default.createSymbolicLink(at: f.file, withDestinationURL: saved) }
      XCTAssertThrowsError(try f.read())
      XCTAssertEqual(f.cache.stats.active + f.cache.stats.idle, 0)
    }
  }

  func testSidecarSymlinkRejectsCachedReader() throws {
    let f = try Fixture()
    _ = try f.read()
    let sidecar = URL(fileURLWithPath: f.file.path + "-journal")
    try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: f.file)
    XCTAssertThrowsError(try f.read())
    XCTAssertEqual(f.cache.stats.idle, 0)
  }

  func testReplacedRootIsRejectedAgainstAnchoredDirectory() throws {
    let f = try Fixture()
    _ = try f.read()
    try FileManager.default.moveItem(at: f.root, to: f.parent.appendingPathComponent("old"))
    try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
    try f.create(f.file, value: 2)
    XCTAssertThrowsError(try f.read())
    XCTAssertEqual(f.cache.stats.idle, 0)
  }

  func testSwapDuringOpenClosesRejectedHandle() throws {
    let f = try Fixture()
    let replacement = f.root.appendingPathComponent("replacement.sqlite")
    try f.create(replacement, value: 2)
    XCTAssertThrowsError(try f.cache.read(root: f.root, file: f.file, directoryDescriptor: f.descriptor,
      checkActive: {}, open: {
        let handle = try f.open()
        var returned = false
        defer { if !returned { AgentKnowledgeSQLiteStatements.shared.close(handle) } }
        try FileManager.default.removeItem(at: f.file)
        try FileManager.default.moveItem(at: replacement, to: f.file)
        returned = true
        return handle
      }, action: { _ in XCTFail("Must not publish swapped handle"); return 0 }))
    XCTAssertEqual(f.cache.stats.active + f.cache.stats.idle, 0)
    XCTAssertEqual(try f.read(), 2)
  }

  func testActionFailureDiscardsAndNextReadReopens() throws {
    let f = try Fixture()
    XCTAssertThrowsError(try f.read { _ in throw Fault.injected })
    XCTAssertEqual(f.cache.stats.idle, 0)
    XCTAssertEqual(try f.read(), 1)
    XCTAssertEqual(f.cache.stats.opened, 2)
  }

  func testRetirementRefusesActiveReadAndThenClosesIdleReader() throws {
    let f = try Fixture()
    _ = try f.read { db in
      XCTAssertThrowsError(try f.cache.retire(root: f.root, file: f.file))
      XCTAssertEqual(sqlite3_db_readonly(db, "main"), 1)
      return 1
    }
    XCTAssertEqual(f.cache.stats.idle, 1)
    try f.cache.retire(root: f.root, file: f.file)
    XCTAssertEqual(f.cache.stats.idle, 0)
  }

  func testMemoryWarningAndRuntimeClearTrimOnCleanupQueue() throws {
    let f = try Fixture()
    for name in [UIApplication.didReceiveMemoryWarningNotification, .galaxySSIRuntimePlaintextWillClear] {
      _ = try f.read()
      f.center.post(name: name, object: nil)
      f.queue.sync {}
      XCTAssertEqual(f.cache.stats.idle, 0)
    }
    XCTAssertEqual(f.cache.stats.opened, 2)
  }

  func testRootClearLetsActiveActionFinishButDoesNotRetainIt() throws {
    let f = try Fixture()
    _ = try f.read { db in
      try f.cache.clear(root: f.root)
      XCTAssertEqual(sqlite3_db_readonly(db, "main"), 1)
      return 1
    }
    XCTAssertEqual(f.cache.stats.active + f.cache.stats.idle, 0)
  }

  func testActualPrimaryReadsReuseAndAuthenticationFailureDiscards() throws {
    let cache = AgentKnowledgePrimaryReadConnections(center: NotificationCenter())
    let f = try AgentKnowledgePrimaryPartitionsTests.Fixture(readConnections: cache), body = Data("authenticated body".utf8)
    try f.write(body)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
    XCTAssertEqual(cache.stats.opened, 1)
    XCTAssertGreaterThan(cache.stats.reused, 0)
    let id = try f.partitionID()
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(f.partitionURL(id).path, &database), SQLITE_OK)
    let handle = try XCTUnwrap(database)
    XCTAssertEqual(sqlite3_exec(handle, "UPDATE frames SET sealed=x'00'", nil, nil, nil), SQLITE_OK)
    AgentKnowledgeSQLiteStatements.shared.close(handle)
    XCTAssertThrowsError(try f.store.read(itemHash: f.key, catalog: f.catalog))
    XCTAssertEqual(cache.stats.idle, 0)
  }

  func testActualPrimaryRetirementDrainsReadersBeforeUnlink() throws {
    let cache = AgentKnowledgePrimaryReadConnections(center: NotificationCenter())
    let f = try AgentKnowledgePrimaryPartitionsTests.Fixture(readConnections: cache)
    try f.write(Data("retire".utf8))
    let id = try f.partitionID(), file = f.partitionURL(id)
    _ = try f.store.read(itemHash: f.key, catalog: f.catalog)
    XCTAssertEqual(cache.stats.idle, 1)
    try f.sql("DELETE FROM knowledge_primary_refs")
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertFalse(page.deferred)
    XCTAssertEqual(cache.stats.idle, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }
}

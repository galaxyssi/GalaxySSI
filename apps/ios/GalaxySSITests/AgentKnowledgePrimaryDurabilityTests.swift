import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryDurabilityTests: XCTestCase {
  private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { root.appendingPathComponent("durability.sqlite") }
    var database: OpaquePointer?
    init(memory: Bool = false) throws {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      guard sqlite3_open(memory ? ":memory:" : url.path, &database) == SQLITE_OK else {
        if let database { AgentKnowledgeSQLiteStatements.shared.close(database) }; throw AgentKnowledgePrimaryDurability.Failure.sqlite
      }
    }
    deinit { if let database { AgentKnowledgeSQLiteStatements.shared.close(database) }; try? FileManager.default.removeItem(at: root) }
    func sql(_ sql: String) throws {
      guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgePrimaryDurability.Failure.sqlite }
    }
  }

  func testPrimaryWriterRequestsAndReadsBackExtraWithWAL() throws {
    let f = try Fixture()
    try AgentKnowledgePrimaryDurability.configure(f.database, role: .primary)
    try AgentKnowledgePrimaryDurability.verify(f.database, role: .primary)
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.verify(f.database, role: .catalog))
  }

  func testCatalogWriterKeepsFullAndRejectsBodyRole() throws {
    let f = try Fixture()
    try AgentKnowledgePrimaryDurability.configure(f.database, role: .catalog)
    try AgentKnowledgePrimaryDurability.verify(f.database, role: .catalog)
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.verify(f.database, role: .primary))
  }

  func testNilAndInMemoryConnectionsCannotPretendToBeDurableWriters() throws {
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.configure(nil, role: .primary))
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.verify(nil, role: .catalog))
    let memory = try Fixture(memory: true)
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.configure(memory.database, role: .primary))
  }

  func testReadOnlyConnectionCannotBeConfiguredOrVerifiedAsWriter() throws {
    let f = try Fixture()
    try AgentKnowledgePrimaryDurability.configure(f.database, role: .primary)
    var reader: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(f.url.path, &reader, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { AgentKnowledgeSQLiteStatements.shared.close(reader) }
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.configure(reader, role: .primary))
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.verify(reader, role: .primary))
  }

  func testConfigurationRequiresAutocommitButVerificationAllowsPendingCommit() throws {
    let f = try Fixture()
    try AgentKnowledgePrimaryDurability.configure(f.database, role: .primary)
    try f.sql("BEGIN IMMEDIATE")
    defer { try? f.sql("ROLLBACK") }
    XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.configure(f.database, role: .primary))
    try AgentKnowledgePrimaryDurability.verify(f.database, role: .primary)
  }

  func testRuntimeDowngradesOfSyncFlagsAndJournalAreRejected() throws {
    let f = try Fixture()
    for downgrade in ["PRAGMA synchronous=OFF", "PRAGMA fullfsync=OFF",
      "PRAGMA checkpoint_fullfsync=OFF", "PRAGMA journal_mode=DELETE"] {
      try AgentKnowledgePrimaryDurability.configure(f.database, role: .primary)
      try f.sql(downgrade)
      XCTAssertThrowsError(try AgentKnowledgePrimaryDurability.verify(f.database, role: .primary), downgrade)
    }
  }

  func testDowngradedCatalogPublicationRetainsPreviousCommittedBody() throws {
    var sabotage = false, catalog: OpaquePointer?
    let f = try AgentKnowledgePrimaryPartitionsTests.Fixture(beforeCatalogPublication: {
      if sabotage, sqlite3_exec(catalog, "PRAGMA fullfsync=OFF", nil, nil, nil) != SQLITE_OK {
        throw AgentKnowledgePrimaryDurability.Failure.sqlite
      }
    })
    catalog = f.catalog
    let previous = Data("Previous committed body".utf8)
    try f.write(previous)
    sabotage = true
    XCTAssertThrowsError(try f.batch { try f.stage(Data("Unpublished replacement".utf8)) })
    try AgentKnowledgePrimaryDurability.configure(f.catalog, role: .catalog)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), previous)
  }
}

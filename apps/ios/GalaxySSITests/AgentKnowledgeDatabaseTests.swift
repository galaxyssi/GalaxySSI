import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeDatabaseTests: XCTestCase {
  func testEncryptedDatabaseRetainsMoreThanLegacyCapAcrossReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let items = (0..<1_201).map { index in
      AgentKnowledgeItem(
        id: "item-\(index)",
        kind: .document,
        title: "Title \(index)",
        content: index == 1_200 ? "Private body 1200 with unique marker and \u{72ec}\u{7279}\u{77e5}\u{8bc6}" : "Private body \(index)",
        source: "source-\(index / 10)",
        updatedAtMillis: Int64(index)
      )
    }

    XCTAssertTrue(AgentKnowledgeDatabase(fileURL: url, secrets: secrets).replaceAll(items))
    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let restored = try reopened.all()

    XCTAssertEqual(restored.count, 1_201)
    XCTAssertEqual(Set(restored.map(\.id)), Set(items.map(\.id)))
    XCTAssertEqual(try reopened.searchCandidates(query: "1200").map(\.id), ["item-1200"])
    XCTAssertEqual(try reopened.searchCandidates(query: "\u{72ec}\u{7279}\u{77e5}\u{8bc6}").map(\.id), ["item-1200"])
    let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    XCTAssertFalse(raw.contains("Private body 1200"))
    XCTAssertFalse(raw.contains("source-120"))
    XCTAssertFalse(raw.contains("item-1200"))
  }

  func testEncryptedDatabaseRejectsIdentityCollisionsAndWrongKeys() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite")
    let secrets = InMemorySecretStore()
    let first = AgentKnowledgeItem(id: "same", kind: .note, title: "First", content: "one", source: "a")
    let collision = AgentKnowledgeItem(id: "same", kind: .note, title: "Second", content: "two", source: "b")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)

    XCTAssertTrue(database.replaceAll([first]))
    XCTAssertFalse(database.replaceAll([first, collision]))
    XCTAssertEqual(try database.all(), [first])
    XCTAssertThrowsError(try AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore()).all())
  }
}

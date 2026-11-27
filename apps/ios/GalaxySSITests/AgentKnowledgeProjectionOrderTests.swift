import CryptoKit
import Darwin
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeProjectionOrderTests: XCTestCase {
  private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var scratch: URL { root.appendingPathComponent("scratch", isDirectory: true) }
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
  }
  private func item(_ id: String, chunk: Int = 0) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .document, title: "Sorted", content: "private-body-sentinel-\(id)", source: "fixture", chunkIndex: chunk, updatedAtMillis: 1)
  }
  private func fixture() throws -> Fixture {
    let value = try Fixture()
    addTeardownBlock { withExtendedLifetime(value) {} }
    return value
  }
  private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func exec(_ db: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  func testOrderUsesChunkAndRawUTF16IdentityNotItsDigest() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    defer { order.close() }
    let ids = ["z", "a", "\u{10000}", "\u{e000}", "\u{e9}", "e\u{301}"]
    for id in ids { try order.append(item(id)) }
    try order.append(item("first", chunk: 0)); try order.append(item("last", chunk: 1)); try order.finish()
    var actual: [String] = []
    try order.scan { actual.append($0.id) }
    let expected = (ids + ["first"]).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) } + ["last"]
    XCTAssertEqual(actual.map { Array($0.utf16) }, expected.map { Array($0.utf16) })
  }
  func testTwoPassesMatchAndOnDiskKeysAndBodiesAreNotPlaintext() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    defer { order.close() }
    for index in (0..<130).reversed() { try order.append(item("private-identity-sentinel-\(index)", chunk: index)) }
    try order.finish()
    let bytes = try Data(contentsOf: order.lease.databaseURL)
    XCTAssertNil(bytes.range(of: Data("private-identity-sentinel-".utf8)))
    XCTAssertNil(bytes.range(of: Data("private-body-sentinel-".utf8)))
    var first: [String] = [], second: [String] = []
    try order.scan { first.append($0.id) }; try order.scan { second.append($0.id) }
    XCTAssertEqual(first, second); XCTAssertEqual(first.count, 130)
  }
  func testDuplicateLogicalOrderKeyPoisonsTheJob() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    defer { order.close() }
    try order.append(item("same"))
    XCTAssertThrowsError(try order.append(item("same")))
    XCTAssertThrowsError(try order.finish())
  }
  func testMissingAuthenticatedRowsCannotMasqueradeAsEOF() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch, beforeScan: { db in
      try self.exec(db, "DELETE FROM ordered_parts WHERE sort_key IN (SELECT sort_key FROM ordered_parts LIMIT 1)")
    })
    defer { order.close() }
    try order.append(item("a")); try order.append(item("b")); try order.finish()
    XCTAssertThrowsError(try order.scan { _ in })
  }
  func testCorruptBodyOrSortKeyFailsClosed() throws {
    for sql in ["UPDATE ordered_parts SET encrypted_item=x'00'", "UPDATE ordered_parts SET sort_key='malformed'"] {
      let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch, beforeScan: { db in _ = sqlite3_exec(db, sql, nil, nil, nil) })
      defer { order.close() }
      try order.append(item("a")); try order.append(item("b")); try order.finish()
      XCTAssertThrowsError(try order.scan { _ in })
    }
  }
  func testSQLiteStepInterruptionIsNotSuccessfulEndOfData() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch, beforeScan: { db in
      sqlite3_progress_handler(db, 100, { _ in 1 }, nil)
    })
    defer { order.close() }
    for value in 0..<130 { try order.append(item("item-\(value)", chunk: value)) }; try order.finish()
    XCTAssertThrowsError(try order.scan { _ in })
  }
  func testCloseDropsOwnedFilesAndPreventsFurtherUse() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    let directory = order.lease.directory
    try order.append(item("a")); try order.finish(); order.close(); order.close()
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertThrowsError(try order.scan { _ in }); XCTAssertThrowsError(try order.append(item("b")))
  }
  func testLiveLeasesSurviveConcurrentJobSweep() throws {
    let f = try fixture(), first = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    defer { first.close() }
    let second = try AgentKnowledgeProjectionOrder(parent: f.scratch); defer { second.close() }
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.lease.directory.path))
    try first.append(item("first")); try first.finish(); var values: [String] = []
    try first.scan { values.append($0.id) }; XCTAssertEqual(values, ["first"])
  }
  func testCloseDuringScanDefersNativeDisposalAndStopsFurtherDelivery() throws {
    let f = try fixture(), order = try AgentKnowledgeProjectionOrder(parent: f.scratch)
    try order.append(item("a")); try order.append(item("b")); try order.finish()
    var delivered = 0
    XCTAssertThrowsError(try order.scan { _ in delivered += 1; order.close() })
    XCTAssertEqual(delivered, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: order.lease.directory.path))
  }
  func testSweepRemovesOnlyRecognizedUnlockedOrphans() throws {
    let f = try fixture()
    try FileManager.default.createDirectory(at: f.scratch, withIntermediateDirectories: true)
    let orphan = f.scratch.appendingPathComponent("job-" + UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
    XCTAssertTrue(FileManager.default.createFile(atPath: orphan.appendingPathComponent(".lease").path, contents: Data()))
    XCTAssertTrue(FileManager.default.createFile(atPath: orphan.appendingPathComponent("order.sqlite").path, contents: Data("orphan".utf8)))
    let order = try AgentKnowledgeProjectionOrder(parent: f.scratch); defer { order.close() }
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
  }
  func testSweepPreservesUnknownFilesSymlinksAndUnclaimedDirectories() throws {
    let f = try fixture()
    try FileManager.default.createDirectory(at: f.scratch, withIntermediateDirectories: true)
    let outside = f.root.appendingPathComponent("outside.txt"); try Data("keep".utf8).write(to: outside)
    var protected: [URL] = []
    for type in 0..<3 {
      let directory = f.scratch.appendingPathComponent("job-" + UUID().uuidString.lowercased())
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      if type != 2 { XCTAssertTrue(FileManager.default.createFile(atPath: directory.appendingPathComponent(".lease").path, contents: Data())) }
      if type == 0 { try Data("unknown".utf8).write(to: directory.appendingPathComponent("keep.txt")) }
      else if type == 1 { try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("order.sqlite"), withDestinationURL: outside) }
      else { try Data("unclaimed".utf8).write(to: directory.appendingPathComponent("order.sqlite")) }
      protected.append(directory)
    }
    let order = try AgentKnowledgeProjectionOrder(parent: f.scratch); defer { order.close() }
    for directory in protected { XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path)) }
    XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
  }
  func testTextScanHashesEntireFileWhileKeepingOnlyUTF16Prefix() throws {
    let f = try fixture(), url = f.root.appendingPathComponent("edited.md")
    let text = "A\u{1f680}B" + String(repeating: "tail", count: 10_000), data = Data(text.utf8)
    try data.write(to: url)
    let result = try AgentIOSObsidianTextScan.read(url, maximumUTF16: 2)
    XCTAssertEqual(result.prefix, "A"); XCTAssertEqual(result.hash, hash(data))
    XCTAssertEqual(try AgentIOSObsidianTextScan.read(url, maximumUTF16: 0).prefix, "")
  }
  func testTextScanHandlesUTF8SequencesAcrossEveryChunkBoundary() throws {
    let f = try fixture(), url = f.root.appendingPathComponent("unicode.md")
    for split in 1...3 {
      let text = String(repeating: "a", count: 8_192 - split) + "\u{1f680}\u{4e2d}e\u{301}", data = Data(text.utf8)
      try data.write(to: url)
      let result = try AgentIOSObsidianTextScan.read(url, maximumUTF16: 20_000)
      XCTAssertEqual(result.prefix.utf8.map { $0 }, data.map { $0 }); XCTAssertEqual(result.hash, hash(data))
    }
  }
  func testTextScanRejectsMalformedOrIncompleteUTF8AndSymlinks() throws {
    let f = try fixture(), url = f.root.appendingPathComponent("bad.md")
    for data in [Data([0xFF]), Data([0xF0, 0x9F]), Data([0xED, 0xA0, 0x80])] {
      try data.write(to: url); XCTAssertThrowsError(try AgentIOSObsidianTextScan.read(url, maximumUTF16: 1))
    }
    let link = f.root.appendingPathComponent("link.md")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    XCTAssertThrowsError(try AgentIOSObsidianTextScan.read(link, maximumUTF16: 1))
  }
  func testDestinationChangedDuringPreparationPreservesUserEdit() throws {
    let f = try fixture(), url = f.root.appendingPathComponent("note.md")
    try Data("old".utf8).write(to: url)
    let destination = try AgentIOSProjectionDestination(url, expected: hash(Data("old".utf8)))
    let staged = try destination.stage(job: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: staged) }
    try Data("generated".utf8).write(to: staged); try Data("user edit".utf8).write(to: url)
    XCTAssertThrowsError(try destination.publish(staged))
    XCTAssertEqual(try Data(contentsOf: url), Data("user edit".utf8))
  }
  func testDestinationAlreadyEditedOrSymlinkedRejectsBeforePreparation() throws {
    let f = try fixture(), url = f.root.appendingPathComponent("note.md"), link = f.root.appendingPathComponent("link.md")
    try Data("user".utf8).write(to: url)
    XCTAssertThrowsError(try AgentIOSProjectionDestination(url, expected: hash(Data("old".utf8))))
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    XCTAssertThrowsError(try AgentIOSProjectionDestination(link))
  }
  @MainActor func testActualProjectionRawIDTieOrderAndExactOutputHash() throws {
    let f = try fixture(), database = AgentKnowledgeDatabase(fileURL: f.root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    let items = [item("z"), item("a")]
    XCTAssertTrue(database.replaceAll(items))
    let group = try XCTUnwrap(database.sourcePage().groups.first), destination = f.root.appendingPathComponent("note.md")
    let result = try AgentIOSObsidianBridge.writeKnowledgeProjection(database: database, group: group, sourceKey: "fixture", type: "knowledge", fallbackTitle: "Sorted", source: "fixture", destination: destination)
    let expected = AgentIOSObsidianBridge.note(sourceKey: "fixture", type: "knowledge", title: "Sorted", source: "fixture", updatedAtMillis: 1,
      tags: [], body: "private-body-sentinel-a\n\nprivate-body-sentinel-z")
    XCTAssertEqual(try Data(contentsOf: destination), Data(expected.utf8)); XCTAssertEqual(result, hash(Data(expected.utf8)))
  }
  @MainActor func testLateScratchCorruptionCannotPublishOrReplaceTheDestination() throws {
    let f = try fixture(), database = AgentKnowledgeDatabase(fileURL: f.root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    XCTAssertTrue(database.replaceAll([item("a"), item("b")]))
    let group = try XCTUnwrap(database.sourcePage().groups.first), destination = f.root.appendingPathComponent("note.md")
    try Data("user baseline".utf8).write(to: destination)
    var scans = 0
    let order = try AgentKnowledgeProjectionOrder(parent: f.scratch, beforeScan: { db in
      scans += 1
      if scans == 2 { try self.exec(db, "UPDATE ordered_parts SET encrypted_item=x'00'") }
    })
    XCTAssertThrowsError(try AgentIOSObsidianBridge.writeKnowledgeProjection(database: database, group: group, sourceKey: "fixture", type: "knowledge",
      fallbackTitle: "Sorted", source: "fixture", destination: destination, scratchOrder: order))
    XCTAssertEqual(scans, 2); XCTAssertEqual(try Data(contentsOf: destination), Data("user baseline".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: order.lease.directory.path))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: f.root.path).contains { $0.hasSuffix(".tmp") })
  }
}

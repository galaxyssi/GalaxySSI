import XCTest
@testable import GalaxySSI

final class AgentIOSOriginalPageArchiveStoreTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    var values: [String: String] = [:]
    func setString(_ value: String, account: String) throws { values[account] = value }
    func string(account: String) -> String? { values[account] }
    func delete(account: String) { values.removeValue(forKey: account) }
  }

  func testEncryptedQueueReopensStagesAndPublishesWithoutDuplicateWork() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cipher = GalaxySSIAttachmentAtRestCipher(secrets: Secrets(), keyAccount: "synthetic-archive")
    let documents = root.appendingPathComponent("Documents")
    func queue() -> AgentIOSOriginalPageArchiveStore {
      .init(profile: "profile-a", applicationSupport: root, documents: documents, cipher: cipher)
    }
    let source = Data("<p>Private source marker</p>".utf8)
    let id = try queue().enqueue(source: source, url: "https://example.com", name: "article", language: "en", conversation: "c", turn: "t")
    let reopened = queue(), job = try XCTUnwrap(reopened.due(now: 0))
    XCTAssertEqual(job.id, id)
    XCTAssertEqual(job.source, source)
    let rendered = Data("<p>Static original</p>".utf8)
    try reopened.stage(rendered, id: id)
    XCTAssertEqual(try queue().staged(id), rendered)
    try reopened.publish(job, data: rendered)
    XCTAssertNil(try queue().due(now: Int64.max))
    XCTAssertEqual(try queue().enqueue(source: source, url: "https://example.com", name: "article", language: "en", conversation: "c", turn: "t"), id)
    XCTAssertNil(try queue().due(now: Int64.max))
    let files = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "html" } ?? []
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), rendered)
  }

  func testArchiveQueueKeepsProfileIsolationAndThreeFailureBoundary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cipher = GalaxySSIAttachmentAtRestCipher(secrets: Secrets(), keyAccount: "synthetic-archive")
    let queue = AgentIOSOriginalPageArchiveStore(profile: "a", applicationSupport: root, documents: root, cipher: cipher)
    _ = try queue.enqueue(source: Data("<p>Source</p>".utf8), url: "https://example.com", name: "article", language: "en", conversation: "c", turn: "t")
    let other = AgentIOSOriginalPageArchiveStore(profile: "b", applicationSupport: root, documents: root, cipher: cipher)
    XCTAssertNil(try other.due(now: Int64.max))
    let original = try XCTUnwrap(queue.due(now: 0))
    XCTAssertNil(try queue.due(now: 0, excluding: [original.id]))
    for failure in 1...3 {
      try queue.failed(original, now: 0)
      XCTAssertNil(try queue.due(now: 0))
      XCTAssertEqual(try queue.due(now: Int64.max)?.failures, failure < 3 ? failure : nil)
    }
    XCTAssertThrowsError(try queue.staged("../foreign"))
  }

  func testArchivePublicationDoesNotOverwriteAnEditedUserFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let queue = AgentIOSOriginalPageArchiveStore(profile: "a", applicationSupport: root, documents: root,
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: Secrets(), keyAccount: "synthetic-archive"))
    _ = try queue.enqueue(source: Data("<p>Source</p>".utf8), url: "https://example.com", name: "article", language: "en", conversation: "c", turn: "t")
    let job = try XCTUnwrap(queue.due(now: 0)), data = Data("<p>Saved</p>".utf8)
    try queue.publish(job, data: data)
    let file = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "html" })
    let edited = Data("User replacement".utf8)
    try edited.write(to: file)
    XCTAssertThrowsError(try queue.publish(job, data: data))
    XCTAssertEqual(try Data(contentsOf: file), edited)
  }
}

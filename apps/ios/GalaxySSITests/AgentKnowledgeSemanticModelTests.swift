import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeSemanticModelTests: XCTestCase {
  func testPinnedEmbeddingArtifactMatchesAndroidContract() {
    XCTAssertEqual(AgentKnowledgeEmbeddingModel.id, "bge-small-zh-v1.5-q8_0")
    XCTAssertEqual(AgentKnowledgeEmbeddingModel.expectedBytes, 26_472_640)
    XCTAssertEqual(
      AgentKnowledgeEmbeddingModel.sha256,
      "5a88d266870fbd27c6f329df60de80e2d4cf3bbd5e6f080bd5c1b2e5abb12039"
    )
    XCTAssertEqual(AgentKnowledgeEmbeddingModel.dimensions, 512)
    XCTAssertEqual(AgentKnowledgeEmbeddingModel.contextTokens, 512)
    XCTAssertTrue(AgentKnowledgeEmbeddingModel.urls.allSatisfy {
      $0.absoluteString.contains(AgentKnowledgeEmbeddingModel.revision)
    })
  }

  func testRejectedImportDoesNotReplaceInstalledModel() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentKnowledgeSemanticModelTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = AgentKnowledgeSemanticModelStorage(rootURL: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let existing = Data("existing-model".utf8)
    try existing.write(to: storage.modelURL)
    let invalid = root.appendingPathComponent("invalid.gguf")
    try Data("invalid-model".utf8).write(to: invalid)

    XCTAssertThrowsError(try storage.importFile(invalid))
    XCTAssertEqual(try Data(contentsOf: storage.modelURL), existing)
  }

  func testSemanticStateRoundTripsRecoveryFields() throws {
    let state = AgentKnowledgeSemanticState(
      installed: true,
      enabled: true,
      phase: .indexing,
      downloadedBytes: 12,
      indexedChunks: 34,
      pendingDocuments: 5,
      enrollmentPending: true,
      countsPending: true,
      countsError: "count failure",
      downloadRequestId: "request",
      error: ""
    )

    XCTAssertEqual(try JSONDecoder().decode(
      AgentKnowledgeSemanticState.self,
      from: JSONEncoder().encode(state)
    ), state)
  }

  func testSemanticStateDecodesLegacyEnrollmentState() throws {
    let legacy = Data(#"{"installed":true,"enabled":true,"phase":"INDEXING","pendingDocuments":0}"#.utf8)
    let state = try JSONDecoder().decode(AgentKnowledgeSemanticState.self, from: legacy)

    XCTAssertFalse(state.enrollmentPending)
    XCTAssertFalse(state.countsPending)
    XCTAssertTrue(state.countsError.isEmpty)
    XCTAssertEqual(state.phase, .indexing)
  }
}

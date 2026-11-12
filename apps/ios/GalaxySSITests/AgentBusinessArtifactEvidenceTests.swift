import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentBusinessArtifactEvidenceTests: XCTestCase {
  private typealias Evidence = AgentBusinessArtifactEvidence
  private let expectation = Evidence.Expectation(extensions: ["docx", "png"], name_prefix: "A005-v02",
    editable_office: true, max_image_count: 1, expected_dimensions: [144, 144])

  @MainActor func testEveryDeclaredArtifactMustBeVerifiedAndSaved() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentDesktopArtifactStore(rootURL: root.appendingPathComponent("artifacts"),
      cipher: GalaxySSIAttachmentAtRestCipher(secrets: InMemorySecretStore()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let png = UIGraphicsImageRenderer(size: CGSize(width: 144, height: 144), format: format)
      .pngData { context in
        UIColor.black.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 144, height: 144))
      }
    let docx = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      entry("[Content_Types].xml", #"<Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"#),
      entry("_rels/.rels", #"<Relationships><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#),
      entry("word/document.xml", #"<w:document xmlns:w="urn:word"><w:body/></w:document>"#)
    ])
    let wordMIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    let document = try ingest(docx, name: "A005-v02.docx", type: .file, mime: wordMIME, store: store)
    let preview = try ingest(png, name: "A005-v02-preview.png", type: .image, mime: "image/png", store: store)
    let wrongVersion = try ingest(docx, name: "A005-v020.docx", type: .file, mime: wordMIME, store: store)
    let wrongContainer = try ingest(Data("not a document".utf8), name: "A005-v02-appendix.docx",
      type: .file, mime: wordMIME, store: store)
    let missing = AgentRichBlock(id: "missing", type: .file, title: "A005-v02-appendix.docx",
      uri: "galaxyssi-artifact://task/A005-v02-not-received.docx")
    func collect(_ blocks: [AgentRichBlock], turn: String = "turn", requestedTurn: String = "turn") throws
      -> Evidence.Assessment {
      let message = ChatMessage(contactId: "desktop", content: "Files", isMine: false, deliveryStatus: .delivered,
        conversationId: "fixture", turnId: turn, richOutputJson: AgentRichContentCodec.encode(blocks))
      return try Evidence.collect(expectation, message: message, conversation: "fixture", turn: requestedTurn,
        store: store, directory: root)
    }
    let complete = try collect([document, preview])
    XCTAssertTrue(complete.correct)
    XCTAssertTrue(complete.all_artifacts_verified == true)
    XCTAssertEqual(complete.artifacts?.filter(\.download_hash_matches).count, 2)
    XCTAssertFalse(complete.content_verified)
    XCTAssertFalse(complete.ui_open_save_verified)
    XCTAssertFalse(complete.preview_fidelity_verified)
    XCTAssertTrue(Evidence.recheck(expectation, original: try JSONEncoder().encode(complete)))
    XCTAssertFalse(try collect([document, preview, missing]).correct)
    XCTAssertFalse(try collect([document, preview, wrongVersion]).correct)
    XCTAssertFalse(try collect([document, preview, wrongContainer]).correct)
    XCTAssertFalse(try collect([preview], turn: "other").correct)
    let previewOnly = try collect([preview])
    XCTAssertFalse(previewOnly.correct)
    XCTAssertEqual(previewOnly.missing_extensions, ["docx"])
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["artifacts"])
  }

  func testOldPositiveFlagCannotHideIncompleteArtifactEvidence() throws {
    let check = Evidence.Expectation(extensions: ["pdf"], name_prefix: "A005-v02", preview_required: false)
    let required = ["received", "container_valid", "version_name_matches", "save_api_pass", "download_hash_matches"]
    var artifact: [String: Any] = Dictionary(uniqueKeysWithValues: required.map { ($0, true as Any) })
    artifact["extension"] = "pdf"
    artifact["type"] = "FILE"
    func legacy(_ items: [[String: Any]]) throws -> Data {
      try JSONSerialization.data(withJSONObject: ["correct": true, "all_artifacts_present": true,
        "all_artifacts_verified": true, "artifacts": items], options: [.sortedKeys])
    }
    XCTAssertTrue(Evidence.recheck(check, original: try legacy([artifact])))
    XCTAssertFalse(Evidence.recheck(check, original: try legacy([])))
    for flag in required {
      var bad = artifact
      bad[flag] = false
      XCTAssertFalse(Evidence.recheck(check, original: try legacy([artifact, bad])))
      bad[flag] = nil
      XCTAssertFalse(Evidence.recheck(check, original: try legacy([bad])))
    }
    XCTAssertFalse(Evidence.recheck(check, original: try legacy([artifact.merging(["extension": "docx"]) { _, new in new }])))
    let textOnly = Evidence.Expectation(text_only: true)
    XCTAssertTrue(Evidence.recheck(textOnly, original: Data(#"{"correct":true,"unexpected_file_count":0}"#.utf8)))
    XCTAssertFalse(Evidence.recheck(textOnly, original: Data(#"{"correct":true,"unexpected_file_count":1}"#.utf8)))
  }

  func testOptInRecheckRecordedDelivery() throws {
    let env = ProcessInfo.processInfo.environment
    guard let report = env["GALAXYSSI_BUSINESS_ASSESSMENT"] else {
      throw XCTSkip("Set an original synthetic assessment to opt in.")
    }
    let expected = try XCTUnwrap(env["GALAXYSSI_BUSINESS_ARTIFACT_EXPECTATION"])
    func read(_ path: String) throws -> Data {
      let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
      defer { try? file.close() }
      let bytes = try file.read(upToCount: 1_048_577) ?? Data()
      guard (1...1_048_576).contains(bytes.count) else { throw CocoaError(.fileReadCorruptFile) }
      return bytes
    }
    let frozen = try JSONDecoder().decode(Evidence.Expectation.self, from: read(expected))
    XCTAssertTrue(Evidence.recheck(frozen, original: try read(report)),
      "The original report does not prove complete artifact delivery.")
  }

  private func entry(_ path: String, _ text: String) -> AgentRuntimeProjectArchiveEntry {
    AgentRuntimeProjectArchiveEntry(path: path, data: Data(text.utf8))
  }

  private func ingest(_ bytes: Data, name: String, type: AgentRichBlockType, mime: String,
                      store: AgentDesktopArtifactStore) throws -> AgentRichBlock {
    let uri = "galaxyssi-artifact://task/" + name
    let digest = AgentBlobProtocol.sha256(bytes)
    let id = AgentDesktopArtifactStore.stableID(uri: uri, sha256: digest)
    try store.ingestBlobArtifact(manifest: ["artifact_id": id, "artifact_uri": uri, "task_id": "task",
      "name": name, "sha256": digest, "size_bytes": bytes.count, "mime_type": mime], plaintext: bytes)
    return AgentRichBlock(id: id, type: type, title: name, uri: uri, mimeType: mime,
      metadata: ["artifact_id": id, "sha256": digest])
  }
}

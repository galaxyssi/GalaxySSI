import XCTest
@testable import SignalASI

final class SignalASIAttachmentTests: XCTestCase {
  func testAttachmentDescriptorsMatchAndroidWireNames() {
    let attachment = SignalASIDraftAttachment(
      id: "att-1",
      displayName: "note.txt",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )

    let descriptors = SignalASIAttachmentPayloadBuilder.descriptors(for: [attachment])
    let item = descriptors.first

    XCTAssertEqual(item?["id"] as? String, "att-1")
    XCTAssertEqual(item?["name"] as? String, "note.txt")
    XCTAssertEqual(item?["mime_type"] as? String, "text/plain")
    XCTAssertEqual(item?["size"] as? Int, 5)
    XCTAssertEqual(item?["data_b64"] as? String, Data("hello".utf8).base64EncodedString())
    XCTAssertEqual(item?["transport_size"] as? Int, 5)
    XCTAssertEqual(item?["transport_lossless"] as? Bool, true)
    XCTAssertNotNil(item?["sha256"] as? String)
  }

  func testAttachmentDescriptorsRespectInlineBudget() {
    let large = SignalASIDraftAttachment(
      displayName: "large.bin",
      mimeType: "application/octet-stream",
      data: Data(repeating: 1, count: SignalASIAttachmentPayloadBuilder.maximumInlineBytes + 1)
    )

    let item = SignalASIAttachmentPayloadBuilder.descriptors(for: [large]).first

    XCTAssertNil(item?["data_b64"])
    XCTAssertEqual(item?["inline_status"] as? String, "metadata_only")
  }

  func testRejectsOversizedAndTooManyAttachments() {
    let oversized = SignalASIDraftAttachment(
      displayName: "huge.bin",
      mimeType: "application/octet-stream",
      data: Data(repeating: 0, count: SignalASIAttachmentPayloadBuilder.maximumAttachmentBytes + 1)
    )
    let small = SignalASIDraftAttachment(displayName: "a.txt", mimeType: "text/plain", data: Data("a".utf8))
    let existing = Array(repeating: small, count: SignalASIAttachmentPayloadBuilder.maximumAttachmentCount)

    XCTAssertFalse(SignalASIAttachmentPayloadBuilder.accepted(oversized, existing: []))
    XCTAssertFalse(SignalASIAttachmentPayloadBuilder.accepted(small, existing: existing))
  }

  func testSanitizesUnsafeNames() {
    XCTAssertEqual(SignalASIAttachmentPayloadBuilder.sanitizeName(" ..bad/name?.txt "), "bad_name_.txt")
    XCTAssertEqual(SignalASIAttachmentPayloadBuilder.sanitizeName(""), "attachment")
  }

  func testPhotoAttachmentDetectsPngMimeType() {
    let pngHeader = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
    let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
      data: pngHeader,
      suggestedName: "image.png"
    )

    XCTAssertEqual(attachment.mimeType, "image/png")
    XCTAssertTrue(attachment.isImage)
  }

  func testAnimatedImageTimingAddsDelayToZeroDurationGifFrames() {
    let gif = Data([
      0x47, 0x49, 0x46,
      0x38, 0x39, 0x61,
      0x21, 0xf9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    let normalized = AgentAnimatedImageTiming.normalizeZeroFrameDelays(gif)

    XCTAssertEqual(normalized[10], 8)
    XCTAssertEqual(normalized[11], 0)
  }

  func testAnimatedImageTimingPreservesExistingGifTiming() {
    let gif = Data([
      0x47, 0x49, 0x46,
      0x38, 0x39, 0x61,
      0x21, 0xf9, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00
    ])

    XCTAssertEqual(AgentAnimatedImageTiming.normalizeZeroFrameDelays(gif), gif)
  }

  func testPhotoAttachmentNormalizesGifTiming() {
    let gif = Data([
      0x47, 0x49, 0x46,
      0x38, 0x39, 0x61,
      0x21, 0xf9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
      data: gif,
      suggestedName: "loop.gif"
    )

    XCTAssertEqual(attachment.mimeType, "image/gif")
    XCTAssertEqual(attachment.data[10], 8)
  }

  func testAgentWorkspaceScopeMatchesAndroidStableIdsAndToolBinding() {
    let workspaceId = AgentWorkspaceScope.id(conversationId: "conversation-1")
    let scopedInput = AgentWorkspaceScope.bindToolInput(
      toolId: "signalasi.workspace.file.read_text",
      input: ["path": "note.txt"],
      workspaceId: workspaceId
    )
    let untouchedInput = AgentWorkspaceScope.bindToolInput(
      toolId: "signalasi.other.tool",
      input: ["path": "note.txt"],
      workspaceId: workspaceId
    )

    XCTAssertEqual(workspaceId, "b2fba169-5c07-35d8-b801-003335d67dc7")
    XCTAssertEqual(AgentWorkspaceScope.id(conversationId: " ", sessionId: "session-1"), AgentWorkspaceScope.id(conversationId: "session-1"))
    XCTAssertEqual(scopedInput["workspace_id"] as? String, workspaceId)
    XCTAssertEqual(scopedInput["path"] as? String, "note.txt")
    XCTAssertNil(untouchedInput["workspace_id"])
  }

  func testAgentAttachmentWorkspaceStagerWritesMetadataAndFiles() throws {
    let root = temporaryAttachmentRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let first = SignalASIDraftAttachment(
      displayName: " ..bad/name?.txt ",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )
    let second = SignalASIDraftAttachment(
      displayName: " ..bad/name?.txt ",
      mimeType: "text/plain",
      data: Data("world".utf8)
    )

    let staged = try AgentAttachmentWorkspaceStager.stage(
      conversationId: "conversation-1",
      turnId: "turn-1",
      attachments: [first, second],
      projectRoot: root
    )
    let workspace = root.appendingPathComponent(AgentWorkspaceScope.id(conversationId: "conversation-1"), isDirectory: true)
    let inputDirectory = workspace
      .appendingPathComponent("inputs", isDirectory: true)
      .appendingPathComponent("turn-1", isDirectory: true)
    let firstUrl = inputDirectory.appendingPathComponent("bad_name_.txt")
    let secondUrl = inputDirectory.appendingPathComponent("bad_name_-2.txt")
    let encoded = try JSONEncoder().encode(staged[0])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(staged.count, 2)
    XCTAssertEqual(staged[0].name, " ..bad/name?.txt ")
    XCTAssertEqual(staged[0].relativePath, "inputs/turn-1/bad_name_.txt")
    XCTAssertEqual(staged[0].mimeType, "text/plain")
    XCTAssertEqual(staged[0].sizeBytes, 5)
    XCTAssertEqual(staged[0].sha256, SignalASIAttachmentPayloadBuilder.sha256(first.data))
    XCTAssertEqual(staged[1].relativePath, "inputs/turn-1/bad_name_-2.txt")
    XCTAssertEqual(try Data(contentsOf: firstUrl), first.data)
    XCTAssertEqual(try Data(contentsOf: secondUrl), second.data)
    XCTAssertEqual(object["relative_path"] as? String, "inputs/turn-1/bad_name_.txt")
    XCTAssertEqual(object["mime_type"] as? String, "text/plain")
    XCTAssertEqual((object["size_bytes"] as? NSNumber)?.int64Value, 5)
  }

  func testAgentAttachmentWorkspaceStagerRejectsUnsafeTurnIds() throws {
    let root = temporaryAttachmentRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let attachment = SignalASIDraftAttachment(
      displayName: "note.txt",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )

    XCTAssertThrowsError(
      try AgentAttachmentWorkspaceStager.stage(
        conversationId: "conversation-1",
        turnId: "../turn",
        attachments: [attachment],
        projectRoot: root
      )
    ) { error in
      XCTAssertEqual(error as? AgentAttachmentWorkspaceStagingError, .invalidTurnId)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  private func temporaryAttachmentRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIAttachmentTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
  }
}

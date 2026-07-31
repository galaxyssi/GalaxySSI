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

  func testAgentAttachmentTransferProtocolMatchesAndroidRangesAndStableIdentity() throws {
    let routeId = try SignalASILinkProtocol.newRouteId()
    let scope = try AgentAttachmentTransferScope(
      contactId: "contact-1",
      desktopId: "desktop-1",
      clientRouteId: routeId,
      conversationId: "conversation-1",
      taskId: "task-1",
      turnId: "turn-1",
      clientMessageId: "client-message-1"
    )
    let digest = AgentAttachmentTransferProtocol.sha256(Data("content".utf8))
    let transferId = try AgentAttachmentTransferProtocol.transferId(
      scope: scope,
      attachmentId: "att-1",
      sha256: digest
    )
    let sameTransferId = try AgentAttachmentTransferProtocol.transferId(
      scope: scope,
      attachmentId: "att-1",
      sha256: digest
    )
    let nextTurnScope = try AgentAttachmentTransferScope(
      contactId: "contact-1",
      desktopId: "desktop-1",
      clientRouteId: routeId,
      conversationId: "conversation-1",
      taskId: "task-1",
      turnId: "turn-2"
    )

    XCTAssertEqual(transferId, sameTransferId)
    XCTAssertNotEqual(
      transferId,
      try AgentAttachmentTransferProtocol.transferId(
        scope: nextTurnScope,
        attachmentId: "att-1",
        sha256: digest
      )
    )
    XCTAssertEqual(transferId.count, 64)
    XCTAssertEqual(
      AgentAttachmentTransferProtocol.missingRanges([0, 1, 2, 5, 7, 8, 9]),
      [[0, 2], [5, 5], [7, 9]]
    )
    XCTAssertEqual(
      try AgentAttachmentTransferProtocol.expandMissingRanges([[0, 2], [5, 5], [7, 9]], chunkCount: 10),
      [0, 1, 2, 5, 7, 8, 9]
    )
    XCTAssertThrowsError(
      try AgentAttachmentTransferProtocol.expandMissingRanges([[0, 10]], chunkCount: 10)
    )
    XCTAssertEqual(
      AgentOutboundAttachmentTransferStore.maxAttachmentBytes,
      Int64(AgentOutboundAttachmentTransferStore.chunkBytes * AgentOutboundAttachmentTransferStore.maxChunks)
    )
  }

  func testAgentOutboundAttachmentTransferStorePreparesChunksAndAcknowledgesStoredReceipt() throws {
    let root = temporaryOutboundTransferRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let routeId = try SignalASILinkProtocol.newRouteId()
    let scope = try AgentAttachmentTransferScope(
      contactId: "contact-1",
      desktopId: "desktop-1",
      clientRouteId: routeId,
      conversationId: "conversation-1",
      taskId: "task-1",
      turnId: "turn-1",
      clientMessageId: "client-message-1"
    )
    let attachmentData = Data(repeating: 7, count: AgentOutboundAttachmentTransferStore.chunkBytes + 3)
    let attachment = SignalASIDraftAttachment(
      id: "att-1",
      displayName: " ..bad/name?.bin ",
      mimeType: "application/octet-stream",
      data: attachmentData
    )
    let store = AgentOutboundAttachmentTransferStore(rootURL: root)

    let prepared = try XCTUnwrap(
      try store.prepare(
        scope: scope,
        attachments: [attachment],
        mediaProfile: AgentMediaNetworkPolicy.profile(for: .normal)
      ).first
    )
    let descriptor = prepared.descriptor()
    let manifest = prepared.manifestPayload(resume: false, nowMillis: 123)
    let firstChunk = try prepared.chunkPayload(index: 0, nowMillis: 456)
    let secondChunk = try prepared.chunkPayload(index: 1, nowMillis: 789)

    XCTAssertEqual(prepared.chunkCount, 2)
    XCTAssertEqual(descriptor["id"] as? String, "att-1")
    XCTAssertEqual(descriptor["name"] as? String, "bad_name_.bin")
    XCTAssertEqual(descriptor["transport_status"] as? String, "chunked")
    XCTAssertEqual(descriptor["chunk_count"] as? Int, 2)
    XCTAssertEqual(descriptor["sha256"] as? String, prepared.sha256)
    XCTAssertEqual(manifest["type"] as? String, "input_attachment_manifest")
    XCTAssertEqual(manifest["resume"] as? Bool, false)
    XCTAssertEqual(manifest["transfer_id"] as? String, prepared.transferId)
    XCTAssertEqual(firstChunk["type"] as? String, "input_attachment_chunk")
    XCTAssertEqual(firstChunk["chunk_index"] as? Int, 0)
    XCTAssertEqual(firstChunk["chunk_size"] as? Int, AgentOutboundAttachmentTransferStore.chunkBytes)
    XCTAssertEqual(secondChunk["chunk_index"] as? Int, 1)
    XCTAssertEqual(secondChunk["chunk_size"] as? Int, 3)
    XCTAssertEqual(store.pending().map(\.transferId), [prepared.transferId])
    XCTAssertEqual(store.find(prepared.transferId)?.sha256, prepared.sha256)

    let receipt: [String: Any] = [
      "status": "stored",
      "transfer_id": prepared.transferId,
      "sha256": prepared.sha256,
      "client_route_id": scope.clientRouteId,
      "conversation_id": scope.conversationId,
      "task_id": scope.taskId,
      "turn_id": scope.turnId,
      "contact_id": scope.contactId,
      "source_message_id": "client-message-1"
    ]
    XCTAssertEqual(store.acknowledgeStored(payload: receipt), prepared.transferId)
    XCTAssertTrue(store.pending().isEmpty)
  }

  private func temporaryAttachmentRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIAttachmentTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
  }

  private func temporaryOutboundTransferRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIOutboundAttachmentTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("agent-link-outgoing-attachments-v1", isDirectory: true)
  }
}

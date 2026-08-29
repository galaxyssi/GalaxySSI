import XCTest
import UIKit
@testable import SignalASI

final class SignalASIAttachmentTests: XCTestCase {
  func testRuntimePlaintextCleanupRemovesOnlyKnownTransientFiles() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIRuntimePlaintextTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recordingDirectory = root.appendingPathComponent("peer-voice-recordings", isDirectory: true)
    let captureDirectory = root.appendingPathComponent("signalasi/visible-capture", isDirectory: true)
    try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
    let transientAudio = root.appendingPathComponent("voice_cmd_private.wav")
    let retained = root.appendingPathComponent("retained-model.bin")
    try Data([1]).write(to: transientAudio)
    try Data([2]).write(to: retained)

    SignalASIRuntimePlaintextProtection.clearKnownTemporaryFiles(roots: [root])

    XCTAssertFalse(FileManager.default.fileExists(atPath: recordingDirectory.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: captureDirectory.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: transientAudio.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
  }

  func testAttachmentAtRestLifecycleRemovesLegacyPlaintextRootsOnly() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASILegacyAttachmentTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("peer-incoming-attachments-v1", isDirectory: true)
    let encrypted = root.appendingPathComponent("peer-incoming-attachments-v2", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: encrypted, withIntermediateDirectories: true)
    try Data("plaintext".utf8).write(to: legacy.appendingPathComponent("data.bin"))
    try Data("ciphertext".utf8).write(to: encrypted.appendingPathComponent("data.saenc"))

    SignalASIAttachmentAtRestCipher.removeLegacyPlaintextRoots(roots: [root])

    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: encrypted.path))
  }

  func testDraftAttachmentWipeClearsPayloadAndSource() {
    var attachments = [SignalASIDraftAttachment(
      displayName: "private.txt",
      mimeType: "text/plain",
      data: Data("sensitive".utf8),
      sourceDescription: "file:///private.txt"
    )]

    attachments.wipeSensitive()

    XCTAssertTrue(attachments.isEmpty)
  }

  func testAttachmentAtRestCipherAuthenticatesPurposeAndRejectsTampering() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASICipherTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let file = root.appendingPathComponent("attachment.saenc")
    let plaintext = Data("private attachment".utf8)

    try cipher.write(plaintext, to: file, purpose: "test:attachment")

    XCTAssertTrue(cipher.isEncryptedFile(file))
    XCTAssertNotEqual(try Data(contentsOf: file), plaintext)
    XCTAssertEqual(try cipher.read(from: file, purpose: "test:attachment"), plaintext)
    XCTAssertThrowsError(try cipher.read(from: file, purpose: "test:other"))

    var tampered = try Data(contentsOf: file)
    tampered[tampered.index(before: tampered.endIndex)] ^= 0xff
    try tampered.write(to: file, options: [.atomic])
    XCTAssertThrowsError(try cipher.read(from: file, purpose: "test:attachment"))

    try cipher.write(plaintext, to: file, purpose: "test:attachment")
    let truncated = try Data(contentsOf: file).dropLast(12)
    try Data(truncated).write(to: file, options: [.atomic])
    XCTAssertThrowsError(try cipher.read(from: file, purpose: "test:attachment"))
  }

  func testAttachmentAtRestCipherMigratesLegacyPlaintext() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASICipherMigrationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let file = root.appendingPathComponent("legacy.bin")
    let plaintext = Data([9, 8, 7, 6])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try plaintext.write(to: file)

    XCTAssertEqual(
      try cipher.readMigratingPlaintext(from: file, purpose: "legacy:test"),
      plaintext
    )
    XCTAssertTrue(cipher.isEncryptedFile(file))
    XCTAssertEqual(try cipher.read(from: file, purpose: "legacy:test"), plaintext)
  }

  func testOutgoingPeerVoiceMovesFromCacheToDurableMessageStorage() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIPeerVoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("files/peer-message-attachments-v1", isDirectory: true)
    let cache = container.appendingPathComponent("cache", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let source = cache.appendingPathComponent("recording.m4a")
    let bytes = Data([1, 2, 3, 4])
    try bytes.write(to: source)
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = SignalASIPeerMessageAttachmentStore(
      rootURL: root,
      cacheRootURLs: [cache],
      cipher: cipher
    )

    let stored = try store.persistOutgoingVoice(
      sourceURL: source,
      messageID: "42",
      fileExtension: "m4a"
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(cipher.isEncryptedFile(stored))
    XCTAssertEqual(try cipher.read(from: stored, purpose: "peer-voice:42"), bytes)
    XCTAssertTrue(stored.path.replacingOccurrences(of: "\\", with: "/")
      .hasSuffix("peer-message-attachments-v1/outgoing/voice/msg_42.m4a.saenc"))
    let playback = try XCTUnwrap(store.resolveOutgoingVoice(displayName: "voice-42.m4a"))
    XCTAssertNotEqual(playback, stored)
    XCTAssertEqual(try Data(contentsOf: playback), bytes)
  }

  func testOutgoingOpusVoiceEncryptsDirectlyFromMemory() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIOpusVoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("files/peer-message-attachments-v2", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let bytes = Data("OggS-memory-only-opus".utf8)
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = SignalASIPeerMessageAttachmentStore(
      rootURL: root,
      cacheRootURLs: [],
      cipher: cipher
    )

    let stored = try store.persistOutgoingVoice(
      sourceURL: nil,
      fallbackData: bytes,
      messageID: "opus-42",
      fileExtension: "opus"
    )

    XCTAssertTrue(cipher.isEncryptedFile(stored))
    XCTAssertTrue(stored.lastPathComponent.hasSuffix("msg_opus-42.opus.saenc"))
    XCTAssertEqual(try cipher.read(from: stored, purpose: "peer-voice:opus-42"), bytes)
    let playback = try XCTUnwrap(store.resolveOutgoingVoice(displayName: "voice-opus-42.opus"))
    XCTAssertEqual(try Data(contentsOf: playback), bytes)
  }

  func testEncryptedPeerVoiceResolvesInMemoryWithoutPlaintextMaterialization() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIInMemoryVoiceTests-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("attachments", isDirectory: true)
    let cache = container.appendingPathComponent("cache", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let bytes = Data("OggS-encrypted-in-memory".utf8)
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = SignalASIPeerMessageAttachmentStore(
      rootURL: root,
      cacheRootURLs: [cache],
      cipher: cipher
    )
    let stored = try store.persistOutgoingVoice(
      sourceURL: nil,
      fallbackData: bytes,
      messageID: "memory-voice",
      fileExtension: "opus"
    )

    XCTAssertEqual(
      store.resolveAudioData(displayName: "voice-memory-voice.opus", sourceURL: stored),
      bytes
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    let storedFiles = try FileManager.default.subpathsOfDirectory(atPath: root.path)
    XCTAssertEqual(storedFiles.filter { $0.hasSuffix(".saenc") }.count, 1)
    for relativePath in storedFiles where !relativePath.hasSuffix(".saenc") {
      var isDirectory = ObjCBool(false)
      XCTAssertTrue(FileManager.default.fileExists(
        atPath: root.appendingPathComponent(relativePath).path,
        isDirectory: &isDirectory
      ))
      XCTAssertTrue(isDirectory.boolValue)
    }
  }

  func testInMemoryVoiceResolutionMigratesLegacyCacheToEncryptedStorage() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASILegacyMemoryVoiceTests-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("attachments", isDirectory: true)
    let cache = container.appendingPathComponent("cache", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let source = cache.appendingPathComponent("voice-legacy-memory.m4a")
    let bytes = Data("legacy-audio".utf8)
    try bytes.write(to: source)
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = SignalASIPeerMessageAttachmentStore(
      rootURL: root,
      cacheRootURLs: [cache],
      cipher: cipher
    )

    XCTAssertEqual(
      store.resolveAudioData(displayName: "voice-legacy-memory.m4a", sourceURL: source),
      bytes
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    let encrypted = root
      .appendingPathComponent("outgoing", isDirectory: true)
      .appendingPathComponent("voice", isDirectory: true)
      .appendingPathComponent("msg_legacy-memory.m4a.saenc")
    XCTAssertTrue(cipher.isEncryptedFile(encrypted))
    XCTAssertEqual(try cipher.read(from: encrypted, purpose: "peer-voice:legacy-memory"), bytes)
  }

  func testLegacyCachedPeerVoiceMigratesWhenResolvedForPlayback() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIPeerVoiceMigrationTests-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("files/peer-message-attachments-v1", isDirectory: true)
    let cache = container.appendingPathComponent("cache", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let source = cache.appendingPathComponent("voice-legacy-id.wav")
    try Data([5, 6, 7]).write(to: source)
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = SignalASIPeerMessageAttachmentStore(
      rootURL: root,
      cacheRootURLs: [cache],
      cipher: cipher
    )

    let resolved = try XCTUnwrap(
      store.resolveAudio(displayName: "voice-legacy-id.wav", sourceURL: source)
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(try Data(contentsOf: resolved), Data([5, 6, 7]))
    XCTAssertTrue(resolved.lastPathComponent.hasSuffix("voice-legacy-id.wav"))
  }

  func testCompletedIncomingAttachmentFollowsChatLifetime() {
    let month: TimeInterval = 30 * 24 * 60 * 60
    let now = Date(timeIntervalSince1970: month * 3)
    let old = Date(timeIntervalSince1970: 1)

    XCTAssertFalse(SignalASIPeerMessageAttachmentStore.shouldPruneIncoming(
      receivedAt: old,
      hasCompletedData: true,
      now: now,
      maximumAge: month
    ))
    XCTAssertTrue(SignalASIPeerMessageAttachmentStore.shouldPruneIncoming(
      receivedAt: old,
      hasCompletedData: false,
      now: now,
      maximumAge: month
    ))
  }

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
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = AgentOutboundAttachmentTransferStore(rootURL: root, cipher: cipher)

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
    let storedChunk = root
      .appendingPathComponent(prepared.transferId, isDirectory: true)
      .appendingPathComponent("chunks/chunk-000000.bin")
    XCTAssertTrue(cipher.isEncryptedFile(storedChunk))
    XCTAssertNotEqual(try Data(contentsOf: storedChunk), Data(attachmentData.prefix(
      AgentOutboundAttachmentTransferStore.chunkBytes
    )))
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

  func testPeerAttachmentTransferPreservesOriginalImageBytes() throws {
    let root = temporaryOutboundTransferRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let scope = try AgentAttachmentTransferScope(
      contactId: "contact-1",
      desktopId: "desktop-1",
      clientRouteId: try SignalASILinkProtocol.newRouteId(),
      conversationId: "peer:conversation-1",
      taskId: "peer:message-1",
      turnId: "peer-turn:message-1"
    )
    let original = Data((0..<(AgentOutboundAttachmentTransferStore.chunkBytes + 17)).map {
      UInt8($0 % 251)
    })
    let attachment = SignalASIDraftAttachment(
      id: "original-image",
      displayName: "original.png",
      mimeType: "image/png",
      data: original
    )
    let store = AgentOutboundAttachmentTransferStore(
      rootURL: root,
      cipher: SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    )

    let prepared = try XCTUnwrap(try store.prepare(
      scope: scope,
      attachments: [attachment],
      mediaProfile: AgentMediaNetworkPolicy.profile(for: .constrained),
      preserveOriginalBytes: true
    ).first)
    let reconstructed = try (0..<prepared.chunkCount).reduce(into: Data()) { data, index in
      let payload = try prepared.chunkPayload(index: index)
      data.append(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(payload["data_b64"] as? String))))
    }

    XCTAssertEqual(prepared.transportProfile, "peer-original")
    XCTAssertEqual(prepared.sizeBytes, Int64(original.count))
    XCTAssertEqual(prepared.originalSizeBytes, Int64(original.count))
    XCTAssertFalse(prepared.requiresValidatedNetwork)
    XCTAssertEqual(reconstructed, original)
  }

  func testPeerImageTransferProgressUpdatesRichContentMetadata() throws {
    let block = AgentRichBlock(
      id: "image-1",
      type: .image,
      title: "photo.png",
      mimeType: "image/png",
      metadata: [:]
    )
    let update = try XCTUnwrap(SignalASIPeerAttachmentTransferUpdate(payload: [
      "transfer_id": String(repeating: "a", count: 64),
      "source_message_id": UUID().uuidString,
      "attachment_ordinal": 0,
      "name": "photo.png",
      "mime_type": "image/png",
      "size_bytes": 1_000,
      "sha256": String(repeating: "b", count: 64),
      "progress": 42,
      "state": SignalASIPeerAttachmentTransferProgress.downloading
    ]))

    let richOutput = SignalASIPeerAttachmentTransferProgress.applying(
      update,
      to: AgentRichContentCodec.encode([block])
    )
    let updated = try XCTUnwrap(AgentRichContentCodec.decode(richOutput).first)

    XCTAssertEqual(updated.metadata["transfer_id"], update.transferId)
    XCTAssertEqual(updated.metadata["transfer_progress"], "42")
    XCTAssertEqual(
      SignalASIPeerAttachmentTransferProgress.activeProgress(metadata: updated.metadata),
      42
    )
    XCTAssertEqual(
      SignalASIPeerAttachmentTransferProgress.percent(receivedBytes: 999, sizeBytes: 1_000),
      99
    )
    let second = try XCTUnwrap(SignalASIPeerAttachmentTransferUpdate(payload: [
      "transfer_id": String(repeating: "c", count: 64),
      "source_message_id": update.sourceMessageId,
      "attachment_ordinal": 1,
      "name": "second.png",
      "mime_type": "image/png",
      "size_bytes": 2_000,
      "sha256": String(repeating: "d", count: 64),
      "progress": 10,
      "state": SignalASIPeerAttachmentTransferProgress.downloading
    ]))
    XCTAssertEqual(
      AgentRichContentCodec.decode(
        SignalASIPeerAttachmentTransferProgress.applying(second, to: richOutput)
      ).count,
      2
    )
  }

  func testPeerImageThumbnailIdentityIgnoresProgressAndEncodingIsBounded() throws {
    var block = AgentRichBlock(
      id: "image-1",
      type: .image,
      title: "photo.png",
      uri: "file:///private/photo.saenc",
      mimeType: "image/png",
      metadata: [
        "transfer_id": String(repeating: "a", count: 64),
        "transfer_progress": "10",
        "transfer_state": SignalASIPeerAttachmentTransferProgress.downloading
      ]
    )
    let identity = SignalASIPeerImageThumbnailPolicy.cacheIdentity(block)
    block.metadata["transfer_progress"] = "100"
    block.metadata["transfer_state"] = SignalASIPeerAttachmentTransferProgress.complete
    XCTAssertEqual(SignalASIPeerImageThumbnailPolicy.cacheIdentity(block), identity)

    let source = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
    }
    let png = try XCTUnwrap(source.pngData())
    let thumbnail = try XCTUnwrap(
      SignalASIPeerImageThumbnailRepository.encodeThumbnail(png, maxPixelSize: 512)
    )
    XCTAssertLessThanOrEqual(thumbnail.count, 100_000)
    XCTAssertTrue(SignalASIImageResourceDecoder.canDecode(thumbnail))
  }

  func testIncomingPeerAttachmentAssemblesResumesAndResolvesDurably() throws {
    let root = temporaryIncomingTransferRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let routes = SignalASILinkRoutes(
      clientRouteId: String(repeating: "c", count: 22),
      linkSecret: String(repeating: "d", count: 43),
      localFingerprint: String(repeating: "b", count: 64),
      remoteFingerprint: String(repeating: "a", count: 64)
    )
    let localId = "signalasi:local"
    let remoteId = "signalasi:remote"
    let bytes = Data("verified phone image".utf8)
    let digest = AgentAttachmentTransferProtocol.sha256(bytes)
    let manifest: [String: Any] = [
      "type": "input_attachment_manifest",
      "transfer_id": digest,
      "sha256": digest,
      "size_bytes": bytes.count,
      "chunk_count": 1,
      "client_route_id": routes.clientRouteId,
      "contact_id": localId,
      "conversation_id": "peer:conversation",
      "task_id": "peer:task",
      "turn_id": "peer:turn",
      "client_message_id": "client-message-1",
      "name": "photo.png",
      "mime_type": "image/png",
      "resume": true
    ]
    let cipher = SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    let store = AgentIncomingAttachmentTransferStore(rootURL: root, cipher: cipher)

    let missing = try XCTUnwrap(
      store.ingest(
        payload: manifest,
        sourceId: remoteId,
        localSignalASIId: localId,
        routes: routes
      )
    )
    XCTAssertEqual(missing["status"] as? String, "missing")
    XCTAssertEqual(missing["missing_ranges"] as? [[Int]], [[0, 0]])
    let pendingDownload = try XCTUnwrap(store.pendingDownloads().first)
    XCTAssertEqual(pendingDownload.transferId, digest)
    XCTAssertEqual(pendingDownload.sourceId, remoteId)
    let resumeReceipt = try XCTUnwrap(store.resumeReceipt(for: pendingDownload))
    XCTAssertEqual(resumeReceipt["status"] as? String, "missing")
    XCTAssertEqual(resumeReceipt["missing_ranges"] as? [[Int]], [[0, 0]])
    XCTAssertEqual(resumeReceipt["resume"] as? Bool, true)
    let pendingProgress = try XCTUnwrap(store.progressEvent(
      payload: manifest,
      sourceId: remoteId,
      localSignalASIId: localId
    ))
    XCTAssertEqual(pendingProgress["progress"] as? Int, 0)
    XCTAssertEqual(
      pendingProgress["state"] as? String,
      SignalASIPeerAttachmentTransferProgress.downloading
    )

    var chunk = manifest
    chunk["type"] = "input_attachment_chunk"
    chunk["chunk_index"] = 0
    chunk["chunk_size"] = bytes.count
    chunk["chunk_sha256"] = digest
    chunk["data_b64"] = bytes.base64EncodedString()
    let stored = try XCTUnwrap(
      store.ingest(
        payload: chunk,
        sourceId: remoteId,
        localSignalASIId: localId,
        routes: routes
      )
    )
    XCTAssertEqual(stored["status"] as? String, "stored")
    XCTAssertEqual(stored["source_message_id"] as? String, "client-message-1")
    let completedProgress = try XCTUnwrap(store.progressEvent(
      payload: chunk,
      sourceId: remoteId,
      localSignalASIId: localId
    ))
    XCTAssertEqual(completedProgress["progress"] as? Int, 100)
    XCTAssertEqual(
      completedProgress["state"] as? String,
      SignalASIPeerAttachmentTransferProgress.complete
    )
    XCTAssertTrue(store.pendingDownloads().isEmpty)

    let descriptor: [String: Any] = [
      "transfer_id": digest,
      "sha256": digest,
      "size": bytes.count,
      "name": "ignored.png",
      "mime_type": "image/png"
    ]
    let resolved = try XCTUnwrap(
      store.resolveMessageAttachments(
        sourceId: remoteId,
        payload: ["attachments": [descriptor]]
      )?.first
    )
    let fileURL = try XCTUnwrap(URL(string: resolved["uri"] as? String ?? ""))
    XCTAssertTrue(cipher.isEncryptedFile(fileURL))
    XCTAssertEqual(resolved["storage"] as? String, "attachment_aes_256_gcm")
    XCTAssertEqual(
      try cipher.read(from: fileURL, purpose: "incoming-data:\(digest)"),
      bytes
    )

    let reopened = AgentIncomingAttachmentTransferStore(rootURL: root, cipher: cipher)
    XCTAssertNotNil(
      reopened.resolveMessageAttachments(
        sourceId: remoteId,
        payload: ["attachments": [descriptor]]
      )
    )
  }

  func testIncomingPeerAttachmentRejectsWrongRouteAndTamperedChunk() throws {
    let root = temporaryIncomingTransferRoot()
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let routes = SignalASILinkRoutes(
      clientRouteId: String(repeating: "e", count: 22),
      linkSecret: String(repeating: "f", count: 43),
      localFingerprint: String(repeating: "1", count: 64),
      remoteFingerprint: String(repeating: "2", count: 64)
    )
    let bytes = Data("trusted".utf8)
    let digest = AgentAttachmentTransferProtocol.sha256(bytes)
    var manifest: [String: Any] = [
      "type": "input_attachment_manifest",
      "transfer_id": digest,
      "sha256": digest,
      "size_bytes": bytes.count,
      "chunk_count": 1,
      "client_route_id": "wrong-route",
      "contact_id": "signalasi:local",
      "conversation_id": "peer:conversation",
      "task_id": "peer:task",
      "turn_id": "peer:turn",
      "name": "document.bin",
      "mime_type": "application/octet-stream"
    ]
    let store = AgentIncomingAttachmentTransferStore(
      rootURL: root,
      cipher: SignalASIAttachmentAtRestCipher(secrets: InMemorySecretStore())
    )
    XCTAssertNil(
      store.ingest(
        payload: manifest,
        sourceId: "signalasi:remote",
        localSignalASIId: "signalasi:local",
        routes: routes
      )
    )

    manifest["client_route_id"] = routes.clientRouteId
    XCTAssertNil(
      store.ingest(
        payload: manifest,
        sourceId: "signalasi:remote",
        localSignalASIId: "signalasi:local",
        routes: routes
      )
    )
    var chunk = manifest
    chunk["type"] = "input_attachment_chunk"
    chunk["chunk_index"] = 0
    chunk["chunk_size"] = bytes.count
    chunk["chunk_sha256"] = String(repeating: "0", count: 64)
    chunk["data_b64"] = bytes.base64EncodedString()
    XCTAssertNil(
      store.ingest(
        payload: chunk,
        sourceId: "signalasi:remote",
        localSignalASIId: "signalasi:local",
        routes: routes
      )
    )
    XCTAssertNil(
      store.resolveMessageAttachments(
        sourceId: "signalasi:remote",
        payload: [
          "attachments": [[
            "transfer_id": digest,
            "sha256": digest,
            "size": bytes.count
          ]]
        ]
      )
    )
  }

  func testDeletingPeerAttachmentRemovesOnlyPrivateTransferCopies() throws {
    let root = temporaryIncomingTransferRoot()
    let container = root.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: container) }
    let digest = String(repeating: "a", count: 64)
    let transferDirectory = root.appendingPathComponent(digest, isDirectory: true)
    let privateFile = transferDirectory.appendingPathComponent("data.saenc")
    let exportedFile = container.appendingPathComponent("exported.bin")
    let modelFile = container.appendingPathComponent("local-model.gguf")
    try FileManager.default.createDirectory(at: transferDirectory, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: privateFile)
    try Data("exported".utf8).write(to: exportedFile)
    try Data("model".utf8).write(to: modelFile)
    let blocks = [
      AgentRichBlock(
        id: "private",
        type: .file,
        title: "private.bin",
        uri: privateFile.absoluteString,
        metadata: ["transfer_id": digest]
      ),
      AgentRichBlock(
        id: "exported",
        type: .file,
        title: "exported.bin",
        uri: exportedFile.absoluteString
      ),
      AgentRichBlock(
        id: "model",
        type: .file,
        title: "local-model.gguf",
        uri: modelFile.absoluteString
      )
    ]

    AgentIncomingAttachmentTransferStore(rootURL: root).deleteLocalCopies(for: blocks)

    XCTAssertFalse(FileManager.default.fileExists(atPath: transferDirectory.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportedFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelFile.path))
  }

  func testPeerMessageCopyFallsBackToAttachmentNames() {
    let blocks = [
      AgentRichBlock(id: "one", type: .image, title: "photo.png"),
      AgentRichBlock(id: "two", type: .file, title: "report.pdf")
    ]
    let message = ChatMessage(
      contactId: "friend",
      content: "",
      isMine: false,
      richOutputJson: AgentRichContentCodec.encode(blocks)
    )

    XCTAssertEqual(SignalASIMessageActionPolicy.copyText(for: message), "photo.png\nreport.pdf")
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

  private func temporaryIncomingTransferRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIIncomingAttachmentTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("peer-incoming-attachments-v1", isDirectory: true)
  }
}

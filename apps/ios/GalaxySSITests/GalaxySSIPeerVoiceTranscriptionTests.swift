import XCTest
@testable import GalaxySSI

final class GalaxySSIPeerVoiceTranscriptionTests: XCTestCase {
  func testPeerSelectionResolvesExactMessageAfterHistoryChanges() {
    let original = ChatMessage(contactId: "peer", content: "original", isMine: false)
    let inserted = ChatMessage(contactId: "peer", content: "newer", isMine: true)
    let target = GalaxySSIPeerMessageActionTarget(scope: "profile:peer", contactID: "peer", messageID: original.id)
    var history = [original, inserted]
    func lookup(_ id: UUID, _ contact: String) -> ChatMessage? {
      history.first { $0.id == id && $0.contactId == contact }
    }
    history.reverse()
    XCTAssertEqual(target.resolve(scope: "profile:peer", contactID: "peer", lookup: lookup), original)
    XCTAssertNil(target.resolve(scope: "other-profile:peer", contactID: "peer", lookup: lookup))
    XCTAssertNil(target.resolve(scope: "profile:peer", contactID: "other-peer", lookup: lookup))
    XCTAssertNil(target.resolve(scope: "profile:peer", contactID: "peer") { _, _ in inserted })
    history.removeAll { $0.id == original.id }
    XCTAssertNil(target.resolve(scope: "profile:peer", contactID: "peer", lookup: lookup))
  }

  func testVoiceMessagesOfferTranscriptionAndDeleteOnly() {
    let message = peerVoiceMessage()

    XCTAssertNotNil(GalaxySSIPeerMessageActionPolicy.voiceAttachment(in: message))
    XCTAssertEqual(
      GalaxySSIPeerMessageActionPolicy.actions(for: message),
      [.transcribe, .delete]
    )
  }

  func testOrdinaryMessagesKeepCopyAndDelete() {
    let message = ChatMessage(contactId: "peer", content: "hello", isMine: false)

    XCTAssertEqual(
      GalaxySSIPeerMessageActionPolicy.actions(for: message),
      [.copy, .delete]
    )
  }

  func testPeerTranscriptionReturnsTextWithoutCommandExecution() {
    XCTAssertTrue(GalaxySSIPeerMessageActionPolicy.returnsTextWithoutCommandExecution())
  }

  func testVoiceTranscriptPersistsAcrossMessageCoding() throws {
    var message = peerVoiceMessage()
    message.voiceTranscript = "\u{672c}\u{5730}\u{8f6c}\u{5199}\u{7ed3}\u{679c}"

    let restored = try JSONDecoder().decode(
      ChatMessage.self,
      from: JSONEncoder().encode(message)
    )

    XCTAssertEqual(restored.voiceTranscript, "\u{672c}\u{5730}\u{8f6c}\u{5199}\u{7ed3}\u{679c}")
  }

  func testPcmWaveDecodesAndResamplesEntirelyInMemory() throws {
    let source = (0..<48_000).map { index in
      Int16((sin(Double(index) * 2 * .pi * 220 / 48_000) * 8_000).rounded())
    }
    let wave = GalaxySSIPeerVoiceOpusCodec.pcmWave(source)

    var decoded = try GalaxySSIPeerVoiceInMemoryDecoder.decode(
      wave,
      fileExtension: "wav",
      mimeType: "audio/wav"
    )
    defer { decoded.wipeSensitive() }

    XCTAssertEqual(decoded.sampleRateHz, 16_000)
    XCTAssertEqual(decoded.sourceSampleRateHz, 48_000)
    XCTAssertEqual(decoded.channelCount, 1)
    XCTAssertEqual(decoded.samples.count, 16_000)
  }

  private func peerVoiceMessage() -> ChatMessage {
    let block = AgentRichBlock(
      id: "voice",
      type: .audio,
      title: "voice-test.opus",
      uri: "file:///tmp/voice-test.opus.sasi",
      mimeType: "audio/ogg; codecs=opus",
      metadata: [
        "source": "peer_message",
        "storage": "attachment_aes_256_gcm",
        "encryption_purpose": "peer-test",
        "display_extension": "opus",
      ]
    )
    return ChatMessage(
      contactId: "peer",
      content: "",
      isMine: false,
      richOutputJson: AgentRichContentCodec.encode([block])
    )
  }
}

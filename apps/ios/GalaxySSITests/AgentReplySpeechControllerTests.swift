import XCTest
import UIKit
@testable import GalaxySSI

final class AgentReplySpeechControllerTests: XCTestCase {
  func testCompletedReplySelectionUsesStoredTextAndChecksBothOwnershipIDs() throws {
    let message = ChatMessage(contactId: "hermes", content: "Repeat. Repeat. Final.", isMine: false,
                              conversationId: "thread", remoteMessageId: "assistant-final:turn")
    let paragraph = AgentReplyParagraphSpeechSelection(paragraph: "Repeat.", sourceText: message.content,
                                                      startOffset: "Repeat. ".count)
    let selection = try XCTUnwrap(AgentCompletedReplyPlaybackSelection(message: message, paragraph: paragraph))
    XCTAssertEqual(selection.resolve(message), "Repeat. Final.")
    var other = message
    other.conversationId = "other-thread"
    XCTAssertNil(selection.resolve(other))
    other = message
    other.id = UUID()
    XCTAssertNil(selection.resolve(other))
    other = message
    other.remoteMessageId = "agent-stream-1"
    XCTAssertNil(selection.resolve(other))
    XCTAssertNil(AgentCompletedReplyPlaybackSelection(message: other))
    let foreignText = AgentReplyParagraphSpeechSelection(paragraph: "Untrusted", sourceText: "Untrusted", startOffset: 0)
    XCTAssertNil(AgentCompletedReplyPlaybackSelection(message: message, paragraph: foreignText))
  }

  @MainActor
  func testProgressivePauseAndResumeAreScopedToAnOpenPlaybackSession() {
    let service = VoiceProgressiveReplySpeechService()
    XCTAssertFalse(service.pauseProgressive())
    let request = VoiceReplyPlaybackRequest(sessionId: "reply", utteranceId: "utterance", text: "",
      language: "en-US", providerId: VoiceTTSProvider.system.rawValue, runtimeChannel: .androidSystemTTS)
    service.beginProgressive(request, onPlaybackStarted: { _ in }, onDone: { _, _, _ in })
    XCTAssertTrue(service.pauseProgressive())
    XCTAssertFalse(service.pauseProgressive())
    XCTAssertTrue(service.resumeProgressive())
    XCTAssertFalse(service.resumeProgressive())
    XCTAssertTrue(service.stop())
    XCTAssertFalse(service.resumeProgressive())
  }

  func testReplyStartsMutedAndEnablingReadsAvailableText() {
    let controller = AgentReplySpeechController()
    let target = makeTarget(responseId: "turn-1", entryId: "stream-1", text: "First segment.")

    XCTAssertEqual(controller.observe(target).appendedText, "")
    XCTAssertFalse(controller.isEnabled(target))

    let command = controller.toggle(target)
    XCTAssertFalse(command.beginSessionId.isEmpty)
    XCTAssertEqual(command.appendedText, "First segment.")
    XCTAssertFalse(command.scheduleCommitSessionId.isEmpty)
    XCTAssertTrue(controller.isEnabled(target))
  }

  func testEnabledReplyReadsOnlyNewTextAndFinishesFinalEntry() {
    let controller = AgentReplySpeechController()
    let first = makeTarget(responseId: "turn-1", entryId: "stream-1", text: "First.")
    controller.observe(first)
    controller.toggle(first)

    var second = first
    second.text = "First. Second."
    XCTAssertEqual(controller.observe(second).appendedText, " Second.")
    XCTAssertEqual(controller.observe(second).appendedText, "")

    var final = second
    final.entryId = "final-1"
    final.complete = true
    let completion = controller.observe(final)
    XCTAssertFalse(completion.finishSessionId.isEmpty)
    XCTAssertEqual(completion.changedEntryIds, ["stream-1", "final-1"])
  }

  func testNewReplyCancelsPlaybackAndReturnsToMuted() {
    let controller = AgentReplySpeechController()
    let first = makeTarget(responseId: "turn-1", entryId: "stream-1", text: "First reply.")
    controller.observe(first)
    let started = controller.toggle(first)

    let second = makeTarget(responseId: "turn-2", entryId: "stream-2", text: "New reply.")
    let command = controller.observe(second)

    XCTAssertEqual(command.cancelSessionId, started.beginSessionId)
    XCTAssertFalse(controller.isEnabled(second))
    XCTAssertEqual(command.changedEntryIds, ["stream-1", "stream-2"])
  }

  func testParagraphReadingStartsFromSelectedParagraph() {
    let controller = AgentReplySpeechController()
    let target = makeTarget(
      responseId: "turn-1",
      entryId: "final-1",
      text: "Earlier paragraph.\n\nRead from here.",
      complete: true
    )
    controller.observe(target)

    let offset = target.text.distance(
      from: target.text.startIndex,
      to: target.text.range(of: "Read from here.")!.lowerBound
    )
    let command = controller.readFromParagraph(
      target,
      paragraph: "Read from here.",
      sourceText: target.text,
      startOffset: offset
    )

    XCTAssertFalse(command.beginSessionId.isEmpty)
    XCTAssertFalse(command.finishSessionId.isEmpty)
    XCTAssertEqual(command.appendedText, "Read from here.")
    XCTAssertTrue(controller.isEnabled(target))
  }

  func testRestartingParagraphUsesANewGenerationScopedSession() {
    let controller = AgentReplySpeechController()
    let target = makeTarget(
      responseId: "turn-1",
      entryId: "final-1",
      text: "First.\n\nSecond.",
      complete: true
    )
    controller.observe(target)
    let first = controller.readFromParagraph(target, paragraph: "First.")
    let second = controller.readFromParagraph(target, paragraph: "Second.")

    XCTAssertEqual(second.cancelSessionId, first.beginSessionId)
    XCTAssertNotEqual(second.beginSessionId, first.beginSessionId)
    XCTAssertEqual(second.appendedText, "Second.")
  }

  func testParagraphReadingContinuesThroughTheRemainingReply() {
    let controller = AgentReplySpeechController()
    let target = makeTarget(
      responseId: "turn-1",
      entryId: "final-1",
      text: "First.\n\nSecond.\n\nThird.",
      complete: true
    )
    controller.observe(target)
    let start = target.text.distance(
      from: target.text.startIndex,
      to: target.text.range(of: "Second.")!.lowerBound
    )

    let command = controller.readFromParagraph(
      target,
      paragraph: "Second.",
      sourceText: target.text,
      startOffset: start
    )

    XCTAssertEqual(command.appendedText, "Second.\n\nThird.")
  }

  func testParagraphOffsetDisambiguatesRepeatedText() {
    let controller = AgentReplySpeechController()
    let text = "Repeated.\n\nMiddle.\n\nRepeated.\n\nEnding."
    let target = makeTarget(responseId: "turn-1", entryId: "final-1", text: text, complete: true)
    controller.observe(target)
    let range = text.range(of: "Repeated.", options: .backwards)!
    let start = text.distance(from: text.startIndex, to: range.lowerBound)

    let command = controller.readFromParagraph(
      target,
      paragraph: "Repeated.",
      sourceText: text,
      startOffset: start
    )

    XCTAssertEqual(command.appendedText, "Repeated.\n\nEnding.")
  }

  func testStoppingPlaybackCancelsTheActiveSession() {
    let controller = AgentReplySpeechController()
    let target = makeTarget(responseId: "turn-1", entryId: "final-1", text: "Read this.", complete: true)
    controller.observe(target)
    let started = controller.toggle(target)

    let stopped = controller.stop()

    XCTAssertEqual(stopped.cancelSessionId, started.beginSessionId)
    XCTAssertEqual(stopped.changedEntryIds, [target.entryId])
    XCTAssertFalse(controller.isPlaying)
    XCTAssertFalse(controller.isEnabled(target))
  }

  func testPresentationChoosesLatestSpeakableAssistantReply() {
    let older = ChatMessage(
      contactId: "hermes",
      content: "Older reply",
      isMine: false,
      turnId: "turn-1"
    )
    let user = ChatMessage(
      contactId: "hermes",
      content: "New question",
      isMine: true,
      turnId: "turn-2"
    )
    let latest = ChatMessage(
      contactId: "hermes",
      content: "Latest reply",
      isMine: false,
      turnId: "turn-2"
    )

    let target = AgentReplySpeechPresentationPolicy.latestTarget([older, user, latest])

    XCTAssertEqual(target?.entryId, latest.id.uuidString.lowercased())
    XCTAssertEqual(target?.responseId, "turn-2")
  }

  func testPresentationExcludesApprovalAndRecoveryRows() {
    let approval = ChatMessage(
      contactId: "hermes",
      content: "Approval required",
      isMine: false,
      remoteMessageId: "approval:123"
    )
    let recovery = ChatMessage(
      contactId: "hermes",
      content: "Recovered state",
      isMine: false,
      remoteMessageId: "agent-recovery:123"
    )

    XCTAssertNil(AgentReplySpeechPresentationPolicy.target(approval))
    XCTAssertNil(AgentReplySpeechPresentationPolicy.target(recovery))
  }

  func testEdgeSpeechPrefetchKeepsTwoUpcomingSegmentsPrepared() {
    XCTAssertEqual(
      VoiceReplySpeechPrefetchPolicy.candidates(
        queuedIndices: [1, 2, 3],
        inFlightIndices: [],
        preparedIndices: [],
        failedIndices: []
      ),
      [1, 2]
    )
    XCTAssertEqual(
      VoiceReplySpeechPrefetchPolicy.candidates(
        queuedIndices: [1, 2, 3],
        inFlightIndices: [1],
        preparedIndices: [],
        failedIndices: []
      ),
      [2]
    )
  }

  func testEdgeSpeechPrefetchDoesNotRetryPreparedOrFailedSegments() {
    XCTAssertEqual(
      VoiceReplySpeechPrefetchPolicy.candidates(
        queuedIndices: [2, 3, 4],
        inFlightIndices: [],
        preparedIndices: [2],
        failedIndices: [3]
      ),
      []
    )
    XCTAssertEqual(
      VoiceReplySpeechPrefetchPolicy.candidates(
        queuedIndices: [3, 4, 5],
        inFlightIndices: [],
        preparedIndices: [1],
        failedIndices: []
      ),
      [3, 4]
    )
  }

  func testVoiceCallReplySessionsUseIndependentPrefix() {
    let controller = AgentReplySpeechController(sessionPrefix: "voice-call")
    let target = makeTarget(responseId: "response", entryId: "entry", text: "Hello")

    let command = controller.toggle(target)

    XCTAssertTrue(command.beginSessionId.hasPrefix("voice-call-"))
  }

  private func makeTarget(
    responseId: String,
    entryId: String,
    text: String,
    complete: Bool = false
  ) -> AgentReplySpeechTarget {
    AgentReplySpeechTarget(
      responseId: responseId,
      entryId: entryId,
      text: text,
      complete: complete
    )
  }
}

extension AgentReplySpeechControllerTests {
  func testNarrationUsesRenderedProseAcrossAnOversizedFencedAnimationAndMedia() throws {
    let animation = String(repeating: "ANIMATION_PROGRAM ", count: 3_000)
    let content = """
      First paragraph.

      ````html
      \(animation)
      ```
      Still code.
      ````

      ![Visual](https://example.org/render.png)

      Last paragraph.
      """
    let plain = ChatMessage(contactId: "hermes", content: content, isMine: false)
    XCTAssertEqual(AgentReplySpeechPresentationPolicy.speakableText(plain), "First paragraph.\n\nLast paragraph.")
    let encoded = AgentRichContentCodec.encode([.init(id: "rich", type: .text, text: content)])
    let rich = ChatMessage(contactId: "hermes", content: "Connector fallback", isMine: false, richOutputJson: encoded)
    let blocks = AgentRichContentCodec.presentationBlocks(content: rich.content, richOutputJson: rich.richOutputJson)
    XCTAssertEqual(blocks.map(\.type), [.text, .code, .image, .text])
    XCTAssertEqual(AgentReplySpeechPresentationPolicy.speakableText(rich), "First paragraph.\n\nLast paragraph.")
    let last = try XCTUnwrap(blocks.last)
    let selected = try XCTUnwrap(AgentReplySpeechPresentationPolicy.Prose(blocks).selection(for: last))
    XCTAssertEqual(String(selected.sourceText.dropFirst(selected.startOffset)), "Last paragraph.")
  }

  func testProseOffsetsFollowRepeatedParagraphsAndRenderedListRows() throws {
    let blocks: [AgentRichBlock] = [
      .init(id: "before", type: .text, text: "Repeated."),
      .init(id: "media", type: .html, text: "<canvas></canvas>"),
      .init(id: "after", type: .text, text: "**Repeated.**"),
      .init(id: "list", type: .list, rows: [["checked", "First item."], ["bullet", "[Second item.](https://example.org)"]]),
      .init(id: "divider", type: .divider),
      .init(id: "end", type: .quote, text: "Finish.")
    ]
    let prose = AgentReplySpeechPresentationPolicy.Prose(blocks)
    XCTAssertEqual(prose.text, "Repeated.\n\nRepeated.\n\nFirst item.\nSecond item.\n\nFinish.")
    let repeated = try XCTUnwrap(prose.selection(for: blocks[2]))
    XCTAssertEqual(repeated.startOffset, "Repeated.\n\n".count)
    let row = try XCTUnwrap(prose.selection(for: blocks[3], listRow: 1))
    XCTAssertEqual(row.paragraph, "Second item.")
    let target = makeTarget(responseId: "turn", entryId: "reply", text: prose.text, complete: true)
    XCTAssertEqual(AgentReplySpeechController().readFromParagraph(target, paragraph: row.paragraph,
      sourceText: row.sourceText, startOffset: row.startOffset).appendedText, "Second item.\n\nFinish.")
  }

  func testNarrationPreservesPlainActionCardFallbackButDoesNotReadCodeOnlyReplies() {
    let action = AgentRichContentCodec.encode([.init(id: "card", type: .actions, title: "Review")])
    let ordinary = ChatMessage(contactId: "hermes", content: "Review the meeting details.", isMine: false, richOutputJson: action)
    XCTAssertEqual(AgentReplySpeechPresentationPolicy.speakableText(ordinary), "Review the meeting details.")
    let code = ChatMessage(contactId: "hermes", content: "~~~javascript\nalert(1)\n~~~", isMine: false)
    XCTAssertNil(AgentReplySpeechPresentationPolicy.target(code))
  }

  @MainActor
  func testNativeSpeechHitTestingProtectsLinksAndExcludesWhitespace() throws {
    let view = AgentReplyParagraphTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 80), textContainer: nil)
    let text = NSMutableAttributedString(string: "Text Link", attributes: [.font: UIFont.systemFont(ofSize: 17)])
    text.addAttribute(.link, value: try XCTUnwrap(URL(string: "https://example.org")), range: NSRange(location: 5, length: 4))
    view.attributedText = text
    view.layoutIfNeeded()
    view.layoutManager.ensureLayout(for: view.textContainer)
    func center(_ character: Int) -> CGPoint {
      let range = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: character, length: 1),
                                                actualCharacterRange: nil)
      let rect = view.layoutManager.boundingRect(forGlyphRange: range, in: view.textContainer)
      return CGPoint(x: rect.midX, y: rect.midY)
    }
    XCTAssertEqual(view.hit(at: center(1)), .text(1))
    XCTAssertEqual(view.hit(at: center(6)), .link)
    XCTAssertEqual(view.hit(at: CGPoint(x: 310, y: center(1).y)), .blank)
    XCTAssertEqual(view.hit(at: CGPoint(x: 10, y: 75)), .blank)
  }
}

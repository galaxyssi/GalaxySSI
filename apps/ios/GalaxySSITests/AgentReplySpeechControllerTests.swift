import XCTest
@testable import GalaxySSI

final class AgentReplySpeechControllerTests: XCTestCase {
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

import XCTest
@testable import GalaxySSI

final class AgentConversationGoalTests: XCTestCase {
  private func goal() -> AgentConversationGoal {
    .init(conversation: "synthetic-chat", objective: "Draft a two-paragraph fictional story.",
      route: .init(kind: .local, target: "local-llm", model: "synthetic-profile", endpointSHA: "", host: ""))
  }
  private func reply(_ state: String, _ result: String = "new work", _ next: String = "next stage") throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["state": state, "result": result, "next": next]), as: UTF8.self)
  }
  func testCommandBoundaryAndCaseFolding() {
    XCTAssertNil(AgentConversationGoalCommand.parse("ordinary message"))
    XCTAssertNil(AgentConversationGoalCommand.parse("/goals example"))
    XCTAssertNil(AgentConversationGoalCommand.parse("prefix /goal"))
    XCTAssertEqual(AgentConversationGoalCommand.parse(" /GOAL \n"), .status)
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal Write a story"), .start("Write a story"))
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal resume use a warmer tone"), .resume("use a warmer tone"))
  }
  func testMalformedControlCommandsAndOversizedObjectiveDoNotStartWork() {
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal pause another goal"), .help)
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal stop now"), .help)
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal status more"), .help)
    XCTAssertEqual(AgentConversationGoalCommand.parse("/goal " + String(repeating: "x", count: 4_001)), .help)
  }
  func testLocalizedControlAliasesRemainControlCommands() {
    for (key, expected) in [("status", AgentConversationGoalCommand.status), ("help", .help), ("pause", .pause), ("stop", .stop), ("resume", .resume(""))] {
      let alias = GalaxySSILocalization.string("galaxyssi.conversation_goal.command_" + key, fallback: key, language: LanguagePolicySettings.zhCN)
      XCTAssertEqual(AgentConversationGoalCommand.parse("/goal " + alias), expected)
    }
  }
  func testSixRoundsConsumeOnlyTheConfirmedAllowance() throws {
    var value = goal()
    for i in 1...6 {
      value = try value.claim()
      XCTAssertEqual(value.rounds, i); XCTAssertTrue(value.inFlight)
      value = try value.accept(reply("continue", "synthetic stage \(i)"))
    }
    XCTAssertEqual(value.phase, .paused); XCTAssertEqual(value.allowance, 6)
    XCTAssertThrowsError(try value.claim())
    let resumed = try value.resume(clarification: "Keep the original narrator")
    XCTAssertEqual(resumed.allowance, 12); XCTAssertEqual(resumed.rounds, 6)
    XCTAssertEqual(resumed.clarification, "Keep the original narrator")
    XCTAssertGreaterThan(resumed.generation, value.generation)
  }
  func testUncertainInFlightRequestCannotBeClaimedAgain() throws {
    let claimed = try goal().claim()
    XCTAssertThrowsError(try claimed.claim())
    let recovered = try claimed.halt(.interrupted)
    XCTAssertEqual(recovered.phase, .blocked); XCTAssertFalse(recovered.inFlight)
    XCTAssertEqual(recovered.rounds, 1)
    XCTAssertThrowsError(try recovered.claim())
  }
  func testDoneRequiresASeparateClaimAndFinalReview() throws {
    let proposed = try goal().claim().accept(reply("done", "complete fictional story", ""))
    XCTAssertEqual(proposed.phase, .running); XCTAssertTrue(proposed.review)
    XCTAssertFalse(proposed.inFlight)
    XCTAssertThrowsError(try proposed.accept(reply("verified", "", "")))
    let reviewed = try proposed.claim().accept(reply("verified", "", ""))
    XCTAssertEqual(reviewed.phase, .done); XCTAssertTrue(reviewed.terminal); XCTAssertFalse(reviewed.review)
    XCTAssertEqual(reviewed.rounds, 2)
  }
  func testCompletionCannotBeSelfCertifiedDuringAnOrdinaryRound() throws {
    XCTAssertThrowsError(try goal().claim().accept(reply("verified", "", "")))
    let proposed = try goal().claim().accept(reply("done", "final story", ""))
    XCTAssertThrowsError(try proposed.claim().accept(reply("done", "another story", "")))
    XCTAssertThrowsError(try proposed.claim().accept(reply("verified", "unsupported assertion", "")))
  }
  func testFailedReviewReturnsToConcreteWorkInsteadOfCompleting() throws {
    let proposed = try goal().claim().accept(reply("done", "draft", ""))
    let corrected = try proposed.claim().accept(reply("continue", "corrected draft", "tighten the ending"))
    XCTAssertEqual(corrected.phase, .running); XCTAssertFalse(corrected.review)
    XCTAssertEqual(corrected.checkpoints.last, "corrected draft")
  }
  func testBlockedRoundCanAskForMissingInputWithoutInventingWork() throws {
    let blocked = try goal().claim().accept(reply("blocked", "", "Which audience should this address?"))
    XCTAssertEqual(blocked.phase, .blocked); XCTAssertTrue(blocked.checkpoints.isEmpty)
    XCTAssertEqual(blocked.next, "Which audience should this address?")
    XCTAssertThrowsError(try blocked.accept(reply("continue")))
  }
  func testRepeatedProgressStopsTheLoop() throws {
    let first = try goal().claim().accept(reply("continue", "same stage"))
    let repeated = try first.claim().accept(reply("continue", "same stage"))
    XCTAssertEqual(repeated.phase, .blocked); XCTAssertEqual(repeated.issue, .repeatedProgress)
    XCTAssertEqual(repeated.checkpoints, ["same stage"])
  }
  func testPauseAndStopInvalidateClaimedGeneration() throws {
    let claimed = try goal().claim()
    let paused = try claimed.pause(), stopped = try claimed.stop()
    XCTAssertNotEqual(paused.generation, claimed.generation); XCTAssertNotEqual(stopped.generation, claimed.generation)
    XCTAssertFalse(paused.inFlight); XCTAssertFalse(stopped.inFlight)
    XCTAssertThrowsError(try paused.accept(reply("continue")))
    XCTAssertThrowsError(try stopped.resume(clarification: ""))
    XCTAssertEqual(try paused.resume(clarification: "").objective, claimed.objective)
  }
  func testCheckpointHandoffRetainsFirstAndLatestStages() throws {
    var value = goal()
    for i in 1...22 {
      if value.phase == .paused { value = try value.resume(clarification: "") }
      value = try value.claim().accept(reply("continue", "stage-\(i)"))
    }
    XCTAssertEqual(value.checkpoints.count, 16)
    XCTAssertEqual(value.checkpoints.first, "stage-1"); XCTAssertEqual(value.checkpoints.last, "stage-22")
    XCTAssertEqual(value.checkpoints[1], "stage-8")
  }
  func testMalformedTypedFieldsUnknownKeysAndExecutableRichOutputFailClosed() throws {
    let claim = try goal().claim()
    for raw in ["plain promise", #"{"state":"continue","result":true,"next":"step"}"#,
      #"{"state":"continue","result":"work","next":"step","tools":["send"]}"#,
      #"{"state":"continue","result":"work","next":""}"#,
      #"{"state":"continue","result":"```galaxyssi-rich","next":"step"}"#] {
      XCTAssertThrowsError(try claim.accept(raw), raw)
    }
    XCTAssertThrowsError(try claim.accept(reply("continue", String(repeating: "x", count: 12_001))))
    XCTAssertThrowsError(try claim.accept(reply("continue", "work", String(repeating: "x", count: 1_001))))
  }
  func testCheckpointPayloadRoundTripsWithoutChangingAuthority() throws {
    let value = try goal().claim().accept(reply("continue"))
    let restored = try JSONDecoder().decode(AgentConversationGoal.self, from: JSONEncoder().encode(value))
    XCTAssertEqual(restored, value); XCTAssertTrue(restored.valid)
    XCTAssertEqual(restored.route.kind, .local); XCTAssertEqual(restored.allowance, 6)
  }
}

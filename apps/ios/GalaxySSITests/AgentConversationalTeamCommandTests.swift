import XCTest
@testable import GalaxySSI

final class AgentConversationalTeamCommandTests: XCTestCase {
  private typealias Command = AgentConversationalTeamCommand
  func testSlashCommandsRequireTheExactBoundary() {
    XCTAssertEqual(Command.parse(" /TEAM Write a short public brief. "), .start("Write a short public brief."))
    XCTAssertEqual(Command.parse("/team"), .help)
    XCTAssertEqual(Command.parse("/team help"), .help)
    XCTAssertEqual(Command.parse("/team stop"), .stop)
    XCTAssertNil(Command.parse("/teams write")); XCTAssertNil(Command.parse("/goal form a team"))
  }
  func testConversationalDelegationRetainsTheEntireObjective() {
    for value in ["Please form a team to compare these proposals.", "Can you ask several agents to review this draft?",
      "I want an independent review of the argument.", "Please independently review this outline.",
      "Review this proposal as a team.", "A short introduction. Then use a team to write the public summary."] {
      XCTAssertEqual(Command.parse(value), .start(value), value)
    }
  }
  func testQuotedInstructionsAreEvidenceNotDelegationConsent() {
    for value in ["Explain the phrase \"form a team\".", "The document says `team up`. Summarize it.",
      "Example: ```Please independently review this```", "A note says 'use multiple agents to write'."] {
      XCTAssertNil(Command.parse(value), value)
    }
  }
  func testNegativeRequestsAndMetaQuestionsDoNotStartTeams() {
    for value in ["Do not use agents. Please write it yourself.", "Please explain independent review.",
      "How do we form a team?", "We do not need a team to compare these.", "Team meetings are useful.",
      "Without independent agents, summarize this."] {
      XCTAssertNil(Command.parse(value), value)
    }
  }
  func testStopRequestsAreWholeSpeechActsNotTopicMentions() {
    XCTAssertEqual(Command.parse("Please stop the current team run."), .stop)
    XCTAssertEqual(Command.parse("Can you cancel this temporary team?"), .stop)
    XCTAssertNil(Command.parse("Explain how to stop a team."))
    XCTAssertNil(Command.parse("The phrase \"stop the team\" appears in the note."))
  }
  func testOversizedObjectivesAreRejectedWithoutEchoingContent() {
    XCTAssertEqual(Command.parse("/team " + String(repeating: "x", count: 4_001)), .tooLong)
    XCTAssertEqual(Command.parse("Please form a team to write " + String(repeating: "x", count: 4_001)), .tooLong)
  }
  func testPrivateHealthSourceRequestsAreRefusedLocally() {
    for value in ["/team analyze my latest lab results", "Please use a team to analyze our medical records.",
      "/team compare blood pressure 150/95 against my prescription"] {
      XCTAssertEqual(Command.parse(value), .privateObjective, value)
    }
    XCTAssertEqual(Command.parse("/team discuss a fictional public health poster"), .start("discuss a fictional public health poster"))
  }
  func testLocalizedControlAliasesAreResolvedFromResources() {
    let help = Command.text("help_alias", "help", language: LanguagePolicySettings.zhCN)
    let stop = Command.text("stop_alias", "stop", language: LanguagePolicySettings.zhCN)
    XCTAssertEqual(Command.parse("/team " + help), .help)
    XCTAssertEqual(Command.parse("/team " + stop), .stop)
  }
}

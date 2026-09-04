import XCTest
@testable import GalaxySSI

final class AgentClarificationPolicyTests: XCTestCase {
  func testAgentClarificationPolicyAsksTargetedQuestionsForMissingDetails() {
    let cases: [(String, AgentClarificationQuestion)] = [
      ("Help me", .taskGoal),
      ("Write a program", .codeOutcome),
      ("Control my computer", .controlAction),
      ("Research", .researchTopic),
      ("Process the file", .fileAction),
      ("Remember this", .memoryContent),
      ("Create an automation", .automationDetails),
      ("\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}", .taskGoal),
      ("\u{5199}\u{4e2a}\u{7a0b}\u{5e8f}", .codeOutcome),
      ("\u{63a7}\u{5236}\u{624b}\u{673a}", .controlAction),
      ("\u{641c}\u{7d22}", .researchTopic),
      ("\u{8bb0}\u{4f4f}\u{8fd9}\u{4e2a}", .memoryContent),
      ("\u{521b}\u{5efa}\u{81ea}\u{52a8}\u{5316}", .automationDetails)
    ]

    for (goal, expectedQuestion) in cases {
      let decision = AgentClarificationPolicy.decide(goal: goal)

      XCTAssertEqual(decision.mode, .askLocally, goal)
      XCTAssertEqual(decision.question, expectedQuestion, goal)
      XCTAssertTrue(decision.shouldAsk, goal)
    }
  }

  func testAgentClarificationPolicyExecutesClearAndContextualRequests() {
    let clearRequests = [
      "Hello",
      "What is the battery level?",
      "Turn on the flashlight",
      "Set a one minute timer",
      "Research today's AI news",
      "Remember that I prefer concise replies",
      "Build an Android calculator app",
      "\u{4f60}\u{597d}",
      "\u{6253}\u{5f00}\u{624b}\u{7535}\u{7b52}",
      "\u{67e5}\u{4e00}\u{4e0b}\u{4eca}\u{5929}\u{4e0a}\u{6d77}\u{7684}\u{5929}\u{6c14}",
      "\u{8bb0}\u{4f4f}\u{6211}\u{559c}\u{6b22}\u{7b80}\u{6d01}\u{56de}\u{590d}"
    ]
    for goal in clearRequests {
      XCTAssertEqual(AgentClarificationPolicy.decide(goal: goal).mode, .execute, goal)
    }

    let contextualRequests = [
      "Continue",
      "Try again",
      "Handle this",
      "Make it better",
      "\u{7ee7}\u{7eed}",
      "\u{518d}\u{8bd5}\u{8bd5}",
      "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
      "\u{6309}\u{4e0a}\u{9762}\u{7684}\u{505a}"
    ]
    for goal in contextualRequests {
      let decision = AgentClarificationPolicy.decide(
        goal: goal,
        hasConversationContext: true
      )

      XCTAssertEqual(decision.mode, .execute, goal)
      XCTAssertFalse(decision.shouldAsk, goal)
    }
  }

  func testAgentClarificationPolicyUsesModelForVagueAttachmentTasks() {
    for goal in ["", "Take a look", "\u{5904}\u{7406}\u{4e00}\u{4e0b}"] {
      let decision = AgentClarificationPolicy.decide(
        goal: goal,
        hasAttachments: true
      )

      XCTAssertEqual(decision.mode, .askWithModel, goal)
      XCTAssertEqual(decision.question, .fileAction, goal)
    }

    XCTAssertEqual(
      AgentClarificationPolicy.decide(
        goal: "Summarize this PDF and list the action items",
        hasAttachments: true
      ).mode,
      .execute
    )
  }
}

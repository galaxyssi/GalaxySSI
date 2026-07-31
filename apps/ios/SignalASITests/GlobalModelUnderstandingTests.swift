import XCTest
@testable import SignalASI

final class GlobalModelUnderstandingTests: XCTestCase {
  func testGlobalUnderstandingDecodesLegacyPayloadWithDefaults() throws {
    let data = #"{"topic":"Runtime","project":"SignalASI"}"#.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(GlobalUnderstanding.self, from: data)

    XCTAssertEqual(decoded.topic, "Runtime")
    XCTAssertEqual(decoded.project, "SignalASI")
    XCTAssertEqual(decoded.goalCandidates, [])
    XCTAssertFalse(decoded.durableFollowUpUseful)
    XCTAssertEqual(decoded.novelty, 0.5)
  }

  func testModelUnderstandingDefaultsAndBoundsMatchAndroidShape() throws {
    let action = GlobalAutonomousAction(kind: .createTopic, goal: "Create project", priority: 2)
    let model = GlobalModelUnderstanding(
      topic: " Runtime ",
      goals: ["Ship", "Ship", ""],
      goalDependencies: [GlobalGoalDependencyProposal(goal: "Ship", dependsOn: "Verify")],
      actions: [action],
      goalState: .completed,
      nextCheckHours: 9_999,
      confidence: 2
    )
    let data = try JSONEncoder().encode(model)
    let restored = try JSONDecoder().decode(GlobalModelUnderstanding.self, from: data)

    XCTAssertEqual(restored.topic, "Runtime")
    XCTAssertEqual(restored.goals, ["Ship"])
    XCTAssertEqual(restored.goalDependencies.first?.dependsOn, "Verify")
    XCTAssertEqual(restored.actions.first?.kind, .createTopic)
    XCTAssertEqual(restored.goalState, .completed)
    XCTAssertEqual(restored.nextCheckHours, 720)
    XCTAssertEqual(restored.confidence, 1)
    XCTAssertTrue(restored.meaningful)
  }

  func testCognitionTaskDecodesLegacyPayloadWithEmptyResult() throws {
    let event = GlobalConversationEvent(
      id: "event-a",
      type: .messageCreated,
      conversationId: "conversation-a",
      actor: .user,
      content: "Ship iOS parity"
    )
    let payload: [String: Any] = [
      "id": "task-a",
      "sourceEvent": try jsonObject(event),
      "baselineUnderstanding": ["topic": "Runtime"],
      "status": "QUEUED"
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)

    let decoded = try JSONDecoder().decode(GlobalCognitionTask.self, from: data)

    XCTAssertEqual(decoded.id, "task-a")
    XCTAssertEqual(decoded.result, GlobalModelUnderstanding())
    XCTAssertEqual(decoded.longHorizonGoalId, "")
  }

  private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data)
  }
}

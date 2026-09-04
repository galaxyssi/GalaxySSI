import XCTest
@testable import GalaxySSI

final class AgentResponseSelfCheckTests: XCTestCase {
  func testMatchesAndroidRepairAndPassCases() {
    let substantive = AgentResponseSelfCheck.evaluate(
      latestRequest: "Summarize the report",
      response: "The report identifies three launch risks and recommends a one-day delay."
    )
    XCTAssertTrue(substantive.accepted)
    XCTAssertEqual(substantive.status, .passed)
    XCTAssertEqual(substantive.requestDigest.count, 16)
    XCTAssertTrue(substantive.diagnostic.contains("addresses the latest user request"))

    let acknowledgement = AgentResponseSelfCheck.evaluate(
      latestRequest: "Build and verify the Android app",
      response: "Got it. I will handle this now."
    )
    XCTAssertFalse(acknowledgement.accepted)
    XCTAssertEqual(acknowledgement.reasons, ["acknowledgement_only"])

    let missingAttachment = AgentResponseSelfCheck.evaluate(
      latestRequest: "Review this worksheet",
      response: "I cannot see any attachment. Please upload the file.",
      hasAttachments: true
    )
    XCTAssertEqual(missingAttachment.status, .repair)
    XCTAssertTrue(missingAttachment.reasons.contains("available_attachment_ignored"))
    XCTAssertTrue(missingAttachment.actionableRequest)

    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "Create a ZIP archive",
      response: "Done.",
      hasOutputArtifacts: true
    ).accepted)
    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "Create and return the annotated image",
      response: "",
      hasOutputArtifacts: true
    ).accepted)
  }

  func testMatchesAndroidChineseAndIdentityCases() {
    let chineseAcknowledgement = AgentResponseSelfCheck.evaluate(
      latestRequest: "\u{5206}\u{6790}\u{8fd9}\u{4efd}\u{62a5}\u{544a}",
      response: "\u{6536}\u{5230}\u{ff0c}\u{6211}\u{4f1a}\u{9a6c}\u{4e0a}\u{5904}\u{7406}\u{3002}"
    )
    XCTAssertFalse(chineseAcknowledgement.accepted)
    XCTAssertEqual(chineseAcknowledgement.reasons, ["acknowledgement_only"])

    let greeting = AgentResponseSelfCheck.evaluate(
      latestRequest: "hello",
      response: "Got it. I will handle this now."
    )
    XCTAssertFalse(greeting.accepted)
    XCTAssertEqual(greeting.reasons, ["acknowledgement_only"])

    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "thank you",
      response: "Okay"
    ).accepted)

    let identityMismatch = AgentResponseSelfCheck.evaluate(
      latestRequest: "Explain the error",
      response: "The token expired.",
      expectedIdentity: ["task_id": "task-1", "turn_id": "turn-2"],
      responseIdentity: ["task_id": "task-1", "turn_id": "turn-1"]
    )
    XCTAssertEqual(identityMismatch.status, .rejected)
    XCTAssertEqual(identityMismatch.reasons, ["identity_mismatch"])
  }
}

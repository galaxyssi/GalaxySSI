import XCTest
@testable import GalaxySSI

final class AgentActiveTurnPolicyTests: XCTestCase {
  func testMatchesAndroidContinuationDecisions() {
    for request in [
      "Stop",
      "Cancel the current task.",
      "\u{505c}\u{6b62}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
      "\u{4e0d}\u{7528}\u{7ee7}\u{7eed}\u{4e86}"
    ] {
      let decision = AgentActiveTurnPolicy.decide(
        request: request,
        activeGoal: "Build an Android app"
      )

      XCTAssertEqual(decision.disposition, .interrupt)
      XCTAssertEqual(decision.interventionKind, .interrupt)
    }

    let newTask = AgentActiveTurnPolicy.decide(
      request: "\u{65b0}\u{4efb}\u{52a1}: \u{67e5}\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}",
      activeGoal: "\u{6784}\u{5efa} Android \u{5e94}\u{7528}"
    )
    XCTAssertEqual(newTask.disposition, .independent)
    XCTAssertFalse(newTask.intervenes)

    let goalChange = AgentActiveTurnPolicy.decide(
      request: "\u{6539}\u{6210} Android \u{539f}\u{751f}\u{5e94}\u{7528}",
      activeGoal: "\u{505a}\u{4e00}\u{4e2a}\u{7f51}\u{9875}\u{5e94}\u{7528}"
    )
    XCTAssertEqual(goalChange.disposition, .steer)
    XCTAssertEqual(goalChange.interventionKind, .goalChange)

    let constraint = AgentActiveTurnPolicy.decide(
      request: "Do not stop after the first page.",
      activeGoal: "Export the whole report"
    )
    XCTAssertEqual(constraint.disposition, .steer)
    XCTAssertEqual(constraint.interventionKind, .constraint)

    let prompt = AgentActiveTurnPolicy.supersedingGoal(
      activeGoal: "Build a web game",
      intervention: "Change the goal to an Android game",
      kind: .goalChange
    )
    XCTAssertTrue(prompt.contains("Build a web game"))
    XCTAssertTrue(prompt.contains("Change the goal to an Android game"))
    XCTAssertTrue(prompt.contains("latest instruction has priority"))

    XCTAssertEqual(
      AgentActiveTurnPolicy.decide(
        request: "Review this image",
        activeGoal: "Build an Android app",
        hasNewAttachments: true
      ).disposition,
      .independent
    )
    XCTAssertEqual(
      AgentActiveTurnPolicy.decide(
        request: "Use this image instead",
        activeGoal: "Review the earlier image",
        hasNewAttachments: true
      ).disposition,
      .steer
    )
  }
}

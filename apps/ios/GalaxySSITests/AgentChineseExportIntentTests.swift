import XCTest
@testable import GalaxySSI

final class AgentChineseExportIntentTests: XCTestCase {
  private let inferences = ["\u{63a8}\u{5bfc}\u{51fa}", "\u{63a8}\u{5c0e}\u{51fa}"]
  private let exports = ["\u{5bfc}\u{51fa}", "\u{5c0e}\u{51fa}", "\u{532f}\u{51fa}"]

  func testSimplifiedAndTraditionalDerivationDoNotRequireFiles() {
    for verb in inferences {
      for source in ["bus timetable", "PDF", "Excel", "CSV"] {
        let goal = "Compare bus timetables by route code. \(verb) \(source) \u{73ed}\u{8ddd}"
        XCTAssertFalse(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
        XCTAssertFalse(AgentArtifactRequestPolicy.pdfRequested(goal), goal)
      }
    }
  }
  func testEveryDirectExportStillRequiresItsDeliverable() {
    for verb in exports {
      for format in ["PDF", "Excel", "CSV"] {
        let goal = "\(verb) \(format)"
        XCTAssertTrue(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
        XCTAssertEqual(AgentExecutionProfile.forGoal(goal).taskKind, .artifact, goal)
      }
    }
  }
  func testExportElsewhereInInferenceSentenceIsNotSuppressed() {
    for inference in inferences {
      for export in exports {
        let goal = "\(inference) \u{73ed}\u{8ddd}; \(export) CSV"
        XCTAssertTrue(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
        XCTAssertTrue(AgentArtifactRequestPolicy.positiveTerm(goal, term: export), goal)
      }
    }
  }
  func testInferenceOccurrenceCannotOverrideLaterNegatedExport() {
    for inference in inferences {
      for export in exports {
        let goal = "\(inference) \u{73ed}\u{8ddd}; \u{4e0d}\u{8981}\(export) PDF"
        XCTAssertFalse(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
        XCTAssertFalse(AgentArtifactRequestPolicy.pdfRequested(goal), goal)
      }
    }
  }
  func testEarlierNegationDoesNotSuppressLaterExplicitExport() {
    for export in exports {
      let goal = "\u{4e0d}\u{8981}\u{5bfc}\u{51fa} CSV; \(export) PDF"
      XCTAssertTrue(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
      XCTAssertTrue(AgentArtifactRequestPolicy.pdfRequested(goal), goal)
    }
  }
  func testQuotedFieldsAndEnglishWordBoundariesKeepExistingMeaning() {
    for export in exports {
      let goal = "{\"\(export)\":true}"
      XCTAssertFalse(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
      XCTAssertFalse(AgentArtifactRequestPolicy.positiveTerm(goal, term: export), goal)
    }
    for goal in ["Explain PDF", "An exporter reads CSV", "Do not export PDF"] {
      XCTAssertFalse(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
    }
    XCTAssertTrue(AgentExecutionProfile.forGoal("Export CSV").requiresArtifact)
  }
  func testPlanOnlyStillCannotRequireFileDelivery() {
    for export in exports {
      let goal = "\(export) PDF"
      XCTAssertFalse(AgentExecutionProfile.forGoal(goal, executionMode: .planOnly).requiresArtifact)
    }
  }
  func testInferenceDoesNotWeakenOtherArtifactRequirements() {
    let inference = "\u{63a8}\u{5bfc}\u{51fa} \u{73ed}\u{8ddd}"
    for goal in [inference + "; generate image", inference + "; return the file", inference + "; build an app"] {
      XCTAssertTrue(AgentExecutionProfile.forGoal(goal).requiresArtifact, goal)
    }
    XCTAssertFalse(AgentExecutionProfile.forGoal(inference + " PDF", hasAttachments: true).requiresArtifact)
  }
}

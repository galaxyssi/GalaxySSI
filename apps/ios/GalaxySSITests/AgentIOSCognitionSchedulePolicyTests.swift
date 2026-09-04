import XCTest
@testable import GalaxySSI

final class AgentIOSCognitionSchedulePolicyTests: XCTestCase {
  func testEventUsesOnlyLightweightProcessing() {
    XCTAssertEqual(
      AgentIOSCognitionSchedulePolicy.workPlan(.event),
      AgentIOSCognitionWorkPlan(eventLimit: 12, runBatchCognition: false, cycleCount: 0, projectKnowledge: false)
    )
  }

  func testScheduledExplicitAndProjectionPlansAreBounded() {
    XCTAssertEqual(AgentIOSCognitionSchedulePolicy.workPlan(.scheduled).cycleCount, 1)
    XCTAssertEqual(AgentIOSCognitionSchedulePolicy.workPlan(.explicit).cycleCount, 2)
    XCTAssertTrue(AgentIOSCognitionSchedulePolicy.workPlan(.projection).projectKnowledge)
  }

  func testActiveWorkUsesTenMinuteCadence() {
    XCTAssertEqual(
      AgentIOSCognitionSchedulePolicy.nextExplorationDelayMillis(
        pendingEvents: 1,
        activeCognition: 0,
        activeResearch: 0,
        pendingInsights: 0
      ),
      AgentIOSCognitionSchedulePolicy.minimumDelayMillis
    )
  }

  func testPendingInsightsUseThirtyMinuteCadence() {
    XCTAssertEqual(
      AgentIOSCognitionSchedulePolicy.nextExplorationDelayMillis(
        pendingEvents: 0,
        activeCognition: 0,
        activeResearch: 0,
        pendingInsights: 1
      ),
      30 * 60 * 1_000
    )
  }

  func testIdleWorkNeverWaitsLongerThanFourHours() {
    XCTAssertEqual(
      AgentIOSCognitionSchedulePolicy.nextExplorationDelayMillis(
        pendingEvents: 0,
        activeCognition: 0,
        activeResearch: 0,
        pendingInsights: 0
      ),
      AgentIOSCognitionSchedulePolicy.maximumDelayMillis
    )
  }
}

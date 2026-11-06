import XCTest
@testable import GalaxySSI

final class AgentIOSCognitionSchedulePolicyTests: XCTestCase {
  func testPauseRejectsEveryLearningEntryPointButNotProjection() {
    for mode: AgentIOSCognitionWorkMode in [.foreground, .event, .scheduled, .explicit] {
      XCTAssertFalse(AgentIOSCognitionSchedulePolicy.allows(mode, learningEnabled: false))
      XCTAssertTrue(AgentIOSCognitionSchedulePolicy.allows(mode, learningEnabled: true))
    }
    XCTAssertTrue(AgentIOSCognitionSchedulePolicy.allows(.projection, learningEnabled: false))
    XCTAssertFalse(AgentIOSCognitionSchedulePolicy.workPlan(.foreground).projectKnowledge)
  }

  func testLegacyAndCurrentSettingsKeepExplicitPauseOnReload() throws {
    let legacy = Data(#"{"enabled":false,"notifications_enabled":true,"proactive_insights_enabled":false}"#.utf8)
    let settings = try JSONDecoder().decode(GlobalAgentSettings.self, from: legacy)
    XCTAssertFalse(settings.enabled)
    XCTAssertTrue(settings.notificationsEnabled)
    XCTAssertFalse(settings.proactiveInsightsEnabled)
    XCTAssertEqual(try JSONDecoder().decode(GlobalAgentSettings.self, from: JSONEncoder().encode(settings)), settings)
    XCTAssertTrue(try JSONDecoder().decode(GlobalAgentSettings.self, from: Data("{}".utf8)).enabled)
  }

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

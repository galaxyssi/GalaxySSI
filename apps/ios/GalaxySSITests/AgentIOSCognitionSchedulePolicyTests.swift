import XCTest
@testable import GalaxySSI

final class AgentIOSCognitionSchedulePolicyTests: XCTestCase {
  func testDeviceLoadUsesNativeThermalAndBatteryThresholds() {
    func sample(_ thermal: ProcessInfo.ThermalState, _ battery: Int? = nil,
                powered: Bool = false, lowPower: Bool = false) -> AgentIOSBackgroundLoad {
      .evaluate(thermal: thermal, batteryPercent: battery, powered: powered, lowPower: lowPower)
    }
    XCTAssertEqual(sample(.nominal), .init(deferSeconds: 0, spacing: 1))
    XCTAssertEqual(sample(.fair), .init(deferSeconds: 0, spacing: 30))
    XCTAssertEqual(sample(.serious), .init(deferSeconds: 120, spacing: 30))
    XCTAssertEqual(sample(.critical), .init(deferSeconds: 300, spacing: 60))
    XCTAssertEqual(sample(.nominal, 10).deferSeconds, 300)
    XCTAssertEqual(sample(.nominal, 10, powered: true).deferSeconds, 0)
    XCTAssertEqual(sample(.nominal, 5, powered: true).deferSeconds, 300)
    XCTAssertEqual(sample(.nominal, 80, lowPower: true).deferSeconds, 300)
    XCTAssertFalse(AgentIOSCognitionWorkMode.explicit.usesBackgroundLoadPolicy)
    XCTAssertFalse(AgentIOSCognitionWorkMode.projection.usesBackgroundLoadPolicy)
  }

  func testAutomaticWakeCoalescesWithoutPostponingTheExistingRetry() {
    var wake = AgentIOSAutomaticCognitionWake()
    let hot = AgentIOSBackgroundLoad(deferSeconds: 120, spacing: 30)
    let fair = AgentIOSBackgroundLoad(deferSeconds: 0, spacing: 30)
    wake.request(.foreground)
    wake.request(.event)
    XCTAssertEqual(wake.pending, .foreground)
    XCTAssertEqual(wake.delay(now: 10, load: hot), 120)
    wake.request(.scheduled)
    XCTAssertEqual(wake.delay(now: 50, load: hot), 80)
    XCTAssertEqual(wake.delay(now: 130, load: fair), 0)
    XCTAssertEqual(wake.take(now: 130), .scheduled)
    XCTAssertNil(wake.take(now: 130))
    wake.request(.foreground)
    XCTAssertEqual(wake.delay(now: 131, load: fair), 29)
    wake.clear()
    XCTAssertNil(wake.pending)
  }

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

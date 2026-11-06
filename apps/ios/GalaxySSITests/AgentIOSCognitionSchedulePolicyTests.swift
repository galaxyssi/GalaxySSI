import XCTest
@testable import GalaxySSI

final class AgentIOSCognitionSchedulePolicyTests: XCTestCase {
  func testCognitionRecoveryPersistsExponentialDelayAndStopsAtTen() throws {
    var state = AgentIOSCognitionRecoveryState()
    let now: Int64 = 100_000
    state.recordFailure(nowMillis: now)
    XCTAssertEqual(state.delay(nowMillis: now), 30)
    state.recordFailure(nowMillis: now + 30_000)
    XCTAssertEqual(state.delay(nowMillis: now + 30_000), 60)
    for _ in 0..<7 { state.recordFailure(nowMillis: now + 90_000) }
    let restored = try JSONDecoder().decode(AgentIOSCognitionRecoveryState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(restored.failures, 9)
    XCTAssertEqual(restored.firstFailureAtMillis, now)
    XCTAssertEqual(restored.delay(nowMillis: now + 90_000), 1_800)
    state.recordFailure(nowMillis: now + 1_890_000)
    XCTAssertTrue(state.stopped)
    XCTAssertNil(state.delay(nowMillis: now + 1_890_000))
    state.recordFailure(nowMillis: now + 2_000_000)
    XCTAssertEqual(state.failures, 10)
  }

  @MainActor
  func testResearchCycleDoesNotDispatchOrOverwriteCorruptState() throws {
    let name = "cognition-recovery-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    defer { try? FileManager.default.removeItem(at: file) }
    let corrupt = Data("invalid research snapshot".utf8)
    try corrupt.write(to: file)
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let cycle = GalaxySSIGlobalAgentRuntimeBridge.processResearchCycle(
      store: store, stateStore: GalaxySSIGlobalResearchRuntimeStore(fileURL: file))
    XCTAssertEqual(cycle.persistenceFailed, true)
    XCTAssertTrue(cycle.dispatchRequests.isEmpty)
    XCTAssertEqual(try Data(contentsOf: file), corrupt)
  }
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

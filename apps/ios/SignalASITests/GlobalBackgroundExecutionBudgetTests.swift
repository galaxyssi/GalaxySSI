import XCTest
@testable import SignalASI

final class GlobalBackgroundExecutionBudgetTests: XCTestCase {
  func testDefersForPowerAndBattery() {
    let now: Int64 = 10_000
    let settings = GlobalAgentSettings.default
    let power = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(
        powerSaveMode: true,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let critical = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .autonomousWork,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 14,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let lowReasoning = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 20,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let lowResearch = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 20,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let charging = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 10,
        charging: true,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let override = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(powerSaveMode: true),
      settings: settings,
      nowMillis: now,
      explicitUserOverride: true
    )

    XCTAssertFalse(power.allowed)
    XCTAssertEqual(power.reason, .powerSave)
    XCTAssertEqual(power.nextEligibleAtMillis, now + GlobalBackgroundExecutionBudgetPolicy.powerSaveRetryMillis)
    XCTAssertFalse(critical.allowed)
    XCTAssertEqual(critical.reason, .criticalBattery)
    XCTAssertEqual(
      critical.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.criticalBatteryRetryMillis
    )
    XCTAssertFalse(lowReasoning.allowed)
    XCTAssertEqual(lowReasoning.reason, .lowBattery)
    XCTAssertEqual(
      lowReasoning.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.lowBatteryReasoningRetryMillis
    )
    XCTAssertFalse(lowResearch.allowed)
    XCTAssertEqual(lowResearch.reason, .lowBattery)
    XCTAssertEqual(
      lowResearch.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.lowBatteryResearchRetryMillis
    )
    XCTAssertTrue(charging.allowed)
    XCTAssertEqual(charging.reason, .none)
    XCTAssertTrue(override.allowed)
    XCTAssertEqual(override.nextEligibleAtMillis, now)
  }

  func testHandlesResearchNetworkGates() {
    let now: Int64 = 20_000
    let settings = GlobalAgentSettings.default
    let unavailable = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(networkAvailable: false),
      settings: settings,
      nowMillis: now
    )
    let unvalidated = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(networkAvailable: true, networkValidated: false),
      settings: settings,
      nowMillis: now
    )
    let metered = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        networkAvailable: true,
        networkValidated: true,
        networkMetered: true
      ),
      settings: settings,
      nowMillis: now
    )
    let allowedMetered = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        networkAvailable: true,
        networkValidated: true,
        networkMetered: true
      ),
      settings: GlobalAgentSettings(allowMeteredBackgroundResearch: true),
      nowMillis: now
    )
    let autonomousOffline = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .autonomousWork,
      environment: AgentTaskBudgetEnvironment(networkAvailable: false, networkValidated: false),
      settings: settings,
      nowMillis: now
    )
    let noBatteryProtection = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(batteryPercent: 5),
      settings: GlobalAgentSettings(protectBatteryForBackgroundWork: false),
      nowMillis: now
    )

    XCTAssertFalse(unavailable.allowed)
    XCTAssertEqual(unavailable.reason, .networkUnavailable)
    XCTAssertEqual(
      unavailable.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.networkRecoveryRetryMillis
    )
    XCTAssertFalse(unvalidated.allowed)
    XCTAssertEqual(unvalidated.reason, .networkUnvalidated)
    XCTAssertFalse(metered.allowed)
    XCTAssertEqual(metered.reason, .meteredNetwork)
    XCTAssertEqual(
      metered.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.meteredNetworkRetryMillis
    )
    XCTAssertTrue(allowedMetered.allowed)
    XCTAssertTrue(autonomousOffline.allowed)
    XCTAssertTrue(noBatteryProtection.allowed)
  }

  func testModelsUseAndroidWireNames() throws {
    let decodedSettings = try JSONDecoder.signalASI.decode(
      GlobalAgentSettings.self,
      from: Data(
        """
        {
          "protect_battery_for_background_work": false,
          "allow_metered_background_research": true,
          "daily_background_model_call_budget": 9999,
          "max_concurrent_background_model_calls": 0,
          "daily_background_token_budget": -10,
          "discovery_interval_millis": 1
        }
        """.utf8
      )
    )
    let workKind = try JSONDecoder.signalASI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""autonomous-work""#.utf8)
    )
    let fallbackWorkKind = try JSONDecoder.signalASI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""future""#.utf8)
    )
    let reason = try JSONDecoder.signalASI.decode(
      GlobalBackgroundDeferralReason.self,
      from: Data(#""network_unvalidated""#.utf8)
    )
    let fallbackReason = try JSONDecoder.signalASI.decode(
      GlobalBackgroundDeferralReason.self,
      from: Data(#""future""#.utf8)
    )
    let encodedDecision = String(decoding: try JSONEncoder.signalASI.encode(
      GlobalBackgroundExecutionDecision(
        allowed: false,
        nextEligibleAtMillis: 9_999,
        reason: .lowBattery
      )
    ), as: UTF8.self)
    let powerConstrained = AgentTaskBudgetEnvironment(powerSaveMode: true)
    let lowBatteryConstrained = AgentTaskBudgetEnvironment(batteryPercent: 19)
    let chargingLowBattery = AgentTaskBudgetEnvironment(batteryPercent: 19, charging: true)

    XCTAssertFalse(decodedSettings.protectBatteryForBackgroundWork)
    XCTAssertTrue(decodedSettings.allowMeteredBackgroundResearch)
    XCTAssertEqual(decodedSettings.dailyBackgroundModelCallBudget, 1_000)
    XCTAssertEqual(decodedSettings.maxConcurrentBackgroundModelCalls, 1)
    XCTAssertEqual(decodedSettings.dailyBackgroundTokenBudget, 0)
    XCTAssertEqual(decodedSettings.discoveryIntervalMillis, 60_000)
    XCTAssertEqual(workKind, .autonomousWork)
    XCTAssertEqual(fallbackWorkKind, .cognition)
    XCTAssertEqual(reason, .networkUnvalidated)
    XCTAssertEqual(fallbackReason, .none)
    XCTAssertTrue(encodedDecision.contains(#""next_eligible_at_millis":9999"#))
    XCTAssertTrue(encodedDecision.contains(#""reason":"LOW_BATTERY""#))
    XCTAssertTrue(powerConstrained.energyConstrained)
    XCTAssertTrue(lowBatteryConstrained.energyConstrained)
    XCTAssertFalse(chargingLowBattery.energyConstrained)
  }
}

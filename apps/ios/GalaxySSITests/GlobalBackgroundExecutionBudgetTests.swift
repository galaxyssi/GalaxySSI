import XCTest
@testable import GalaxySSI

final class GlobalBackgroundExecutionBudgetTests: XCTestCase {
  func testEnergyStateDoesNotSuppressDurableBackgroundWork() {
    let environments = [
      AgentTaskBudgetEnvironment(powerSaveMode: true),
      AgentTaskBudgetEnvironment(batteryPercent: 5),
      AgentTaskBudgetEnvironment(batteryPercent: 5, charging: true)
    ]
    for environment in environments {
      for kind in GlobalBackgroundWorkKind.allCases {
        let decision = GlobalBackgroundExecutionBudgetPolicy.decide(
          kind: kind,
          environment: environment,
          settings: .default,
          nowMillis: 10_000
        )
        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.reason, .none)
        XCTAssertEqual(decision.nextEligibleAtMillis, 10_000)
      }
    }
  }

  func testNetworkStateDoesNotAddSchedulerConstraint() {
    let environments = [
      AgentTaskBudgetEnvironment(networkAvailable: false, networkValidated: false),
      AgentTaskBudgetEnvironment(networkAvailable: true, networkValidated: false),
      AgentTaskBudgetEnvironment(networkAvailable: true, networkValidated: true, networkMetered: true)
    ]
    for environment in environments {
      for kind in GlobalBackgroundWorkKind.allCases {
        let decision = GlobalBackgroundExecutionBudgetPolicy.decide(
          kind: kind,
          environment: environment,
          settings: .default,
          nowMillis: 20_000
        )
        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.reason, .none)
      }
    }
  }

  func testExplicitOverrideUsesSameCheckpointSemantics() {
    let decision = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(powerSaveMode: true),
      settings: .default,
      nowMillis: 30_000,
      explicitUserOverride: true
    )
    XCTAssertTrue(decision.allowed)
    XCTAssertEqual(decision.nextEligibleAtMillis, 30_000)
  }

  func testModelsKeepStableWireNames() throws {
    let workKind = try JSONDecoder.galaxySSI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""autonomous-work""#.utf8)
    )
    let fallbackWorkKind = try JSONDecoder.galaxySSI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""future""#.utf8)
    )
    let reason = try JSONDecoder.galaxySSI.decode(
      GlobalBackgroundDeferralReason.self,
      from: Data(#""network_unvalidated""#.utf8)
    )
    let encoded = String(decoding: try JSONEncoder.galaxySSI.encode(
      GlobalBackgroundExecutionDecision(
        allowed: true,
        nextEligibleAtMillis: 9_999,
        reason: .none
      )
    ), as: UTF8.self)

    XCTAssertEqual(workKind, .autonomousWork)
    XCTAssertEqual(fallbackWorkKind, .cognition)
    XCTAssertEqual(reason, .networkUnvalidated)
    XCTAssertTrue(encoded.contains(#""next_eligible_at_millis":9999"#))
    XCTAssertTrue(encoded.contains(#""reason":"NONE""#))
  }
}

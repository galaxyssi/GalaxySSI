import XCTest
@testable import GalaxySSI

final class AgentTaskBudgetTests: XCTestCase {
  func testDecodesAndroidProfilesNormalizesLimitsAndPersistsStoreBudget() throws {
    let decoded = try JSONDecoder.galaxySSI.decode(
      AgentTaskBudget.self,
      from: Data("""
      {
        "version": 1,
        "profile": "PRIVATE",
        "max_elapsed_seconds": 999999999,
        "max_cost_micros": 9999999999,
        "max_input_tokens": -25,
        "max_output_tokens": 999999999,
        "max_network_bytes": 999999999999,
        "minimum_battery_percent": 250,
        "max_memory_bytes": 999999999999,
        "network_policy": "TRUSTED_ONLY",
        "allow_cloud": false,
        "allow_paid_providers": false
      }
      """.utf8)
    )
    let fallback = try JSONDecoder.galaxySSI.decode(
      AgentTaskBudget.self,
      from: Data(#"{"profile":"not-supported","network_policy":"not-supported"}"#.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(AgentTaskBudget.forProfile(.fast))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let store = makeStore()

    XCTAssertEqual(decoded.profile, .privateMode)
    XCTAssertEqual(decoded.maxElapsedSeconds, AgentTaskBudget.maximumElapsedSeconds)
    XCTAssertEqual(decoded.maxCostMicros, AgentTaskBudget.maximumCostMicros)
    XCTAssertEqual(decoded.maxInputTokens, 0)
    XCTAssertEqual(decoded.maxOutputTokens, AgentTaskBudget.maximumTokens)
    XCTAssertEqual(decoded.maxNetworkBytes, AgentTaskBudget.maximumNetworkBytes)
    XCTAssertEqual(decoded.minimumBatteryPercent, 100)
    XCTAssertEqual(decoded.maxMemoryBytes, AgentTaskBudget.maximumMemoryBytes)
    XCTAssertEqual(decoded.networkPolicy, .trustedOnly)
    XCTAssertFalse(decoded.allowCloud)
    XCTAssertFalse(decoded.allowPaidProviders)
    XCTAssertEqual(fallback.profile, .adaptive)
    XCTAssertEqual(fallback.networkPolicy, .any)
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual(object["profile"] as? String, "fast")
    XCTAssertEqual(object["max_elapsed_seconds"] as? Int, 300)
    XCTAssertEqual(object["max_network_bytes"] as? Int, 128 * 1_048_576)

    XCTAssertEqual(store.agentTaskBudget.profile, .adaptive)
    store.selectAgentTaskBudgetProfile(.economy)
    XCTAssertEqual(store.agentTaskBudget.maxCostMicros, 250_000)
    XCTAssertEqual(store.agentTaskBudget.minimumBatteryPercent, 15)

    store.updateAgentTaskBudget {
      $0.maxInputTokens = 999_999_999
      $0.allowPaidProviders = false
    }

    XCTAssertEqual(store.agentTaskBudget.profile, .custom)
    XCTAssertEqual(store.agentTaskBudget.maxInputTokens, AgentTaskBudget.maximumTokens)
    XCTAssertFalse(store.agentTaskBudget.allowPaidProviders)
  }

  func testPolicyMatchesAndroidLimitDecisions() {
    let cases: [(AgentTaskBudget, AgentTaskBudgetUsage, AgentTaskBudgetLimit)] = [
      (AgentTaskBudget(maxElapsedSeconds: 1), AgentTaskBudgetUsage(elapsedMillis: 1_001), .time),
      (AgentTaskBudget(maxCostMicros: 10), AgentTaskBudgetUsage(costMicros: 11), .cost),
      (AgentTaskBudget(maxInputTokens: 10), AgentTaskBudgetUsage(inputTokens: 11), .inputTokens),
      (AgentTaskBudget(maxOutputTokens: 10), AgentTaskBudgetUsage(outputTokens: 11), .outputTokens),
      (AgentTaskBudget(maxNetworkBytes: 10), AgentTaskBudgetUsage(networkBytes: 11), .network),
      (AgentTaskBudget(maxMemoryBytes: 10), AgentTaskBudgetUsage(peakMemoryBytes: 11), .memory)
    ]

    for (budget, usage, expectedLimit) in cases {
      let decision = AgentTaskBudgetPolicy.evaluate(budget: budget, usage: usage)

      XCTAssertFalse(decision.allowed)
      XCTAssertEqual(decision.limit, expectedLimit)
    }

    let cloudDecision = AgentTaskBudgetPolicy.evaluate(
      budget: .forProfile(.privateMode),
      usage: AgentTaskBudgetUsage(),
      cloudProvider: true
    )
    let paidDecision = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(allowPaidProviders: false),
      usage: AgentTaskBudgetUsage(),
      paidProvider: true
    )

    XCTAssertEqual(cloudDecision.limit, .cloud)
    XCTAssertEqual(paidDecision.limit, .paidProvider)
  }

  func testBatteryAndNetworkChecksUseTheCurrentEnvironment() {
    let lowBattery = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(minimumBatteryPercent: 20),
      usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(batteryPercent: 19)
    )
    let charging = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(minimumBatteryPercent: 20),
      usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(batteryPercent: 1, charging: true)
    )
    let trusted = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(networkPolicy: .trustedOnly),
      usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(networkAvailable: true),
      networkRequired: true,
      trustedNetworkTarget: true
    )
    let untrusted = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(networkPolicy: .trustedOnly),
      usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(networkAvailable: true),
      networkRequired: true,
      trustedNetworkTarget: false
    )

    XCTAssertEqual(lowBattery.limit, .battery)
    XCTAssertTrue(charging.allowed)
    XCTAssertTrue(trusted.allowed)
    XCTAssertEqual(untrusted.limit, .network)
  }

  private func makeStore() -> GalaxySSIStore {
    let suite = "AgentTaskBudgetTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
  }
}

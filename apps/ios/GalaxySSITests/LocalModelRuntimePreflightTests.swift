import XCTest
@testable import GalaxySSI

final class LocalModelRuntimePreflightTests: XCTestCase {
  func testLocalModelRuntimeEstimatorAcceptsNormalGemmaWorkload() {
    let estimate = estimate()

    XCTAssertEqual(estimate.readiness, .ready)
    XCTAssertTrue(estimate.launchAllowed)
    XCTAssertEqual(estimate.recommendedContextTokens, 4_096)
    XCTAssertEqual(estimate.recommendedThreads, 6)
    XCTAssertGreaterThan(estimate.kvCacheBytes, 0)
    XCTAssertLessThan(estimate.totalRequiredBytes, estimate.safeMemoryBudgetBytes)
  }

  func testEveryIOSNativeModelUsesDedicatedPinnedRuntime() {
    let supportedProfiles = LocalModelRuntimeCatalog.profiles().filter(\.supportsIOSRuntime)

    XCTAssertFalse(supportedProfiles.isEmpty)
    XCTAssertTrue(supportedProfiles.allSatisfy(LocalModelInferenceExecutionPolicy.requiresDedicatedExecutor))
    XCTAssertEqual(
      LocalModelInferenceExecutionPolicy.executionIsolation,
      "in-process-dedicated-serial-executor"
    )
    XCTAssertEqual(
      LocalModelInferenceExecutionPolicy.backendScope,
      "pinned-static-cpu-metal-accelerate"
    )
  }

  func testIOSGGUFRuntimeRejectsForeignQNNBackendFamilies() {
    XCTAssertTrue(LocalModelInferenceExecutionPolicy.allowsRegisteredBackend(named: "CPU, Metal"))
    XCTAssertFalse(LocalModelInferenceExecutionPolicy.allowsRegisteredBackend(named: "QNN Hexagon"))
    XCTAssertFalse(LocalModelInferenceExecutionPolicy.allowsRegisteredBackend(named: "Genie HTP"))
  }

  func testLocalModelRuntimeEstimatorReducesOversizedContextBeforeBlocking() {
    let estimate = estimate(contextTokens: 32_768)

    XCTAssertEqual(estimate.readiness, .caution)
    XCTAssertTrue(estimate.issues.contains(.contextReduced))
    XCTAssertLessThan(estimate.recommendedContextTokens, estimate.requestedContextTokens)
    XCTAssertLessThanOrEqual(estimate.totalRequiredBytes, estimate.safeMemoryBudgetBytes)
  }

  func testLocalModelRuntimeEstimatorBlocksWhenMinimumContextIsOverBudget() {
    let estimate = estimate(
      profile: LocalModelRuntimeProfiles.QWEN_2_5_7B_Q4,
      device: device(totalGib: 4, availableGib: 1)
    )

    XCTAssertEqual(estimate.readiness, .blocked)
    XCTAssertTrue(estimate.issues.contains(.insufficientMemory))
    XCTAssertFalse(estimate.launchAllowed)
  }

  func testLocalModelRuntimeEstimatorAppliesMemoryAndThermalPoliciesWithoutEnergyGating() {
    let lowMemory = estimate(device: device(systemLowMemory: true))
    let moderate = estimate(device: device(thermalStatus: 2))
    let severe = estimate(device: device(thermalStatus: 3))
    let hotBattery = estimate(device: device(batteryTemperatureCelsius: 45.0))
    let saver = estimate(device: device(powerSaveMode: true))

    XCTAssertEqual(lowMemory.readiness, .blocked)
    XCTAssertTrue(lowMemory.issues.contains(.systemLowMemory))
    XCTAssertEqual(moderate.readiness, .caution)
    XCTAssertEqual(moderate.recommendedThreads, 2)
    XCTAssertTrue(moderate.issues.contains(.thermalPressure))
    XCTAssertEqual(severe.readiness, .blocked)
    XCTAssertEqual(hotBattery.readiness, .blocked)
    XCTAssertEqual(saver.readiness, .ready)
    XCTAssertEqual(saver.recommendedThreads, 6)
    XCTAssertFalse(saver.issues.contains(.lowBattery))
    XCTAssertFalse(saver.issues.contains(.criticalBattery))
    XCTAssertFalse(saver.issues.contains(.powerSaveMode))
  }

  func testLocalModelRuntimePreflightRequiresRealModelFileBeforeLaunch() throws {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("missing-local-model-\(UUID().uuidString).gguf")

    XCTAssertThrowsError(
      try LocalModelRuntimePreflight.beforeLaunch(
        profile: LocalModelRuntimeProfiles.GEMMA_3_1B_Q4,
        modelFileURL: missingURL,
        contextTokens: 4_096,
        device: device()
      )
    ) { error in
      guard case LocalModelRuntimePreflightError.blocked(let estimate) = error else {
        return XCTFail("Expected blocked local model preflight error")
      }
      XCTAssertTrue(estimate.issues.contains(.modelFileMissing))
      XCTAssertTrue(estimate.issues.contains(.modelFileInvalid))
    }

    let modelURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-model-\(UUID().uuidString).gguf")
    try Data(repeating: 0x31, count: 1_024).write(to: modelURL)
    defer { try? FileManager.default.removeItem(at: modelURL) }

    let allowed = try LocalModelRuntimePreflight.beforeLaunch(
      profile: LocalModelRuntimeProfiles.GEMMA_3_1B_Q4,
      modelFileURL: modelURL,
      contextTokens: 4_096,
      device: device()
    )

    XCTAssertTrue(allowed.launchAllowed)
    XCTAssertEqual(allowed.modelFileBytes, 1_024)
  }

  func testLocalModelRuntimeEstimatorRejectsBlockedAssessmentAtLaunchGate() {
    XCTAssertThrowsError(
      try LocalModelRuntimeEstimator.requireLaunchable(estimate(device: device(systemLowMemory: true)))
    ) { error in
      guard case LocalModelRuntimePreflightError.blocked(let estimate) = error else {
        return XCTFail("Expected blocked local model preflight error")
      }
      XCTAssertTrue(estimate.issues.contains(.systemLowMemory))
    }
  }

  func testLocalModelRuntimeEstimatorKvCacheScalesWithContextLength() {
    let short = estimate(contextTokens: 2_048)
    let long = estimate(contextTokens: 4_096)

    XCTAssertEqual(short.kvCacheBytes * 2, long.kvCacheBytes)
  }

  func testLocalModelRuntimeModelsUseAndroidWireNamesAndSettingsBounds() throws {
    let estimate = estimate(device: device(thermalStatus: 2, powerSaveMode: true))
    let encoded = try JSONEncoder().encode(estimate)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let issues = try XCTUnwrap(object["issues"] as? [String])
    let nestedDevice = try XCTUnwrap(object["device"] as? [String: Any])
    let request = LocalModelRuntimeRequest(
      profile: LocalModelRuntimeProfiles.GEMMA_3_1B_Q4,
      requestedContextTokens: 8_192,
      preferredThreads: 4
    )
    let requestObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(object["readiness"] as? String, "CAUTION")
    XCTAssertEqual(
      (object["model_file_bytes"] as? NSNumber)?.int64Value ?? 0,
      LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.expectedModelFileBytes
    )
    XCTAssertEqual((object["recommended_threads"] as? NSNumber)?.intValue ?? 0, 2)
    XCTAssertTrue(issues.contains("THERMAL_PRESSURE"))
    XCTAssertFalse(issues.contains("POWER_SAVE_MODE"))
    XCTAssertEqual(nestedDevice["system_low_memory"] as? Bool, false)
    XCTAssertEqual((nestedDevice["battery_temperature_celsius"] as? NSNumber)?.doubleValue ?? -1, 32.0)
    XCTAssertEqual((requestObject["requested_context_tokens"] as? NSNumber)?.intValue ?? 0, 8_192)
    XCTAssertEqual((requestObject["preferred_threads"] as? NSNumber)?.intValue ?? 0, 4)
    XCTAssertEqual(requestObject["require_model_file"] as? Bool, false)
    XCTAssertEqual(LocalModelRuntimeReadiness.fromWireValue("ready"), .ready)
    XCTAssertEqual(LocalModelRuntimeIssue.fromWireValue("LOW_BATTERY"), .lowBattery)

    let suiteName = "LocalModelRuntimeSettingsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertEqual(LocalModelRuntimeSettings.selectedProfile(defaults: defaults), LocalModelRuntimeProfiles.GEMMA_3_4B_Q4)
    LocalModelRuntimeSettings.setSelectedProfile("qwen-2.5-7b-q4", defaults: defaults)
    XCTAssertEqual(LocalModelRuntimeSettings.selectedProfile(defaults: defaults), LocalModelRuntimeProfiles.QWEN_2_5_7B_Q4)
    LocalModelRuntimeSettings.setSelectedProfile("unknown-profile", defaults: defaults)
    XCTAssertEqual(LocalModelRuntimeSettings.selectedProfile(defaults: defaults), LocalModelRuntimeProfiles.GEMMA_3_4B_Q4)
    LocalModelRuntimeSettings.setContextTokens(64, defaults: defaults)
    XCTAssertEqual(LocalModelRuntimeSettings.contextTokens(defaults: defaults), 512)
    LocalModelRuntimeSettings.setContextTokens(100_000, defaults: defaults)
    XCTAssertEqual(LocalModelRuntimeSettings.contextTokens(defaults: defaults), 32_768)
  }

  func testLocalModelDeviceSnapshotDetectorMapsIOSThermalStateConservatively() {
    let snapshot = LocalModelDeviceSnapshotDetector.capture(
      totalMemoryBytes: 8 * GIB,
      availableMemoryBytes: 5 * GIB,
      systemLowMemory: false,
      processorCount: 8,
      batteryPercent: 80,
      charging: true,
      batteryTemperatureCelsius: nil,
      thermalState: .serious,
      powerSaveMode: false
    )

    XCTAssertEqual(snapshot.totalMemoryBytes, 8 * GIB)
    XCTAssertEqual(snapshot.availableMemoryBytes, 5 * GIB)
    XCTAssertEqual(snapshot.cpuCoreCount, 8)
    XCTAssertEqual(snapshot.batteryPercent, 80)
    XCTAssertEqual(snapshot.thermalStatus, 2)
    XCTAssertEqual(LocalModelDeviceSnapshotDetector.thermalStatus(for: .critical), 3)
  }

  private func estimate(
    profile: LocalModelRuntimeProfile = LocalModelRuntimeProfiles.GEMMA_3_4B_Q4,
    contextTokens: Int = 4_096,
    device: LocalModelDeviceSnapshot = LocalModelRuntimePreflightTests.makeDevice()
  ) -> LocalModelRuntimeEstimate {
    LocalModelRuntimeEstimator.estimate(
      LocalModelRuntimeRequest(profile: profile, requestedContextTokens: contextTokens),
      device: device
    )
  }

  private static func makeDevice(
    totalGib: Int64 = 12,
    availableGib: Int64 = 8,
    systemLowMemory: Bool = false,
    cpuCoreCount: Int = 8,
    batteryPercent: Int? = 80,
    charging: Bool = true,
    batteryTemperatureCelsius: Double? = 32.0,
    thermalStatus: Int? = 0,
    powerSaveMode: Bool = false
  ) -> LocalModelDeviceSnapshot {
    LocalModelDeviceSnapshot(
      totalMemoryBytes: totalGib * GIB,
      availableMemoryBytes: availableGib * GIB,
      systemLowMemory: systemLowMemory,
      cpuCoreCount: cpuCoreCount,
      batteryPercent: batteryPercent,
      charging: charging,
      batteryTemperatureCelsius: batteryTemperatureCelsius,
      thermalStatus: thermalStatus,
      powerSaveMode: powerSaveMode
    )
  }

  private func device(
    totalGib: Int64 = 12,
    availableGib: Int64 = 8,
    systemLowMemory: Bool = false,
    cpuCoreCount: Int = 8,
    batteryPercent: Int? = 80,
    charging: Bool = true,
    batteryTemperatureCelsius: Double? = 32.0,
    thermalStatus: Int? = 0,
    powerSaveMode: Bool = false
  ) -> LocalModelDeviceSnapshot {
    Self.makeDevice(
      totalGib: totalGib,
      availableGib: availableGib,
      systemLowMemory: systemLowMemory,
      cpuCoreCount: cpuCoreCount,
      batteryPercent: batteryPercent,
      charging: charging,
      batteryTemperatureCelsius: batteryTemperatureCelsius,
      thermalStatus: thermalStatus,
      powerSaveMode: powerSaveMode
    )
  }

  private static let GIB: Int64 = 1_024 * 1_024 * 1_024
}

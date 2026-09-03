import XCTest
@testable import SignalASI

@MainActor
final class AgentDeviceProfileTests: XCTestCase {
  func testLocalIdentityNameUsesDeviceNameAndIdentitySuffix() {
    XCTAssertEqual(
      SignalASIDeviceIdentityName.format(
        deviceName: "iPhone 17 Pro Max",
        signalASIId: "signalasi:0123456789ab69d7"
      ),
      "iPhone 17 Pro Max · 69D7"
    )
  }

  func testLocalIdentityNameNormalizesWhitespaceAndSuffixCase() {
    XCTAssertEqual(
      SignalASIDeviceIdentityName.format(
        deviceName: "  Alice's   iPhone  ",
        signalASIId: "signalasi:0123456789abcdef"
      ),
      "Alice's iPhone · CDEF"
    )
  }

  func testLocalIdentityNameMigratesOnlyLegacyDefaults() {
    XCTAssertTrue(SignalASIDeviceIdentityName.isLegacyDefault("Me"))
    XCTAssertTrue(SignalASIDeviceIdentityName.isLegacyDefault("\u{6211}"))
    XCTAssertTrue(SignalASIDeviceIdentityName.isLegacyDefault("  "))
    XCTAssertFalse(SignalASIDeviceIdentityName.isLegacyDefault("Helen"))
  }

  func testAutomotiveProfileIsVoiceFirstAndConservative() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(interfaceClass: .automotive)
    )

    XCTAssertEqual(profile.kind, .automotive)
    XCTAssertTrue(profile.voiceFirst)
    XCTAssertTrue(profile.reduceMotion)
    XCTAssertTrue(profile.conservativeMedia)
    XCTAssertEqual(profile.maxTeamConcurrency, 1)
    XCTAssertEqual(profile.minimumTouchTargetDp, 64)
    XCTAssertEqual(profile.inputTargetPolicy.orientation, .flexible)
    XCTAssertEqual(profile.inputTargetPolicy.voiceButtonMinimumWidthDp, 160)
  }

  func testTabletProfileExpandsParallelismAndCaptureSize() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(interfaceClass: .tablet, smallestScreenWidthDp: 834)
    )

    XCTAssertEqual(profile.kind, .tablet)
    XCTAssertEqual(profile.maxReadReasoningTasks, 3)
    XCTAssertEqual(profile.maxTeamConcurrency, 4)
    XCTAssertEqual(profile.maxScreenCaptureLongEdgePx, 2_048)
    XCTAssertFalse(profile.conservativeMedia)
    XCTAssertEqual(profile.inputTargetPolicy.orientation, .flexible)
  }

  func testIOS15PhoneUsesCompatibilityBudget() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(osMajorVersion: 15)
    )

    XCTAssertEqual(profile.kind, .legacyIOSPhone)
    XCTAssertEqual(profile.maxReadReasoningTasks, 1)
    XCTAssertEqual(profile.maxTeamConcurrency, 1)
    XCTAssertEqual(profile.maxQemuMemoryMegabytes, 640)
    XCTAssertTrue(profile.reduceMotion)
    XCTAssertTrue(profile.conservativeMedia)
  }

  func testLowMemoryIPadKeepsCompatibilityAndTabletIdentity() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(
        interfaceClass: .tablet,
        osMajorVersion: 17,
        smallestScreenWidthDp: 768,
        lowMemoryDevice: true
      )
    )

    XCTAssertEqual(profile.kind, .legacyIOSTablet)
    XCTAssertEqual(profile.maxTeamConcurrency, 2)
    XCTAssertEqual(profile.minimumTouchTargetDp, 52)
    XCTAssertEqual(profile.maxScreenCaptureLongEdgePx, 1_400)
  }

  func testCurrentIPhoneIsNotMisclassifiedAsLegacy() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(osMajorVersion: 17, totalMemoryBytes: 8 * agentDeviceProfileTestGiB)
    )

    XCTAssertEqual(profile.kind, .phone)
    XCTAssertEqual(profile.maxTeamConcurrency, 3)
    XCTAssertEqual(profile.maxQemuMemoryMegabytes, 1_536)
  }

  func testLowPowerModeKeepsPhoneIdentityButUsesConservativeMedia() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(osMajorVersion: 17, totalMemoryBytes: 8 * agentDeviceProfileTestGiB, lowPowerMode: true)
    )

    XCTAssertEqual(profile.kind, .phone)
    XCTAssertTrue(profile.conservativeMedia)
    XCTAssertFalse(profile.reduceMotion)
  }

  func testLargeTabletCaptureIsDownscaledWithoutChangingAspectRatio() {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(interfaceClass: .tablet, smallestScreenWidthDp: 700)
    )

    XCTAssertEqual(
      profile.constrainCaptureSize(width: 1_600, height: 2_560),
      AgentDeviceCaptureSize(width: 1_280, height: 2_048)
    )
  }

  func testCompatibilityDeviceCapsNormalMediaWithoutChangingDeferredState() {
    let profile = AgentDeviceProfilePolicy.resolve(signals: signals(osMajorVersion: 15))
    let adapted = profile.adaptMedia(
      AgentMediaDeliveryProfile(
        state: .normal,
        id: "normal",
        imageTargetBytes: 100_000,
        audioSampleRateHz: 44_100,
        audioBitRateBps: 96_000,
        deferMediaUpload: false
      )
    )

    XCTAssertEqual(adapted.imageTargetBytes, 64 * 1024)
    XCTAssertEqual(adapted.audioSampleRateHz, 16_000)
    XCTAssertEqual(adapted.audioBitRateBps, 32_000)
    XCTAssertFalse(adapted.deferMediaUpload)
  }

  func testOfflineMediaRemainsDeferredAfterDeviceProfileAdaptation() {
    let profile = AgentDeviceProfilePolicy.resolve(signals: signals(osMajorVersion: 15))
    let adapted = profile.adaptMedia(AgentMediaNetworkPolicy.profile(for: .offline))

    XCTAssertEqual(adapted.state, .offline)
    XCTAssertEqual(adapted.imageTargetBytes, 48 * 1024)
    XCTAssertEqual(adapted.audioBitRateBps, 24_000)
    XCTAssertTrue(adapted.deferMediaUpload)
  }

  func testRuntimeBudgetCapsQemuCpuAndMemory() {
    let profile = AgentDeviceProfilePolicy.resolve(signals: signals(osMajorVersion: 15))
    let budget = profile.constrainRuntime(cpuCount: 8, memoryMegabytes: 2_048)

    XCTAssertEqual(budget.cpuCount, 2)
    XCTAssertEqual(budget.memoryMegabytes, 640)
  }

  func testProfileCodecUsesAndroidStyleWireKeys() throws {
    let profile = AgentDeviceProfilePolicy.resolve(
      signals: signals(interfaceClass: .automotive)
    )
    let encoded = String(data: try JSONEncoder().encode(profile), encoding: .utf8) ?? ""

    XCTAssertTrue(encoded.contains(#""kind":"AUTOMOTIVE""#))
    XCTAssertTrue(encoded.contains(#""max_team_concurrency":1"#))
    XCTAssertTrue(encoded.contains(#""voice_first":true"#))
    XCTAssertEqual(try JSONDecoder().decode(AgentDeviceProfile.self, from: Data(encoded.utf8)), profile)
  }

  private func signals(
    interfaceClass: AgentDeviceInterfaceClass = .phone,
    osMajorVersion: Int = 17,
    smallestScreenWidthDp: Int = 393,
    lowMemoryDevice: Bool = false,
    totalMemoryBytes: Int64 = 8 * agentDeviceProfileTestGiB,
    processorCount: Int = 6,
    lowPowerMode: Bool = false,
    thermalPressure: Bool = false,
    reduceMotionEnabled: Bool = false
  ) -> AgentDeviceProfileSignals {
    AgentDeviceProfileSignals(
      interfaceClass: interfaceClass,
      osMajorVersion: osMajorVersion,
      smallestScreenWidthDp: smallestScreenWidthDp,
      lowMemoryDevice: lowMemoryDevice,
      totalMemoryBytes: totalMemoryBytes,
      processorCount: processorCount,
      lowPowerMode: lowPowerMode,
      thermalPressure: thermalPressure,
      reduceMotionEnabled: reduceMotionEnabled
    )
  }
}

private let agentDeviceProfileTestGiB: Int64 = 1024 * 1024 * 1024

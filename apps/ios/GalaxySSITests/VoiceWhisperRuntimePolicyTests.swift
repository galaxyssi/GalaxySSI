import XCTest
@testable import GalaxySSI

final class VoiceWhisperRuntimePolicyTests: XCTestCase {
  func testAutomaticChoosesRealtimeAndSecondPassWhenCertified() {
    let fastProfile = profile(id: "tiny", family: .tiny, displayName: "Tiny", mode: .realtimePartial)
    let accurateProfile = profile(id: "small", family: .small, displayName: "Small", mode: .secondPass)
    let fast = candidate(fastProfile, level: .realtime, mode: .realtimePartial, rtfP95: 0.42)
    let accurate = candidate(accurateProfile, level: .secondPass, mode: .secondPass, rtfP95: 1.4)
    let decision = VoiceWhisperRuntimePolicyEngine.decide(
      VoiceWhisperRuntimePolicyInput(
        userMode: .automatic,
        candidates: [accurate, fast],
        environment: environment(highRiskTask: true)
      )
    )

    XCTAssertEqual(decision.provider, .local)
    XCTAssertEqual(decision.fastProfileId, .some("tiny"))
    XCTAssertEqual(decision.fastMode, .some(.realtimePartial))
    XCTAssertEqual(decision.accurateProfileId, .some("small"))
    XCTAssertTrue(decision.runSecondPass)
    XCTAssertEqual(decision.partialIntervalMillis, .some(750))
  }

  func testPrivacyNeverFallsBackToRemote() {
    let decision = VoiceWhisperRuntimePolicyEngine.decide(
      VoiceWhisperRuntimePolicyInput(
        userMode: .privacy,
        candidates: [],
        environment: environment(network: .unmetered, remoteAllowed: true)
      )
    )

    XCTAssertEqual(decision.provider, .unavailable)
    XCTAssertNil(decision.fastMode)
    XCTAssertTrue(decision.reasons.contains("Privacy mode has no realtime-certified local model"))
  }

  func testCriticalBatteryFallsBackToRemoteWhenAllowed() {
    let fastProfile = profile(id: "tiny", family: .tiny, displayName: "Tiny", mode: .realtimePartial)
    let decision = VoiceWhisperRuntimePolicyEngine.decide(
      VoiceWhisperRuntimePolicyInput(
        userMode: .automatic,
        candidates: [candidate(fastProfile, level: .realtime, mode: .realtimePartial, rtfP95: 0.5)],
        environment: environment(network: .metered, batteryPercent: 4, remoteAllowed: true)
      )
    )

    XCTAssertEqual(decision.provider, .remote)
    XCTAssertEqual(decision.fastMode, .some(.remoteNode))
    XCTAssertTrue(decision.reasons.contains("Critical battery level blocks sustained local inference"))
  }

  func testRemoteRecommendedCertificationIsNotInstalledUsable() throws {
    let env = try StorageEnvironment()
    let source = try env.writeFile(named: "model.bin", contents: "verified-model")
    let model = try env.profile(for: source)
    _ = try env.storage.install(sourceFileURL: source, profile: model, sourceLabel: "test")

    try env.storage.updateCertification(model, certification: .remoteRecommended)
    let snapshot = env.storage.inspect(model)

    XCTAssertEqual(snapshot.state, .unsupported)
    XCTAssertFalse(snapshot.installed)
  }

  private func profile(
    id: String,
    family: VoiceWhisperModelFamily,
    displayName: String,
    mode: VoiceWhisperExecutionMode,
    ram: Int64 = 128 * 1_024 * 1_024
  ) -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: id,
      family: family,
      displayName: displayName,
      fileName: "ggml-\(id).bin",
      sizeLabel: "test",
      expectedSizeBytes: 1_024,
      sha256: String(repeating: "a", count: 64),
      recommendedMode: mode,
      minAvailableRamBytes: ram,
      defaultPartialIntervalMillis: 750
    )
  }

  private func candidate(
    _ model: VoiceWhisperModelProfile,
    level: VoiceWhisperCertificationLevel,
    mode: VoiceWhisperExecutionMode,
    rtfP95: Double,
    peakPss: Int64 = 256 * 1_024 * 1_024
  ) -> VoiceWhisperRuntimeCandidate {
    VoiceWhisperRuntimeCandidate(
      profile: model,
      installed: true,
      certification: VoiceWhisperCertification(
        key: benchmarkKey(for: model),
        level: level,
        recommendedMode: mode,
        recommendedThreadCount: 4,
        recommendedPartialIntervalMillis: model.defaultPartialIntervalMillis,
        warmRtfP50: rtfP95 / 2,
        warmRtfP95: rtfP95,
        peakPssBytes: peakPss,
        createdAtEpochMillis: 1
      )
    )
  }

  private func benchmarkKey(for model: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkKey {
    VoiceWhisperBenchmarkKey(
      manufacturer: "Apple",
      device: "iPhone",
      soc: "A17",
      osVersion: "17.0",
      appVersionCode: 1,
      whisperNativeVersion: "test",
      nativeBuildFingerprint: "test",
      modelProfileId: model.id,
      modelSha256: model.sha256,
      benchmarkAudioVersion: "test"
    )
  }

  private func environment(
    network: VoiceWhisperNetworkState = .offline,
    batteryPercent: Int? = 80,
    highRiskTask: Bool = false,
    remoteAllowed: Bool = false
  ) -> VoiceWhisperRuntimeEnvironment {
    VoiceWhisperRuntimeEnvironment(
      network: network,
      availableMemoryBytes: 2 * 1_024 * 1_024 * 1_024,
      currentPssBytes: 128 * 1_024 * 1_024,
      batteryPercent: batteryPercent,
      charging: false,
      foreground: true,
      decodeQueueDepth: 0,
      utteranceDurationMillis: 4_000,
      highRiskTask: highRiskTask,
      remoteAllowed: remoteAllowed
    )
  }

  private final class StorageEnvironment {
    let root: URL
    let storage: VoiceWhisperModelStorage

    init() throws {
      let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      root = rootURL
      try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: rootURL, catalogVersion: "test", clockMillis: { 10_000 })
    }

    func writeFile(named name: String, contents: String) throws -> URL {
      let url = root.appendingPathComponent(name, isDirectory: false)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func profile(for fileURL: URL) throws -> VoiceWhisperModelProfile {
      VoiceWhisperModelProfile(
        id: "test_model",
        displayName: "Test model",
        fileName: "ggml-test.bin",
        sizeLabel: "test",
        expectedSizeBytes: Int64(try Data(contentsOf: fileURL).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: fileURL)
      )
    }
  }
}

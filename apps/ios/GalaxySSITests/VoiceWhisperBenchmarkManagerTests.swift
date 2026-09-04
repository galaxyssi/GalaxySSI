import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkManagerTests: XCTestCase {
  func testSaveCurrentAndDecisionUseCurrentCertification() throws {
    let env = try Environment()
    let profile = try env.installProfile(id: "tiny", family: .tiny, mode: .realtimePartial)
    let record = env.record(for: profile, level: .realtime, mode: .realtimePartial, rtfP95: 0.42)

    try env.manager.save(record, profile: profile)

    XCTAssertEqual(env.manager.current(profile: profile)?.certification.level, .realtime)
    XCTAssertEqual(env.manager.latest(profile: profile)?.certification.warmRtfP95, 0.42)
    XCTAssertEqual(env.storage.inspect(profile).state, .certified)

    let decision = env.manager.decide(
      userMode: .automatic,
      context: VoiceWhisperBenchmarkDecisionContext(utteranceDurationMillis: 4_000)
    )

    XCTAssertEqual(decision.provider, .local)
    XCTAssertEqual(decision.fastProfileId, .some(profile.id))
    XCTAssertEqual(decision.fastMode, .some(.realtimePartial))
    XCTAssertEqual(decision.threadCount, .some(4))
  }

  func testCurrentMissResetsInstalledCertification() throws {
    let env = try Environment()
    let profile = try env.installProfile(id: "tiny", family: .tiny, mode: .realtimePartial)
    try env.storage.updateCertification(profile, certification: .realtime)

    XCTAssertNil(env.manager.current(profile: profile))
    XCTAssertEqual(env.storage.inspect(profile).state, .installedUncertified)
  }

  func testDecisionIgnoresLatestRecordWhenKeyDoesNotMatchCurrentDevice() throws {
    let env = try Environment()
    let profile = try env.installProfile(id: "tiny", family: .tiny, mode: .realtimePartial)
    let stale = env.record(
      for: profile,
      level: .realtime,
      mode: .realtimePartial,
      rtfP95: 0.35,
      device: "iPhone-stale"
    )
    try env.store.save(stale)

    XCTAssertNotNil(env.manager.latest(profile: profile))
    XCTAssertNil(env.manager.current(profile: profile))

    let decision = env.manager.decide(
      userMode: .automatic,
      context: VoiceWhisperBenchmarkDecisionContext(network: .unmetered, remoteAllowed: true)
    )

    XCTAssertEqual(decision.provider, .remote)
    XCTAssertNil(decision.fastProfileId)
    XCTAssertTrue(decision.reasons.contains("Automatic mode requires a current realtime certification"))
  }

  func testDecisionContextHoldsSevereThermalStatus() throws {
    var elapsedMillis: Int64 = 1_000
    let thermalController = VoiceWhisperThermalController(elapsedMillis: { elapsedMillis })
    let env = try Environment(thermalController: thermalController)
    let profile = try env.installProfile(id: "tiny", family: .tiny, mode: .realtimePartial)
    try env.manager.save(
      env.record(for: profile, level: .realtime, mode: .realtimePartial, rtfP95: 0.3, threads: 6),
      profile: profile
    )

    _ = env.manager.decide(
      userMode: .automatic,
      context: VoiceWhisperBenchmarkDecisionContext(thermalStatus: 3)
    )
    elapsedMillis += 1_000
    let held = env.manager.decide(
      userMode: .automatic,
      context: VoiceWhisperBenchmarkDecisionContext(thermalStatus: 0)
    )

    XCTAssertEqual(held.provider, .local)
    XCTAssertEqual(held.fastMode, .some(.finalOnly))
    XCTAssertEqual(held.threadCount, .some(2))
    XCTAssertTrue(held.reasons.contains("Severe thermal pressure disables realtime partial decoding"))
  }

  private final class Environment {
    let root: URL
    let storage: VoiceWhisperModelStorage
    let store: VoiceWhisperBenchmarkStore
    let manager: VoiceWhisperBenchmarkManager
    let profileProvider: ProfileProvider

    init(thermalController: VoiceWhisperThermalController = VoiceWhisperThermalController()) throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: root, catalogVersion: "test", clockMillis: { 10_000 })
      store = VoiceWhisperBenchmarkStore(fileURL: root.appendingPathComponent("benchmarks.json", isDirectory: false))
      let provider = ProfileProvider()
      profileProvider = provider
      manager = VoiceWhisperBenchmarkManager(
        modelsDirectory: root,
        storage: storage,
        store: store,
        thermalController: thermalController,
        modelsProvider: { provider.profiles },
        deviceIdentityProvider: {
          VoiceWhisperBenchmarkDeviceIdentity(
            device: "iPhone-test",
            soc: "A17",
            osVersion: "17.0"
          )
        },
        buildInfoProvider: {
          VoiceWhisperBenchmarkBuildInfo(
            appVersionCode: 7,
            whisperNativeVersion: "test-native",
            nativeBuildFingerprint: "test-build"
          )
        },
        deviceSnapshotProvider: {
          LocalModelDeviceSnapshot(
            totalMemoryBytes: 6 * 1_024 * 1_024 * 1_024,
            availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
            systemLowMemory: false,
            cpuCoreCount: 6,
            batteryPercent: 80,
            charging: false,
            thermalStatus: 0,
            powerSaveMode: false
          )
        }
      )
    }

    func installProfile(
      id: String,
      family: VoiceWhisperModelFamily,
      mode: VoiceWhisperExecutionMode
    ) throws -> VoiceWhisperModelProfile {
      let source = root.appendingPathComponent("\(id).bin", isDirectory: false)
      try Data("verified-\(id)".utf8).write(to: source)
      let profile = VoiceWhisperModelProfile(
        id: id,
        family: family,
        displayName: id.uppercased(),
        fileName: "ggml-\(id).bin",
        sizeLabel: "test",
        expectedSizeBytes: Int64(try Data(contentsOf: source).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: source),
        recommendedMode: mode,
        minAvailableRamBytes: 128 * 1_024 * 1_024,
        defaultPartialIntervalMillis: 750
      )
      _ = try storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test")
      profileProvider.profiles = [profile]
      return profile
    }

    func record(
      for profile: VoiceWhisperModelProfile,
      level: VoiceWhisperCertificationLevel,
      mode: VoiceWhisperExecutionMode,
      rtfP95: Double,
      device: String = "iPhone-test",
      threads: Int = 4
    ) -> VoiceWhisperBenchmarkRecord {
      let key = VoiceWhisperBenchmarkKey(
        manufacturer: "Apple",
        device: device,
        soc: "A17",
        osVersion: "17.0",
        appVersionCode: 7,
        whisperNativeVersion: "test-native",
        nativeBuildFingerprint: "test-build",
        modelProfileId: profile.id,
        modelSha256: profile.sha256,
        benchmarkAudioVersion: "\(VoiceWhisperBenchmarkManager.benchmarkAudioVersion):" +
          String(VoiceWhisperBenchmarkManager.benchmarkAudioSHA256.prefix(16))
      )
      return VoiceWhisperBenchmarkRecord(
        certification: VoiceWhisperCertification(
          key: key,
          level: level,
          recommendedMode: mode,
          recommendedThreadCount: threads,
          recommendedPartialIntervalMillis: profile.defaultPartialIntervalMillis,
          warmRtfP50: rtfP95 / 2,
          warmRtfP95: rtfP95,
          peakPssBytes: 256 * 1_024 * 1_024,
          createdAtEpochMillis: 10_000
        )
      )
    }

    private final class ProfileProvider {
      var profiles: [VoiceWhisperModelProfile] = []
    }
  }
}

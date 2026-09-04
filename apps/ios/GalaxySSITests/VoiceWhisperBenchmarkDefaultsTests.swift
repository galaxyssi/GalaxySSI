import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkDefaultsTests: XCTestCase {
  func testSystemProbeMapsDeviceSnapshotToBenchmarkSnapshot() {
    let snapshot = VoiceWhisperBenchmarkSystemProbe.snapshot(
      device: LocalModelDeviceSnapshot(
        totalMemoryBytes: 6 * 1_024 * 1_024 * 1_024,
        availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        systemLowMemory: true,
        cpuCoreCount: 6,
        batteryPercent: 42,
        charging: false,
        batteryTemperatureCelsius: 37.5,
        thermalStatus: 2,
        powerSaveMode: false
      )
    )

    XCTAssertEqual(snapshot.availableMemoryBytes, 4 * 1_024 * 1_024 * 1_024)
    XCTAssertTrue(snapshot.systemLowMemory)
    XCTAssertEqual(snapshot.batteryTemperatureCelsius, 37.5)
    XCTAssertEqual(snapshot.thermalStatus, 2)
  }

  func testManagerKeyUsesExplicitBenchmarkAudioVersion() throws {
    let env = try Environment()
    let defaultKey = env.manager.key(profile: env.profile)
    let explicitKey = env.manager.key(profile: env.profile, benchmarkAudioVersion: "custom-audio")

    XCTAssertNotEqual(defaultKey.stableId, explicitKey.stableId)
    XCTAssertEqual(explicitKey.benchmarkAudioVersion, "custom-audio")
  }

  func testDefaultFactoryCreatesCoordinatorThatUsesSharedManagerStore() async throws {
    let env = try Environment()
    let record = env.record(audioVersion: "test-audio")
    let runner = FakeRunner(record: record)
    let coordinator = VoiceWhisperBenchmarkDefaultFactory.makeCoordinator(
      modelsDirectory: env.root,
      modelManager: env.modelManager,
      benchmarkManager: env.manager,
      bundle: Bundle(for: Self.self),
      audioLoader: {
        try VoiceWhisperBenchmarkAudio(
          version: "test-audio",
          pcm16: Array(repeating: 1, count: VoiceWhisperBenchmarkAudio.sampleRateHz * 5),
          expectedTokens: ["hello"],
          language: "en"
        )
      },
      runnerOverride: { _ in runner }
    )

    let result = try await coordinator.benchmark(profile: env.profile)

    XCTAssertEqual(result.certification.key.benchmarkAudioVersion, "test-audio")
    XCTAssertEqual(env.manager.latest(profile: env.profile)?.certification.key.stableId, record.certification.key.stableId)
    XCTAssertEqual(runner.runCount, 1)
  }

  private final class Environment {
    let root: URL
    let storage: VoiceWhisperModelStorage
    let modelManager: VoiceWhisperModelManager
    let manager: VoiceWhisperBenchmarkManager
    let profile: VoiceWhisperModelProfile

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: root, catalogVersion: "test", clockMillis: { 10_000 })
      let source = root.appendingPathComponent("tiny.bin", isDirectory: false)
      try Data("verified".utf8).write(to: source)
      profile = VoiceWhisperModelProfile(
        id: "tiny",
        family: .tiny,
        displayName: "Tiny",
        fileName: "ggml-tiny.bin",
        sizeLabel: "test",
        expectedSizeBytes: Int64(try Data(contentsOf: source).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: source),
        recommendedMode: .realtimePartial,
        minAvailableRamBytes: 128 * 1_024 * 1_024,
        defaultPartialIntervalMillis: 750
      )
      _ = try storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test")
      modelManager = VoiceWhisperModelManager(modelsDirectory: root, storage: storage)
      let installedProfile = profile
      manager = VoiceWhisperBenchmarkManager(
        modelsDirectory: root,
        storage: storage,
        modelsProvider: { [installedProfile] },
        deviceIdentityProvider: {
          VoiceWhisperBenchmarkDeviceIdentity(device: "iPhone", soc: "A17", osVersion: "17.0")
        },
        buildInfoProvider: {
          VoiceWhisperBenchmarkBuildInfo(
            appVersionCode: 1,
            whisperNativeVersion: "test",
            nativeBuildFingerprint: "test"
          )
        }
      )
    }

    func record(audioVersion: String) -> VoiceWhisperBenchmarkRecord {
      VoiceWhisperBenchmarkRecord(
        certification: VoiceWhisperCertification(
          key: manager.key(profile: profile, benchmarkAudioVersion: audioVersion),
          level: .realtime,
          recommendedMode: .realtimePartial,
          recommendedThreadCount: 4,
          recommendedPartialIntervalMillis: 750,
          warmRtfP50: 0.25,
          warmRtfP95: 0.5,
          createdAtEpochMillis: 2_000
        )
      )
    }
  }

  private final class FakeRunner: VoiceWhisperBenchmarkRunning {
    private let record: VoiceWhisperBenchmarkRecord
    private(set) var runCount = 0

    init(record: VoiceWhisperBenchmarkRecord) {
      self.record = record
    }

    func run(
      profile: VoiceWhisperModelProfile,
      audio: VoiceWhisperBenchmarkAudio,
      force: Bool,
      onProgress: @escaping (VoiceWhisperBenchmarkProgress) -> Void
    ) async throws -> VoiceWhisperBenchmarkRecord {
      runCount += 1
      return record
    }
  }
}

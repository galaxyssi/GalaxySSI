import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkRunCoordinatorTests: XCTestCase {
  func testBenchmarkLoadsAudioRunsAndSyncsCertification() async throws {
    let env = try Environment()
    let record = env.record(level: .realtime)
    let runner = FakeBenchmarkRunner(record: record)
    let coordinator = env.coordinator(runner: runner)
    var progress: [VoiceWhisperBenchmarkProgress] = []

    let result = try await coordinator.benchmark(profile: env.profile) {
      progress.append($0)
    }

    XCTAssertEqual(result.certification.level, .realtime)
    XCTAssertEqual(env.storage.inspect(env.profile).state, .certified)
    XCTAssertEqual(runner.audioVersions, ["test-audio"])
    XCTAssertEqual(env.audioLoadCount, 1)
    XCTAssertEqual(progress.map(\.stage), [.verifying, .complete])
    XCTAssertFalse(coordinator.isRunning(profileId: env.profile.id))
  }

  func testRejectsSecondBenchmarkWhileOneIsRunning() async throws {
    let env = try Environment()
    let gate = RunnerGate()
    let runner = FakeBenchmarkRunner(record: env.record(level: .realtime), gate: gate)
    let coordinator = env.coordinator(runner: runner)

    let first = Task {
      try await coordinator.benchmark(profile: env.profile)
    }
    while !gate.waiting {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    XCTAssertTrue(coordinator.isRunning(profileId: env.profile.id))
    do {
      _ = try await coordinator.benchmark(profile: env.profile)
      XCTFail("Expected busy benchmark")
    } catch {
      XCTAssertEqual(
        error as? VoiceWhisperBenchmarkRunCoordinatorError,
        .busy(profileId: env.profile.id)
      )
    }

    gate.release()
    _ = try await first.value
  }

  func testCancelForInteractiveVoiceCancelsActiveBenchmark() async throws {
    let env = try Environment()
    let gate = RunnerGate()
    let runner = FakeBenchmarkRunner(record: env.record(level: .realtime), gate: gate)
    let coordinator = env.coordinator(runner: runner)

    let task = Task {
      try await coordinator.benchmark(profile: env.profile)
    }
    while !gate.waiting {
      try await Task.sleep(nanoseconds: 1_000_000)
    }

    coordinator.cancelForInteractiveVoice()
    gate.release()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      XCTAssertFalse(coordinator.isRunning(profileId: env.profile.id))
    }
  }

  private final class Environment {
    let root: URL
    let storage: VoiceWhisperModelStorage
    let store: VoiceWhisperBenchmarkStore
    let profile: VoiceWhisperModelProfile
    let manager: VoiceWhisperBenchmarkManager
    var audioLoadCount = 0

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: root, catalogVersion: "test", clockMillis: { 10_000 })
      store = VoiceWhisperBenchmarkStore(fileURL: root.appendingPathComponent("benchmarks.json", isDirectory: false))
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
      let installedProfile = profile
      manager = VoiceWhisperBenchmarkManager(
        modelsDirectory: root,
        storage: storage,
        store: store,
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

    func coordinator(runner: FakeBenchmarkRunner) -> VoiceWhisperBenchmarkRunCoordinator {
      VoiceWhisperBenchmarkRunCoordinator(
        manager: manager,
        audioLoader: {
          self.audioLoadCount += 1
          return try VoiceWhisperBenchmarkAudio(
            version: "test-audio",
            pcm16: Array(repeating: 1, count: VoiceWhisperBenchmarkAudio.sampleRateHz * 5),
            expectedTokens: ["hello"],
            language: "en"
          )
        },
        runnerFactory: { runner }
      )
    }

    func record(level: VoiceWhisperCertificationLevel) -> VoiceWhisperBenchmarkRecord {
      let certification = VoiceWhisperCertification(
        key: manager.key(profile: profile),
        level: level,
        recommendedMode: .realtimePartial,
        recommendedThreadCount: 4,
        recommendedPartialIntervalMillis: 750,
        warmRtfP50: 0.25,
        warmRtfP95: 0.5,
        createdAtEpochMillis: 2_000
      )
      return VoiceWhisperBenchmarkRecord(certification: certification)
    }
  }

  private final class FakeBenchmarkRunner: VoiceWhisperBenchmarkRunning {
    private let record: VoiceWhisperBenchmarkRecord
    private let gate: RunnerGate?
    private let lock = NSLock()
    private(set) var audioVersions: [String] = []

    init(record: VoiceWhisperBenchmarkRecord, gate: RunnerGate? = nil) {
      self.record = record
      self.gate = gate
    }

    func run(
      profile: VoiceWhisperModelProfile,
      audio: VoiceWhisperBenchmarkAudio,
      force: Bool,
      onProgress: @escaping (VoiceWhisperBenchmarkProgress) -> Void
    ) async throws -> VoiceWhisperBenchmarkRecord {
      lock.lock()
      audioVersions.append(audio.version)
      lock.unlock()
      onProgress(VoiceWhisperBenchmarkProgress(stage: .verifying, completedSteps: 0, totalSteps: 1))
      if let gate {
        await gate.wait()
      }
      try Task.checkCancellation()
      onProgress(VoiceWhisperBenchmarkProgress(stage: .complete, completedSteps: 1, totalSteps: 1))
      return record
    }
  }

  private final class RunnerGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    var waiting: Bool {
      lock.lock()
      defer { lock.unlock() }
      return continuation != nil
    }

    func wait() async {
      await withCheckedContinuation { next in
        lock.lock()
        continuation = next
        lock.unlock()
      }
    }

    func release() {
      lock.lock()
      let next = continuation
      continuation = nil
      lock.unlock()
      next?.resume()
    }
  }
}

import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkRunnerTests: XCTestCase {
  func testRunSearchesThreadsCertifiesAndStoresRecord() async throws {
    let env = try Environment()
    let audio = try env.audio()
    var progress: [VoiceWhisperBenchmarkProgress] = []

    let record = try await env.runner.run(profile: env.profile, audio: audio) {
      progress.append($0)
    }

    XCTAssertEqual(record.certification.level, .realtime)
    XCTAssertEqual(record.certification.recommendedThreadCount, 2)
    XCTAssertEqual(record.threadCandidates, [2, 3, 4])
    XCTAssertEqual(env.store.find(record.certification.key)?.certification.level, .realtime)
    XCTAssertEqual(progress.first?.stage, .verifying)
    XCTAssertEqual(progress.last?.stage, .complete)
    XCTAssertTrue(env.runtimePool.loadedThreads.contains(2))
    XCTAssertTrue(env.runtimePool.abortRequests > 0)
  }

  func testRunReturnsCachedRecordWhenForceIsFalse() async throws {
    let env = try Environment()
    let audio = try env.audio()
    let key = env.keyFactory(env.profile, audio.version)
    let cached = VoiceWhisperBenchmarkRecordBuilder.terminalRecord(
      key: key,
      profile: env.profile,
      level: .remoteRecommended,
      reason: "cached",
      verificationDurationMillis: 0,
      highPerformanceCoreCount: 4,
      threadCandidates: [2],
      createdAtEpochMillis: 2_000
    )
    try env.store.save(cached)

    let record = try await env.runner.run(profile: env.profile, audio: audio)

    XCTAssertEqual(record.certification.failureReason, "cached")
    XCTAssertTrue(env.runtimePool.loadedThreads.isEmpty)
  }

  func testPreflightFailureStoresTerminalRecordWithoutRuntimeLoad() async throws {
    let env = try Environment(
      snapshot: VoiceWhisperBenchmarkSystemSnapshot(
        availableMemoryBytes: 128,
        systemLowMemory: true,
        thermalStatus: 0
      )
    )

    let record = try await env.runner.run(profile: env.profile, audio: try env.audio())

    XCTAssertEqual(record.certification.level, .remoteRecommended)
    XCTAssertEqual(record.certification.failureReason, "iOS reported system-wide low memory")
    XCTAssertTrue(env.runtimePool.loadedThreads.isEmpty)
  }

  func testModerateThermalDefersBenchmark() async throws {
    let env = try Environment(
      snapshot: VoiceWhisperBenchmarkSystemSnapshot(
        availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        thermalStatus: 2
      )
    )

    do {
      _ = try await env.runner.run(profile: env.profile, audio: try env.audio())
      XCTFail("Expected deferred benchmark")
    } catch {
      XCTAssertEqual(
        error as? VoiceWhisperBenchmarkRunnerError,
        .deferred("Benchmark paused until the device cools below MODERATE")
      )
    }
  }

  private final class Environment {
    let root: URL
    let store: VoiceWhisperBenchmarkStore
    let profile: VoiceWhisperModelProfile
    let runtimePool: FakeRuntimePool
    let runner: VoiceWhisperBenchmarkRunner

    init(
      snapshot: VoiceWhisperBenchmarkSystemSnapshot = VoiceWhisperBenchmarkSystemSnapshot(
        availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        pssBytes: 128 * 1_024 * 1_024,
        rssBytes: 160 * 1_024 * 1_024,
        nativeAllocatedBytes: 64 * 1_024 * 1_024,
        cpuTimeMillis: 100,
        energyCounterNwh: 10,
        thermalStatus: 0
      )
    ) throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      store = VoiceWhisperBenchmarkStore(fileURL: root.appendingPathComponent("benchmarks.json", isDirectory: false))
      profile = VoiceWhisperModelProfile(
        id: "tiny",
        family: .tiny,
        displayName: "Tiny",
        fileName: "ggml-tiny.bin",
        sizeLabel: "test",
        expectedSizeBytes: 1_024,
        sha256: String(repeating: "a", count: 64),
        recommendedMode: .realtimePartial,
        minAvailableRamBytes: 128 * 1_024 * 1_024,
        defaultPartialIntervalMillis: 750
      )
      let pool = FakeRuntimePool()
      runtimePool = pool
      var now: Int64 = 1_000
      runner = VoiceWhisperBenchmarkRunner(
        runtimeFactory: { FakeRuntime(pool: pool) },
        keyFactory: Environment.keyFactory,
        snapshot: {
          now += 10
          return VoiceWhisperBenchmarkSystemSnapshot(
            availableMemoryBytes: snapshot.availableMemoryBytes,
            systemLowMemory: snapshot.systemLowMemory,
            pssBytes: snapshot.pssBytes + now,
            rssBytes: snapshot.rssBytes + now,
            nativeAllocatedBytes: snapshot.nativeAllocatedBytes,
            cpuTimeMillis: snapshot.cpuTimeMillis + now,
            energyCounterNwh: snapshot.energyCounterNwh.map { $0 + now },
            thermalStatus: snapshot.thermalStatus
          )
        },
        highPerformanceCoreCount: { 4 },
        verifyModel: { _ in },
        elapsedMillis: {
          now += 10
          return now
        },
        clockMillis: { 2_000 },
        store: store,
        plan: VoiceWhisperBenchmarkPlan(
          candidateAudioDurationsMillis: [3_000],
          candidateIterations: 2,
          stabilityAudioDurationMillis: 5_000,
          stabilityIterations: 3,
          abortIterations: 1
        )
      )
    }

    func audio() throws -> VoiceWhisperBenchmarkAudio {
      try VoiceWhisperBenchmarkAudio(
        version: "test-audio",
        pcm16: Array(repeating: 1, count: VoiceWhisperBenchmarkAudio.sampleRateHz * 5),
        expectedTokens: ["hello"],
        language: "en"
      )
    }

    func keyFactory(_ profile: VoiceWhisperModelProfile, _ audioVersion: String) -> VoiceWhisperBenchmarkKey {
      Environment.keyFactory(profile, audioVersion)
    }

    private static func keyFactory(
      _ profile: VoiceWhisperModelProfile,
      _ audioVersion: String
    ) -> VoiceWhisperBenchmarkKey {
      VoiceWhisperBenchmarkKey(
        manufacturer: "Apple",
        device: "iPhone",
        soc: "A17",
        osVersion: "17.0",
        appVersionCode: 1,
        whisperNativeVersion: "test",
        nativeBuildFingerprint: "test",
        modelProfileId: profile.id,
        modelSha256: profile.sha256,
        benchmarkAudioVersion: audioVersion
      )
    }
  }

  private final class FakeRuntimePool {
    var loadedThreads: [Int] = []
    var abortRequests = 0

    func rtf(for thread: Int, mode: VoiceWhisperExecutionMode) -> Double {
      if mode == .finalOnly {
        return thread == 2 ? 0.45 : 0.85
      }
      switch thread {
      case 2:
        return 0.40
      case 3:
        return 0.62
      default:
        return 0.95
      }
    }
  }

  private final class FakeRuntime: VoiceStatefulLocalWhisperRuntime {
    let pool: FakeRuntimePool
    var state: VoiceWhisperRuntimeState = .unloaded
    var currentProfile: VoiceWhisperModelProfile?
    var currentThread = 1

    init(pool: FakeRuntimePool) {
      self.pool = pool
    }

    func load(
      profile: VoiceWhisperModelProfile,
      options: VoiceWhisperLoadOptions
    ) async throws -> VoiceWhisperLoadedModel {
      currentProfile = profile
      currentThread = options.threadCount
      pool.loadedThreads.append(options.threadCount)
      state = .ready(
        VoiceWhisperLoadedModel(
          profile: profile,
          threadCount: options.threadCount,
          loadedAtMillis: 1_000,
          loadDurationMillis: Int64(100 + options.threadCount),
          warmUpTimings: VoiceNativeWhisperTimings(
            sampleMillis: 0,
            encodeMillis: 0,
            decodeMillis: 20,
            totalMillis: 20,
            audioMillis: 1_000,
            realTimeFactor: 0.02
          )
        )
      )
      return try currentLoaded()
    }

    func createSession(config: VoiceLocalWhisperSessionConfig) async throws -> VoiceLocalWhisperSession {
      FakeSession(thread: currentThread, config: config, pool: pool)
    }

    func unload(reason: VoiceWhisperUnloadReason) async {
      state = .unloaded
    }

    func runBenchmark(_ request: VoiceWhisperBenchmarkRequest) async throws -> VoiceWhisperBenchmarkResult {
      throw VoiceWhisperRuntimeFailure.modelNotLoaded
    }

    func requestAbortAll(_ reason: VoiceWhisperAbortReason) {
      pool.abortRequests += 1
    }

    func close() {
      state = .unloaded
    }

    private func currentLoaded() throws -> VoiceWhisperLoadedModel {
      guard case .ready(let loaded) = state else {
        throw VoiceWhisperRuntimeFailure.modelNotLoaded
      }
      return loaded
    }
  }

  private final class FakeSession: VoiceLocalWhisperSession {
    let id = UUID().uuidString
    let config: VoiceLocalWhisperSessionConfig
    let thread: Int
    let pool: FakeRuntimePool

    init(thread: Int, config: VoiceLocalWhisperSessionConfig, pool: FakeRuntimePool) {
      self.thread = thread
      self.config = config
      self.pool = pool
    }

    func decode(_ request: VoiceWhisperDecodeRequest) async throws -> VoiceNativeWhisperResult {
      let rtf = pool.rtf(for: thread, mode: request.mode)
      let audioMillis = Int64(request.length * 1_000 / request.sampleRateHz)
      return VoiceNativeWhisperResult(
        codeValue: VoiceNativeWhisperCode.ok.rawValue,
        segments: [
          VoiceNativeWhisperSegment(
            startMillis: 0,
            endMillis: audioMillis,
            text: "hello benchmark",
            averageLogProbability: -0.1,
            noSpeechProbability: 0.01
          )
        ],
        detectedLanguage: config.language,
        timings: VoiceNativeWhisperTimings(
          sampleMillis: 0,
          encodeMillis: 0,
          decodeMillis: Double(audioMillis) * rtf,
          totalMillis: Double(audioMillis) * rtf,
          audioMillis: audioMillis,
          realTimeFactor: rtf
        ),
        aborted: false,
        message: nil
      )
    }

    func requestAbort(_ reason: VoiceWhisperAbortReason) {
      pool.abortRequests += 1
    }

    func close() {}
  }
}

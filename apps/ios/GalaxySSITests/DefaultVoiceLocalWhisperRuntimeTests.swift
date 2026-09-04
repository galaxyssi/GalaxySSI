import XCTest
@testable import GalaxySSI

final class DefaultVoiceLocalWhisperRuntimeTests: XCTestCase {
  func testRuntimeOwnsSessionLifecycleAndStructuredDecode() async throws {
    let env = try Environment()
    let native = FakeNativeAPI()
    let runtime = env.runtime(native)

    let loaded = try await runtime.load(
      profile: VoiceWhisperModelCatalog.model("tiny"),
      options: try VoiceWhisperLoadOptions(warmUp: false)
    )
    let session = try await runtime.createSession(config: try VoiceLocalWhisperSessionConfig(language: "zh"))
    let result = try await session.decode(try VoiceWhisperDecodeRequest(pcm16: Array(repeating: 3, count: 16_000)))

    XCTAssertEqual(loaded.profile.id, "tiny")
    XCTAssertEqual(result.code, .ok)
    XCTAssertEqual(result.text, "test")
    XCTAssertEqual(native.runtimeCount, 1)
    XCTAssertEqual(native.sessionCount, 1)
    XCTAssertEqual(env.loadedModelIds, ["tiny"])
    if case .ready(let model) = runtime.state {
      XCTAssertEqual(model.profile.id, "tiny")
    } else {
      XCTFail("Expected ready runtime")
    }

    session.close()
    await runtime.unload(reason: .userRequest)
    XCTAssertEqual(native.runtimeCount, 0)
    XCTAssertEqual(native.sessionCount, 0)
    XCTAssertEqual(runtime.state, .unloaded)
    XCTAssertEqual(env.unloadedModelIds, [Optional("tiny")])
    runtime.close()
  }

  func testSwitchingModelsAbortsAndClosesExistingSessions() async throws {
    let env = try Environment()
    let native = FakeNativeAPI()
    let runtime = env.runtime(native)

    _ = try await runtime.load(profile: VoiceWhisperModelCatalog.model("tiny"), options: try VoiceWhisperLoadOptions(warmUp: false))
    _ = try await runtime.createSession(config: try VoiceLocalWhisperSessionConfig())
    _ = try await runtime.load(profile: VoiceWhisperModelCatalog.model("base"), options: try VoiceWhisperLoadOptions(warmUp: false))

    XCTAssertGreaterThan(native.abortCount, 0)
    XCTAssertEqual(native.runtimeCount, 1)
    XCTAssertEqual(native.sessionCount, 0)
    XCTAssertEqual(env.unloadedModelIds, [Optional("tiny")])
    if case .ready(let model) = runtime.state {
      XCTAssertEqual(model.profile.id, "base")
    } else {
      XCTFail("Expected base model to be ready")
    }
    runtime.close()
  }

  func testBenchmarkUsesFreshSessionsAndLeavesNoSessionHandles() async throws {
    let env = try Environment()
    let native = FakeNativeAPI()
    let runtime = env.runtime(native)
    _ = try await runtime.load(profile: VoiceWhisperModelCatalog.model("tiny"), options: try VoiceWhisperLoadOptions(warmUp: false))

    let result = try await runtime.runBenchmark(
      try VoiceWhisperBenchmarkRequest(pcm16: Array(repeating: 1, count: 1_600), iterations: 3)
    )

    XCTAssertEqual(result.iterations, 3)
    XCTAssertEqual(result.timings.count, 3)
    XCTAssertEqual(result.medianRealTimeFactor, 0.1, accuracy: 0.0001)
    XCTAssertEqual(native.sessionCount, 0)
    runtime.close()
    XCTAssertEqual(native.runtimeCount, 0)
  }

  func testTranscribeLoadsModelAndReleasesSession() async throws {
    let env = try Environment()
    let native = FakeNativeAPI()
    let runtime = env.runtime(native)

    let text = try await runtime.transcribe(
      VoiceLocalWhisperRuntimeRequest(
        model: VoiceWhisperModelCatalog.model("tiny"),
        modelFileURL: env.modelURL,
        language: "en",
        samples: Array(repeating: 0.25, count: 1_600),
        sampleRateHz: 16_000,
        threadCount: 2
      )
    )

    XCTAssertEqual(text, "test")
    XCTAssertEqual(native.runtimeCount, 1)
    XCTAssertEqual(native.sessionCount, 0)
    runtime.close()
  }

  func testPcmRequestRejectsUnsupportedRatesAndRanges() {
    XCTAssertThrowsError(try VoiceWhisperDecodeRequest(pcm16: Array(repeating: 1, count: 100), sampleRateHz: 48_000))
    XCTAssertThrowsError(try VoiceWhisperDecodeRequest(pcm16: Array(repeating: 1, count: 100), offset: 90, length: 20))
  }

  private final class Environment {
    let root: URL
    let modelURL: URL
    var loadedModelIds: [String] = []
    var unloadedModelIds: [String?] = []

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      modelURL = root.appendingPathComponent("ggml-test.bin", isDirectory: false)
      try Data("model".utf8).write(to: modelURL)
    }

    func runtime(_ native: FakeNativeAPI) -> DefaultVoiceLocalWhisperRuntime {
      var elapsed: Int64 = 1_000
      return DefaultVoiceLocalWhisperRuntime(
        modelResolver: { _ in self.modelURL },
        native: native,
        markModelLoaded: { self.loadedModelIds.append($0) },
        markModelUnloaded: { self.unloadedModelIds.append($0) },
        clockMillis: { 10_000 },
        elapsedMillis: {
          elapsed += 1
          return elapsed
        }
      )
    }
  }

  private final class FakeNativeAPI: VoiceWhisperNativeAPI {
    private var nextHandle: Int64 = 1
    private var runtimes = Set<Int64>()
    private var sessions = Set<Int64>()
    private(set) var abortCount = 0

    var runtimeCount: Int { runtimes.count }
    var sessionCount: Int { sessions.count }

    func createRuntime(modelPath: String, threadCount: Int, useGPU: Bool) -> Int64 {
      guard !modelPath.isEmpty, threadCount > 0, !useGPU else { return 0 }
      let handle = nextHandle
      nextHandle += 1
      runtimes.insert(handle)
      return handle
    }

    func createSession(runtimeHandle: Int64, config: VoiceLocalWhisperSessionConfig) -> Int64 {
      guard runtimes.contains(runtimeHandle) else { return 0 }
      let handle = nextHandle
      nextHandle += 1
      sessions.insert(handle)
      return handle
    }

    func decodePcm16(
      sessionHandle: Int64,
      pcm: [Int16],
      offset: Int,
      length: Int
    ) -> VoiceNativeWhisperResult {
      guard sessions.contains(sessionHandle) else {
        return .failure(.invalidHandle, message: "invalid")
      }
      return VoiceNativeWhisperResult(
        codeValue: VoiceNativeWhisperCode.ok.rawValue,
        segments: [
          VoiceNativeWhisperSegment(
            startMillis: 0,
            endMillis: 1_000,
            text: "test",
            averageLogProbability: -0.1,
            noSpeechProbability: 0
          ),
        ],
        detectedLanguage: "en",
        timings: VoiceNativeWhisperTimings(
          sampleMillis: 1,
          encodeMillis: 2,
          decodeMillis: 3,
          totalMillis: 100,
          audioMillis: 1_000,
          realTimeFactor: 0.1
        ),
        aborted: false,
        message: nil
      )
    }

    func requestAbort(sessionHandle: Int64) {
      if sessions.contains(sessionHandle) {
        abortCount += 1
      }
    }

    func getTimings(sessionHandle: Int64) -> VoiceNativeWhisperTimings { .empty }
    func destroySession(sessionHandle: Int64) { sessions.remove(sessionHandle) }
    func destroyRuntime(runtimeHandle: Int64) { runtimes.remove(runtimeHandle) }
    func activeRuntimeCount() -> Int { runtimeCount }
    func activeSessionCount() -> Int { sessionCount }
  }
}

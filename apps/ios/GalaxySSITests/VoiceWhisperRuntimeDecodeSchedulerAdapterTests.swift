import XCTest
@testable import GalaxySSI

final class VoiceWhisperRuntimeDecodeSchedulerAdapterTests: XCTestCase {
  func testAdapterLoadsProfileCreatesSessionAndClosesAfterDecode() async throws {
    let runtime = FakeSchedulerRuntime(result: Self.nativeResult("hello"))
    let adapter = VoiceWhisperRuntimeDecodeSchedulerAdapter(
      runtime: runtime,
      profileProvider: { VoiceWhisperModelCatalog.model($0) },
      threadCountProvider: { profile, request in
        XCTAssertEqual(profile.id, "base")
        XCTAssertEqual(request.requestId, "voice-1:1")
        return 3
      }
    )

    let result = try await adapter.decode(try Self.request(modelProfileId: "base", mode: .realtimePartial))

    XCTAssertEqual(result.text, "hello")
    XCTAssertEqual(runtime.loadedProfileIds, ["base"])
    XCTAssertEqual(runtime.loadedThreadCounts, [3])
    XCTAssertEqual(runtime.createdConfigs.first?.language, "en")
    XCTAssertEqual(runtime.createdConfigs.first?.mode, .realtimePartial)
    XCTAssertEqual(runtime.sessions.first?.decodeRequests.first?.mode, .realtimePartial)
    XCTAssertEqual(runtime.sessions.first?.decodeRequests.first?.pcm16.count, 1_600)
    XCTAssertEqual(runtime.sessions.first?.closeCount, 1)
  }

  func testFactorySchedulerCompletesDecodeThroughRuntime() async throws {
    let runtime = FakeSchedulerRuntime(result: Self.nativeResult("scheduled"))
    let adapter = VoiceWhisperRuntimeDecodeSchedulerAdapter(
      runtime: runtime,
      threadCountProvider: { _, _ in 2 }
    )
    let scheduler = adapter.makeScheduler()
    defer { scheduler.close() }

    let request = try Self.request(modelProfileId: "tiny", mode: .finalOnly)
    let result = await scheduler.submit(request)

    guard case .completed(_, let native) = result else {
      return XCTFail("Expected scheduled decode to complete")
    }
    XCTAssertEqual(native.text, "scheduled")
    XCTAssertEqual(runtime.loadedProfileIds, ["tiny"])
    XCTAssertEqual(runtime.loadedThreadCounts, [2])
    XCTAssertEqual(runtime.sessions.first?.decodeRequests.first?.mode, .finalOnly)
  }

  func testFactorySchedulerRetainsAdapterForDecodeLifetime() async throws {
    let runtime = FakeSchedulerRuntime(result: Self.nativeResult("retained"))
    let scheduler = VoiceWhisperRuntimeDecodeSchedulerAdapter(
      runtime: runtime,
      threadCountProvider: { _, _ in 1 }
    ).makeScheduler()
    defer { scheduler.close() }

    let request = try Self.request(modelProfileId: "tiny", mode: .finalOnly)
    let result = await scheduler.submit(request)

    guard case .completed(_, let native) = result else {
      return XCTFail("Expected scheduler to keep adapter alive for decode")
    }
    XCTAssertEqual(native.text, "retained")
    XCTAssertEqual(runtime.loadedProfileIds, ["tiny"])
  }

  func testAbortForwardingUsesStatefulRuntimeAbortAll() {
    let runtime = FakeSchedulerRuntime(result: Self.nativeResult("unused"))
    let adapter = VoiceWhisperRuntimeDecodeSchedulerAdapter(runtime: runtime)

    adapter.requestAbort(.newUtterance)

    XCTAssertEqual(runtime.abortReasons, [.newUtterance])
  }

  private static func request(
    modelProfileId: String,
    mode: VoiceWhisperExecutionMode
  ) throws -> VoiceScheduledWhisperDecode {
    try VoiceScheduledWhisperDecode(
      requestId: "voice-1:1",
      voiceSessionId: "voice-1",
      revision: 1,
      modelProfileId: modelProfileId,
      pcm16: Array(repeating: Int16(4), count: 1_600),
      sampleRateHz: 16_000,
      language: "en",
      mode: mode,
      priority: mode == .finalOnly ? .currentFinal : .currentPartial,
      windowStartSample: 0,
      windowEndSampleExclusive: 1_600
    )
  }

  private static func nativeResult(_ text: String) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult(
      codeValue: VoiceNativeWhisperCode.ok.rawValue,
      segments: [
        VoiceNativeWhisperSegment(
          startMillis: 0,
          endMillis: 100,
          text: text,
          averageLogProbability: -0.1,
          noSpeechProbability: 0
        )
      ],
      detectedLanguage: "en",
      timings: VoiceNativeWhisperTimings(
        sampleMillis: 1,
        encodeMillis: 2,
        decodeMillis: 3,
        totalMillis: 25,
        audioMillis: 100,
        realTimeFactor: 0.25
      ),
      aborted: false,
      message: nil
    )
  }
}

private final class FakeSchedulerRuntime: VoiceStatefulLocalWhisperRuntime {
  private let result: VoiceNativeWhisperResult
  private(set) var state: VoiceWhisperRuntimeState = .unloaded
  private(set) var loadedProfileIds: [String] = []
  private(set) var loadedThreadCounts: [Int] = []
  private(set) var createdConfigs: [VoiceLocalWhisperSessionConfig] = []
  private(set) var sessions: [FakeSchedulerSession] = []
  private(set) var abortReasons: [VoiceWhisperAbortReason] = []

  init(result: VoiceNativeWhisperResult) {
    self.result = result
  }

  func load(
    profile: VoiceWhisperModelProfile,
    options: VoiceWhisperLoadOptions
  ) async throws -> VoiceWhisperLoadedModel {
    loadedProfileIds.append(profile.id)
    loadedThreadCounts.append(options.threadCount)
    let loaded = VoiceWhisperLoadedModel(
      profile: profile,
      threadCount: options.threadCount,
      loadedAtMillis: 1_000,
      loadDurationMillis: 2,
      warmUpTimings: nil
    )
    state = .ready(loaded)
    return loaded
  }

  func createSession(config: VoiceLocalWhisperSessionConfig) async throws -> VoiceLocalWhisperSession {
    createdConfigs.append(config)
    let session = FakeSchedulerSession(config: config, result: result)
    sessions.append(session)
    return session
  }

  func unload(reason: VoiceWhisperUnloadReason) async {
    state = .unloaded
  }

  func runBenchmark(_ request: VoiceWhisperBenchmarkRequest) async throws -> VoiceWhisperBenchmarkResult {
    VoiceWhisperBenchmarkResult(
      profileId: loadedProfileIds.last ?? "tiny",
      iterations: 0,
      timings: [],
      medianRealTimeFactor: 0
    )
  }

  func requestAbortAll(_ reason: VoiceWhisperAbortReason) {
    abortReasons.append(reason)
    sessions.forEach { $0.requestAbort(reason) }
  }

  func close() {
    state = .unloaded
  }
}

private final class FakeSchedulerSession: VoiceLocalWhisperSession {
  let id = "session-1"
  let config: VoiceLocalWhisperSessionConfig
  private let result: VoiceNativeWhisperResult
  private(set) var decodeRequests: [VoiceWhisperDecodeRequest] = []
  private(set) var abortReasons: [VoiceWhisperAbortReason] = []
  private(set) var closeCount = 0

  init(
    config: VoiceLocalWhisperSessionConfig,
    result: VoiceNativeWhisperResult
  ) {
    self.config = config
    self.result = result
  }

  func decode(_ request: VoiceWhisperDecodeRequest) async throws -> VoiceNativeWhisperResult {
    decodeRequests.append(request)
    return result
  }

  func requestAbort(_ reason: VoiceWhisperAbortReason) {
    abortReasons.append(reason)
  }

  func close() {
    closeCount += 1
  }
}

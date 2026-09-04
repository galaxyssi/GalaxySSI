import XCTest
@testable import GalaxySSI

final class VoiceLiveWhisperTranscriptionSessionTests: XCTestCase {
  func testPartialsRemainProvisionalAndFinalCanOnlyBeRequestedOnce() async throws {
    let profile = VoiceWhisperModelCatalog.model("tiny")
    let clock = LiveWhisperClock(1_000)
    let updates = LiveWhisperLockedValues<VoiceLiveWhisperTranscriptUpdate>()
    let finalRuns = LiveWhisperLockedInt()
    let scheduler = FakeLiveWhisperScheduler { request in
      if request.isFinal {
        finalRuns.increment()
      }
      return .completed(
        request: request,
        native: Self.nativeResult(request.isFinal ? "hello world" : "hello")
      )
    }
    let session = VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: "voice-1",
      profile: profile,
      language: "en",
      scheduler: scheduler,
      elapsedClock: clock.now,
      onUpdate: { updates.append($0) }
    )
    defer { session.close() }

    XCTAssertEqual(
      session.nextPartialWindowMillis(capturedAudioMillis: 1_000),
      profile.maxWindowMillis
    )
    session.offerPartial(Self.snapshot(16_000))
    await waitUntil { updates.values.count == 1 }
    clock.set(2_000)
    XCTAssertNotNil(session.nextPartialWindowMillis(capturedAudioMillis: 2_000))
    session.offerPartial(Self.snapshot(32_000))
    await waitUntil { updates.values.count == 2 }

    let final = try await session.finish(Self.snapshot(32_000))

    XCTAssertEqual(final.text, "hello world")
    XCTAssertEqual(finalRuns.value, 1)
    XCTAssertTrue(updates.values.contains { !$0.transcript.final })
    XCTAssertEqual(updates.values.last?.transcript.final, true)
    XCTAssertEqual(updates.values.last?.transcript.unstableText, "")
    do {
      _ = try await session.finish(Self.snapshot(32_000))
      XCTFail("Expected duplicate final request to fail")
    } catch {
      XCTAssertEqual(error as? VoiceLiveWhisperTranscriptionSessionFailure, .finalAlreadyRequested)
    }
    XCTAssertEqual(finalRuns.value, 1)
  }

  func testNoSpeechSnapshotDoesNotSubmitPartial() async {
    let scheduler = FakeLiveWhisperScheduler { request in
      .completed(request: request, native: Self.nativeResult("unused"))
    }
    let session = VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: "voice-1",
      profile: VoiceWhisperModelCatalog.model("tiny"),
      language: "en",
      scheduler: scheduler,
      elapsedClock: { 1_000 },
      onUpdate: { _ in XCTFail("No update should be emitted without speech") }
    )
    defer { session.close() }

    session.offerPartial(Self.snapshot(16_000, speechDetected: false))
    await Task.yield()

    XCTAssertEqual(scheduler.submittedCount, 0)
  }

  func testCloseCancelsSessionAndBlocksFurtherPartials() async {
    let scheduler = FakeLiveWhisperScheduler { request in
      .completed(request: request, native: Self.nativeResult("unused"))
    }
    let session = VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: "voice-1",
      profile: VoiceWhisperModelCatalog.model("tiny"),
      language: "en",
      scheduler: scheduler,
      elapsedClock: { 1_000 },
      onUpdate: { _ in XCTFail("Closed sessions should not emit partial updates") }
    )

    session.close()
    session.offerPartial(Self.snapshot(16_000))
    await Task.yield()

    XCTAssertEqual(scheduler.cancelledSessions, ["voice-1"])
    XCTAssertNil(session.nextPartialWindowMillis(capturedAudioMillis: 1_000))
    XCTAssertEqual(scheduler.submittedCount, 0)
  }

  func testDroppedFinalMapsToSessionFailure() async throws {
    let scheduler = FakeLiveWhisperScheduler { request in
      .dropped(request: request, reason: .schedulerClosed)
    }
    let session = VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: "voice-1",
      profile: VoiceWhisperModelCatalog.model("tiny"),
      language: "en",
      scheduler: scheduler,
      elapsedClock: { 1_000 },
      onUpdate: { _ in XCTFail("Dropped final should not emit an update") }
    )
    defer { session.close() }

    do {
      _ = try await session.finish(Self.snapshot(16_000))
      XCTFail("Expected dropped final to fail")
    } catch {
      XCTAssertEqual(
        error as? VoiceLiveWhisperTranscriptionSessionFailure,
        .finalDecodeDropped(.schedulerClosed)
      )
    }
  }

  private static func snapshot(
    _ sampleCount: Int,
    speechDetected: Bool = true
  ) -> PcmSnapshot {
    PcmSnapshot(
      samples: Array(repeating: Int16(10), count: sampleCount),
      sampleRateHz: 16_000,
      speechDetected: speechDetected,
      speechStartSample: speechDetected ? 0 : nil,
      speechEndSampleExclusive: speechDetected ? Int64(sampleCount) : nil,
      captureStartSample: 0,
      captureEndSampleExclusive: Int64(sampleCount)
    )
  }

  private static func nativeResult(_ text: String) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult(
      codeValue: VoiceNativeWhisperCode.ok.rawValue,
      segments: [
        VoiceNativeWhisperSegment(
          startMillis: 0,
          endMillis: 700,
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
        totalMillis: 50,
        audioMillis: 1_000,
        realTimeFactor: 0.05
      ),
      aborted: false,
      message: nil
    )
  }

  private func waitUntil(
    _ condition: @escaping () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<200 {
      if condition() {
        return
      }
      await Task.yield()
    }
    XCTFail("Condition was not satisfied", file: file, line: line)
  }
}

private final class FakeLiveWhisperScheduler: VoiceWhisperDecodeScheduling {
  private let lock = NSLock()
  private let handler: (VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult
  private var submitted: [VoiceScheduledWhisperDecode] = []
  private var cancelled: [String] = []

  init(handler: @escaping (VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult) {
    self.handler = handler
  }

  var submittedCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return submitted.count
  }

  var cancelledSessions: [String] {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func submit(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult {
    lock.lock()
    submitted.append(request)
    lock.unlock()
    return await handler(request)
  }

  func cancelSession(_ sessionId: String) {
    lock.lock()
    cancelled.append(sessionId)
    lock.unlock()
  }

  func queueSnapshot() -> VoiceWhisperDecodeQueueSnapshot {
    VoiceWhisperDecodeQueueSnapshot()
  }

  func close() {}
}

private final class LiveWhisperClock {
  private let lock = NSLock()
  private var value: Int64

  init(_ value: Int64) {
    self.value = value
  }

  func now() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: Int64) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}

private final class LiveWhisperLockedInt {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func increment() {
    lock.lock()
    storage += 1
    lock.unlock()
  }
}

private final class LiveWhisperLockedValues<Value: Equatable> {
  private let lock = NSLock()
  private var storage: [Value] = []

  var values: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func append(_ value: Value) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }
}

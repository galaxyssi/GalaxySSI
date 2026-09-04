import XCTest
@testable import GalaxySSI

final class VoiceWhisperDecodeSchedulerTests: XCTestCase {
  func testFinalAbortsActivePartialAndRunsExactlyOnce() async throws {
    let partialStarted = AsyncGate()
    let partialAbort = AsyncGate()
    let finalRuns = LockedInt()
    let aborts = LockedValues<VoiceWhisperAbortReason>()
    let scheduler = VoiceWhisperDecodeScheduler(
      decoder: { request in
        if request.mode == .realtimePartial {
          partialStarted.open()
          await partialAbort.wait()
          return Self.failure(.aborted, message: "cancelled")
        }
        finalRuns.increment()
        return Self.success("final")
      },
      abortActive: { reason in
        aborts.append(reason)
        partialAbort.open()
      }
    )
    defer { scheduler.close() }

    let partialRequest = try Self.request("partial", priority: .currentPartial)
    let finalRequest = try Self.request("final", priority: .currentFinal)
    let partial = Task {
      await scheduler.submit(partialRequest)
    }
    await partialStarted.wait()
    let final = Task {
      await scheduler.submit(finalRequest)
    }

    guard case .dropped(_, .nativeAborted) = await partial.value else {
      return XCTFail("Expected active partial to be dropped after native abort")
    }
    guard case .completed(_, let native) = await final.value else {
      return XCTFail("Expected final decode to complete")
    }
    XCTAssertEqual(native.text, "final")
    XCTAssertEqual(finalRuns.value, 1)
    XCTAssertEqual(aborts.values, [.upstreamFinalSelected])
    XCTAssertEqual(scheduler.queueSnapshot().queued, 0)
  }

  func testFinalForDifferentSessionDoesNotAbortActivePartial() async throws {
    let partialStarted = AsyncGate()
    let releasePartial = AsyncGate()
    let aborts = LockedValues<VoiceWhisperAbortReason>()
    let scheduler = VoiceWhisperDecodeScheduler(
      decoder: { request in
        if request.mode == .realtimePartial {
          partialStarted.open()
          await releasePartial.wait()
        }
        return Self.success(request.requestId)
      },
      abortActive: { reason in
        aborts.append(reason)
        releasePartial.open()
      }
    )
    defer { scheduler.close() }

    let partialRequest = try Self.request(
      "partial-other-session",
      voiceSessionId: "voice-2",
      priority: .currentPartial
    )
    let finalRequest = try Self.request("final", priority: .currentFinal)
    let partial = Task {
      await scheduler.submit(partialRequest)
    }
    await partialStarted.wait()
    let final = Task {
      await scheduler.submit(finalRequest)
    }
    await waitUntil { scheduler.queueSnapshot().queued == 1 }

    XCTAssertEqual(aborts.values, [])
    releasePartial.open()
    guard case .completed(_, let partialNative) = await partial.value else {
      return XCTFail("Expected other-session partial to complete normally")
    }
    guard case .completed(_, let finalNative) = await final.value else {
      return XCTFail("Expected final request to run after active partial")
    }
    XCTAssertEqual(partialNative.text, "partial-other-session")
    XCTAssertEqual(finalNative.text, "final")
  }

  func testBoundedQueueRejectsLowerPriorityWork() async throws {
    let activeStarted = AsyncGate()
    let releaseActive = AsyncGate()
    let scheduler = VoiceWhisperDecodeScheduler(
      maxQueueSize: 1,
      decoder: { request in
        if request.requestId == "active" {
          activeStarted.open()
          await releaseActive.wait()
        }
        return Self.success(request.requestId)
      }
    )
    defer { scheduler.close() }

    let activeRequest = try Self.request("active", priority: .currentPartial)
    let queuedRequest = try Self.request("queued", priority: .currentPartial)
    let backgroundRequest = try Self.request("background", priority: .background)
    let active = Task {
      await scheduler.submit(activeRequest)
    }
    await activeStarted.wait()
    let queued = Task {
      await scheduler.submit(queuedRequest)
    }
    await waitUntil { scheduler.queueSnapshot().queued == 1 }

    let rejected = await scheduler.submit(backgroundRequest)
    guard case .dropped(_, .queueCapacity) = rejected else {
      return XCTFail("Expected background work to be rejected by queue capacity")
    }

    releaseActive.open()
    guard case .completed(_, _) = await active.value else {
      return XCTFail("Expected active request to complete")
    }
    guard case .completed(_, let native) = await queued.value else {
      return XCTFail("Expected queued request to complete")
    }
    XCTAssertEqual(native.text, "queued")
  }

  func testCancelSessionDropsQueuedWorkAndAbortsActiveWork() async throws {
    let activeStarted = AsyncGate()
    let releaseActive = AsyncGate()
    let aborts = LockedValues<VoiceWhisperAbortReason>()
    let scheduler = VoiceWhisperDecodeScheduler(
      decoder: { request in
        if request.requestId == "active" {
          activeStarted.open()
          await releaseActive.wait()
          return Self.failure(.aborted, message: "cancelled")
        }
        return Self.success(request.requestId)
      },
      abortActive: { reason in
        aborts.append(reason)
        releaseActive.open()
      }
    )
    defer { scheduler.close() }

    let activeRequest = try Self.request("active", priority: .currentPartial)
    let queuedRequest = try Self.request("queued", priority: .currentPartial)
    let active = Task {
      await scheduler.submit(activeRequest)
    }
    await activeStarted.wait()
    let queued = Task {
      await scheduler.submit(queuedRequest)
    }
    await waitUntil { scheduler.queueSnapshot().queued == 1 }

    scheduler.cancelSession("voice-1")

    guard case .dropped(_, .sessionCancelled) = await queued.value else {
      return XCTFail("Expected queued request to be session-cancelled")
    }
    guard case .dropped(_, .nativeAborted) = await active.value else {
      return XCTFail("Expected active request to report native abort")
    }
    XCTAssertEqual(aborts.values, [.sessionClosed])
  }

  func testCloseDropsQueuedAndActiveWork() async throws {
    let activeStarted = AsyncGate()
    let releaseActive = AsyncGate()
    let scheduler = VoiceWhisperDecodeScheduler(
      decoder: { request in
        if request.requestId == "active" {
          activeStarted.open()
          await releaseActive.wait()
        }
        return Self.success(request.requestId)
      },
      abortActive: { _ in releaseActive.open() }
    )

    let activeRequest = try Self.request("active", priority: .currentPartial)
    let queuedRequest = try Self.request("queued", priority: .currentPartial)
    let active = Task {
      await scheduler.submit(activeRequest)
    }
    await activeStarted.wait()
    let queued = Task {
      await scheduler.submit(queuedRequest)
    }
    await waitUntil { scheduler.queueSnapshot().queued == 1 }

    scheduler.close()

    guard case .dropped(_, .schedulerClosed) = await active.value else {
      return XCTFail("Expected active request to be closed")
    }
    guard case .dropped(_, .schedulerClosed) = await queued.value else {
      return XCTFail("Expected queued request to be closed")
    }
    XCTAssertEqual(scheduler.queueSnapshot().dropped, 2)
  }

  private static func request(
    _ id: String,
    voiceSessionId: String = "voice-1",
    priority: VoiceWhisperDecodePriority
  ) throws -> VoiceScheduledWhisperDecode {
    let revision = max(id.utf8.reduce(0) { ($0 + Int($1)) % 1_000_000 }, 1)
    try VoiceScheduledWhisperDecode(
      requestId: id,
      voiceSessionId: voiceSessionId,
      revision: revision,
      modelProfileId: "tiny",
      pcm16: Array(repeating: 1, count: 1_600),
      mode: priority == .currentFinal ? .finalOnly : .realtimePartial,
      priority: priority
    )
  }

  private static func success(_ text: String) -> VoiceNativeWhisperResult {
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
        totalMillis: 50,
        audioMillis: 100,
        realTimeFactor: 0.5
      ),
      aborted: false,
      message: nil
    )
  }

  private static func failure(
    _ code: VoiceNativeWhisperCode,
    message: String
  ) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult.failure(code, message: message)
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

private final class AsyncGate {
  private let lock = NSLock()
  private var opened = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if opened {
        lock.unlock()
        continuation.resume()
      } else {
        continuations.append(continuation)
        lock.unlock()
      }
    }
  }

  func open() {
    lock.lock()
    guard !opened else {
      lock.unlock()
      return
    }
    opened = true
    let waiting = continuations
    continuations.removeAll()
    lock.unlock()
    waiting.forEach { $0.resume() }
  }
}

private final class LockedInt {
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

private final class LockedValues<Value: Equatable> {
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

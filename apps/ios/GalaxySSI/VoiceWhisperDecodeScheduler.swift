import Foundation

enum VoiceWhisperDecodePriority: Int, Codable, CaseIterable, Equatable {
  case currentFinal = 0
  case currentPartial = 1
  case accuracyReview = 2
  case secondPass = 3
  case benchmark = 4
  case background = 5

  var rank: Int { rawValue }
}

struct VoiceScheduledWhisperDecode: Equatable {
  var requestId: String
  var voiceSessionId: String
  var revision: Int
  var modelProfileId: String
  var pcm16: [Int16]
  var sampleRateHz: Int
  var language: String
  var threadCount: Int?
  var mode: VoiceWhisperExecutionMode
  var priority: VoiceWhisperDecodePriority
  var windowStartSample: Int64
  var windowEndSampleExclusive: Int64

  init(
    requestId: String,
    voiceSessionId: String,
    revision: Int,
    modelProfileId: String,
    pcm16: [Int16],
    sampleRateHz: Int = 16_000,
    language: String = "zh",
    threadCount: Int? = nil,
    mode: VoiceWhisperExecutionMode,
    priority: VoiceWhisperDecodePriority,
    windowStartSample: Int64 = 0,
    windowEndSampleExclusive: Int64? = nil
  ) throws {
    let cleanRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanSessionId = voiceSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanModelId = modelProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedEnd = windowEndSampleExclusive ?? (windowStartSample + Int64(pcm16.count))
    let validThreadCount = threadCount.map { (1...16).contains($0) } ?? true
    guard !cleanRequestId.isEmpty,
          !cleanSessionId.isEmpty,
          revision > 0,
          !cleanModelId.isEmpty,
          !pcm16.isEmpty,
          sampleRateHz == 16_000,
          validThreadCount,
          windowStartSample >= 0,
          resolvedEnd >= windowStartSample + Int64(pcm16.count) else {
      throw VoiceWhisperDecodeSchedulerFailure.invalidRequest
    }
    self.requestId = cleanRequestId
    self.voiceSessionId = cleanSessionId
    self.revision = revision
    self.modelProfileId = cleanModelId
    self.pcm16 = pcm16
    self.sampleRateHz = sampleRateHz
    self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("zh")
    self.threadCount = threadCount
    self.mode = mode
    self.priority = priority
    self.windowStartSample = windowStartSample
    self.windowEndSampleExclusive = resolvedEnd
  }

  var isFinal: Bool {
    priority == .currentFinal
  }
}

enum VoiceWhisperDecodeDropReason: String, Codable, Equatable {
  case supersededByFinal = "SUPERSEDED_BY_FINAL"
  case sessionCancelled = "SESSION_CANCELLED"
  case queueCapacity = "QUEUE_CAPACITY"
  case schedulerClosed = "SCHEDULER_CLOSED"
  case nativeAborted = "NATIVE_ABORTED"
}

struct VoiceWhisperDecodeSchedulerFailure: Error, Equatable {
  var code: VoiceNativeWhisperCode?
  var message: String

  static let invalidRequest = VoiceWhisperDecodeSchedulerFailure(
    code: nil,
    message: "Scheduled Whisper decode request is invalid"
  )
}

enum VoiceScheduledWhisperResult: Equatable {
  case completed(request: VoiceScheduledWhisperDecode, native: VoiceNativeWhisperResult)
  case dropped(request: VoiceScheduledWhisperDecode, reason: VoiceWhisperDecodeDropReason)
  case failed(request: VoiceScheduledWhisperDecode, error: VoiceWhisperDecodeSchedulerFailure)

  var request: VoiceScheduledWhisperDecode {
    switch self {
    case .completed(let request, _), .dropped(let request, _), .failed(let request, _):
      return request
    }
  }
}

typealias VoiceScheduledWhisperDecoder = (VoiceScheduledWhisperDecode) async throws -> VoiceNativeWhisperResult
typealias VoiceWhisperDecodeAbortHandler = (VoiceWhisperAbortReason) -> Void

protocol VoiceWhisperDecodeScheduling: AnyObject {
  func submit(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult
  func cancelSession(_ sessionId: String)
  func queueSnapshot() -> VoiceWhisperDecodeQueueSnapshot
  func close()
}

final class VoiceWhisperDecodeScheduler: VoiceWhisperDecodeScheduling {
  private final class Queued {
    let sequence: Int64
    let request: VoiceScheduledWhisperDecode
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VoiceScheduledWhisperResult, Never>?
    private var completed = false

    init(
      sequence: Int64,
      request: VoiceScheduledWhisperDecode,
      continuation: CheckedContinuation<VoiceScheduledWhisperResult, Never>
    ) {
      self.sequence = sequence
      self.request = request
      self.continuation = continuation
    }

    func complete(_ result: VoiceScheduledWhisperResult) {
      lock.lock()
      guard !completed, let continuation else {
        lock.unlock()
        return
      }
      completed = true
      self.continuation = nil
      lock.unlock()
      continuation.resume(returning: result)
    }
  }

  private let maxQueueSize: Int
  private let decoder: VoiceScheduledWhisperDecoder
  private let abortActive: VoiceWhisperDecodeAbortHandler
  private let lock = NSLock()
  private var nextSequence: Int64 = 0
  private var pending: [Queued] = []
  private var active: Queued?
  private var closed = false
  private var workerRunning = false
  private var droppedCount: Int64 = 0

  init(
    maxQueueSize: Int = 8,
    decoder: @escaping VoiceScheduledWhisperDecoder,
    abortActive: @escaping VoiceWhisperDecodeAbortHandler = { _ in }
  ) {
    precondition((1...64).contains(maxQueueSize), "maxQueueSize must be between 1 and 64")
    self.maxQueueSize = maxQueueSize
    self.decoder = decoder
    self.abortActive = abortActive
  }

  func submit(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult {
    await withCheckedContinuation { continuation in
      var dropped: [(Queued, VoiceWhisperDecodeDropReason)] = []
      var abortCurrent = false
      var startWorker = false

      lock.lock()
      if closed {
        lock.unlock()
        continuation.resume(returning: .dropped(request: request, reason: .schedulerClosed))
        return
      }

      let queued = Queued(sequence: nextSequence, request: request, continuation: continuation)
      nextSequence += 1

      if request.isFinal {
        let superseded = pending.filter {
          $0.request.voiceSessionId == request.voiceSessionId &&
            $0.request.mode == .realtimePartial
        }
        pending.removeAll {
          $0.request.voiceSessionId == request.voiceSessionId &&
            $0.request.mode == .realtimePartial
        }
        dropped += superseded.map { ($0, .supersededByFinal) }
        abortCurrent = active?.request.voiceSessionId == request.voiceSessionId &&
          active?.request.mode == .realtimePartial
      }

      if pending.count >= maxQueueSize {
        if let replaceableIndex = replaceableQueueIndexLocked(),
           pending[replaceableIndex].request.priority.rank > request.priority.rank {
          let replaced = pending.remove(at: replaceableIndex)
          dropped.append((replaced, .queueCapacity))
        } else {
          droppedCount += 1
          lock.unlock()
          continuation.resume(returning: .dropped(request: request, reason: .queueCapacity))
          return
        }
      }

      pending.append(queued)
      droppedCount += Int64(dropped.count)
      if !workerRunning {
        workerRunning = true
        startWorker = true
      }
      lock.unlock()

      dropped.forEach { queued, reason in
        queued.complete(.dropped(request: queued.request, reason: reason))
      }
      if abortCurrent {
        abortActive(.upstreamFinalSelected)
      }
      if startWorker {
        _ = Task { await self.workerLoop() }
      }
    }
  }

  func cancelSession(_ sessionId: String) {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanSessionId.isEmpty else { return }
    let cancelled: [Queued]
    let abortCurrent: Bool
    lock.lock()
    cancelled = pending.filter { $0.request.voiceSessionId == cleanSessionId }
    pending.removeAll { $0.request.voiceSessionId == cleanSessionId }
    abortCurrent = active?.request.voiceSessionId == cleanSessionId
    droppedCount += Int64(cancelled.count)
    lock.unlock()

    cancelled.forEach {
      $0.complete(.dropped(request: $0.request, reason: .sessionCancelled))
    }
    if abortCurrent {
      abortActive(.sessionClosed)
    }
  }

  func queueSnapshot() -> VoiceWhisperDecodeQueueSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return VoiceWhisperDecodeQueueSnapshot(
      activeRequestId: active?.request.requestId,
      activeSessionId: active?.request.voiceSessionId,
      activeMode: active?.request.mode,
      queued: pending.count,
      queuedPartials: pending.filter { $0.request.mode == .realtimePartial }.count,
      dropped: droppedCount
    )
  }

  func close() {
    let abandoned: [Queued]
    let running: Queued?
    lock.lock()
    if closed {
      lock.unlock()
      return
    }
    closed = true
    abandoned = pending
    pending.removeAll()
    running = active
    active = nil
    workerRunning = false
    droppedCount += Int64(abandoned.count + (running == nil ? 0 : 1))
    lock.unlock()

    abandoned.forEach {
      $0.complete(.dropped(request: $0.request, reason: .schedulerClosed))
    }
    if let running {
      running.complete(.dropped(request: running.request, reason: .schedulerClosed))
      abortActive(.sessionClosed)
    }
  }

  private func workerLoop() async {
    while true {
      guard let next = nextQueuedRequest() else {
        return
      }
      let result = await decode(next.request)
      let shouldComplete: Bool
      lock.lock()
      if active === next {
        active = nil
        shouldComplete = true
      } else {
        shouldComplete = false
      }
      lock.unlock()
      if shouldComplete {
        next.complete(result)
      }
    }
  }

  private func nextQueuedRequest() -> Queued? {
    lock.lock()
    defer { lock.unlock() }
    guard let index = nextQueueIndexLocked() else {
      workerRunning = false
      return nil
    }
    let queued = pending.remove(at: index)
    active = queued
    return queued
  }

  private func decode(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult {
    do {
      let native = try await decoder(request)
      if native.code == .aborted {
        return .dropped(request: request, reason: .nativeAborted)
      }
      if native.successful {
        return .completed(request: request, native: native)
      }
      return .failed(
        request: request,
        error: VoiceWhisperDecodeSchedulerFailure(
          code: native.code,
          message: native.message ?? "Whisper decode failed"
        )
      )
    } catch {
      return .failed(
        request: request,
        error: VoiceWhisperDecodeSchedulerFailure(
          code: nil,
          message: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        )
      )
    }
  }

  private func nextQueueIndexLocked() -> Int? {
    pending.indices.min { leftIndex, rightIndex in
      let left = pending[leftIndex]
      let right = pending[rightIndex]
      if left.request.priority.rank != right.request.priority.rank {
        return left.request.priority.rank < right.request.priority.rank
      }
      return left.sequence < right.sequence
    }
  }

  private func replaceableQueueIndexLocked() -> Int? {
    pending.indices.max { leftIndex, rightIndex in
      let left = pending[leftIndex]
      let right = pending[rightIndex]
      if left.request.priority.rank != right.request.priority.rank {
        return left.request.priority.rank < right.request.priority.rank
      }
      return left.sequence < right.sequence
    }
  }
}

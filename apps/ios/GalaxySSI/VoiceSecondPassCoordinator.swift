import Foundation

struct VoiceSecondPassRequest: Equatable {
  var sessionId: String
  var pcm16: [Int16]
  var sampleRateHz: Int
  var language: String
  var fast: TranscriptHypothesis
  var accurateProfileId: String
  var accurateModelSha256: String
  var mode: VoiceWhisperExecutionMode
  var requestedAtMillis: Int64

  init(
    sessionId: String,
    pcm16: [Int16],
    sampleRateHz: Int,
    language: String,
    fast: TranscriptHypothesis,
    accurateProfileId: String,
    accurateModelSha256: String,
    mode: VoiceWhisperExecutionMode = .secondPass,
    requestedAtMillis: Int64 = VoiceSecondPassRequest.defaultNowMillis()
  ) {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanProfileId = accurateProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanSha = accurateModelSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    precondition(!cleanSessionId.isEmpty)
    precondition(!pcm16.isEmpty)
    precondition(sampleRateHz == 16_000)
    precondition(!cleanProfileId.isEmpty)
    precondition(cleanSha.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    precondition(mode == .secondPass || mode == .finalOnly)
    self.sessionId = cleanSessionId
    self.pcm16 = pcm16
    self.sampleRateHz = sampleRateHz
    self.language = language
    self.fast = fast
    self.accurateProfileId = cleanProfileId
    self.accurateModelSha256 = cleanSha
    self.mode = mode
    self.requestedAtMillis = max(requestedAtMillis, 0)
  }

  func frozenCopy() -> VoiceSecondPassRequest {
    self
  }

  mutating func wipePcm() {
    guard !pcm16.isEmpty else { return }
    pcm16 = Array(repeating: 0, count: pcm16.count)
  }

  private static func defaultNowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

struct VoiceSecondPassMetadata: Equatable {
  var sessionId: String
  var fast: TranscriptHypothesis
  var accurateProfileId: String
  var accurateModelSha256: String
  var mode: VoiceWhisperExecutionMode
  var requestedAtMillis: Int64
}

struct VoiceSecondPassResult: Equatable {
  var metadata: VoiceSecondPassMetadata
  var accurate: TranscriptHypothesis
  var diff: TranscriptDiff
  var decision: CorrectionDecision
  var completedAtMillis: Int64
}

typealias VoiceSecondPassDecoder = (VoiceSecondPassRequest) async throws -> TranscriptHypothesis
typealias VoiceSecondPassResultHandler = (VoiceSecondPassResult) -> Void
typealias VoiceSecondPassFailureHandler = (Error) -> Void

final class VoiceSecondPassCoordinator {
  private let correctionController: TranscriptCorrectionController
  private let entityChecker: EntityConsistencyChecking
  private let clock: () -> Int64
  private let lock = NSLock()
  private var tasks: [String: Task<Void, Never>] = [:]

  init(
    correctionController: TranscriptCorrectionController = DefaultTranscriptCorrectionController(),
    entityChecker: EntityConsistencyChecking = DefaultEntityConsistencyChecker(),
    clock: @escaping () -> Int64 = VoiceSecondPassCoordinator.defaultNowMillis
  ) {
    self.correctionController = correctionController
    self.entityChecker = entityChecker
    self.clock = clock
  }

  func schedule(
    request: VoiceSecondPassRequest,
    executionLedger: VoiceExecutionLedger,
    decoder: @escaping VoiceSecondPassDecoder,
    onResult: @escaping VoiceSecondPassResultHandler,
    onFailure: @escaping VoiceSecondPassFailureHandler = { _ in }
  ) -> Bool {
    let frozen = request.frozenCopy()
    return locked {
      guard tasks[frozen.sessionId] == nil else { return false }
      let task = Task { [correctionController, entityChecker, clock] in
        var frozenRequest = frozen
        defer {
          frozenRequest.wipePcm()
          self.removeTask(sessionId: frozen.sessionId)
        }
        do {
          let accurate = try await decoder(frozenRequest)
          guard !accurate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceSecondPassCoordinatorError.emptyAccurateTranscript
          }
          guard let recordBeforeCorrection = executionLedger.snapshot(sessionId: frozen.sessionId) else {
            return
          }
          let decision = correctionController.compare(
            fast: frozen.fast,
            accurate: accurate,
            executionRecord: recordBeforeCorrection
          )
          guard executionLedger.acceptCorrectionRevision(
            sessionId: frozen.sessionId,
            revision: accurate.revision
          ) else {
            return
          }
          let consistency = entityChecker.compare(
            fastText: frozen.fast.text,
            accurateText: accurate.text
          )
          let diff = TranscriptDiff(
            fastText: frozen.fast.text.trimmingCharacters(in: .whitespacesAndNewlines),
            accurateText: accurate.text.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedFastText: frozen.fast.text.voiceNormalizedTranscript(),
            normalizedAccurateText: accurate.text.voiceNormalizedTranscript(),
            entityDifferences: consistency.differences
          )
          onResult(VoiceSecondPassResult(
            metadata: VoiceSecondPassMetadata(
              sessionId: frozen.sessionId,
              fast: frozen.fast,
              accurateProfileId: frozen.accurateProfileId,
              accurateModelSha256: frozen.accurateModelSha256,
              mode: frozen.mode,
              requestedAtMillis: frozen.requestedAtMillis
            ),
            accurate: accurate,
            diff: diff,
            decision: decision,
            completedAtMillis: clock()
          ))
        } catch is CancellationError {
          return
        } catch {
          onFailure(error)
        }
      }
      tasks[frozen.sessionId] = task
      return true
    }
  }

  func cancel(sessionId: String) -> Bool {
    guard let task = locked({ tasks.removeValue(forKey: sessionId) }) else {
      return false
    }
    task.cancel()
    return true
  }

  func cancelForInteractiveVoice() -> Int {
    let active = locked { () -> [Task<Void, Never>] in
      let values = Array(tasks.values)
      tasks.removeAll()
      return values
    }
    active.forEach { $0.cancel() }
    return active.count
  }

  func activeSessionIds() -> Set<String> {
    locked { Set(tasks.keys) }
  }

  private func removeTask(sessionId: String) {
    locked {
      tasks.removeValue(forKey: sessionId)
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func defaultNowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

enum VoiceSecondPassCoordinatorError: Error, Equatable {
  case emptyAccurateTranscript
}

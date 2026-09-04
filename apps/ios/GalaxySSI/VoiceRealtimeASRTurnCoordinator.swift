import Foundation

enum VoiceRealtimeASRTurnAction {
  case display(TranscriptHypothesis, stable: Bool)
  case commit(TranscriptHypothesis)
  case correct(TranscriptHypothesis)
  case requestLocalFallback(reasonCode: String)
  case failed(reasonCode: String)
  case none
}

final class VoiceRealtimeASRTurnCoordinator: @unchecked Sendable {
  private let transcriptID: String
  private let arbiter: VoiceFinalTranscriptArbiter
  private let lock = NSLock()
  private var localSpeechStarted = false
  private var localSpeechEnded = false
  private var serverSpeechStarted = false
  private var onlineFinal = false
  private var fallbackRequested = false
  private var pcmBufferComplete = true
  private var partialObserved = false
  private var highestRevision = -1

  init(
    transcriptID: String,
    arbiter: VoiceFinalTranscriptArbiter = VoiceFinalTranscriptArbiter()
  ) {
    self.transcriptID = transcriptID
    self.arbiter = arbiter
  }

  func onLocalSpeechStarted() {
    locked { localSpeechStarted = true }
  }

  func onLocalSpeechEnded() {
    locked { localSpeechEnded = true }
  }

  func onServerSpeechStarted() {
    locked { serverSpeechStarted = true }
  }

  func onPcmBufferIntegrity(complete: Bool) {
    locked { pcmBufferComplete = complete }
  }

  func onOnlineEvent(_ event: VoiceOnlineRealtimeASREvent) -> VoiceRealtimeASRTurnAction {
    locked {
      switch event {
      case .ready, .usage, .metrics:
        return .none
      case .speechStarted:
        serverSpeechStarted = true
        return .none
      case .partial(let hypothesis, let stable):
        serverSpeechStarted = true
        partialObserved = true
        highestRevision = max(highestRevision, hypothesis.revision)
        return display(hypothesis, stable: stable)
      case .final(let hypothesis):
        serverSpeechStarted = true
        onlineFinal = true
        highestRevision = max(highestRevision, hypothesis.revision)
        return arbitrate(hypothesis, source: .onlinePrimary)
      case .failed(let failure):
        return fallbackOrFailure(reasonCode: failure.code)
      case .closed(_, _, let reasonCode):
        guard !onlineFinal else { return .none }
        return fallbackOrFailure(
          reasonCode: reasonCode.isEmpty ? "online_session_closed" : reasonCode
        )
      }
    }
  }

  func onInputFinishedWithoutFinal() -> VoiceRealtimeASRTurnAction {
    locked {
      guard !onlineFinal else { return .none }
      return fallbackOrFailure(
        reasonCode: partialObserved ? "online_partial_without_final" : "online_final_missing"
      )
    }
  }

  func onLocalFinal(_ hypothesis: TranscriptHypothesis) -> VoiceRealtimeASRTurnAction {
    locked {
      guard fallbackRequested || !onlineFinal else { return .none }
      var normalized = hypothesis
      normalized.revision = max(normalized.revision, highestRevision + 1)
      highestRevision = normalized.revision
      return arbitrate(normalized, source: .localFallback)
    }
  }

  func hasObservedSpeech() -> Bool {
    locked { localSpeechStarted || serverSpeechStarted }
  }

  private func fallbackOrFailure(reasonCode: String) -> VoiceRealtimeASRTurnAction {
    guard !fallbackRequested, !onlineFinal else { return .none }
    guard pcmBufferComplete else { return .failed(reasonCode: "pcm_fallback_incomplete") }
    fallbackRequested = true
    return .requestLocalFallback(reasonCode: reasonCode.isEmpty ? "online_session_closed" : reasonCode)
  }

  private func display(
    _ hypothesis: TranscriptHypothesis,
    stable: Bool
  ) -> VoiceRealtimeASRTurnAction {
    switch arbiter.consider(
      hypothesis: hypothesis,
      transcriptID: transcriptID,
      isFinal: false,
      source: .onlinePrimary
    ) {
    case .displayOnly:
      return .display(hypothesis, stable: stable)
    default:
      return .none
    }
  }

  private func arbitrate(
    _ hypothesis: TranscriptHypothesis,
    source: VoiceTranscriptSource
  ) -> VoiceRealtimeASRTurnAction {
    switch arbiter.consider(
      hypothesis: hypothesis,
      transcriptID: transcriptID,
      isFinal: true,
      source: source
    ) {
    case .commit:
      return .commit(hypothesis)
    case .correction:
      return .correct(hypothesis)
    default:
      return .none
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}

import Foundation

final class VoiceSpeechCaptureCoordinatorBridge {
  private let coordinator: VoiceInteractionCoordinator
  private let isCoordinatorEnabled: () -> Bool
  private let elapsedClock: VoiceElapsedClock
  private let lock = NSLock()
  private var currentSessionId = ""
  private var transcriptRevision = 0

  init(
    coordinator: VoiceInteractionCoordinator = VoiceInteractionCoordinatorRegistry.coordinator,
    isCoordinatorEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isCoordinatorEnabled() },
    elapsedClock: @escaping VoiceElapsedClock = VoiceSpeechCaptureCoordinatorBridge.defaultElapsedClock
  ) {
    self.coordinator = coordinator
    self.isCoordinatorEnabled = isCoordinatorEnabled
    self.elapsedClock = elapsedClock
  }

  static func config(
    settings: VoiceSettings,
    source: String = "ios_hold_to_talk"
  ) -> VoiceSessionConfig {
    let normalized = settings.normalized
    return VoiceSessionConfig(
      source: source,
      language: normalized.preferredLocaleIdentifier,
      targetId: normalized.targetContactId,
      routingMode: normalized.routingMode.rawValue,
      speakReplies: normalized.speakReplies,
      continueInBackground: normalized.wakeListeningEnabled
    )
  }

  func sessionId() -> String {
    locked { currentSessionId }
  }

  @discardableResult
  func begin(config: VoiceSessionConfig) -> VoiceInteractionTransition {
    guard isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    let transition = coordinator.begin(config: config)
    if transition.accepted {
      locked {
        currentSessionId = transition.current.sessionId
        transcriptRevision = 0
      }
    }
    return transition
  }

  @discardableResult
  func capturePrepared() -> VoiceInteractionTransition {
    dispatchCurrent { .capturePrepared(sessionId: $0) }
  }

  @discardableResult
  func speechStarted(atElapsedNs: Int64? = nil) -> VoiceInteractionTransition {
    dispatchCurrent {
      .speechStarted(sessionId: $0, atElapsedNs: atElapsedNs ?? max(0, elapsedClock()))
    }
  }

  @discardableResult
  func speechEnded(atElapsedNs: Int64? = nil) -> VoiceInteractionTransition {
    dispatchCurrent {
      .speechEnded(sessionId: $0, atElapsedNs: atElapsedNs ?? max(0, elapsedClock()))
    }
  }

  @discardableResult
  func finalizationStarted() -> VoiceInteractionTransition {
    dispatchCurrent { .finalizationStarted(sessionId: $0) }
  }

  @discardableResult
  func transcriptPartial(
    _ text: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    transcriptUpdate(text, provider: provider, modelProfileId: modelProfileId) {
      .transcriptPartial(sessionId: $0, value: $1)
    }
  }

  @discardableResult
  func transcriptStable(
    _ text: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    transcriptUpdate(text, provider: provider, modelProfileId: modelProfileId) {
      .transcriptStable(sessionId: $0, value: $1)
    }
  }

  @discardableResult
  func finishWithBestTranscript(
    _ text: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return cancelCurrent(reasonCode: "empty_transcript")
    }
    let sessionId = sessionId()
    guard !sessionId.isEmpty, isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    let snapshot = coordinator.snapshot()
    if snapshot.sessionId == sessionId, snapshot.phase == .listening {
      speechEnded()
    }
    let afterSpeechEnd = coordinator.snapshot()
    if afterSpeechEnd.sessionId == sessionId,
       afterSpeechEnd.phase == .listening || afterSpeechEnd.phase == .endpointing {
      finalizationStarted()
    }
    let revision = nextTranscriptRevision()
    let transition = coordinator.dispatch(
      .transcriptFinal(
        sessionId: sessionId,
        value: TranscriptHypothesis(
          text: normalized,
          revision: revision,
          provider: provider,
          modelProfileId: modelProfileId
        )
      )
    )
    clearCurrentSessionIfTerminal(transition)
    return transition
  }

  @discardableResult
  func finishStoppedCapture(
    transcript: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    let sessionId = sessionId()
    guard !sessionId.isEmpty, isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    let snapshot = coordinator.snapshot()
    if snapshot.sessionId == sessionId && (snapshot.finalText != nil || snapshot.phase.isTerminal) {
      return VoiceInteractionTransition(previous: snapshot, current: snapshot, accepted: false)
    }
    return finishWithBestTranscript(transcript, provider: provider, modelProfileId: modelProfileId)
  }

  @discardableResult
  func cancelCurrent(reasonCode: String = "user_cancelled") -> VoiceInteractionTransition {
    let sessionId = sessionId()
    guard !sessionId.isEmpty, isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    let transition = coordinator.dispatch(.cancelled(sessionId: sessionId, reasonCode: reasonCode))
    clearCurrentSessionIfTerminal(transition)
    return transition
  }

  @discardableResult
  func failCurrent(
    code: String,
    detail: String = "",
    recoverable: Bool = true
  ) -> VoiceInteractionTransition {
    let sessionId = sessionId()
    guard !sessionId.isEmpty, isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    let snapshot = coordinator.snapshot()
    let stage = snapshot.sessionId == sessionId ? snapshot.phase : .idle
    let transition = coordinator.dispatch(
      .failed(
        sessionId: sessionId,
        failure: VoiceFailure(
          code: code,
          recoverable: recoverable,
          stage: stage,
          detail: detail
        )
      )
    )
    clearCurrentSessionIfTerminal(transition)
    return transition
  }

  private func transcriptUpdate(
    _ text: String,
    provider: String,
    modelProfileId: String,
    makeEvent: (String, TranscriptHypothesis) -> VoiceInteractionEvent
  ) -> VoiceInteractionTransition {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return rejectedTransition() }
    return dispatchCurrent { sessionId in
      makeEvent(
        sessionId,
        TranscriptHypothesis(
          text: normalized,
          revision: nextTranscriptRevision(),
          provider: provider,
          modelProfileId: modelProfileId
        )
      )
    }
  }

  private func dispatchCurrent(_ makeEvent: (String) -> VoiceInteractionEvent) -> VoiceInteractionTransition {
    let sessionId = sessionId()
    guard !sessionId.isEmpty, isCoordinatorEnabled() else {
      return rejectedTransition()
    }
    return coordinator.dispatch(makeEvent(sessionId))
  }

  private func clearCurrentSessionIfTerminal(_ transition: VoiceInteractionTransition) {
    guard transition.current.phase.isTerminal else { return }
    locked {
      if currentSessionId == transition.current.sessionId {
        currentSessionId = ""
      }
    }
  }

  private func nextTranscriptRevision() -> Int {
    locked {
      transcriptRevision += 1
      return transcriptRevision
    }
  }

  private func rejectedTransition() -> VoiceInteractionTransition {
    let snapshot = coordinator.snapshot()
    return VoiceInteractionTransition(previous: snapshot, current: snapshot, accepted: false)
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }
}

let iosSpeechProviderId = "ios_speech"

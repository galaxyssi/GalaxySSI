import Foundation

final class VoiceSpeechCaptureCoordinatorBridge {
  private let coordinator: VoiceInteractionCoordinator
  private let isCoordinatorEnabled: () -> Bool
  private let elapsedClock: VoiceElapsedClock
  private let latencyTracer: VoiceLatencyTracer?
  private let lock = NSLock()
  private var currentSessionId = ""
  private var currentTraceId = ""
  private var transcriptRevision = 0

  init(
    coordinator: VoiceInteractionCoordinator = VoiceInteractionCoordinatorRegistry.coordinator,
    isCoordinatorEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isCoordinatorEnabled() },
    elapsedClock: @escaping VoiceElapsedClock = VoiceSpeechCaptureCoordinatorBridge.defaultElapsedClock,
    latencyTracer: VoiceLatencyTracer? = VoiceLatencyTelemetry.tracer()
  ) {
    self.coordinator = coordinator
    self.isCoordinatorEnabled = isCoordinatorEnabled
    self.elapsedClock = elapsedClock
    self.latencyTracer = latencyTracer
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
        currentTraceId = transition.current.sessionId
        transcriptRevision = 0
      }
      recordLatency(
        VoiceTraceEvents.sessionCreated,
        attributes: [
          "recording_source": config.source,
          "asr_provider": iosSpeechProviderId,
          "model_profile_id": config.language,
        ],
        once: true
      )
      recordLatency(VoiceTraceEvents.microphoneOpenStarted, once: true)
    }
    return transition
  }

  @discardableResult
  func capturePrepared() -> VoiceInteractionTransition {
    let transition = dispatchCurrent { .capturePrepared(sessionId: $0) }
    if transition.accepted {
      recordLatency(VoiceTraceEvents.microphoneOpened, once: true)
    }
    return transition
  }

  @discardableResult
  func speechStarted(atElapsedNs: Int64? = nil) -> VoiceInteractionTransition {
    let transition = dispatchCurrent {
      .speechStarted(sessionId: $0, atElapsedNs: atElapsedNs ?? max(0, elapsedClock()))
    }
    if transition.accepted {
      recordLatency(VoiceTraceEvents.speechStarted, once: true)
    }
    return transition
  }

  @discardableResult
  func speechEnded(atElapsedNs: Int64? = nil) -> VoiceInteractionTransition {
    let transition = dispatchCurrent {
      .speechEnded(sessionId: $0, atElapsedNs: atElapsedNs ?? max(0, elapsedClock()))
    }
    if transition.accepted {
      recordLatency(VoiceTraceEvents.speechEnded, once: true)
    }
    return transition
  }

  @discardableResult
  func dispatchAudioLevel(_ rms: Float) -> VoiceInteractionTransition {
    dispatchCurrent { .audioLevel(sessionId: $0, rms: max(0, min(rms, 1))) }
  }

  @discardableResult
  func finalizationStarted() -> VoiceInteractionTransition {
    let transition = dispatchCurrent { .finalizationStarted(sessionId: $0) }
    if transition.accepted {
      recordLatency(VoiceTraceEvents.asrFinalStarted, once: true)
    }
    return transition
  }

  @discardableResult
  func transcriptPartial(
    _ text: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    let transition = transcriptUpdate(text, provider: provider, modelProfileId: modelProfileId) {
      .transcriptPartial(sessionId: $0, value: $1)
    }
    if transition.accepted {
      recordLatency(
        VoiceTraceEvents.asrFirstPartial,
        attributes: asrAttributes(provider: provider, modelProfileId: modelProfileId),
        once: true
      )
    }
    return transition
  }

  @discardableResult
  func transcriptStable(
    _ text: String,
    provider: String = iosSpeechProviderId,
    modelProfileId: String = ""
  ) -> VoiceInteractionTransition {
    let transition = transcriptUpdate(text, provider: provider, modelProfileId: modelProfileId) {
      .transcriptStable(sessionId: $0, value: $1)
    }
    if transition.accepted {
      recordLatency(
        VoiceTraceEvents.asrFirstStable,
        attributes: asrAttributes(provider: provider, modelProfileId: modelProfileId),
        once: true
      )
    }
    return transition
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
    if transition.accepted {
      recordLatency(
        VoiceTraceEvents.asrFinalReceived,
        attributes: asrAttributes(provider: provider, modelProfileId: modelProfileId),
        once: true
      )
      recordLatency(VoiceTraceEvents.routeStarted, once: true)
    }
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
    if transition.accepted {
      recordLatency(VoiceTraceEvents.sessionCancelled, attributes: ["error_code": reasonCode], once: true)
    }
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
    if transition.accepted {
      recordLatency(VoiceTraceEvents.sessionFailed, attributes: ["error_code": code], once: true)
    }
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
        currentTraceId = ""
      }
    }
  }

  private func recordLatency(
    _ event: String,
    attributes: [String: String] = [:],
    once: Bool = false
  ) {
    let ids = locked { (traceId: currentTraceId, sessionId: currentSessionId) }
    guard !ids.traceId.isEmpty else { return }
    latencyTracer?.record(
      traceId: ids.traceId,
      sessionId: ids.sessionId,
      event: event,
      attributes: attributes,
      once: once
    )
  }

  private func asrAttributes(provider: String, modelProfileId: String) -> [String: String] {
    [
      "asr_provider": provider,
      "model_profile_id": modelProfileId,
    ]
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

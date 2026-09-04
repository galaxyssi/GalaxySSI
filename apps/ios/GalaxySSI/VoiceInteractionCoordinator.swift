import Foundation

typealias VoiceElapsedClock = () -> Int64
typealias VoiceInteractionObserver = (VoiceInteractionState) throws -> Void

final class VoiceInteractionCoordinator {
  private let elapsedClock: VoiceElapsedClock
  private let sessionIdFactory: () -> String
  private let lock = NSLock()
  private var observers: [String: VoiceInteractionObserver] = [:]
  private var emittedCommandKeys: Set<String> = []
  private var emittedCommandOrder: [String] = []
  private var currentConfig: VoiceSessionConfig?
  private var state = VoiceInteractionState()

  init(
    elapsedClock: @escaping VoiceElapsedClock = VoiceInteractionCoordinator.defaultElapsedClock,
    sessionIdFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.elapsedClock = elapsedClock
    self.sessionIdFactory = sessionIdFactory
  }

  func snapshot() -> VoiceInteractionState {
    locked { state }
  }

  func config() -> VoiceSessionConfig? {
    locked { currentConfig }
  }

  func observe(_ observer: @escaping VoiceInteractionObserver) -> String {
    let observerId = UUID().uuidString
    let current = locked { () -> VoiceInteractionState in
      observers[observerId] = observer
      return state
    }
    try? observer(current)
    return observerId
  }

  func removeObserver(_ observerId: String) {
    locked {
      observers.removeValue(forKey: observerId)
    }
  }

  func begin(config: VoiceSessionConfig) -> VoiceInteractionTransition {
    let result = locked { () -> (VoiceInteractionTransition, VoiceInteractionState?, [VoiceInteractionObserver]) in
      let previous = state
      if !state.phase.isTerminal && state.phase != .idle {
        return (VoiceInteractionTransition(previous: previous, current: previous, accepted: false), nil, [])
      }
      let trimmedSessionId = config.requestedSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let sessionId = trimmedSessionId.isEmpty ? sessionIdFactory() : trimmedSessionId
      if previous.sessionId == sessionId && previous.phase.isTerminal {
        return (VoiceInteractionTransition(previous: previous, current: previous, accepted: false), nil, [])
      }
      let now = max(0, elapsedClock())
      currentConfig = VoiceSessionConfig(
        requestedSessionId: sessionId,
        source: config.source,
        language: config.language,
        targetId: config.targetId,
        routingMode: config.routingMode,
        speakReplies: config.speakReplies,
        continueInBackground: config.continueInBackground
      )
      state = VoiceInteractionState(
        sessionId: sessionId,
        phase: .preparing,
        revision: previous.revision + 1,
        createdAtElapsedNs: now,
        updatedAtElapsedNs: now
      )
      trimCommandLedger()
      return (
        VoiceInteractionTransition(previous: previous, current: state),
        state,
        Array(observers.values)
      )
    }
    notify(result.1, observers: result.2)
    return result.0
  }

  func dispatch(_ event: VoiceInteractionEvent) -> VoiceInteractionTransition {
    let result = locked { () -> (VoiceInteractionTransition, VoiceInteractionState?, [VoiceInteractionObserver]) in
      let previous = state
      if event.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
          event.sessionId != previous.sessionId ||
          (previous.phase.isTerminal && !event.isTranscriptCorrection) {
        return (VoiceInteractionTransition(previous: previous, current: previous, accepted: false), nil, [])
      }
      let reduced = reduce(previous: previous, event: event)
      if reduced.state == previous && reduced.commands.isEmpty {
        return (VoiceInteractionTransition(previous: previous, current: previous, accepted: false), nil, [])
      }
      let now = max(previous.updatedAtElapsedNs, elapsedClock())
      state = reduced.state
      state.revision = previous.revision + 1
      state.updatedAtElapsedNs = max(0, now)
      let commands = reduced.commands.filter { acceptCommandKey($0.idempotencyKey) }
      trimCommandLedger()
      return (
        VoiceInteractionTransition(previous: previous, current: state, commands: commands),
        state,
        Array(observers.values)
      )
    }
    notify(result.1, observers: result.2)
    return result.0
  }

  func cancel(reasonCode: String = "user_cancelled") -> VoiceInteractionTransition {
    let current = snapshot()
    guard !current.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return VoiceInteractionTransition(previous: current, current: current, accepted: false)
    }
    return dispatch(.cancelled(sessionId: current.sessionId, reasonCode: reasonCode))
  }

  func result() -> VoiceSessionResult? {
    locked {
      guard state.phase.isTerminal, !state.sessionId.isEmpty else { return nil }
      return VoiceSessionResult(
        sessionId: state.sessionId,
        completed: state.phase == .completed,
        cancelled: state.phase == .cancelled,
        route: state.route,
        failure: state.failure,
        finalTranscriptRevision: state.finalTranscriptRevision
      )
    }
  }

  private func reduce(
    previous: VoiceInteractionState,
    event: VoiceInteractionEvent
  ) -> (state: VoiceInteractionState, commands: [VoiceInteractionCommand]) {
    switch event {
    case .capturePrepared(sessionId: _):
      guard previous.phase == .preparing else { return (previous, []) }
      var next = previous
      next.phase = .listening
      return (next, [])

    case .audioLevel(sessionId: _, rms: _):
      return (previous, [])

    case .speechStarted(sessionId: _, atElapsedNs: _):
      guard previous.phase == .preparing || previous.phase == .listening else { return (previous, []) }
      var next = previous
      next.phase = .listening
      return (next, [])

    case .speechEnded(sessionId: _, atElapsedNs: _):
      guard previous.phase == .listening else { return (previous, []) }
      var next = previous
      next.phase = .endpointing
      return (next, [])

    case .finalizationStarted(sessionId: _):
      guard previous.phase == .listening || previous.phase == .endpointing else { return (previous, []) }
      var next = previous
      next.phase = .finalizingASR
      return (next, [])

    case let .transcriptPartial(sessionId: _, value: value):
      guard transcriptUpdatesAllowed(previous.phase) else { return (previous, []) }
      var next = previous
      next.partialText = value.text
      next.asrProvider = nonBlank(value.provider) ?? previous.asrProvider
      next.modelProfileId = nonBlank(value.modelProfileId) ?? previous.modelProfileId
      return (next, [])

    case let .transcriptStable(sessionId: _, value: value):
      guard transcriptUpdatesAllowed(previous.phase) else { return (previous, []) }
      var next = previous
      next.stableText = value.text
      next.asrProvider = nonBlank(value.provider) ?? previous.asrProvider
      next.modelProfileId = nonBlank(value.modelProfileId) ?? previous.modelProfileId
      return (next, [])

    case let .transcriptFinal(sessionId: _, value: value):
      let normalized = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { return (previous, []) }
      if previous.finalText == nil && transcriptUpdatesAllowed(previous.phase) {
        var finalValue = value
        finalValue.text = normalized
        var next = previous
        next.phase = .routing
        next.partialText = ""
        next.stableText = normalized
        next.finalText = normalized
        next.finalTranscriptRevision = value.revision
        next.asrProvider = nonBlank(value.provider) ?? previous.asrProvider
        next.modelProfileId = nonBlank(value.modelProfileId) ?? previous.modelProfileId
        let key = "\(previous.sessionId):route:\(value.revision)"
        return (
          next,
          [.routeFinalTranscript(sessionId: previous.sessionId, transcript: finalValue, idempotencyKey: key)]
        )
      }
      if previous.finalText != normalized {
        var next = previous
        next.correctedText = normalized
        return (next, [])
      }
      return (previous, [])

    case let .transcriptCorrected(sessionId: _, original: _, corrected: corrected):
      let text = corrected.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text != previous.correctedText else { return (previous, []) }
      var next = previous
      next.correctedText = text
      return (next, [])

    case let .routeSelected(sessionId: _, decision: decision):
      guard previous.phase == .routing else { return (previous, []) }
      var next = previous
      next.route = decision
      switch decision.kind {
      case .localAction:
        next.phase = .executingLocalAction
      case .cloudModel:
        next.phase = .waitingModelFirstToken
      case .remoteAgent:
        next.phase = .startingAgent
      }
      return (next, [])

    case .localActionCompleted(sessionId: _):
      guard previous.phase == .executingLocalAction else { return (previous, []) }
      var next = previous
      next.phase = .completed
      next.canInterrupt = false
      return (next, [])

    case .modelDelta(sessionId: _, text: _):
      guard previous.phase == .waitingModelFirstToken || previous.phase == .streamingModelText else {
        return (previous, [])
      }
      var next = previous
      next.phase = .streamingModelText
      return (next, [])

    case let .agentAccepted(sessionId: _, runId: runId),
         let .agentProgress(sessionId: _, runId: runId):
      guard previous.phase == .startingAgent || previous.phase == .agentRunning else {
        return (previous, [])
      }
      var next = previous
      next.phase = .agentRunning
      next.agentRunId = nonBlank(runId) ?? previous.agentRunId
      return (next, [])

    case .playbackStarted(sessionId: _, utteranceId: _):
      guard previous.phase == .waitingModelFirstToken ||
          previous.phase == .streamingModelText ||
          previous.phase == .agentRunning else {
        return (previous, [])
      }
      var next = previous
      next.phase = .playingTTS
      return (next, [])

    case .completed(sessionId: _):
      var next = previous
      next.phase = .completed
      next.canInterrupt = false
      return (next, [])

    case let .cancelled(sessionId: _, reasonCode: reasonCode):
      var next = previous
      next.phase = .cancelled
      next.canInterrupt = false
      return (
        next,
        [.cancelLegacyWork(
          sessionId: previous.sessionId,
          reasonCode: reasonCode,
          idempotencyKey: "\(previous.sessionId):cancel"
        )]
      )

    case let .failed(sessionId: _, failure: failure):
      var next = previous
      next.phase = .failed
      next.canInterrupt = false
      next.failure = failure
      return (next, [])
    }
  }

  private func notify(
    _ state: VoiceInteractionState?,
    observers: [VoiceInteractionObserver]
  ) {
    guard let state = state else { return }
    observers.forEach { observer in
      try? observer(state)
    }
  }

  private func acceptCommandKey(_ key: String) -> Bool {
    guard emittedCommandKeys.insert(key).inserted else { return false }
    emittedCommandOrder.append(key)
    return true
  }

  private func trimCommandLedger() {
    guard emittedCommandOrder.count > 2_048 else { return }
    let expired = emittedCommandOrder.prefix(512)
    expired.forEach { emittedCommandKeys.remove($0) }
    emittedCommandOrder.removeFirst(min(512, emittedCommandOrder.count))
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private func transcriptUpdatesAllowed(_ phase: VoiceInteractionPhase) -> Bool {
    phase == .listening || phase == .endpointing || phase == .finalizingASR
  }

  private func nonBlank(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }
}

enum VoiceInteractionCoordinatorRegistry {
  static let coordinator = VoiceInteractionCoordinator()
}

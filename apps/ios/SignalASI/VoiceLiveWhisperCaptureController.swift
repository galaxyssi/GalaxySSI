import Foundation

protocol VoiceLiveWhisperSessionHandling: AnyObject {
  var modelProfileId: String { get }
  func nextPartialWindowMillis(capturedAudioMillis: Int64) -> Int64?
  func offerPartial(_ snapshot: PcmSnapshot)
  func finish(_ snapshot: PcmSnapshot) async throws -> VoiceNativeWhisperResult
  func close()
}

extension VoiceLiveWhisperTranscriptionSession: VoiceLiveWhisperSessionHandling {}

typealias VoiceLiveWhisperCaptureSessionBuilder = (
  _ voiceSessionId: String,
  _ settings: VoiceSettings,
  _ scheduler: VoiceWhisperDecodeScheduling,
  _ queue: VoiceWhisperDecodeQueueSnapshot,
  _ onUpdate: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void
) -> VoiceLiveWhisperSessionHandling?

final class VoiceLiveWhisperCaptureController {
  private let sessionBuilder: VoiceLiveWhisperCaptureSessionBuilder
  private let coordinatorBridge: VoiceLiveWhisperCoordinatorBridge
  private var updateHandler: (VoiceLiveWhisperTranscriptUpdate) -> Void
  private var transitionHandler: (VoiceInteractionTransition) -> Void
  private let lock = NSLock()
  private var session: VoiceLiveWhisperSessionHandling?
  private var speechStartedAtMillis: Int64?

  init(
    factory: VoiceLiveWhisperSessionFactory = VoiceLiveWhisperSessionFactory(),
    coordinatorBridge: VoiceLiveWhisperCoordinatorBridge,
    updateHandler: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void = { _ in },
    transitionHandler: @escaping (VoiceInteractionTransition) -> Void = { _ in }
  ) {
    self.sessionBuilder = { voiceSessionId, settings, scheduler, queue, onUpdate in
      factory.makeSession(
        voiceSessionId: voiceSessionId,
        settings: settings,
        scheduler: scheduler,
        queue: queue,
        onUpdate: onUpdate
      )
    }
    self.coordinatorBridge = coordinatorBridge
    self.updateHandler = updateHandler
    self.transitionHandler = transitionHandler
  }

  init(
    sessionBuilder: @escaping VoiceLiveWhisperCaptureSessionBuilder,
    coordinatorBridge: VoiceLiveWhisperCoordinatorBridge,
    updateHandler: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void = { _ in },
    transitionHandler: @escaping (VoiceInteractionTransition) -> Void = { _ in }
  ) {
    self.sessionBuilder = sessionBuilder
    self.coordinatorBridge = coordinatorBridge
    self.updateHandler = updateHandler
    self.transitionHandler = transitionHandler
  }

  var activeModelProfileId: String? {
    locked { session?.modelProfileId }
  }

  func setUpdateHandler(_ updateHandler: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void) {
    locked {
      self.updateHandler = updateHandler
    }
  }

  func setTransitionHandler(_ transitionHandler: @escaping (VoiceInteractionTransition) -> Void) {
    locked {
      self.transitionHandler = transitionHandler
    }
  }

  @discardableResult
  func start(
    voiceSessionId: String,
    settings: VoiceSettings,
    scheduler: VoiceWhisperDecodeScheduling,
    queue: VoiceWhisperDecodeQueueSnapshot = VoiceWhisperDecodeQueueSnapshot()
  ) -> Bool {
    close()
    let created = sessionBuilder(voiceSessionId, settings, scheduler, queue) { [weak self] update in
      self?.apply(update)
    }
    locked {
      session = created
      speechStartedAtMillis = nil
    }
    return created != nil
  }

  func handleSpeechStarted(nowMillis: Int64) {
    locked {
      if session != nil, speechStartedAtMillis == nil {
        speechStartedAtMillis = max(0, nowMillis)
      }
    }
  }

  func handleAudioLevel(
    isSpeech: Bool,
    nowMillis: Int64,
    snapshotWindow: (Int64) -> PcmSnapshot?
  ) {
    let current = locked { () -> (VoiceLiveWhisperSessionHandling?, Int64?) in
      (session, speechStartedAtMillis)
    }
    guard isSpeech,
          let session = current.0,
          let startedAt = current.1 else {
      return
    }
    let capturedAudioMillis = max(0, nowMillis - startedAt)
    guard let windowMillis = session.nextPartialWindowMillis(capturedAudioMillis: capturedAudioMillis),
          let snapshot = snapshotWindow(windowMillis) else {
      return
    }
    session.offerPartial(snapshot)
  }

  func finish(_ snapshot: PcmSnapshot) async throws -> VoiceNativeWhisperResult? {
    guard let current = locked({ session }) else {
      return nil
    }
    return try await current.finish(snapshot)
  }

  func close() {
    let current = locked { () -> VoiceLiveWhisperSessionHandling? in
      let current = session
      session = nil
      speechStartedAtMillis = nil
      return current
    }
    current?.close()
  }

  private func apply(_ update: VoiceLiveWhisperTranscriptUpdate) {
    let handlers = locked { (update: updateHandler, transition: transitionHandler) }
    handlers.update(update)
    coordinatorBridge.apply(update).forEach(handlers.transition)
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

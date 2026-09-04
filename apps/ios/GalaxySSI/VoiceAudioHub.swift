import Foundation

protocol PcmRecorder {
  func start(config: PcmCaptureConfig) throws -> AsyncStream<AudioFrame>
  func requestStop(reason: PcmStopReason)
  func stop(reason: PcmStopReason) async
  func currentState() -> PcmRecorderState
}

struct VoiceAudioSessionConfig: Equatable {
  var capture: PcmCaptureConfig
  var endpoint: AdaptiveEndpointConfig
  var autoEndpoint: Bool

  init(
    capture: PcmCaptureConfig = PcmCaptureConfig(),
    endpoint: AdaptiveEndpointConfig = AdaptiveEndpointConfig(),
    autoEndpoint: Bool = false
  ) {
    self.capture = capture
    self.endpoint = endpoint
    self.autoEndpoint = autoEndpoint
  }
}

struct VoiceAudioSession: Equatable {
  var id: String
}

protocol VoiceAudioHubListener {
  func onCaptureReady(session: VoiceAudioSession, state: PcmRecorderState)
  func onAudioLevel(session: VoiceAudioSession, decision: VadDecision)
  func onSpeechStarted(session: VoiceAudioSession, sequence: Int64)
  func onSpeechEndedCandidate(session: VoiceAudioSession, sequence: Int64)
  func onEndpoint(session: VoiceAudioSession, reason: EndpointReason)
  func onInputRouteChanged(session: VoiceAudioSession, route: String)
  func onFailure(session: VoiceAudioSession, error: Error)
}

extension VoiceAudioHubListener {
  func onCaptureReady(session: VoiceAudioSession, state: PcmRecorderState) {}
  func onAudioLevel(session: VoiceAudioSession, decision: VadDecision) {}
  func onSpeechStarted(session: VoiceAudioSession, sequence: Int64) {}
  func onSpeechEndedCandidate(session: VoiceAudioSession, sequence: Int64) {}
  func onEndpoint(session: VoiceAudioSession, reason: EndpointReason) {}
  func onInputRouteChanged(session: VoiceAudioSession, route: String) {}
  func onFailure(session: VoiceAudioSession, error: Error) {}
}

struct NoopVoiceAudioHubListener: VoiceAudioHubListener {}

final class VoiceAudioHub {
  private final class ActiveSession {
    let publicSession: VoiceAudioSession
    let config: VoiceAudioSessionConfig
    let store: SpeechSegmentStore
    let vad: VoiceActivityDetector
    let endpoint: AdaptiveEndpointDetector
    let listener: VoiceAudioHubListener
    let lock = NSLock()
    var stopRequested = false
    var lastRoute = ""
    var task: Task<Void, Never>?

    init(
      publicSession: VoiceAudioSession,
      config: VoiceAudioSessionConfig,
      store: SpeechSegmentStore,
      vad: VoiceActivityDetector,
      endpoint: AdaptiveEndpointDetector,
      listener: VoiceAudioHubListener
    ) {
      self.publicSession = publicSession
      self.config = config
      self.store = store
      self.vad = vad
      self.endpoint = endpoint
      self.listener = listener
    }

    func isStopRequested() -> Bool {
      locked { stopRequested }
    }

    func requestStop() {
      locked { stopRequested = true }
    }

    func claimEndpointStop() -> Bool {
      locked {
        guard !stopRequested else { return false }
        stopRequested = true
        return true
      }
    }

    func updateRoute(_ route: String) -> Bool {
      locked {
        guard !route.isEmpty, route != lastRoute else { return false }
        lastRoute = route
        return true
      }
    }

    private func locked<T>(_ action: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return action()
    }
  }

  private let recorder: PcmRecorder
  private let sessionIdFactory: () -> String
  private let vadFactory: () -> VoiceActivityDetector
  private let lock = NSLock()
  private var active: ActiveSession?

  init(
    recorder: PcmRecorder,
    sessionIdFactory: @escaping () -> String = { UUID().uuidString },
    vadFactory: @escaping () -> VoiceActivityDetector = { AdaptiveSpeechVad() }
  ) {
    self.recorder = recorder
    self.sessionIdFactory = sessionIdFactory
    self.vadFactory = vadFactory
  }

  func start(
    config: VoiceAudioSessionConfig,
    listener: VoiceAudioHubListener = NoopVoiceAudioHubListener()
  ) -> VoiceAudioSession? {
    let session = locked { () -> ActiveSession? in
      guard active == nil else { return nil }
      let publicSession = VoiceAudioSession(id: sessionIdFactory())
      let session = ActiveSession(
        publicSession: publicSession,
        config: config,
        store: InMemorySpeechSegmentStore(
          sampleRateHz: config.capture.sampleRateHz,
          maxDurationMs: config.capture.maxDurationMs + 1_000
        ),
        vad: vadFactory(),
        endpoint: AdaptiveEndpointDetector(
          sampleRateHz: config.capture.sampleRateHz,
          config: config.endpoint,
          autoEndpoint: config.autoEndpoint
        ),
        listener: listener
      )
      active = session
      return session
    }
    guard let session = session else { return nil }
    session.task = Task { [weak self] in
      await self?.run(session)
    }
    return session.publicSession
  }

  func currentAmplitude() -> Int {
    recorder.currentState().currentAmplitude
  }

  func currentState() -> PcmRecorderState {
    recorder.currentState()
  }

  func requestStop(session: VoiceAudioSession, reason: PcmStopReason) {
    guard let current = matchingActive(session) else { return }
    current.requestStop()
    recorder.requestStop(reason: reason)
  }

  func stop(session: VoiceAudioSession, reason: PcmStopReason) async -> VoiceAudioCaptureResult? {
    guard let current = matchingActive(session) else { return nil }
    current.requestStop()
    await recorder.stop(reason: reason)
    await current.task?.value
    let state = recorder.currentState()
    let result = VoiceAudioCaptureResult(
      sessionId: session.id,
      stopReason: state.stopReason ?? reason,
      snapshot: current.store.snapshot(
        segment: SegmentRange(
          preRollMs: current.config.endpoint.preRollMs,
          postRollMs: current.config.endpoint.postRollMs
        )
      ),
      diagnostics: state.diagnostics,
      audioSource: state.audioSource,
      inputRoute: state.inputRoute
    )
    current.store.clear()
    clearActive(current)
    return result
  }

  func activeSession() -> VoiceAudioSession? {
    locked { active?.publicSession }
  }

  func snapshotWindow(session: VoiceAudioSession, maxDurationMs: Int64) -> PcmSnapshot? {
    guard let current = matchingActive(session) else { return nil }
    return current.store.snapshotWindow(
      maxDurationMs: maxDurationMs,
      segment: SegmentRange(
        preRollMs: current.config.endpoint.preRollMs,
        postRollMs: current.config.endpoint.postRollMs
      )
    )
  }

  private func run(_ session: ActiveSession) async {
    do {
      let frames = try recorder.start(config: session.config.capture)
      if session.isStopRequested() {
        await recorder.stop(reason: .userCancel)
        return
      }
      let readyState = recorder.currentState()
      _ = session.updateRoute(readyState.inputRoute)
      session.listener.onCaptureReady(session: session.publicSession, state: readyState)
      for await frame in frames {
        processFrame(session, frame: frame)
        frame.close()
      }
    } catch {
      if !session.isStopRequested() {
        session.listener.onFailure(session: session.publicSession, error: error)
      }
    }
    if !session.isStopRequested() {
      session.store.clear()
      clearActive(session)
    }
  }

  private func processFrame(_ session: ActiveSession, frame: AudioFrame) {
    session.store.append(frame)
    let decision = session.vad.accept(frame)
    let endpoint = session.endpoint.accept(frame, vad: decision)
    if endpoint.speechStarted {
      session.store.markSpeechStart(sequence: frame.sequence)
      session.listener.onSpeechStarted(session: session.publicSession, sequence: frame.sequence)
    }
    if endpoint.speechEndedCandidate {
      session.store.markSpeechEnd(sequence: frame.sequence)
      session.listener.onSpeechEndedCandidate(session: session.publicSession, sequence: frame.sequence)
    }
    session.listener.onAudioLevel(session: session.publicSession, decision: decision)
    let route = recorder.currentState().inputRoute
    if session.updateRoute(route) {
      session.listener.onInputRouteChanged(session: session.publicSession, route: route)
    }
    if let reason = endpoint.endpointReason, session.claimEndpointStop() {
      session.listener.onEndpoint(session: session.publicSession, reason: reason)
    }
  }

  private func matchingActive(_ session: VoiceAudioSession) -> ActiveSession? {
    locked { active?.publicSession.id == session.id ? active : nil }
  }

  private func clearActive(_ session: ActiveSession) {
    locked {
      if active === session {
        active = nil
      }
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}

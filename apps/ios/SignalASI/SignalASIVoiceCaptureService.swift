import AVFoundation
import Foundation
import Speech
import SwiftUI

private enum SpeechCaptureServiceError: LocalizedError {
  case recognizerUnavailable
  case requestUnavailable
  case localWhisperUnavailable

  var errorDescription: String? {
    switch self {
    case .recognizerUnavailable:
      return "Speech recognition is unavailable for this locale."
    case .requestUnavailable:
      return "Speech recognition could not start a capture request."
    case .localWhisperUnavailable:
      return "On-device Whisper is not ready. Download the selected model or use iOS Speech."
    }
  }
}

private enum SpeechCaptureLiveWhisperFinalizationError: LocalizedError {
  case sessionUnavailable

  var errorDescription: String? {
    switch self {
    case .sessionUnavailable:
      return "Live Whisper session is unavailable for final transcription."
    }
  }
}

final class SpeechCaptureService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
  @Published private(set) var transcript = ""
  @Published private(set) var isRecording = false
  private(set) var stableTranscript = ""
  private(set) var unstableTranscript = ""
  var onVoiceCommand: ((VoiceInteractionCommand) -> Void)?

  private let coordinatorBridge: VoiceSpeechCaptureCoordinatorBridge
  private let liveWhisperScheduler: VoiceWhisperDecodeScheduling
  private let liveWhisperController: VoiceLiveWhisperCaptureController
  private let audioEngine = AVAudioEngine()
  private let audioLevelLock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var currentRecognitionModelProfileId = ""
  private var currentRecognitionProvider = iosSpeechProviderId
  private var currentIOSSpeechTranscript = ""
  private var currentRuntimeChannel = VoiceRuntimeChannel.androidSystemASR
  private var pcmTapPipeline: VoicePcmTapPipeline?
  private var pcmTapSpeechStarted = false
  private var pcmTapSpeechEnded = false
  private var pcmTapEndpointRequested = false
  private var liveWhisperActive = false
  private var onlineRealtimeActive = false
  private var onlineRealtimeFinalizing = false
  private var onlineRealtimeHasTranscript = false
  private var onlineRealtimeProvider = "signalasi_realtime"
  private var onlineRealtimeModelProfileId = ""
  private var onlineRealtimeSession: VoiceOnlineRealtimeASRSession?
  private var onlineRealtimeTimeoutTask: Task<Void, Never>?
  private var remoteWhisperActive = false
  private var remoteWhisperLanguage = ""
  private var inputSampleRateHz = VoiceOnlineRealtimeASRProtocol.sampleRateHz
  private var latestAudioLevel: Float = 0
  private var holdToTalkCompletion: ((String) -> Void)?
  private var holdToTalkTimeoutTask: Task<Void, Never>?

  var currentAudioLevel: Float {
    audioLevelLock.lock()
    defer { audioLevelLock.unlock() }
    return latestAudioLevel
  }

  init(
    coordinatorBridge: VoiceSpeechCaptureCoordinatorBridge = VoiceSpeechCaptureCoordinatorBridge(),
    liveWhisperScheduler: VoiceWhisperDecodeScheduling? = nil,
    liveWhisperController: VoiceLiveWhisperCaptureController? = nil
  ) {
    self.coordinatorBridge = coordinatorBridge
    self.liveWhisperScheduler = liveWhisperScheduler ??
      VoiceWhisperRuntimeDecodeSchedulerAdapter(runtime: DefaultVoiceLocalWhisperRuntime()).makeScheduler()
    self.liveWhisperController = liveWhisperController ??
      VoiceLiveWhisperCaptureController(
        coordinatorBridge: VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: coordinatorBridge)
      )
    super.init()
    self.liveWhisperController.setUpdateHandler { [weak self] update in
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.liveWhisperActive else { return }
        self.stableTranscript = update.transcript.stableText
        self.unstableTranscript = update.transcript.unstableText
        let displayText = update.transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcript = displayText
      }
    }
    self.liveWhisperController.setTransitionHandler { [weak self] transition in
      DispatchQueue.main.async { [weak self] in
        self?.emitCommands(transition)
      }
    }
  }

  func requestAuthorization(localeIdentifier: String) async -> Bool {
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    let speechGranted = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    let micGranted = await AVAudioSession.sharedInstance().requestRecordPermission()
    return speechGranted && micGranted
  }

  func requestAuthorization(settings: VoiceSettings) async -> Bool {
    let normalized = settings.normalized
    let capabilities = VoiceProviderCapabilityDetector.detect(
      settings: normalized,
      validatedNetworkAvailable: false
    )
    activateLocalWhisperPipelineIfReady(settings: normalized, capabilities: capabilities)
    let authorizationRequirement = VoiceASRProviderRoutingPolicy.authorizationRequirement(
      settings: normalized,
      capabilities: capabilities,
      pcmCaptureEnabled: VoiceFeatureFlags.isPcmCaptureEnabled(),
      localRuntimeEnabled: VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(),
      adaptivePartialEnabled: VoiceFeatureFlags.isWhisperAdaptivePartialEnabled()
    )
    let micGranted = await AVAudioSession.sharedInstance().requestRecordPermission()
    guard micGranted else { return false }
    guard authorizationRequirement == .microphoneAndSystemSpeech else { return true }
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: normalized.preferredLocaleIdentifier))
    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  @MainActor
  func start(localeIdentifier: String) throws {
    try start(localeIdentifier: localeIdentifier, settings: nil, coordinatorConfig: nil)
  }

  @MainActor
  func start(settings: VoiceSettings, source: String = "ios_hold_to_talk") throws {
    let normalized = settings.normalized
    try start(
      localeIdentifier: normalized.preferredLocaleIdentifier,
      settings: normalized,
      coordinatorConfig: VoiceSpeechCaptureCoordinatorBridge.config(settings: normalized, source: source)
    )
  }

  @MainActor
  private func start(
    localeIdentifier: String,
    settings: VoiceSettings?,
    coordinatorConfig: VoiceSessionConfig?
  ) throws {
    if let coordinatorConfig = coordinatorConfig {
      coordinatorBridge.begin(config: coordinatorConfig)
    }
    let useLocalWhisper: Bool
    let useOnlineRealtime: Bool
    let useRemoteWhisper: Bool
    if let settings {
      if settings.asrProvider == .onlineRealtime {
        VoiceFeatureFlags.setOnlineRealtimeASREnabled(true)
      }
      if settings.asrProvider == .remoteWhisper {
        VoiceFeatureFlags.setRemoteWhisperNodeEnabled(true)
      }
      let networkProbe = AgentMediaNetworkDetector.shared.currentProbe
      let validatedNetworkAvailable = networkProbe.networkPresent &&
        networkProbe.internetCapable && networkProbe.validated
      let capabilities = VoiceProviderCapabilityDetector.detect(
        settings: settings,
        validatedNetworkAvailable: validatedNetworkAvailable
      )
      activateLocalWhisperPipelineIfReady(settings: settings, capabilities: capabilities)
      useLocalWhisper = VoiceASRProviderRoutingPolicy.shouldUseLocalWhisper(
        settings: settings,
        capabilities: capabilities,
        pcmCaptureEnabled: VoiceFeatureFlags.isPcmCaptureEnabled(),
        localRuntimeEnabled: VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(),
        adaptivePartialEnabled: VoiceFeatureFlags.isWhisperAdaptivePartialEnabled()
      )
      useOnlineRealtime = VoiceASRProviderRoutingPolicy.shouldUseOnlineRealtime(
        settings: settings,
        capabilities: capabilities,
        onlineRealtimeAvailable: VoiceOnlineRealtimeASRConfiguration.isConfigured &&
          validatedNetworkAvailable &&
          (!settings.onlineAsrWifiOnly || !networkProbe.cellular)
      )
      useRemoteWhisper = VoiceASRProviderRoutingPolicy.shouldUseRemoteWhisper(
        settings: settings,
        capabilities: capabilities,
        remoteWhisperAvailable: VoiceRemoteWhisperCaptureRuntime.shared.isAvailable
      )
    } else {
      useLocalWhisper = false
      useOnlineRealtime = false
      useRemoteWhisper = false
    }
    transcript = ""
    stableTranscript = ""
    unstableTranscript = ""
    currentIOSSpeechTranscript = ""
    updateAudioLevel(0)
    currentRecognitionModelProfileId = useLocalWhisper ? settings?.asrModelId ?? "" : localeIdentifier
    currentRecognitionProvider = useLocalWhisper ? voiceLocalWhisperProviderId : iosSpeechProviderId
    onlineRealtimeActive = useOnlineRealtime
    onlineRealtimeFinalizing = false
    onlineRealtimeHasTranscript = false
    onlineRealtimeProvider = "signalasi_realtime"
    onlineRealtimeModelProfileId = ""
    onlineRealtimeTimeoutTask?.cancel()
    onlineRealtimeTimeoutTask = nil
    remoteWhisperActive = useRemoteWhisper
    remoteWhisperLanguage = useRemoteWhisper ? localeIdentifier : ""
    if useLocalWhisper {
      recognizer = nil
      request = nil
    } else {
      recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
      guard recognizer != nil else {
        let error = SpeechCaptureServiceError.recognizerUnavailable
        if coordinatorConfig != nil {
          coordinatorBridge.failCurrent(code: "ios_speech_recognizer_unavailable", detail: error.localizedDescription)
        }
        throw error
      }
      request = SFSpeechAudioBufferRecognitionRequest()
      guard let request = request else {
        let error = SpeechCaptureServiceError.requestUnavailable
        if coordinatorConfig != nil {
          coordinatorBridge.failCurrent(code: "ios_speech_request_unavailable", detail: error.localizedDescription)
        }
        throw error
      }
      request.shouldReportPartialResults = true
    }
    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    inputSampleRateHz = max(1, Int(format.sampleRate.rounded()))
    let pcmCaptureEnabled = coordinatorConfig != nil &&
      (VoiceFeatureFlags.isPcmCaptureEnabled() || useLocalWhisper || useOnlineRealtime || useRemoteWhisper)
    if pcmCaptureEnabled {
      pcmTapPipeline = VoicePcmTapPipeline(
        config: VoiceAudioSessionConfig(
          capture: PcmCaptureConfig(sampleRateHz: max(1, Int(format.sampleRate.rounded()))),
          endpoint: AdaptiveEndpointConfig(),
          autoEndpoint: coordinatorConfig?.source.localizedCaseInsensitiveContains("wake") == true
        )
      )
    } else {
      pcmTapPipeline = nil
    }
    pcmTapSpeechStarted = false
    pcmTapSpeechEnded = false
    pcmTapEndpointRequested = false
    liveWhisperActive = false
    let voiceSessionId = coordinatorBridge.sessionId()
    if let settings,
       useOnlineRealtime,
       !voiceSessionId.isEmpty {
      let config = VoiceOnlineRealtimeASRConfig(
        voiceSessionID: voiceSessionId,
        transcriptID: voiceSessionId,
        language: settings.preferredLocaleIdentifier,
        requestServerDataDeletion: settings.onlineAsrRequestServerDeletion
      )
      let session = VoiceOnlineRealtimeASRSession(config: config) { [weak self] event in
        Task { @MainActor in self?.handleOnlineRealtimeEvent(event) }
      }
      onlineRealtimeSession = session
      Task { await session.start() }
    } else {
      onlineRealtimeSession = nil
    }
    if let settings = settings,
       useLocalWhisper,
       !voiceSessionId.isEmpty {
      liveWhisperActive = liveWhisperController.start(
        voiceSessionId: voiceSessionId,
        settings: settings,
        scheduler: liveWhisperScheduler,
        queue: liveWhisperScheduler.queueSnapshot()
      )
    }
    if useLocalWhisper, !liveWhisperActive {
      let error = SpeechCaptureServiceError.localWhisperUnavailable
      if coordinatorConfig != nil {
        coordinatorBridge.failCurrent(code: "ios_local_whisper_unavailable", detail: error.localizedDescription)
      }
      throw error
    }
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
      self?.processPcmTap(buffer)
    }
    currentRuntimeChannel = liveWhisperActive
      ? .localWhisperASR
      : useOnlineRealtime
        ? .onlineRealtimeASR
        : useRemoteWhisper ? .remoteWhisperASR : .androidSystemASR
    VoiceRuntimeHealthRegistry.begin(currentRuntimeChannel)
    do {
      try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
      audioEngine.prepare()
      try audioEngine.start()
    } catch {
      VoiceRuntimeHealthRegistry.failure(currentRuntimeChannel, reason: error.localizedDescription)
      liveWhisperController.close()
      liveWhisperActive = false
      if coordinatorConfig != nil {
        coordinatorBridge.failCurrent(code: "ios_speech_capture_failed", detail: error.localizedDescription)
      }
      throw error
    }
    isRecording = true
    if coordinatorConfig != nil {
      coordinatorBridge.capturePrepared()
      if pcmTapPipeline == nil {
        coordinatorBridge.speechStarted()
      }
    }
    guard let recognizer = recognizer, let request = request else { return }
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let result = result {
          let text = result.bestTranscription.formattedString
          self.currentIOSSpeechTranscript = text
          if !self.liveWhisperActive && !self.onlineRealtimeHasTranscript {
            self.transcript = text
          }
          if result.isFinal {
            if !self.liveWhisperActive &&
              !self.onlineRealtimeActive &&
              !self.onlineRealtimeFinalizing &&
              !self.remoteWhisperActive {
              self.stableTranscript = text
              self.unstableTranscript = ""
              self.emitCommands(
                self.coordinatorBridge.finishWithBestTranscript(
                  text,
                  provider: self.currentRecognitionProvider,
                  modelProfileId: self.currentRecognitionModelProfileId
                )
              )
            }
          } else {
            if !self.liveWhisperActive && !self.onlineRealtimeHasTranscript {
              let transition = self.coordinatorBridge.transcriptPartial(
                text,
                provider: self.currentRecognitionProvider,
                modelProfileId: self.currentRecognitionModelProfileId
              )
              self.stableTranscript = transition.current.stableText
              self.unstableTranscript = transition.current.partialText
            }
          }
        }
        if let error = error, self.isRecording {
          if self.liveWhisperActive || self.onlineRealtimeActive || self.remoteWhisperActive {
            VoiceRuntimeHealthRegistry.failure(.androidSystemASR, reason: error.localizedDescription)
          } else {
            VoiceRuntimeHealthRegistry.failure(self.currentRuntimeChannel, reason: error.localizedDescription)
            self.coordinatorBridge.failCurrent(
              code: "ios_speech_capture_failed",
              detail: error.localizedDescription
            )
          }
        } else if result?.isFinal == true,
                  !self.liveWhisperActive,
                  !self.onlineRealtimeActive,
                  !self.onlineRealtimeFinalizing,
                  !self.remoteWhisperActive {
          VoiceRuntimeHealthRegistry.success(self.currentRuntimeChannel)
        }
        if self.isRecording,
           (error != nil || result?.isFinal == true),
           self.onlineRealtimeActive {
          Task { @MainActor in self.stop() }
        } else if self.isRecording,
           (error != nil || result?.isFinal == true),
           self.remoteWhisperActive {
          Task { @MainActor in self.stop() }
        } else if (error != nil || result?.isFinal == true),
                  !self.liveWhisperActive,
                  !self.onlineRealtimeFinalizing {
          if self.holdToTalkCompletion != nil {
            let receivedFinal = result?.isFinal == true
            Task { @MainActor in
              self.completeHoldToTalkStop(receivedFinal: receivedFinal)
            }
          } else {
            Task { @MainActor in self.stop() }
          }
        }
      }
    }
  }

  private func activateLocalWhisperPipelineIfReady(
    settings: VoiceSettings,
    capabilities: VoiceProviderCapabilitySnapshot
  ) {
    let provider = settings.normalized.asrProvider
    guard provider == .automatic || provider == .localWhisperCpp else { return }
    let localWhisper = capabilities[.whisperCpp]
    guard localWhisper.state == .ready || localWhisper.state == .needsPermission else { return }
    VoiceFeatureFlags.activateCoreLocalWhisperPipelineIfUnconfigured()
  }

  /// Ends the microphone input while allowing Apple's recognizer to deliver its final result.
  /// Android's hold-to-talk flow sends on release, but cancelling the iOS task at that moment
  /// discards the final partial transcript.
  @MainActor
  func stopForHoldToTalk(completion: @escaping (String) -> Void) {
    guard isRecording else {
      completion(currentIOSSpeechTranscript.ifBlank(transcript))
      return
    }
    if liveWhisperActive || onlineRealtimeActive || onlineRealtimeFinalizing || remoteWhisperActive {
      // Whisper finalization runs asynchronously from the retained PCM snapshot. Do not
      // report an empty result on release while that final decode is still in flight.
      holdToTalkCompletion = completion
      stop(preservingHoldToTalkCompletion: true)
      return
    }

    holdToTalkCompletion = completion
    holdToTalkTimeoutTask?.cancel()
    holdToTalkTimeoutTask = nil
    isRecording = false
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()

    holdToTalkTimeoutTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 900_000_000)
      guard !Task.isCancelled else { return }
      await self?.completeHoldToTalkStop(receivedFinal: false)
    }
  }

  @MainActor
  private func completeHoldToTalkStop(receivedFinal: Bool) {
    guard let completion = holdToTalkCompletion else { return }
    holdToTalkCompletion = nil
    holdToTalkTimeoutTask?.cancel()
    holdToTalkTimeoutTask = nil

    let fallbackTranscript = currentIOSSpeechTranscript.ifBlank(transcript)
    let fallbackModelProfileId = currentRecognitionModelProfileId
    let fallbackProvider = currentRecognitionProvider
    let runtimeChannel = currentRuntimeChannel
    if !receivedFinal {
      emitCommands(
        coordinatorBridge.finishStoppedCapture(
          transcript: fallbackTranscript,
          provider: fallbackProvider,
          modelProfileId: fallbackModelProfileId
        )
      )
    }
    task?.cancel()
    task = nil
    request = nil
    currentRecognitionModelProfileId = ""
    currentRecognitionProvider = iosSpeechProviderId
    currentIOSSpeechTranscript = ""
    stableTranscript = ""
    unstableTranscript = ""
    updateAudioLevel(0)
    pcmTapPipeline = nil
    pcmTapSpeechStarted = false
    pcmTapSpeechEnded = false
    pcmTapEndpointRequested = false
    liveWhisperController.close()
    liveWhisperActive = false
    onlineRealtimeTimeoutTask?.cancel()
    onlineRealtimeTimeoutTask = nil
    if let onlineRealtimeSession {
      Task { await onlineRealtimeSession.cancel(reason: "session_closed") }
    }
    onlineRealtimeSession = nil
    onlineRealtimeActive = false
    onlineRealtimeFinalizing = false
    onlineRealtimeHasTranscript = false
    remoteWhisperActive = false
    remoteWhisperLanguage = ""
    VoiceRuntimeHealthRegistry.idle(runtimeChannel)

    // Let a final coordinator command reach the hold-to-talk controller first.
    Task { @MainActor in
      await Task.yield()
      completion(fallbackTranscript)
    }
  }

  @MainActor
  func stop() {
    stop(preservingHoldToTalkCompletion: false)
  }

  @MainActor
  func cancel() {
    let runtimeChannel = currentRuntimeChannel
    holdToTalkTimeoutTask?.cancel()
    holdToTalkTimeoutTask = nil
    holdToTalkCompletion = nil
    onlineRealtimeTimeoutTask?.cancel()
    onlineRealtimeTimeoutTask = nil

    isRecording = false
    onlineRealtimeActive = false
    onlineRealtimeFinalizing = false
    onlineRealtimeHasTranscript = false
    remoteWhisperActive = false
    remoteWhisperLanguage = ""
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    if let onlineRealtimeSession {
      Task { await onlineRealtimeSession.cancel(reason: "user_cancelled") }
    }
    onlineRealtimeSession = nil
    liveWhisperController.close()
    liveWhisperActive = false
    pcmTapPipeline = nil
    pcmTapSpeechStarted = false
    pcmTapSpeechEnded = false
    pcmTapEndpointRequested = false
    currentRecognitionModelProfileId = ""
    currentRecognitionProvider = iosSpeechProviderId
    currentIOSSpeechTranscript = ""
    stableTranscript = ""
    unstableTranscript = ""
    transcript = ""
    updateAudioLevel(0)
    _ = coordinatorBridge.cancelCurrent(reasonCode: "user_cancelled")
    VoiceRuntimeHealthRegistry.idle(runtimeChannel)
  }

  @MainActor
  private func stop(preservingHoldToTalkCompletion: Bool) {
    holdToTalkTimeoutTask?.cancel()
    holdToTalkTimeoutTask = nil
    if !preservingHoldToTalkCompletion {
      holdToTalkCompletion = nil
    }
    if onlineRealtimeActive || onlineRealtimeFinalizing {
      beginOnlineRealtimeFinalization()
      return
    }
    let wasRecording = isRecording
    let fallbackTranscript = currentIOSSpeechTranscript.ifBlank(transcript)
    let fallbackModelProfileId = currentRecognitionModelProfileId
    let fallbackProvider = currentRecognitionProvider
    let runtimeChannel = currentRuntimeChannel
    let finalSnapshot = wasRecording && (liveWhisperActive || remoteWhisperActive)
      ? pcmTapPipeline?.snapshot()
      : nil
    let shouldRunLiveFinal = liveWhisperActive && finalSnapshot?.samples.isEmpty == false
    let shouldRunRemoteFinal = remoteWhisperActive && finalSnapshot?.samples.isEmpty == false
    isRecording = false
    if wasRecording, !shouldRunLiveFinal && !shouldRunRemoteFinal {
      emitCommands(
        coordinatorBridge.finishStoppedCapture(
          transcript: fallbackTranscript,
          provider: fallbackProvider,
          modelProfileId: fallbackModelProfileId
        )
      )
    } else if wasRecording {
      coordinatorBridge.finalizationStarted()
    }
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    currentRecognitionModelProfileId = ""
    currentRecognitionProvider = iosSpeechProviderId
    currentIOSSpeechTranscript = ""
    stableTranscript = ""
    unstableTranscript = ""
    updateAudioLevel(0)
    pcmTapPipeline = nil
    pcmTapSpeechStarted = false
    pcmTapSpeechEnded = false
    pcmTapEndpointRequested = false
    if shouldRunRemoteFinal, let finalSnapshot {
      finalizeStoppedRemoteWhisperCapture(
        snapshot: finalSnapshot,
        fallbackTranscript: fallbackTranscript,
        fallbackModelProfileId: fallbackModelProfileId,
        fallbackProvider: fallbackProvider,
        runtimeChannel: runtimeChannel
      )
    } else if shouldRunLiveFinal, let finalSnapshot {
      finalizeStoppedLiveWhisperCapture(
        snapshot: finalSnapshot,
        fallbackTranscript: fallbackTranscript,
        fallbackModelProfileId: fallbackModelProfileId,
        fallbackProvider: fallbackProvider,
        runtimeChannel: runtimeChannel
      )
    } else {
      liveWhisperController.close()
      liveWhisperActive = false
      if let onlineRealtimeSession {
        Task { await onlineRealtimeSession.cancel(reason: "session_closed") }
      }
      onlineRealtimeSession = nil
      onlineRealtimeActive = false
      onlineRealtimeFinalizing = false
      onlineRealtimeHasTranscript = false
      remoteWhisperActive = false
      remoteWhisperLanguage = ""
      if wasRecording {
        VoiceRuntimeHealthRegistry.idle(runtimeChannel)
      }
    }
  }

  @MainActor
  private func beginOnlineRealtimeFinalization() {
    guard onlineRealtimeActive, !onlineRealtimeFinalizing else { return }
    let wasRecording = isRecording
    onlineRealtimeActive = false
    onlineRealtimeFinalizing = true
    isRecording = false
    if wasRecording {
      coordinatorBridge.finalizationStarted()
    }
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    pcmTapPipeline = nil
    pcmTapSpeechStarted = false
    pcmTapSpeechEnded = false
    pcmTapEndpointRequested = false
    if let onlineRealtimeSession {
      Task { await onlineRealtimeSession.finishInput() }
    }
    onlineRealtimeTimeoutTask?.cancel()
    onlineRealtimeTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      guard !Task.isCancelled, let self else { return }
      self.completeOnlineRealtimeFinalization(
        text: "",
        provider: iosSpeechProviderId,
        modelProfileID: self.currentRecognitionModelProfileId,
        succeeded: false,
        failureReason: "final_timeout"
      )
    }
  }

  @MainActor
  private func handleOnlineRealtimeEvent(_ event: VoiceOnlineRealtimeASREvent) {
    switch event {
    case .ready(let provider, let modelProfileID):
      onlineRealtimeProvider = provider.ifBlank("signalasi_realtime")
      onlineRealtimeModelProfileId = modelProfileID
    case .partial(let hypothesis, let stable):
      guard onlineRealtimeActive || onlineRealtimeFinalizing else { return }
      let text = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return }
      transcript = text
      onlineRealtimeHasTranscript = true
      onlineRealtimeProvider = hypothesis.provider.ifBlank(onlineRealtimeProvider)
      onlineRealtimeModelProfileId = hypothesis.modelProfileId
      let transition = stable
        ? coordinatorBridge.transcriptStable(
          text,
          provider: onlineRealtimeProvider,
          modelProfileId: onlineRealtimeModelProfileId
        )
        : coordinatorBridge.transcriptPartial(
          text,
          provider: onlineRealtimeProvider,
          modelProfileId: onlineRealtimeModelProfileId
        )
      stableTranscript = transition.current.stableText
      unstableTranscript = transition.current.partialText
    case .final(let hypothesis):
      guard onlineRealtimeActive || onlineRealtimeFinalizing else { return }
      if !onlineRealtimeFinalizing {
        beginOnlineRealtimeFinalization()
      }
      completeOnlineRealtimeFinalization(
        text: hypothesis.text,
        provider: hypothesis.provider.ifBlank(onlineRealtimeProvider),
        modelProfileID: hypothesis.modelProfileId.ifBlank(onlineRealtimeModelProfileId),
        succeeded: true,
        failureReason: ""
      )
    case .failed(let code, let message):
      VoiceRuntimeHealthRegistry.failure(.onlineRealtimeASR, reason: message.ifBlank(code))
      if onlineRealtimeFinalizing {
        completeOnlineRealtimeFinalization(
          text: "",
          provider: iosSpeechProviderId,
          modelProfileID: currentRecognitionModelProfileId,
          succeeded: false,
          failureReason: code
        )
      } else {
        onlineRealtimeActive = false
        onlineRealtimeHasTranscript = false
        onlineRealtimeSession = nil
        currentRuntimeChannel = .androidSystemASR
      }
    }
  }

  @MainActor
  private func completeOnlineRealtimeFinalization(
    text: String,
    provider: String,
    modelProfileID: String,
    succeeded: Bool,
    failureReason: String
  ) {
    guard onlineRealtimeFinalizing else { return }
    onlineRealtimeTimeoutTask?.cancel()
    onlineRealtimeTimeoutTask = nil
    let fallback = currentIOSSpeechTranscript.ifBlank(transcript)
    let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(fallback)
    emitCommands(
      coordinatorBridge.finishStoppedCapture(
        transcript: finalText,
        provider: succeeded ? provider : iosSpeechProviderId,
        modelProfileId: succeeded ? modelProfileID : currentRecognitionModelProfileId
      )
    )
    task?.cancel()
    task = nil
    request = nil
    currentRecognitionModelProfileId = ""
    currentRecognitionProvider = iosSpeechProviderId
    currentIOSSpeechTranscript = ""
    stableTranscript = finalText
    unstableTranscript = ""
    transcript = finalText
    updateAudioLevel(0)
    if let onlineRealtimeSession {
      Task { await onlineRealtimeSession.cancel(reason: succeeded ? "final_received" : failureReason) }
    }
    onlineRealtimeSession = nil
    onlineRealtimeActive = false
    onlineRealtimeFinalizing = false
    onlineRealtimeHasTranscript = false
    if succeeded {
      VoiceRuntimeHealthRegistry.success(.onlineRealtimeASR)
    }
    VoiceRuntimeHealthRegistry.idle(.onlineRealtimeASR)
    completeDeferredHoldToTalkStop(with: finalText)
  }

  @MainActor
  private func finalizeStoppedRemoteWhisperCapture(
    snapshot: PcmSnapshot,
    fallbackTranscript: String,
    fallbackModelProfileId: String,
    fallbackProvider: String,
    runtimeChannel: VoiceRuntimeChannel
  ) {
    let sessionID = coordinatorBridge.sessionId().ifBlank(UUID().uuidString.lowercased())
    let transcriptID = UUID().uuidString.lowercased()
    let language = remoteWhisperLanguage.ifBlank(Locale.current.identifier)
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let result = try await VoiceRemoteWhisperCaptureRuntime.shared.transcribe(
          sessionID: sessionID,
          transcriptID: transcriptID,
          snapshot: snapshot,
          language: language
        )
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcript = text.ifBlank(fallbackTranscript)
        self.stableTranscript = self.transcript
        self.unstableTranscript = ""
        self.emitCommands(
          self.coordinatorBridge.finishStoppedCapture(
            transcript: self.transcript,
            provider: "remote_whisper",
            modelProfileId: result.profile.id
          )
        )
        self.remoteWhisperActive = false
        self.remoteWhisperLanguage = ""
        VoiceRuntimeHealthRegistry.success(runtimeChannel)
        VoiceRuntimeHealthRegistry.idle(runtimeChannel)
        self.completeDeferredHoldToTalkStop(with: self.transcript)
      } catch {
        self.emitCommands(
          self.coordinatorBridge.finishStoppedCapture(
            transcript: fallbackTranscript,
            provider: fallbackProvider,
            modelProfileId: fallbackModelProfileId
          )
        )
        self.remoteWhisperActive = false
        self.remoteWhisperLanguage = ""
        VoiceRuntimeHealthRegistry.failure(runtimeChannel, reason: error.localizedDescription)
        VoiceRuntimeHealthRegistry.idle(runtimeChannel)
        self.completeDeferredHoldToTalkStop(with: fallbackTranscript)
      }
    }
  }

  private func finalizeStoppedLiveWhisperCapture(
    snapshot: PcmSnapshot,
    fallbackTranscript: String,
    fallbackModelProfileId: String,
    fallbackProvider: String,
    runtimeChannel: VoiceRuntimeChannel
  ) {
    let controller = liveWhisperController
    Task {
      do {
        guard let result = try await controller.finish(snapshot) else {
          throw SpeechCaptureLiveWhisperFinalizationError.sessionUnavailable
        }
        await MainActor.run {
          let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty {
            self.transcript = text
          }
          controller.close()
          self.liveWhisperActive = false
          VoiceRuntimeHealthRegistry.success(runtimeChannel)
          VoiceRuntimeHealthRegistry.idle(runtimeChannel)
          self.completeDeferredHoldToTalkStop(with: text.ifBlank(fallbackTranscript))
        }
      } catch {
        await MainActor.run {
          controller.close()
          self.liveWhisperActive = false
          var isIncompleteFinal = false
          if let failure = error as? VoiceLiveWhisperTranscriptionSessionFailure {
            if case .finalTranscriptIncomplete = failure {
              isIncompleteFinal = true
            }
          }
          if isIncompleteFinal {
            // The system recognizer fallback remains usable when Whisper coverage is incomplete.
            VoiceRuntimeHealthRegistry.success(runtimeChannel)
          } else {
            VoiceRuntimeHealthRegistry.failure(runtimeChannel, reason: error.localizedDescription)
          }
          self.emitCommands(
            self.coordinatorBridge.finishStoppedCapture(
              transcript: fallbackTranscript,
              provider: fallbackProvider,
              modelProfileId: fallbackModelProfileId
            )
          )
          VoiceRuntimeHealthRegistry.idle(runtimeChannel)
          self.completeDeferredHoldToTalkStop(with: fallbackTranscript)
        }
      }
    }
  }

  @MainActor
  private func completeDeferredHoldToTalkStop(with transcript: String) {
    guard let completion = holdToTalkCompletion else { return }
    holdToTalkCompletion = nil
    Task { @MainActor in
      // The final coordinator event is scheduled on the main queue. Yield once so it
      // can update the live transcript before the composer decides whether to submit.
      await Task.yield()
      completion(transcript)
    }
  }

  private func processPcmTap(_ buffer: AVAudioPCMBuffer) {
    guard let update = pcmTapPipeline?.accept(buffer: buffer) else { return }
    if onlineRealtimeActive, let onlineRealtimeSession {
      let sampleRateHz = inputSampleRateHz
      Task {
        await onlineRealtimeSession.push(
          frame: update.frame,
          sourceSampleRateHz: sampleRateHz
        )
      }
    }
    updateAudioLevel(Float(update.decision.peak) / Float(Int16.max))
    coordinatorBridge.dispatchAudioLevel(update.decision.rms)
    if update.endpoint.speechStarted, !pcmTapSpeechStarted {
      pcmTapSpeechStarted = true
      coordinatorBridge.speechStarted(atElapsedNs: update.frame.captureTimeNanos)
      if liveWhisperActive {
        liveWhisperController.handleSpeechStarted(nowMillis: update.frame.captureTimeNanos / 1_000_000)
      }
    }
    if liveWhisperActive {
      liveWhisperController.handleAudioLevel(
        isSpeech: update.decision.isSpeech,
        nowMillis: update.frame.captureTimeNanos / 1_000_000
      ) { [weak self] windowMillis in
        self?.pcmTapPipeline?.snapshotWindow(maxDurationMs: windowMillis)
      }
    }
    if update.endpoint.speechEndedCandidate, !pcmTapSpeechEnded {
      pcmTapSpeechEnded = true
      coordinatorBridge.speechEnded(atElapsedNs: update.frame.captureTimeNanos)
    }
    guard let reason = update.endpoint.endpointReason else { return }
    let code = reason == .noSpeechTimeout ? "no_speech_timeout" :
      reason == .maxDuration ? "max_duration" : "trailing_silence"
    if reason != .noSpeechTimeout, !pcmTapSpeechEnded {
      pcmTapSpeechEnded = true
      coordinatorBridge.speechEnded(atElapsedNs: update.frame.captureTimeNanos)
    }
    guard !pcmTapEndpointRequested else { return }
    pcmTapEndpointRequested = true
    Task { [weak self] in
      await MainActor.run {
        guard let self = self, self.isRecording else { return }
        if reason == .noSpeechTimeout {
          _ = self.coordinatorBridge.cancelCurrent(reasonCode: code)
        }
        self.stop()
      }
    }
  }

  private func updateAudioLevel(_ value: Float) {
    audioLevelLock.lock()
    latestAudioLevel = min(max(value, 0), 1)
    audioLevelLock.unlock()
  }

  private func emitCommands(_ transition: VoiceInteractionTransition) {
    transition.commands.forEach { onVoiceCommand?($0) }
  }
}

private extension AVAudioSession {
  func requestRecordPermission() async -> Bool {
    await withCheckedContinuation { continuation in
      requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }
}

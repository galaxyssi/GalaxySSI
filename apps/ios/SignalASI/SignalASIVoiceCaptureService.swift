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
    if let settings {
      let capabilities = VoiceProviderCapabilityDetector.detect(
        settings: settings,
        validatedNetworkAvailable: false
      )
      activateLocalWhisperPipelineIfReady(settings: settings, capabilities: capabilities)
      useLocalWhisper = VoiceASRProviderRoutingPolicy.shouldUseLocalWhisper(
        settings: settings,
        capabilities: capabilities,
        pcmCaptureEnabled: VoiceFeatureFlags.isPcmCaptureEnabled(),
        localRuntimeEnabled: VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(),
        adaptivePartialEnabled: VoiceFeatureFlags.isWhisperAdaptivePartialEnabled()
      )
    } else {
      useLocalWhisper = false
    }
    transcript = ""
    stableTranscript = ""
    unstableTranscript = ""
    currentIOSSpeechTranscript = ""
    updateAudioLevel(0)
    currentRecognitionModelProfileId = useLocalWhisper ? settings?.asrModelId ?? "" : localeIdentifier
    currentRecognitionProvider = useLocalWhisper ? voiceLocalWhisperProviderId : iosSpeechProviderId
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
    let pcmCaptureEnabled = coordinatorConfig != nil && (VoiceFeatureFlags.isPcmCaptureEnabled() || useLocalWhisper)
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
    currentRuntimeChannel = liveWhisperActive ? .localWhisperASR : .androidSystemASR
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
          if !self.liveWhisperActive {
            self.transcript = text
          }
          if result.isFinal {
            if !self.liveWhisperActive {
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
            if !self.liveWhisperActive {
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
          if self.liveWhisperActive {
            VoiceRuntimeHealthRegistry.failure(.androidSystemASR, reason: error.localizedDescription)
          } else {
            VoiceRuntimeHealthRegistry.failure(self.currentRuntimeChannel, reason: error.localizedDescription)
            self.coordinatorBridge.failCurrent(
              code: "ios_speech_capture_failed",
              detail: error.localizedDescription
            )
          }
        } else if result?.isFinal == true, !self.liveWhisperActive {
          VoiceRuntimeHealthRegistry.success(self.currentRuntimeChannel)
        }
        if (error != nil || result?.isFinal == true), !self.liveWhisperActive {
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
    if liveWhisperActive {
      // Local Whisper finishes asynchronously from the retained PCM snapshot. Do not
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
  private func stop(preservingHoldToTalkCompletion: Bool) {
    holdToTalkTimeoutTask?.cancel()
    holdToTalkTimeoutTask = nil
    if !preservingHoldToTalkCompletion {
      holdToTalkCompletion = nil
    }
    let wasRecording = isRecording
    let fallbackTranscript = currentIOSSpeechTranscript.ifBlank(transcript)
    let fallbackModelProfileId = currentRecognitionModelProfileId
    let fallbackProvider = currentRecognitionProvider
    let runtimeChannel = currentRuntimeChannel
    let liveFinalSnapshot = wasRecording && liveWhisperActive ? pcmTapPipeline?.snapshot() : nil
    let shouldRunLiveFinal = liveFinalSnapshot?.samples.isEmpty == false
    isRecording = false
    if wasRecording, !shouldRunLiveFinal {
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
    if shouldRunLiveFinal, let liveFinalSnapshot = liveFinalSnapshot {
      finalizeStoppedLiveWhisperCapture(
        snapshot: liveFinalSnapshot,
        fallbackTranscript: fallbackTranscript,
        fallbackModelProfileId: fallbackModelProfileId,
        fallbackProvider: fallbackProvider,
        runtimeChannel: runtimeChannel
      )
    } else {
      liveWhisperController.close()
      liveWhisperActive = false
      if wasRecording {
        VoiceRuntimeHealthRegistry.idle(runtimeChannel)
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
          self.completeLiveWhisperHoldToTalkStop(with: text.ifBlank(fallbackTranscript))
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
          self.completeLiveWhisperHoldToTalkStop(with: fallbackTranscript)
        }
      }
    }
  }

  @MainActor
  private func completeLiveWhisperHoldToTalkStop(with transcript: String) {
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

import AVFoundation
import Combine
import Foundation

final class VoiceReplySpeechService: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
  @Published private(set) var isSpeaking = false
  @Published private(set) var lastErrorDescription = ""

  private let synthesizer: AVSpeechSynthesizer
  private let edgeTTS: VoiceMicrosoftEdgeTTS
  private let latencyTracer: VoiceLatencyTracer?
  private let systemTTSRequests = VoiceTTSRequestRegistry()
  private var activeRequest: VoiceReplyPlaybackRequest?
  private var activeSystemUtterance: AVSpeechUtterance?
  private var edgePlayer: AVAudioPlayer?
  private var edgeSynthesisTask: Task<Void, Never>?
  private var onPlaybackStarted: ((VoiceReplyPlaybackRequest) -> Void)?
  private var onDone: ((VoiceReplyPlaybackRequest, Bool, String?) -> Void)?

  init(
    synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
    edgeTTS: VoiceMicrosoftEdgeTTS = VoiceMicrosoftEdgeTTS(),
    latencyTracer: VoiceLatencyTracer? = VoiceLatencyTelemetry.tracer()
  ) {
    self.synthesizer = synthesizer
    self.edgeTTS = edgeTTS
    self.latencyTracer = latencyTracer
    super.init()
    self.synthesizer.delegate = self
  }

  @MainActor
  func speak(
    _ request: VoiceReplyPlaybackRequest,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    stop()
    let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      onDone(request, true, nil)
      return
    }
    if request.providerId == VoiceTTSProvider.microsoftEdge.rawValue {
      speakWithEdge(request, onPlaybackStarted: onPlaybackStarted, onDone: onDone)
      return
    }
    activeRequest = request
    self.onPlaybackStarted = onPlaybackStarted
    self.onDone = onDone
    lastErrorDescription = ""
    VoiceRuntimeHealthRegistry.begin(request.runtimeChannel)
    recordLatency(
      request,
      event: VoiceTraceEvents.ttsRequestStarted,
      attributes: ["tts_provider": request.providerId],
      once: true
    )

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: request.language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    activeSystemUtterance = utterance
    systemTTSRequests.begin(VoiceTTSRequest(
      utteranceId: request.utteranceId,
      traceId: request.sessionId,
      onFinished: {}
    ))
    synthesizer.speak(utterance)
  }

  @MainActor
  func stop() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    if let request = activeRequest, request.providerId == VoiceTTSProvider.microsoftEdge.rawValue {
      edgeSynthesisTask?.cancel()
      edgeSynthesisTask = nil
      edgePlayer?.stop()
      edgePlayer = nil
      completeActiveRequest(request, success: false, error: "Speech playback was cancelled", errorCode: "tts_cancelled")
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard self.activeSystemUtterance === utterance,
            let request = self.activeRequest,
            self.systemTTSRequests.isActive(request.utteranceId) else {
        return
      }
      self.isSpeaking = true
      self.recordLatency(
        request,
        event: VoiceTraceEvents.ttsFirstAudio,
        attributes: ["tts_provider": request.providerId],
        once: true
      )
      self.recordLatency(
        request,
        event: VoiceTraceEvents.ttsPlaybackStarted,
        attributes: ["tts_provider": request.providerId],
        once: true
      )
      self.onPlaybackStarted?(request)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard self.activeSystemUtterance === utterance,
            let request = self.activeRequest,
            self.systemTTSRequests.finish(request.utteranceId) != nil else {
        return
      }
      self.isSpeaking = false
      self.activeRequest = nil
      self.activeSystemUtterance = nil
      VoiceRuntimeHealthRegistry.success(request.runtimeChannel)
      self.recordLatency(
        request,
        event: VoiceTraceEvents.ttsCompleted,
        attributes: [
          "tts_provider": request.providerId,
          "success": "true",
        ],
        once: true
      )
      self.onDone?(request, true, nil)
      self.onPlaybackStarted = nil
      self.onDone = nil
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard self.activeSystemUtterance === utterance,
            let request = self.activeRequest,
            self.systemTTSRequests.finish(request.utteranceId) != nil else {
        return
      }
      self.activeSystemUtterance = nil
      self.completeActiveRequest(request, success: false, error: "Speech playback was cancelled", errorCode: "tts_cancelled")
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    DispatchQueue.main.async {
      guard self.edgePlayer === player, let request = self.activeRequest else { return }
      self.edgePlayer = nil
      self.completeActiveRequest(
        request,
        success: flag,
        error: flag ? nil : "Microsoft Edge TTS playback failed",
        errorCode: flag ? nil : "edge_audio_playback_failed"
      )
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    DispatchQueue.main.async {
      guard self.edgePlayer === player, let request = self.activeRequest else { return }
      self.edgePlayer = nil
      self.completeActiveRequest(
        request,
        success: false,
        error: error?.localizedDescription ?? "Microsoft Edge TTS audio decode failed",
        errorCode: "edge_audio_decode_failed"
      )
    }
  }

  private func speakWithEdge(
    _ request: VoiceReplyPlaybackRequest,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    activeSystemUtterance = nil
    systemTTSRequests.clear()
    activeRequest = request
    self.onPlaybackStarted = onPlaybackStarted
    self.onDone = onDone
    edgeSynthesisTask?.cancel()
    lastErrorDescription = ""
    VoiceRuntimeHealthRegistry.begin(request.runtimeChannel)

    edgeSynthesisTask = Task {
      do {
        let result = try await edgeTTS.synthesize(request)
        await MainActor.run {
          guard !Task.isCancelled, self.activeRequest == request else { return }
          self.edgeSynthesisTask = nil
          self.playEdgeAudio(result.audioData, request: request)
        }
      } catch {
        await MainActor.run {
          guard !Task.isCancelled, self.activeRequest == request else { return }
          self.edgeSynthesisTask = nil
          self.completeActiveRequest(
            request,
            success: false,
            error: error.localizedDescription,
            errorCode: self.edgeErrorCode(error)
          )
        }
      }
    }
  }

  @MainActor
  private func playEdgeAudio(_ audioData: Data, request: VoiceReplyPlaybackRequest) {
    do {
      let player = try AVAudioPlayer(data: audioData)
      player.delegate = self
      edgePlayer = player
      player.prepareToPlay()
      guard player.play() else {
        completeActiveRequest(
          request,
          success: false,
          error: "Microsoft Edge TTS playback failed",
          errorCode: "edge_audio_playback_failed"
        )
        return
      }
      isSpeaking = true
      recordLatency(
        request,
        event: VoiceTraceEvents.ttsPlaybackStarted,
        attributes: ["tts_provider": request.providerId],
        once: true
      )
      onPlaybackStarted?(request)
    } catch {
      completeActiveRequest(
        request,
        success: false,
        error: error.localizedDescription,
        errorCode: "edge_audio_decode_failed"
      )
    }
  }

  private func completeActiveRequest(
    _ request: VoiceReplyPlaybackRequest,
    success: Bool,
    error: String?,
    errorCode: String?
  ) {
    isSpeaking = false
    activeRequest = nil
    activeSystemUtterance = nil
    _ = systemTTSRequests.discard(request.utteranceId)
    edgeSynthesisTask = nil
    edgePlayer = nil
    if success {
      lastErrorDescription = ""
      VoiceRuntimeHealthRegistry.success(request.runtimeChannel)
    } else {
      lastErrorDescription = error ?? "Speech playback failed"
      VoiceRuntimeHealthRegistry.failure(request.runtimeChannel, reason: lastErrorDescription)
    }
    var attributes = [
      "tts_provider": request.providerId,
      "success": success ? "true" : "false",
    ]
    if let errorCode {
      attributes["error_code"] = errorCode
    }
    recordLatency(
      request,
      event: VoiceTraceEvents.ttsCompleted,
      attributes: attributes,
      once: true
    )
    onDone?(request, success, success ? nil : lastErrorDescription)
    onPlaybackStarted = nil
    onDone = nil
  }

  private func edgeErrorCode(_ error: Error) -> String {
    if let edgeError = error as? VoiceMicrosoftEdgeTTSError {
      switch edgeError {
      case .blankText: return "edge_blank_text"
      case .invalidEndpoint: return "edge_invalid_endpoint"
      case .runtimeUnavailable: return "edge_runtime_unavailable"
      case .timedOut: return "edge_timeout"
      case .emptyAudio: return "edge_empty_audio"
      }
    }
    return "edge_synthesis_failed"
  }

  private func recordLatency(
    _ request: VoiceReplyPlaybackRequest,
    event: String,
    attributes: [String: String],
    once: Bool
  ) {
    latencyTracer?.record(
      traceId: request.sessionId,
      sessionId: request.sessionId,
      event: event,
      attributes: attributes,
      once: once
    )
  }
}

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
  @discardableResult
  func stop() -> Bool {
    let hadActivePlayback = activeRequest != nil ||
      activeSystemUtterance != nil ||
      edgeSynthesisTask != nil ||
      isSpeaking ||
      synthesizer.isSpeaking
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
    return hadActivePlayback
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

@MainActor
final class VoiceProgressiveReplySpeechService: ObservableObject {
  @Published private(set) var isSpeaking = false

  private let inner: VoiceReplySpeechService
  private var cancellables = Set<AnyCancellable>()
  private var generation: UInt64 = 0
  private var activeRequest: VoiceReplyPlaybackRequest?
  private var inputBuffer = ""
  private var queuedChunks: [String] = []
  private var inputClosed = false
  private var chunkIndex = 0
  private var playingChunk = false
  private var reportedPlaybackStart = false
  private var onPlaybackStarted: ((VoiceReplyPlaybackRequest) -> Void)?
  private var onDone: ((VoiceReplyPlaybackRequest, Bool, String?) -> Void)?

  init(inner: VoiceReplySpeechService = VoiceReplySpeechService()) {
    self.inner = inner
    inner.$isSpeaking
      .receive(on: RunLoop.main)
      .sink { [weak self] value in
        self?.isSpeaking = value
      }
      .store(in: &cancellables)
  }

  @MainActor
  func speak(
    _ request: VoiceReplyPlaybackRequest,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    _ = stop()
    inner.speak(request, onPlaybackStarted: onPlaybackStarted, onDone: onDone)
  }

  @MainActor
  func beginProgressive(
    _ request: VoiceReplyPlaybackRequest,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    _ = stop()
    generation &+= 1
    activeRequest = request
    inputBuffer = ""
    queuedChunks = []
    inputClosed = false
    chunkIndex = 0
    playingChunk = false
    reportedPlaybackStart = false
    self.onPlaybackStarted = onPlaybackStarted
    self.onDone = onDone
  }

  @MainActor
  func appendProgressive(_ text: String, isFinal: Bool) {
    guard activeRequest != nil else { return }
    if !text.isEmpty {
      inputBuffer += text
    }
    if isFinal {
      inputClosed = true
    }
    let split = VoiceProgressiveSentenceChunker.split(inputBuffer, final: inputClosed)
    queuedChunks.append(contentsOf: split.committed)
    inputBuffer = split.remainder
    pump()
  }

  @MainActor
  func finishProgressive() {
    appendProgressive("", isFinal: true)
  }

  @MainActor
  func commitProgressive() {
    guard activeRequest != nil else { return }
    let committed = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !committed.isEmpty else { return }
    queuedChunks.append(committed)
    inputBuffer = ""
    pump()
  }

  @discardableResult
  @MainActor
  func stop() -> Bool {
    let request = activeRequest
    let hadProgressiveState = request != nil || playingChunk || !queuedChunks.isEmpty || !inputBuffer.isEmpty
    let done = onDone
    generation &+= 1
    activeRequest = nil
    inputBuffer = ""
    queuedChunks = []
    inputClosed = false
    playingChunk = false
    onPlaybackStarted = nil
    onDone = nil
    let hadInnerPlayback = inner.stop()
    if let request {
      done?(request, false, "Speech playback was cancelled")
    }
    return hadProgressiveState || hadInnerPlayback
  }

  private func pump() {
    guard !playingChunk,
          let baseRequest = activeRequest,
          let chunk = queuedChunks.first else {
      if let baseRequest = activeRequest,
         inputClosed,
         !playingChunk,
         queuedChunks.isEmpty,
         inputBuffer.isEmpty {
        finishProgressive(baseRequest, success: true, error: nil)
      }
      return
    }
    queuedChunks.removeFirst()
    playingChunk = true
    chunkIndex += 1
    let currentGeneration = generation
    var chunkRequest = baseRequest
    chunkRequest.utteranceId = baseRequest.utteranceId + ":chunk:" + String(chunkIndex)
    chunkRequest.text = chunk
    inner.speak(
      chunkRequest,
      onPlaybackStarted: { [weak self] _ in
        guard let self,
              self.generation == currentGeneration,
              self.activeRequest?.sessionId == baseRequest.sessionId else { return }
        if !self.reportedPlaybackStart {
          self.reportedPlaybackStart = true
          self.onPlaybackStarted?(baseRequest)
        }
      },
      onDone: { [weak self] _, success, error in
        guard let self else { return }
        Task { @MainActor in
          self.chunkFinished(
            generation: currentGeneration,
            request: baseRequest,
            success: success,
            error: error
          )
        }
      }
    )
  }

  private func chunkFinished(
    generation: UInt64,
    request: VoiceReplyPlaybackRequest,
    success: Bool,
    error: String?
  ) {
    guard self.generation == generation,
          activeRequest?.sessionId == request.sessionId else { return }
    playingChunk = false
    guard success else {
      finishProgressive(request, success: false, error: error)
      return
    }
    pump()
  }

  private func finishProgressive(
    _ request: VoiceReplyPlaybackRequest,
    success: Bool,
    error: String?
  ) {
    guard activeRequest?.sessionId == request.sessionId else { return }
    let done = onDone
    generation &+= 1
    activeRequest = nil
    inputBuffer = ""
    queuedChunks = []
    inputClosed = false
    playingChunk = false
    onPlaybackStarted = nil
    onDone = nil
    done?(request, success, error)
  }
}

private enum VoiceProgressiveSentenceChunker {
  private static let boundaries: Set<Character> = [".", "!", "?", ";", ":", "。", "！", "？", "；", "：", "\n"]

  static func split(_ text: String, final: Bool) -> (committed: [String], remainder: String) {
    guard !text.isEmpty else { return ([], "") }
    var committed: [String] = []
    var start = text.startIndex
    for index in text.indices {
      guard boundaries.contains(text[index]) else { continue }
      let end = text.index(after: index)
      let value = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        committed.append(value)
      }
      start = end
    }
    let remainder = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    if final, !remainder.isEmpty {
      committed.append(remainder)
      return (committed, "")
    }
    return (committed, remainder)
  }
}

import AVFoundation
import Combine
import Foundation

final class VoiceReplySpeechService: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
  @Published private(set) var isSpeaking = false
  @Published private(set) var lastErrorDescription = ""

  private let synthesizer: AVSpeechSynthesizer
  private let edgeTTS: VoiceMicrosoftEdgeTTS
  private let latencyTracer: VoiceLatencyTracer?
  private let tracksRuntimeHealth: Bool
  private let systemTTSRequests = VoiceTTSRequestRegistry()
  private var activeRequest: VoiceReplyPlaybackRequest?
  private var activeSystemUtterance: AVSpeechUtterance?
  private var edgePlayer: AVAudioPlayer?
  private var edgeReferenceId: UUID?
  weak var echoReference: VoicePlaybackEchoReference?
  private var activeEdgeAudioData: Data?
  private var edgeSynthesisTask: Task<Void, Never>?
  private var onPlaybackStarted: ((VoiceReplyPlaybackRequest) -> Void)?
  private var onDone: ((VoiceReplyPlaybackRequest, Bool, String?) -> Void)?

  init(
    synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
    edgeTTS: VoiceMicrosoftEdgeTTS = VoiceMicrosoftEdgeTTS(),
    latencyTracer: VoiceLatencyTracer? = VoiceLatencyTelemetry.tracer(),
    tracksRuntimeHealth: Bool = true
  ) {
    self.synthesizer = synthesizer
    self.edgeTTS = edgeTTS
    self.latencyTracer = latencyTracer
    self.tracksRuntimeHealth = tracksRuntimeHealth
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
    if tracksRuntimeHealth { VoiceRuntimeHealthRegistry.begin(request.runtimeChannel) }
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
    if activeSystemUtterance != nil || synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    if let request = activeRequest, request.providerId == VoiceTTSProvider.microsoftEdge.rawValue {
      edgeSynthesisTask?.cancel()
      edgeSynthesisTask = nil
      finishEdgeReference(played: edgePlayer?.currentTime ?? 0)
      edgePlayer?.stop()
      edgePlayer = nil
      completeActiveRequest(request, success: false, error: "Speech playback was cancelled", errorCode: "tts_cancelled")
    }
    return hadActivePlayback
  }

  @MainActor
  func pauseCurrentPlayback() {
    if let edgePlayer {
      edgePlayer.pause()
      isSpeaking = false
    } else if synthesizer.isSpeaking {
      if synthesizer.pauseSpeaking(at: .immediate) { isSpeaking = false }
    }
  }

  @MainActor
  func resumeCurrentPlayback() {
    if let edgePlayer, let request = activeRequest {
      if edgePlayer.play() {
        isSpeaking = true
      } else {
        finishEdgeReference(played: edgePlayer.currentTime)
        self.edgePlayer = nil
        completeActiveRequest(request, success: false,
          error: "Microsoft Edge TTS playback failed", errorCode: "edge_audio_playback_failed")
      }
    } else if synthesizer.isPaused, synthesizer.continueSpeaking() {
      isSpeaking = true
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
      if self.tracksRuntimeHealth { VoiceRuntimeHealthRegistry.success(request.runtimeChannel) }
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
      self.finishEdgeReference(played: flag ? player.duration : player.currentTime)
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
      self.finishEdgeReference(played: player.currentTime)
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
    if tracksRuntimeHealth { VoiceRuntimeHealthRegistry.begin(request.runtimeChannel) }

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

  func prepareEdgeAudio(_ request: VoiceReplyPlaybackRequest) async throws -> Data {
    try await edgeTTS.synthesize(request).audioData
  }

  @MainActor
  func speakPreparedEdge(
    _ request: VoiceReplyPlaybackRequest,
    audioData: Data,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    stop()
    activeSystemUtterance = nil
    systemTTSRequests.clear()
    activeRequest = request
    self.onPlaybackStarted = onPlaybackStarted
    self.onDone = onDone
    lastErrorDescription = ""
    if tracksRuntimeHealth { VoiceRuntimeHealthRegistry.begin(request.runtimeChannel) }
    playEdgeAudio(audioData, request: request)
  }

  @MainActor
  private func playEdgeAudio(_ audioData: Data, request: VoiceReplyPlaybackRequest) {
    do {
      activeEdgeAudioData = audioData
      let player = try AVAudioPlayer(data: activeEdgeAudioData ?? audioData)
      player.delegate = self
      edgePlayer = player
      player.prepareToPlay()
      let reference = echoReference
      let referenceSamples = reference.flatMap { _ in
        try? GalaxySSIAppleInMemoryAudioDecoder.decode(
          audioData, fileExtension: "mp3", targetSampleRateHz: VoicePlaybackEchoReference.sampleRate,
          maximumFrames: VoicePlaybackEchoReference.maximumFrames
        ).samples
      }
      let startedAt = ProcessInfo.processInfo.systemUptime
      guard player.play() else {
        completeActiveRequest(
          request,
          success: false,
          error: "Microsoft Edge TTS playback failed",
          errorCode: "edge_audio_playback_failed"
        )
        return
      }
      if let reference, let referenceSamples {
        let id = UUID()
        edgeReferenceId = id
        reference.begin(id: id, samples: referenceSamples, at: startedAt)
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

  private func finishEdgeReference(played: TimeInterval) {
    guard let id = edgeReferenceId else { return }
    edgeReferenceId = nil
    echoReference?.end(id: id, played: played, at: ProcessInfo.processInfo.systemUptime)
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
    clearActiveEdgeAudio()
    if success {
      lastErrorDescription = ""
      if tracksRuntimeHealth { VoiceRuntimeHealthRegistry.success(request.runtimeChannel) }
    } else {
      lastErrorDescription = error ?? "Speech playback failed"
      if tracksRuntimeHealth { VoiceRuntimeHealthRegistry.failure(request.runtimeChannel, reason: lastErrorDescription) }
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

  private func clearActiveEdgeAudio() {
    guard var audio = activeEdgeAudioData else { return }
    activeEdgeAudioData = nil
    if !audio.isEmpty {
      audio.resetBytes(in: 0..<audio.count)
      audio.removeAll(keepingCapacity: false)
    }
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
  func setEchoReference(_ reference: VoicePlaybackEchoReference) { inner.echoReference = reference }
  private var cancellables = Set<AnyCancellable>()
  private var generation: UInt64 = 0
  private var activeRequest: VoiceReplyPlaybackRequest?
  private var inputBuffer = ""
  private var queuedChunks: [QueuedChunk] = []
  private var prefetchTasks: [Int: Task<Void, Never>] = [:]
  private var preparedEdgeAudio: [Int: Data] = [:]
  private var prefetchFailures: [Int: String] = [:]
  private var inputClosed = false
  private var nextChunkIndex = 0
  private var playingChunk = false
  private var paused = false
  private var reportedPlaybackStart = false
  private var onPlaybackStarted: ((VoiceReplyPlaybackRequest) -> Void)?
  private var onDone: ((VoiceReplyPlaybackRequest, Bool, String?) -> Void)?
  private var onParagraphStarted: ((Int) -> Void)?

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
    clearPrefetch()
    inputClosed = false
    nextChunkIndex = 0
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
    enqueue(split.committed)
    inputBuffer = split.remainder
    prefetchEdgeChunks()
    pump()
  }

  @MainActor
  func finishProgressive() {
    appendProgressive("", isFinal: true)
  }

  func appendDocumentParagraphs(_ paragraphs: ArraySlice<String>, onParagraphStarted: @escaping (Int) -> Void) {
    guard activeRequest != nil, nextChunkIndex == 0, inputBuffer.isEmpty, !inputClosed else { return }
    self.onParagraphStarted = onParagraphStarted
    for index in paragraphs.indices {
      let chunks = PublicNewsTranslation.parts(paragraphs[index]).flatMap {
        VoiceProgressiveSentenceChunker.split($0, final: true).committed
      }
      for (offset, text) in chunks.enumerated() {
        nextChunkIndex += 1
        queuedChunks.append(QueuedChunk(index: nextChunkIndex, text: text, paragraph: offset == 0 ? index : nil))
      }
    }
    inputClosed = true
    prefetchEdgeChunks()
    pump()
  }

  @MainActor
  func commitProgressive() {
    guard activeRequest != nil else { return }
    let committed = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !committed.isEmpty else { return }
    enqueue([committed])
    inputBuffer = ""
    prefetchEdgeChunks()
    pump()
  }

  func pauseProgressive() -> Bool {
    guard activeRequest != nil, !paused else { return false }
    paused = true
    inner.pauseCurrentPlayback()
    return true
  }

  func resumeProgressive() -> Bool {
    guard activeRequest != nil, paused else { return false }
    paused = false
    inner.resumeCurrentPlayback()
    pump()
    return true
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
    clearPrefetch()
    inputClosed = false
    playingChunk = false
    paused = false
    onPlaybackStarted = nil
    onDone = nil
    onParagraphStarted = nil
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
    guard !paused else { return }
    if baseRequest.providerId == VoiceTTSProvider.microsoftEdge.rawValue {
      if let failure = prefetchFailures.removeValue(forKey: chunk.index) {
        finishProgressive(baseRequest, success: false, error: failure)
        return
      }
      guard let audioData = preparedEdgeAudio.removeValue(forKey: chunk.index) else {
        prefetchEdgeChunks()
        return
      }
      queuedChunks.removeFirst()
      startChunk(
        chunk,
        baseRequest: baseRequest,
        generation: generation,
        preparedEdgeAudio: audioData
      )
      prefetchEdgeChunks()
      return
    }
    queuedChunks.removeFirst()
    startChunk(chunk, baseRequest: baseRequest, generation: generation, preparedEdgeAudio: nil)
  }

  private func startChunk(
    _ chunk: QueuedChunk,
    baseRequest: VoiceReplyPlaybackRequest,
    generation currentGeneration: UInt64,
    preparedEdgeAudio: Data?
  ) {
    playingChunk = true
    var chunkRequest = baseRequest
    chunkRequest.utteranceId = baseRequest.utteranceId + ":chunk:" + String(chunk.index)
    chunkRequest.text = chunk.text
    let started: (VoiceReplyPlaybackRequest) -> Void = { [weak self] _ in
      guard let self,
            self.generation == currentGeneration,
            self.activeRequest?.sessionId == baseRequest.sessionId else { return }
      if !self.reportedPlaybackStart {
        self.reportedPlaybackStart = true
        self.onPlaybackStarted?(baseRequest)
      }
      if let paragraph = chunk.paragraph { self.onParagraphStarted?(paragraph) }
    }
    let completed: (VoiceReplyPlaybackRequest, Bool, String?) -> Void = { [weak self] _, success, error in
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
    if let preparedEdgeAudio {
      inner.speakPreparedEdge(
        chunkRequest,
        audioData: preparedEdgeAudio,
        onPlaybackStarted: started,
        onDone: completed
      )
    } else {
      inner.speak(
        chunkRequest,
        onPlaybackStarted: started,
        onDone: completed
      )
    }
  }

  private func enqueue(_ chunks: [String]) {
    for text in chunks {
      nextChunkIndex += 1
      queuedChunks.append(QueuedChunk(index: nextChunkIndex, text: text))
    }
  }

  private func prefetchEdgeChunks() {
    guard let baseRequest = activeRequest,
          baseRequest.providerId == VoiceTTSProvider.microsoftEdge.rawValue else { return }
    let candidates = VoiceReplySpeechPrefetchPolicy.candidates(
      queuedIndices: queuedChunks.map(\.index),
      inFlightIndices: Set(prefetchTasks.keys),
      preparedIndices: Set(preparedEdgeAudio.keys),
      failedIndices: Set(prefetchFailures.keys)
    )
    let currentGeneration = generation
    for index in candidates {
      guard let chunk = queuedChunks.first(where: { $0.index == index }) else { continue }
      var request = baseRequest
      request.utteranceId = baseRequest.utteranceId + ":chunk:" + String(chunk.index)
      request.text = chunk.text
      prefetchTasks[index] = Task { [weak self] in
        guard let self else { return }
        do {
          let audio = try await self.inner.prepareEdgeAudio(request)
          guard !Task.isCancelled,
                self.generation == currentGeneration,
                self.activeRequest?.sessionId == baseRequest.sessionId else {
            var discarded = audio
            if !discarded.isEmpty { discarded.resetBytes(in: 0..<discarded.count) }
            return
          }
          self.prefetchTasks.removeValue(forKey: index)
          self.preparedEdgeAudio[index] = audio
          self.pump()
          self.prefetchEdgeChunks()
        } catch {
          guard !Task.isCancelled,
                self.generation == currentGeneration,
                self.activeRequest?.sessionId == baseRequest.sessionId else { return }
          self.prefetchTasks.removeValue(forKey: index)
          self.prefetchFailures[index] = error.localizedDescription
          self.pump()
          self.prefetchEdgeChunks()
        }
      }
    }
  }

  private func clearPrefetch() {
    prefetchTasks.values.forEach { $0.cancel() }
    prefetchTasks.removeAll()
    for index in Array(preparedEdgeAudio.keys) {
      guard var audio = preparedEdgeAudio.removeValue(forKey: index), !audio.isEmpty else { continue }
      audio.resetBytes(in: 0..<audio.count)
      audio.removeAll(keepingCapacity: false)
    }
    prefetchFailures.removeAll()
  }

  private struct QueuedChunk: Equatable {
    var index: Int
    var text: String
    var paragraph: Int? = nil
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
    clearPrefetch()
    inputClosed = false
    playingChunk = false
    paused = false
    onPlaybackStarted = nil
    onDone = nil
    onParagraphStarted = nil
    done?(request, success, error)
  }
}

enum VoiceReplySpeechPrefetchPolicy {
  static let maximumUpcomingSegments = 2

  static func candidates(
    queuedIndices: [Int],
    inFlightIndices: Set<Int>,
    preparedIndices: Set<Int>,
    failedIndices: Set<Int>
  ) -> [Int] {
    let occupied = inFlightIndices.union(preparedIndices).union(failedIndices)
    let retained = occupied.intersection(queuedIndices)
    let capacity = max(0, maximumUpcomingSegments - retained.count)
    guard capacity > 0 else { return [] }
    return Array(queuedIndices.filter { !occupied.contains($0) }.prefix(capacity))
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

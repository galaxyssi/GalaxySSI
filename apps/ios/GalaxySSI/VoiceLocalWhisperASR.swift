import Foundation

typealias VoiceLocalWhisperTraceRecorder = (
  _ traceId: String,
  _ event: String,
  _ attributes: [String: String],
  _ once: Bool
) -> Void

typealias VoiceLocalWhisperRuntimeDecisionProvider = (
  _ settings: VoiceSettings,
  _ selectedModel: VoiceWhisperModelProfile,
  _ audioDurationMillis: Int64
) -> VoiceWhisperRuntimeDecision?

final class VoiceLocalWhisperASR {
  private let runtime: VoiceLocalWhisperRuntime
  private let decoder: VoiceWhisperAudioDecoding
  private let modelAvailable: (VoiceWhisperModelProfile) -> Bool
  private let modelFileProvider: (VoiceWhisperModelProfile) throws -> URL?
  private let markModelLoaded: (String) -> Void
  private let markModelUnloaded: (String?) -> Void
  private let runtimeDecisionProvider: VoiceLocalWhisperRuntimeDecisionProvider
  private let trace: VoiceLocalWhisperTraceRecorder
  private let elapsedClock: () -> Int64
  private let lock = NSLock()
  private var loadedModelId: String?

  init(
    runtime: VoiceLocalWhisperRuntime = UnavailableVoiceLocalWhisperRuntime(),
    decoder: VoiceWhisperAudioDecoding = VoiceWhisperAudioDecoder(),
    modelManager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    modelAvailable: ((VoiceWhisperModelProfile) -> Bool)? = nil,
    modelFileProvider: ((VoiceWhisperModelProfile) throws -> URL?)? = nil,
    markModelLoaded: ((String) -> Void)? = nil,
    markModelUnloaded: ((String?) -> Void)? = nil,
    benchmarkManager: VoiceWhisperBenchmarkManager? = nil,
    runtimeDecisionProvider: VoiceLocalWhisperRuntimeDecisionProvider? = nil,
    elapsedClock: @escaping () -> Int64 = VoiceLocalWhisperASR.defaultElapsedClock,
    trace: @escaping VoiceLocalWhisperTraceRecorder = VoiceLocalWhisperASR.defaultTraceRecorder
  ) {
    self.runtime = runtime
    self.decoder = decoder
    self.modelAvailable = modelAvailable ?? { modelManager.isAvailable($0) }
    if let modelFileProvider {
      self.modelFileProvider = modelFileProvider
    } else if modelAvailable != nil {
      self.modelFileProvider = { _ in nil }
    } else {
      self.modelFileProvider = { try modelManager.ensureVerifiedFile(for: $0) }
    }
    self.markModelLoaded = markModelLoaded ?? { modelManager.markLoaded($0) }
    self.markModelUnloaded = markModelUnloaded ?? { modelManager.markUnloaded($0) }
    let resolvedBenchmarkManager = benchmarkManager ?? VoiceWhisperBenchmarkManager()
    self.runtimeDecisionProvider = runtimeDecisionProvider ?? { settings, selectedModel, audioDurationMillis in
      resolvedBenchmarkManager.decide(
        userMode: settings.asrRuntimeMode,
        selectedProfileId: selectedModel.id,
        context: VoiceWhisperBenchmarkDecisionContext(
          utteranceDurationMillis: audioDurationMillis
        )
      )
    }
    self.elapsedClock = elapsedClock
    self.trace = trace
  }

  func transcribe(
    audioFile: URL,
    settings: VoiceSettings,
    language: String? = nil,
    traceId: String = VoiceLatencyTraceContext.currentTraceId()
  ) async throws -> VoiceLocalWhisperTranscriptionResult {
    try await transcribe(
      settings: settings,
      language: language,
      traceId: traceId,
      decodeAudio: { try decoder.decode(fileURL: audioFile) }
    )
  }

  func transcribe(
    pcmWaveData: Data,
    settings: VoiceSettings,
    language: String? = nil,
    traceId: String = VoiceLatencyTraceContext.currentTraceId()
  ) async throws -> VoiceLocalWhisperTranscriptionResult {
    try await transcribe(
      settings: settings,
      language: language,
      traceId: traceId,
      decodeAudio: { try decoder.decodePcmWave(pcmWaveData) }
    )
  }

  func transcribe(
    decodedAudio: VoiceWhisperAudio,
    settings: VoiceSettings,
    language: String? = nil,
    traceId: String = VoiceLatencyTraceContext.currentTraceId()
  ) async throws -> VoiceLocalWhisperTranscriptionResult {
    try await transcribe(
      settings: settings,
      language: language,
      traceId: traceId,
      decodeAudio: { decodedAudio }
    )
  }

  private func transcribe(
    settings: VoiceSettings,
    language: String?,
    traceId: String,
    decodeAudio: () throws -> VoiceWhisperAudio
  ) async throws -> VoiceLocalWhisperTranscriptionResult {
    let startedAtNs = elapsedClock()
    let selectedModel = VoiceWhisperModelCatalog.model(settings.asrModelId)
    guard selectedModel.supportsIOSRuntime else {
      throw VoiceWhisperModelManagerError.unsupportedPlatform(
        modelId: selectedModel.id,
        artifactFormat: selectedModel.artifactFormat
      )
    }
    var model = selectedModel
    let requestedLanguage = language ?? settings.preferredLocaleIdentifier
    let runtimeLanguage = VoiceWhisperLanguagePolicy.normalizedRecognitionLanguage(requestedLanguage)
    var threadCount = min(4, max(1, ProcessInfo.processInfo.processorCount))
    var baseAttributes = [
      "asr_provider": "whisper.cpp",
      "model_profile_id": selectedModel.id,
      "execution_mode": "full_file",
      "thread_count": String(threadCount),
      "runtime_mode": settings.asrRuntimeMode.rawValue,
    ]
    record(traceId, VoiceTraceEvents.asrFinalStarted, baseAttributes, once: true)
    do {
      record(traceId, VoiceTraceEvents.asrDecodeStarted, baseAttributes)
      let decodeStartedAtNs = elapsedClock()
      var audio = try decodeAudio()
      defer { audio.wipeSensitive() }
      guard !audio.samples.isEmpty else {
        throw VoiceLocalWhisperASRError.emptyAudio
      }
      let runtimeDecision = runtimeDecisionProvider(settings, selectedModel, audio.durationMs)
      if let decision = runtimeDecision {
        baseAttributes["runtime_decision"] = decision.provider.rawValue
        if let accurateProfileId = decision.accurateProfileId {
          baseAttributes["accurate_profile_id"] = accurateProfileId
        }
        baseAttributes["run_second_pass"] = String(decision.runSecondPass)
        if decision.provider == .local,
           let decidedModelId = decision.fastProfileId {
          model = VoiceWhisperModelCatalog.model(decidedModelId)
          guard model.supportsIOSRuntime else {
            throw VoiceWhisperModelManagerError.unsupportedPlatform(
              modelId: model.id,
              artifactFormat: model.artifactFormat
            )
          }
          threadCount = decision.threadCount ?? threadCount
          baseAttributes["model_profile_id"] = model.id
          baseAttributes["thread_count"] = String(threadCount)
        }
      }
      let audioAttributes = baseAttributes.merging([
        "audio_duration_ms": String(audio.durationMs),
        "duration_ms": String(millisecondsSince(decodeStartedAtNs)),
      ]) { _, incoming in incoming }
      record(traceId, VoiceTraceEvents.asrDecodeCompleted, audioAttributes)
      guard modelAvailable(model) else {
        throw VoiceLocalWhisperASRError.modelUnavailable(model.id)
      }
      if let unloadedModelId = unloadIfModelChanged(model.id) {
        runtime.release()
        markModelUnloaded(unloadedModelId)
      }
      let coldStartAttributes = audioAttributes.merging(["cold_start": "true"]) { _, incoming in incoming }
      let coldStart = claimColdStart(model.id)
      if coldStart {
        record(traceId, VoiceTraceEvents.asrModelLoadStarted, coldStartAttributes)
      }
      let modelFileURL = try modelFileProvider(model)
      let inferenceStartedAtNs = elapsedClock()
      record(traceId, VoiceTraceEvents.whisperFullStarted, audioAttributes)
      let rawText = try await runtime.transcribe(
        VoiceLocalWhisperRuntimeRequest(
          model: model,
          modelFileURL: modelFileURL,
          language: runtimeLanguage,
          samples: audio.samples,
          sampleRateHz: audio.sampleRateHz,
          threadCount: threadCount
        )
      )
      if coldStart {
        markLoaded(model.id)
        markModelLoaded(model.id)
        record(traceId, VoiceTraceEvents.asrModelLoadCompleted, coldStartAttributes)
      }
      let inferenceDurationMs = millisecondsSince(inferenceStartedAtNs)
      let rtf = audio.durationMs > 0 ?
        String(format: "%.4f", Double(inferenceDurationMs) / Double(audio.durationMs)) :
        "0"
      record(
        traceId,
        VoiceTraceEvents.whisperFullCompleted,
        audioAttributes.merging([
          "duration_ms": String(inferenceDurationMs),
          "rtf": rtf,
        ]) { _, incoming in incoming }
      )
      let text = VoiceWhisperLanguagePolicy.normalizeTranscript(rawText, language: requestedLanguage)
      record(
        traceId,
        VoiceTraceEvents.asrFinalReceived,
        audioAttributes.merging([
          "duration_ms": String(millisecondsSince(startedAtNs)),
          "success": "true",
        ]) { _, incoming in incoming },
        once: true
      )
      return VoiceLocalWhisperTranscriptionResult(
        text: text,
        selectedModel: selectedModel,
        model: model,
        language: runtimeLanguage,
        audioDurationMs: audio.durationMs,
        sampleRateHz: audio.sampleRateHz,
        threadCount: threadCount,
        runtimeDecision: runtimeDecision
      )
    } catch {
      record(
        traceId,
        VoiceTraceEvents.asrFinalFailed,
        baseAttributes.merging([
          "duration_ms": String(millisecondsSince(startedAtNs)),
          "success": "false",
          "error_code": Self.errorCode(error),
        ]) { _, incoming in incoming },
        once: true
      )
      throw error
    }
  }

  func release() {
    runtime.release()
    let previousModelId = clearLoadedModel()
    markModelUnloaded(previousModelId)
  }

  private func unloadIfModelChanged(_ modelId: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard let previousModelId = loadedModelId, previousModelId != modelId else {
      return nil
    }
    loadedModelId = nil
    return previousModelId
  }

  private func claimColdStart(_ modelId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return loadedModelId != modelId
  }

  private func markLoaded(_ modelId: String) {
    lock.lock()
    loadedModelId = modelId
    lock.unlock()
  }

  private func clearLoadedModel() -> String? {
    lock.lock()
    defer { lock.unlock() }
    let previousModelId = loadedModelId
    loadedModelId = nil
    return previousModelId
  }

  private func millisecondsSince(_ startedAtNs: Int64) -> Int64 {
    max(0, (elapsedClock() - startedAtNs) / 1_000_000)
  }

  private func record(
    _ traceId: String,
    _ event: String,
    _ attributes: [String: String],
    once: Bool = false
  ) {
    guard !traceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    trace(traceId, event, attributes, once)
  }

  private static func errorCode(_ error: Error) -> String {
    switch error {
    case VoiceLocalWhisperASRError.runtimeUnavailable:
      return "WHISPER_RUNTIME_MISSING"
    case VoiceLocalWhisperASRError.modelUnavailable(_):
      return "WHISPER_MODEL_MISSING"
    case VoiceLocalWhisperASRError.emptyAudio:
      return "EMPTY_AUDIO"
    case let error as VoiceWhisperAudioDecodeError:
      return "ASR_DECODE_\(String(describing: error).uppercased())"
    default:
      return String(describing: type(of: error))
    }
  }

  private static func defaultTraceRecorder(
    traceId: String,
    event: String,
    attributes: [String: String],
    once: Bool
  ) {
    VoiceLatencyTelemetry.record(
      traceId: traceId,
      event: event,
      attributes: attributes,
      once: once
    )
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }
}

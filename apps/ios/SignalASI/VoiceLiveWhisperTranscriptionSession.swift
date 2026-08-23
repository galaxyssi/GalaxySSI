import Foundation

struct VoiceLiveWhisperTranscriptUpdate: Codable, Equatable {
  var voiceSessionId: String
  var transcript: VoiceWhisperStabilizedTranscript
  var modelProfileId: String
  var realTimeFactor: Double
  var correctionReview: VoiceTranscriptCorrectionReview?

  init(
    voiceSessionId: String,
    transcript: VoiceWhisperStabilizedTranscript,
    modelProfileId: String,
    realTimeFactor: Double,
    correctionReview: VoiceTranscriptCorrectionReview? = nil
  ) {
    self.voiceSessionId = voiceSessionId
    self.transcript = transcript
    self.modelProfileId = modelProfileId
    self.realTimeFactor = realTimeFactor
    self.correctionReview = correctionReview
  }
}

enum VoiceLiveWhisperTranscriptionSessionFailure: Error, Equatable {
  case finalAlreadyRequested
  case finalDecodeDropped(VoiceWhisperDecodeDropReason)
  case finalTranscriptIncomplete(String)
}

typealias VoiceLiveWhisperSessionPostFastDecisionProvider = (
  _ fastResult: VoiceNativeWhisperResult,
  _ snapshot: PcmSnapshot,
  _ queue: VoiceWhisperDecodeQueueSnapshot
) -> VoiceWhisperRuntimeDecision?

private struct VoiceLiveWhisperFinalPass {
  var request: VoiceScheduledWhisperDecode
  var result: VoiceNativeWhisperResult
}

final class VoiceLiveWhisperTranscriptionSession {
  private let voiceSessionId: String
  private let profile: VoiceWhisperModelProfile
  private let finalProfileId: String?
  private let threadCount: Int?
  private let postFastDecisionProvider: VoiceLiveWhisperSessionPostFastDecisionProvider?
  private let language: String
  private let scheduler: VoiceWhisperDecodeScheduling
  private let elapsedClock: () -> Int64
  private let onUpdate: (VoiceLiveWhisperTranscriptUpdate) -> Void
  private let policy: VoiceAdaptiveWhisperPartialPolicy
  private let stabilizer: VoiceWhisperTextStabilizer
  private let lock = NSLock()
  private var finalized = false
  private var closed = false
  private var requestSequence = 0
  private var lastAppliedRevision = 0

  init(
    voiceSessionId: String,
    profile: VoiceWhisperModelProfile,
    language: String,
    scheduler: VoiceWhisperDecodeScheduling,
    elapsedClock: @escaping () -> Int64,
    certifiedPartialIntervalMillis: Int64? = nil,
    realtimeCertified: Bool? = nil,
    finalProfileId: String? = nil,
    threadCount: Int? = nil,
    postFastDecisionProvider: VoiceLiveWhisperSessionPostFastDecisionProvider? = nil,
    stabilizer: VoiceWhisperTextStabilizer = VoiceWhisperTextStabilizer(),
    onUpdate: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void
  ) {
    self.voiceSessionId = voiceSessionId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("voice")
    self.profile = profile
    let normalizedFinalProfileId = finalProfileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.finalProfileId = normalizedFinalProfileId.isEmpty ? nil : normalizedFinalProfileId
    self.threadCount = threadCount.map { min(max($0, 1), 16) }
    self.postFastDecisionProvider = postFastDecisionProvider
    self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("zh")
    self.scheduler = scheduler
    self.elapsedClock = elapsedClock
    self.stabilizer = stabilizer
    self.onUpdate = onUpdate
    self.policy = VoiceAdaptiveWhisperPartialPolicy(
      profile: profile,
      certifiedPartialIntervalMillis: certifiedPartialIntervalMillis,
      realtimeCertified: realtimeCertified
    )
  }

  var modelProfileId: String {
    profile.id
  }

  func partialPolicy() -> VoiceAdaptiveWhisperPartialSnapshot {
    policy.snapshot()
  }

  func nextPartialWindowMillis(capturedAudioMillis: Int64) -> Int64? {
    lock.lock()
    let blocked = closed || finalized
    lock.unlock()
    guard !blocked else { return nil }
    let queue = scheduler.queueSnapshot()
    guard policy.shouldSubmit(
      nowMillis: elapsedClock(),
      capturedAudioMillis: capturedAudioMillis,
      queue: queue
    ) else {
      return nil
    }
    return policy.snapshot().windowMillis
  }

  func offerPartial(_ snapshot: PcmSnapshot) {
    lock.lock()
    let blocked = closed || finalized
    lock.unlock()
    guard !blocked, snapshot.speechDetected else { return }
    guard let request = try? makeRequest(
      snapshot: snapshot,
      mode: .realtimePartial,
      priority: .currentPartial
    ) else {
      return
    }

    Task { [weak self] in
      await self?.submitPartial(request)
    }
  }

  func finish(_ snapshot: PcmSnapshot) async throws -> VoiceNativeWhisperResult {
    lock.lock()
    guard !finalized else {
      lock.unlock()
      throw VoiceLiveWhisperTranscriptionSessionFailure.finalAlreadyRequested
    }
    finalized = true
    lock.unlock()

    let firstPass = try await decodeFinalPass(
      snapshot,
      modelProfileId: finalProfileId ?? profile.id,
      mode: .finalOnly,
      threadCount: threadCount
    )
    var acceptedPass = firstPass
    var correctionReview: VoiceTranscriptCorrectionReview?
    if finalProfileId == nil,
       let decision = postFastDecisionProvider?(
         firstPass.result,
         snapshot,
         scheduler.queueSnapshot()
       ),
       decision.provider == .local,
       decision.runSecondPass,
       let accurateProfileId = decision.accurateProfileId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !accurateProfileId.isEmpty,
       accurateProfileId != firstPass.request.modelProfileId {
      do {
        acceptedPass = try await decodeFinalPass(
          snapshot,
          modelProfileId: accurateProfileId,
          mode: .secondPass,
          threadCount: decision.threadCount ?? threadCount
        )
        correctionReview = makeCorrectionReview(
          fast: firstPass.result,
          accurate: acceptedPass.result
        )
      } catch {
        lock.lock()
        let cancelled = closed
        lock.unlock()
        if cancelled {
          throw error
        }
        acceptedPass = firstPass
      }
    }
    let decoded = decode(request: acceptedPass.request, native: acceptedPass.result)
    applyFinal(
      request: acceptedPass.request,
      decoded: decoded,
      correctionReview: correctionReview
    )
    return acceptedPass.result
  }

  private func makeCorrectionReview(
    fast: VoiceNativeWhisperResult,
    accurate: VoiceNativeWhisperResult
  ) -> VoiceTranscriptCorrectionReview {
    let fastText = fast.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let accurateText = accurate.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let consistency = DefaultEntityConsistencyChecker.compare(
      fastText: fastText,
      accurateText: accurateText
    )
    return VoiceTranscriptCorrectionReview(
      sessionId: voiceSessionId,
      diff: TranscriptDiff(
        fastText: fastText,
        accurateText: accurateText,
        normalizedFastText: fastText.voiceNormalizedTranscript(),
        normalizedAccurateText: accurateText.voiceNormalizedTranscript(),
        entityDifferences: consistency.differences
      )
    )
  }

  private func decodeFinalPass(
    _ snapshot: PcmSnapshot,
    modelProfileId: String,
    mode: VoiceWhisperExecutionMode,
    threadCount: Int?
  ) async throws -> VoiceLiveWhisperFinalPass {
    let chunks = VoiceWhisperFinalAudioChunker.plan(
      sampleCount: snapshot.samples.count,
      sampleRateHz: snapshot.sampleRateHz,
      mode: .finalOnly
    )
    var decodedChunks: [VoiceWhisperFinalDecodeChunk] = []
    var lastRequest: VoiceScheduledWhisperDecode?
    for chunk in chunks {
      let windowStartSample = snapshot.captureStartSample + Int64(chunk.offset)
      let windowEndSampleExclusive = windowStartSample + Int64(chunk.length)
      let request = try makeRequest(
        pcm16: Array(snapshot.samples[chunk.offset..<chunk.endExclusive]),
        sampleRateHz: snapshot.sampleRateHz,
        windowStartSample: windowStartSample,
        windowEndSampleExclusive: windowEndSampleExclusive,
        modelProfileId: modelProfileId,
        threadCount: threadCount,
        mode: mode,
        priority: .currentFinal
      )
      lastRequest = request
      switch await scheduler.submit(request) {
      case .completed(_, let native):
        decodedChunks.append(VoiceWhisperFinalDecodeChunk(chunk: chunk, result: native))
      case .failed(_, let error):
        throw error
      case .dropped(_, let reason):
        throw VoiceLiveWhisperTranscriptionSessionFailure.finalDecodeDropped(reason)
      }
    }

    guard let lastRequest else {
      throw VoiceLiveWhisperTranscriptionSessionFailure.finalTranscriptIncomplete("empty_audio")
    }
    let native = decodedChunks.count == 1
      ? decodedChunks[0].result
      : VoiceWhisperFinalResultAssembler.assemble(
        chunks: decodedChunks,
        totalSamples: snapshot.samples.count,
        sampleRateHz: snapshot.sampleRateHz
      )
    let completeness = VoiceWhisperTranscriptCompletenessPolicy.evaluate(
      result: native,
      snapshot: snapshot
    )
    guard completeness.accepted else {
      throw VoiceLiveWhisperTranscriptionSessionFailure.finalTranscriptIncomplete(
        completeness.reasonCode
      )
    }
    let aggregateRequest = decodedChunks.count == 1
      ? lastRequest
      : try makeRequest(
        snapshot: snapshot,
        modelProfileId: modelProfileId,
        threadCount: threadCount,
        mode: mode,
        priority: .currentFinal
      )
    return VoiceLiveWhisperFinalPass(request: aggregateRequest, result: native)
  }

  func close() {
    lock.lock()
    guard !closed else {
      lock.unlock()
      return
    }
    closed = true
    lock.unlock()
    scheduler.cancelSession(voiceSessionId)
  }

  private func submitPartial(_ request: VoiceScheduledWhisperDecode) async {
    switch await scheduler.submit(request) {
    case .completed(_, let native):
      let decoded = decode(request: request, native: native)
      policy.onDecodeCompleted(
        realTimeFactor: decoded.realTimeFactor,
        queue: scheduler.queueSnapshot()
      )
      applyPartial(request: request, decoded: decoded)
    case .failed:
      policy.onDecodeCompleted(
        realTimeFactor: Double.infinity,
        queue: scheduler.queueSnapshot()
      )
    case .dropped:
      return
    }
  }

  private func makeRequest(
    snapshot: PcmSnapshot,
    modelProfileId: String? = nil,
    threadCount: Int? = nil,
    mode: VoiceWhisperExecutionMode,
    priority: VoiceWhisperDecodePriority
  ) throws -> VoiceScheduledWhisperDecode {
    try makeRequest(
      pcm16: snapshot.samples,
      sampleRateHz: snapshot.sampleRateHz,
      windowStartSample: snapshot.captureStartSample,
      windowEndSampleExclusive: snapshot.captureEndSampleExclusive,
      modelProfileId: modelProfileId,
      threadCount: threadCount,
      mode: mode,
      priority: priority
    )
  }

  private func makeRequest(
    pcm16: [Int16],
    sampleRateHz: Int,
    windowStartSample: Int64,
    windowEndSampleExclusive: Int64,
    modelProfileId: String? = nil,
    threadCount: Int? = nil,
    mode: VoiceWhisperExecutionMode,
    priority: VoiceWhisperDecodePriority
  ) throws -> VoiceScheduledWhisperDecode {
    let revision = nextRevision()
    return try VoiceScheduledWhisperDecode(
      requestId: "\(voiceSessionId):\(revision)",
      voiceSessionId: voiceSessionId,
      revision: revision,
      modelProfileId: modelProfileId ?? profile.id,
      pcm16: pcm16,
      sampleRateHz: sampleRateHz,
      language: language,
      threadCount: threadCount ?? self.threadCount,
      mode: mode,
      priority: priority,
      windowStartSample: windowStartSample,
      windowEndSampleExclusive: windowEndSampleExclusive
    )
  }

  private func nextRevision() -> Int {
    lock.lock()
    requestSequence += 1
    let revision = requestSequence
    lock.unlock()
    return revision
  }

  private func decode(
    request: VoiceScheduledWhisperDecode,
    native: VoiceNativeWhisperResult
  ) -> VoiceWhisperDecodedWindow {
    VoiceWhisperSegmentDecoder.decode(
      requestId: request.requestId,
      windowStartSample: request.windowStartSample,
      windowEndSampleExclusive: request.windowEndSampleExclusive,
      sampleRateHz: request.sampleRateHz,
      result: native,
      final: request.isFinal
    )
  }

  private func applyPartial(
    request: VoiceScheduledWhisperDecode,
    decoded: VoiceWhisperDecodedWindow
  ) {
    let update: VoiceLiveWhisperTranscriptUpdate?
    lock.lock()
    if closed || finalized || request.revision <= lastAppliedRevision {
      update = nil
    } else {
      lastAppliedRevision = request.revision
      let transcript = stabilizer.accept(decoded)
      if transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        update = nil
      } else {
        update = VoiceLiveWhisperTranscriptUpdate(
          voiceSessionId: voiceSessionId,
          transcript: transcript,
          modelProfileId: profile.id,
          realTimeFactor: decoded.realTimeFactor
        )
      }
    }
    lock.unlock()
    if let update {
      onUpdate(update)
    }
  }

  private func applyFinal(
    request: VoiceScheduledWhisperDecode,
    decoded: VoiceWhisperDecodedWindow,
    correctionReview: VoiceTranscriptCorrectionReview?
  ) {
    let update: VoiceLiveWhisperTranscriptUpdate
    lock.lock()
    lastAppliedRevision = request.revision
    let transcript = stabilizer.accept(decoded)
    update = VoiceLiveWhisperTranscriptUpdate(
      voiceSessionId: voiceSessionId,
      transcript: transcript,
      modelProfileId: request.modelProfileId,
      realTimeFactor: decoded.realTimeFactor,
      correctionReview: correctionReview
    )
    lock.unlock()
    onUpdate(update)
  }
}

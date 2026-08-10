import Foundation

struct VoiceLiveWhisperTranscriptUpdate: Codable, Equatable {
  var voiceSessionId: String
  var transcript: VoiceWhisperStabilizedTranscript
  var modelProfileId: String
  var realTimeFactor: Double
}

enum VoiceLiveWhisperTranscriptionSessionFailure: Error, Equatable {
  case finalAlreadyRequested
  case finalDecodeDropped(VoiceWhisperDecodeDropReason)
  case finalTranscriptIncomplete(String)
}

final class VoiceLiveWhisperTranscriptionSession {
  private let voiceSessionId: String
  private let profile: VoiceWhisperModelProfile
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
    stabilizer: VoiceWhisperTextStabilizer = VoiceWhisperTextStabilizer(),
    onUpdate: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void
  ) {
    self.voiceSessionId = voiceSessionId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("voice")
    self.profile = profile
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

    let request = try makeRequest(
      snapshot: snapshot,
      mode: .finalOnly,
      priority: .currentFinal
    )
    switch await scheduler.submit(request) {
    case .completed(_, let native):
      let completeness = VoiceWhisperTranscriptCompletenessPolicy.evaluate(
        result: native,
        snapshot: snapshot
      )
      guard completeness.accepted else {
        throw VoiceLiveWhisperTranscriptionSessionFailure.finalTranscriptIncomplete(
          completeness.reasonCode
        )
      }
      let decoded = decode(request: request, native: native)
      applyFinal(request: request, decoded: decoded)
      return native
    case .failed(_, let error):
      throw error
    case .dropped(_, let reason):
      throw VoiceLiveWhisperTranscriptionSessionFailure.finalDecodeDropped(reason)
    }
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
    mode: VoiceWhisperExecutionMode,
    priority: VoiceWhisperDecodePriority
  ) throws -> VoiceScheduledWhisperDecode {
    let revision = nextRevision()
    return try VoiceScheduledWhisperDecode(
      requestId: "\(voiceSessionId):\(revision)",
      voiceSessionId: voiceSessionId,
      revision: revision,
      modelProfileId: profile.id,
      pcm16: snapshot.samples,
      sampleRateHz: snapshot.sampleRateHz,
      language: language,
      mode: mode,
      priority: priority,
      windowStartSample: snapshot.captureStartSample,
      windowEndSampleExclusive: snapshot.captureEndSampleExclusive
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
    decoded: VoiceWhisperDecodedWindow
  ) {
    let update: VoiceLiveWhisperTranscriptUpdate
    lock.lock()
    lastAppliedRevision = request.revision
    let transcript = stabilizer.accept(decoded)
    update = VoiceLiveWhisperTranscriptUpdate(
      voiceSessionId: voiceSessionId,
      transcript: transcript,
      modelProfileId: profile.id,
      realTimeFactor: decoded.realTimeFactor
    )
    lock.unlock()
    onUpdate(update)
  }
}

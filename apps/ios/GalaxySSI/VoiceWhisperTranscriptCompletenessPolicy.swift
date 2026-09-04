import Foundation

struct VoiceWhisperTranscriptCompletenessDecision: Equatable {
  var accepted: Bool
  var reasonCode: String
  var missingCoverageMs: Int64
}

enum VoiceWhisperTranscriptCompletenessPolicy {
  static func evaluate(
    result: VoiceNativeWhisperResult,
    snapshot: PcmSnapshot
  ) -> VoiceWhisperTranscriptCompletenessDecision {
    guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return rejected(reasonCode: "empty_transcript")
    }
    guard result.successful else {
      return rejected(reasonCode: "decoder_failed")
    }

    let capturedSpeechMs = speechDurationMillis(snapshot)
    let decodedAudioMs = max(0, result.timings.audioMillis)
    guard let capturedSpeechMs, capturedSpeechMs > 0, decodedAudioMs > 0 else {
      return accepted()
    }

    let missingMs = max(0, capturedSpeechMs - decodedAudioMs)
    let toleranceMs = min(
      max(capturedSpeechMs / 5, minimumCoverageToleranceMs),
      maximumCoverageToleranceMs
    )
    return missingMs <= toleranceMs
      ? accepted()
      : rejected(reasonCode: "incomplete_audio_coverage", missingCoverageMs: missingMs)
  }

  private static func speechDurationMillis(_ snapshot: PcmSnapshot) -> Int64? {
    guard let start = snapshot.speechStartSample,
          let end = snapshot.speechEndSampleExclusive,
          snapshot.sampleRateHz > 0,
          end > start else {
      return nil
    }
    return (end - start) * 1_000 / Int64(snapshot.sampleRateHz)
  }

  private static func accepted() -> VoiceWhisperTranscriptCompletenessDecision {
    VoiceWhisperTranscriptCompletenessDecision(
      accepted: true,
      reasonCode: "complete",
      missingCoverageMs: 0
    )
  }

  private static func rejected(
    reasonCode: String,
    missingCoverageMs: Int64 = 0
  ) -> VoiceWhisperTranscriptCompletenessDecision {
    VoiceWhisperTranscriptCompletenessDecision(
      accepted: false,
      reasonCode: reasonCode,
      missingCoverageMs: max(0, missingCoverageMs)
    )
  }

  private static let minimumCoverageToleranceMs: Int64 = 500
  private static let maximumCoverageToleranceMs: Int64 = 1_500
}

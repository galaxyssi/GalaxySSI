import Foundation

enum VoiceSecondPassTriggerPolicy {
  static func evaluate(
    fast: TranscriptHypothesis,
    utteranceDurationMs: Int64,
    userRequestedAccuracy: Bool = false,
    meetingOrLongRecordMode: Bool = false,
    onlineProviderUnstable: Bool = false
  ) -> VoiceSecondPassTrigger {
    var reasons: [String] = []
    if userRequestedAccuracy {
      reasons.append("user_requested_accuracy")
    }
    if meetingOrLongRecordMode || utteranceDurationMs >= longRecordThresholdMs {
      reasons.append("long_recording")
    }
    if let confidence = fast.confidence, confidence < lowConfidenceThreshold {
      reasons.append("low_confidence")
    }
    if containsDenseProperNouns(fast.text) {
      reasons.append("proper_nouns")
    }
    if onlineProviderUnstable {
      reasons.append("online_provider_unstable")
    }
    return VoiceSecondPassTrigger(requested: !reasons.isEmpty, reasons: Set(reasons))
  }

  private static func containsDenseProperNouns(_ text: String) -> Bool {
    let normalized = text.voiceNFKC()
    let tokens = tokenPattern.matches(in: normalized)
    let namedTokens = tokens.filter { token in
      token.dropFirst().contains(where: { $0.isUppercase }) ||
        (token.contains(where: { $0.isLetter }) && token.contains(where: { $0.isNumber })) ||
        token.contains(".") ||
        token.contains("@") ||
        token.contains("_")
    }.count
    let quotedTerms = quotedTermPattern.matches(in: normalized).count
    return namedTokens >= 2 || quotedTerms >= 1
  }

  private static let tokenPattern = VoiceTextPattern("[\\p{L}\\p{N}_.@+-]{2,}")
  private static let quotedTermPattern = VoiceTextPattern("[\\\"'\u{201c}\u{201d}\u{300c}\u{300d}][^\\\"'\u{201c}\u{201d}\u{300c}\u{300d}]{2,48}[\\\"'\u{201c}\u{201d}\u{300c}\u{300d}]")
  private static let lowConfidenceThreshold: Float = 0.72
  private static let longRecordThresholdMs: Int64 = 15_000
}

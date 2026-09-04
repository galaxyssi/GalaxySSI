import Foundation

protocol VoiceCommandRiskClassifying {
  func classify(_ text: String) -> VoiceCommandRisk
}

struct DefaultVoiceCommandRiskClassifier: VoiceCommandRiskClassifying {
  func classify(_ text: String) -> VoiceCommandRisk {
    Self.classify(text)
  }

  static func classify(_ text: String) -> VoiceCommandRisk {
    let normalized = text.voiceNormalizedForMatching()
    if criticalPatterns.contains(where: { $0.containsMatch(in: normalized) }) {
      return .critical
    }
    if highPatterns.contains(where: { $0.containsMatch(in: normalized) }) {
      return .high
    }
    if mediumPatterns.contains(where: { $0.containsMatch(in: normalized) }) {
      return .medium
    }
    if lowPatterns.contains(where: { $0.containsMatch(in: normalized) }) {
      return .low
    }
    return .conversation
  }

  private static func patterns(_ values: String...) -> [VoiceTextPattern] {
    values.map { VoiceTextPattern($0, options: [.caseInsensitive]) }
  }

  private static let criticalPatterns = patterns(
    "\\b(?:transfer money|wire money|make a payment|pay|purchase|place an order|publish publicly|factory reset|wipe all|grant admin|elevate privilege)\\b",
    "(?:\u{8f6c}\u{8d26}|\u{4ed8}\u{6b3e}|\u{652f}\u{4ed8}|\u{8d2d}\u{4e70}|\u{4e0b}\u{5355}|\u{516c}\u{5f00}\u{53d1}\u{5e03}|\u{6062}\u{590d}\u{51fa}\u{5382}|\u{6e05}\u{7a7a}\u{6240}\u{6709}|\u{6388}\u{4e88}\u{7ba1}\u{7406}\u{5458}|\u{63d0}\u{6743})"
  )

  private static let highPatterns = patterns(
    "\\b(?:send|message|call|dial|delete|remove|overwrite|disable service|uninstall|install apk|lock device|unlock device)\\b",
    "(?:\u{53d1}\u{9001}|\u{53d1}\u{7ed9}|\u{53d1}\u{6d88}\u{606f}|\u{6253}\u{7535}\u{8bdd}|\u{62e8}\u{6253}|\u{5220}\u{9664}|\u{79fb}\u{9664}|\u{8986}\u{76d6}|\u{505c}\u{7528}\u{670d}\u{52a1}|\u{5378}\u{8f7d}|\u{5b89}\u{88c5}apk|\u{9501}\u{5c4f}|\u{89e3}\u{9501})"
  )

  private static let mediumPatterns = patterns(
    "\\b(?:draft|change settings|modify settings|download|create contact|update contact|create calendar|schedule event|start a long task)\\b",
    "(?:\u{8349}\u{7a3f}|\u{4fee}\u{6539}\u{8bbe}\u{7f6e}|\u{66f4}\u{6539}\u{8bbe}\u{7f6e}|\u{4e0b}\u{8f7d}|\u{521b}\u{5efa}\u{8054}\u{7cfb}\u{4eba}|\u{4fee}\u{6539}\u{8054}\u{7cfb}\u{4eba}|\u{521b}\u{5efa}\u{65e5}\u{5386}|\u{65b0}\u{5efa}\u{65e5}\u{7a0b}|\u{542f}\u{52a8}\u{957f}\u{4efb}\u{52a1})"
  )

  private static let lowPatterns = patterns(
    "\\b(?:open|launch|show|query|check|volume|flashlight|timer|alarm|battery|device status)\\b",
    "(?:\u{6253}\u{5f00}|\u{542f}\u{52a8}|\u{67e5}\u{770b}|\u{67e5}\u{8be2}|\u{97f3}\u{91cf}|\u{624b}\u{7535}\u{7b52}|\u{8ba1}\u{65f6}\u{5668}|\u{95f9}\u{949f}|\u{7535}\u{91cf}|\u{8bbe}\u{5907}\u{72b6}\u{6001})"
  )
}

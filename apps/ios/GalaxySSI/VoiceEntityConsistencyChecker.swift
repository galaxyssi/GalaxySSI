import Foundation

protocol EntityConsistencyChecking {
  func extract(_ text: String) -> [VoiceEntity]
  func compare(fastText: String, accurateText: String) -> EntityConsistencyResult
}

struct DefaultEntityConsistencyChecker: EntityConsistencyChecking {
  func extract(_ text: String) -> [VoiceEntity] {
    Self.extract(text)
  }

  func compare(fastText: String, accurateText: String) -> EntityConsistencyResult {
    Self.compare(fastText: fastText, accurateText: accurateText)
  }

  static func extract(_ text: String) -> [VoiceEntity] {
    let normalized = text.voiceNFKC()
    var entities: [VoiceEntity] = []
    recipientPatterns.forEach { pattern in
      pattern.matches(in: normalized, group: 1).forEach {
        addEntity(.recipient, value: $0, to: &entities)
      }
    }
    addMatches(.phoneNumber, text: normalized, pattern: phonePattern, to: &entities)
    addMatches(.amount, text: normalized, pattern: amountPattern, to: &entities)
    dateTimePatterns.forEach { addMatches(.dateTime, text: normalized, pattern: $0, to: &entities) }
    filePathPatterns.forEach { addMatches(.filePath, text: normalized, pattern: $0, to: &entities) }
    applicationPatterns.forEach { addCaptured(.application, text: normalized, pattern: $0, to: &entities) }
    devicePatterns.forEach { addCaptured(.device, text: normalized, pattern: $0, to: &entities) }
    negationTerms.forEach { term in
      let (canonical, pattern) = term
      if pattern.containsMatch(in: normalized) {
        addEntity(.negation, value: canonical, to: &entities)
      }
    }
    actionTerms.forEach { term in
      let (canonical, pattern) = term
      if pattern.containsMatch(in: normalized) {
        addEntity(.action, value: canonical, to: &entities)
      }
    }
    var seen: Set<String> = []
    return entities
      .filter { seen.insert("\($0.type.rawValue):\($0.canonicalValue)").inserted }
      .sorted {
        if $0.type != $1.type {
          return entityRank($0.type) < entityRank($1.type)
        }
        return $0.canonicalValue < $1.canonicalValue
      }
  }

  static func compare(fastText: String, accurateText: String) -> EntityConsistencyResult {
    let fast = extract(fastText)
    let accurate = extract(accurateText)
    let differences = VoiceEntityType.allCases.compactMap { type -> VoiceEntityDifference? in
      let fastValues = values(of: type, in: fast)
      let accurateValues = values(of: type, in: accurate)
      return fastValues == accurateValues ? nil : VoiceEntityDifference(
        type: type,
        fastValues: fastValues,
        accurateValues: accurateValues
      )
    }
    return EntityConsistencyResult(
      fastEntities: fast,
      accurateEntities: accurate,
      differences: differences
    )
  }

  private static func addMatches(
    _ type: VoiceEntityType,
    text: String,
    pattern: VoiceTextPattern,
    to entities: inout [VoiceEntity]
  ) {
    pattern.matches(in: text).forEach {
      addEntity(type, value: $0, to: &entities)
    }
  }

  private static func addCaptured(
    _ type: VoiceEntityType,
    text: String,
    pattern: VoiceTextPattern,
    to entities: inout [VoiceEntity]
  ) {
    pattern.matches(in: text, group: 1).forEach {
      addEntity(type, value: $0, to: &entities)
    }
  }

  private static func addEntity(
    _ type: VoiceEntityType,
    value: String,
    to entities: inout [VoiceEntity]
  ) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).voiceTrimEndPunctuation()
    guard !trimmed.isEmpty else { return }
    entities.append(VoiceEntity(
      type: type,
      value: trimmed,
      canonicalValue: trimmed.voiceNormalizedEntityValue()
    ))
  }

  private static func values(of type: VoiceEntityType, in entities: [VoiceEntity]) -> [String] {
    Array(Set(entities.filter { $0.type == type }.map(\.canonicalValue))).sorted()
  }

  private static func entityRank(_ type: VoiceEntityType) -> Int {
    VoiceEntityType.allCases.firstIndex(of: type) ?? Int.max
  }

  private static let recipientPatterns = [
    VoiceTextPattern("(?:\u{7ed9}|\u{5411})([\\p{L}\\p{N}_.@+-]{1,48}?)(?=\u{53d1}\u{9001}|\u{53d1}|\u{8f6c}\u{8d26}|\u{6253}\u{7535}\u{8bdd}|\u{62e8}\u{6253}|\u{5206}\u{4eab})"),
    VoiceTextPattern("(?:\u{53d1}\u{9001}|\u{53d1}|\u{5206}\u{4eab})(?:\u{6d88}\u{606f}|\u{6587}\u{4ef6})?(?:\u{7ed9}|\u{5230})([\\p{L}\\p{N}_.@+-]{1,48})"),
    VoiceTextPattern("\\b(?:send|message|call|dial|pay|transfer|share)(?:\\s+(?:a|the|this|file|message|money))*\\s+(?:to\\s+)?([\\p{L}\\p{N}_.@+-]{1,48})\\b", options: [.caseInsensitive]),
  ]

  private static let phonePattern = VoiceTextPattern("(?<![\\d.])(?:\\+?\\d[\\d ()-]{5,}\\d)(?![\\d.])")

  private static let amountPattern = VoiceTextPattern(
    "(?:[$\u{00a5}\u{ffe5}\u{20ac}\u{00a3}]\\s*\\d+(?:[.,]\\d{1,2})?)|" +
      "(?:\\d+(?:[.,]\\d{1,2})?\\s*(?:\u{5143}|\u{7f8e}\u{5143}|\u{4eba}\u{6c11}\u{5e01}|usd|cny|rmb|eur|gbp))",
    options: [.caseInsensitive]
  )

  private static let dateTimePatterns = [
    VoiceTextPattern("\\b\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}\\b"),
    VoiceTextPattern("\\b\\d{1,2}:\\d{2}(?::\\d{2})?\\s*(?:am|pm)?\\b", options: [.caseInsensitive]),
    VoiceTextPattern("\\d{1,2}\\s*(?:\u{6708})\\s*\\d{1,2}\\s*(?:\u{65e5}|\u{53f7})"),
    VoiceTextPattern("\\d{1,2}\\s*(?:\u{70b9}|\u{65f6})(?:\\s*\\d{1,2}\\s*\u{5206})?"),
  ]

  private static let filePathPatterns = [
    VoiceTextPattern("\\b[A-Za-z]:[\\\\/](?:[^\\s\\\"'<>|]+[\\\\/]?)+"),
    VoiceTextPattern("(?<![A-Za-z0-9])/(?:[^\\s\\\"']+/)*[^\\s\\\"']+"),
    VoiceTextPattern("\\b(?:Downloads?|Documents?|Pictures?|DCIM|Movies|Music)[\\\\/][^\\s\\\"']+", options: [.caseInsensitive]),
    VoiceTextPattern("(?<![\\p{L}\\p{N}_.-])[\\p{L}\\p{N}_-]{1,96}\\.(?:txt|csv|json|xml|pdf|docx?|xlsx?|pptx?|zip|tar|gz|7z|rar|jpg|jpeg|png|gif|webp|mp3|wav|m4a|opus|mp4|mkv|py|js|ts|kt|java|c|cc|cpp|h|hpp|rs|go|sh|apk)(?![\\p{L}\\p{N}_.-])", options: [.caseInsensitive]),
  ]

  private static let applicationPatterns = [
    VoiceTextPattern("(?:\u{6253}\u{5f00}|\u{542f}\u{52a8}|\u{5173}\u{95ed}|\u{5378}\u{8f7d})([\\p{L}\\p{N}_.+-]{1,48})"),
    VoiceTextPattern("\\b(?:open|launch|close|uninstall)\\s+([A-Za-z][A-Za-z0-9_.+-]*(?:\\s+[A-Za-z0-9_.+-]+){0,2})", options: [.caseInsensitive]),
  ]

  private static let devicePatterns = [
    VoiceTextPattern("(?:\u{5728}|\u{7528})([\\p{L}\\p{N}_.+-]{1,48})(?:\u{4e0a}|\u{8bbe}\u{5907})"),
    VoiceTextPattern("\\b(?:on|using)\\s+(?:the\\s+)?([A-Za-z][A-Za-z0-9_.+-]*(?:\\s+[A-Za-z0-9_.+-]+){0,2})", options: [.caseInsensitive]),
  ]

  private static let negationTerms = [
    (
      "negated",
      VoiceTextPattern("\\b(?:not|never|do not|don't|without)\\b|(?:\u{4e0d}\u{8981}|\u{4e0d}\u{7528}|\u{522b}|\u{7981}\u{6b62}|\u{672a}|\u{65e0})", options: [.caseInsensitive])
    ),
  ]

  private static let actionTerms = [
    ("send", VoiceTextPattern("\\b(?:send|message|share)\\b|(?:\u{53d1}\u{9001}|\u{53d1}\u{7ed9}|\u{5206}\u{4eab})", options: [.caseInsensitive])),
    ("delete", VoiceTextPattern("\\b(?:delete|remove|erase|wipe)\\b|(?:\u{5220}\u{9664}|\u{79fb}\u{9664}|\u{6e05}\u{7a7a})", options: [.caseInsensitive])),
    ("overwrite", VoiceTextPattern("\\b(?:overwrite|replace)\\b|(?:\u{8986}\u{76d6}|\u{66ff}\u{6362})", options: [.caseInsensitive])),
    ("pay", VoiceTextPattern("\\b(?:pay|transfer|purchase|order)\\b|(?:\u{652f}\u{4ed8}|\u{8f6c}\u{8d26}|\u{8d2d}\u{4e70}|\u{4e0b}\u{5355})", options: [.caseInsensitive])),
    ("call", VoiceTextPattern("\\b(?:call|dial)\\b|(?:\u{6253}\u{7535}\u{8bdd}|\u{62e8}\u{6253})", options: [.caseInsensitive])),
    ("install", VoiceTextPattern("\\b(?:install|uninstall)\\b|(?:\u{5b89}\u{88c5}|\u{5378}\u{8f7d})", options: [.caseInsensitive])),
    ("publish", VoiceTextPattern("\\b(?:publish|post publicly)\\b|(?:\u{53d1}\u{5e03}|\u{516c}\u{5f00})", options: [.caseInsensitive])),
  ]
}

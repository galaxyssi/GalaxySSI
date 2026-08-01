import CryptoKit
import Foundation

enum GlobalConversationEventType: String, Codable, CaseIterable, Identifiable {
  case messageCreated = "MESSAGE_CREATED"
  case messageUpdated = "MESSAGE_UPDATED"
  case messageDeleted = "MESSAGE_DELETED"
  case conversationCreated = "CONVERSATION_CREATED"
  case conversationUpdated = "CONVERSATION_UPDATED"
  case conversationMerged = "CONVERSATION_MERGED"
  case conversationDeleted = "CONVERSATION_DELETED"
  case attachmentAdded = "ATTACHMENT_ADDED"
  case artifactCreated = "ARTIFACT_CREATED"
  case taskUpdated = "TASK_UPDATED"
  case toolStarted = "TOOL_STARTED"
  case toolCompleted = "TOOL_COMPLETED"
  case toolCancelled = "TOOL_CANCELLED"
  case toolFailed = "TOOL_FAILED"
  case toolResult = "TOOL_RESULT"
  case cognitionResult = "COGNITION_RESULT"
  case userFeedback = "USER_FEEDBACK"
  case memoryCreated = "MEMORY_CREATED"
  case memoryUpdated = "MEMORY_UPDATED"
  case memoryConflicted = "MEMORY_CONFLICTED"
  case memoryDeleted = "MEMORY_DELETED"
  case knowledgeImported = "KNOWLEDGE_IMPORTED"
  case knowledgeUpdated = "KNOWLEDGE_UPDATED"
  case knowledgeAccessChanged = "KNOWLEDGE_ACCESS_CHANGED"
  case knowledgeDeleted = "KNOWLEDGE_DELETED"
  case authorizationGranted = "AUTHORIZATION_GRANTED"
  case authorizationRevoked = "AUTHORIZATION_REVOKED"
  case authorizationPolicyChanged = "AUTHORIZATION_POLICY_CHANGED"
  case resourceRegistered = "RESOURCE_REGISTERED"
  case resourceUpdated = "RESOURCE_UPDATED"
  case resourceRemoved = "RESOURCE_REMOVED"
  case resourceStateChanged = "RESOURCE_STATE_CHANGED"
  case capabilitySnapshotReset = "CAPABILITY_SNAPSHOT_RESET"

  var id: String { rawValue }

  var isCapabilityLifecycleEvent: Bool {
    Self.capabilityLifecycleEvents.contains(self)
  }

  private static let capabilityLifecycleEvents: Set<GlobalConversationEventType> = [
    .authorizationGranted,
    .authorizationRevoked,
    .authorizationPolicyChanged,
    .resourceRegistered,
    .resourceUpdated,
    .resourceRemoved,
    .resourceStateChanged,
    .capabilitySnapshotReset
  ]
}

enum GlobalConversationActor: String, Codable, CaseIterable, Identifiable {
  case user = "USER"
  case assistant = "ASSISTANT"
  case tool = "TOOL"
  case system = "SYSTEM"
  case globalAgent = "GLOBAL_AGENT"

  var id: String { rawValue }
}

enum GlobalConversationSensitivity: String, Codable, CaseIterable, Identifiable {
  case personal = "PERSONAL"
  case sessionPrivate = "SESSION_PRIVATE"

  var id: String { rawValue }
}

struct GlobalConversationEvent: Codable, Equatable, Identifiable {
  var id: String
  var type: GlobalConversationEventType
  var conversationId: String
  var messageId: String
  var actor: GlobalConversationActor
  var timestampMillis: Int64
  var content: String
  var contentRef: String
  var conversationTitle: String
  var topicHints: Set<String>
  var sensitivity: GlobalConversationSensitivity
  var metadata: [String: String]
  var causalEventIds: Set<String>
  var retractedEventIds: Set<String>

  init(
    id: String = UUID().uuidString,
    type: GlobalConversationEventType,
    conversationId: String,
    messageId: String = "",
    actor: GlobalConversationActor,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    content: String = "",
    contentRef: String = "",
    conversationTitle: String = "",
    topicHints: Set<String> = [],
    sensitivity: GlobalConversationSensitivity = .personal,
    metadata: [String: String] = [:],
    causalEventIds: Set<String> = [],
    retractedEventIds: Set<String> = []
  ) {
    self.id = id
    self.type = type
    self.conversationId = conversationId
    self.messageId = messageId
    self.actor = actor
    self.timestampMillis = timestampMillis
    self.content = content
    self.contentRef = contentRef
    self.conversationTitle = conversationTitle
    self.topicHints = topicHints
    self.sensitivity = sensitivity
    self.metadata = metadata
    self.causalEventIds = causalEventIds
    self.retractedEventIds = retractedEventIds
  }

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case actor
    case timestampMillis = "timestamp_millis"
    case content
    case contentRef = "content_ref"
    case conversationTitle = "conversation_title"
    case topicHints = "topic_hints"
    case sensitivity
    case metadata
    case causalEventIds = "causal_event_ids"
    case retractedEventIds = "retracted_event_ids"
  }
}

enum GlobalWorldLayer: String, Codable, CaseIterable, Identifiable {
  case conversation = "CONVERSATION"
  case topic = "TOPIC"
  case user = "USER"
  case realtime = "REALTIME"

  var id: String { rawValue }
}

enum GlobalWorldItemKind: String, Codable, CaseIterable, Identifiable {
  case topic = "TOPIC"
  case goal = "GOAL"
  case task = "TASK"
  case decision = "DECISION"
  case preference = "PREFERENCE"
  case fact = "FACT"
  case risk = "RISK"
  case opportunity = "OPPORTUNITY"
  case state = "STATE"

  var id: String { rawValue }
}

enum GlobalWorldContextVisibility: String, Codable, CaseIterable, Identifiable {
  case shareable = "SHAREABLE"
  case localOnly = "LOCAL_ONLY"

  var id: String { rawValue }
}

struct AgentResourceHealth: Codable, Equatable {
  var successes: Int
  var failures: Int
  var consecutiveFailures: Int
  var averageLatencyMs: Int64
  var circuitOpenUntil: Int64
  var lastUpdatedAt: Int64

  var reliabilityPercent: Int {
    let samples = successes + failures
    guard samples > 0 else { return 90 }
    return max(0, min(100, successes * 100 / samples))
  }

  init(
    successes: Int = 0,
    failures: Int = 0,
    consecutiveFailures: Int = 0,
    averageLatencyMs: Int64 = 0,
    circuitOpenUntil: Int64 = 0,
    lastUpdatedAt: Int64 = 0
  ) {
    self.successes = max(successes, 0)
    self.failures = max(failures, 0)
    self.consecutiveFailures = max(consecutiveFailures, 0)
    self.averageLatencyMs = max(averageLatencyMs, 0)
    self.circuitOpenUntil = max(circuitOpenUntil, 0)
    self.lastUpdatedAt = max(lastUpdatedAt, 0)
  }

  enum CodingKeys: String, CodingKey {
    case successes
    case failures
    case consecutiveFailures = "consecutive_failures"
    case averageLatencyMs = "average_latency_ms"
    case circuitOpenUntil = "circuit_open_until"
    case lastUpdatedAt = "last_updated_at"
  }
}

enum GlobalAgentText {
  private static let legacyProductTitles: [String: String] = [
    "Signal insight": "SignalASI insight",
    "Signal prepared": "SignalASI prepared",
    "Signal digest": "SignalASI digest",
    "Signal \u{5efa}\u{8bae}": "SignalASI \u{5efa}\u{8bae}",
    "Signal \u{5df2}\u{51c6}\u{5907}": "SignalASI \u{5df2}\u{51c6}\u{5907}",
    "Signal \u{6458}\u{8981}": "SignalASI \u{6458}\u{8981}"
  ]

  static func productTitle(_ value: String) -> String {
    let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return legacyProductTitles[title] ?? title
  }

  static func stableKey(_ values: String...) -> String {
    let normalized = values.map(normalize).joined(separator: "|").prefix(2_000)
    return privateFingerprint(String(normalized)).prefix(32).description
  }

  static func normalize(_ value: String) -> String {
    value.lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func privateFingerprint(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct LanguagePolicySettings: Codable, Equatable {
  static let auto = "auto"
  static let zhCN = "zh-CN"
  static let en = "en"
  static let enUS = "en-US"
  static let zhHK = "zh-HK"
  static let zhTW = "zh-TW"

  static let interfaceChoices = [auto, zhCN, en]
  static let voiceChoices = [auto, zhCN, enUS, zhHK, zhTW]

  var interfaceLanguage: String
  var responseLanguage: String
  var asrLanguage: String
  var ttsLanguage: String

  init(
    interfaceLanguage: String = LanguagePolicySettings.auto,
    responseLanguage: String = LanguagePolicySettings.auto,
    asrLanguage: String = LanguagePolicySettings.auto,
    ttsLanguage: String = LanguagePolicySettings.auto
  ) {
    self.interfaceLanguage = Self.normalizeInterface(interfaceLanguage)
    self.responseLanguage = Self.normalizeVoice(responseLanguage)
    self.asrLanguage = Self.normalizeVoice(asrLanguage)
    self.ttsLanguage = Self.normalizeVoice(ttsLanguage)
  }

  static let `default` = LanguagePolicySettings()

  var asrLocaleIdentifier: String {
    Self.localeIdentifier(for: Self.resolve(asrLanguage))
  }

  enum CodingKeys: String, CodingKey {
    case interfaceLanguage = "interface_language"
    case responseLanguage = "response_language"
    case asrLanguage = "asr_language"
    case ttsLanguage = "tts_language"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      interfaceLanguage: try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? Self.auto,
      responseLanguage: try container.decodeIfPresent(String.self, forKey: .responseLanguage) ?? Self.auto,
      asrLanguage: try container.decodeIfPresent(String.self, forKey: .asrLanguage) ?? Self.auto,
      ttsLanguage: try container.decodeIfPresent(String.self, forKey: .ttsLanguage) ?? Self.auto
    )
  }

  static func normalizeInterface(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return interfaceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func normalizeVoice(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func resolve(_ value: String) -> String {
    let normalized = normalizeVoice(value)
    guard normalized == auto else { return normalized }
    return Locale.current.identifier.replacingOccurrences(of: "_", with: "-").ifBlank(enUS)
  }

  static func localeIdentifier(for languageTag: String) -> String {
    resolve(languageTag).replacingOccurrences(of: "-", with: "_")
  }

  static func displayName(_ value: String) -> String {
    switch normalizeVoice(value) {
    case zhCN: return "Simplified Chinese"
    case enUS: return "English (United States)"
    case zhHK: return "Traditional Chinese (Hong Kong)"
    case zhTW: return "Traditional Chinese (Taiwan)"
    default: return "Automatic"
    }
  }

  static func interfaceDisplayName(_ value: String) -> String {
    switch normalizeInterface(value) {
    case zhCN: return "Simplified Chinese"
    case en: return "English"
    default: return "Automatic"
    }
  }

  static func modelLanguageName(_ value: String) -> String {
    let resolved = resolve(value)
    if resolved.caseInsensitiveCompare(zhCN) == .orderedSame || resolved.hasPrefix("zh-Hans") {
      return "Simplified Chinese"
    }
    if resolved.caseInsensitiveCompare(zhHK) == .orderedSame ||
       resolved.caseInsensitiveCompare(zhTW) == .orderedSame ||
       resolved.hasPrefix("zh-Hant") {
      return "Traditional Chinese"
    }
    let locale = Locale(identifier: localeIdentifier(for: resolved))
    let english = Locale(identifier: "en_US")
    return english.localizedString(forLanguageCode: locale.languageCode ?? "")?.capitalized ?? "English"
  }

  static func microsoftVoice(languageTag: String, configuredVoice: String) -> String {
    let resolved = resolve(languageTag)
    let expectedPrefix = "\(resolved.lowercased())-"
    if configuredVoice.lowercased().hasPrefix(expectedPrefix) {
      return configuredVoice
    }
    if resolved.caseInsensitiveCompare(zhHK) == .orderedSame {
      return "zh-HK-HiuMaanNeural"
    }
    if resolved.caseInsensitiveCompare(zhTW) == .orderedSame {
      return "zh-TW-HsiaoChenNeural"
    }
    if resolved.lowercased().hasPrefix("zh") {
      return "zh-CN-XiaoxiaoNeural"
    }
    return "en-US-JennyNeural"
  }
}

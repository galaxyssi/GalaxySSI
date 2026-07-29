import Foundation

enum SignalASITrustState: String, Codable, CaseIterable {
  case unverified
  case verified
  case deleted
}

enum SignalASIDeliveryMode: String, Codable, CaseIterable {
  case local
  case link
  case cloudAPI
}

enum SignalASICloudAPIStyle: String, Codable, CaseIterable, Identifiable {
  case openAICompatible = "openai"
  case anthropic
  case gemini

  var id: String { rawValue }
}

struct SignalASIProfile: Codable, Equatable {
  var signalASIId: String
  var name: String
  var identityFingerprint: String
  var identityPublicKey: String
}

struct SignalASIContact: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var signalASIId: String
  var name: String
  var displayName: String
  var type: String
  var agentKind: String
  var deliveryMode: SignalASIDeliveryMode
  var trustState: SignalASITrustState
  var desktopId: String
  var desktopName: String
  var identityFingerprint: String
  var setupStatus: String
  var setupDetail: String
  var cloudProvider: String
  var cloudModels: [CloudModelConfig]
  var selectedCloudModelId: String
  var deleted: Bool
  var createdAt: Date
  var updatedAt: Date
  var mqttTopic: String? = nil
  var mqttInboxTopic: String? = nil
  var signalBundleRef: String? = nil
  var deletedAt: Date? = nil

  var selectedCloudModel: CloudModelConfig? {
    cloudModels.first { $0.modelId == selectedCloudModelId } ?? cloudModels.first
  }

  var isCommunicable: Bool {
    !deleted && trustState == .verified
  }

  static func hermes() -> SignalASIContact {
    SignalASIContact(
      id: "hermes",
      signalASIId: "hermes",
      name: "Hermes Agent",
      displayName: "Hermes Agent",
      type: "hermes",
      agentKind: "desktop-agent",
      deliveryMode: .link,
      trustState: .unverified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "needs_pairing",
      setupDetail: "Waiting for SignalASI Desktop pairing",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: Date(),
      updatedAt: Date()
    )
  }

  static func system() -> SignalASIContact {
    SignalASIContact(
      id: "system",
      signalASIId: "system",
      name: "System",
      displayName: "System",
      type: "system",
      agentKind: "local",
      deliveryMode: .local,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "ready",
      setupDetail: "Local notices",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: Date(),
      updatedAt: Date()
    )
  }
}

enum SignalASIFriendRequestStatus: String, Codable, CaseIterable {
  case pending
  case approved
  case rejected
  case deleted
}

struct SignalASIFriendRequest: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var signalASIId: String
  var name: String
  var type: String
  var identityPublicKey: String
  var identityFingerprint: String
  var mqttTopic: String
  var mqttInboxTopic: String
  var signalBundleRef: String
  var source: String
  var status: SignalASIFriendRequestStatus
  var createdAt: Date
  var approvedAt: Date?
  var rejectedAt: Date?
  var deletedAt: Date?
  var previouslyDeleted: Bool
  var readdRequired: Bool

  init(
    id: String,
    signalASIId: String,
    name: String,
    type: String,
    identityPublicKey: String,
    identityFingerprint: String,
    mqttTopic: String,
    mqttInboxTopic: String,
    signalBundleRef: String = "",
    source: String = "qr",
    status: SignalASIFriendRequestStatus = .pending,
    createdAt: Date = Date(),
    approvedAt: Date? = nil,
    rejectedAt: Date? = nil,
    deletedAt: Date? = nil,
    previouslyDeleted: Bool = false,
    readdRequired: Bool = false
  ) {
    self.id = id
    self.signalASIId = signalASIId
    self.name = name
    self.type = type
    self.identityPublicKey = identityPublicKey
    self.identityFingerprint = identityFingerprint
    self.mqttTopic = mqttTopic
    self.mqttInboxTopic = mqttInboxTopic
    self.signalBundleRef = signalBundleRef
    self.source = source
    self.status = status
    self.createdAt = createdAt
    self.approvedAt = approvedAt
    self.rejectedAt = rejectedAt
    self.deletedAt = deletedAt
    self.previouslyDeleted = previouslyDeleted
    self.readdRequired = readdRequired
  }

  enum CodingKeys: String, CodingKey {
    case id
    case signalASIId = "signalasi_id"
    case name
    case type
    case identityPublicKey = "identity_public_key"
    case identityFingerprint = "identity_fingerprint"
    case mqttTopic = "mqtt_topic"
    case mqttInboxTopic = "mqtt_inbox_topic"
    case signalBundleRef = "signal_bundle_ref"
    case source
    case status
    case createdAt = "created_at"
    case approvedAt = "approved_at"
    case rejectedAt = "rejected_at"
    case deletedAt = "deleted_at"
    case previouslyDeleted = "previously_deleted"
    case readdRequired = "readd_required"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    signalASIId = try container.decodeIfPresent(String.self, forKey: .signalASIId) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Friend"
    type = try container.decodeIfPresent(String.self, forKey: .type) ?? "person"
    identityPublicKey = try container.decodeIfPresent(String.self, forKey: .identityPublicKey) ?? ""
    identityFingerprint = try container.decodeIfPresent(String.self, forKey: .identityFingerprint) ?? ""
    mqttTopic = try container.decodeIfPresent(String.self, forKey: .mqttTopic) ?? ""
    mqttInboxTopic = try container.decodeIfPresent(String.self, forKey: .mqttInboxTopic) ?? mqttTopic
    signalBundleRef = try container.decodeIfPresent(String.self, forKey: .signalBundleRef) ?? ""
    source = try container.decodeIfPresent(String.self, forKey: .source) ?? "qr"
    status = try container.decodeIfPresent(SignalASIFriendRequestStatus.self, forKey: .status) ?? .pending
    createdAt = Self.decodeDate(container, key: .createdAt) ?? Date()
    approvedAt = Self.decodeDate(container, key: .approvedAt)
    rejectedAt = Self.decodeDate(container, key: .rejectedAt)
    deletedAt = Self.decodeDate(container, key: .deletedAt)
    previouslyDeleted = try container.decodeIfPresent(Bool.self, forKey: .previouslyDeleted) ?? false
    readdRequired = try container.decodeIfPresent(Bool.self, forKey: .readdRequired) ?? previouslyDeleted
  }

  private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
    if let date = try? container.decode(Date.self, forKey: key) {
      return date
    }
    if let milliseconds = try? container.decode(Double.self, forKey: key), milliseconds > 0 {
      return Date(timeIntervalSince1970: (milliseconds < 10_000_000_000 ? milliseconds * 1000 : milliseconds) / 1000)
    }
    if let value = try? container.decode(String.self, forKey: key),
       let milliseconds = Double(value), milliseconds > 0 {
      return Date(timeIntervalSince1970: (milliseconds < 10_000_000_000 ? milliseconds * 1000 : milliseconds) / 1000)
    }
    return nil
  }
}

struct CloudModelConfig: Codable, Identifiable, Equatable, Hashable {
  var id: String
  var displayName: String
  var provider: String
  var modelId: String
  var endpoint: String
  var apiStyle: SignalASICloudAPIStyle
  var keychainAccount: String
  var updatedAt: Date
}

struct CloudModelPreset: Identifiable, Equatable, Hashable {
  var id: String { "\(provider)-\(modelId)" }
  var provider: String
  var name: String
  var modelId: String
  var endpoint: String
  var apiStyle: SignalASICloudAPIStyle

  static let androidParity: [CloudModelPreset] = [
    CloudModelPreset(provider: "OpenAI", name: "GPT-5.5", modelId: "gpt-5.5", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenAI", name: "GPT-5.4 mini", modelId: "gpt-5.4-mini", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenAI", name: "GPT-5", modelId: "gpt-5", endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Anthropic", name: "Claude Opus 4.7", modelId: "claude-opus-4-7-latest", endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
    CloudModelPreset(provider: "Anthropic", name: "Claude Sonnet 5", modelId: "claude-sonnet-5-latest", endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
    CloudModelPreset(provider: "Google Gemini", name: "Gemini 3.5 Flash", modelId: "gemini-3.5-flash", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent", apiStyle: .gemini),
    CloudModelPreset(provider: "DeepSeek", name: "DeepSeek V4 Pro", modelId: "deepseek-v4-pro", endpoint: "https://api.deepseek.com/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Qwen", name: "Qwen 3.7 Max", modelId: "qwen3.7-max", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "OpenRouter", name: "OpenRouter Auto", modelId: "openrouter/auto", endpoint: "https://openrouter.ai/api/v1/chat/completions", apiStyle: .openAICompatible),
    CloudModelPreset(provider: "Custom", name: "OpenAI Compatible", modelId: "model-id", endpoint: "https://api.example.com/v1/chat/completions", apiStyle: .openAICompatible)
  ]
}

enum CloudModelCredentialPolicy {
  private static let placeholderCredentials: Set<String> = [
    "key",
    "api-key",
    "your-api-key",
    "your_api_key",
    "replace-me",
    "replace_me"
  ]

  private static let debugCredentials: Set<String> = [
    "smoke-key",
    "backup-smoke-key",
    "sk-signalasi-smoke-key"
  ]

  static func isStoredCredential(_ value: String?) -> Bool {
    let credential = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if credential.isEmpty || credential.contains("*") {
      return false
    }
    return !placeholderCredentials.contains(credential.lowercased())
  }

  static func isDebugFixtureCredential(_ value: String?) -> Bool {
    let credential = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return debugCredentials.contains(credential) ||
      credential.contains("signalasi-smoke") ||
      credential.hasPrefix("backup-smoke-")
  }

  static func isAutoRoutableCredential(_ value: String?) -> Bool {
    isStoredCredential(value) && !isDebugFixtureCredential(value)
  }

  static func isAutoRoutable(
    model: CloudModelConfig,
    apiKey: String?,
    provider: String,
    setupStatus: String = "ready"
  ) -> Bool {
    let endpoint = model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelId = model.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let status = setupStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    return (status.isEmpty || status.localizedCaseInsensitiveCompare("ready") == .orderedSame) &&
      !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !modelId.isEmpty &&
      modelId.localizedCaseInsensitiveCompare("model-id") != .orderedSame &&
      endpoint.lowercased().hasPrefix("https://") &&
      !endpoint.localizedCaseInsensitiveContains("example.com") &&
      isAutoRoutableCredential(apiKey)
  }
}

enum ChatDeliveryStatus: String, Codable, Equatable {
  case local
  case queued
  case sent
  case delivered
  case failed
}

struct DeliveryTraceEvent: Codable, Equatable, Identifiable {
  var id: UUID
  var stage: String
  var detail: String
  var createdAt: Date

  init(id: UUID = UUID(), stage: String, detail: String = "", createdAt: Date = Date()) {
    self.id = id
    self.stage = stage
    self.detail = detail
    self.createdAt = createdAt
  }

  var displayTitle: String {
    switch stage {
    case "created": return "Created"
    case "persisted": return "Persisted"
    case "queued": return "Queued"
    case "sent": return "Sent"
    case "delivered": return "Delivered"
    case "failed": return "Failed"
    case "mqtt_published": return "Published to MQTT"
    case "publish_failed": return "Publish failed"
    case "delivered_local_estimate": return "Delivery estimated"
    case "desktop_received": return "Desktop received"
    case "desktop_plain": return "Desktop plaintext debug"
    case "desktop_decrypted": return "Desktop decrypted"
    case "agent_started": return "Agent started"
    case "agent_first_output": return "First Agent output"
    case "agent_replied": return "Agent replied"
    case "desktop_reply_publish_queued": return "Desktop reply queued"
    case "desktop_reply_broker_ack": return "Desktop reply Broker ACK"
    case "desktop_broker_ack": return "Broker confirmed"
    case "desktop_mobile_test_queued": return "Desktop test queued"
    case "desktop_agent_push_queued": return "Agent Push queued"
    case "desktop_connector_status": return "Connector status synced"
    case "desktop_pairing_confirmed": return "Pairing confirmed"
    case "desktop_pairing_revocation_queued": return "Pairing revocation queued"
    case "received": return "Received"
    case "decrypted": return "Decrypted"
    case "cloud_request": return "Model request"
    case "cloud_reply": return "Model replied"
    case "cloud_reply_received": return "Model reply received"
    case "cloud_error": return "Model error"
    default: return stage
    }
  }
}

struct ChatMessage: Codable, Identifiable, Equatable {
  var id: UUID
  var contactId: String
  var content: String
  var isMine: Bool
  var isSystem: Bool
  var createdAt: Date
  var deliveryStatus: ChatDeliveryStatus
  var deliveryTrace: [DeliveryTraceEvent]
  var conversationId: String
  var turnId: String
  var remoteMessageId: String

  init(
    id: UUID = UUID(),
    contactId: String,
    content: String,
    isMine: Bool,
    isSystem: Bool = false,
    createdAt: Date = Date(),
    deliveryStatus: ChatDeliveryStatus = .local,
    deliveryTrace: [DeliveryTraceEvent] = [],
    conversationId: String = "",
    turnId: String = "",
    remoteMessageId: String = ""
  ) {
    self.id = id
    self.contactId = contactId
    self.content = content
    self.isMine = isMine
    self.isSystem = isSystem
    self.createdAt = createdAt
    self.deliveryStatus = deliveryStatus
    self.deliveryTrace = deliveryTrace
    self.conversationId = conversationId
    self.turnId = turnId
    self.remoteMessageId = remoteMessageId
  }
}

struct SignalASILinkRoutes: Codable, Equatable, Hashable {
  var serverRouteId: String
  var clientRouteId: String

  var pairingTopic: String {
    "\(SignalASILinkProtocol.topicRoot)/\(serverRouteId)/pair"
  }

  var upTopic: String {
    "\(SignalASILinkProtocol.topicRoot)/\(serverRouteId)/\(clientRouteId)/up"
  }

  var downTopic: String {
    "\(SignalASILinkProtocol.topicRoot)/\(serverRouteId)/\(clientRouteId)/down"
  }

  var controlTopic: String {
    "\(SignalASILinkProtocol.topicRoot)/\(serverRouteId)/\(clientRouteId)/control"
  }
}

struct PairingAccess: Codable, Equatable, Hashable {
  var profile: String
  var scopes: Set<String>

  var fullDesktopExecutor: Bool {
    profile == SignalASILinkProtocol.accessDesktopExecutor &&
      scopes.contains(SignalASILinkProtocol.scopeDesktopExecutor)
  }
}

struct ServerLink: Codable, Identifiable, Equatable, Hashable {
  var id: String { desktopId }
  var desktopId: String
  var desktopName: String
  var desktopFingerprint: String
  var signalName: String
  var routes: SignalASILinkRoutes
  var paired: Bool
  var accessProfile: String
  var accessScopes: Set<String>
  var updatedAt: Date

  var fullDesktopExecutor: Bool {
    accessProfile == SignalASILinkProtocol.accessDesktopExecutor &&
      accessScopes.contains(SignalASILinkProtocol.scopeDesktopExecutor)
  }
}

enum VoiceRoutingMode: String, Codable, CaseIterable, Identifiable {
  case nativeAgent = "native_agent"
  case contact

  var id: String { rawValue }

  var displayTitle: String {
    switch self {
    case .nativeAgent: return "Native Agent"
    case .contact: return "Chat Contact"
    }
  }
}

struct VoiceSettings: Codable, Equatable {
  var wakeListeningEnabled: Bool
  var speechRecognitionEnabled: Bool
  var textToSpeechEnabled: Bool
  var autoSendTranscripts: Bool
  var preferredLocaleIdentifier: String
  var wakeWords: [String]
  var wakeThreshold: Double
  var welcomeText: String
  var targetContactId: String
  var speakReplies: Bool
  var routingMode: VoiceRoutingMode

  init(
    wakeListeningEnabled: Bool,
    speechRecognitionEnabled: Bool,
    textToSpeechEnabled: Bool,
    autoSendTranscripts: Bool,
    preferredLocaleIdentifier: String,
    wakeWords: [String] = VoiceSettings.defaultWakeWords,
    wakeThreshold: Double = 0.5,
    welcomeText: String = VoiceSettings.defaultWelcomeText,
    targetContactId: String = "hermes",
    speakReplies: Bool = true,
    routingMode: VoiceRoutingMode = .nativeAgent
  ) {
    self.wakeListeningEnabled = wakeListeningEnabled
    self.speechRecognitionEnabled = speechRecognitionEnabled
    self.textToSpeechEnabled = textToSpeechEnabled
    self.autoSendTranscripts = autoSendTranscripts
    self.preferredLocaleIdentifier = preferredLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Locale.current.identifier)
    self.wakeWords = Self.normalizedWakeWords(wakeWords)
    self.wakeThreshold = min(max(wakeThreshold, 0.01), 0.99)
    self.welcomeText = welcomeText.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(Self.defaultWelcomeText)
    self.targetContactId = targetContactId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("hermes")
    self.speakReplies = speakReplies
    self.routingMode = routingMode
  }

  static let `default` = VoiceSettings(
    wakeListeningEnabled: false,
    speechRecognitionEnabled: true,
    textToSpeechEnabled: true,
    autoSendTranscripts: false,
    preferredLocaleIdentifier: Locale.current.identifier,
    wakeWords: defaultWakeWords,
    wakeThreshold: 0.5,
    welcomeText: defaultWelcomeText,
    targetContactId: "hermes",
    speakReplies: true,
    routingMode: .nativeAgent
  )

  static let defaultWakeWords = [
    "SignalASI",
    "signal asi",
    "signal ai",
    "hello",
    "hi"
  ]

  static let defaultWelcomeText = "I am here. Welcome to SignalASI. Say your question or task."

  var wakeWordsText: String {
    wakeWords.joined(separator: ", ")
  }

  var normalized: VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: wakeListeningEnabled,
      speechRecognitionEnabled: speechRecognitionEnabled,
      textToSpeechEnabled: textToSpeechEnabled,
      autoSendTranscripts: autoSendTranscripts,
      preferredLocaleIdentifier: preferredLocaleIdentifier,
      wakeWords: wakeWords,
      wakeThreshold: wakeThreshold,
      welcomeText: welcomeText,
      targetContactId: targetContactId,
      speakReplies: speakReplies,
      routingMode: routingMode
    )
  }

  enum CodingKeys: String, CodingKey {
    case wakeListeningEnabled
    case speechRecognitionEnabled
    case textToSpeechEnabled
    case autoSendTranscripts
    case preferredLocaleIdentifier
    case wakeWords = "wake_words"
    case wakeThreshold = "wake_threshold"
    case welcomeText = "welcome_text"
    case targetContactId = "target_contact_id"
    case speakReplies = "speak_replies"
    case routingMode = "routing_mode"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      wakeListeningEnabled: try container.decodeIfPresent(Bool.self, forKey: .wakeListeningEnabled) ?? false,
      speechRecognitionEnabled: try container.decodeIfPresent(Bool.self, forKey: .speechRecognitionEnabled) ?? true,
      textToSpeechEnabled: try container.decodeIfPresent(Bool.self, forKey: .textToSpeechEnabled) ?? true,
      autoSendTranscripts: try container.decodeIfPresent(Bool.self, forKey: .autoSendTranscripts) ?? false,
      preferredLocaleIdentifier: try container.decodeIfPresent(String.self, forKey: .preferredLocaleIdentifier) ?? Locale.current.identifier,
      wakeWords: try container.decodeIfPresent([String].self, forKey: .wakeWords) ?? Self.defaultWakeWords,
      wakeThreshold: try container.decodeIfPresent(Double.self, forKey: .wakeThreshold) ?? 0.5,
      welcomeText: try container.decodeIfPresent(String.self, forKey: .welcomeText) ?? Self.defaultWelcomeText,
      targetContactId: try container.decodeIfPresent(String.self, forKey: .targetContactId) ?? "hermes",
      speakReplies: try container.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? true,
      routingMode: try container.decodeIfPresent(VoiceRoutingMode.self, forKey: .routingMode) ?? .nativeAgent
    )
  }

  static func wakeWords(from text: String) -> [String] {
    normalizedWakeWords(text.split(separator: ",").map(String.init))
  }

  private static func normalizedWakeWords(_ words: [String]) -> [String] {
    let normalized = words
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return normalized.isEmpty ? defaultWakeWords : Array(normalized.prefix(12))
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
}

enum SignalASIError: LocalizedError {
  case invalidPairingQRCode(String)
  case invalidPayload(String)
  case missingCloudModel
  case missingAPIKey
  case notPaired
  case transportUnavailable
  case unsupportedResponse

  var errorDescription: String? {
    switch self {
    case .invalidPairingQRCode(let detail):
      return "Invalid SignalASI pairing QR: \(detail)"
    case .invalidPayload(let detail):
      return "Invalid SignalASI payload: \(detail)"
    case .missingCloudModel:
      return "No cloud model is selected for this contact."
    case .missingAPIKey:
      return "No API key is saved for this cloud model."
    case .notPaired:
      return "SignalASI Desktop is not paired yet."
    case .transportUnavailable:
      return "SignalASI Link transport is unavailable."
    case .unsupportedResponse:
      return "The model provider returned an unsupported response."
    }
  }
}

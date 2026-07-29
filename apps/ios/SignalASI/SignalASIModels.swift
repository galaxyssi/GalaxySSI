import CryptoKit
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

enum AppTextScaleMode: String, Codable, CaseIterable, Identifiable {
  case system
  case standard
  case comfortable
  case large
  case extraLarge = "extra_large"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AppTextScaleMode {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .comfortable
  }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .standard: return "Standard"
    case .comfortable: return "Comfortable"
    case .large: return "Large"
    case .extraLarge: return "Extra Large"
    }
  }

  var detail: String {
    switch self {
    case .system:
      return "Follow the iOS system text size."
    case .standard:
      return "Use the app's compact default text size."
    case .comfortable:
      return "Use the Android default comfortable text size."
    case .large:
      return "Increase text for easier reading."
    case .extraLarge:
      return "Use the largest app text size."
    }
  }
}

struct AppDisplaySettings: Codable, Equatable {
  var textScale: AppTextScaleMode

  static let `default` = AppDisplaySettings()

  init(textScale: AppTextScaleMode = .comfortable) {
    self.textScale = textScale
  }

  enum CodingKeys: String, CodingKey {
    case textScale = "text_scale"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(textScale: AppTextScaleMode.fromWireValue(try container.decodeIfPresent(String.self, forKey: .textScale)))
  }
}

enum AgentTaskExecutionMode: String, CaseIterable, Identifiable, Codable {
  case planOnly = "plan_only"
  case autoComplete = "auto_complete"

  var id: String { rawValue }

  var androidName: String {
    switch self {
    case .planOnly: return "PLAN_ONLY"
    case .autoComplete: return "AUTO_COMPLETE"
    }
  }

  var displayTitle: String {
    switch self {
    case .planOnly: return "Plan only"
    case .autoComplete: return "Auto complete"
    }
  }

  var detail: String {
    switch self {
    case .planOnly:
      return "Inspect context and return an actionable plan without changing anything."
    case .autoComplete:
      return "Continue through execution, recovery, verification, and completion."
    }
  }

  static func fromStoredValue(_ value: String?) -> AgentTaskExecutionMode {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lowered = trimmed.lowercased()
    let uppercased = trimmed.uppercased()
    return allCases.first { $0.rawValue == lowered || $0.androidName == uppercased } ?? .autoComplete
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromStoredValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(androidName)
  }
}

enum AgentPermissionMode: String, CaseIterable, Identifiable, Codable {
  case observeOnly = "OBSERVE_ONLY"
  case suggestOnly = "SUGGEST_ONLY"
  case askBeforeAction = "ASK_BEFORE_ACTION"
  case autoLowRisk = "AUTO_LOW_RISK"

  var id: String { rawValue }

  var displayTitle: String {
    switch self {
    case .observeOnly: return "Observe Only"
    case .suggestOnly: return "Suggest Only"
    case .askBeforeAction: return "Ask Before Action"
    case .autoLowRisk: return "Auto Low-risk"
    }
  }

  var detail: String {
    switch self {
    case .observeOnly:
      return "Read current screen and device state; never create or execute actions."
    case .suggestOnly:
      return "Build plans and suggestions, but block every executable action."
    case .askBeforeAction:
      return "Require confirmation before every executable action."
    case .autoLowRisk:
      return "Run direct actions, remember first-time consent, and always confirm high-risk actions."
    }
  }

  static func fromStoredValue(_ value: String?) -> AgentPermissionMode {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalized = trimmed.uppercased().replacingOccurrences(of: "-", with: "_")
    return allCases.first { $0.rawValue == normalized } ?? .askBeforeAction
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromStoredValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentSafetySettings: Codable, Equatable {
  var taskExecutionMode: AgentTaskExecutionMode
  var permissionMode: AgentPermissionMode
  var highRiskGuard: Bool
  var memoryCapture: Bool
  var screenObservationAllowed: Bool
  var localActionsAllowed: Bool
  var connectorCallsAllowed: Bool
  var deviceControlAllowed: Bool
  var executionPaused: Bool

  init(
    taskExecutionMode: AgentTaskExecutionMode = .autoComplete,
    permissionMode: AgentPermissionMode = .askBeforeAction,
    highRiskGuard: Bool = true,
    memoryCapture: Bool = true,
    screenObservationAllowed: Bool = true,
    localActionsAllowed: Bool = true,
    connectorCallsAllowed: Bool = true,
    deviceControlAllowed: Bool = true,
    executionPaused: Bool = false
  ) {
    self.taskExecutionMode = taskExecutionMode
    self.permissionMode = permissionMode
    self.highRiskGuard = highRiskGuard
    self.memoryCapture = memoryCapture
    self.screenObservationAllowed = screenObservationAllowed
    self.localActionsAllowed = localActionsAllowed
    self.connectorCallsAllowed = connectorCallsAllowed
    self.deviceControlAllowed = deviceControlAllowed
    self.executionPaused = executionPaused
  }

  static let `default` = AgentSafetySettings()

  enum CodingKeys: String, CodingKey {
    case taskExecutionMode = "task_execution_mode"
    case permissionMode = "permission_mode"
    case highRiskGuard = "high_risk_guard"
    case memoryCapture = "memory_capture"
    case screenObservationAllowed = "screen_observation_allowed"
    case localActionsAllowed = "local_actions_allowed"
    case connectorCallsAllowed = "connector_calls_allowed"
    case deviceControlAllowed = "device_control_allowed"
    case executionPaused = "execution_paused"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      taskExecutionMode: try container.decodeIfPresent(AgentTaskExecutionMode.self, forKey: .taskExecutionMode) ?? .autoComplete,
      permissionMode: try container.decodeIfPresent(AgentPermissionMode.self, forKey: .permissionMode) ?? .askBeforeAction,
      highRiskGuard: try container.decodeIfPresent(Bool.self, forKey: .highRiskGuard) ?? true,
      memoryCapture: try container.decodeIfPresent(Bool.self, forKey: .memoryCapture) ?? true,
      screenObservationAllowed: try container.decodeIfPresent(Bool.self, forKey: .screenObservationAllowed) ?? true,
      localActionsAllowed: try container.decodeIfPresent(Bool.self, forKey: .localActionsAllowed) ?? true,
      connectorCallsAllowed: try container.decodeIfPresent(Bool.self, forKey: .connectorCallsAllowed) ?? true,
      deviceControlAllowed: try container.decodeIfPresent(Bool.self, forKey: .deviceControlAllowed) ?? true,
      executionPaused: try container.decodeIfPresent(Bool.self, forKey: .executionPaused) ?? false
    )
  }
}

enum AgentActionKind: String, Codable, CaseIterable, Identifiable {
  case readScreen = "READ_SCREEN"
  case saveScreenKnowledge = "SAVE_SCREEN_KNOWLEDGE"
  case draftPlan = "DRAFT_PLAN"
  case tap = "TAP"
  case typeText = "TYPE_TEXT"
  case swipe = "SWIPE"
  case longPress = "LONG_PRESS"
  case back = "BACK"
  case home = "HOME"
  case recents = "RECENTS"
  case lockScreen = "LOCK_SCREEN"
  case openApp = "OPEN_APP"
  case openURL = "OPEN_URL"
  case setAlarm = "SET_ALARM"
  case createNotification = "CREATE_NOTIFICATION"
  case replyNotification = "REPLY_NOTIFICATION"
  case importWebKnowledge = "IMPORT_WEB_KNOWLEDGE"
  case copyScreenText = "COPY_SCREEN_TEXT"
  case deleteText = "DELETE_TEXT"
  case pasteText = "PASTE_TEXT"
  case callConnector = "CALL_CONNECTOR"
  case callNativeTool = "CALL_NATIVE_TOOL"
  case controlDevice = "CONTROL_DEVICE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentActionKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .draftPlan
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentActionStatus: String, Codable, CaseIterable, Identifiable {
  case proposed = "PROPOSED"
  case pendingConfirmation = "PENDING_CONFIRMATION"
  case running = "RUNNING"
  case waitingResponse = "WAITING_RESPONSE"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case blocked = "BLOCKED"
  case rolledBack = "ROLLED_BACK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentActionStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pendingConfirmation
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRisk: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"
  case blocked = "BLOCKED"

  var id: String { rawValue }

  var weight: Int {
    switch self {
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    case .blocked: return 4
    }
  }

  static func fromWireValue(_ value: String?) -> AgentRisk {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .medium
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentPhase: String, Codable, CaseIterable, Identifiable {
  case observing = "OBSERVING"
  case planning = "PLANNING"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case executing = "EXECUTING"
  case verifying = "VERIFYING"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case cancelled = "CANCELLED"
  case blocked = "BLOCKED"
  case completed = "COMPLETED"
  case failed = "FAILED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPhase {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .executing
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRouteKind: String, Codable, CaseIterable, Identifiable {
  case localSystem = "LOCAL_SYSTEM"
  case cloudModel = "CLOUD_MODEL"
  case localModel = "LOCAL_MODEL"
  case desktopAgent = "DESKTOP_AGENT"
  case deviceConnector = "DEVICE_CONNECTOR"
  case knowledge = "KNOWLEDGE"
  case unknown = "UNKNOWN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRouteKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unknown
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentExecutionLocationKind: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case desktop = "DESKTOP"
  case cloud = "CLOUD"
  case connectedDevice = "CONNECTED_DEVICE"
  case unknown = "UNKNOWN"

  var id: String { rawValue }
}

struct AgentExecutionPresentation: Codable, Equatable {
  var executorId: String
  var executorLabel: String
  var locationKind: AgentExecutionLocationKind
  var locationLabelHint: String
  var currentStep: String
  var phase: AgentPhase
  var cancellable: Bool
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  init(
    executorId: String,
    executorLabel: String,
    locationKind: AgentExecutionLocationKind,
    locationLabelHint: String,
    currentStep: String,
    phase: AgentPhase,
    cancellable: Bool,
    startedAtMillis: Int64,
    completedAtMillis: Int64 = 0
  ) {
    self.executorId = executorId
    self.executorLabel = executorLabel
    self.locationKind = locationKind
    self.locationLabelHint = locationLabelHint
    self.currentStep = currentStep
    self.phase = phase
    self.cancellable = cancellable
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis
  }
}

enum AgentExecutionPresentationPolicy {
  static func local(
    routeKind: AgentRouteKind,
    targetTitle: String,
    selectedAgentOrModel: String,
    phase: AgentPhase,
    currentStep: String,
    startedAtMillis: Int64,
    completedAtMillis: Int64 = 0
  ) -> AgentExecutionPresentation {
    let targetTitle = trim(targetTitle)
    let fallbackTarget = trim(selectedAgentOrModel)
    let target = targetTitle.isEmpty ? fallbackTarget : targetTitle
    let targetParts = target.components(separatedBy: targetSeparator).map(trim)
    let firstTarget = targetParts.first ?? ""
    let locationKind: AgentExecutionLocationKind
    switch routeKind {
    case .cloudModel:
      locationKind = .cloud
    case .desktopAgent:
      locationKind = .desktop
    case .deviceConnector:
      locationKind = .connectedDevice
    case .localSystem, .localModel, .knowledge:
      locationKind = .phone
    case .unknown:
      locationKind = .unknown
    }
    let executor: String
    switch routeKind {
    case .localSystem, .knowledge, .unknown:
      executor = "SignalASI"
    default:
      executor = firstTarget.isEmpty ? "SignalASI" : firstTarget
    }
    return AgentExecutionPresentation(
      executorId: firstTarget.isEmpty ? "signalasi" : firstTarget,
      executorLabel: executor,
      locationKind: locationKind,
      locationLabelHint: locationKind == .desktop && targetParts.count > 1 ? targetParts[1] : "",
      currentStep: trim(currentStep),
      phase: phase,
      cancellable: isCancellable(phase),
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis
    )
  }

  static func remote(
    executorId: String,
    executorLabel: String,
    locationKind: String,
    locationName: String,
    status: String,
    currentStep: String,
    startedAtMillis: Int64,
    completedAtMillis: Int64,
    advertisedCancellable: Bool
  ) -> AgentExecutionPresentation {
    let phase = phaseForRemoteStatus(status)
    let cleanExecutorId = trim(executorId)
    let cleanExecutorLabel = trim(executorLabel)
    let resolvedExecutorId = cleanExecutorId.isEmpty ? cleanExecutorLabel : cleanExecutorId
    let resolvedExecutorLabel: String
    if cleanExecutorLabel.isEmpty {
      resolvedExecutorLabel = cleanExecutorId.isEmpty ? "Agent" : cleanExecutorId
    } else {
      resolvedExecutorLabel = cleanExecutorLabel
    }
    return AgentExecutionPresentation(
      executorId: resolvedExecutorId,
      executorLabel: resolvedExecutorLabel,
      locationKind: locationKindForRemoteValue(locationKind),
      locationLabelHint: trim(locationName),
      currentStep: trim(currentStep),
      phase: phase,
      cancellable: advertisedCancellable && isCancellable(phase),
      startedAtMillis: startedAtMillis,
      completedAtMillis: completedAtMillis
    )
  }

  static func isCancellable(_ phase: AgentPhase) -> Bool {
    ![.completed, .failed, .cancelled, .blocked].contains(phase)
  }

  static func phaseForRemoteStatus(_ status: String) -> AgentPhase {
    switch trim(status).lowercased() {
    case "waiting_input", "waiting_approval":
      return .paused
    case "completed":
      return .completed
    case "failed", "timed_out", "not_found":
      return .failed
    case "cancelled":
      return .cancelled
    default:
      return .executing
    }
  }

  private static func locationKindForRemoteValue(_ value: String) -> AgentExecutionLocationKind {
    switch trim(value).lowercased() {
    case "phone", "android", "ios":
      return .phone
    case "desktop", "windows", "macos", "linux":
      return .desktop
    case "cloud":
      return .cloud
    case "device", "connected_device":
      return .connectedDevice
    default:
      return .unknown
    }
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let targetSeparator = " \u{00b7} "
}

enum AgentCronExpressionError: LocalizedError, Equatable {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let detail):
      return detail
    }
  }
}

struct AgentCronExpression: Equatable {
  let expression: String
  private let minute: Field
  private let hour: Field
  private let day: Field
  private let month: Field
  private let weekday: Field

  func matches(date: Date, timeZone: TimeZone) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
    let cronWeekday = ((components.weekday ?? 1) - 1) % 7
    let dayMatches = day.values.contains(components.day ?? -1)
    let weekdayMatches = weekday.values.contains(cronWeekday)
    let calendarMatches: Bool
    if day.wildcard && weekday.wildcard {
      calendarMatches = true
    } else if day.wildcard {
      calendarMatches = weekdayMatches
    } else if weekday.wildcard {
      calendarMatches = dayMatches
    } else {
      calendarMatches = dayMatches || weekdayMatches
    }
    return minute.values.contains(components.minute ?? -1) &&
      hour.values.contains(components.hour ?? -1) &&
      month.values.contains(components.month ?? -1) &&
      calendarMatches
  }

  func nextAfter(timestampMillis: Int64, timeZoneIdentifier: String) throws -> Int64 {
    let timeZone = try Self.parseZone(timeZoneIdentifier)
    var candidate = floorToMinute(timestampMillis: timestampMillis, timeZone: timeZone, minuteOffset: 1)
    for _ in 0..<Self.maxScanMinutes {
      if matches(date: candidate, timeZone: timeZone) {
        return Self.millis(candidate)
      }
      candidate = candidate.addingTimeInterval(60)
    }
    throw AgentCronExpressionError.invalid("Cron has no occurrence within six years")
  }

  func previousAtOrBefore(timestampMillis: Int64, timeZoneIdentifier: String) throws -> Int64 {
    let timeZone = try Self.parseZone(timeZoneIdentifier)
    var candidate = floorToMinute(timestampMillis: timestampMillis, timeZone: timeZone, minuteOffset: 0)
    for _ in 0..<Self.maxScanMinutes {
      if matches(date: candidate, timeZone: timeZone) {
        return Self.millis(candidate)
      }
      candidate = candidate.addingTimeInterval(-60)
    }
    throw AgentCronExpressionError.invalid("Cron has no occurrence within six years")
  }

  static func parse(_ expression: String) throws -> AgentCronExpression {
    let parts = expression
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
    guard parts.count == 5 else {
      throw AgentCronExpressionError.invalid("Cron requires five fields")
    }
    return AgentCronExpression(
      expression: parts.joined(separator: " "),
      minute: try parseField(parts[0], minimum: 0, maximum: 59),
      hour: try parseField(parts[1], minimum: 0, maximum: 23),
      day: try parseField(parts[2], minimum: 1, maximum: 31),
      month: try parseField(parts[3], minimum: 1, maximum: 12, aliases: monthNames),
      weekday: try parseField(parts[4], minimum: 0, maximum: 6, aliases: weekdayNames, sundayAlias: true)
    )
  }

  static func parseZone(_ timeZoneIdentifier: String) throws -> TimeZone {
    let clean = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let identifier = clean.isEmpty ? "UTC" : clean
    guard let zone = TimeZone(identifier: identifier) else {
      throw AgentCronExpressionError.invalid("Unknown time zone: \(timeZoneIdentifier)")
    }
    return zone
  }

  private func floorToMinute(timestampMillis: Int64, timeZone: TimeZone, minuteOffset: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = Date(timeIntervalSince1970: Double(timestampMillis) / 1_000)
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    components.second = 0
    components.nanosecond = 0
    let floored = calendar.date(from: components) ?? date
    return calendar.date(byAdding: .minute, value: minuteOffset, to: floored) ?? floored.addingTimeInterval(Double(minuteOffset) * 60)
  }

  private static func parseField(
    _ text: String,
    minimum: Int,
    maximum: Int,
    aliases: [String: Int] = [:],
    sundayAlias: Bool = false
  ) throws -> Field {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !clean.isEmpty else {
      throw AgentCronExpressionError.invalid("Cron field is blank")
    }
    var output = Set<Int>()
    for clause in clean.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
      let parts = clause.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
      let base = parts[0]
      let step: Int
      if parts.count == 2 {
        guard let value = Int(parts[1]) else {
          throw AgentCronExpressionError.invalid("Invalid cron step")
        }
        step = value
      } else {
        step = 1
      }
      guard step > 0 else {
        throw AgentCronExpressionError.invalid("Cron step must be positive")
      }
      let range: ClosedRange<Int>
      if base == "*" {
        range = minimum...maximum
      } else if base.contains("-") {
        let edges = base.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard edges.count == 2 else {
          throw AgentCronExpressionError.invalid("Invalid cron range")
        }
        let lower = try numeric(edges[0], aliases: aliases, sundayAlias: sundayAlias)
        let upper = try numeric(edges[1], aliases: aliases, sundayAlias: sundayAlias)
        guard upper >= lower else {
          throw AgentCronExpressionError.invalid("Cron ranges cannot wrap")
        }
        range = lower...upper
      } else {
        let value = try numeric(base, aliases: aliases, sundayAlias: sundayAlias)
        range = value...value
      }
      guard range.lowerBound >= minimum && range.upperBound <= maximum else {
        throw AgentCronExpressionError.invalid("Cron value is outside \(minimum)..\(maximum)")
      }
      for value in stride(from: range.lowerBound, through: range.upperBound, by: step) {
        output.insert(value)
      }
    }
    guard !output.isEmpty else {
      throw AgentCronExpressionError.invalid("Cron field has no values")
    }
    return Field(values: output, wildcard: clean == "*")
  }

  private static func numeric(
    _ raw: String,
    aliases: [String: Int],
    sundayAlias: Bool
  ) throws -> Int {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let alias = aliases[clean] {
      return alias
    }
    guard let value = Int(clean) else {
      throw AgentCronExpressionError.invalid("Invalid cron token: \(raw)")
    }
    return sundayAlias && value == 7 ? 0 : value
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private struct Field: Equatable {
    var values: Set<Int>
    var wildcard: Bool
  }

  private static let maxScanMinutes = 3_200_000
  private static let monthNames = [
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
  ]
  private static let weekdayNames = [
    "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6
  ]
}

enum AgentInlineStyle: String, Codable, CaseIterable, Identifiable {
  case normal = "NORMAL"
  case bold = "BOLD"
  case italic = "ITALIC"
  case strike = "STRIKE"
  case code = "CODE"
  case link = "LINK"

  var id: String { rawValue }
}

struct AgentInlineSegment: Codable, Equatable {
  var text: String
  var style: AgentInlineStyle
  var url: String

  init(
    text: String,
    style: AgentInlineStyle = .normal,
    url: String = ""
  ) {
    self.text = text
    self.style = style
    self.url = url
  }
}

enum AgentInlineMarkdown {
  static func parse(_ value: String) -> [AgentInlineSegment] {
    guard !value.isEmpty else { return [] }
    var result: [AgentInlineSegment] = []
    var cursor = value.startIndex
    while cursor < value.endIndex {
      let candidates = tokens.compactMap { token in
        firstMatch(pattern: token.pattern, style: token.style, in: value, from: cursor)
      }
      guard let next = candidates.min(by: { $0.range.lowerBound < $1.range.lowerBound }) else {
        result.append(AgentInlineSegment(text: String(value[cursor...])))
        break
      }
      if next.range.lowerBound > cursor {
        result.append(AgentInlineSegment(text: String(value[cursor..<next.range.lowerBound])))
      }
      if next.style == .link, next.groups.count >= 2 {
        result.append(AgentInlineSegment(text: next.groups[0], style: next.style, url: next.groups[1]))
      } else {
        result.append(AgentInlineSegment(text: next.groups.first ?? "", style: next.style))
      }
      cursor = next.range.upperBound
    }
    return result.filter { !$0.text.isEmpty }
  }

  private static func firstMatch(
    pattern: String,
    style: AgentInlineStyle,
    in value: String,
    from cursor: String.Index
  ) -> MatchCandidate? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let searchRange = NSRange(cursor..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, options: [], range: searchRange),
          let range = Range(match.range, in: value) else {
      return nil
    }
    var groups: [String] = []
    for index in 1..<match.numberOfRanges {
      if let groupRange = Range(match.range(at: index), in: value) {
        groups.append(String(value[groupRange]))
      } else {
        groups.append("")
      }
    }
    return MatchCandidate(style: style, range: range, groups: groups)
  }

  private struct Token {
    var style: AgentInlineStyle
    var pattern: String
  }

  private struct MatchCandidate {
    var style: AgentInlineStyle
    var range: Range<String.Index>
    var groups: [String]
  }

  private static let tokens = [
    Token(style: .bold, pattern: #"\*\*([^*\n]+)\*\*"#),
    Token(style: .strike, pattern: #"~~([^~\n]+)~~"#),
    Token(style: .link, pattern: #"\[([^\]\n]+)\]\((https?://[^\)\s]+)\)"#),
    Token(style: .code, pattern: #"`([^`\n]+)`"#),
    Token(style: .italic, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
  ]
}

enum AgentActiveTurnDisposition: String, Codable, CaseIterable, Identifiable {
  case independent = "INDEPENDENT"
  case steer = "STEER"
  case interrupt = "INTERRUPT"

  var id: String { rawValue }
}

enum AgentActiveTurnInterventionKind: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case constraint = "CONSTRAINT"
  case goalChange = "GOAL_CHANGE"
  case interrupt = "INTERRUPT"

  var id: String { rawValue }
}

struct AgentActiveTurnDecision: Codable, Equatable {
  var disposition: AgentActiveTurnDisposition
  var interventionKind: AgentActiveTurnInterventionKind

  init(
    disposition: AgentActiveTurnDisposition,
    interventionKind: AgentActiveTurnInterventionKind = .none
  ) {
    self.disposition = disposition
    self.interventionKind = interventionKind
  }

  var intervenes: Bool {
    disposition != .independent
  }
}

enum AgentActiveTurnPolicy {
  static func decide(
    request: String,
    activeGoal: String,
    hasNewAttachments: Bool = false
  ) -> AgentActiveTurnDecision {
    let clean = normalize(request)
    guard !clean.isEmpty, !activeGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return independent
    }
    if interruptCommands.contains(clean) {
      return AgentActiveTurnDecision(disposition: .interrupt, interventionKind: .interrupt)
    }
    if independentPrefixes.contains(where: clean.hasPrefix) {
      return independent
    }
    if standaloneRequests.contains(where: { regexMatches(pattern: $0, in: clean).first != nil }) {
      return independent
    }
    if continuationPrefixes.contains(where: clean.hasPrefix) {
      return steerDecision(clean)
    }
    if !hasNewAttachments && continuationReferences.contains(where: clean.contains) {
      return steerDecision(clean)
    }
    if !hasNewAttachments &&
      looksLikeFragment(clean) &&
      !distinctiveTokens(clean).intersection(distinctiveTokens(normalize(activeGoal))).isEmpty {
      return steerDecision(clean)
    }
    return independent
  }

  static func supersedingGoal(
    activeGoal: String,
    intervention: String,
    kind: AgentActiveTurnInterventionKind
  ) -> String {
    let original = String(activeGoal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16_000))
    let latest = String(intervention.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
    let label = kind == .goalChange
      ? "The user changed the goal of an in-progress task."
      : "The user added a constraint to an in-progress task."
    return """
    \(label)
    Continue as one task. The latest instruction has priority wherever it conflicts with the original request.

    Original request:
    \(original)

    Latest instruction:
    \(latest)
    """
  }

  private static func steerDecision(_ clean: String) -> AgentActiveTurnDecision {
    AgentActiveTurnDecision(
      disposition: .steer,
      interventionKind: goalChangePrefixes.contains(where: clean.hasPrefix) ? .goalChange : .constraint
    )
  }

  private static func normalize(_ value: String) -> String {
    let punctuationScalars: Set<UnicodeScalar> = [
      "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1a}",
      "\u{ff1b}", "\u{201c}", "\u{201d}", "\u{2018}", "\u{2019}"
    ]
    let mapped = value.lowercased().unicodeScalars.map { scalar -> String in
      if CharacterSet.punctuationCharacters.contains(scalar) || punctuationScalars.contains(scalar) {
        return " "
      }
      return String(scalar)
    }.joined()
    return mapped
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func looksLikeFragment(_ value: String) -> Bool {
    if value.count > 100 { return false }
    if regexMatches(pattern: #"[a-z0-9_+-]+"#, in: value).count > 12 { return false }
    return !standaloneLeads.contains(where: value.hasPrefix)
  }

  private static func distinctiveTokens(_ value: String) -> Set<String> {
    var result = Set(
      regexMatches(pattern: #"[a-z0-9][a-z0-9_+.-]{2,}"#, in: value)
        .filter { !commonWords.contains($0) }
    )
    for sequence in cjkSequences(in: value) {
      guard sequence.count >= 2 else { continue }
      let characters = Array(sequence)
      for index in 0..<(characters.count - 1) {
        result.insert(String(characters[index...index + 1]))
      }
    }
    return result
  }

  private static func regexMatches(pattern: String, in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
  }

  private static func cjkSequences(in value: String) -> [String] {
    var sequences: [String] = []
    var current = ""
    for scalar in value.unicodeScalars {
      if scalar.value >= 0x4e00 && scalar.value <= 0x9fff {
        current.append(Character(scalar))
      } else if !current.isEmpty {
        sequences.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      sequences.append(current)
    }
    return sequences
  }

  private static let independent = AgentActiveTurnDecision(disposition: .independent)
  private static let commonWords: Set<String> = ["the", "and", "for", "with", "this", "that", "please"]
  private static let interruptCommands: Set<String> = [
    "stop", "stop task", "stop this task", "stop the task", "stop current task",
    "stop the current task", "cancel", "cancel task", "cancel this task",
    "cancel the task", "cancel current task", "cancel the current task",
    "abort", "abort task", "interrupt", "interrupt task", "stop working", "stop running",
    "\u{505c}\u{6b62}", "\u{53d6}\u{6d88}", "\u{4e2d}\u{65ad}",
    "\u{505c}\u{6b62}\u{4efb}\u{52a1}", "\u{53d6}\u{6d88}\u{4efb}\u{52a1}",
    "\u{4e2d}\u{65ad}\u{4efb}\u{52a1}", "\u{505c}\u{6b62}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
    "\u{53d6}\u{6d88}\u{5f53}\u{524d}\u{4efb}\u{52a1}", "\u{4e2d}\u{65ad}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
    "\u{5148}\u{505c}\u{4e0b}", "\u{505c}\u{4e0b}\u{6765}",
    "\u{522b}\u{505a}\u{4e86}", "\u{4e0d}\u{7528}\u{7ee7}\u{7eed}\u{4e86}",
    "\u{4e0d}\u{8981}\u{7ee7}\u{7eed}\u{4e86}"
  ]
  private static let independentPrefixes = [
    "new task", "start a new task", "separate task", "another task", "independent task",
    "\u{65b0}\u{4efb}\u{52a1}", "\u{65b0}\u{7684}\u{4efb}\u{52a1}",
    "\u{53e6}\u{4e00}\u{4e2a}\u{4efb}\u{52a1}", "\u{53e6}\u{5916}\u{4e00}\u{4e2a}\u{4efb}\u{52a1}",
    "\u{5355}\u{72ec}\u{4efb}\u{52a1}", "\u{72ec}\u{7acb}\u{4efb}\u{52a1}"
  ]
  private static let standaloneRequests = [
    #"^(reply|respond) exactly\b.*"#,
    #"^(hello|hi|hey)$"#
  ]
  private static let goalChangePrefixes = [
    "change the goal", "change goal", "switch the goal", "replace the task",
    "do this instead", "instead ", "not that", "\u{6539}\u{76ee}\u{6807}",
    "\u{66f4}\u{6362}\u{76ee}\u{6807}", "\u{6362}\u{4e2a}\u{76ee}\u{6807}",
    "\u{6539}\u{6210}", "\u{6539}\u{4e3a}", "\u{6539}\u{505a}",
    "\u{522b}\u{505a}", "\u{4e0d}\u{662f}"
  ]
  private static let continuationPrefixes = [
    "continue", "keep going", "go on", "also", "add ", "additionally",
    "change ", "correct ", "correction", "make sure", "ensure ", "use the previous",
    "use this", "use that", "with that", "based on that", "instead", "remove ",
    "keep ", "retry", "redo", "not that", "do not ", "no ", "wait",
    "\u{7ee7}\u{7eed}", "\u{63a5}\u{7740}", "\u{518d}", "\u{91cd}\u{65b0}",
    "\u{91cd}\u{8bd5}", "\u{66f4}\u{6b63}", "\u{7ea0}\u{6b63}",
    "\u{4fee}\u{6539}", "\u{6539}\u{6210}", "\u{6539}\u{4e3a}",
    "\u{6539}\u{4e00}\u{4e0b}", "\u{8865}\u{5145}", "\u{8ffd}\u{52a0}",
    "\u{53e6}\u{5916}", "\u{8fd8}\u{6709}", "\u{786e}\u{4fdd}",
    "\u{4fdd}\u{8bc1}", "\u{8981}\u{786e}\u{4fdd}", "\u{8981}\u{4fdd}\u{8bc1}",
    "\u{8bf7}\u{786e}\u{4fdd}", "\u{4e0d}\u{8981}", "\u{53bb}\u{6389}",
    "\u{5220}\u{6389}", "\u{4fdd}\u{7559}", "\u{6062}\u{590d}",
    "\u{7528}\u{521a}\u{624d}", "\u{6309}\u{521a}\u{624d}", "\u{6839}\u{636e}\u{521a}\u{624d}",
    "\u{4e0a}\u{9762}", "\u{524d}\u{9762}", "\u{8fd9}\u{4e2a}",
    "\u{8fd9}\u{5f20}", "\u{90a3}\u{4e2a}", "\u{628a}\u{5b83}",
    "\u{4e0d}\u{5bf9}", "\u{4e0d}\u{662f}"
  ]
  private static let continuationReferences = [
    "previous", "above", "earlier", "that", "this", "same", "again",
    "\u{521a}\u{624d}", "\u{4e0a}\u{4e00}\u{4e2a}", "\u{4e0a}\u{4e00}\u{6761}",
    "\u{4e0a}\u{9762}", "\u{524d}\u{9762}", "\u{539f}\u{6765}",
    "\u{8fd9}\u{4e2a}", "\u{8fd9}\u{5f20}", "\u{90a3}\u{4e2a}",
    "\u{5b83}", "\u{540c}\u{4e00}\u{4e2a}", "\u{4e00}\u{6837}"
  ]
  private static let standaloneLeads = [
    "write", "create", "build", "generate", "search", "find", "check", "tell",
    "explain", "summarize", "translate", "open", "run", "set",
    "\u{5199}", "\u{521b}\u{5efa}", "\u{751f}\u{6210}", "\u{67e5}",
    "\u{641c}\u{7d22}", "\u{6253}\u{5f00}", "\u{8fd0}\u{884c}",
    "\u{8bbe}\u{7f6e}", "\u{89e3}\u{91ca}", "\u{603b}\u{7ed3}",
    "\u{7ffb}\u{8bd1}"
  ]
}

enum AgentResponseSelfCheckStatus: String, Codable, CaseIterable, Identifiable {
  case passed = "PASSED"
  case repair = "REPAIR"
  case rejected = "REJECTED"

  var id: String { rawValue }
}

struct AgentResponseSelfCheckResult: Codable, Equatable {
  var status: AgentResponseSelfCheckStatus
  var reasons: [String]
  var requestDigest: String
  var responseDigest: String
  var actionableRequest: Bool
  var hasAttachments: Bool

  var accepted: Bool {
    status == .passed
  }

  var diagnostic: String {
    if accepted {
      return "Final response addresses the latest user request."
    }
    let detail = reasons.isEmpty ? "response_not_verified" : reasons.joined(separator: ", ")
    return "Final response did not pass latest-request self-check: \(detail)"
  }
}

enum AgentResponseSelfCheck {
  static func evaluate(
    latestRequest: String,
    response: String,
    hasAttachments: Bool = false,
    hasOutputArtifacts: Bool = false,
    expectedIdentity: [String: String] = [:],
    responseIdentity: [String: String] = [:]
  ) -> AgentResponseSelfCheckResult {
    let request = String(latestRequest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxRequestLength))
    let reply = String(response.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxResponseLength))
    let actionable = isActionable(request, hasAttachments: hasAttachments)
    var reasons: [String] = []
    let status: AgentResponseSelfCheckStatus

    if !identityMatches(expected: expectedIdentity, actual: responseIdentity) {
      reasons.append("identity_mismatch")
      status = .rejected
    } else if reply.isEmpty && !hasOutputArtifacts {
      reasons.append("empty_response")
      status = .repair
    } else {
      if hasAttachments && regexContains(missingAttachmentPattern, in: reply, caseInsensitive: true) {
        reasons.append("available_attachment_ignored")
      }
      if actionable && regexContains(askForTaskAgainPattern, in: reply, caseInsensitive: true) {
        reasons.append("latest_request_ignored")
      }
      if !hasOutputArtifacts &&
        acknowledgementOnly(reply) &&
        !acknowledgementRequests.contains(normalized(request)) {
        reasons.append("acknowledgement_only")
      }
      if actionable && normalized(reply) == normalized(request) {
        reasons.append("request_echo")
      }
      status = reasons.isEmpty ? .passed : .repair
    }

    return AgentResponseSelfCheckResult(
      status: status,
      reasons: reasons,
      requestDigest: digest(request),
      responseDigest: digest(reply),
      actionableRequest: actionable,
      hasAttachments: hasAttachments
    )
  }

  private static func isActionable(_ request: String, hasAttachments: Bool) -> Bool {
    let clean = normalized(request)
    if clean.isEmpty || genericRequests.contains(clean) {
      return false
    }
    return regexContains(actionTermsPattern, in: request, caseInsensitive: true) ||
      (hasAttachments && clean.split(separator: " ").filter { !$0.isEmpty }.count >= 2)
  }

  private static func acknowledgementOnly(_ response: String) -> Bool {
    let stripped = response.map { char -> String in
      "`*_>#[]()".contains(char) ? " " : String(char)
    }.joined()
    let clean = replaceRegex(pattern: #"\s+"#, in: stripped, with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if ackExact.contains(clean) {
      return true
    }
    if clean.count > 400 || clean.split(separator: " ").count > 60 {
      return false
    }
    return regexContains(ackStartPattern, in: clean, caseInsensitive: true) &&
      regexContains(futureOnlyPattern, in: clean, caseInsensitive: true)
  }

  private static func identityMatches(
    expected: [String: String],
    actual: [String: String]
  ) -> Bool {
    if expected.isEmpty {
      return true
    }
    if actual.isEmpty {
      return false
    }
    for (key, value) in expected {
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        continue
      }
      if actual[key] ?? "" != value {
        return false
      }
    }
    return true
  }

  private static func normalized(_ value: String) -> String {
    replaceRegex(pattern: #"[^\p{L}\p{N}_]+"#, in: value.lowercased(), with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func digest(_ value: String) -> String {
    let hash = Data(SHA256.hash(data: Data(value.utf8)))
    return Data(hash.prefix(8)).hexString()
  }

  private static func regexContains(_ pattern: String, in value: String, caseInsensitive: Bool = false) -> Bool {
    var options: NSRegularExpression.Options = []
    if caseInsensitive {
      options.insert(.caseInsensitive)
    }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return false
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.firstMatch(in: value, options: [], range: range) != nil
  }

  private static func replaceRegex(pattern: String, in value: String, with replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
  }

  private static let maxRequestLength = 16_000
  private static let maxResponseLength = 32_000
  private static let genericRequests: Set<String> = ["attached files", "attached file", "attachment", "file"]
  private static let actionTermsPattern =
    #"\b(?:analy[sz]e|build|calculate|check|compare|convert|create|debug|delete|download|edit|explain|export|extract|find|fix|generate|install|list|make|modify|open|prepare|read|repair|research|review|run|save|search|send|set|show|start|stop|summari[sz]e|test|translate|update|verify|write)\b|"# +
    "(?:\u{5206}\u{6790}|\u{8ba1}\u{7b97}|\u{521b}\u{5efa}|\u{6253}\u{5f00}|\u{5173}\u{95ed}|\u{4fee}\u{590d}|\u{68c0}\u{67e5}|\u{67e5}\u{627e}|\u{641c}\u{7d22}|\u{603b}\u{7ed3}|\u{7ffb}\u{8bd1}|\u{8fd0}\u{884c}|\u{6d4b}\u{8bd5}|\u{5b89}\u{88c5}|\u{751f}\u{6210}|\u{5236}\u{4f5c}|\u{4fee}\u{6539}|\u{7f16}\u{8f91}|\u{5bfc}\u{51fa}|\u{4fdd}\u{5b58}|\u{53d1}\u{9001}|\u{8bbe}\u{7f6e}|\u{8bfb}\u{53d6}|\u{67e5}\u{770b}|\u{5bf9}\u{6bd4}|\u{9a8c}\u{8bc1})"
  private static let ackExact: Set<String> = [
    "got it", "got it.", "ok", "okay", "sure", "understood", "done", "completed",
    "working on it", "i will handle this", "i'll handle this",
    "\u{597d}\u{7684}", "\u{6536}\u{5230}", "\u{660e}\u{767d}",
    "\u{5df2}\u{5b8c}\u{6210}", "\u{5904}\u{7406}\u{597d}\u{4e86}"
  ]
  private static let acknowledgementRequests: Set<String> = [
    "ok", "okay", "thanks", "thank you", "got it",
    "\u{597d}\u{7684}", "\u{8c22}\u{8c22}", "\u{6536}\u{5230}", "\u{660e}\u{767d}"
  ]
  private static let ackStartPattern =
    #"^(?:got it|okay|sure|understood|i(?:'ll| will| am going to)|working on it|starting now|"# +
    "\u{597d}\u{7684}|\u{6536}\u{5230}|\u{660e}\u{767d}|\u{6211}\u{4f1a}|\u{6211}\u{5c06}|\u{9a6c}\u{4e0a}|\u{6b63}\u{5728}|\u{5f00}\u{59cb}\u{5904}\u{7406})"
  private static let futureOnlyPattern =
    #"\b(?:will|going to|working on|starting|handle this|do that)\b|"# +
    "(?:\u{5c06}\u{4f1a}|\u{6211}\u{4f1a}|\u{9a6c}\u{4e0a}|\u{6b63}\u{5728}|\u{5f00}\u{59cb}\u{5904}\u{7406})"
  private static let missingAttachmentPattern =
    #"(?:no|without)\s+(?:an?\s+|any\s+)?(?:attachment|image|file)|"# +
    #"(?:cannot|can't|could not|couldn't)\s+(?:see|find|access)\s+(?:the\s+|an?\s+|any\s+)?(?:attachment|image|file)|"# +
    #"(?:please\s+)?(?:upload|attach|send)\s+(?:the\s+|an?\s+)?(?:attachment|image|file)|"# +
    "(?:\u{6ca1}\u{6709}|\u{672a})\u{6536}\u{5230}(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})|(?:\u{770b}\u{4e0d}\u{5230}|\u{627e}\u{4e0d}\u{5230})(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})|\u{8bf7}(?:\u{4e0a}\u{4f20}|\u{53d1}\u{9001})(?:\u{9644}\u{4ef6}|\u{56fe}\u{7247}|\u{6587}\u{4ef6})"
  private static let askForTaskAgainPattern =
    #"(?:what|which)\s+(?:task|thing)\s+(?:should|would)\s+i|"# +
    #"what\s+would\s+you\s+like\s+me\s+to\s+do|"# +
    #"please\s+(?:provide|tell\s+me)\s+(?:the\s+)?(?:task|request|goal)|"# +
    "(?:\u{8bf7}\u{544a}\u{8bc9}\u{6211}|\u{4f60}\u{60f3}\u{8ba9}\u{6211}|\u{9700}\u{8981}\u{6211})(?:\u{505a}\u{4ec0}\u{4e48}|\u{5b8c}\u{6210}\u{4ec0}\u{4e48}|\u{5904}\u{7406}\u{4ec0}\u{4e48})"
}

enum AgentTaskBudgetProfile: String, Codable, CaseIterable, Identifiable {
  case adaptive
  case fast
  case economy
  case privateMode = "private"
  case custom

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentTaskBudgetProfile {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .adaptive
  }

  var displayName: String {
    switch self {
    case .adaptive: return "Adaptive"
    case .fast: return "Fast"
    case .economy: return "Economy"
    case .privateMode: return "Private"
    case .custom: return "Custom"
    }
  }

  var detail: String {
    switch self {
    case .adaptive:
      return "Broad limits with no fixed task deadline."
    case .fast:
      return "Five-minute execution window with bounded resources."
    case .economy:
      return "Reduce paid usage, tokens, data, and memory."
    case .privateMode:
      return "Use phone, private, and trusted paired resources only."
    case .custom:
      return "Use the limits configured below."
    }
  }
}

enum AgentConfirmationTier: String, Codable, CaseIterable, Identifiable {
  case direct = "DIRECT"
  case confirmOnce = "CONFIRM_ONCE"
  case confirmAlways = "CONFIRM_ALWAYS"

  var id: String { rawValue }
}

struct AgentAction: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentActionKind
  var target: String
  var risk: AgentRisk
  var status: AgentActionStatus
  var description: String
  var parameters: [String: String]
  var requiresConfirmation: Bool
  var result: String
  var evidence: String

  init(
    id: String,
    kind: AgentActionKind,
    target: String,
    risk: AgentRisk,
    status: AgentActionStatus,
    description: String,
    parameters: [String: String] = [:],
    requiresConfirmation: Bool = true,
    result: String = "",
    evidence: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.target = target
    self.risk = risk
    self.status = status
    self.description = description
    self.parameters = parameters
    self.requiresConfirmation = requiresConfirmation
    self.result = result
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case target
    case risk
    case status
    case description
    case parameters
    case requiresConfirmation = "requires_confirmation"
    case result
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      kind: try container.decodeIfPresent(AgentActionKind.self, forKey: .kind) ?? .draftPlan,
      target: try container.decodeIfPresent(String.self, forKey: .target) ?? "",
      risk: try container.decodeIfPresent(AgentRisk.self, forKey: .risk) ?? .medium,
      status: try container.decodeIfPresent(AgentActionStatus.self, forKey: .status) ?? .pendingConfirmation,
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
      parameters: try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:],
      requiresConfirmation: try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? true,
      result: try container.decodeIfPresent(String.self, forKey: .result) ?? "",
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    )
  }
}

enum AgentConfirmationPolicy {
  static func tier(for action: AgentAction) -> AgentConfirmationTier {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if toolId == homeAssistantServiceCall && requiresAlwaysHomeAssistantConfirmation(action.parameters["input_json"] ?? "") {
      return .confirmAlways
    }
    if alwaysConfirmNativeToolIds.contains(toolId) {
      return .confirmAlways
    }
    if confirmOnceNativeToolIds.contains(toolId) {
      return .confirmOnce
    }
    if desktopRemoteNativeToolIds.contains(toolId) {
      return .direct
    }
    if toolId == webSearch || webIntelligenceToolIds.contains(toolId) {
      return .direct
    }
    if alwaysConfirmKinds.contains(action.kind) || alwaysConfirmTerms.contains(where: value.contains) {
      return .confirmAlways
    }
    if action.kind == .callConnector {
      return .direct
    }
    if confirmOnceTerms.contains(where: value.contains) || action.kind == .controlDevice {
      return .confirmOnce
    }
    if action.kind == .setAlarm ||
      action.kind == .openApp ||
      directActionIds.contains(action.id) ||
      directNativeToolIds.contains(toolId) ||
      directTerms.contains(where: value.contains) {
      return .direct
    }
    switch action.risk {
    case .low:
      return .direct
    case .medium:
      return .confirmOnce
    case .high, .blocked:
      return .confirmAlways
    }
  }

  static func consentKey(for action: AgentAction) -> String {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if locationTerms.contains(where: value.contains) {
      return "location"
    }
    if microphoneTerms.contains(where: value.contains) {
      return "microphone"
    }
    if downloadTerms.contains(where: value.contains) {
      return "downloads"
    }
    if contactWriteTerms.contains(where: value.contains) {
      return "contacts_write"
    }
    if calendarWriteTerms.contains(where: value.contains) {
      return "calendar_write"
    }
    if toolId == bluetoothDiscoveryForeground {
      return "bluetooth_discovery"
    }
    if toolId == wifiScanStart {
      return "wifi_scan"
    }
    if toolId == installedAppsList || toolId == packageDetail {
      return "installed_apps_read"
    }
    if toolId == homeAssistantEntitiesList || toolId == homeAssistantEntityRead {
      return "home_assistant_read"
    }
    if toolId == homeAssistantServiceCall {
      return homeAssistantConsentScope(action.parameters["input_json"] ?? "")
    }
    if action.kind == .controlDevice {
      return "device_control:\(action.target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    return "action:\(action.kind.rawValue.lowercased()):\(action.id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private static func nativeToolId(_ action: AgentAction) -> String {
    action.parameters["tool_id"] ?? ""
  }

  private static func searchableValue(_ action: AgentAction) -> String {
    var parts = [action.id, action.kind.rawValue, action.target, action.description]
    for (key, value) in action.parameters where !key.hasPrefix(internalParameterPrefix) {
      parts.append(key)
      parts.append(value)
    }
    return parts.joined(separator: " ").lowercased()
  }

  private static func requiresAlwaysHomeAssistantConfirmation(_ inputJson: String) -> Bool {
    let input = homeAssistantInput(inputJson)
    let cleanEntity = input.entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let entityDomain = cleanEntity.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    let identity = "\(cleanEntity) \(input.serviceDomain.lowercased()) \(input.service.lowercased())"
    return homeAssistantAlwaysConfirmDomains.contains(entityDomain) ||
      homeAssistantAlwaysConfirmServices.contains(input.service.lowercased()) ||
      homeAssistantAlwaysConfirmIdentityTerms.contains(where: identity.contains)
  }

  private static func homeAssistantConsentScope(_ inputJson: String) -> String {
    let entityId = homeAssistantInput(inputJson).entityId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if entityId.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil {
      return "home_assistant_control:\(entityId)"
    }
    return "home_assistant_control"
  }

  private static func homeAssistantInput(_ inputJson: String) -> (entityId: String, serviceDomain: String, service: String) {
    guard let data = inputJson.data(using: .utf8),
          let rawObject = try? JSONSerialization.jsonObject(with: data),
          let object = rawObject as? [String: Any] else {
      return ("", "", "")
    }
    return (
      object["entity_id"] as? String ?? "",
      object["service_domain"] as? String ?? "",
      object["service"] as? String ?? ""
    )
  }

  private static let internalParameterPrefix = "_signalasi_"
  private static let homeAssistantServiceCall = "signalasi.home_assistant.service.call"
  private static let homeAssistantEntitiesList = "signalasi.home_assistant.entities.list"
  private static let homeAssistantEntityRead = "signalasi.home_assistant.entity.read"
  private static let bluetoothDiscoveryForeground = "signalasi.hardware.bluetooth.discovery.foreground"
  private static let installedAppsList = "signalasi.hardware.apps.installed.list"
  private static let packageDetail = "signalasi.hardware.apps.package.detail"
  private static let wifiScanStart = "signalasi.android.wifi.scan.start"
  private static let webSearch = "web.search"

  private static let alwaysConfirmKinds: Set<AgentActionKind> = [.replyNotification, .deleteText, .lockScreen]
  private static let directActionIds: Set<String> = [
    "set-timer", "open-timer", "set-alarm", "open-camera", "open-flashlight",
    "battery-status", "device-status"
  ]
  private static let desktopRemoteNativeToolIds: Set<String> = [
    "signalasi.desktop.windows.system.status",
    "signalasi.desktop.windows.process.list",
    "signalasi.desktop.workspace.file.list",
    "signalasi.desktop.workspace.file.read.text",
    "signalasi.desktop.workspace.file.write.text",
    "signalasi.desktop.workspace.file.sha256",
    "signalasi.desktop.workspace.archive.create",
    "signalasi.desktop.terminal.run",
    "signalasi.desktop.office.document.inspect",
    "signalasi.desktop.office.document.convert"
  ]
  private static let webIntelligenceToolIds: Set<String> = [
    "signalasi.web.intelligence.search",
    "signalasi.web.intelligence.fetch",
    "signalasi.web.intelligence.crawl",
    "signalasi.web.intelligence.extract",
    "signalasi.web.intelligence.cache",
    "signalasi.web.intelligence.find_similar",
    "signalasi.web.intelligence.research",
    "signalasi.web.intelligence.agent",
    "signalasi.web.intelligence.diff",
    "signalasi.web.intelligence.watch"
  ]
  private static let directNativeToolIds = Set([
    "signalasi.hardware.battery.status",
    "signalasi.hardware.power.status",
    "signalasi.hardware.storage.status",
    "signalasi.hardware.network.status",
    "signalasi.hardware.sensors.list",
    "signalasi.hardware.sensor.sample",
    "signalasi.hardware.bluetooth.status",
    "signalasi.hardware.nfc.status",
    "signalasi.hardware.flashlight.set",
    "signalasi.camera.capture.visible",
    "web.search",
    "signalasi.media.ffmpeg.transcode",
    "signalasi.runtime.execute",
    "signalasi.hardware.bluetooth.pairing.handoff",
    "signalasi.android.audio.status",
    "signalasi.android.audio.volume.set",
    "signalasi.android.audio.mute.set",
    "signalasi.android.wifi.panel.open",
    "signalasi.android.wifi.hotspot.panel.open",
    "signalasi.android.biometric.enrollment.open"
  ]).union(webIntelligenceToolIds)
  private static let confirmOnceNativeToolIds: Set<String> = [
    "signalasi.microphone.record.visible",
    "signalasi.notifications.list",
    bluetoothDiscoveryForeground,
    installedAppsList,
    packageDetail,
    wifiScanStart,
    "signalasi.runtime.packs.install",
    homeAssistantEntitiesList,
    homeAssistantEntityRead,
    homeAssistantServiceCall
  ]
  private static let alwaysConfirmNativeToolIds: Set<String> = [
    "signalasi.notifications.reply"
  ]

  private static let alwaysConfirmTerms = [
    "send sms", "sms.send", "reply sms", "send message", "reply message", "reply notification",
    "send email", "reply email", "phone call", "dial", "telephony.dial", "delete", "remove",
    "install", "uninstall", "payment", "purchase", "checkout", "transfer", "grant permission",
    "authorize", "security setting", "screen lock", "lock device", "device_policy.lock", "reboot",
    "door lock", "smart lock", "garage door", "alarm panel", "private key", "password",
    "\u{53D1}\u{9001}\u{77ED}\u{4FE1}", "\u{56DE}\u{590D}\u{77ED}\u{4FE1}",
    "\u{53D1}\u{6D88}\u{606F}", "\u{56DE}\u{590D}\u{6D88}\u{606F}",
    "\u{6253}\u{7535}\u{8BDD}", "\u{62E8}\u{53F7}", "\u{5220}\u{9664}",
    "\u{5B89}\u{88C5}", "\u{5378}\u{8F7D}", "\u{652F}\u{4ED8}",
    "\u{8F6C}\u{8D26}", "\u{6388}\u{6743}", "\u{6743}\u{9650}",
    "\u{5B89}\u{5168}\u{8BBE}\u{7F6E}", "\u{9501}\u{5C4F}",
    "\u{91CD}\u{542F}", "\u{95E8}\u{9501}", "\u{8F66}\u{5E93}\u{95E8}"
  ]
  private static let directTerms = [
    "timer", "alarm clock", "set alarm", "camera capture", "take photo", "flashlight", "torch",
    "audio volume", "set volume", "audio mute", "open app", "launch app", "battery status",
    "device status", "read battery", "read device", "\u{8BA1}\u{65F6}\u{5668}",
    "\u{95F9}\u{949F}", "\u{62CD}\u{7167}", "\u{624B}\u{7535}\u{7B52}",
    "\u{97F3}\u{91CF}", "\u{6253}\u{5F00}app", "\u{6253}\u{5F00} app",
    "\u{7535}\u{91CF}", "\u{8BBE}\u{5907}\u{72B6}\u{6001}"
  ]
  private static let locationTerms = ["location", "gps", "\u{5B9A}\u{4F4D}", "\u{4F4D}\u{7F6E}"]
  private static let microphoneTerms = ["microphone", "record audio", "\u{9EA6}\u{514B}\u{98CE}", "\u{5F55}\u{97F3}"]
  private static let downloadTerms = ["download", "\u{4E0B}\u{8F7D}"]
  private static let contactWriteTerms = [
    "contacts.write", "contact upsert", "create contact", "update contact",
    "\u{65B0}\u{5EFA}\u{8054}\u{7CFB}\u{4EBA}", "\u{4FEE}\u{6539}\u{8054}\u{7CFB}\u{4EBA}",
    "\u{66F4}\u{65B0}\u{8054}\u{7CFB}\u{4EBA}"
  ]
  private static let calendarWriteTerms = [
    "calendar.write", "calendar event upsert", "create calendar event", "update calendar event",
    "\u{65B0}\u{5EFA}\u{65E5}\u{7A0B}", "\u{4FEE}\u{6539}\u{65E5}\u{7A0B}",
    "\u{66F4}\u{65B0}\u{65E5}\u{7A0B}"
  ]
  private static let confirmOnceTerms = locationTerms + microphoneTerms + downloadTerms + contactWriteTerms + calendarWriteTerms
  private static let homeAssistantAlwaysConfirmDomains: Set<String> = [
    "alarm_control_panel", "automation", "camera", "lock", "script", "siren", "valve"
  ]
  private static let homeAssistantAlwaysConfirmServices: Set<String> = [
    "alarm_arm_away", "alarm_arm_home", "alarm_arm_night", "alarm_disarm", "alarm_trigger", "unlock"
  ]
  private static let homeAssistantAlwaysConfirmIdentityTerms = [
    "alarm", "door", "gate", "garage", "lock", "security", "siren"
  ]
}

enum AgentClarificationMode: String, Codable, CaseIterable, Identifiable {
  case execute = "EXECUTE"
  case askLocally = "ASK_LOCALLY"
  case askWithModel = "ASK_WITH_MODEL"

  var id: String { rawValue }
}

enum AgentClarificationQuestion: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case taskGoal = "TASK_GOAL"
  case codeOutcome = "CODE_OUTCOME"
  case controlAction = "CONTROL_ACTION"
  case researchTopic = "RESEARCH_TOPIC"
  case fileAction = "FILE_ACTION"
  case memoryContent = "MEMORY_CONTENT"
  case automationDetails = "AUTOMATION_DETAILS"

  var id: String { rawValue }
}

struct AgentClarificationDecision: Codable, Equatable {
  var mode: AgentClarificationMode
  var question: AgentClarificationQuestion

  init(
    mode: AgentClarificationMode,
    question: AgentClarificationQuestion = .none
  ) {
    self.mode = mode
    self.question = question
  }

  var shouldAsk: Bool {
    mode != .execute
  }
}

enum AgentClarificationPolicy {
  static func decide(
    goal: String,
    hasAttachments: Bool = false,
    hasConversationContext: Bool = false
  ) -> AgentClarificationDecision {
    let normalized = normalize(goal)
    if normalized.isEmpty {
      if hasAttachments {
        return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
      }
      return ask(.taskGoal)
    }
    if hasConversationContext && isContextualFollowUp(normalized) {
      return execute
    }
    if hasAttachments && vagueRequests.contains(normalized) {
      return AgentClarificationDecision(mode: .askWithModel, question: .fileAction)
    }
    if vagueRequests.contains(normalized) {
      return hasConversationContext ? execute : ask(.taskGoal)
    }
    if isQuestion(normalized) || greetings.contains(normalized) {
      return execute
    }

    let missingQuestion: AgentClarificationQuestion?
    if codeRequestsWithoutOutcome.contains(normalized) {
      missingQuestion = .codeOutcome
    } else if controlRequestsWithoutAction.contains(normalized) {
      missingQuestion = .controlAction
    } else if researchRequestsWithoutTopic.contains(normalized) {
      missingQuestion = .researchTopic
    } else if fileRequestsWithoutAction.contains(normalized) {
      missingQuestion = .fileAction
    } else if memoryRequestsWithoutContent.contains(normalized) {
      missingQuestion = .memoryContent
    } else if automationRequestsWithoutDetails.contains(normalized) {
      missingQuestion = .automationDetails
    } else {
      missingQuestion = nil
    }
    if let missingQuestion = missingQuestion, !hasConversationContext {
      return ask(missingQuestion)
    }
    return execute
  }

  private static func ask(_ question: AgentClarificationQuestion) -> AgentClarificationDecision {
    AgentClarificationDecision(mode: .askLocally, question: question)
  }

  private static func normalize(_ value: String) -> String {
    let punctuationScalars: Set<UnicodeScalar> = [
      "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1a}",
      "\u{ff1b}", "\u{201c}", "\u{201d}", "\u{2018}", "\u{2019}"
    ]
    let mapped = value.lowercased().unicodeScalars.map { scalar -> String in
      if CharacterSet.punctuationCharacters.contains(scalar) || punctuationScalars.contains(scalar) {
        return " "
      }
      return String(scalar)
    }.joined()
    return mapped
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isQuestion(_ value: String) -> Bool {
    questionPrefixes.contains(where: value.hasPrefix) ||
      questionSuffixes.contains(where: value.hasSuffix)
  }

  private static func isContextualFollowUp(_ value: String) -> Bool {
    contextualFollowUps.contains(value) ||
      contextualReferences.contains(where: value.contains)
  }

  private static let execute = AgentClarificationDecision(mode: .execute)
  private static let greetings: Set<String> = [
    "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
    "\u{4f60}\u{597d}", "\u{55e8}", "\u{65e9}\u{4e0a}\u{597d}",
    "\u{4e0b}\u{5348}\u{597d}", "\u{665a}\u{4e0a}\u{597d}"
  ]
  private static let questionPrefixes: Set<String> = [
    "what ", "why ", "how ", "when ", "where ", "which ", "who ",
    "can ", "could ", "would ", "is ", "are ", "do ", "does ",
    "\u{4ec0}\u{4e48}", "\u{4e3a}\u{4ec0}\u{4e48}", "\u{600e}\u{4e48}",
    "\u{5982}\u{4f55}", "\u{54ea}\u{4e2a}", "\u{54ea}\u{4e9b}",
    "\u{8c01}", "\u{80fd}\u{4e0d}\u{80fd}", "\u{53ef}\u{4ee5}"
  ]
  private static let questionSuffixes: Set<String> = [
    "\u{5417}", "\u{5462}", "\u{4e48}", "\u{600e}\u{4e48}\u{6837}",
    "\u{5982}\u{4f55}"
  ]
  private static let contextualFollowUps: Set<String> = [
    "continue", "go ahead", "do it", "try again", "retry", "keep going",
    "use this", "use that", "same as before", "make it better",
    "\u{7ee7}\u{7eed}", "\u{6267}\u{884c}", "\u{5c31}\u{8fd9}\u{6837}",
    "\u{6309}\u{8fd9}\u{4e2a}", "\u{518d}\u{8bd5}\u{8bd5}",
    "\u{91cd}\u{8bd5}", "\u{4fdd}\u{8bc1}\u{6b63}\u{786e}",
    "\u{7528}\u{8fd9}\u{4e2a}", "\u{548c}\u{4e4b}\u{524d}\u{4e00}\u{6837}",
    "\u{6309}\u{4e0a}\u{9762}\u{7684}\u{505a}"
  ]
  private static let contextualReferences: Set<String> = [
    " this", " that", " it", " above", " previous",
    "\u{8fd9}\u{4e2a}", "\u{90a3}\u{4e2a}", "\u{5b83}",
    "\u{4e0a}\u{9762}", "\u{4e4b}\u{524d}", "\u{521a}\u{624d}",
    "\u{524d}\u{9762}", "\u{8be5}\u{6587}\u{4ef6}", "\u{8fd9}\u{5f20}\u{56fe}"
  ]
  private static let vagueRequests: Set<String> = [
    "help me", "handle this", "do something", "take a look", "fix it",
    "improve it", "optimize it", "work on this", "please help",
    "\u{5e2e}\u{6211}", "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
    "\u{5904}\u{7406}\u{4e00}\u{4e0b}", "\u{5f04}\u{4e00}\u{4e0b}",
    "\u{770b}\u{770b}", "\u{5e2e}\u{6211}\u{770b}\u{770b}",
    "\u{4fee}\u{4e00}\u{4e0b}", "\u{4f18}\u{5316}\u{4e00}\u{4e0b}",
    "\u{6539}\u{8fdb}\u{4e00}\u{4e0b}", "\u{4f60}\u{770b}\u{7740}\u{529e}",
    "\u{7ed9}\u{6211}\u{7ed3}\u{679c}", "\u{5feb}\u{70b9}",
    "\u{4e0d}\u{884c}"
  ]
  private static let codeRequestsWithoutOutcome: Set<String> = [
    "write code", "write a program", "build an app", "create an app", "fix the code",
    "\u{5199}\u{4ee3}\u{7801}", "\u{5199}\u{4e2a}\u{7a0b}\u{5e8f}",
    "\u{5f00}\u{53d1}\u{4e00}\u{4e2a} app", "\u{505a}\u{4e00}\u{4e2a} app",
    "\u{4fee}\u{4ee3}\u{7801}"
  ]
  private static let controlRequestsWithoutAction: Set<String> = [
    "control my phone", "control the phone", "control my computer",
    "control the computer", "remote desktop",
    "\u{63a7}\u{5236}\u{624b}\u{673a}", "\u{64cd}\u{4f5c}\u{624b}\u{673a}",
    "\u{63a7}\u{5236}\u{7535}\u{8111}", "\u{64cd}\u{4f5c}\u{7535}\u{8111}",
    "\u{8fdc}\u{7a0b}\u{684c}\u{9762}"
  ]
  private static let researchRequestsWithoutTopic: Set<String> = [
    "research", "research this", "search", "search the web", "look it up",
    "\u{7814}\u{7a76}\u{4e00}\u{4e0b}", "\u{641c}\u{7d22}",
    "\u{641c}\u{4e00}\u{4e0b}", "\u{67e5}\u{4e00}\u{4e0b}",
    "\u{67e5}\u{8d44}\u{6599}"
  ]
  private static let fileRequestsWithoutAction: Set<String> = [
    "process the file", "handle the file", "work on the document",
    "\u{5904}\u{7406}\u{6587}\u{4ef6}", "\u{5904}\u{7406}\u{8fd9}\u{4e2a}\u{6587}\u{4ef6}",
    "\u{770b}\u{4e0b}\u{6587}\u{4ef6}"
  ]
  private static let memoryRequestsWithoutContent: Set<String> = [
    "remember this", "remember that", "save this to memory",
    "\u{8bb0}\u{4f4f}\u{8fd9}\u{4e2a}", "\u{8bb0}\u{4f4f}\u{8fd9}\u{4ef6}\u{4e8b}",
    "\u{5b58}\u{5230}\u{8bb0}\u{5fc6}"
  ]
  private static let automationRequestsWithoutDetails: Set<String> = [
    "create an automation", "make a workflow", "schedule a task", "remind me",
    "\u{521b}\u{5efa}\u{81ea}\u{52a8}\u{5316}", "\u{5efa}\u{4e00}\u{4e2a}\u{5de5}\u{4f5c}\u{6d41}",
    "\u{8bbe}\u{7f6e}\u{5b9a}\u{65f6}\u{4efb}\u{52a1}", "\u{63d0}\u{9192}\u{6211}"
  ]
}

enum AgentTaskBudgetProfile: String, Codable, CaseIterable, Identifiable {
  case adaptive
  case fast
  case economy
  case privateMode = "private"
  case custom

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentTaskBudgetProfile {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .adaptive
  }

  var displayName: String {
    switch self {
    case .adaptive: return "Adaptive"
    case .fast: return "Fast"
    case .economy: return "Economy"
    case .privateMode: return "Private"
    case .custom: return "Custom"
    }
  }

  var detail: String {
    switch self {
    case .adaptive:
      return "Broad limits with no fixed task deadline."
    case .fast:
      return "Five-minute execution window with bounded resources."
    case .economy:
      return "Reduce paid usage, tokens, data, and memory."
    case .privateMode:
      return "Use phone, private, and trusted paired resources only."
    case .custom:
      return "Use the limits configured below."
    }
  }
}

enum AgentTaskNetworkPolicy: String, Codable, CaseIterable, Identifiable {
  case any
  case unmeteredOnly = "unmetered_only"
  case trustedOnly = "trusted_only"
  case offlineOnly = "offline_only"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentTaskNetworkPolicy {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .any
  }

  var displayName: String {
    switch self {
    case .any: return "Any Available Network"
    case .unmeteredOnly: return "Unmetered Only"
    case .trustedOnly: return "Trusted and Private Only"
    case .offlineOnly: return "Offline Only"
    }
  }
}

struct AgentTaskBudget: Codable, Equatable {
  static let mib: Int64 = 1_048_576
  static let gib: Int64 = 1_073_741_824
  static let maximumElapsedSeconds: Int64 = 7 * 24 * 60 * 60
  static let maximumCostMicros: Int64 = 1_000_000_000
  static let maximumTokens: Int64 = 10_000_000
  static let maximumNetworkBytes: Int64 = 10 * gib
  static let maximumMemoryBytes: Int64 = 16 * gib

  var profile: AgentTaskBudgetProfile
  var maxElapsedSeconds: Int64
  var maxCostMicros: Int64
  var maxInputTokens: Int64
  var maxOutputTokens: Int64
  var maxNetworkBytes: Int64
  var minimumBatteryPercent: Int
  var maxMemoryBytes: Int64
  var networkPolicy: AgentTaskNetworkPolicy
  var allowCloud: Bool
  var allowPaidProviders: Bool

  init(
    profile: AgentTaskBudgetProfile = .adaptive,
    maxElapsedSeconds: Int64 = 0,
    maxCostMicros: Int64 = 5_000_000,
    maxInputTokens: Int64 = 1_000_000,
    maxOutputTokens: Int64 = 256_000,
    maxNetworkBytes: Int64 = 256 * AgentTaskBudget.mib,
    minimumBatteryPercent: Int = 5,
    maxMemoryBytes: Int64 = 0,
    networkPolicy: AgentTaskNetworkPolicy = .any,
    allowCloud: Bool = true,
    allowPaidProviders: Bool = true
  ) {
    self.profile = profile
    self.maxElapsedSeconds = maxElapsedSeconds
    self.maxCostMicros = maxCostMicros
    self.maxInputTokens = maxInputTokens
    self.maxOutputTokens = maxOutputTokens
    self.maxNetworkBytes = maxNetworkBytes
    self.minimumBatteryPercent = minimumBatteryPercent
    self.maxMemoryBytes = maxMemoryBytes
    self.networkPolicy = networkPolicy
    self.allowCloud = allowCloud
    self.allowPaidProviders = allowPaidProviders
  }

  static let `default` = AgentTaskBudget.forProfile(.adaptive)

  static func forProfile(_ profile: AgentTaskBudgetProfile) -> AgentTaskBudget {
    switch profile {
    case .adaptive:
      return AgentTaskBudget(profile: profile)
    case .fast:
      return AgentTaskBudget(
        profile: profile,
        maxElapsedSeconds: 5 * 60,
        maxCostMicros: 2_000_000,
        maxInputTokens: 256_000,
        maxOutputTokens: 64_000,
        maxNetworkBytes: 128 * mib,
        minimumBatteryPercent: 10,
        maxMemoryBytes: 1_536 * mib
      )
    case .economy:
      return AgentTaskBudget(
        profile: profile,
        maxCostMicros: 250_000,
        maxInputTokens: 64_000,
        maxOutputTokens: 16_000,
        maxNetworkBytes: 32 * mib,
        minimumBatteryPercent: 15,
        maxMemoryBytes: 768 * mib
      )
    case .privateMode:
      return AgentTaskBudget(
        profile: profile,
        maxInputTokens: 128_000,
        maxOutputTokens: 32_000,
        maxNetworkBytes: 64 * mib,
        minimumBatteryPercent: 10,
        maxMemoryBytes: 1_024 * mib,
        networkPolicy: .trustedOnly,
        allowCloud: false,
        allowPaidProviders: false
      )
    case .custom:
      return AgentTaskBudget(profile: .custom)
    }
  }

  var normalized: AgentTaskBudget {
    AgentTaskBudget(
      profile: profile,
      maxElapsedSeconds: max(0, min(maxElapsedSeconds, Self.maximumElapsedSeconds)),
      maxCostMicros: max(0, min(maxCostMicros, Self.maximumCostMicros)),
      maxInputTokens: max(0, min(maxInputTokens, Self.maximumTokens)),
      maxOutputTokens: max(0, min(maxOutputTokens, Self.maximumTokens)),
      maxNetworkBytes: max(0, min(maxNetworkBytes, Self.maximumNetworkBytes)),
      minimumBatteryPercent: max(0, min(minimumBatteryPercent, 100)),
      maxMemoryBytes: max(0, min(maxMemoryBytes, Self.maximumMemoryBytes)),
      networkPolicy: networkPolicy,
      allowCloud: allowCloud,
      allowPaidProviders: allowPaidProviders
    )
  }

  enum CodingKeys: String, CodingKey {
    case version
    case profile
    case maxElapsedSeconds = "max_elapsed_seconds"
    case maxCostMicros = "max_cost_micros"
    case maxInputTokens = "max_input_tokens"
    case maxOutputTokens = "max_output_tokens"
    case maxNetworkBytes = "max_network_bytes"
    case minimumBatteryPercent = "minimum_battery_percent"
    case maxMemoryBytes = "max_memory_bytes"
    case networkPolicy = "network_policy"
    case allowCloud = "allow_cloud"
    case allowPaidProviders = "allow_paid_providers"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let profile = AgentTaskBudgetProfile.fromWireValue(try container.decodeIfPresent(String.self, forKey: .profile))
    let fallback = Self.forProfile(profile)
    self = AgentTaskBudget(
      profile: profile,
      maxElapsedSeconds: try container.decodeIfPresent(Int64.self, forKey: .maxElapsedSeconds) ?? fallback.maxElapsedSeconds,
      maxCostMicros: try container.decodeIfPresent(Int64.self, forKey: .maxCostMicros) ?? fallback.maxCostMicros,
      maxInputTokens: try container.decodeIfPresent(Int64.self, forKey: .maxInputTokens) ?? fallback.maxInputTokens,
      maxOutputTokens: try container.decodeIfPresent(Int64.self, forKey: .maxOutputTokens) ?? fallback.maxOutputTokens,
      maxNetworkBytes: try container.decodeIfPresent(Int64.self, forKey: .maxNetworkBytes) ?? fallback.maxNetworkBytes,
      minimumBatteryPercent: try container.decodeIfPresent(Int.self, forKey: .minimumBatteryPercent) ?? fallback.minimumBatteryPercent,
      maxMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .maxMemoryBytes) ?? fallback.maxMemoryBytes,
      networkPolicy: AgentTaskNetworkPolicy.fromWireValue(
        try container.decodeIfPresent(String.self, forKey: .networkPolicy) ?? fallback.networkPolicy.rawValue
      ),
      allowCloud: try container.decodeIfPresent(Bool.self, forKey: .allowCloud) ?? fallback.allowCloud,
      allowPaidProviders: try container.decodeIfPresent(Bool.self, forKey: .allowPaidProviders) ?? fallback.allowPaidProviders
    ).normalized
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(value.profile.rawValue, forKey: .profile)
    try container.encode(value.maxElapsedSeconds, forKey: .maxElapsedSeconds)
    try container.encode(value.maxCostMicros, forKey: .maxCostMicros)
    try container.encode(value.maxInputTokens, forKey: .maxInputTokens)
    try container.encode(value.maxOutputTokens, forKey: .maxOutputTokens)
    try container.encode(value.maxNetworkBytes, forKey: .maxNetworkBytes)
    try container.encode(value.minimumBatteryPercent, forKey: .minimumBatteryPercent)
    try container.encode(value.maxMemoryBytes, forKey: .maxMemoryBytes)
    try container.encode(value.networkPolicy.rawValue, forKey: .networkPolicy)
    try container.encode(value.allowCloud, forKey: .allowCloud)
    try container.encode(value.allowPaidProviders, forKey: .allowPaidProviders)
  }
}

struct AgentTaskBudgetUsage: Codable, Equatable {
  var elapsedMillis: Int64 = 0
  var inputTokens: Int64 = 0
  var outputTokens: Int64 = 0
  var costMicros: Int64 = 0
  var networkBytes: Int64 = 0
  var peakMemoryBytes: Int64 = 0
  var usageEstimated: Bool = false

  enum CodingKeys: String, CodingKey {
    case elapsedMillis = "elapsed_ms"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case costMicros = "cost_micros"
    case networkBytes = "network_bytes"
    case peakMemoryBytes = "peak_memory_bytes"
    case usageEstimated = "usage_estimated"
  }

  init(
    elapsedMillis: Int64 = 0,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0,
    networkBytes: Int64 = 0,
    peakMemoryBytes: Int64 = 0,
    usageEstimated: Bool = false
  ) {
    self.elapsedMillis = max(0, elapsedMillis)
    self.inputTokens = max(0, inputTokens)
    self.outputTokens = max(0, outputTokens)
    self.costMicros = max(0, costMicros)
    self.networkBytes = max(0, networkBytes)
    self.peakMemoryBytes = max(0, peakMemoryBytes)
    self.usageEstimated = usageEstimated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      elapsedMillis: try container.decodeIfPresent(Int64.self, forKey: .elapsedMillis) ?? 0,
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
      costMicros: try container.decodeIfPresent(Int64.self, forKey: .costMicros) ?? 0,
      networkBytes: try container.decodeIfPresent(Int64.self, forKey: .networkBytes) ?? 0,
      peakMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes) ?? 0,
      usageEstimated: try container.decodeIfPresent(Bool.self, forKey: .usageEstimated) ?? false
    )
  }
}

struct AgentTaskBudgetEnvironment: Equatable {
  var batteryPercent: Int = -1
  var charging: Bool = false
  var networkAvailable: Bool = false
  var networkMetered: Bool = false
  var appMemoryBytes: Int64 = 0
  var availableMemoryBytes: Int64 = 0
}

enum AgentTaskBudgetLimit: String, Equatable {
  case time
  case cost
  case inputTokens = "input_tokens"
  case outputTokens = "output_tokens"
  case network
  case battery
  case memory
  case cloud
  case paidProvider = "paid_provider"
}

struct AgentTaskBudgetDecision: Equatable {
  var allowed: Bool
  var limit: AgentTaskBudgetLimit?
  var reason: String

  static let approved = AgentTaskBudgetDecision(allowed: true, limit: nil, reason: "")
}

enum AgentTaskBudgetPolicy {
  static func evaluate(
    budget: AgentTaskBudget,
    usage: AgentTaskBudgetUsage,
    environment: AgentTaskBudgetEnvironment = AgentTaskBudgetEnvironment(),
    networkRequired: Bool = false,
    trustedNetworkTarget: Bool = false,
    cloudProvider: Bool = false,
    paidProvider: Bool = false
  ) -> AgentTaskBudgetDecision {
    let limits = budget.normalized
    if limits.maxElapsedSeconds > 0 && usage.elapsedMillis > limits.maxElapsedSeconds * 1_000 {
      return denied(.time, "Task time budget exhausted")
    }
    if limits.maxCostMicros > 0 && usage.costMicros > limits.maxCostMicros {
      return denied(.cost, "Task cost budget exhausted")
    }
    if limits.maxInputTokens > 0 && usage.inputTokens > limits.maxInputTokens {
      return denied(.inputTokens, "Task input token budget exhausted")
    }
    if limits.maxOutputTokens > 0 && usage.outputTokens > limits.maxOutputTokens {
      return denied(.outputTokens, "Task output token budget exhausted")
    }
    if limits.maxNetworkBytes > 0 && usage.networkBytes > limits.maxNetworkBytes {
      return denied(.network, "Task network budget exhausted")
    }
    if environment.batteryPercent >= 0 &&
      environment.batteryPercent < limits.minimumBatteryPercent &&
      !environment.charging {
      return denied(.battery, "Phone battery is below the task minimum")
    }
    let observedMemory = max(max(usage.peakMemoryBytes, environment.appMemoryBytes), 0)
    if limits.maxMemoryBytes > 0 && observedMemory > limits.maxMemoryBytes {
      return denied(.memory, "Task memory budget exhausted")
    }
    if cloudProvider && !limits.allowCloud {
      return denied(.cloud, "Cloud resources are disabled for this task")
    }
    if paidProvider && !limits.allowPaidProviders {
      return denied(.paidProvider, "Paid resources are disabled for this task")
    }
    if networkRequired {
      if !environment.networkAvailable {
        return denied(.network, "Network is unavailable")
      }
      switch limits.networkPolicy {
      case .any:
        break
      case .unmeteredOnly where environment.networkMetered:
        return denied(.network, "Task requires an unmetered network")
      case .trustedOnly where !trustedNetworkTarget:
        return denied(.network, "Task allows trusted network targets only")
      case .offlineOnly:
        return denied(.network, "Task is limited to offline resources")
      default:
        break
      }
    }
    return .approved
  }

  private static func denied(_ limit: AgentTaskBudgetLimit, _ reason: String) -> AgentTaskBudgetDecision {
    AgentTaskBudgetDecision(allowed: false, limit: limit, reason: reason)
  }
}

enum CustomDeviceTransport: String, Codable, CaseIterable, Identifiable {
  case httpRest = "HTTP_REST"
  case mqtt = "MQTT"
  case websocket = "WEBSOCKET"
  case tcp = "TCP"
  case udp = "UDP"
  case mcp = "MCP"
  case signalASIAgent = "SIGNALASI_AGENT"
  case ble = "BLE"
  case matterThread = "MATTER_THREAD"

  var id: String { rawValue }

  var displayName: String {
    rawValue.replacingOccurrences(of: "_", with: " ")
  }

  static func fromWireValue(_ value: String?) -> CustomDeviceTransport {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: " ", with: "_") ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .httpRest
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum CustomDeviceRisk: String, Codable, CaseIterable, Identifiable {
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .low: return "LOW"
    case .medium: return "MEDIUM"
    case .high: return "HIGH"
    }
  }

  static func fromWireValue(_ value: String?) -> CustomDeviceRisk {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .medium
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct CustomDeviceConnector: Codable, Equatable, Identifiable {
  static let maximumConnectors = 50
  static let maximumIdLength = 80
  static let maximumNameLength = 100
  static let maximumEndpointLength = 1_000
  static let maximumCommandTargetLength = 300
  static let maximumUsernameLength = 200
  static let maximumAuthTokenLength = 2_000

  var id: String
  var name: String
  var transport: CustomDeviceTransport
  var endpoint: String
  var commandTarget: String
  var username: String
  var authToken: String
  var risk: CustomDeviceRisk
  var enabled: Bool

  init(
    id: String = UUID().uuidString,
    name: String = "Custom Device",
    transport: CustomDeviceTransport = .httpRest,
    endpoint: String = "",
    commandTarget: String = "",
    username: String = "",
    authToken: String = "",
    risk: CustomDeviceRisk = .medium,
    enabled: Bool = true
  ) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = String(cleanId.prefix(Self.maximumIdLength)).ifBlank(UUID().uuidString)
    self.name = String(cleanName.prefix(Self.maximumNameLength)).ifBlank("Custom Device")
    self.transport = transport
    self.endpoint = String(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumEndpointLength))
    self.commandTarget = String(commandTarget.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCommandTargetLength))
    self.username = String(username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumUsernameLength))
    self.authToken = String(authToken.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumAuthTokenLength))
    self.risk = risk
    self.enabled = enabled
  }

  var configured: Bool {
    enabled && !name.isEmpty && !endpoint.isEmpty
  }

  var normalized: CustomDeviceConnector {
    CustomDeviceConnector(
      id: id,
      name: name,
      transport: transport,
      endpoint: endpoint,
      commandTarget: commandTarget,
      username: username,
      authToken: authToken,
      risk: risk,
      enabled: enabled
    )
  }

  var withoutAuthToken: CustomDeviceConnector {
    CustomDeviceConnector(
      id: id,
      name: name,
      transport: transport,
      endpoint: endpoint,
      commandTarget: commandTarget,
      username: username,
      authToken: "",
      risk: risk,
      enabled: enabled
    )
  }

  var maskedAuthToken: String {
    guard !authToken.isEmpty else { return "" }
    if authToken.count <= 8 { return "****" }
    return "\(authToken.prefix(4))****\(authToken.suffix(4))"
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case transport
    case endpoint
    case commandTarget = "command_target"
    case username
    case authToken = "auth_token"
    case risk
    case enabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Custom Device",
      transport: try container.decodeIfPresent(CustomDeviceTransport.self, forKey: .transport) ?? .httpRest,
      endpoint: try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "",
      commandTarget: try container.decodeIfPresent(String.self, forKey: .commandTarget) ?? "",
      username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
      authToken: try container.decodeIfPresent(String.self, forKey: .authToken) ?? "",
      risk: try container.decodeIfPresent(CustomDeviceRisk.self, forKey: .risk) ?? .medium,
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    )
  }
}

struct HomeAssistantSettings: Codable, Equatable {
  static let maximumBaseURLLength = 2_000
  static let maximumAccessTokenLength = 8_000
  static let maximumEntityIdLength = 240

  var enabled: Bool
  var baseUrl: String
  var accessToken: String
  var defaultEntityId: String

  init(
    enabled: Bool = false,
    baseUrl: String = "",
    accessToken: String = "",
    defaultEntityId: String = ""
  ) {
    self.enabled = enabled
    var cleanBaseURL = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    while cleanBaseURL.hasSuffix("/") {
      cleanBaseURL.removeLast()
    }
    self.baseUrl = String(cleanBaseURL.prefix(Self.maximumBaseURLLength))
    self.accessToken = String(
      accessToken.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumAccessTokenLength)
    )
    self.defaultEntityId = String(
      defaultEntityId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumEntityIdLength)
    )
  }

  static let `default` = HomeAssistantSettings()

  var credentialsConfigured: Bool {
    !baseUrl.isEmpty && !accessToken.isEmpty
  }

  var configured: Bool {
    enabled && credentialsConfigured
  }

  var normalized: HomeAssistantSettings {
    HomeAssistantSettings(
      enabled: enabled,
      baseUrl: baseUrl,
      accessToken: accessToken,
      defaultEntityId: defaultEntityId
    )
  }

  var withoutAccessToken: HomeAssistantSettings {
    HomeAssistantSettings(
      enabled: enabled,
      baseUrl: baseUrl,
      accessToken: "",
      defaultEntityId: defaultEntityId
    )
  }

  var maskedAccessToken: String {
    guard !accessToken.isEmpty else { return "" }
    if accessToken.count <= 8 { return "********" }
    return "\(accessToken.prefix(4))...\(accessToken.suffix(4))"
  }

  enum CodingKeys: String, CodingKey {
    case version
    case enabled
    case baseUrl = "base_url"
    case accessToken = "access_token"
    case defaultEntityId = "default_entity_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
      baseUrl: try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? "",
      accessToken: try container.decodeIfPresent(String.self, forKey: .accessToken) ?? "",
      defaultEntityId: try container.decodeIfPresent(String.self, forKey: .defaultEntityId) ?? ""
    )
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(value.enabled, forKey: .enabled)
    try container.encode(value.baseUrl, forKey: .baseUrl)
    try container.encode(value.accessToken, forKey: .accessToken)
    try container.encode(value.defaultEntityId, forKey: .defaultEntityId)
  }
}

struct AgentModelPlannerSettings: Codable, Equatable {
  static let maximumCloudContactIdLength = 120
  static let maximumActions = 12
  static let maximumReplans = 5
  static let maximumAgentHops = 8
  static let minimumToolCalls = 4
  static let maximumToolCalls = 32
  static let minimumLoopIterations = 1
  static let maximumLoopIterations = 24
  static let minimumPhaseRetries = 0
  static let maximumPhaseRetries = 5
  static let minimumNoProgressTimeoutSeconds = 60
  static let maximumNoProgressTimeoutSeconds = 3_600

  var enabled: Bool
  var shareScreenText: Bool
  var maxActions: Int
  var cloudContactId: String
  var dynamicReplanning: Bool
  var maxReplans: Int
  var multiAgentCoordination: Bool
  var shareAgentOutputsWithPlanner: Bool
  var maxAgentHops: Int
  var maxToolCalls: Int
  var maxLoopIterations: Int
  var maxPhaseRetries: Int
  var noProgressTimeoutSeconds: Int

  init(
    enabled: Bool = false,
    shareScreenText: Bool = false,
    maxActions: Int = 8,
    cloudContactId: String = "",
    dynamicReplanning: Bool = true,
    maxReplans: Int = 3,
    multiAgentCoordination: Bool = true,
    shareAgentOutputsWithPlanner: Bool = false,
    maxAgentHops: Int = 4,
    maxToolCalls: Int = 16,
    maxLoopIterations: Int = 8,
    maxPhaseRetries: Int = 2,
    noProgressTimeoutSeconds: Int = 180
  ) {
    self.enabled = enabled
    self.shareScreenText = shareScreenText
    self.maxActions = max(1, min(maxActions, Self.maximumActions))
    self.cloudContactId = String(
      cloudContactId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCloudContactIdLength)
    )
    self.dynamicReplanning = dynamicReplanning
    self.maxReplans = max(1, min(maxReplans, Self.maximumReplans))
    self.multiAgentCoordination = multiAgentCoordination
    self.shareAgentOutputsWithPlanner = shareAgentOutputsWithPlanner
    self.maxAgentHops = max(1, min(maxAgentHops, Self.maximumAgentHops))
    self.maxToolCalls = max(Self.minimumToolCalls, min(maxToolCalls, Self.maximumToolCalls))
    self.maxLoopIterations = max(Self.minimumLoopIterations, min(maxLoopIterations, Self.maximumLoopIterations))
    self.maxPhaseRetries = max(Self.minimumPhaseRetries, min(maxPhaseRetries, Self.maximumPhaseRetries))
    self.noProgressTimeoutSeconds = max(
      Self.minimumNoProgressTimeoutSeconds,
      min(noProgressTimeoutSeconds, Self.maximumNoProgressTimeoutSeconds)
    )
  }

  static let `default` = AgentModelPlannerSettings()

  var normalized: AgentModelPlannerSettings {
    AgentModelPlannerSettings(
      enabled: enabled,
      shareScreenText: shareScreenText,
      maxActions: maxActions,
      cloudContactId: cloudContactId,
      dynamicReplanning: dynamicReplanning,
      maxReplans: maxReplans,
      multiAgentCoordination: multiAgentCoordination,
      shareAgentOutputsWithPlanner: shareAgentOutputsWithPlanner,
      maxAgentHops: maxAgentHops,
      maxToolCalls: maxToolCalls,
      maxLoopIterations: maxLoopIterations,
      maxPhaseRetries: maxPhaseRetries,
      noProgressTimeoutSeconds: noProgressTimeoutSeconds
    )
  }

  enum CodingKeys: String, CodingKey {
    case version
    case enabled
    case shareScreenText = "share_screen_text"
    case maxActions = "max_actions"
    case cloudContactId = "cloud_contact_id"
    case dynamicReplanning = "dynamic_replanning"
    case maxReplans = "max_replans"
    case multiAgentCoordination = "multi_agent_coordination"
    case shareAgentOutputsWithPlanner = "share_agent_outputs_with_planner"
    case maxAgentHops = "max_agent_hops"
    case maxToolCalls = "max_tool_calls"
    case maxLoopIterations = "max_loop_iterations"
    case maxPhaseRetries = "max_phase_retries"
    case noProgressTimeoutSeconds = "no_progress_timeout_seconds"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
      shareScreenText: try container.decodeIfPresent(Bool.self, forKey: .shareScreenText) ?? false,
      maxActions: try container.decodeIfPresent(Int.self, forKey: .maxActions) ?? 8,
      cloudContactId: try container.decodeIfPresent(String.self, forKey: .cloudContactId) ?? "",
      dynamicReplanning: try container.decodeIfPresent(Bool.self, forKey: .dynamicReplanning) ?? true,
      maxReplans: try container.decodeIfPresent(Int.self, forKey: .maxReplans) ?? 3,
      multiAgentCoordination: try container.decodeIfPresent(Bool.self, forKey: .multiAgentCoordination) ?? true,
      shareAgentOutputsWithPlanner: try container.decodeIfPresent(Bool.self, forKey: .shareAgentOutputsWithPlanner) ?? false,
      maxAgentHops: try container.decodeIfPresent(Int.self, forKey: .maxAgentHops) ?? 4,
      maxToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 16,
      maxLoopIterations: try container.decodeIfPresent(Int.self, forKey: .maxLoopIterations) ?? 8,
      maxPhaseRetries: try container.decodeIfPresent(Int.self, forKey: .maxPhaseRetries) ?? 2,
      noProgressTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .noProgressTimeoutSeconds) ?? 180
    )
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(5, forKey: .version)
    try container.encode(value.enabled, forKey: .enabled)
    try container.encode(value.shareScreenText, forKey: .shareScreenText)
    try container.encode(value.maxActions, forKey: .maxActions)
    try container.encode(value.cloudContactId, forKey: .cloudContactId)
    try container.encode(value.dynamicReplanning, forKey: .dynamicReplanning)
    try container.encode(value.maxReplans, forKey: .maxReplans)
    try container.encode(value.multiAgentCoordination, forKey: .multiAgentCoordination)
    try container.encode(value.shareAgentOutputsWithPlanner, forKey: .shareAgentOutputsWithPlanner)
    try container.encode(value.maxAgentHops, forKey: .maxAgentHops)
    try container.encode(value.maxToolCalls, forKey: .maxToolCalls)
    try container.encode(value.maxLoopIterations, forKey: .maxLoopIterations)
    try container.encode(value.maxPhaseRetries, forKey: .maxPhaseRetries)
    try container.encode(value.noProgressTimeoutSeconds, forKey: .noProgressTimeoutSeconds)
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

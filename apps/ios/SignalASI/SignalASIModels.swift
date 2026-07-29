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

struct VoiceSettings: Codable, Equatable {
  var wakeListeningEnabled: Bool
  var speechRecognitionEnabled: Bool
  var textToSpeechEnabled: Bool
  var autoSendTranscripts: Bool
  var preferredLocaleIdentifier: String

  static let `default` = VoiceSettings(
    wakeListeningEnabled: false,
    speechRecognitionEnabled: true,
    textToSpeechEnabled: true,
    autoSendTranscripts: false,
    preferredLocaleIdentifier: Locale.current.identifier
  )
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

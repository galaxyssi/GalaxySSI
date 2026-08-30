import CryptoKit
import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

struct SignalASIBackupIdentity: Codable, Equatable {
  var kind: String
  var identityPrivateKey: String
  var identityPublicKey: String
  var identityFingerprint: String

  init(
    kind: String = "ios-p256-signing",
    identityPrivateKey: String,
    identityPublicKey: String,
    identityFingerprint: String
  ) {
    self.kind = kind
    self.identityPrivateKey = identityPrivateKey
    self.identityPublicKey = identityPublicKey
    self.identityFingerprint = identityFingerprint
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case identityPrivateKey = "identity_private_key"
    case identityPublicKey = "identity_public_key"
    case identityFingerprint = "identity_fingerprint"
  }
}

struct SignalASIBackupPrivacyManifest: Codable, Equatable {
  var includesIdentity: Bool
  var includesContacts: Bool
  var includesMessages: Bool
  var includesServerLinks: Bool
  var includesVoiceSettings: Bool
  var includesDisplaySettings: Bool
  var includesAgentSafetySettings: Bool
  var includesAgentTaskBudget: Bool
  var includesAgentKnowledge: Bool
  var includesAgentTaskHistory: Bool
  var includesAutomationTasks: Bool
  var includesAgentConversations: Bool
  var includesGlobalAgentState: Bool
  var includesAgentTranscript: Bool
  var includesCustomDeviceConnectors: Bool
  var includesHomeAssistantSettings: Bool
  var includesModelPlannerSettings: Bool
  var includesGlobalAgentSettings: Bool
  var includesCloudAPISecrets: Bool

  init(
    includesIdentity: Bool,
    includesContacts: Bool,
    includesMessages: Bool,
    includesServerLinks: Bool,
    includesVoiceSettings: Bool,
    includesDisplaySettings: Bool = false,
    includesAgentSafetySettings: Bool = false,
    includesAgentTaskBudget: Bool = false,
    includesAgentKnowledge: Bool = false,
    includesAgentTaskHistory: Bool = false,
    includesAutomationTasks: Bool = false,
    includesAgentConversations: Bool = false,
    includesGlobalAgentState: Bool = false,
    includesAgentTranscript: Bool = false,
    includesCustomDeviceConnectors: Bool = false,
    includesHomeAssistantSettings: Bool = false,
    includesModelPlannerSettings: Bool = false,
    includesGlobalAgentSettings: Bool = false,
    includesCloudAPISecrets: Bool
  ) {
    self.includesIdentity = includesIdentity
    self.includesContacts = includesContacts
    self.includesMessages = includesMessages
    self.includesServerLinks = includesServerLinks
    self.includesVoiceSettings = includesVoiceSettings
    self.includesDisplaySettings = includesDisplaySettings
    self.includesAgentSafetySettings = includesAgentSafetySettings
    self.includesAgentTaskBudget = includesAgentTaskBudget
    self.includesAgentKnowledge = includesAgentKnowledge
    self.includesAgentTaskHistory = includesAgentTaskHistory
    self.includesAutomationTasks = includesAutomationTasks
    self.includesAgentConversations = includesAgentConversations
    self.includesGlobalAgentState = includesGlobalAgentState
    self.includesAgentTranscript = includesAgentTranscript
    self.includesCustomDeviceConnectors = includesCustomDeviceConnectors
    self.includesHomeAssistantSettings = includesHomeAssistantSettings
    self.includesModelPlannerSettings = includesModelPlannerSettings
    self.includesGlobalAgentSettings = includesGlobalAgentSettings
    self.includesCloudAPISecrets = includesCloudAPISecrets
  }

  static let empty = SignalASIBackupPrivacyManifest(
    includesIdentity: false,
    includesContacts: false,
    includesMessages: false,
    includesServerLinks: false,
    includesVoiceSettings: false,
    includesDisplaySettings: false,
    includesAgentSafetySettings: false,
    includesAgentTaskBudget: false,
    includesAgentKnowledge: false,
    includesAgentTaskHistory: false,
    includesAutomationTasks: false,
    includesAgentConversations: false,
    includesGlobalAgentState: false,
    includesAgentTranscript: false,
    includesCustomDeviceConnectors: false,
    includesHomeAssistantSettings: false,
    includesModelPlannerSettings: false,
    includesGlobalAgentSettings: false,
    includesCloudAPISecrets: false
  )

  enum CodingKeys: String, CodingKey {
    case includesIdentity = "includes_identity"
    case includesContacts = "includes_contacts"
    case includesMessages = "includes_messages"
    case includesServerLinks = "includes_server_links"
    case includesVoiceSettings = "includes_voice_settings"
    case includesDisplaySettings = "includes_display_settings"
    case includesAgentSafetySettings = "includes_agent_safety_settings"
    case includesAgentTaskBudget = "includes_agent_task_budget"
    case includesAgentKnowledge = "includes_agent_knowledge"
    case includesAgentTaskHistory = "includes_agent_task_history"
    case includesAutomationTasks = "includes_automation_tasks"
    case includesAgentConversations = "includes_agent_conversations"
    case includesGlobalAgentState = "includes_global_agent_state"
    case includesAgentTranscript = "includes_agent_transcript"
    case includesCustomDeviceConnectors = "includes_custom_device_connectors"
    case includesHomeAssistantSettings = "includes_home_assistant_settings"
    case includesModelPlannerSettings = "includes_model_planner_settings"
    case includesGlobalAgentSettings = "includes_global_agent_settings"
    case includesCloudAPISecrets = "includes_cloud_api_secrets"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    includesIdentity = try container.decodeIfPresent(Bool.self, forKey: .includesIdentity) ?? false
    includesContacts = try container.decodeIfPresent(Bool.self, forKey: .includesContacts) ?? false
    includesMessages = try container.decodeIfPresent(Bool.self, forKey: .includesMessages) ?? false
    includesServerLinks = try container.decodeIfPresent(Bool.self, forKey: .includesServerLinks) ?? false
    includesVoiceSettings = try container.decodeIfPresent(Bool.self, forKey: .includesVoiceSettings) ?? false
    includesDisplaySettings = try container.decodeIfPresent(Bool.self, forKey: .includesDisplaySettings) ?? false
    includesAgentSafetySettings = try container.decodeIfPresent(Bool.self, forKey: .includesAgentSafetySettings) ?? false
    includesAgentTaskBudget = try container.decodeIfPresent(Bool.self, forKey: .includesAgentTaskBudget) ?? false
    includesAgentKnowledge = try container.decodeIfPresent(Bool.self, forKey: .includesAgentKnowledge) ?? false
    includesAgentTaskHistory = try container.decodeIfPresent(Bool.self, forKey: .includesAgentTaskHistory) ?? false
    includesAutomationTasks = try container.decodeIfPresent(Bool.self, forKey: .includesAutomationTasks) ?? false
    includesAgentConversations = try container.decodeIfPresent(Bool.self, forKey: .includesAgentConversations) ?? false
    includesGlobalAgentState = try container.decodeIfPresent(Bool.self, forKey: .includesGlobalAgentState) ?? false
    includesAgentTranscript = try container.decodeIfPresent(Bool.self, forKey: .includesAgentTranscript) ?? false
    includesCustomDeviceConnectors = try container.decodeIfPresent(Bool.self, forKey: .includesCustomDeviceConnectors) ?? false
    includesHomeAssistantSettings = try container.decodeIfPresent(Bool.self, forKey: .includesHomeAssistantSettings) ?? false
    includesModelPlannerSettings = try container.decodeIfPresent(Bool.self, forKey: .includesModelPlannerSettings) ?? false
    includesGlobalAgentSettings = try container.decodeIfPresent(Bool.self, forKey: .includesGlobalAgentSettings) ?? false
    includesCloudAPISecrets = try container.decodeIfPresent(Bool.self, forKey: .includesCloudAPISecrets) ?? false
  }
}

struct SignalASIBackupAgentData: Codable, Equatable {
  var serverLinks: [ServerLink]
  var memory: [AgentMemoryItem]?
  var memoryDeletionIndex: [AgentMemoryDeletionTombstone]?
  var knowledge: [AgentKnowledgeItem]?
  var knowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry]?
  var taskHistory: [AgentTaskRecord]?
  var transcript: [AgentTranscriptEntry]?
  var proactiveTasks: [AgentProactiveTask]?
  var proactiveRuns: [AgentProactiveRun]?
  var workflowExecutions: [AgentWorkflowExecutionRecord]?
  var workflowTriggers: [AgentWorkflowTrigger]?
  var globalProactiveMessages: [GlobalProactiveMessage]?
  var globalAgentFeedback: [GlobalAgentFeedback]?
  var globalAgentState: SignalASIGlobalAgentBackupData?
  var agentConversations: [AgentConversation]?
  var activeAgentConversationId: String
  var voiceSettings: VoiceSettings
  var languagePolicy: LanguagePolicySettings
  var displaySettings: AppDisplaySettings
  var agentSafetySettings: AgentSafetySettings
  var agentPreferenceMode: AgentPreferenceMode
  var cloudAPISecrets: [String: String]
  var taskBudget: AgentTaskBudget
  var customDeviceConnectors: [CustomDeviceConnector]
  var homeAssistantSettings: HomeAssistantSettings
  var modelPlannerSettings: AgentModelPlannerSettings
  var globalAgentSettings: GlobalAgentSettings

  static let empty = SignalASIBackupAgentData(
    serverLinks: [],
    memory: nil,
    memoryDeletionIndex: nil,
    knowledge: nil,
    knowledgeAccessAudit: nil,
    taskHistory: nil,
    transcript: nil,
    proactiveTasks: nil,
    proactiveRuns: nil,
    workflowExecutions: nil,
    workflowTriggers: nil,
    globalProactiveMessages: nil,
    globalAgentFeedback: nil,
    globalAgentState: nil,
    agentConversations: nil,
    activeAgentConversationId: "",
    voiceSettings: .default,
    languagePolicy: .default,
    displaySettings: .default,
    agentSafetySettings: .default,
    agentPreferenceMode: .cautious,
    cloudAPISecrets: [:],
    taskBudget: .default,
    customDeviceConnectors: [],
    homeAssistantSettings: .default,
    modelPlannerSettings: .default,
    globalAgentSettings: .default
  )

  init(
    serverLinks: [ServerLink],
    memory: [AgentMemoryItem]? = nil,
    memoryDeletionIndex: [AgentMemoryDeletionTombstone]? = nil,
    knowledge: [AgentKnowledgeItem]? = nil,
    knowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry]? = nil,
    taskHistory: [AgentTaskRecord]? = nil,
    transcript: [AgentTranscriptEntry]? = nil,
    proactiveTasks: [AgentProactiveTask]? = nil,
    proactiveRuns: [AgentProactiveRun]? = nil,
    workflowExecutions: [AgentWorkflowExecutionRecord]? = nil,
    workflowTriggers: [AgentWorkflowTrigger]? = nil,
    globalProactiveMessages: [GlobalProactiveMessage]? = nil,
    globalAgentFeedback: [GlobalAgentFeedback]? = nil,
    globalAgentState: SignalASIGlobalAgentBackupData? = nil,
    agentConversations: [AgentConversation]? = nil,
    activeAgentConversationId: String = "",
    voiceSettings: VoiceSettings,
    languagePolicy: LanguagePolicySettings = .default,
    displaySettings: AppDisplaySettings = .default,
    agentSafetySettings: AgentSafetySettings = .default,
    agentPreferenceMode: AgentPreferenceMode = .cautious,
    cloudAPISecrets: [String: String],
    taskBudget: AgentTaskBudget = .default,
    customDeviceConnectors: [CustomDeviceConnector] = [],
    homeAssistantSettings: HomeAssistantSettings = .default,
    modelPlannerSettings: AgentModelPlannerSettings = .default,
    globalAgentSettings: GlobalAgentSettings = .default
  ) {
    self.serverLinks = serverLinks
    self.memory = memory.map { Array($0.suffix(AgentMemoryPolicy.maxItems)) }
    self.memoryDeletionIndex = memoryDeletionIndex.map {
      AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: $0)
    }
    self.knowledge = knowledge.map { Array($0.suffix(500)) }
    self.knowledgeAccessAudit = knowledgeAccessAudit.map { Array($0.suffix(100)) }
    self.taskHistory = taskHistory.map { Array($0.suffix(200)) }
    self.transcript = transcript.map { Array($0.suffix(500)) }
    self.proactiveTasks = proactiveTasks.map { Array($0.suffix(200)) }
    self.proactiveRuns = proactiveRuns.map { Array($0.suffix(500)) }
    self.workflowExecutions = workflowExecutions.map { Array($0.suffix(500)) }
    self.workflowTriggers = workflowTriggers.map { Array($0.suffix(100)) }
    self.globalProactiveMessages = globalProactiveMessages.map { Array($0.suffix(500)) }
    self.globalAgentFeedback = globalAgentFeedback.map { Array($0.suffix(500)) }
    self.globalAgentState = globalAgentState
    self.agentConversations = agentConversations.map { Array($0.suffix(10_000)) }
    self.activeAgentConversationId = activeAgentConversationId
    self.voiceSettings = voiceSettings
    self.languagePolicy = languagePolicy
    self.displaySettings = displaySettings
    self.agentSafetySettings = agentSafetySettings
    self.agentPreferenceMode = agentPreferenceMode
    self.cloudAPISecrets = cloudAPISecrets
    self.taskBudget = taskBudget
    self.customDeviceConnectors = Array(customDeviceConnectors.suffix(CustomDeviceConnector.maximumConnectors))
    self.homeAssistantSettings = homeAssistantSettings
    self.modelPlannerSettings = modelPlannerSettings
    self.globalAgentSettings = globalAgentSettings
  }

  enum CodingKeys: String, CodingKey {
    case serverLinks = "server_links"
    case memory
    case memoryDeletionIndex = "memory_deletion_index"
    case knowledge
    case knowledgeAccessAudit = "knowledge_access_audit"
    case taskHistory = "task_history"
    case transcript
    case proactiveTasks = "proactive_tasks"
    case proactiveRuns = "proactive_runs"
    case workflowExecutions = "workflow_executions"
    case workflowTriggers = "workflow_triggers"
    case globalProactiveMessages = "global_proactive_messages"
    case globalAgentFeedback = "global_agent_feedback"
    case globalAgentState = "global_super_agent"
    case agentConversations = "agent_conversations"
    case activeAgentConversationId = "active_agent_conversation_id"
    case voiceSettings = "voice_settings"
    case languagePolicy = "language_policy"
    case displaySettings = "display_settings"
    case agentSafetySettings = "agent_safety_settings"
    case agentPreferenceMode = "agent_preference_mode"
    case cloudAPISecrets = "cloud_api_secrets"
    case taskBudget = "task_budget"
    case customDeviceConnectors = "custom_device_connectors"
    case homeAssistantSettings = "home_assistant"
    case modelPlannerSettings = "model_planner"
    case globalAgentSettings = "global_agent"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    serverLinks = try container.decodeIfPresent([ServerLink].self, forKey: .serverLinks) ?? []
    memory = try container.decodeIfPresent([AgentMemoryItem].self, forKey: .memory).map {
      Array($0.suffix(AgentMemoryPolicy.maxItems))
    }
    memoryDeletionIndex = try container.decodeIfPresent(
      [AgentMemoryDeletionTombstone].self,
      forKey: .memoryDeletionIndex
    ).map {
      AgentMemoryCausalDeletionPolicy.merge(current: [], incoming: $0)
    }
    knowledge = try container.decodeIfPresent([AgentKnowledgeItem].self, forKey: .knowledge).map {
      Array($0.suffix(500))
    }
    knowledgeAccessAudit = try container.decodeIfPresent(
      [AgentKnowledgeAccessAuditEntry].self,
      forKey: .knowledgeAccessAudit
    ).map {
      Array($0.suffix(100))
    }
    taskHistory = try container.decodeIfPresent([AgentTaskRecord].self, forKey: .taskHistory).map {
      Array($0.suffix(200))
    }
    transcript = try container.decodeIfPresent([AgentTranscriptEntry].self, forKey: .transcript).map {
      Array($0.suffix(500))
    }
    proactiveTasks = try container.decodeIfPresent([AgentProactiveTask].self, forKey: .proactiveTasks).map {
      Array($0.suffix(200))
    }
    proactiveRuns = try container.decodeIfPresent([AgentProactiveRun].self, forKey: .proactiveRuns).map {
      Array($0.suffix(500))
    }
    workflowExecutions = try container.decodeIfPresent(
      [AgentWorkflowExecutionRecord].self,
      forKey: .workflowExecutions
    ).map {
      Array($0.suffix(500))
    }
    workflowTriggers = try container.decodeIfPresent([AgentWorkflowTrigger].self, forKey: .workflowTriggers).map {
      Array($0.suffix(100))
    }
    globalProactiveMessages = try container.decodeIfPresent([GlobalProactiveMessage].self, forKey: .globalProactiveMessages).map {
      Array($0.suffix(500))
    }
    globalAgentFeedback = try container.decodeIfPresent([GlobalAgentFeedback].self, forKey: .globalAgentFeedback).map {
      Array($0.suffix(500))
    }
    globalAgentState = try container.decodeIfPresent(
      SignalASIGlobalAgentBackupData.self,
      forKey: .globalAgentState
    )
    agentConversations = try container.decodeIfPresent([AgentConversation].self, forKey: .agentConversations).map {
      Array($0.suffix(10_000))
    }
    activeAgentConversationId = try container.decodeIfPresent(String.self, forKey: .activeAgentConversationId) ?? ""
    voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings) ?? .default
    languagePolicy = try container.decodeIfPresent(LanguagePolicySettings.self, forKey: .languagePolicy) ?? .default
    displaySettings = try container.decodeIfPresent(AppDisplaySettings.self, forKey: .displaySettings) ?? .default
    agentSafetySettings = try container.decodeIfPresent(AgentSafetySettings.self, forKey: .agentSafetySettings) ?? .default
    agentPreferenceMode = try container.decodeIfPresent(AgentPreferenceMode.self, forKey: .agentPreferenceMode) ?? .cautious
    cloudAPISecrets = try container.decodeIfPresent([String: String].self, forKey: .cloudAPISecrets) ?? [:]
    taskBudget = try container.decodeIfPresent(AgentTaskBudget.self, forKey: .taskBudget) ?? .default
    customDeviceConnectors = Array(
      (try container.decodeIfPresent([CustomDeviceConnector].self, forKey: .customDeviceConnectors) ?? [])
        .suffix(CustomDeviceConnector.maximumConnectors)
    )
    homeAssistantSettings = try container.decodeIfPresent(HomeAssistantSettings.self, forKey: .homeAssistantSettings) ?? .default
    modelPlannerSettings = try container.decodeIfPresent(AgentModelPlannerSettings.self, forKey: .modelPlannerSettings) ?? .default
    globalAgentSettings = try container.decodeIfPresent(GlobalAgentSettings.self, forKey: .globalAgentSettings) ?? .default
  }
}

struct SignalASIBackupPayload: Codable, Equatable {
  var platform: String
  var exportedAt: Int64
  var identity: SignalASIBackupIdentity?
  var profile: SignalASIProfile
  var includesContacts: Bool
  var includesMessages: Bool
  var includesAgentData: Bool
  var privacyManifest: SignalASIBackupPrivacyManifest
  var agentData: SignalASIBackupAgentData
  var contacts: [SignalASIContact]
  var friendRequests: [SignalASIFriendRequest]
  var messagesByContact: [String: [ChatMessage]]
  var readAtByContact: [String: Date]

  init(
    platform: String = "ios",
    exportedAt: Int64 = SignalASIBackupManager.currentTimestampMilliseconds(),
    identity: SignalASIBackupIdentity?,
    profile: SignalASIProfile,
    includesContacts: Bool,
    includesMessages: Bool,
    includesAgentData: Bool = true,
    privacyManifest: SignalASIBackupPrivacyManifest,
    agentData: SignalASIBackupAgentData,
    contacts: [SignalASIContact],
    friendRequests: [SignalASIFriendRequest] = [],
    messagesByContact: [String: [ChatMessage]],
    readAtByContact: [String: Date] = [:]
  ) {
    self.platform = platform
    self.exportedAt = exportedAt
    self.identity = identity
    self.profile = profile
    self.includesContacts = includesContacts
    self.includesMessages = includesMessages
    self.includesAgentData = includesAgentData
    self.privacyManifest = privacyManifest
    self.agentData = agentData
    self.contacts = contacts
    self.friendRequests = friendRequests
    self.messagesByContact = messagesByContact
    self.readAtByContact = readAtByContact
  }

  enum CodingKeys: String, CodingKey {
    case platform
    case exportedAt = "exported_at"
    case identity
    case profile
    case includesContacts = "includes_contacts"
    case includesMessages = "includes_messages"
    case includesAgentData = "includes_agent_data"
    case privacyManifest = "privacy_manifest"
    case agentData = "agent_data"
    case contacts
    case friendRequests = "friend_requests"
    case messagesByContact = "messages"
    case readAtByContact = "read_at_by_contact"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    platform = try container.decode(String.self, forKey: .platform)
    exportedAt = try container.decode(Int64.self, forKey: .exportedAt)
    identity = try container.decodeIfPresent(SignalASIBackupIdentity.self, forKey: .identity)
    profile = try container.decode(SignalASIProfile.self, forKey: .profile)
    includesContacts = try container.decode(Bool.self, forKey: .includesContacts)
    includesMessages = try container.decode(Bool.self, forKey: .includesMessages)
    includesAgentData = try container.decodeIfPresent(Bool.self, forKey: .includesAgentData) ?? true
    privacyManifest = try container.decode(SignalASIBackupPrivacyManifest.self, forKey: .privacyManifest)
    agentData = try container.decode(SignalASIBackupAgentData.self, forKey: .agentData)
    contacts = try container.decode([SignalASIContact].self, forKey: .contacts)
    friendRequests = try container.decodeIfPresent([SignalASIFriendRequest].self, forKey: .friendRequests) ?? []
    messagesByContact = try container.decode([String: [ChatMessage]].self, forKey: .messagesByContact)
    readAtByContact = try container.decodeIfPresent([String: Date].self, forKey: .readAtByContact) ?? [:]
  }
}

struct SignalASIBackupRoot: Codable, Equatable {
  var version: Int
  var type: String
  var kdf: String
  var iterations: Int
  var cipher: String
  var salt: String
  var iv: String
  var ciphertext: String
  var createdAt: Int64

  enum CodingKeys: String, CodingKey {
    case version
    case type
    case kdf
    case iterations
    case cipher
    case salt
    case iv
    case ciphertext
    case createdAt = "created_at"
  }
}

enum SignalASIBackupManager {
  static let version = 1
  static let type = "signalasi_backup"
  static let kdf = "pbkdf2-hmac-sha256"
  static let cipher = "aes-256-gcm"
  static let iterations = 180_000
  static let minimumPasswordLength = 8

  private static let keyByteCount = 32
  private static let saltByteCount = 16
  private static let nonceByteCount = 12
  private static let gcmTagByteCount = 16

  @MainActor
  static func exportBackup(
    store: SignalASIStore,
    password: String,
    includeContacts: Bool = true,
    includeMessages: Bool = true,
    iterations: Int = SignalASIBackupManager.iterations
  ) throws -> Data {
    let payload = store.exportBackupPayload(
      includeContacts: includeContacts,
      includeMessages: includeMessages
    )
    return try encryptPayload(payload, password: password, iterations: iterations)
  }

  static func encryptPayload(
    _ payload: SignalASIBackupPayload,
    password: String,
    iterations: Int = SignalASIBackupManager.iterations
  ) throws -> Data {
    try validatePassword(password)
    guard iterations > 0 else {
      throw SignalASIError.invalidPayload("Backup KDF iterations must be positive.")
    }
    let payloadData = try backupEncoder.encode(payload)
    let salt = try randomData(count: saltByteCount)
    let iv = try randomData(count: nonceByteCount)
    let key = SymmetricKey(data: try pbkdf2SHA256(
      password: password,
      salt: salt,
      iterations: iterations,
      keyByteCount: keyByteCount
    ))
    let sealed = try AES.GCM.seal(
      payloadData,
      using: key,
      nonce: try AES.GCM.Nonce(data: iv)
    )
    var androidCompatibleCiphertext = sealed.ciphertext
    androidCompatibleCiphertext.append(sealed.tag)
    let root = SignalASIBackupRoot(
      version: version,
      type: type,
      kdf: kdf,
      iterations: iterations,
      cipher: cipher,
      salt: salt.base64EncodedString(),
      iv: iv.base64EncodedString(),
      ciphertext: androidCompatibleCiphertext.base64EncodedString(),
      createdAt: currentTimestampMilliseconds()
    )
    return try backupEncoder.encode(root)
  }

  static func importBackup(data: Data, password: String) throws -> SignalASIBackupPayload {
    try validatePassword(password)
    let root = try decodeRoot(from: data)
    let payloadData = try decryptRoot(root, password: password)
    return try backupDecoder.decode(SignalASIBackupPayload.self, from: payloadData)
  }

  static func decodeRoot(from data: Data) throws -> SignalASIBackupRoot {
    try backupDecoder.decode(SignalASIBackupRoot.self, from: data)
  }

  static func pbkdf2SHA256(
    password: String,
    salt: Data,
    iterations: Int,
    keyByteCount: Int
  ) throws -> Data {
    guard iterations > 0, keyByteCount > 0 else {
      throw SignalASIError.invalidPayload("Backup KDF parameters are invalid.")
    }
    let passwordKey = SymmetricKey(data: Data(password.utf8))
    var derived = Data()
    var blockIndex: UInt32 = 1

    while derived.count < keyByteCount {
      var blockSalt = salt
      blockSalt.append(contentsOf: [
        UInt8((blockIndex >> 24) & 0xff),
        UInt8((blockIndex >> 16) & 0xff),
        UInt8((blockIndex >> 8) & 0xff),
        UInt8(blockIndex & 0xff)
      ])

      var previous = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: passwordKey))
      var block = [UInt8](previous)
      if iterations > 1 {
        for _ in 1..<iterations {
          previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: passwordKey))
          let previousBytes = [UInt8](previous)
          for offset in block.indices {
            block[offset] ^= previousBytes[offset]
          }
        }
      }
      derived.append(contentsOf: block)
      blockIndex += 1
    }
    return Data(derived.prefix(keyByteCount))
  }

  static func currentTimestampMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  static func defaultFilename() -> String {
    "signalasi_backup_\(currentTimestampMilliseconds()).hcbak"
  }

  private static func decryptRoot(_ root: SignalASIBackupRoot, password: String) throws -> Data {
    guard root.version == version,
          root.type == type,
          root.kdf == kdf,
          root.cipher == cipher else {
      throw SignalASIError.invalidPayload("Backup file format is not supported.")
    }
    guard let salt = Data(base64Encoded: root.salt),
          let iv = Data(base64Encoded: root.iv),
          let combined = Data(base64Encoded: root.ciphertext),
          salt.count == saltByteCount,
          iv.count == nonceByteCount,
          combined.count > gcmTagByteCount else {
      throw SignalASIError.invalidPayload("Backup envelope is malformed.")
    }
    let key = SymmetricKey(data: try pbkdf2SHA256(
      password: password,
      salt: salt,
      iterations: root.iterations,
      keyByteCount: keyByteCount
    ))
    let ciphertext = combined.prefix(combined.count - gcmTagByteCount)
    let tag = combined.suffix(gcmTagByteCount)
    do {
      let sealed = try AES.GCM.SealedBox(
        nonce: try AES.GCM.Nonce(data: iv),
        ciphertext: Data(ciphertext),
        tag: Data(tag)
      )
      return try AES.GCM.open(sealed, using: key)
    } catch {
      throw SignalASIError.invalidPayload("Backup password is incorrect or the file is damaged.")
    }
  }

  private static func validatePassword(_ password: String) throws {
    guard password.count >= minimumPasswordLength else {
      throw SignalASIError.invalidPayload("Backup password must be at least 8 characters.")
    }
  }

  private static func randomData(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw SignalASIError.invalidPayload("Unable to create secure backup randomness.")
    }
    return Data(bytes)
  }

  private static var backupEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static var backupDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

struct SignalASIBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  static var writableContentTypes: [UTType] { [.data] }

  var data: Data

  init(data: Data = Data()) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

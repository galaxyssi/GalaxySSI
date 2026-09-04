import Foundation

enum AgentPrivateDataExportPolicy: String, Codable, CaseIterable, Identifiable {
  case alwaysEncrypted = "ALWAYS_ENCRYPTED"
  case optionalContacts = "OPTIONAL_CONTACTS"
  case optionalSessionHistory = "OPTIONAL_SESSION_HISTORY"
  case neverExport = "NEVER_EXPORT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataExportPolicy {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .neverExport
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

enum AgentPrivateDataSensitivity: String, Codable, CaseIterable, Identifiable {
  case personal = "PERSONAL"
  case secret = "SECRET"
  case ephemeral = "EPHEMERAL"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataSensitivity {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .personal
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

enum AgentPrivateDataErasePolicy: String, Codable, CaseIterable, Identifiable {
  case delete = "DELETE"
  case deleteAndRotateIdentity = "DELETE_AND_ROTATE_IDENTITY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPrivateDataErasePolicy {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .delete
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

struct AgentPrivateDataDescriptor: Codable, Equatable, Identifiable {
  var id: String
  var category: String
  var storageIds: Set<String>
  var backupPath: String
  var exportPolicy: AgentPrivateDataExportPolicy
  var sensitivity: AgentPrivateDataSensitivity
  var erasePolicy: AgentPrivateDataErasePolicy

  init(
    id: String,
    category: String,
    storageIds: Set<String>,
    backupPath: String = "",
    exportPolicy: AgentPrivateDataExportPolicy,
    sensitivity: AgentPrivateDataSensitivity,
    erasePolicy: AgentPrivateDataErasePolicy = .delete
  ) {
    self.id = id
    self.category = category
    self.storageIds = storageIds
    self.backupPath = backupPath
    self.exportPolicy = exportPolicy
    self.sensitivity = sensitivity
    self.erasePolicy = erasePolicy
  }

  enum CodingKeys: String, CodingKey {
    case id
    case category
    case storageIds = "storage_ids"
    case backupPath = "backup_path"
    case exportPolicy = "export_policy"
    case sensitivity
    case erasePolicy = "erase_policy"
  }
}

struct AgentPrivateDataInventoryAudit: Codable, Equatable {
  var duplicateIds: Set<String>
  var descriptorsWithoutStorage: Set<String>
  var exportedDescriptorsWithoutPath: Set<String>
  var nonExportedDescriptorsWithPath: Set<String>
  var identityRotationCount: Int

  var complete: Bool {
    duplicateIds.isEmpty &&
      descriptorsWithoutStorage.isEmpty &&
      exportedDescriptorsWithoutPath.isEmpty &&
      nonExportedDescriptorsWithPath.isEmpty &&
      identityRotationCount == 1
  }

  enum CodingKeys: String, CodingKey {
    case duplicateIds = "duplicate_ids"
    case descriptorsWithoutStorage = "descriptors_without_storage"
    case exportedDescriptorsWithoutPath = "exported_descriptors_without_path"
    case nonExportedDescriptorsWithPath = "non_exported_descriptors_with_path"
    case identityRotationCount = "identity_rotation_count"
  }
}

struct AgentPrivateDataBackupManifest: Codable, Equatable {
  var policyVersion: Int
  var encryptedContainerRequired: Bool
  var privateModeExported: Bool
  var pausedTrackingExported: Bool
  var identityRotatedOnReset: Bool
  var includedStoreIds: [String]
  var secretStoreIds: [String]
  var excludedStoreIds: [String]
  var eraseStoreIds: [String]

  enum CodingKeys: String, CodingKey {
    case policyVersion = "policy_version"
    case encryptedContainerRequired = "encrypted_container_required"
    case privateModeExported = "private_mode_exported"
    case pausedTrackingExported = "paused_tracking_exported"
    case identityRotatedOnReset = "identity_rotated_on_reset"
    case includedStoreIds = "included_store_ids"
    case secretStoreIds = "secret_store_ids"
    case excludedStoreIds = "excluded_store_ids"
    case eraseStoreIds = "erase_store_ids"
  }
}

enum AgentPrivateDataInventory {
  static let policyVersion = 1

  static let descriptors: [AgentPrivateDataDescriptor] = [
    item(
      "identity",
      "Identity keys and installation identity",
      "keychain:identity.p256.private",
      "user_defaults:galaxyssi_signal_store",
      "user_defaults:galaxyssi_signal_trust",
      backupPath: "root.identity",
      exportPolicy: .alwaysEncrypted,
      sensitivity: .secret,
      erasePolicy: .deleteAndRotateIdentity
    ),
    item("profile", "Local profile", "user_defaults:galaxyssi_app_store", backupPath: "root.profile"),
    item(
      "contacts",
      "Contacts, paired endpoints, and cloud model credentials",
      "user_defaults:galaxyssi_app_store",
      "keychain:cloud_api_keys",
      backupPath: "root.contacts",
      exportPolicy: .optionalContacts,
      sensitivity: .secret
    ),
    item(
      "friend_requests",
      "Pending trust requests",
      "user_defaults:galaxyssi_app_store",
      backupPath: "root.friend_requests",
      exportPolicy: .optionalContacts
    ),
    item(
      "chat_history",
      "Contact message history",
      "user_defaults:galaxyssi_app_store",
      backupPath: "root.messages",
      exportPolicy: .optionalSessionHistory
    ),
    item("memory", "Long-term memory", "user_defaults:galaxyssi_agent_memory_v2", backupPath: "agent.memory"),
    item(
      "memory_deletion_index",
      "Causal memory deletion tombstones",
      "user_defaults:galaxyssi_agent_memory_deletions_v1",
      backupPath: "agent.memory_deletion_index",
      sensitivity: .secret
    ),
    item("knowledge", "Personal knowledge index", "user_defaults:galaxyssi_agent_knowledge", backupPath: "agent.knowledge"),
    item(
      "tasks",
      "Task history",
      "user_defaults:galaxyssi_agent_tasks",
      backupPath: "agent.tasks",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "transcript",
      "Agent transcript",
      "user_defaults:galaxyssi_agent_transcript",
      "user_defaults:galaxyssi_agent_transcript_entries",
      backupPath: "agent.transcript",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "agent_conversations",
      "Agent conversation metadata",
      "user_defaults:galaxyssi_agent_transcript",
      backupPath: "agent.agent_conversations",
      exportPolicy: .optionalSessionHistory
    ),
    item(
      "active_agent_conversation",
      "Active conversation pointer",
      "user_defaults:galaxyssi_agent_transcript",
      backupPath: "agent.active_agent_conversation",
      exportPolicy: .optionalSessionHistory,
      sensitivity: .ephemeral
    ),
    item("workflows", "Saved workflows", "user_defaults:galaxyssi_agent_workflows", backupPath: "agent.workflows"),
    item("workflow_schedules", "Workflow schedules", "user_defaults:galaxyssi_agent_workflow_schedules", backupPath: "agent.workflow_schedules"),
    item("workflow_triggers", "Workflow triggers", "user_defaults:galaxyssi_agent_workflow_triggers", backupPath: "agent.workflow_triggers"),
    item(
      "workflow_history",
      "Workflow execution history",
      "user_defaults:galaxyssi_agent_workflow_execution_history",
      backupPath: "agent.workflow_execution_history"
    ),
    item("safety", "Safety and execution policy", "user_defaults:galaxyssi_agent_safety", backupPath: "agent.safety"),
    item(
      "custom_devices",
      "Custom device connectors and credentials",
      "user_defaults:galaxyssi_custom_device_connectors",
      "keychain:custom_device_connectors",
      backupPath: "agent.custom_device_connectors",
      sensitivity: .secret
    ),
    item("personal_asi", "Personal ASI world, graph, event, and autonomy state", "user_defaults:galaxyssi_global_super_agent", backupPath: "agent.global_super_agent"),
    item("self_model", "Learned Agent self model", "user_defaults:galaxyssi_agent_self_model", backupPath: "agent.agent_self_model"),
    item("model_planner", "Model planner settings", "user_defaults:galaxyssi_agent_model_planner", backupPath: "agent.model_planner"),
    item("voice_assistant", "Wake, ASR, and TTS settings", "user_defaults:galaxyssi_voice_assistant", backupPath: "agent.voice_assistant"),
    item(
      "home_assistant",
      "Home Assistant endpoint and access token",
      "user_defaults:galaxyssi_home_assistant",
      "keychain:home_assistant",
      backupPath: "agent.home_assistant",
      sensitivity: .secret
    ),
    localOnly("permission_grants", "Host permission grants", "user_defaults:galaxyssi_permission_grants_v1", .secret),
    localOnly("policy_firewall_replay", "External request replay claims", "user_defaults:galaxyssi_policy_firewall_replay_v1", .secret),
    localOnly("policy_firewall_audit", "External request policy decisions", "user_defaults:galaxyssi_policy_firewall_audit_v1", .ephemeral),
    localOnly("cross_team_delegations", "Isolated cross-team delegation envelopes and receipts", "user_defaults:galaxyssi_cross_team_delegations_v1", .ephemeral),
    localOnly("agent_reputation_ledger", "Signed Agent execution receipts and independent attestations", "user_defaults:galaxyssi_agent_reputation_ledger_v1", .personal),
    localOnly("run_start_receipts", "Cross-end idempotency receipts", "user_defaults:galaxyssi_run_start_receipts_v1", .ephemeral),
    localOnly("provider_health", "Per-runtime health and circuit state", "user_defaults:galaxyssi_agent_provider_health", .ephemeral),
    localOnly("run_workspaces", "Active Run workspaces and checkpoints", "user_defaults:galaxyssi_agent_workspaces", .ephemeral),
    localOnly("run_events", "Run event ledger", "user_defaults:galaxyssi_agent_runs", .ephemeral),
    localOnly("data_disclosure_ledger", "Model and Agent data-flow metadata and destination blocks", "files:AgentDataDisclosure/agent-data-disclosure-ledger.json", .secret),
    localOnly("connector_responses", "Pending connector responses", "user_defaults:galaxyssi_agent_connector_responses", .ephemeral),
    localOnly("observation_context", "Recently observed Agent context", "user_defaults:galaxyssi_agent_observation_context_v1", .ephemeral),
    localOnly("mcp_credentials", "MCP connections and credentials", "user_defaults:galaxyssi_mcp_connections", .secret),
    localOnly("mcp_tool_audit", "Redacted MCP permission decisions and tool receipts", "user_defaults:galaxyssi_mcp_tool_audit", .ephemeral),
    localOnly("mcp_packages", "Installed MCP packages", "user_defaults:galaxyssi_mcp_packages", .secret),
    localOnly("installed_skills", "Installed executable Skill packages", "user_defaults:galaxyssi_agent_skills", .secret),
    localOnly("link_delivery", "Signal Link outbox and inbox receipts", "user_defaults:galaxyssi_link_delivery_v1", .ephemeral),
    localOnly("runtime_files", "On-device Linux workspaces, exports, downloads, and caches", "files:agent-runtime", .ephemeral)
  ]

  static func backupManifest(
    includeContacts: Bool,
    includeSessionHistory: Bool
  ) -> AgentPrivateDataBackupManifest {
    let included = descriptors.filter {
      shouldExport(
        descriptor: $0,
        includeContacts: includeContacts,
        includeSessionHistory: includeSessionHistory
      )
    }
    let includedIds = Set(included.map(\.id))
    let excluded = descriptors.filter { !includedIds.contains($0.id) }
    return AgentPrivateDataBackupManifest(
      policyVersion: policyVersion,
      encryptedContainerRequired: true,
      privateModeExported: false,
      pausedTrackingExported: false,
      identityRotatedOnReset: true,
      includedStoreIds: included.map(\.id),
      secretStoreIds: included.filter { $0.sensitivity == .secret }.map(\.id),
      excludedStoreIds: excluded.map(\.id),
      eraseStoreIds: descriptors.map(\.id)
    )
  }

  static func shouldExport(
    descriptor: AgentPrivateDataDescriptor,
    includeContacts: Bool,
    includeSessionHistory: Bool
  ) -> Bool {
    switch descriptor.exportPolicy {
    case .alwaysEncrypted:
      return true
    case .optionalContacts:
      return includeContacts
    case .optionalSessionHistory:
      return includeSessionHistory
    case .neverExport:
      return false
    }
  }

  static func audit() -> AgentPrivateDataInventoryAudit {
    var idCounts: [String: Int] = [:]
    descriptors.forEach { idCounts[$0.id, default: 0] += 1 }
    return AgentPrivateDataInventoryAudit(
      duplicateIds: Set(idCounts.filter { $0.value > 1 }.map(\.key)),
      descriptorsWithoutStorage: Set(descriptors.filter { $0.storageIds.isEmpty }.map(\.id)),
      exportedDescriptorsWithoutPath: Set(descriptors.filter {
        $0.exportPolicy != .neverExport && $0.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.id)),
      nonExportedDescriptorsWithPath: Set(descriptors.filter {
        $0.exportPolicy == .neverExport && !$0.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.map(\.id)),
      identityRotationCount: descriptors.filter { $0.erasePolicy == .deleteAndRotateIdentity }.count
    )
  }

  private static func item(
    _ id: String,
    _ category: String,
    _ storageIds: String...,
    backupPath: String,
    exportPolicy: AgentPrivateDataExportPolicy = .alwaysEncrypted,
    sensitivity: AgentPrivateDataSensitivity = .personal,
    erasePolicy: AgentPrivateDataErasePolicy = .delete
  ) -> AgentPrivateDataDescriptor {
    AgentPrivateDataDescriptor(
      id: id,
      category: category,
      storageIds: Set(storageIds),
      backupPath: backupPath,
      exportPolicy: exportPolicy,
      sensitivity: sensitivity,
      erasePolicy: erasePolicy
    )
  }

  private static func localOnly(
    _ id: String,
    _ category: String,
    _ storageId: String,
    _ sensitivity: AgentPrivateDataSensitivity
  ) -> AgentPrivateDataDescriptor {
    AgentPrivateDataDescriptor(
      id: id,
      category: category,
      storageIds: [storageId],
      exportPolicy: .neverExport,
      sensitivity: sensitivity
    )
  }
}

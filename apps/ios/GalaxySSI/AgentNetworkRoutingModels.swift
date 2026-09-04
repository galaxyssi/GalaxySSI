import Foundation

enum AgentDeliveryMode: String, Codable, CaseIterable, Identifiable {
  case respond = "RESPOND"
  case observe = "OBSERVE"
  case ignore = "IGNORE"

  var id: String { rawValue }
}

enum AgentRoutingMode: String, Codable, CaseIterable, Identifiable {
  case balanced = "BALANCED"
  case fast = "FAST"
  case economy = "ECONOMY"
  case quality = "QUALITY"
  case `private` = "PRIVATE"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRoutingMode {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .balanced
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

enum AgentDataSensitivity: String, Codable, CaseIterable, Identifiable {
  case `public` = "PUBLIC"
  case personal = "PERSONAL"
  case confidential = "CONFIDENTIAL"
  case restricted = "RESTRICTED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentDataSensitivity {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
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

enum AgentExecutionHorizon: String, Codable, CaseIterable, Identifiable {
  case interactive = "INTERACTIVE"
  case background = "BACKGROUND"
  case longRunning = "LONG_RUNNING"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentExecutionHorizon {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .interactive
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

struct AgentTaskRequirements: Codable, Equatable {
  var capabilities: Set<AgentCapability>
  var mode: AgentRoutingMode
  var liveDataRequired: Bool
  var localOnly: Bool
  var complexReasoning: Bool
  var estimatedInputTokens: Int
  var dataSensitivity: AgentDataSensitivity
  var executionHorizon: AgentExecutionHorizon

  init(
    capabilities: Set<AgentCapability> = [],
    mode: AgentRoutingMode = .balanced,
    liveDataRequired: Bool = false,
    localOnly: Bool = false,
    complexReasoning: Bool = false,
    estimatedInputTokens: Int = 0,
    dataSensitivity: AgentDataSensitivity = .personal,
    executionHorizon: AgentExecutionHorizon = .interactive
  ) {
    self.capabilities = capabilities
    self.mode = mode
    self.liveDataRequired = liveDataRequired
    self.localOnly = localOnly
    self.complexReasoning = complexReasoning
    self.estimatedInputTokens = max(0, estimatedInputTokens)
    self.dataSensitivity = dataSensitivity
    self.executionHorizon = executionHorizon
  }

  enum CodingKeys: String, CodingKey {
    case capabilities
    case mode
    case liveDataRequired = "live_data_required"
    case localOnly = "local_only"
    case complexReasoning = "complex_reasoning"
    case estimatedInputTokens = "estimated_input_tokens"
    case dataSensitivity = "data_sensitivity"
    case executionHorizon = "execution_horizon"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedCapabilities = try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .capabilities) ?? []
    capabilities = decodedCapabilities
    mode = try container.decodeIfPresent(AgentRoutingMode.self, forKey: .mode) ?? .balanced
    liveDataRequired = try container.decodeIfPresent(Bool.self, forKey: .liveDataRequired) ??
      decodedCapabilities.contains(.liveData)
    localOnly = try container.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
    complexReasoning = try container.decodeIfPresent(Bool.self, forKey: .complexReasoning) ?? false
    estimatedInputTokens = max(0, try container.decodeIfPresent(Int.self, forKey: .estimatedInputTokens) ?? 0)
    dataSensitivity = try container.decodeIfPresent(AgentDataSensitivity.self, forKey: .dataSensitivity) ?? .personal
    executionHorizon = try container.decodeIfPresent(AgentExecutionHorizon.self, forKey: .executionHorizon) ??
      .interactive
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(capabilities, forKey: .capabilities)
    try container.encode(mode, forKey: .mode)
    try container.encode(liveDataRequired, forKey: .liveDataRequired)
    try container.encode(localOnly, forKey: .localOnly)
    try container.encode(complexReasoning, forKey: .complexReasoning)
    try container.encode(estimatedInputTokens, forKey: .estimatedInputTokens)
    try container.encode(dataSensitivity, forKey: .dataSensitivity)
    try container.encode(executionHorizon, forKey: .executionHorizon)
  }
}

struct AgentResourceDescriptor: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var type: AgentResourceType
  var location: AgentResourceLocation
  var status: AgentConnectorStatus
  var capabilities: Set<AgentCapability>
  var cost: AgentResourceCost
  var latency: AgentResourceLatency
  var quality: AgentResourceQuality
  var supportsTools: Bool
  var targetId: String
  var trust: AgentResourceTrust
  var energy: AgentResourceEnergy
  var contextWindowTokens: Int
  var supportsStreaming: Bool
  var supportsBackground: Bool
  var activeTasks: Int
  var maxParallelTasks: Int
  var failureDomain: String
  var providerProfile: ProviderProfile?

  init(
    id: String,
    title: String,
    type: AgentResourceType,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    capabilities: Set<AgentCapability>,
    cost: AgentResourceCost,
    latency: AgentResourceLatency,
    quality: AgentResourceQuality,
    supportsTools: Bool,
    targetId: String = "",
    trust: AgentResourceTrust = .unknown,
    energy: AgentResourceEnergy = .low,
    contextWindowTokens: Int = 8_192,
    supportsStreaming: Bool = false,
    supportsBackground: Bool = false,
    activeTasks: Int = 0,
    maxParallelTasks: Int = 1,
    failureDomain: String = "",
    providerProfile: ProviderProfile? = nil
  ) {
    self.id = id
    self.title = title
    self.type = type
    self.location = location
    self.status = status
    self.capabilities = capabilities
    self.cost = cost
    self.latency = latency
    self.quality = quality
    self.supportsTools = supportsTools
    self.targetId = targetId
    self.trust = trust
    self.energy = energy
    self.contextWindowTokens = max(0, contextWindowTokens)
    self.supportsStreaming = supportsStreaming
    self.supportsBackground = supportsBackground
    self.activeTasks = max(0, activeTasks)
    self.maxParallelTasks = max(1, maxParallelTasks)
    self.failureDomain = failureDomain
    self.providerProfile = providerProfile
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case type
    case location
    case status
    case capabilities
    case cost
    case latency
    case quality
    case supportsTools = "supports_tools"
    case targetId = "target_id"
    case trust
    case energy
    case contextWindowTokens = "context_window_tokens"
    case supportsStreaming = "supports_streaming"
    case supportsBackground = "supports_background"
    case activeTasks = "active_tasks"
    case maxParallelTasks = "max_parallel_tasks"
    case failureDomain = "failure_domain"
    case providerProfile = "provider_profile"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      type: try container.decodeIfPresent(AgentResourceType.self, forKey: .type) ?? .cloudModel,
      location: try container.decodeIfPresent(AgentResourceLocation.self, forKey: .location) ?? .cloud,
      status: try container.decodeIfPresent(AgentConnectorStatus.self, forKey: .status) ?? .disconnected,
      capabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .capabilities) ?? [],
      cost: ProviderProfileCatalog.cost(try container.decodeIfPresent(String.self, forKey: .cost), fallback: .free),
      latency: ProviderProfileCatalog.latency(
        try container.decodeIfPresent(String.self, forKey: .latency),
        fallback: .normal
      ),
      quality: ProviderProfileCatalog.quality(
        try container.decodeIfPresent(String.self, forKey: .quality),
        fallback: .standard
      ),
      supportsTools: try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? false,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      trust: ProviderProfileCatalog.trust(try container.decodeIfPresent(String.self, forKey: .trust), fallback: .unknown),
      energy: try container.decodeIfPresent(AgentResourceEnergy.self, forKey: .energy) ?? .low,
      contextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens) ?? 8_192,
      supportsStreaming: try container.decodeIfPresent(Bool.self, forKey: .supportsStreaming) ?? false,
      supportsBackground: try container.decodeIfPresent(Bool.self, forKey: .supportsBackground) ?? false,
      activeTasks: try container.decodeIfPresent(Int.self, forKey: .activeTasks) ?? 0,
      maxParallelTasks: try container.decodeIfPresent(Int.self, forKey: .maxParallelTasks) ?? 1,
      failureDomain: try container.decodeIfPresent(String.self, forKey: .failureDomain) ?? "",
      providerProfile: try container.decodeIfPresent(ProviderProfile.self, forKey: .providerProfile)
    )
  }
}

struct AgentRuntimeEnvironment: Codable, Equatable {
  var batteryPercent: Int
  var charging: Bool
  var powerSaveMode: Bool
  var networkAvailable: Bool
  var networkValidated: Bool
  var networkMetered: Bool
  var appMemoryBytes: Int64
  var availableMemoryBytes: Int64

  init(
    batteryPercent: Int = -1,
    charging: Bool = false,
    powerSaveMode: Bool = false,
    networkAvailable: Bool = false,
    networkValidated: Bool = false,
    networkMetered: Bool = false,
    appMemoryBytes: Int64 = 0,
    availableMemoryBytes: Int64 = 0
  ) {
    self.batteryPercent = batteryPercent
    self.charging = charging
    self.powerSaveMode = powerSaveMode
    self.networkAvailable = networkAvailable
    self.networkValidated = networkValidated
    self.networkMetered = networkMetered
    self.appMemoryBytes = max(0, appMemoryBytes)
    self.availableMemoryBytes = max(0, availableMemoryBytes)
  }

  enum CodingKeys: String, CodingKey {
    case batteryPercent = "battery_percent"
    case charging
    case powerSaveMode = "power_save_mode"
    case networkAvailable = "network_available"
    case networkValidated = "network_validated"
    case networkMetered = "network_metered"
    case appMemoryBytes = "app_memory_bytes"
    case availableMemoryBytes = "available_memory_bytes"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      batteryPercent: try container.decodeIfPresent(Int.self, forKey: .batteryPercent) ?? -1,
      charging: try container.decodeIfPresent(Bool.self, forKey: .charging) ?? false,
      powerSaveMode: try container.decodeIfPresent(Bool.self, forKey: .powerSaveMode) ?? false,
      networkAvailable: try container.decodeIfPresent(Bool.self, forKey: .networkAvailable) ?? false,
      networkValidated: try container.decodeIfPresent(Bool.self, forKey: .networkValidated) ?? false,
      networkMetered: try container.decodeIfPresent(Bool.self, forKey: .networkMetered) ?? false,
      appMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .appMemoryBytes) ?? 0,
      availableMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .availableMemoryBytes) ?? 0
    )
  }
}

struct AgentResourceCandidate: Codable, Equatable {
  var resource: AgentResourceDescriptor
  var score: Int
  var reasons: [String]

  init(resource: AgentResourceDescriptor, score: Int, reasons: [String] = []) {
    self.resource = resource
    self.score = score
    self.reasons = reasons
  }
}

struct AgentRoutingDecision: Codable, Equatable {
  var requirements: AgentTaskRequirements
  var primary: AgentResourceCandidate?
  var fallbacks: [AgentResourceCandidate]
  var environment: AgentRuntimeEnvironment
  var catalog: [AgentResourceDescriptor]
  var taskBudget: AgentTaskBudget

  var orderedTargetIds: [String] {
    var ids: [String] = []
    if let primaryId = primary?.resource.targetId, !primaryId.isEmpty {
      ids.append(primaryId)
    }
    ids.append(contentsOf: fallbacks.map(\.resource.targetId).filter { !$0.isEmpty })
    return ids
  }

  init(
    requirements: AgentTaskRequirements,
    primary: AgentResourceCandidate?,
    fallbacks: [AgentResourceCandidate] = [],
    environment: AgentRuntimeEnvironment = AgentRuntimeEnvironment(),
    catalog: [AgentResourceDescriptor] = [],
    taskBudget: AgentTaskBudget = .default
  ) {
    self.requirements = requirements
    self.primary = primary
    self.fallbacks = fallbacks
    self.environment = environment
    self.catalog = catalog
    self.taskBudget = taskBudget
  }

  enum CodingKeys: String, CodingKey {
    case requirements
    case primary
    case fallbacks
    case environment
    case catalog
    case taskBudget = "task_budget"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      requirements: try container.decodeIfPresent(AgentTaskRequirements.self, forKey: .requirements) ??
        AgentTaskRequirements(),
      primary: try container.decodeIfPresent(AgentResourceCandidate.self, forKey: .primary),
      fallbacks: try container.decodeIfPresent([AgentResourceCandidate].self, forKey: .fallbacks) ?? [],
      environment: try container.decodeIfPresent(AgentRuntimeEnvironment.self, forKey: .environment) ??
        AgentRuntimeEnvironment(),
      catalog: try container.decodeIfPresent([AgentResourceDescriptor].self, forKey: .catalog) ?? [],
      taskBudget: try container.decodeIfPresent(AgentTaskBudget.self, forKey: .taskBudget) ?? .default
    )
  }
}

struct AgentConnectorRouteSelection: Codable, Equatable {
  var target: AgentCallableTarget
  var decision: AgentRoutingDecision?
}

struct AgentConnectorFallbackSelection: Equatable {
  var resourceId: String
  var remainingResourceIds: [String]
  var deferredRetryIds: [String]
  var retriedResourceIds: Set<String>
}

/// Preserves the original Auto route while incorporating connectors that became
/// available after the plan was persisted.
enum AgentConnectorFallbackTrail {
  static func mergeAvailable(
    rememberedResourceIds: [String],
    currentResourceIds: [String],
    failedResourceId: String
  ) -> [String] {
    let failed = failedResourceId.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized(rememberedResourceIds + currentResourceIds).filter { $0 != failed }
  }

  static func selectNext(
    failedResourceId: String,
    remainingResourceIds: [String],
    deferredRetryIds: [String],
    retriedResourceIds: Set<String>,
    retryFailedResource: Bool
  ) -> AgentConnectorFallbackSelection? {
    let remaining = normalized(remainingResourceIds)
    let retried = Set(normalized(Array(retriedResourceIds)))
    var deferred = normalized(deferredRetryIds)
    let failed = failedResourceId.trimmingCharacters(in: .whitespacesAndNewlines)
    if retryFailedResource,
       !failed.isEmpty,
       !retried.contains(failed),
       !deferred.contains(failed),
       !remaining.contains(failed) {
      deferred.append(failed)
    }

    if let next = remaining.first {
      return AgentConnectorFallbackSelection(
        resourceId: next,
        remainingResourceIds: Array(remaining.dropFirst()),
        deferredRetryIds: deferred,
        retriedResourceIds: retried
      )
    }
    guard let retry = deferred.first(where: { !retried.contains($0) }) else { return nil }
    return AgentConnectorFallbackSelection(
      resourceId: retry,
      remainingResourceIds: [],
      deferredRetryIds: deferred.filter { $0 != retry },
      retriedResourceIds: retried.union([retry])
    )
  }

  static func parse(_ value: String) -> [String] {
    normalized(value.split(separator: ",").map(String.init))
  }

  static func encode<S: Sequence>(_ values: S) -> String where S.Element == String {
    normalized(Array(values)).joined(separator: ",")
  }

  private static func normalized(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return Array(
      values.lazy
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
        .prefix(12)
    )
  }
}

enum AgentConnectorRouteSelector {
  static func isDeliverable(_ target: AgentCallableTarget?) -> Bool {
    guard let target else { return false }
    return target.status == .available ||
      (target.status == .disconnected && hasReasoningCapability(target))
  }

  static func select(
    targets: [AgentCallableTarget],
    decision: AgentRoutingDecision?,
    preferredTargetId: String = "",
    goal: String = ""
  ) -> AgentConnectorRouteSelection? {
    let reasoningTargets = targets.filter(hasReasoningCapability)
    var eligible = reasoningTargets.filter { $0.status == .available }
    if eligible.isEmpty {
      eligible = reasoningTargets.filter(isDeliverable)
    }
    guard !eligible.isEmpty else { return nil }

    let eligibleById = eligible.reduce(into: [String: AgentCallableTarget]()) { values, target in
      values[target.id] = target
    }
    let preferredTarget = preferredTargetId.isEmpty ? nil : eligibleById[preferredTargetId]
    let baselineTarget = preferredTarget ?? defaultTarget(eligible)
    var routingDecision = decision
    if routingDecision == nil, !goal.isBlank {
      routingDecision = AgentQualityRoutingService.baselineDecision(
        goal: goal,
        targets: eligible,
        primaryTargetId: baselineTarget.id
      )
    }
    if let current = routingDecision, !goal.isBlank {
      routingDecision = AgentQualityRoutingService.adjustedDecision(goal: goal, decision: current)
    }
    let decisionCandidates: [AgentResourceCandidate]
    if let routingDecision {
      decisionCandidates = [routingDecision.primary].compactMap { $0 } + routingDecision.fallbacks
    } else {
      decisionCandidates = []
    }
    var seenTargetIds = Set<String>()
    let routedCandidates = decisionCandidates
      .filter { eligibleById[$0.resource.targetId] != nil }
      .filter { seenTargetIds.insert($0.resource.targetId).inserted }
    let routedOrder = Dictionary(uniqueKeysWithValues: routedCandidates.enumerated().map {
      ($0.element.resource.targetId, $0.offset)
    })
    let calibratedCandidates = routedCandidates.sorted { lhs, rhs in
      let leftAdjustment = AgentSelfModelReducer.calibrationAdjustment(
        goal: goal,
        resourceId: lhs.resource.targetId,
        requirements: routingDecision?.requirements ?? AgentTaskRequirements()
      )
      let rightAdjustment = AgentSelfModelReducer.calibrationAdjustment(
        goal: goal,
        resourceId: rhs.resource.targetId,
        requirements: routingDecision?.requirements ?? AgentTaskRequirements()
      )
      let leftScore = lhs.score + leftAdjustment
      let rightScore = rhs.score + rightAdjustment
      return leftScore == rightScore
        ? (routedOrder[lhs.resource.targetId] ?? .max) < (routedOrder[rhs.resource.targetId] ?? .max)
        : leftScore > rightScore
    }
    let routedTarget = calibratedCandidates.compactMap { eligibleById[$0.resource.targetId] }.first
    let selectedTarget = preferredTarget ?? routedTarget ?? baselineTarget

    guard let routingDecision else {
      return AgentConnectorRouteSelection(target: selectedTarget, decision: nil)
    }
    let selectedCandidate = calibratedCandidates.first { $0.resource.targetId == selectedTarget.id } ??
      routingDecision.catalog.first { $0.targetId == selectedTarget.id }.map { resource in
        AgentResourceCandidate(
          resource: resource,
          score: 0,
          reasons: [
            selectedTarget.status == .disconnected ?
              "recoverable_connector_status" :
              "eligible_reasoning_fallback"
          ]
        )
      }
    let connectorDecision = selectedCandidate.map { primary in
      AgentRoutingDecision(
        requirements: routingDecision.requirements,
        primary: primary,
        fallbacks: calibratedCandidates.filter { $0.resource.targetId != selectedTarget.id },
        environment: routingDecision.environment,
        catalog: routingDecision.catalog,
        taskBudget: routingDecision.taskBudget
      )
    }
    return AgentConnectorRouteSelection(target: selectedTarget, decision: connectorDecision)
  }

  private static func hasReasoningCapability(_ target: AgentCallableTarget) -> Bool {
    target.kind != .device &&
      target.capabilities.contains { capability in
        capability == .chat || capability == .reasoning || capability == .research
      }
  }

  private static func defaultTarget(_ targets: [AgentCallableTarget]) -> AgentCallableTarget {
    targets.first { $0.id == "codex" || $0.id.hasSuffix(":codex") } ??
      targets.first { $0.id == "local-llm" } ??
      targets.first { $0.kind == .model } ??
      targets.first { $0.id == "hermes" || $0.id.hasSuffix(":hermes") } ??
      targets.first { $0.capabilities.contains(.research) } ??
      targets[0]
  }
}

/// Builds the same connector target view for routing, selection, and execution.
enum AgentCallableTargetCatalog {
  static func build(
    contacts: [GalaxySSIContact],
    apiKey: (CloudModelConfig) -> String?,
    activeLocalProfiles: [LocalModelRuntimeProfile] = LocalModelRuntimeSettings.activeProfiles(),
    localModelReady: (LocalModelRuntimeProfile) -> Bool = {
      LocalModelInferenceRuntime.shared.ready(profile: $0)
    }
  ) -> [AgentCallableTarget] {
    var targets = contacts
      .filter { !$0.deleted }
      .map { target(for: $0, apiKey: apiKey) }
      .filter { !["phone", "local-system", "cloud-models"].contains($0.id) }
      .filter { $0.id != "local-llm" }
    if let profile = activeLocalProfiles.first {
      targets.append(
        AgentCallableTarget(
          id: "local-llm",
          title: profile.displayName.ifBlank(profile.id),
          kind: .model,
          status: localModelReady(profile) ? .available : .needsSetup,
          capabilities: [.chat, .reasoning, .toolUse, .localInference],
          failureDomain: "local-model",
          adapterType: "ios-local-model"
        )
      )
    }
    return targets
  }

  static func selectableAgentTargets(_ targets: [AgentCallableTarget]) -> [AgentCallableTarget] {
    let availableAgents = targets.filter { target in
      target.kind == .agent && AgentConnectorRouteSelector.isDeliverable(target)
    }
    let concreteAgentIds = Set(
      availableAgents
        .filter { $0.id.contains(":") }
        .map { $0.id.split(separator: ":").last.map(String.init) ?? $0.id }
    )
    return availableAgents
      .filter { target in
        let concreteId = target.id.split(separator: ":").last.map(String.init) ?? target.id
        return target.id.contains(":") || !concreteAgentIds.contains(concreteId)
      }
      .reduce(into: [AgentCallableTarget]()) { result, target in
        guard !result.contains(where: { $0.id == target.id }) else { return }
        result.append(target)
      }
  }

  static func preferredTargetId(
    selection: AgentModelSelection,
    targets: [AgentCallableTarget]
  ) -> String {
    guard selection.mode == .manual else { return "" }
    let targetId = selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !targetId.isEmpty else { return "" }
    // Keep the manual choice visible even when it is temporarily unavailable.
    // The execution boundary decides whether the selected target is deliverable.
    return targetId
  }

  private static func target(
    for contact: GalaxySSIContact,
    apiKey: (CloudModelConfig) -> String?
  ) -> AgentCallableTarget {
    let kind = connectorKind(for: contact)
    let status = connectorStatus(for: contact, apiKey: apiKey)
    let capabilities = connectorCapabilities(for: contact, kind: kind)
    let adapterType = contact.connectorAdapterName.ifBlank(adapterType(for: contact))
    return AgentCallableTarget(
      id: contact.id,
      title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
      kind: kind,
      status: status,
      capabilities: capabilities,
      failureDomain: failureDomain(for: contact, kind: kind),
      adapterType: adapterType,
      desktopAccessProfile: contact.connectorDesktopAccessProfile,
      providerProfile: providerProfile(
        for: contact,
        kind: kind,
        status: status,
        capabilities: capabilities,
        adapterType: adapterType
      ),
      invocationProfile: kind == .model
        ? CloudModelRequestRoutingPolicy.invocationProfile(contact)
        : contact.connectorInvocationProfile
    )
  }

  private static func connectorKind(for contact: GalaxySSIContact) -> AgentConnectorKind {
    if contact.deliveryMode == .cloudAPI { return .model }
    if contact.type == "device" { return .device }
    return .agent
  }

  private static func connectorStatus(
    for contact: GalaxySSIContact,
    apiKey: (CloudModelConfig) -> String?
  ) -> AgentConnectorStatus {
    let setup = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if contact.deliveryMode == .cloudAPI {
      guard let model = contact.selectedCloudModel else { return .needsSetup }
      return CloudModelCredentialPolicy.isAutoRoutable(
        model: model,
        apiKey: apiKey(model),
        provider: contact.cloudProvider,
        setupStatus: contact.setupStatus
      ) ? .available : .needsSetup
    }
    if setup == "ready" || setup == "verified" { return .available }
    if setup.contains("needs") || setup == "pairing" || contact.trustState != .verified {
      return .needsSetup
    }
    return .disconnected
  }

  private static func connectorCapabilities(
    for contact: GalaxySSIContact,
    kind: AgentConnectorKind
  ) -> [AgentCapability] {
    if !contact.connectorCapabilitySet.isEmpty {
      return contact.connectorCapabilitySet.sorted { $0.rawValue < $1.rawValue }
    }
    switch kind {
    case .model:
      return [.chat, .reasoning, .toolUse, .liveData]
    case .device:
      return [.deviceControl, .appNavigation]
    case .knowledge:
      return [.knowledgeSearch]
    case .agent:
      return contact.deliveryMode.isGalaxySSILinkFamily
        ? [.chat, .reasoning, .toolUse, .taskExecution]
        : [.chat, .reasoning]
    }
  }

  private static func failureDomain(
    for contact: GalaxySSIContact,
    kind: AgentConnectorKind
  ) -> String {
    if kind == .model { return "cloud-model:\(contact.cloudProvider.ifBlank(contact.id))" }
    if !contact.desktopId.isBlank { return "desktop:\(contact.desktopId)" }
    return "contact:\(contact.id)"
  }

  private static func adapterType(for contact: GalaxySSIContact) -> String {
    switch contact.deliveryMode {
    case .cloudAPI: return "cloud-api"
    case .link: return "galaxyssi-link"
    case .pcConnector: return "pc-connector"
    case .local: return "local"
    }
  }

  private static func providerProfile(
    for contact: GalaxySSIContact,
    kind: AgentConnectorKind,
    status: AgentConnectorStatus,
    capabilities: [AgentCapability],
    adapterType: String
  ) -> ProviderProfile? {
    if contact.deliveryMode == .cloudAPI {
      return ProviderProfileCatalog.fromCloudContact(contact, status: status)
    }
    if kind == .agent, contact.deliveryMode.isGalaxySSILinkFamily {
      return ProviderProfileCatalog.fromConnectorContact(
        contact,
        status: status,
        capabilities: capabilities,
        adapterType: adapterType
      )
    }
    return nil
  }
}

enum AgentResourceCatalog {
  static func build(
    targets: [AgentCallableTarget],
    tools: [AgentSystemTool],
    nativeTools: [AgentNativeToolDescriptor] = []
  ) -> [AgentResourceDescriptor] {
    let capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
      nativeTools: nativeTools,
      systemTools: tools,
      targets: targets
    )
    let callable = targets.map(fromTarget)
    let localTools = tools.map { tool in
      let capability = capabilityMatrix.entry(source: .systemTool, id: tool.id)
      return AgentResourceDescriptor(
        id: "tool:\(tool.id)",
        title: tool.title,
        type: systemToolType(tool.id),
        location: .phone,
        status: connectorStatus(capability),
        capabilities: Set(tool.capabilities),
        cost: .free,
        latency: .instant,
        quality: .standard,
        supportsTools: true,
        trust: .phoneSystem,
        energy: .minimal,
        contextWindowTokens: 0,
        supportsStreaming: false,
        supportsBackground: false,
        maxParallelTasks: 4,
        failureDomain: "phone"
      )
    }
    let registeredNativeTools = nativeTools.map { tool in
      fromNativeTool(
        tool,
        capability: capabilityMatrix.entry(source: .nativeTool, id: tool.id)
      )
    }
    return callable + localTools + registeredNativeTools
  }

  private static func fromNativeTool(
    _ tool: AgentNativeToolDescriptor,
    capability: AgentRuntimeCapabilityEntry?
  ) -> AgentResourceDescriptor {
    AgentResourceDescriptor(
      id: "native:\(tool.id)",
      title: tool.title,
      type: nativeToolType(tool.id),
      location: .phone,
      status: connectorStatus(capability),
      capabilities: nativeCapabilities(tool),
      cost: .free,
      latency: .instant,
      quality: .standard,
      supportsTools: true,
      trust: .phoneSystem,
      energy: tool.id.contains("runtime") || tool.id.contains("ffmpeg") ? .high : .minimal,
      contextWindowTokens: 0,
      supportsStreaming: false,
      supportsBackground: tool.location == .application,
      maxParallelTasks: 4,
      failureDomain: "phone"
    )
  }

  private static func fromTarget(_ target: AgentCallableTarget) -> AgentResourceDescriptor {
    let lowerId = target.id.lowercased()
    let providerProfile = [.agent, .model].contains(target.kind) ? ProviderProfileCatalog.fromTarget(target) : nil
    let type = targetType(target, lowerId: lowerId)
    let location = location(for: type)
    let defaults = defaultProfile(for: type)
    let trust = defaultTrust(for: location)
    let contextWindow = defaultContextWindow(for: type)
    let profileFailureDomain = providerProfile?.failureDomain ?? ""
    let failureDomain = !profileFailureDomain.isEmpty
      ? profileFailureDomain
      : target.failureDomain.isEmpty ? defaultFailureDomain(targetId: target.id, location: location) : target.failureDomain

    return AgentResourceDescriptor(
      id: "target:\(target.id)",
      title: target.title,
      type: type,
      location: location,
      status: target.status,
      capabilities: Set(target.capabilities),
      cost: providerProfile?.pricing.tier ?? defaults.cost,
      latency: providerProfile?.latency ?? defaults.latency,
      quality: providerProfile?.quality ?? defaults.quality,
      supportsTools: providerProfile?.supportsTools ??
        (target.capabilities.contains(.toolUse) || target.capabilities.contains(.research)),
      targetId: target.id,
      trust: providerProfile?.trust ?? trust,
      energy: energy(for: type),
      contextWindowTokens: providerProfile?.contextWindowTokens ?? contextWindow,
      supportsStreaming: providerProfile?.supportsStreaming ?? streamingDefault(for: type),
      supportsBackground: providerProfile?.supportsBackground ?? backgroundDefault(for: type),
      maxParallelTasks: providerProfile?.maxParallelRuns ?? maxParallelTasksDefault(for: type),
      failureDomain: failureDomain,
      providerProfile: providerProfile
    )
  }

  private static func systemToolType(_ id: String) -> AgentResourceType {
    if id.hasPrefix("workflow:") || id.hasPrefix("template:") {
      return .localSkill
    }
    if id.localizedCaseInsensitiveContains("mcp") {
      return .localMcp
    }
    return .localTool
  }

  private static func nativeToolType(_ id: String) -> AgentResourceType {
    if id.contains(".mcp.") || id.hasPrefix("mcp.") {
      return .localMcp
    }
    if id.contains(".skill.") || id.hasPrefix("skill.") {
      return .localSkill
    }
    return .localTool
  }

  private static func nativeCapabilities(_ tool: AgentNativeToolDescriptor) -> Set<AgentCapability> {
    let text = ([tool.id] + Array(tool.capabilities)).joined(separator: " ").lowercased()
    var capabilities: Set<AgentCapability> = [.toolUse]
    if containsAny(text, ["web", "http", "browser", "network"]) {
      capabilities.insert(.liveData)
    }
    if containsAny(text, ["web", "research", "search"]) {
      capabilities.insert(.research)
    }
    if containsAny(text, ["workspace", "runtime", "python", "node", "compile", "ffmpeg"]) {
      capabilities.formUnion([.code, .taskExecution])
    }
    if text.contains("mcp") {
      capabilities.insert(.mcp)
    }
    if text.contains("skill") {
      capabilities.insert(.skill)
    }
    if text.contains("screen") || text.contains("ocr") {
      capabilities.insert(.screenReading)
    }
    if text.contains("clipboard") {
      capabilities.insert(.clipboard)
    }
    if text.contains("settings") {
      capabilities.insert(.systemSettings)
    }
    if text.contains("app") || text.contains("package") {
      capabilities.insert(.appNavigation)
    }
    if text.contains("alarm") || text.contains("timer") {
      capabilities.insert(.alarm)
    }
    if containsAny(text, [
      "hardware", "device", "location", "sensor", "bluetooth", "nfc", "wifi",
      "audio", "telephony", "sms", "contact", "calendar", "battery", "power", "storage"
    ]) {
      capabilities.insert(.deviceControl)
    }
    return capabilities
  }

  private static func connectorStatus(_ capability: AgentRuntimeCapabilityEntry?) -> AgentConnectorStatus {
    switch capability?.state {
    case .available:
      return .available
    case .requiresSetup:
      return .needsSetup
    case .unavailable, .blocked, nil:
      return .disconnected
    }
  }

  private static func targetType(_ target: AgentCallableTarget, lowerId: String) -> AgentResourceType {
    if lowerId == "home-assistant" {
      return .homeAssistant
    }
    if lowerId.hasPrefix("custom-device:") {
      return .customDevice
    }
    if lowerId.contains("mcp") {
      return .remoteMcp
    }
    if lowerId.contains("skill") {
      return .remoteSkill
    }
    if target.kind == .knowledge {
      return .knowledge
    }
    if target.kind == .model && (lowerId == "local-llm" || target.capabilities.contains(.localInference)) {
      return .remoteLocalModel
    }
    if target.kind == .model {
      return .cloudModel
    }
    if target.kind == .agent {
      return .remoteAgent
    }
    return .customDevice
  }

  private static func location(for type: AgentResourceType) -> AgentResourceLocation {
    switch type {
    case .onDeviceModel, .localAgent, .localTool, .localMcp, .localSkill, .knowledge:
      return .phone
    case .remoteLocalModel, .remoteAgent, .remoteMcp, .remoteSkill:
      return .trustedDesktop
    case .homeAssistant, .customDevice:
      return .privateNetwork
    case .cloudModel, .cloudMcp, .cloudSkill:
      return .cloud
    }
  }

  private static func defaultProfile(
    for type: AgentResourceType
  ) -> (cost: AgentResourceCost, latency: AgentResourceLatency, quality: AgentResourceQuality) {
    switch type {
    case .cloudModel:
      return (.medium, .normal, .frontier)
    case .remoteAgent, .remoteMcp, .remoteSkill:
      return (.low, .slow, .strong)
    case .remoteLocalModel, .homeAssistant, .customDevice:
      return (.free, .fast, .standard)
    default:
      return (.free, .instant, .standard)
    }
  }

  private static func defaultTrust(for location: AgentResourceLocation) -> AgentResourceTrust {
    switch location {
    case .phone:
      return .phoneSystem
    case .trustedDesktop:
      return .verifiedPaired
    case .privateNetwork:
      return .privateConfigured
    case .cloud:
      return .cloudConfigured
    }
  }

  private static func energy(for type: AgentResourceType) -> AgentResourceEnergy {
    switch type {
    case .onDeviceModel:
      return .high
    case .localAgent, .localMcp, .localSkill:
      return .moderate
    case .localTool, .knowledge:
      return .minimal
    default:
      return .low
    }
  }

  private static func defaultContextWindow(for type: AgentResourceType) -> Int {
    switch type {
    case .cloudModel:
      return 128_000
    case .remoteAgent:
      return 64_000
    case .remoteLocalModel, .onDeviceModel:
      return 16_000
    default:
      return 8_192
    }
  }

  private static func streamingDefault(for type: AgentResourceType) -> Bool {
    type == .cloudModel || type == .remoteAgent || type == .remoteLocalModel
  }

  private static func backgroundDefault(for type: AgentResourceType) -> Bool {
    type == .remoteAgent || type == .remoteLocalModel || type == .remoteMcp || type == .remoteSkill
  }

  private static func maxParallelTasksDefault(for type: AgentResourceType) -> Int {
    switch type {
    case .remoteAgent:
      return 4
    case .cloudModel:
      return 3
    case .remoteLocalModel:
      return 2
    default:
      return 1
    }
  }

  private static func defaultFailureDomain(targetId: String, location: AgentResourceLocation) -> String {
    switch location {
    case .phone:
      return "phone"
    case .cloud:
      return "cloud:\(targetId)"
    case .trustedDesktop:
      return "desktop:\(targetId.split(separator: ":").first.map(String.init) ?? targetId)"
    case .privateNetwork:
      return "private:\(targetId)"
    }
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }
}

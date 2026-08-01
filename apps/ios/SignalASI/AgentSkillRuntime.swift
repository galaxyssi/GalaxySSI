import Foundation

final class AgentSkillRuntime {
  private let store: AgentSkillStore
  private let availableTools: Set<String>?
  private let clock: () -> Int64

  init(
    store: AgentSkillStore = InMemoryAgentSkillStore(),
    availableNativeToolIds: [String]? = nil,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.store = store
    self.availableTools = availableNativeToolIds.map { Set($0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) }
    self.clock = clock
  }

  func validate(_ manifest: AgentSkillManifest) -> AgentSkillValidationResult {
    AgentSkillManifestValidator.validate(manifest, availableNativeToolIds: availableTools)
  }

  func validate(_ rawManifest: String) -> AgentSkillValidationResult {
    if rawManifest.data(using: .utf8)?.count ?? 0 > AgentSkillLimits.maxManifestBytes {
      return AgentSkillValidationResult(issues: [
        skillRuntimeIssue("$", "oversized_manifest", "Manifest exceeds \(AgentSkillLimits.maxManifestBytes) bytes")
      ])
    }
    guard let manifest = AgentSkillManifestCodec.decode(rawManifest) else {
      return AgentSkillValidationResult(issues: [
        skillRuntimeIssue("$", "malformed_manifest", "Manifest JSON is invalid")
      ])
    }
    return validate(manifest)
  }

  func install(_ manifest: AgentSkillManifest, enabled: Bool = true) throws -> AgentSkillInstallation {
    try validate(manifest).requireValid()
    if let existing = get(id: manifest.id, version: manifest.version) {
      if AgentSkillManifestCodec.encode(existing.manifest) != AgentSkillManifestCodec.encode(manifest) {
        throw AgentSkillConflictError(id: manifest.id, version: manifest.version)
      }
      return existing
    }
    guard store.list().count < AgentSkillLimits.maxInstalledSkills else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        skillRuntimeIssue("$", "store_full", "Agent Skill store is full")
      ]))
    }
    let now = max(clock(), 0)
    let installation = AgentSkillInstallation(
      manifest: manifest,
      enabled: enabled,
      installedAtMillis: now,
      updatedAtMillis: now
    )
    store.upsert(installation)
    return installation
  }

  func install(_ rawManifest: String, enabled: Bool = true) throws -> AgentSkillInstallation {
    try validate(rawManifest).requireValid()
    guard let manifest = AgentSkillManifestCodec.decode(rawManifest) else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        skillRuntimeIssue("$", "malformed_manifest", "Manifest JSON is invalid")
      ]))
    }
    return try install(manifest, enabled: enabled)
  }

  func installAvailable(_ manifests: [AgentSkillManifest], enabled: Bool = true) -> [AgentSkillInstallation] {
    var current = store.list()
    var accepted: [AgentSkillInstallation] = []
    for manifest in manifests where validate(manifest).isValid {
      if let existing = current.first(where: { $0.id == manifest.id && $0.version == manifest.version }) {
        if AgentSkillManifestCodec.encode(existing.manifest) == AgentSkillManifestCodec.encode(manifest) {
          accepted.append(existing)
        }
        continue
      }
      guard current.count < AgentSkillLimits.maxInstalledSkills else {
        break
      }
      let now = max(clock(), 0)
      let installation = AgentSkillInstallation(manifest: manifest, enabled: enabled, installedAtMillis: now, updatedAtMillis: now)
      current.append(installation)
      accepted.append(installation)
    }
    store.replaceAll(current)
    return accepted
  }

  func enable(id: String, version: String) throws -> AgentSkillInstallation {
    try setEnabled(id: id, version: version, enabled: true)
  }

  func disable(id: String, version: String) throws -> AgentSkillInstallation {
    try setEnabled(id: id, version: version, enabled: false)
  }

  func setAutoInvoke(id: String, version: String, enabled: Bool) throws -> AgentSkillInstallation {
    guard var current = get(id: id, version: version) else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [skillRuntimeIssue("$", "missing_skill", "Agent Skill is not installed")]))
    }
    current.autoInvokeOverride = enabled
    current.updatedAtMillis = max(current.updatedAtMillis, clock())
    store.upsert(current)
    return current
  }

  func delete(id: String, version: String) -> Bool {
    store.delete(id: id, version: version)
  }

  func list(enabledOnly: Bool = false) -> [AgentSkillInstallation] {
    store.list()
      .filter { !enabledOnly || $0.enabled }
      .sorted { left, right in
        left.id == right.id ? left.version < right.version : left.id < right.id
      }
  }

  func get(id: String, version: String) -> AgentSkillInstallation? {
    store.list().first {
      $0.id == id.trimmingCharacters(in: .whitespacesAndNewlines) &&
        $0.version == version.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  func recordUse(id: String, version: String) throws -> AgentSkillInstallation {
    guard var current = get(id: id, version: version) else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [skillRuntimeIssue("$", "missing_skill", "Agent Skill is not installed")]))
    }
    current.useCount = min(current.useCount + 1, Int64.max)
    current.lastUsedAtMillis = max(clock(), 0)
    current.updatedAtMillis = max(current.updatedAtMillis, current.lastUsedAtMillis)
    store.upsert(current)
    return current
  }

  func expand(id: String, version: String, parameters: AgentMcpJSONObject = [:]) throws -> AgentSkillExpansion {
    guard let installation = get(id: id, version: version) else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [skillRuntimeIssue("$", "missing_skill", "Agent Skill is not installed")]))
    }
    guard installation.enabled else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [skillRuntimeIssue("$", "disabled_skill", "Agent Skill is disabled")]))
    }
    return try expand(installation.manifest, parameters: parameters)
  }

  func expand(_ manifest: AgentSkillManifest, parameters: AgentMcpJSONObject = [:]) throws -> AgentSkillExpansion {
    try validate(manifest).requireValid()
    try AgentSkillValidationResult(
      issues: AgentSkillManifestValidator.validateParameters(manifest.parameters, value: .object(parameters), path: "$.parameters")
    ).requireValid()
    let ordered = try AgentSkillManifestValidator.topologicalSteps(manifest.steps)
    let resources = Dictionary(uniqueKeysWithValues: manifest.resources.map { ($0.id, $0) })
    let expanded = try ordered.map { step -> AgentSkillExpandedStep in
      let input = try AgentSkillTemplateExpander.expand(.object(step.input), parameters: parameters, resources: resources)
      guard case .object(let object) = input else {
        throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
          skillRuntimeIssue("$.steps.\(step.id).input", "invalid_input", "Expanded step input must be an object")
        ]))
      }
      guard AgentMcpJSONCodec.stringify(object).utf8.count <= 64 * 1_024 else {
        throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
          skillRuntimeIssue("$.steps.\(step.id).input", "oversized_input", "Expanded input exceeds the byte limit")
        ]))
      }
      return AgentSkillExpandedStep(id: step.id, toolId: step.toolId, input: object, dependsOn: step.dependsOn)
    }
    return AgentSkillExpansion(
      skillId: manifest.id,
      skillVersion: manifest.version,
      title: manifest.name,
      instructions: manifest.instructions,
      permissions: manifest.permissions,
      resources: resources,
      steps: expanded
    )
  }

  private func setEnabled(id: String, version: String, enabled: Bool) throws -> AgentSkillInstallation {
    guard var current = get(id: id, version: version) else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [skillRuntimeIssue("$", "missing_skill", "Agent Skill is not installed")]))
    }
    current.enabled = enabled
    current.updatedAtMillis = max(current.updatedAtMillis, clock())
    store.upsert(current)
    return current
  }
}

struct AgentSkillExpandedStep: Codable, Equatable, Identifiable {
  var id: String
  var toolId: String
  var input: AgentMcpJSONObject
  var dependsOn: [String]

  enum CodingKeys: String, CodingKey {
    case id
    case toolId = "tool_id"
    case input
    case dependsOn = "depends_on"
  }
}

struct AgentSkillExpansion: Codable, Equatable {
  var skillId: String
  var skillVersion: String
  var title: String
  var instructions: String
  var permissions: Set<String>
  var resources: [String: AgentSkillResource]
  var steps: [AgentSkillExpandedStep]

  enum CodingKeys: String, CodingKey {
    case skillId = "skill_id"
    case skillVersion = "skill_version"
    case title
    case instructions
    case permissions
    case resources
    case steps
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(skillId, forKey: .skillId)
    try container.encode(skillVersion, forKey: .skillVersion)
    try container.encode(title, forKey: .title)
    try container.encode(instructions, forKey: .instructions)
    try container.encode(permissions.sorted(), forKey: .permissions)
    try container.encode(resources, forKey: .resources)
    try container.encode(steps, forKey: .steps)
  }
}

private func skillRuntimeIssue(_ path: String, _ code: String, _ message: String) -> AgentSkillValidationIssue {
  AgentSkillValidationIssue(path: path, code: code, message: message)
}

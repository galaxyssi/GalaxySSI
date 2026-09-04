import Foundation

struct AgentSkillExecutionResult: Codable, Equatable {
  var success: Bool
  var skillId: String
  var version: String
  var message: String
  var toolResults: [AgentNativeToolResult]

  init(
    success: Bool,
    skillId: String,
    version: String,
    message: String,
    toolResults: [AgentNativeToolResult] = []
  ) {
    self.success = success
    self.skillId = String(skillId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.version = String(version.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxVersionCharacters))
    self.message = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxFeedbackCharacters))
    self.toolResults = Array(toolResults.prefix(AgentSkillLimits.maxToolCalls))
  }

  enum CodingKeys: String, CodingKey {
    case success
    case skillId = "skill_id"
    case version
    case message
    case toolResults = "tool_results"
  }
}

final class AgentSkillExecutionEngine {
  private let runtime: AgentSkillRuntime
  private let registry: AgentNativeToolRegistry
  private let contextFactory: (AgentSkillMatch, AgentSkillExpandedStep, Int, String, String) -> AgentNativeToolInvocationContext
  private let hooks: AgentNativeToolInvocationHooks

  init(
    runtime: AgentSkillRuntime,
    registry: AgentNativeToolRegistry,
    contextFactory: @escaping (AgentSkillMatch, AgentSkillExpandedStep, Int, String, String) -> AgentNativeToolInvocationContext =
      AgentSkillExecutionEngine.defaultContext,
    hooks: AgentNativeToolInvocationHooks = AgentNativeToolInvocationHooks()
  ) {
    self.runtime = runtime
    self.registry = registry
    self.contextFactory = contextFactory
    self.hooks = hooks
  }

  func execute(
    match: AgentSkillMatch,
    conversationId: String = "",
    turnId: String = ""
  ) -> AgentSkillExecutionResult {
    let expansion: AgentSkillExpansion
    do {
      expansion = try runtime.expand(id: match.installation.id, version: match.installation.version, parameters: match.parameters)
    } catch {
      return fallback(match, reason: executionMessage(error), results: [])
    }

    var results: [AgentNativeToolResult] = []
    for (index, step) in expansion.steps.enumerated() {
      guard let descriptor = registry.lookup(step.toolId)?.descriptor else {
        return fallback(match, reason: "Missing tool: \(step.toolId)", results: results)
      }
      if descriptor.risk.weight >= AgentNativeToolRisk.high.weight || descriptor.requiredConsents.contains(where: { $0.required }) {
        return fallback(match, reason: "Tool requires interactive authorization: \(step.toolId)", results: results)
      }
      var context = contextFactory(match, step, index, conversationId, turnId)
      context.grantedPermissions.formUnion(descriptor.requiredPermissions.filter(\.required).map(\.id))
      let result = registry.invoke(step.toolId, input: step.input, context: context, hooks: hooks)
      AgentIOSNativeToolHandoffPresenter.openIfNeeded(result)
      results.append(result)
      if !result.isSuccess {
        return fallback(match, reason: result.message.ifBlank(result.error?.message ?? "Skill tool failed"), results: results)
      }
    }

    do {
      _ = try runtime.recordUse(id: match.installation.id, version: match.installation.version)
    } catch {
      return fallback(match, reason: executionMessage(error), results: results)
    }
    let finalMessage = results.last.map { AgentMcpJSONCodec.stringify($0.output) }?.ifBlank("Skill completed") ?? "Skill completed"
    return AgentSkillExecutionResult(
      success: true,
      skillId: match.installation.id,
      version: match.installation.version,
      message: finalMessage,
      toolResults: results
    )
  }

  private func fallback(
    _ match: AgentSkillMatch,
    reason: String,
    results: [AgentNativeToolResult]
  ) -> AgentSkillExecutionResult {
    AgentSkillExecutionResult(
      success: false,
      skillId: match.installation.id,
      version: match.installation.version,
      message: reason.ifBlank("Skill failed"),
      toolResults: results
    )
  }

  private func executionMessage(_ error: Error) -> String {
    if let validation = error as? AgentSkillValidationError {
      return validation.result.issues.map { "\($0.path) [\($0.code)] \($0.message)" }.joined(separator: "; ")
    }
    if let conflict = error as? AgentSkillConflictError {
      return "Agent Skill \(conflict.id)@\(conflict.version) conflicts with installed content"
    }
    return error.localizedDescription.ifBlank(String(describing: error))
  }

  private static func defaultContext(
    match: AgentSkillMatch,
    step: AgentSkillExpandedStep,
    index: Int,
    conversationId: String,
    turnId: String
  ) -> AgentNativeToolInvocationContext {
    return AgentNativeToolInvocationContext(
      invocationId: "\(match.installation.id)-\(match.installation.version)-\(step.id)-\(index + 1)",
      conversationId: conversationId,
      turnId: turnId,
      callerId: "galaxyssi.agent_skill",
      grantedPermissions: match.installation.manifest.permissions,
      attributes: [
        "skill_id": match.installation.id,
        "skill_version": match.installation.version,
        "skill_step_id": step.id,
        "skill_explicit_match": match.explicit ? "true" : "false"
      ]
    )
  }
}

final class AgentSkillVersionManager {
  private let runtime: AgentSkillRuntime

  init(_ runtime: AgentSkillRuntime) {
    self.runtime = runtime
  }

  func buildUpgrade(base: AgentSkillInstallation, improvedRuns: [AgentRecordedRun]) throws -> AgentSkillManifest {
    guard let latest = improvedRuns.last else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        issueForSkillExecution("$", "improved_run_required", "An improved run is required")
      ]))
    }
    let feedback = improvedRuns.flatMap(\.userFeedback)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .stableDistinctForSkillExecution()
      .joined(separator: "; ")
    let instructions = [base.manifest.instructions, feedback]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n")
    let tests = Array((base.manifest.tests + [
      AgentSkillTestCase(
        id: "regression_\(base.manifest.tests.count + 1)",
        input: ["request": .string(latest.originalRequest)],
        expectedToolIds: base.manifest.nativeTools
      )
    ]).prefix(AgentSkillLimits.maxTests))
    let manifest = AgentSkillManifest(
      id: base.manifest.id,
      name: base.manifest.name,
      version: incrementMinor(base.version),
      summary: base.manifest.summary,
      instructions: String(instructions.prefix(AgentSkillLimits.maxInstructionsCharacters)),
      nativeTools: base.manifest.nativeTools,
      permissions: base.manifest.permissions,
      mcpCatalogIds: base.manifest.mcpCatalogIds,
      resources: base.manifest.resources,
      parameters: base.manifest.parameters,
      steps: base.manifest.steps,
      formatVersion: base.manifest.formatVersion,
      description: base.manifest.description,
      author: base.manifest.author,
      source: base.manifest.source,
      autoInvoke: base.manifest.autoInvoke,
      triggerExamples: base.manifest.triggerExamples,
      negativeExamples: base.manifest.negativeExamples,
      renderSpec: latest.renderSpec.isEmpty ? base.manifest.renderSpec : latest.renderSpec,
      tests: tests
    )
    try runtime.validate(manifest).requireValid()
    return manifest
  }

  func upgrade(base: AgentSkillInstallation, improvedRuns: [AgentRecordedRun]) throws -> AgentSkillInstallation {
    try runtime.install(buildUpgrade(base: base, improvedRuns: improvedRuns))
  }

  func rollback(id: String, currentVersion: String) throws -> AgentSkillInstallation {
    let previous = runtime.list()
      .filter { $0.id == id && compareVersions($0.version, currentVersion) < 0 }
      .max(by: { compareVersions($0.version, $1.version) < 0 })
    guard let previous else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        issueForSkillExecution("$", "missing_previous_skill", "No previous Skill version is available")
      ]))
    }
    for installation in runtime.list().filter({ $0.id == id }) {
      _ = try runtime.disable(id: installation.id, version: installation.version)
    }
    return try runtime.enable(id: previous.id, version: previous.version)
  }

  private func incrementMinor(_ version: String) -> String {
    var parts = version.split(separator: ".").map { Int(String($0)) ?? 0 }
    while parts.count < 3 {
      parts.append(0)
    }
    return "\(parts[0]).\(parts[1] + 1).0"
  }

  private func compareVersions(_ left: String, _ right: String) -> Int {
    let leftParts = left.split(separator: ".").map { Int(String($0)) ?? 0 }
    let rightParts = right.split(separator: ".").map { Int(String($0)) ?? 0 }
    for index in 0..<3 {
      let delta = (leftParts[safeForSkillExecution: index] ?? 0) - (rightParts[safeForSkillExecution: index] ?? 0)
      if delta != 0 {
        return delta
      }
    }
    return 0
  }
}

private func issueForSkillExecution(_ path: String, _ code: String, _ message: String) -> AgentSkillValidationIssue {
  AgentSkillValidationIssue(path: path, code: code, message: message)
}

private extension Array where Element: Hashable {
  func stableDistinctForSkillExecution() -> [Element] {
    var seen: Set<Element> = []
    var values: [Element] = []
    for item in self where seen.insert(item).inserted {
      values.append(item)
    }
    return values
  }
}

private extension Array {
  subscript(safeForSkillExecution index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

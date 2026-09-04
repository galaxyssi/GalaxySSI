import Foundation

final class GlobalAutonomousSkillHost {
  typealias RuntimeProvider = (Set<String>) -> AgentSkillRuntime?

  private let runtimeProvider: RuntimeProvider

  init(runtimeProvider: @escaping RuntimeProvider) {
    self.runtimeProvider = runtimeProvider
  }

  func descriptors(nativeRegistry: AgentNativeToolRegistry) -> [AgentNativeToolDescriptor] {
    snapshots(nativeRegistry: nativeRegistry)
      .map(\.descriptor)
      .sorted { $0.id < $1.id }
  }

  func isSkillToolId(_ toolId: String) -> Bool {
    toolId.hasPrefix(Self.toolIdPrefix)
  }

  func descriptor(
    toolId: String,
    nativeRegistry: AgentNativeToolRegistry
  ) -> AgentNativeToolDescriptor? {
    snapshot(toolId: toolId, nativeRegistry: nativeRegistry)?.descriptor
  }

  func validateInput(
    toolId: String,
    input: AgentMcpJSONObject,
    nativeRegistry: AgentNativeToolRegistry
  ) -> AgentNativeValidationResult {
    guard let descriptor = descriptor(toolId: toolId, nativeRegistry: nativeRegistry) else {
      return .invalid(
        path: "$",
        code: "unknown_skill",
        message: "No autonomous Skill is registered with id \(toolId)"
      )
    }
    return AgentNativeJsonSchemaValidator.validateObject(
      schema: descriptor.inputSchema,
      object: input
    )
  }

  func invoke(
    toolId: String,
    input: AgentMcpJSONObject,
    nativeRegistry: AgentNativeToolRegistry,
    context: AgentNativeToolInvocationContext,
    hooks: AgentNativeToolInvocationHooks = AgentNativeToolInvocationHooks()
  ) -> AgentNativeToolResult {
    guard let snapshot = snapshot(toolId: toolId, nativeRegistry: nativeRegistry) else {
      return Self.syntheticResult(
        toolId: toolId,
        input: input,
        context: context,
        hooks: hooks,
        status: .unavailable,
        message: "The installed Skill is disabled, removed, or no longer eligible for autonomous use",
        error: AgentNativeToolError(
          code: "skill_unavailable",
          message: "The installed Skill is disabled, removed, or no longer eligible for autonomous use"
        )
      )
    }
    do {
      let registry = try AgentNativeToolRegistry().registerExecutable(
        definition(snapshot: snapshot, nativeRegistry: nativeRegistry)
      )
      return registry.invoke(
        toolId,
        input: input,
        context: context,
        hooks: hooks
      )
    } catch {
      let message = error.localizedDescription.ifBlank(String(describing: error))
      return Self.syntheticResult(
        toolId: toolId,
        input: input,
        context: context,
        hooks: hooks,
        status: .failed,
        message: message,
        error: AgentNativeToolError(code: "skill_adapter_failed", message: message)
      )
    }
  }

  func toolId(skillId: String, version: String) -> String {
    Self.toolIdPrefix + String(GlobalAgentText.stableKey(skillId, version).prefix(24))
  }

  private func snapshots(nativeRegistry: AgentNativeToolRegistry) -> [SkillSnapshot] {
    let nativeDescriptors = Dictionary(uniqueKeysWithValues: nativeRegistry.descriptors().map { ($0.id, $0) })
    guard let runtime = runtime(nativeToolIds: Set(nativeDescriptors.keys)) else {
      return []
    }
    return runtime.list(enabledOnly: true)
      .filter(\.autoInvoke)
      .filter { installation in
        !installation.manifest.steps.contains { $0.toolId == Self.agentOrchestrationToolId }
      }
      .compactMap { installation in
        snapshot(
          runtime: runtime,
          installation: installation,
          nativeDescriptors: nativeDescriptors
        )
      }
  }

  private func snapshot(
    toolId: String,
    nativeRegistry: AgentNativeToolRegistry
  ) -> SkillSnapshot? {
    snapshots(nativeRegistry: nativeRegistry).first { $0.descriptor.id == toolId }
  }

  private func snapshot(
    runtime: AgentSkillRuntime,
    installation: AgentSkillInstallation,
    nativeDescriptors: [String: AgentNativeToolDescriptor]
  ) -> SkillSnapshot? {
    let manifest = installation.manifest
    let stepDescriptors = manifest.steps.compactMap { nativeDescriptors[$0.toolId] }
    let missingToolIds = Array(Set(manifest.steps.map(\.toolId).filter { nativeDescriptors[$0] == nil })).sorted()
    let unavailable = stepDescriptors.filter { $0.availability.status != .available }
    let availability: AgentNativeToolAvailability
    if !missingToolIds.isEmpty {
      availability = AgentNativeToolAvailability(
        status: .unavailable,
        reason: "Skill dependency is not registered: \(missingToolIds.joined(separator: ", "))"
      )
    } else if let firstUnavailable = unavailable.first {
      availability = AgentNativeToolAvailability(
        status: .unavailable,
        reason: firstUnavailable.availability.reason.ifBlank("A Skill dependency is not currently available")
      )
    } else {
      availability = .available
    }

    do {
      let descriptor = try AgentNativeToolDescriptor(
        id: toolId(skillId: manifest.id, version: manifest.version),
        version: Self.adapterVersion,
        title: clean(manifest.name, maximum: 160),
        description: skillDescription(manifest),
        location: .application,
        inputSchema: manifest.parameters.globalAutonomousNativeSchema(),
        outputSchema: Self.outputSchema(),
        risk: stepDescriptors.max(by: { $0.risk.weight < $1.risk.weight })?.risk ??
          (missingToolIds.isEmpty ? .low : .high),
        capabilities: Set(["skill.workflow", "skill.\(manifest.id)"])
          .union(stepDescriptors.flatMap(\.capabilities)),
        requiredPermissions: Self.mergePermissions(stepDescriptors),
        requiredConsents: Self.mergeConsents(stepDescriptors),
        timeoutMillis: Self.aggregateTimeout(stepDescriptors),
        idempotency: .idempotencyKeyRequired,
        availability: availability
      )
      return SkillSnapshot(runtime: runtime, installation: installation, descriptor: descriptor)
    } catch {
      return nil
    }
  }

  private func definition(
    snapshot: SkillSnapshot,
    nativeRegistry: AgentNativeToolRegistry
  ) -> AgentNativeToolExecutableDefinition {
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: snapshot.descriptor,
      executorId: "galaxyssi.skill_runtime",
      provenanceMetadata: [
        "skill_id": snapshot.installation.id,
        "skill_version": snapshot.installation.version,
        "skill_source": snapshot.installation.manifest.source,
        "workflow_sha256": GlobalAgentText.stableKey(AgentSkillManifestCodec.encode(snapshot.installation.manifest))
      ],
      availabilityProvider: AgentNativeToolAvailabilityProvider { [weak self] _ in
        self?.snapshot(toolId: snapshot.descriptor.id, nativeRegistry: nativeRegistry)?.descriptor.availability ??
          AgentNativeToolAvailability(
            status: .unavailable,
            reason: "The installed Skill is disabled, removed, or no longer eligible for autonomous use"
          )
      }
    )
    return AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { [weak self] invocation in
        guard let self else {
          return .failure(
            code: "skill_adapter_released",
            message: "The autonomous Skill adapter is no longer available"
          )
        }
        guard let current = self.snapshot(toolId: invocation.descriptor.id, nativeRegistry: nativeRegistry) else {
          return .failure(
            code: "skill_unavailable",
            message: "The installed Skill is disabled, removed, or no longer eligible for autonomous use"
          )
        }
        return try self.execute(
          snapshot: current,
          nativeRegistry: nativeRegistry,
          invocation: invocation
        )
      },
      verifier: { _, execution in
        Self.verify(snapshot: snapshot, execution: execution)
      }
    )
  }

  private func execute(
    snapshot: SkillSnapshot,
    nativeRegistry: AgentNativeToolRegistry,
    invocation: AgentNativeToolInvocation
  ) throws -> AgentNativeToolExecutionResult {
    let installation = snapshot.installation
    let expansion: AgentSkillExpansion
    do {
      expansion = try snapshot.runtime.expand(
        id: installation.id,
        version: installation.version,
        parameters: invocation.input
      )
    } catch {
      return .failure(
        code: "skill_expansion_failed",
        message: Self.executionMessage(error)
      )
    }

    var stepRecords: [AgentMcpJSONValue] = []
    var finalOutput: AgentMcpJSONObject = [:]
    for (index, step) in expansion.steps.enumerated() {
      try invocation.checkpoint()
      guard let descriptor = nativeRegistry.descriptors().first(where: { $0.id == step.toolId }) else {
        return failedStep(
          step: step,
          completed: stepRecords,
          code: "skill_dependency_missing",
          message: "Skill dependency is unavailable"
        )
      }
      try invocation.reportProgress(
        stage: "skill_step",
        message: "\(index + 1)/\(max(expansion.steps.count, 1)): \(descriptor.title)",
        percent: Int(Double(index) * 100.0 / Double(max(expansion.steps.count, 1))),
        sequence: Int64(index)
      )
      let scopedInput = scopedStepInput(
        step.toolId,
        input: step.input,
        workspaceId: invocation.context.attributes["workspace_id"] ?? ""
      )
      let childResult = nativeRegistry.invoke(
        step.toolId,
        input: scopedInput,
        context: childContext(
          parent: invocation,
          descriptor: descriptor,
          step: step,
          index: index
        ),
        hooks: AgentNativeToolInvocationHooks(
          nowMillis: invocationNow(invocation),
          cancellationRequested: { invocation.isCancellationRequested },
          onProgress: { _, progress in
            try? invocation.reportProgress(
              stage: "skill_step.\(step.id).\(progress.stage)",
              message: progress.message,
              percent: progress.percent,
              sequence: Int64(index)
            )
          }
        )
      )
      AgentIOSNativeToolHandoffPresenter.openIfNeeded(childResult)
      let stepRecord = Self.stepRecord(
        step: step,
        result: childResult
      )
      stepRecords.append(.object(stepRecord))
      if !childResult.isSuccess {
        return failedStep(
          step: step,
          completed: stepRecords,
          code: childResult.error?.code ?? "skill_step_failed",
          message: childResult.error?.message ?? childResult.message.ifBlank("A Skill step failed"),
          retryable: childResult.error?.retryable == true
        )
      }
      finalOutput = childResult.output
    }

    do {
      _ = try snapshot.runtime.recordUse(id: installation.id, version: installation.version)
    } catch {
      return .failure(
        code: "skill_record_use_failed",
        message: Self.executionMessage(error)
      )
    }
    return .success(
      output: [
        "skill_id": .string(installation.id),
        "skill_version": .string(installation.version),
        "completed_steps": .int(Int64(stepRecords.count)),
        "total_steps": .int(Int64(expansion.steps.count)),
        "steps": .array(stepRecords),
        "final_output": .object(finalOutput)
      ],
      message: Self.clean(installation.manifest.name, maximum: 160).ifBlank("Skill completed") + " completed",
      metadata: ["execution_contract": .string("host_validated_skill_v1")]
    )
  }

  private func failedStep(
    step: AgentSkillExpandedStep,
    completed: [AgentMcpJSONValue],
    code: String,
    message: String,
    retryable: Bool = false
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult(
      output: [
        "completed_steps": .int(Int64(completed.count)),
        "steps": .array(completed)
      ],
      message: message,
      error: AgentNativeToolError(
        code: code,
        message: message,
        retryable: retryable,
        details: [
          "step_id": .string(step.id),
          "tool_id": .string(step.toolId)
        ]
      )
    )
  }

  private func childContext(
    parent: AgentNativeToolInvocation,
    descriptor: AgentNativeToolDescriptor,
    step: AgentSkillExpandedStep,
    index: Int
  ) -> AgentNativeToolInvocationContext {
    AgentNativeToolInvocationContext(
      invocationId: "\(parent.context.invocationId):skill:\(index + 1)",
      sessionId: parent.context.sessionId,
      conversationId: parent.context.conversationId,
      turnId: parent.context.turnId,
      callerId: "galaxyssi.global_super_agent.skill",
      requestedAtEpochMillis: parent.context.requestedAtEpochMillis,
      deadlineEpochMillis: parent.deadlineEpochMillis,
      idempotencyKey: descriptor.idempotency == .nonIdempotent
        ? nil
        : "\(parent.context.idempotencyKey ?? parent.context.invocationId):\(step.id)",
      grantedPermissions: Set(descriptor.requiredPermissions
        .filter { $0.required && parent.context.grantedPermissions.contains($0.id) }
        .map(\.id)),
      grantedConsents: Set(descriptor.requiredConsents
        .filter { $0.required && parent.context.grantedConsents.contains($0.id) }
        .map(\.id)),
      attributes: parent.context.attributes.merging([
        "parent_skill_id": parent.descriptor.id,
        "skill_step_id": step.id,
        "skill_step_index": String(index)
      ]) { _, new in new }
    )
  }

  private func scopedStepInput(
    _ toolId: String,
    input: AgentMcpJSONObject,
    workspaceId: String
  ) -> AgentMcpJSONObject {
    guard !workspaceId.isBlank, toolId.hasPrefix("galaxyssi.workspace.") else {
      return input
    }
    var scoped = input
    scoped["workspace_id"] = .string(workspaceId)
    return scoped
  }

  private func invocationNow(_ invocation: AgentNativeToolInvocation) -> () -> Int64 {
    { invocation.startedAtEpochMillis + max(0, invocation.deadlineEpochMillis - invocation.startedAtEpochMillis) / 2 }
  }

  private func runtime(nativeToolIds: Set<String>) -> AgentSkillRuntime? {
    runtimeProvider(nativeToolIds.union([Self.agentOrchestrationToolId]))
  }

  private func skillDescription(_ manifest: AgentSkillManifest) -> String {
    var parts = [
      "Installed host-validated Skill workflow.",
      clean(manifest.description.ifBlank(manifest.instructions), maximum: 800)
    ]
    let examples = manifest.triggerExamples
      .prefix(8)
      .map { clean($0, maximum: 160) }
      .filter { !$0.isEmpty }
    if !examples.isEmpty {
      parts.append("Relevant requests: \(examples.joined(separator: "; "))")
    }
    return String(parts.joined(separator: " ").prefix(1_800))
  }

  private func clean(_ value: String, maximum: Int) -> String {
    Self.clean(value, maximum: maximum)
  }

  private static func clean(_ value: String, maximum: Int) -> String {
    String(value
      .replacingOccurrences(of: #"[[:cntrl:]]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(maximum))
  }

  private static func mergePermissions(
    _ descriptors: [AgentNativeToolDescriptor]
  ) -> [AgentNativePermissionRequirement] {
    var merged: [String: AgentNativePermissionRequirement] = [:]
    for requirement in descriptors.flatMap(\.requiredPermissions) {
      if var current = merged[requirement.id] {
        current.required = current.required || requirement.required
        merged[requirement.id] = current
      } else {
        merged[requirement.id] = requirement
      }
    }
    return merged.values.sorted { $0.id < $1.id }
  }

  private static func mergeConsents(
    _ descriptors: [AgentNativeToolDescriptor]
  ) -> [AgentNativeConsentRequirement] {
    var merged: [String: AgentNativeConsentRequirement] = [:]
    for requirement in descriptors.flatMap(\.requiredConsents) {
      if var current = merged[requirement.id] {
        current.required = current.required || requirement.required
        merged[requirement.id] = current
      } else {
        merged[requirement.id] = requirement
      }
    }
    return merged.values.sorted { $0.id < $1.id }
  }

  private static func aggregateTimeout(_ descriptors: [AgentNativeToolDescriptor]) -> Int64 {
    let total = descriptors.reduce(Int64(0)) { partial, descriptor in
      if partial >= maximumWorkflowTimeoutMillis - descriptor.timeoutMillis {
        return maximumWorkflowTimeoutMillis
      }
      return partial + descriptor.timeoutMillis
    }
    return min(
      max(total, AgentNativeToolDescriptor.defaultTimeoutMillis),
      maximumWorkflowTimeoutMillis
    )
  }

  private static func stepRecord(
    step: AgentSkillExpandedStep,
    result: AgentNativeToolResult
  ) -> AgentMcpJSONObject {
    [
      "step_id": .string(step.id),
      "tool_id": .string(step.toolId),
      "status": .string(result.status.rawValue),
      "message": .string(result.message),
      "output": .object(result.output),
      "receipt": .object([
        "invocation_id": .string(result.receipt.invocationId),
        "duration_ms": .int(result.receipt.durationMillis),
        "input_sha256": .string(result.receipt.inputSha256),
        "output_sha256": .string(result.receipt.outputSha256)
      ]),
      "provenance": .object([
        "tool_id": .string(result.provenance.toolId),
        "tool_version": .string(result.provenance.toolVersion),
        "executor_id": .string(result.provenance.executorId)
      ])
    ]
  }

  private static func verify(
    snapshot: SkillSnapshot,
    execution: AgentNativeToolExecutionResult
  ) -> AgentNativeToolVerification {
    let completed = execution.output["completed_steps"]?.intValue ?? -1
    let total = execution.output["total_steps"]?.intValue ?? -1
    let steps = execution.output["steps"]?.arrayValue ?? []
    let valid = execution.isSuccess && total > 0 && completed == total && Int64(steps.count) == total
    return AgentNativeToolVerification(
      status: valid ? .passed : .failed,
      message: valid ? "Every Skill step completed with a native receipt" : "Skill step evidence is incomplete",
      evidence: [
        "skill_id": .string(snapshot.installation.id),
        "skill_version": .string(snapshot.installation.version),
        "completed_steps": .int(completed),
        "total_steps": .int(total)
      ]
    )
  }

  private static func outputSchema() -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object([
        "skill_id": .object(Self.stringSchema(minLength: 1)),
        "skill_version": .object(Self.stringSchema(minLength: 1)),
        "completed_steps": .object(Self.integerSchema(minimum: 0)),
        "total_steps": .object(Self.integerSchema(minimum: 1)),
        "steps": .object(Self.arraySchema(items: AgentNativeToolDescriptor.objectSchema())),
        "final_output": .object(AgentNativeToolDescriptor.objectSchema())
      ]),
      "required": .array([
        .string("skill_id"),
        .string("skill_version"),
        .string("completed_steps"),
        .string("total_steps"),
        .string("steps"),
        .string("final_output")
      ]),
      "additionalProperties": .bool(false)
    ]
  }

  private static func stringSchema(minLength: Int? = nil, maxLength: Int? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(Int64(minLength)) }
    if let maxLength { schema["maxLength"] = .int(Int64(maxLength)) }
    return schema
  }

  private static func integerSchema(minimum: Int64? = nil, maximum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("integer")]
    if let minimum { schema["minimum"] = .int(minimum) }
    if let maximum { schema["maximum"] = .int(maximum) }
    return schema
  }

  private static func arraySchema(items: AgentMcpJSONObject) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(items)
    ]
  }

  private static func executionMessage(_ error: Error) -> String {
    if let validation = error as? AgentSkillValidationError {
      return validation.result.issues
        .map { "\($0.path) [\($0.code)] \($0.message)" }
        .joined(separator: "; ")
        .ifBlank("Skill validation failed")
    }
    if let conflict = error as? AgentSkillConflictError {
      return "Agent Skill \(conflict.id)@\(conflict.version) conflicts with installed content"
    }
    return error.localizedDescription.ifBlank(String(describing: error))
  }

  private static func syntheticResult(
    toolId: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    hooks: AgentNativeToolInvocationHooks,
    status: AgentNativeToolResultStatus,
    message: String,
    error: AgentNativeToolError?
  ) -> AgentNativeToolResult {
    let started = hooks.nowMillis()
    let output: AgentMcpJSONObject = [:]
    let result = AgentNativeToolResult(
      status: status,
      output: output,
      message: message,
      error: error,
      receipt: AgentNativeToolReceipt(
        invocationId: context.invocationId,
        idempotencyKey: context.idempotencyKey,
        startedAtEpochMillis: started,
        finishedAtEpochMillis: started,
        durationMillis: 0,
        status: status,
        inputSha256: AgentMcpJSONCodec.sha256(input),
        outputSha256: AgentMcpJSONCodec.sha256(output)
      ),
      provenance: AgentNativeToolProvenance(
        toolId: toolId,
        toolVersion: "",
        location: .application,
        executorId: "galaxyssi.skill_runtime",
        contractVersion: AgentNativeToolRegistry.contractVersion,
        metadata: [:]
      )
    )
    hooks.onFinished(result)
    return result
  }

  private struct SkillSnapshot {
    var runtime: AgentSkillRuntime
    var installation: AgentSkillInstallation
    var descriptor: AgentNativeToolDescriptor
  }

  private static let toolIdPrefix = "galaxyssi.skill."
  private static let agentOrchestrationToolId = "galaxyssi.agent.orchestrate"
  private static let adapterVersion = "1.0.0"
  private static let maximumWorkflowTimeoutMillis: Int64 = 15 * 60 * 1_000
}

private extension AgentSkillParameterSchema {
  func globalAutonomousNativeSchema() -> AgentMcpJSONObject {
    var document: AgentMcpJSONObject = ["type": .string(type.rawValue)]
    switch type {
    case .object:
      document["properties"] = .object(properties.mapValues { .object($0.globalAutonomousNativeSchema()) })
      document["required"] = .array(required.sorted().map(AgentMcpJSONValue.string))
      document["additionalProperties"] = .bool(additionalProperties)
    case .array:
      document["items"] = .object((items ?? AgentSkillParameterSchema.objectSchema()).globalAutonomousNativeSchema())
      if let minItems { document["minItems"] = .int(Int64(minItems)) }
      if let maxItems { document["maxItems"] = .int(Int64(maxItems)) }
    case .string:
      if let minLength { document["minLength"] = .int(Int64(minLength)) }
      if let maxLength { document["maxLength"] = .int(Int64(maxLength)) }
    case .integer, .number:
      if let minimum { document["minimum"] = .double(minimum) }
      if let maximum { document["maximum"] = .double(maximum) }
    case .boolean:
      break
    }
    if !enumValues.isEmpty {
      document["enum"] = .array(enumValues)
    }
    return document
  }
}

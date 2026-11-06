import Foundation

protocol AgentModelPlanningToolLoopRunning {
  func run(_ request: AgentModelToolLoopRequest) async -> AgentModelToolLoopOutcome
}

extension AgentModelToolLoop: AgentModelPlanningToolLoopRunning {}

struct CloudModelToolLoopAgentPlanningProvider: AgentModelPlanningProviding {
  static let androidPlannerBudget = AgentModelToolLoopBudget(
    maxRounds: 4,
    maxToolCalls: 8,
    maxDepth: 2,
    maxTokens: 12_000,
    maxDurationMillis: 45_000
  )

  var fallbackProvider: AgentModelPlanningProviding
  var toolRegistry: AgentNativeToolRegistry
  var budget: AgentModelToolLoopBudget
  var requestIdFactory: () -> String
  var memoryTelemetryCapture: (AgentWorkspace?) -> Void
  var recoveryJournal: AgentModelLoopJournal?

  private var makeToolLoop: (
    [AgentNativeToolDescriptor], AgentNativeToolRegistry, AgentPlannerToolCatalogSession?
  ) throws -> AgentModelPlanningToolLoopRunning

  init(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    toolRegistry: AgentNativeToolRegistry,
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    ),
    budget: AgentModelToolLoopBudget = CloudModelToolLoopAgentPlanningProvider.androidPlannerBudget,
    clock: AgentModelToolLoopClock = .system,
    loopIdFactory: AgentModelToolLoopIdFactory = .uuids,
    journal: AgentModelLoopJournal = EncryptedAgentModelLoopJournal(),
    requestIdFactory: @escaping () -> String = { UUID().uuidString },
    memoryTelemetryCapture: @escaping (AgentWorkspace?) -> Void = {
      AgentMemoryPssRuntime.requestCapture(workspace: $0)
    }
  ) {
    self.init(
      fallbackProvider: CloudModelAgentPlanningProvider(
        contact: contact,
        store: store,
        sender: structuredSender,
        disclosureStore: disclosureStore
      ),
      toolRegistry: toolRegistry,
      budget: budget,
      requestIdFactory: requestIdFactory,
      memoryTelemetryCapture: memoryTelemetryCapture,
      recoveryJournal: journal
    ) { catalog, registry, session in
      AgentModelToolLoop(
        modelAdapter: CloudModelNativeToolAdapter(
          contact: contact,
          store: store,
          catalog: catalog,
          sender: nativeToolSender,
          disclosureStore: disclosureStore,
          plannerCatalog: session
        ),
        toolRegistry: registry,
        clock: clock,
        idFactory: loopIdFactory,
        journal: journal
      )
    }
  }

  init(
    fallbackProvider: AgentModelPlanningProviding,
    toolRegistry: AgentNativeToolRegistry,
    budget: AgentModelToolLoopBudget = CloudModelToolLoopAgentPlanningProvider.androidPlannerBudget,
    requestIdFactory: @escaping () -> String = { UUID().uuidString },
    memoryTelemetryCapture: @escaping (AgentWorkspace?) -> Void = {
      AgentMemoryPssRuntime.requestCapture(workspace: $0)
    },
    recoveryJournal: AgentModelLoopJournal? = nil,
    makeToolLoop: @escaping (
      [AgentNativeToolDescriptor], AgentNativeToolRegistry, AgentPlannerToolCatalogSession?
    ) throws -> AgentModelPlanningToolLoopRunning
  ) {
    self.fallbackProvider = fallbackProvider
    self.toolRegistry = toolRegistry
    self.budget = budget
    self.requestIdFactory = requestIdFactory
    self.memoryTelemetryCapture = memoryTelemetryCapture
    self.recoveryJournal = recoveryJournal
    self.makeToolLoop = makeToolLoop
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    if invocation.completionShapeRepairOnly == true {
      return try await fallbackProvider.rawPlan(invocation: invocation)
    }
    let recoveryIdentity = Self.recoveryIdentity(invocation.request)
    let loopId = Self.boundedIdentifier(
      "planner-\(recoveryIdentity)",
      fallback: requestIdFactory()
    )
    let scope = AgentModelLoopScope(request: Self.toolLoopRequest(invocation: invocation,
      catalog: [], budget: budget, loopId: loopId, recoveryIdentity: recoveryIdentity))
    if let journal = recoveryJournal {
      do {
        if let registered = try safeExecutableSelection(for: invocation, useRegisteredContracts: true) {
          let fingerprint = registered.registry.registeredContractFingerprint()
          let stable = try await journal.withLease(scope: scope) { records in
            try AgentModelLoopCheckpoint(records: records).plannerCatalogUsesContracts(
              scope: scope, fingerprint: fingerprint)
          }
          if stable {
            let session = AgentPlannerToolCatalogSession(scope: scope, registry: registered.registry)
            return try await run(invocation, selection: registered, session: session, loopId: loopId,
                                 recoveryIdentity: recoveryIdentity)
          }
        }
        if let legacy = try safeExecutableSelection(for: invocation, useRegisteredContracts: false) {
          return try await run(invocation, selection: legacy, session: nil, loopId: loopId,
                               recoveryIdentity: recoveryIdentity)
        }
        if try journal.hasRecords(scope: scope) {
          throw AgentModelLoopRecoveryError(code: "model_loop_requires_recovery_not_fallback")
        }
      } catch {
        throw AgentModelPlanningProviderError.recoveryRequired(error.localizedDescription)
      }
    } else if let selection = try safeExecutableSelection(for: invocation, useRegisteredContracts: false) {
      return try await run(invocation, selection: selection, session: nil, loopId: loopId,
                           recoveryIdentity: recoveryIdentity)
    }
    return try await fallbackProvider.rawPlan(invocation: invocation)
  }

  private func run(_ invocation: AgentModelPlanningInvocation,
                   selection: (registry: AgentNativeToolRegistry, catalog: [AgentNativeToolDescriptor]),
                   session: AgentPlannerToolCatalogSession?, loopId: String, recoveryIdentity: String) async throws -> String {
    var request = Self.toolLoopRequest(
      invocation: invocation,
      catalog: selection.catalog,
      budget: budget,
      loopId: loopId,
      recoveryIdentity: recoveryIdentity
    )
    request.plannerRegisteredCatalog = session != nil
    let runner = try makeToolLoop(selection.catalog, selection.registry, session)
    memoryTelemetryCapture(Self.telemetryWorkspace(request: request))
    defer { memoryTelemetryCapture(nil) }
    let outcome = await runner.run(request)
    guard outcome.status == .completed else {
      throw AgentModelPlanningProviderError.unavailable(
        outcome.error?.message ?? "Model-native tool planning did not complete"
      )
    }
    let text = outcome.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw AgentModelPlanningProviderError.unavailable("Model-native tool planning returned an empty plan")
    }
    return text
  }

  func repairPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    // Repair is text-only on the same selected model; do not start a new native tool loop.
    try await fallbackProvider.repairPlan(invocation: invocation)
  }

  private func safeExecutableSelection(
    for invocation: AgentModelPlanningInvocation, useRegisteredContracts: Bool
  ) throws -> (registry: AgentNativeToolRegistry, catalog: [AgentNativeToolDescriptor])? {
    let allowsPhoneRuntimeTools = invocation.request.allowsPhoneRuntimeTools &&
      AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: invocation.request.planRequest.goal)
    let phoneOwnsExecution = invocation.request.phoneOwnsExecution
    let requested = useRegisteredContracts ? (invocation.registeredNativeTools ?? invocation.nativeTools) : invocation.nativeTools
    let requestedIds = Set(requested
      .filter { Self.isSafePlannerTool($0, allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
                                       phoneOwnsExecution: phoneOwnsExecution, requireAvailable: !useRegisteredContracts) }
      .map(\.id))
    guard !requestedIds.isEmpty else {
      return nil
    }

    let registry = try toolRegistry.subset(useRegisteredContracts: useRegisteredContracts) { descriptor in
      requestedIds.contains(descriptor.id) &&
        Self.isSafePlannerTool(descriptor, allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
                               phoneOwnsExecution: phoneOwnsExecution, requireAvailable: !useRegisteredContracts)
    }
    let catalog = useRegisteredContracts ? registry.registeredContracts() : registry.descriptors()
    return catalog.isEmpty ? nil : (registry, catalog)
  }

  private static func toolLoopRequest(
    invocation: AgentModelPlanningInvocation,
    catalog: [AgentNativeToolDescriptor],
    budget: AgentModelToolLoopBudget,
    loopId: String,
    recoveryIdentity: String
  ) -> AgentModelToolLoopRequest {
    let conversationId = boundedIdentifier(
      invocation.request.conversationContext.conversationId,
      fallback: loopId
    )
    let sessionId = conversationId
    let turnId = boundedIdentifier(invocation.request.executionTurnId, fallback: sessionId)
    let grantedPermissions = Set(catalog.flatMap { descriptor in
      descriptor.requiredPermissions.filter(\.required).map(\.id)
    })
    let grantedConsents = Set(catalog.flatMap { descriptor in
      descriptor.requiredConsents.filter(\.required).map(\.id)
    })
    return AgentModelToolLoopRequest(
      sessionId: sessionId,
      conversationId: conversationId,
      turnId: turnId,
      taskId: turnId,
      workspaceId: AgentWorkspaceScope.id(conversationId: conversationId, sessionId: sessionId),
      loopId: loopId,
      messages: [
        .system(invocation.systemPrompt),
        .user(invocation.prompt)
      ],
      budget: budget,
      callerId: toolLoopCallerId,
      grantedPermissions: grantedPermissions,
      grantedConsents: grantedConsents,
      recoveryInputIdentity: recoveryIdentity,
      observationHistoryEnabled: true
    )
  }

  static func telemetryWorkspace(request: AgentModelToolLoopRequest) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: request.workspaceId,
      sessionId: request.sessionId,
      conversationId: request.conversationId,
      taskId: request.taskId,
      goal: request.messages.last?.text ?? "",
      agentId: toolLoopCallerId,
      status: .running
    )
  }

  private static func isSafePlannerTool(
    _ descriptor: AgentNativeToolDescriptor,
    allowsPhoneRuntimeTools: Bool,
    phoneOwnsExecution: Bool, requireAvailable: Bool
  ) -> Bool {
    (!requireAvailable || descriptor.availability.status == .available) &&
      descriptor.risk == .low &&
      descriptor.requiredConsents.allSatisfy { !$0.required } &&
      (!phoneOwnsExecution || (!descriptor.requiresEffectClaim &&
        !AgentPhoneRuntimePolicy.directPhoneActionTools.contains(descriptor.id))) &&
      (allowsPhoneRuntimeTools || !AgentPhoneRuntimePolicy.isPhoneRuntimeTool(descriptor.id))
  }

  private static func recoveryIdentity(_ request: AgentModelPlanningPromptRequest) -> String {
    AgentModelLoopRecoveryIdentity.sha256([
      "goal": request.planRequest.goal,
      "conversation_id": request.conversationContext.conversationId,
      "execution_turn_id": request.executionTurnId,
      "replan_reason": request.parsingContext.replanReason,
      "completion_requirements": AgentModelLoopRecoveryIdentity.sha256(
        request.planRequest.completionRequirements
      ),
      "execution_history": AgentModelLoopRecoveryIdentity.sha256(request.executionHistory)
    ])
  }

  private static func boundedIdentifier(_ value: String, fallback: String) -> String {
    let selected = value.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(fallback)
    guard selected.count > AgentModelToolLoopValidation.maximumIdCharacters else {
      return selected
    }
    let digest = AgentModelToolProtocolJSON.sha256(selected)
    let prefix = selected.prefix(120)
    return "\(prefix)-\(digest.prefix(32))"
  }

  static let toolLoopCallerId = "galaxyssi.ios_model_planner_tool_loop"
}

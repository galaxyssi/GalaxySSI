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

  private var makeToolLoop: ([AgentNativeToolDescriptor], AgentNativeToolRegistry) throws -> AgentModelPlanningToolLoopRunning

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
      memoryTelemetryCapture: memoryTelemetryCapture
    ) { catalog, registry in
      AgentModelToolLoop(
        modelAdapter: CloudModelNativeToolAdapter(
          contact: contact,
          store: store,
          catalog: catalog,
          sender: nativeToolSender,
          disclosureStore: disclosureStore
        ),
        toolRegistry: registry,
        clock: clock,
        idFactory: loopIdFactory
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
    makeToolLoop: @escaping ([AgentNativeToolDescriptor], AgentNativeToolRegistry) throws -> AgentModelPlanningToolLoopRunning
  ) {
    self.fallbackProvider = fallbackProvider
    self.toolRegistry = toolRegistry
    self.budget = budget
    self.requestIdFactory = requestIdFactory
    self.memoryTelemetryCapture = memoryTelemetryCapture
    self.makeToolLoop = makeToolLoop
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    guard let selection = try safeExecutableSelection(for: invocation) else {
      return try await fallbackProvider.rawPlan(invocation: invocation)
    }

    let turnId = Self.boundedIdentifier(requestIdFactory(), fallback: UUID().uuidString)
    let request = Self.toolLoopRequest(
      invocation: invocation,
      catalog: selection.catalog,
      budget: budget,
      turnId: turnId
    )
    let runner = try makeToolLoop(selection.catalog, selection.registry)
    memoryTelemetryCapture(Self.telemetryWorkspace(request: request))
    let outcome = await runner.run(request)
    memoryTelemetryCapture(nil)
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

  private func safeExecutableSelection(
    for invocation: AgentModelPlanningInvocation
  ) throws -> (registry: AgentNativeToolRegistry, catalog: [AgentNativeToolDescriptor])? {
    let allowsPhoneRuntimeTools = invocation.request.allowsPhoneRuntimeTools &&
      AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: invocation.request.planRequest.goal)
    let requestedIds = Set(invocation.nativeTools
      .filter { Self.isSafePlannerTool($0, allowsPhoneRuntimeTools: allowsPhoneRuntimeTools) }
      .map(\.id))
    guard !requestedIds.isEmpty else {
      return nil
    }

    let registry = try toolRegistry.subset { descriptor in
      requestedIds.contains(descriptor.id) &&
        Self.isSafePlannerTool(descriptor, allowsPhoneRuntimeTools: allowsPhoneRuntimeTools)
    }
    let catalog = registry.descriptors()
    return catalog.isEmpty ? nil : (registry, catalog)
  }

  private static func toolLoopRequest(
    invocation: AgentModelPlanningInvocation,
    catalog: [AgentNativeToolDescriptor],
    budget: AgentModelToolLoopBudget,
    turnId: String
  ) -> AgentModelToolLoopRequest {
    let conversationId = boundedIdentifier(
      invocation.request.conversationContext.conversationId,
      fallback: turnId
    )
    let grantedPermissions = Set(catalog.flatMap { descriptor in
      descriptor.requiredPermissions.filter(\.required).map(\.id)
    })
    let grantedConsents = Set(catalog.flatMap { descriptor in
      descriptor.requiredConsents.filter(\.required).map(\.id)
    })
    return AgentModelToolLoopRequest(
      sessionId: conversationId,
      conversationId: conversationId,
      turnId: turnId,
      taskId: turnId,
      workspaceId: turnId,
      messages: [
        .system(invocation.systemPrompt),
        .user(invocation.prompt)
      ],
      budget: budget,
      callerId: toolLoopCallerId,
      grantedPermissions: grantedPermissions,
      grantedConsents: grantedConsents
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
    allowsPhoneRuntimeTools: Bool
  ) -> Bool {
    descriptor.availability.status == .available &&
      descriptor.risk == .low &&
      descriptor.requiredConsents.allSatisfy { !$0.required } &&
      (allowsPhoneRuntimeTools || !AgentPhoneRuntimePolicy.isPhoneRuntimeTool(descriptor.id))
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

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

  private var makeToolLoop: ([AgentNativeToolDescriptor], AgentNativeToolRegistry) throws -> AgentModelPlanningToolLoopRunning

  init(
    contact: SignalASIContact,
    store: SignalASIStore,
    toolRegistry: AgentNativeToolRegistry,
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    ),
    budget: AgentModelToolLoopBudget = CloudModelToolLoopAgentPlanningProvider.androidPlannerBudget,
    clock: AgentModelToolLoopClock = .system,
    loopIdFactory: AgentModelToolLoopIdFactory = .uuids,
    requestIdFactory: @escaping () -> String = { UUID().uuidString }
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
      requestIdFactory: requestIdFactory
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
    makeToolLoop: @escaping ([AgentNativeToolDescriptor], AgentNativeToolRegistry) throws -> AgentModelPlanningToolLoopRunning
  ) {
    self.fallbackProvider = fallbackProvider
    self.toolRegistry = toolRegistry
    self.budget = budget
    self.requestIdFactory = requestIdFactory
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

  private func safeExecutableSelection(
    for invocation: AgentModelPlanningInvocation
  ) throws -> (registry: AgentNativeToolRegistry, catalog: [AgentNativeToolDescriptor])? {
    let requestedIds = Set(invocation.nativeTools
      .filter { Self.isSafePlannerTool($0, allowsPhoneRuntimeTools: invocation.request.allowsPhoneRuntimeTools) }
      .map(\.id))
    guard !requestedIds.isEmpty else {
      return nil
    }

    let registry = try toolRegistry.subset { descriptor in
      requestedIds.contains(descriptor.id) &&
        Self.isSafePlannerTool(descriptor, allowsPhoneRuntimeTools: invocation.request.allowsPhoneRuntimeTools)
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
      callerId: "signalasi.ios_model_planner_tool_loop",
      grantedPermissions: grantedPermissions,
      grantedConsents: grantedConsents
    )
  }

  private static func isSafePlannerTool(
    _ descriptor: AgentNativeToolDescriptor,
    allowsPhoneRuntimeTools: Bool
  ) -> Bool {
    descriptor.availability.status == .available &&
      descriptor.risk == .low &&
      descriptor.requiredConsents.allSatisfy { !$0.required } &&
      (allowsPhoneRuntimeTools || !isPhoneRuntimeTool(descriptor.id))
  }

  private static func isPhoneRuntimeTool(_ id: String) -> Bool {
    id.hasPrefix("signalasi.runtime.") || id.hasPrefix("signalasi.workspace.")
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
}

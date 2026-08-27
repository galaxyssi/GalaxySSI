import CryptoKit
import Foundation

struct AgentControlPlaneWarmupResult: Equatable {
  var requestedAgentIds: [String]
  var warmedAgentIds: [String]
  var failedAgentIds: [String]

  var isComplete: Bool {
    requestedAgentIds.count == warmedAgentIds.count && failedAgentIds.isEmpty
  }
}

final class AgentControlPlaneActionExecutor: AgentActionExecutor {
  private let provider: ActionExecutorAgentProvider
  private let directory: AgentAdapterDirectory
  private let teamDispatchCoordinator: AgentControlPlaneTeamDispatchCoordinator

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun] = { [] },
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore(),
    healthLedger: AgentProviderHealthLedger = UserDefaultsAgentProviderHealthLedger(),
    runEventStore: AgentRunEventPersistence? = UserDefaultsAgentRunEventStore(),
    managedResponseLedger: AgentManagedResponseLedger = UserDefaultsAgentManagedResponseLedger(),
    terminalDeliveryStore: AgentTerminalDeliveryStoring = UserDefaultsAgentTerminalDeliveryStore()
  ) {
    let provider = ActionExecutorAgentProvider(
      registrationSource: registrationSource,
      delegate: delegate,
      recoverableSource: recoverableSource,
      runStartReceipts: runStartReceipts,
      healthLedger: healthLedger,
      runEventStore: runEventStore,
      managedResponseLedger: managedResponseLedger,
      terminalDeliveryStore: terminalDeliveryStore
    )
    self.provider = provider
    let directory = AgentAdapterDirectory()
    try? directory.register(provider)
    self.directory = directory
    self.teamDispatchCoordinator = AgentControlPlaneTeamDispatchCoordinator(provider: provider, directory: directory)
    scheduleAdapterPrewarm()
  }

  init(provider: ActionExecutorAgentProvider) {
    self.provider = provider
    let directory = AgentAdapterDirectory()
    try? directory.register(provider)
    self.directory = directory
    self.teamDispatchCoordinator = AgentControlPlaneTeamDispatchCoordinator(provider: provider, directory: directory)
    scheduleAdapterPrewarm()
  }

  @discardableResult
  func prewarm(agentIds: [String]? = nil) async -> AgentControlPlaneWarmupResult {
    await provider.prewarm(agentIds: agentIds)
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard action.kind == .callConnector else {
      return provider.executeDelegate(action: action, screen: screen)
    }
    if let rawSpec = action.parameters[Self.agentTeamSpecParameter],
      let spec = AgentTeamDispatchSpecCodec.decode(rawSpec) {
      return executeTeamAction(spec: spec, action: action, screen: screen)
    }
    if !(action.parameters[Self.agentTeamSpecParameter] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return provider.executeDelegate(action: action, screen: screen)
    }
    let requestedAgentId = (action.parameters["connector_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(action.target)
    guard let agentId = provider.resolveAgentId(requestedAgentId) else {
      return provider.executeDelegate(action: action, screen: screen)
    }
    let conversationId = action.parameters[Self.conversationIdKey] ?? ""
    let turnId = action.parameters[Self.turnIdKey] ?? ""
    let runId = Self.stableRunId(
      conversationId: conversationId,
      turnId: turnId,
      actionId: action.id,
      agentId: agentId
    )
    let request = AgentRunRequest(
      conversationId: conversationId,
      messageId: turnId.ifBlank(action.id),
      taskId: turnId.ifBlank(runId),
      runId: runId,
      parentRunId: (action.parameters["parent_run_id"] ?? "").ifBlank(runId),
      goal: (action.parameters["original_goal"] ?? "")
        .ifBlank(action.parameters["prompt"] ?? "")
        .ifBlank(action.description),
      deliveryMode: Self.deliveryMode(action.parameters["delivery_mode"] ?? ""),
      requiredCapabilities: provider.registration(agentId: agentId)?.capabilities ?? [],
      context: [
        "action_id": .string(action.id),
        "action_target": .string(action.target),
        "risk": .string(action.risk.rawValue.lowercased())
      ],
      idempotencyKey: (action.parameters["idempotency_key"] ?? "").ifBlank(runId),
      createdAtMillis: AgentControlPlaneClock.nowMillis()
    )
    provider.prepare(agentId: agentId, request: request, action: action, screen: screen)
    let dispatchStartedAt = AgentControlPlaneClock.nowMillis()
    do {
      guard let adapter = try Self.awaitBlocking({ try await self.directory.resolveAdapter(agentId) }) else {
        provider.discardPrepared(agentId: agentId, runId: runId)
        return provider.executeDelegate(action: action, screen: screen)
      }
      let handle = try Self.awaitBlocking({ try await adapter.startRun(request) })
      let dispatchResult = provider.result(agentId: agentId, runId: handle.runId)
      provider.discardPrepared(agentId: agentId, runId: runId)
      if var result = dispatchResult {
        provider.recordDispatchOutcome(
          agentId: agentId,
          result: result,
          latencyMillis: AgentControlPlaneClock.nowMillis() - dispatchStartedAt
        )
        result.metadata.merge([
          "control_plane_run_id": handle.runId,
          "control_plane_agent_id": handle.agentId,
          "control_plane_remote_run_id": handle.remoteRunId,
          "control_plane_adapter_family": provider.adapterFamily(agentId: agentId),
          "control_plane_health_scope": provider.healthScope(agentId: agentId)
        ]) { _, new in new }
        return result
      }
      if request.deliveryMode == AgentDeliveryMode.ignore {
        return AgentActionResult(
          actionId: action.id,
          success: true,
          message: "",
          metadata: [
            "delivery_mode": "ignore",
            "control_plane_run_id": handle.runId,
            "control_plane_agent_id": handle.agentId
          ]
        )
      }
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Agent Adapter returned no dispatch receipt"
      )
    } catch {
      let circuit = error as? AgentProviderCircuitOpenError
      provider.discardPrepared(agentId: agentId, runId: runId)
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: error.localizedDescription.isEmpty ? "Agent Adapter dispatch failed" : error.localizedDescription,
        metadata: [
          "control_plane_run_id": runId,
          "control_plane_agent_id": agentId,
          "provider_circuit_open": circuit == nil ? "false" : "true",
          "provider_health_scope": provider.healthScope(agentId: agentId),
          "provider_retry_at_millis": circuit.map { String($0.retryAtMillis) } ?? ""
        ]
      )
    }
  }

  private func executeTeamAction(
    spec: AgentTeamDispatchSpec,
    action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let startedAt = AgentControlPlaneClock.nowMillis()
    do {
      let receipt = try Self.awaitBlocking {
        try await self.teamDispatchCoordinator.dispatch(spec: spec, action: action, screen: screen)
      }
      let primaryAgentId = spec.definition.primaryAgentId
      let teamMetadata = Self.teamMetadata(spec: spec, receipt: receipt)
      if var result = provider.result(agentId: primaryAgentId, runId: receipt.primaryRun.runId) {
        provider.recordDispatchOutcome(
          agentId: primaryAgentId,
          result: result,
          latencyMillis: AgentControlPlaneClock.nowMillis() - startedAt
        )
        result.actionId = action.id
        result.metadata.merge(teamMetadata) { _, new in new }
        return result
      }
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "",
        metadata: teamMetadata
      )
    } catch {
      provider.discardPrepared(agentId: spec.definition.primaryAgentId, runId: spec.supervisorRunId)
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: error.localizedDescription.ifBlank("Agent team dispatch failed"),
        metadata: [
          "agent_team_id": spec.definition.teamId,
          "agent_team_run_id": spec.supervisorRunId,
          "agent_team_primary_agent_id": spec.definition.primaryAgentId
        ]
      )
    }
  }

  private static func teamMetadata(
    spec: AgentTeamDispatchSpec,
    receipt: AgentControlPlaneTeamDispatchReceipt
  ) -> [String: String] {
    [
      "agent_team_id": spec.definition.teamId,
      "agent_team_run_id": spec.supervisorRunId,
      "agent_team_primary_agent_id": spec.definition.primaryAgentId,
      "agent_team_member_count": String(receipt.memberRuns.count),
      "agent_team_unavailable_members": receipt.unavailableMembers.keys.sorted().joined(separator: ","),
      "control_plane_run_id": receipt.primaryRun.runId,
      "control_plane_agent_id": receipt.primaryRun.agentId
    ]
  }

  @discardableResult
  func acceptConnectorResponse(_ response: AgentConnectorResponse) -> AgentActionResult? {
    provider.acceptConnectorResponse(response)
  }

  @discardableResult
  func observeConnectorResponses(from bus: AgentConnectorResponseBus) -> UUID {
    provider.observeConnectorResponses(from: bus)
  }

  func removeConnectorResponseObserver(_ token: UUID, from bus: AgentConnectorResponseBus) {
    provider.removeConnectorResponseObserver(token, from: bus)
  }

  private func scheduleAdapterPrewarm() {
    Task { [weak self] in
      _ = await self?.prewarm()
    }
  }

  static func stableRunId(conversationId: String, turnId: String, actionId: String, agentId: String) -> String {
    let source = [conversationId, turnId, actionId, agentId].joined(separator: "\u{001f}")
    var bytes = Array(Insecure.MD5.hash(data: Data(source.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let uuid = UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
    return uuid.uuidString.lowercased()
  }

  static func deliveryMode(_ value: String) -> AgentDeliveryMode {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "observe", "inject", "context":
      return .observe
    case "ignore", "none", "skip":
      return .ignore
    default:
      return .respond
    }
  }

  private static func awaitBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: Result<T, Error>?
    Task {
      do {
        let value = try await operation()
        lock.lock()
        result = .success(value)
        lock.unlock()
      } catch {
        lock.lock()
        result = .failure(error)
        lock.unlock()
      }
      semaphore.signal()
    }
    semaphore.wait()
    lock.lock()
    let captured = result
    lock.unlock()
    return try captured!.get()
  }

  private static let conversationIdKey = "_signalasi_conversation_id"
  private static let turnIdKey = "_signalasi_turn_id"
  private static let agentTeamSpecParameter = "_signalasi_agent_team_spec"
}

final class ActionExecutorAgentProvider: AgentProvider {
  private let registrationSource: () -> [AgentRegistration]
  private let delegate: AgentActionExecutor
  private let recoverableSource: () -> [AgentRecoverableRun]
  private let runStartReceipts: AgentRunStartReceiptStore
  private let healthLedger: AgentProviderHealthLedger
  private let runEventStore: AgentRunEventPersistence?
  private let managedResponseLedger: AgentManagedResponseLedger
  private let terminalDeliveryStore: AgentTerminalDeliveryStoring
  private let localProtocol: AgentProtocolRange
  private let lock = NSRecursiveLock()
  private var transportsByAgentId: [String: ActionExecutorAgentTransport] = [:]
  private var adaptersByAgentId: [String: AgentAdapter] = [:]
  private var cachedRegistrations: [AgentRegistration]?
  private var registrationsCachedAtUptime: TimeInterval = 0
  let providerId: String

  private static let registrationCacheTTL: TimeInterval = 1

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun] = { [] },
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore(),
    healthLedger: AgentProviderHealthLedger = InMemoryAgentProviderHealthLedger(),
    runEventStore: AgentRunEventPersistence? = nil,
    managedResponseLedger: AgentManagedResponseLedger = UserDefaultsAgentManagedResponseLedger(),
    terminalDeliveryStore: AgentTerminalDeliveryStoring = UserDefaultsAgentTerminalDeliveryStore(),
    providerId: String = "signalasi-connectors",
    localProtocol: AgentProtocolRange = AgentProtocolRange(
      preferred: "1.0",
      minimum: "1.0",
      maximum: "1.0",
      features: ["run.cancel", "run.recover", "run.events", "message.respond", "message.observe"]
    )
  ) {
    self.registrationSource = registrationSource
    self.delegate = delegate
    self.recoverableSource = recoverableSource
    self.runStartReceipts = runStartReceipts
    self.healthLedger = healthLedger
    self.runEventStore = runEventStore
    self.managedResponseLedger = managedResponseLedger
    self.terminalDeliveryStore = terminalDeliveryStore
    self.providerId = providerId
    self.localProtocol = localProtocol
  }

  func connect() async throws -> AgentProtocolAgreement {
    AgentProtocolAgreement(version: localProtocol.preferred, features: localProtocol.features)
  }

  @discardableResult
  func prewarm(agentIds: [String]? = nil) async -> AgentControlPlaneWarmupResult {
    let registrations = registrationSnapshot()
    let available = registrations.filter { registration in
      registration.status != .offline &&
        registration.status != .unreachable &&
        registration.status != .permissionRequired
    }
    let cleanedAgentIds = (agentIds ?? available.map(\.agentId))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var seenAgentIds = Set<String>()
    let requested = cleanedAgentIds
      .filter { seenAgentIds.insert($0).inserted }
      .filter { id in available.contains { $0.agentId == id } }
      .sorted()
    guard !requested.isEmpty else {
      return AgentControlPlaneWarmupResult(
        requestedAgentIds: [],
        warmedAgentIds: [],
        failedAgentIds: []
      )
    }

    var warmed: [String] = []
    var failed: [String] = []
    await withTaskGroup(of: (String, Bool).self) { group in
      for agentId in requested {
        group.addTask { [weak self] in
          guard let self else { return (agentId, false) }
          do {
            guard let adapter = try await self.adapter(agentId: agentId) else {
              return (agentId, false)
            }
            _ = try await adapter.connect()
            return (agentId, true)
          } catch {
            await self.invalidateAdapter(agentId: agentId)
            return (agentId, false)
          }
        }
      }
      for await (agentId, succeeded) in group {
        if succeeded {
          warmed.append(agentId)
        } else {
          failed.append(agentId)
        }
      }
    }
    return AgentControlPlaneWarmupResult(
      requestedAgentIds: requested,
      warmedAgentIds: warmed.sorted(),
      failedAgentIds: failed.sorted()
    )
  }

  func disconnect() async {
    lock.lock()
    let adapters = Array(adaptersByAgentId.values)
    adaptersByAgentId.removeAll()
    transportsByAgentId.removeAll()
    cachedRegistrations = nil
    registrationsCachedAtUptime = 0
    lock.unlock()
    for adapter in adapters {
      await adapter.disconnect()
    }
  }

  func registrations() async throws -> [AgentRegistration] {
    registrationSnapshot().map { registration in
      let health = healthLedger.snapshot(registration: registration)
      switch health.circuitState(nowMillis: AgentControlPlaneClock.nowMillis()) {
      case .open:
        var projected = registration
        projected.status = .unreachable
        return projected
      case .halfOpen:
        var projected = registration
        projected.status = .degraded
        return projected
      case .closed:
        if health.consecutiveFailures > 0 && registration.status == .online {
          var projected = registration
          projected.status = .degraded
          return projected
        }
        return registration
      }
    }
  }

  func adapter(agentId: String) async throws -> AgentAdapter? {
    lock.lock()
    if let adapter = adaptersByAgentId[agentId] {
      lock.unlock()
      return adapter
    }
    lock.unlock()
    guard let registration = registration(agentId: agentId) else {
      return nil
    }
    let transport = transport(agentId: agentId)
    let transportAdapter = TransportBackedAgentAdapter(
      initialRegistration: registration,
      transport: transport,
      localProtocol: localProtocol,
      runStartReceipts: runStartReceipts
    )
    let adapter = HealthIsolatedAgentAdapter(
      delegate: transportAdapter,
      family: registration.agentAdapterFamily(),
      healthLedger: healthLedger
    )
    lock.lock()
    if let existing = adaptersByAgentId[agentId] {
      lock.unlock()
      return existing
    }
    adaptersByAgentId[agentId] = adapter
    lock.unlock()
    return adapter
  }

  private func invalidateAdapter(agentId: String) async {
    lock.lock()
    let adapter = adaptersByAgentId.removeValue(forKey: agentId)
    lock.unlock()
    await adapter?.disconnect()
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    recoverableSource()
  }

  func registration(agentId: String) -> AgentRegistration? {
    registrationSnapshot().first { $0.agentId == agentId }
  }

  func resolveAgentId(_ requested: String) -> String? {
    let clean = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return nil
    }
    let registrations = registrationSnapshot()
    return registrations.first { $0.agentId == clean }?.agentId ??
      registrations.first { $0.agentId.hasSuffix(":\(clean)") || clean.hasSuffix(":\($0.agentId)") }?.agentId ??
      registrations.first { $0.displayName.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.agentId
  }

  func prepare(agentId: String, request: AgentRunRequest, action: AgentAction, screen: AgentScreenContext) {
    guard let registration = registration(agentId: agentId) else {
      return
    }
    transport(agentId: agentId).prepare(runId: request.runId, action: action, screen: screen, registration: registration)
  }

  func result(agentId: String, runId: String) -> AgentActionResult? {
    transportIfPresent(agentId: agentId)?.result(runId: runId)
  }

  func recordDispatchOutcome(agentId: String, result: AgentActionResult, latencyMillis: Int64) {
    guard let registration = registration(agentId: agentId) else { return }
    let now = AgentControlPlaneClock.nowMillis()
    if result.success {
      healthLedger.recordSuccess(
        registration: registration,
        operation: "start_run",
        latencyMillis: latencyMillis,
        nowMillis: now
      )
    } else {
      healthLedger.recordFailure(
        registration: registration,
        operation: "start_run",
        kind: AgentProviderFailureClassifier.from(result: result),
        latencyMillis: latencyMillis,
        nowMillis: now
      )
    }
  }

  @discardableResult
  func recordNativeToolLifecycleEvent(
    _ event: AgentNativeToolLifecycleEvent,
    agentId: String = "signalasi-mobile",
    deviceId: String = ""
  ) -> AgentRunControlEvent? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let recorded = transport.recordNativeToolLifecycleEvent(event, agentId: agentId, deviceId: deviceId) {
        return recorded
      }
    }
    return nil
  }

  @discardableResult
  func acceptConnectorResponse(_ response: AgentConnectorResponse) -> AgentActionResult? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.acceptConnectorResponse(response) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func observeConnectorResponses(from bus: AgentConnectorResponseBus) -> UUID {
    bus.addListener { [weak self] response in
      _ = self?.acceptConnectorResponse(response)
    }
  }

  func removeConnectorResponseObserver(_ token: UUID, from bus: AgentConnectorResponseBus) {
    bus.removeListener(token)
  }

  func nativeToolLifecycleEventSink(
    agentId: String = "signalasi-mobile",
    deviceId: String = ""
  ) -> AgentNativeToolLifecycleEventSink {
    AgentNativeToolLifecycleEventSink { [weak self] event in
      _ = self?.recordNativeToolLifecycleEvent(event, agentId: agentId, deviceId: deviceId)
    }
  }

  @discardableResult
  func acceptConnectorTerminalStatus(
    sourceMessageId: Int64,
    contactId: String,
    taskId: String,
    taskStatus: String,
    statusSeq: Int64,
    message: String,
    conversationId: String = "",
    turnId: String = "",
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    let envelope = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: sourceMessageId,
      contactId: contactId,
      taskId: taskId,
      taskStatus: taskStatus,
      statusSeq: statusSeq,
      message: message,
      conversationId: conversationId,
      turnId: turnId,
      nowMillis: nowMillis
    )
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.acceptConnectorTerminalStatus(envelope) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func recordConnectorTaskStatus(
    sourceMessageId: Int64,
    contactId: String,
    taskId: String,
    taskStatus: String,
    statusSeq: Int64,
    conversationId: String = "",
    turnId: String = "",
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    let envelope = AgentConnectorTerminalStatusEnvelope(
      sourceMessageId: sourceMessageId,
      contactId: contactId,
      taskId: taskId,
      taskStatus: taskStatus,
      statusSeq: statusSeq,
      conversationId: conversationId,
      turnId: turnId,
      nowMillis: nowMillis
    )
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.recordConnectorTaskStatus(envelope) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func recordConnectorTransportAccepted(
    sourceMessageId: Int64,
    contactId: String,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.recordConnectorTransportAccepted(
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        nowMillis: nowMillis
      ) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func handleConnectorTimeout(
    sourceMessageId: Int64,
    stage: AgentConnectorTimeoutStage,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.handleConnectorTimeout(
        sourceMessageId: sourceMessageId,
        stage: stage,
        nowMillis: nowMillis
      ) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func acceptConnectorSteered(
    sourceMessageId: Int64,
    contactId: String,
    mergedIntoTaskId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.acceptConnectorSteered(
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        mergedIntoTaskId: mergedIntoTaskId,
        conversationId: conversationId,
        turnId: turnId,
        taskId: taskId,
        nowMillis: nowMillis
      ) {
        return result
      }
    }
    return nil
  }

  @discardableResult
  func forceTaskTimeout(
    runId: String,
    message: String,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentActionResult? {
    lock.lock()
    let transports = Array(transportsByAgentId.values)
    lock.unlock()
    for transport in transports {
      if let result = transport.forceTaskTimeout(
        runId: runId,
        message: message,
        nowMillis: nowMillis
      ) {
        return result
      }
    }
    return nil
  }

  func discardPrepared(agentId: String, runId: String) {
    transportIfPresent(agentId: agentId)?.discardPrepared(runId: runId)
  }

  func executeDelegate(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    delegate.execute(action: action, screen: screen)
  }

  func adapterFamily(agentId: String) -> String {
    registration(agentId: agentId)?.agentAdapterFamily() ?? ""
  }

  func healthScope(agentId: String) -> String {
    registration(agentId: agentId)?.runtimeHealthScope() ?? ""
  }

  private func transport(agentId: String) -> ActionExecutorAgentTransport {
    lock.lock()
    defer { lock.unlock() }
    if let transport = transportsByAgentId[agentId] {
      return transport
    }
    let transport = ActionExecutorAgentTransport(
      registrationSource: { [weak self] in
        self?.registrationSnapshot() ?? []
      },
      delegate: delegate,
      recoverableSource: recoverableSource,
      agentId: agentId,
      runEventStore: runEventStore,
      managedResponseLedger: managedResponseLedger,
      terminalDeliveryStore: terminalDeliveryStore
    )
    transportsByAgentId[agentId] = transport
    return transport
  }

  private func transportIfPresent(agentId: String) -> ActionExecutorAgentTransport? {
    lock.lock()
    defer { lock.unlock() }
    return transportsByAgentId[agentId]
  }

  private func registrationSnapshot(
    nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> [AgentRegistration] {
    lock.lock()
    defer { lock.unlock() }
    if let cachedRegistrations,
       nowUptime - registrationsCachedAtUptime <= Self.registrationCacheTTL {
      return cachedRegistrations
    }
    let registrations = registrationSource()
    cachedRegistrations = registrations
    registrationsCachedAtUptime = nowUptime
    return registrations
  }
}

private final class ActionExecutorAgentTransport: AgentAdapterTransport {
  private struct PreparedAction {
    var action: AgentAction
    var screen: AgentScreenContext
    var registration: AgentRegistration
  }

  private struct ActiveRun {
    var request: AgentRunRequest
    var action: AgentAction
    var registration: AgentRegistration
    var sourceMessageId: Int64
    var contactId: String
  }

  private struct RunEventContext {
    var request: AgentRunRequest
    var action: AgentAction
    var registration: AgentRegistration
  }

  private let registrationSource: () -> [AgentRegistration]
  private let delegate: AgentActionExecutor
  private let recoverableSource: () -> [AgentRecoverableRun]
  private let agentId: String
  private let runEventStore: AgentRunEventPersistence?
  private let managedResponseLedger: AgentManagedResponseLedger
  private let terminalDeliveryStore: AgentTerminalDeliveryStoring
  private let lock = NSRecursiveLock()
  private var preparedByRunId: [String: PreparedAction] = [:]
  private var resultsByRunId: [String: AgentActionResult] = [:]
  private var activeByRunId: [String: ActiveRun] = [:]
  private var eventContextsByRunId: [String: RunEventContext] = [:]
  private var eventBuffersByRunId: [String: [AgentRunControlEvent]] = [:]
  private var continuationsByRunId: [String: [UUID: AsyncStream<AgentRunControlEvent>.Continuation]] = [:]

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun],
    agentId: String,
    runEventStore: AgentRunEventPersistence?,
    managedResponseLedger: AgentManagedResponseLedger,
    terminalDeliveryStore: AgentTerminalDeliveryStoring
  ) {
    self.registrationSource = registrationSource
    self.delegate = delegate
    self.recoverableSource = recoverableSource
    self.agentId = agentId
    self.runEventStore = runEventStore
    self.managedResponseLedger = managedResponseLedger
    self.terminalDeliveryStore = terminalDeliveryStore
  }

  func prepare(runId: String, action: AgentAction, screen: AgentScreenContext, registration: AgentRegistration) {
    lock.lock()
    preparedByRunId[runId] = PreparedAction(action: action, screen: screen, registration: registration)
    lock.unlock()
  }

  func result(runId: String) -> AgentActionResult? {
    lock.lock()
    defer { lock.unlock() }
    return resultsByRunId[runId]
  }

  func discardPrepared(runId: String) {
    lock.lock()
    preparedByRunId.removeValue(forKey: runId)
    eventContextsByRunId.removeValue(forKey: runId)
    trimIfNeeded(&resultsByRunId)
    lock.unlock()
  }

  func open() async throws -> AgentProtocolRange {
    try currentRegistration().`protocol`
  }

  func close() async {}

  func status() async throws -> AgentRegistration {
    try currentRegistration()
  }

  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle {
    let item: PreparedAction
    lock.lock()
    if let prepared = preparedByRunId.removeValue(forKey: request.runId) {
      item = prepared
      lock.unlock()
    } else {
      lock.unlock()
      throw AgentControlPlaneAdapterError(message: "No prepared connector action for Run \(request.runId)")
    }
    lock.lock()
    eventContextsByRunId[request.runId] = RunEventContext(
      request: request,
      action: item.action,
      registration: item.registration
    )
    trimIfNeeded(&eventContextsByRunId)
    lock.unlock()
    emitAll(
      request: request,
      registration: item.registration,
      events: [
        (type: .runCreated, sequence: 1, payload: ["action_id": .string(item.action.id)]),
        (type: .runStarted, sequence: 2, payload: [:]),
        (type: .agentConnected, sequence: 3, payload: [:])
      ]
    )
    var result = delegate.execute(action: item.action, screen: item.screen)
    let awaitingResponse = result.metadata["awaiting_response"] == "true"
    if awaitingResponse {
      var metadata = result.metadata
      metadata["conversation_id"] = (metadata["conversation_id"] ?? "")
        .ifBlank(request.conversationId)
      metadata["turn_id"] = (metadata["turn_id"] ?? "")
        .ifBlank(request.messageId)
      metadata["task_id"] = (metadata["task_id"] ?? "")
        .ifBlank(metadata["remote_task_id"] ?? "")
        .ifBlank(request.taskId)
      result = AgentActionResult(
        actionId: result.actionId,
        success: result.success,
        message: result.message,
        metadata: metadata
      )
    }
    lock.lock()
    resultsByRunId[request.runId] = result
    lock.unlock()
    let sourceMessageId = Int64(result.metadata["source_message_id"] ?? "") ?? 0
    let contactId = result.metadata["contact_id"] ?? ""
    if awaitingResponse && sourceMessageId > 0 {
      let responseConversationId = result.metadata["conversation_id"] ?? request.conversationId
      let responseTurnId = result.metadata["turn_id"] ?? request.messageId
      let responseTaskId = result.metadata["task_id"] ?? request.taskId
      lock.lock()
      activeByRunId[request.runId] = ActiveRun(
        request: request,
        action: item.action,
        registration: item.registration,
        sourceMessageId: sourceMessageId,
        contactId: contactId
      )
      lock.unlock()
      try? managedResponseLedger.register(
        AgentManagedResponseRecord(
          ownerRunId: request.runId,
          supervisorRunId: request.parentRunId,
          agentId: agentId,
          deliveryMode: request.deliveryMode,
          sourceMessageId: sourceMessageId,
          contactId: contactId,
          conversationId: responseConversationId,
          turnId: responseTurnId,
          taskId: responseTaskId
        )
      )
      try? AgentManagedConnectorResponseRegistry.shared.register(
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        ownerId: request.runId,
        conversationId: responseConversationId,
        turnId: responseTurnId,
        taskId: responseTaskId
      ) { [weak self] response in
        guard let self else { return false }
        return self.acceptConnectorResponse(response) != nil
      }
    }
    emit(
      request: request,
      registration: item.registration,
      type: awaitingResponse && sourceMessageId > 0 ? .waitingForDevice : (result.success ? .runCompleted : .runFailed),
      sequence: 4,
      payload: [
        "action_id": .string(item.action.id),
        "success": .bool(result.success),
        "source_message_id": .string(result.metadata["source_message_id"] ?? ""),
        "result": .string(result.message),
        "error": .string(result.success ? "" : result.message)
      ]
    )
    if !(awaitingResponse && sourceMessageId > 0) {
      lock.lock()
      eventContextsByRunId.removeValue(forKey: request.runId)
      lock.unlock()
    }
    let remoteRunId = (result.metadata["remote_task_id"] ?? "")
      .ifBlank(result.metadata["source_message_id"] ?? "")
      .ifBlank(request.runId)
    return AgentRunHandle(
      runId: request.runId,
      taskId: request.taskId,
      agentId: agentId,
      remoteRunId: remoteRunId
    )
  }

  func sendMessage(runId: String, message: AgentControlMessage) async throws {
    guard message.deliveryMode != .ignore else {
      return
    }
    throw AgentControlPlaneAdapterError(message: "Follow-up messages require a prepared connector action")
  }

  func cancelRun(runId: String) async throws {
    lock.lock()
    preparedByRunId.removeValue(forKey: runId)
    let active = activeByRunId.removeValue(forKey: runId)
    eventContextsByRunId.removeValue(forKey: runId)
    let current = resultsByRunId[runId]
    var metadata = current?.metadata ?? [:]
    metadata["cancelled"] = "true"
    let cancelled = AgentActionResult(
      actionId: current?.actionId ?? runId,
      success: false,
      message: "Agent Run cancelled",
      metadata: metadata
    )
    resultsByRunId[runId] = cancelled
    lock.unlock()
    clearManagedResponse(runId: runId)
    if let active {
      terminalDeliveryStore.mark(terminalDelivery(
        active: active,
        result: cancelled,
        reason: "Agent Run cancelled"
      ))
      emit(
        request: active.request,
        registration: active.registration,
        type: .runCancelled,
        sequence: 3,
        payload: ["message": .string("Agent Run cancelled")]
      )
    }
  }

  func acceptConnectorResponse(_ response: AgentConnectorResponse) -> AgentActionResult? {
    let active: ActiveRun
    let settlement: AgentConnectorResponseSettlement
    let runId: String
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorResponseResolver.canAccept(pending: pending, response: response)
    }), let pending = resultsByRunId[match.key],
      let resolved = AgentConnectorResponseResolver.settle(pending: pending, response: response) else {
      lock.unlock()
      return nil
    }
    runId = match.key
    active = match.value
    settlement = resolved
    resultsByRunId[runId] = resolved.result
    activeByRunId.removeValue(forKey: runId)
    eventContextsByRunId.removeValue(forKey: runId)
    lock.unlock()
    _ = managedResponseLedger.acknowledge(response)
    emit(
      request: active.request,
      registration: active.registration,
      type: settlement.eventType,
      sequence: 5,
      payload: settlement.eventPayload
    )
    return settlement.result
  }

  func acceptConnectorTerminalStatus(_ envelope: AgentConnectorTerminalStatusEnvelope) -> AgentActionResult? {
    let runId: String
    let active: ActiveRun
    let settlement: AgentConnectorTerminalStatusSettlement
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard item.value.sourceMessageId == envelope.sourceMessageId,
        let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorTerminalStatusResolver.canAccept(pending: pending, envelope: envelope)
    }), let pending = resultsByRunId[match.key],
      let resolved = AgentConnectorTerminalStatusResolver.settle(pending: pending, envelope: envelope) else {
      lock.unlock()
      return nil
    }
    runId = match.key
    active = match.value
    settlement = resolved
    resultsByRunId[runId] = resolved.result
    if resolved.shouldDeactivateRun {
      activeByRunId.removeValue(forKey: runId)
      eventContextsByRunId.removeValue(forKey: runId)
    }
    lock.unlock()
    if resolved.shouldDeactivateRun {
      clearManagedResponse(runId: runId)
      terminalDeliveryStore.mark(AgentTerminalDelivery(
        sourceMessageId: envelope.sourceMessageId,
        conversationId: envelope.conversationId.ifBlank(active.request.conversationId),
        turnId: envelope.turnId.ifBlank(settlement.result.metadata["turn_id"] ?? ""),
        taskId: envelope.taskId.ifBlank(active.request.taskId),
        contactId: envelope.contactId.ifBlank(active.contactId),
        reason: settlement.result.message,
        terminalAtMillis: envelope.nowMillis
      ))
    }
    if let eventType = settlement.eventType {
      emit(
        request: active.request,
        registration: active.registration,
        type: eventType,
        sequence: max(3, envelope.statusSeq),
        payload: settlement.eventPayload
      )
    }
    return settlement.result
  }

  func recordConnectorTaskStatus(_ envelope: AgentConnectorTerminalStatusEnvelope) -> AgentActionResult? {
    let record: AgentConnectorTaskStatusRecord
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard item.value.sourceMessageId == envelope.sourceMessageId,
        let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorTerminalStatusResolver.canAccept(pending: pending, envelope: envelope)
    }), let pending = resultsByRunId[match.key],
      let resolved = AgentConnectorTaskStatusRecorder.record(pending: pending, envelope: envelope) else {
      lock.unlock()
      return nil
    }
    record = resolved
    resultsByRunId[match.key] = resolved.result
    lock.unlock()
    return record.result
  }

  func recordConnectorTransportAccepted(
    sourceMessageId: Int64,
    contactId: String,
    nowMillis: Int64
  ) -> AgentActionResult? {
    let updated: AgentActionResult
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard item.value.sourceMessageId == sourceMessageId,
        let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorTransportReceiptRecorder.canAcceptTransport(
        pending: pending,
        sourceMessageId: sourceMessageId,
        contactId: contactId
      )
    }), let pending = resultsByRunId[match.key],
      let result = AgentConnectorTransportReceiptRecorder.recordAccepted(
        pending: pending,
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        nowMillis: nowMillis
      ) else {
      lock.unlock()
      return nil
    }
    updated = result
    resultsByRunId[match.key] = result
    lock.unlock()
    return updated
  }

  func handleConnectorTimeout(
    sourceMessageId: Int64,
    stage: AgentConnectorTimeoutStage,
    nowMillis: Int64
  ) -> AgentActionResult? {
    let active: ActiveRun
    let timeout: AgentConnectorTimeoutResolution
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard item.value.sourceMessageId == sourceMessageId,
        let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorTimeoutResolver.resolve(
        pending: pending,
        sourceMessageId: sourceMessageId,
        stage: stage,
        nowMillis: nowMillis
      ) != nil
    }), let pending = resultsByRunId[match.key],
      let resolved = AgentConnectorTimeoutResolver.resolve(
        pending: pending,
        sourceMessageId: sourceMessageId,
        stage: stage,
        nowMillis: nowMillis
      ) else {
      lock.unlock()
      return nil
    }
    active = match.value
    timeout = resolved
    resultsByRunId[match.key] = resolved.result
    if resolved.shouldDeactivateRun {
      activeByRunId.removeValue(forKey: match.key)
      eventContextsByRunId.removeValue(forKey: match.key)
    }
    lock.unlock()
    if resolved.shouldDeactivateRun {
      clearManagedResponse(runId: match.key)
      terminalDeliveryStore.mark(terminalDelivery(
        active: active,
        result: timeout.result,
        reason: timeout.result.message,
        terminalAtMillis: nowMillis
      ))
    }
    emit(
      request: active.request,
      registration: active.registration,
      type: .runFailed,
      sequence: 3,
      payload: timeout.eventPayload
    )
    return timeout.result
  }

  private func terminalDelivery(
    active: ActiveRun,
    result: AgentActionResult?,
    reason: String,
    terminalAtMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentTerminalDelivery {
    let metadata = result?.metadata ?? [:]
    return AgentTerminalDelivery(
      sourceMessageId: active.sourceMessageId,
      conversationId: metadata["conversation_id"]?.ifBlank(active.request.conversationId) ?? active.request.conversationId,
      turnId: metadata["turn_id"] ?? "",
      taskId: metadata["remote_task_id"]?.ifBlank(active.request.taskId) ?? active.request.taskId,
      contactId: metadata["contact_id"]?.ifBlank(active.contactId) ?? active.contactId,
      reason: reason,
      terminalAtMillis: terminalAtMillis
    )
  }

  func acceptConnectorSteered(
    sourceMessageId: Int64,
    contactId: String,
    mergedIntoTaskId: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    nowMillis: Int64
  ) -> AgentActionResult? {
    let active: ActiveRun
    let steered: AgentConnectorSteeredResult
    lock.lock()
    guard let match = activeByRunId.first(where: { item in
      guard item.value.sourceMessageId == sourceMessageId,
        let pending = resultsByRunId[item.key] else {
        return false
      }
      return AgentConnectorSteeredResultResolver.canAccept(
        pending: pending,
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        conversationId: conversationId,
        turnId: turnId,
        taskId: taskId
      )
    }), let pending = resultsByRunId[match.key],
      let resolved = AgentConnectorSteeredResultResolver.resolve(
        pending: pending,
        sourceMessageId: sourceMessageId,
        contactId: contactId,
        mergedIntoTaskId: mergedIntoTaskId,
        conversationId: conversationId,
        turnId: turnId,
        taskId: taskId,
        nowMillis: nowMillis
      ) else {
      lock.unlock()
      return nil
    }
    active = match.value
    steered = resolved
    resultsByRunId[match.key] = resolved.result
    activeByRunId.removeValue(forKey: match.key)
    eventContextsByRunId.removeValue(forKey: match.key)
    lock.unlock()
    clearManagedResponse(runId: match.key)
    emit(
      request: active.request,
      registration: active.registration,
      type: .runCompleted,
      sequence: 3,
      payload: steered.eventPayload
    )
    return steered.result
  }

  func forceTaskTimeout(runId: String, message: String, nowMillis: Int64) -> AgentActionResult? {
    let active: ActiveRun
    let timeout: AgentTaskWatchdogTimeoutResult
    lock.lock()
    guard let matchedActive = activeByRunId.removeValue(forKey: runId),
      let pending = resultsByRunId[runId] else {
      lock.unlock()
      return nil
    }
    active = matchedActive
    timeout = AgentTaskWatchdogTimeoutResolver.resolve(
      pending: pending,
      message: message,
      nowMillis: nowMillis
    )
    resultsByRunId[runId] = timeout.result
    eventContextsByRunId.removeValue(forKey: runId)
    lock.unlock()
    clearManagedResponse(runId: runId)
    emit(
      request: active.request,
      registration: active.registration,
      type: .runFailed,
      sequence: 3,
      payload: timeout.eventPayload
    )
    return timeout.result
  }

  private func clearManagedResponse(runId: String) {
    AgentManagedConnectorResponseRegistry.shared.unregisterOwner(runId)
    managedResponseLedger.removeOwner(runId)
  }

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    AsyncStream(bufferingPolicy: .bufferingNewest(Self.eventReplay)) { continuation in
      let token = UUID()
      lock.lock()
      let persisted = runEventStore?.events(runId: runId) ?? []
      let buffered = eventBuffersByRunId[runId] ?? []
      var seenEventIds = Set<String>()
      for event in persisted where seenEventIds.insert(event.eventId).inserted {
        continuation.yield(event)
      }
      for event in buffered where seenEventIds.insert(event.eventId).inserted {
        continuation.yield(event)
      }
      continuationsByRunId[runId, default: [:]][token] = continuation
      lock.unlock()
      continuation.onTermination = { [weak self] _ in
        self?.lock.lock()
        self?.continuationsByRunId[runId]?.removeValue(forKey: token)
        self?.lock.unlock()
      }
    }
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    recoverableSource().filter { $0.handle.agentId == agentId }
  }

  func recordNativeToolLifecycleEvent(
    _ event: AgentNativeToolLifecycleEvent,
    agentId: String,
    deviceId: String
  ) -> AgentRunControlEvent? {
    lock.lock()
    guard let context = matchedEventContextLocked(event) else {
      lock.unlock()
      return nil
    }
    lock.unlock()
    let controlEvent = AgentNativeToolRunControlAdapter.controlEvent(
      from: event,
      runId: context.request.runId,
      conversationId: context.request.conversationId,
      messageId: event.turnId.ifBlank(context.request.messageId),
      taskId: event.turnId.ifBlank(context.request.taskId),
      agentId: agentId.ifBlank("signalasi-mobile"),
      deviceId: deviceId.ifBlank(context.registration.deviceId),
      sequence: event.sequence
    )
    append(controlEvent)
    return controlEvent
  }

  private func currentRegistration() throws -> AgentRegistration {
    guard let registration = registrationSource().first(where: { $0.agentId == agentId }) else {
      throw AgentControlPlaneAdapterError(message: "Agent registration is no longer available: \(agentId)")
    }
    return registration
  }

  private func emit(
    request: AgentRunRequest,
    registration: AgentRegistration,
    type: AgentRunControlEventType,
    sequence: Int64,
    payload: AgentRunControlPayload = [:]
  ) {
    let event = AgentRunControlEvent(
      conversationId: request.conversationId,
      messageId: request.messageId,
      taskId: request.taskId,
      runId: request.runId,
      agentId: registration.agentId,
      deviceId: registration.deviceId,
      type: type,
      sequence: sequence,
      payload: payload
    )
    append(event)
  }

  private func emitAll(
    request: AgentRunRequest,
    registration: AgentRegistration,
    events: [(type: AgentRunControlEventType, sequence: Int64, payload: AgentRunControlPayload)]
  ) {
    appendAll(events.map { item in
      AgentRunControlEvent(
        conversationId: request.conversationId,
        messageId: request.messageId,
        taskId: request.taskId,
        runId: request.runId,
        agentId: registration.agentId,
        deviceId: registration.deviceId,
        type: item.type,
        sequence: item.sequence,
        payload: item.payload
      )
    })
  }

  private func append(_ event: AgentRunControlEvent) {
    appendAll([event])
  }

  private func appendAll(_ events: [AgentRunControlEvent]) {
    guard !events.isEmpty else {
      return
    }
    let persistedEvents: [AgentRunControlEvent]
    if let runEventStore {
      var groups: [String: [AgentRunControlEvent]] = [:]
      var order: [String] = []
      for event in events {
        if groups[event.runId] == nil {
          order.append(event.runId)
        }
        groups[event.runId, default: []].append(event)
      }
      persistedEvents = order.flatMap { runEventStore.appendNextAll(groups[$0] ?? []) }
    } else {
      persistedEvents = events
    }
    guard !persistedEvents.isEmpty else {
      return
    }
    var deliveries: [(AgentRunControlEvent, [AsyncStream<AgentRunControlEvent>.Continuation])] = []
    lock.lock()
    for persisted in persistedEvents {
      var buffer = eventBuffersByRunId[persisted.runId] ?? []
      buffer.append(persisted)
      eventBuffersByRunId[persisted.runId] = Array(buffer.suffix(Self.eventReplay))
      let continuations = continuationsByRunId[persisted.runId].map { Array($0.values) } ?? []
      deliveries.append((persisted, continuations))
    }
    lock.unlock()
    for (event, continuations) in deliveries {
      continuations.forEach { $0.yield(event) }
    }
  }

  private func matchedEventContextLocked(_ event: AgentNativeToolLifecycleEvent) -> RunEventContext? {
    let contexts = Array(eventContextsByRunId.values)
    return contexts.first { matchesTurn(event, context: $0) && matchesConversation(event, context: $0) } ??
      contexts.first { matchesInvocation(event, context: $0) && matchesConversation(event, context: $0) }
  }

  private func matchesTurn(_ event: AgentNativeToolLifecycleEvent, context: RunEventContext) -> Bool {
    let turnId = event.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !turnId.isEmpty else { return false }
    let actionTurnId = context.action.parameters["_signalasi_turn_id"] ?? ""
    return [
      context.request.messageId,
      context.request.taskId,
      context.request.runId,
      actionTurnId
    ].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == turnId }
  }

  private func matchesInvocation(_ event: AgentNativeToolLifecycleEvent, context: RunEventContext) -> Bool {
    let ids = [
      event.invocationId,
      event.stepId
    ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !ids.isEmpty else { return false }
    let actionInvocationId = context.action.parameters["invocation_id"] ?? ""
    let known = [
      context.action.id,
      actionInvocationId,
      context.request.runId
    ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return ids.contains { known.contains($0) }
  }

  private func matchesConversation(_ event: AgentNativeToolLifecycleEvent, context: RunEventContext) -> Bool {
    let conversationId = event.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationId.isEmpty else { return true }
    let actionConversationId = context.action.parameters["_signalasi_conversation_id"] ?? ""
    return [
      context.request.conversationId,
      actionConversationId
    ].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == conversationId }
  }

  private func trimIfNeeded<T>(_ map: inout [String: T]) {
    guard map.count > Self.maxTrackedRuns else {
      return
    }
    let overflow = map.count - Self.maxTrackedRuns
    for key in Array(map.keys.prefix(overflow)) {
      map.removeValue(forKey: key)
    }
  }

  private static let eventReplay = 32
  private static let maxTrackedRuns = 256
}

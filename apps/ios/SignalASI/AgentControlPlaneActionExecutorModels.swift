import CryptoKit
import Foundation

final class AgentControlPlaneActionExecutor: AgentActionExecutor {
  private let provider: ActionExecutorAgentProvider
  private let directory: AgentAdapterDirectory

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun] = { [] },
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore()
  ) {
    let provider = ActionExecutorAgentProvider(
      registrationSource: registrationSource,
      delegate: delegate,
      recoverableSource: recoverableSource,
      runStartReceipts: runStartReceipts
    )
    self.provider = provider
    let directory = AgentAdapterDirectory()
    try? directory.register(provider)
    self.directory = directory
  }

  init(provider: ActionExecutorAgentProvider) {
    self.provider = provider
    let directory = AgentAdapterDirectory()
    try? directory.register(provider)
    self.directory = directory
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard action.kind == .callConnector else {
      return provider.executeDelegate(action: action, screen: screen)
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
      idempotencyKey: (action.parameters["idempotency_key"] ?? "").ifBlank(runId)
    )
    provider.prepare(agentId: agentId, request: request, action: action, screen: screen)
    do {
      guard let adapter = try Self.awaitBlocking({ try await self.directory.resolveAdapter(agentId) }) else {
        provider.discardPrepared(agentId: agentId, runId: runId)
        return provider.executeDelegate(action: action, screen: screen)
      }
      let handle = try Self.awaitBlocking({ try await adapter.startRun(request) })
      let dispatchResult = provider.result(agentId: agentId, runId: handle.runId)
      provider.discardPrepared(agentId: agentId, runId: runId)
      if var result = dispatchResult {
        result.metadata.merge([
          "control_plane_run_id": handle.runId,
          "control_plane_agent_id": handle.agentId,
          "control_plane_remote_run_id": handle.remoteRunId,
          "control_plane_adapter_family": provider.adapterFamily(agentId: agentId),
          "control_plane_health_scope": provider.healthScope(agentId: agentId)
        ]) { _, new in new }
        return result
      }
      if request.deliveryMode == .ignore {
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
      provider.discardPrepared(agentId: agentId, runId: runId)
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: error.localizedDescription.isEmpty ? "Agent Adapter dispatch failed" : error.localizedDescription,
        metadata: [
          "control_plane_run_id": runId,
          "control_plane_agent_id": agentId,
          "provider_circuit_open": "false",
          "provider_health_scope": provider.healthScope(agentId: agentId),
          "provider_retry_at_millis": ""
        ]
      )
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
  private let localProtocol: AgentProtocolRange
  private let lock = NSRecursiveLock()
  private var transportsByAgentId: [String: ActionExecutorAgentTransport] = [:]
  private var adaptersByAgentId: [String: AgentAdapter] = [:]
  let providerId: String

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun] = { [] },
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore(),
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
    self.providerId = providerId
    self.localProtocol = localProtocol
  }

  func connect() async throws -> AgentProtocolAgreement {
    AgentProtocolAgreement(version: localProtocol.preferred, features: localProtocol.features)
  }

  func disconnect() async {
    lock.lock()
    let adapters = Array(adaptersByAgentId.values)
    adaptersByAgentId.removeAll()
    transportsByAgentId.removeAll()
    lock.unlock()
    for adapter in adapters {
      await adapter.disconnect()
    }
  }

  func registrations() async throws -> [AgentRegistration] {
    registrationSource()
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
    let adapter = TransportBackedAgentAdapter(
      initialRegistration: registration,
      transport: transport,
      localProtocol: localProtocol,
      runStartReceipts: runStartReceipts
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

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    recoverableSource()
  }

  func registration(agentId: String) -> AgentRegistration? {
    registrationSource().first { $0.agentId == agentId }
  }

  func resolveAgentId(_ requested: String) -> String? {
    let clean = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return nil
    }
    let registrations = registrationSource()
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

  func discardPrepared(agentId: String, runId: String) {
    transportIfPresent(agentId: agentId)?.discardPrepared(runId: runId)
  }

  func executeDelegate(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    delegate.execute(action: action, screen: screen)
  }

  func adapterFamily(agentId: String) -> String {
    let adapterType = registration(agentId: agentId)?.adapterType.lowercased() ?? ""
    if adapterType.contains("codex") { return "codex" }
    if adapterType.contains("claude") { return "claude" }
    if adapterType.contains("openclaw") { return "openclaw" }
    return ""
  }

  func healthScope(agentId: String) -> String {
    let registration = registration(agentId: agentId)
    return registration?.runtimeFailureDomain.ifBlank(registration?.failureDomain ?? "") ?? ""
  }

  private func transport(agentId: String) -> ActionExecutorAgentTransport {
    lock.lock()
    defer { lock.unlock() }
    if let transport = transportsByAgentId[agentId] {
      return transport
    }
    let transport = ActionExecutorAgentTransport(
      registrationSource: registrationSource,
      delegate: delegate,
      recoverableSource: recoverableSource,
      agentId: agentId
    )
    transportsByAgentId[agentId] = transport
    return transport
  }

  private func transportIfPresent(agentId: String) -> ActionExecutorAgentTransport? {
    lock.lock()
    defer { lock.unlock() }
    return transportsByAgentId[agentId]
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

  private let registrationSource: () -> [AgentRegistration]
  private let delegate: AgentActionExecutor
  private let recoverableSource: () -> [AgentRecoverableRun]
  private let agentId: String
  private let lock = NSRecursiveLock()
  private var preparedByRunId: [String: PreparedAction] = [:]
  private var resultsByRunId: [String: AgentActionResult] = [:]
  private var activeByRunId: [String: ActiveRun] = [:]
  private var eventBuffersByRunId: [String: [AgentRunControlEvent]] = [:]
  private var continuationsByRunId: [String: [UUID: AsyncStream<AgentRunControlEvent>.Continuation]] = [:]

  init(
    registrationSource: @escaping () -> [AgentRegistration],
    delegate: AgentActionExecutor,
    recoverableSource: @escaping () -> [AgentRecoverableRun],
    agentId: String
  ) {
    self.registrationSource = registrationSource
    self.delegate = delegate
    self.recoverableSource = recoverableSource
    self.agentId = agentId
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
    emit(request: request, registration: item.registration, type: .agentConnected, sequence: 1)
    let result = delegate.execute(action: item.action, screen: item.screen)
    lock.lock()
    resultsByRunId[request.runId] = result
    lock.unlock()
    let awaitingResponse = result.metadata["awaiting_response"] == "true"
    let sourceMessageId = Int64(result.metadata["source_message_id"] ?? "") ?? 0
    let contactId = result.metadata["contact_id"] ?? ""
    if awaitingResponse && sourceMessageId > 0 {
      lock.lock()
      activeByRunId[request.runId] = ActiveRun(
        request: request,
        action: item.action,
        registration: item.registration,
        sourceMessageId: sourceMessageId,
        contactId: contactId
      )
      lock.unlock()
    }
    emit(
      request: request,
      registration: item.registration,
      type: awaitingResponse && sourceMessageId > 0 ? .waitingForDevice : (result.success ? .runCompleted : .runFailed),
      sequence: 2,
      payload: [
        "action_id": .string(item.action.id),
        "success": .bool(result.success),
        "source_message_id": .string(result.metadata["source_message_id"] ?? ""),
        "result": .string(result.message),
        "error": .string(result.success ? "" : result.message)
      ]
    )
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
    let current = resultsByRunId[runId]
    var metadata = current?.metadata ?? [:]
    metadata["cancelled"] = "true"
    resultsByRunId[runId] = AgentActionResult(
      actionId: current?.actionId ?? runId,
      success: false,
      message: "Agent Run cancelled",
      metadata: metadata
    )
    lock.unlock()
    if let active {
      emit(
        request: active.request,
        registration: active.registration,
        type: .runCancelled,
        sequence: 3,
        payload: ["message": .string("Agent Run cancelled")]
      )
    }
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
    }
    lock.unlock()
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

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    AsyncStream(bufferingPolicy: .bufferingNewest(Self.eventReplay)) { continuation in
      let token = UUID()
      lock.lock()
      let buffered = eventBuffersByRunId[runId] ?? []
      for event in buffered {
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
    lock.lock()
    var buffer = eventBuffersByRunId[request.runId] ?? []
    buffer.append(event)
    eventBuffersByRunId[request.runId] = Array(buffer.suffix(Self.eventReplay))
    let continuations = continuationsByRunId[request.runId].map { Array($0.values) } ?? []
    lock.unlock()
    continuations.forEach { $0.yield(event) }
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

private extension String {
  func ifBlank(_ fallback: String) -> String {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
  }
}

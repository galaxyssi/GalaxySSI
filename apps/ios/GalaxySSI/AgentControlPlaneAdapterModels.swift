import Foundation

struct AgentControlPlaneAdapterError: Error, Equatable {
  var message: String
}

extension AgentControlPlaneAdapterError: LocalizedError {
  var errorDescription: String? { message }
}

protocol AgentAdapter: AnyObject {
  var registration: AgentRegistration { get }
  func connect() async throws -> AgentProtocolAgreement
  func disconnect() async
  func status() async throws -> AgentRegistration
  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle
  func sendMessage(runId: String, message: AgentControlMessage) async throws
  func cancelRun(runId: String) async throws
  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent>
  func recoverRuns() async throws -> [AgentRecoverableRun]
}

protocol AgentProvider: AnyObject {
  var providerId: String { get }
  func connect() async throws -> AgentProtocolAgreement
  func disconnect() async
  func registrations() async throws -> [AgentRegistration]
  func adapter(agentId: String) async throws -> AgentAdapter?
  func recoverRuns() async throws -> [AgentRecoverableRun]
}

protocol AgentAdapterTransport: AnyObject {
  func open() async throws -> AgentProtocolRange
  func close() async
  func status() async throws -> AgentRegistration
  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle
  func sendMessage(runId: String, message: AgentControlMessage) async throws
  func cancelRun(runId: String) async throws
  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent>
  func recoverRuns() async throws -> [AgentRecoverableRun]
}

protocol AgentProviderTransport: AnyObject {
  func open() async throws -> AgentProtocolRange
  func close() async
  func registrations() async throws -> [AgentRegistration]
  func adapterTransport(agentId: String) async throws -> (AgentRegistration, AgentAdapterTransport)?
  func recoverRuns() async throws -> [AgentRecoverableRun]
}

final class TransportBackedAgentAdapter: AgentAdapter {
  private let transport: AgentAdapterTransport
  private let localProtocol: AgentProtocolRange
  private let runStartReceipts: AgentRunStartReceiptStore
  private var currentRegistration: AgentRegistration
  private var agreement: AgentProtocolAgreement?

  var registration: AgentRegistration { currentRegistration }

  init(
    initialRegistration: AgentRegistration,
    transport: AgentAdapterTransport,
    localProtocol: AgentProtocolRange? = nil,
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore()
  ) {
    self.transport = transport
    self.localProtocol = localProtocol ?? initialRegistration.`protocol`
    self.runStartReceipts = runStartReceipts
    self.currentRegistration = initialRegistration
  }

  func connect() async throws -> AgentProtocolAgreement {
    if let agreement {
      return agreement
    }
    let remoteProtocol = try await transport.open()
    guard let negotiated = AgentProtocolNegotiator.negotiate(local: localProtocol, remote: remoteProtocol) else {
      await transport.close()
      throw AgentControlPlaneAdapterError(message: "No compatible GalaxySSI Agent protocol version")
    }
    agreement = negotiated
    return negotiated
  }

  func disconnect() async {
    await transport.close()
    agreement = nil
  }

  func status() async throws -> AgentRegistration {
    _ = try await ensureConnected()
    let remote = try await transport.status()
    guard remote.agentId == currentRegistration.agentId else {
      throw AgentControlPlaneAdapterError(message: "Agent identity changed during a connection")
    }
    guard remote.installationId == currentRegistration.installationId else {
      throw AgentControlPlaneAdapterError(message: "Agent installation identity changed during a connection")
    }
    currentRegistration = remote
    return remote
  }

  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle {
    guard !request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentControlPlaneAdapterError(message: "Run idempotency key must not be blank")
    }
    let existedBeforeReservation = runStartReceipts.find(
      agentId: currentRegistration.agentId,
      idempotencyKey: request.idempotencyKey
    ) != nil
    let receipt = try runStartReceipts.reserve(registration: currentRegistration, request: request)
    switch receipt.status {
    case .accepted:
      guard let handle = receipt.handle else {
        throw AgentControlPlaneAdapterError(message: "Accepted Run receipt is missing its handle")
      }
      return handle
    case .cancelled:
      throw AgentControlPlaneAdapterError(message: "Run idempotency key belongs to a cancelled Run")
    case .reserved, .outcomeUnknown:
      if existedBeforeReservation {
        if let recovered = try await recoverReservedRun(request) {
          return try runStartReceipts.accept(
            agentId: currentRegistration.agentId,
            idempotencyKey: request.idempotencyKey,
            handle: recovered
          ).handle!
        }
        throw AgentControlPlaneAdapterError(message: "Run start outcome is unresolved; duplicate execution was blocked")
      }
    }
    do {
      let handle: AgentRunHandle
      if request.deliveryMode == .ignore {
        handle = AgentRunHandle(
          runId: request.runId,
          taskId: request.taskId,
          agentId: currentRegistration.agentId,
          remoteRunId: ""
        )
      } else {
        let negotiated = try await ensureConnected()
        if request.deliveryMode == .observe {
          try requireFeature(negotiated, "message.observe")
        }
        handle = try await transport.startRun(request)
      }
      return try runStartReceipts.accept(
        agentId: currentRegistration.agentId,
        idempotencyKey: request.idempotencyKey,
        handle: handle
      ).handle!
    } catch {
      _ = runStartReceipts.markOutcomeUnknown(
        agentId: currentRegistration.agentId,
        idempotencyKey: request.idempotencyKey,
        error: String(describing: error)
      )
      throw error
    }
  }

  func sendMessage(runId: String, message: AgentControlMessage) async throws {
    let negotiated = try await ensureConnected()
    if message.deliveryMode == .observe {
      try requireFeature(negotiated, "message.observe")
    }
    if message.deliveryMode != .ignore {
      try await transport.sendMessage(runId: runId, message: message)
    }
  }

  func cancelRun(runId: String) async throws {
    try requireFeature(try await ensureConnected(), "run.cancel")
    try await transport.cancelRun(runId: runId)
    _ = runStartReceipts.markCancelledByRun(agentId: currentRegistration.agentId, runId: runId)
  }

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    transport.observeEvents(runId: runId)
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    let negotiated = try await ensureConnected()
    guard negotiated.features.contains("run.recover") else {
      return []
    }
    return try await transport.recoverRuns()
  }

  private func ensureConnected() async throws -> AgentProtocolAgreement {
    if let agreement {
      return agreement
    }
    return try await connect()
  }

  private func recoverReservedRun(_ request: AgentRunRequest) async throws -> AgentRunHandle? {
    let negotiated = try await ensureConnected()
    guard negotiated.features.contains("run.recover") else {
      return nil
    }
    let recoveredRuns = try await transport.recoverRuns()
    return recoveredRuns
      .map(\.handle)
      .first { handle in
        handle.agentId == currentRegistration.agentId &&
          (handle.runId == request.runId ||
            (handle.taskId == request.taskId && handle.remoteRunId == request.runId))
      }
  }

  private func requireFeature(_ negotiated: AgentProtocolAgreement, _ feature: String) throws {
    guard negotiated.features.contains(feature) else {
      throw AgentControlPlaneAdapterError(message: "Agent does not support \(feature)")
    }
  }
}

final class TransportBackedAgentProvider: AgentProvider {
  let providerId: String
  private let transport: AgentProviderTransport
  private let localProtocol: AgentProtocolRange
  private let runStartReceipts: AgentRunStartReceiptStore
  private var agreement: AgentProtocolAgreement?
  private let registrationCacheLock = NSLock()
  private var cachedRegistrations: [AgentRegistration] = []
  private var registrationsCachedAt: Date?

  private static let registrationCacheTTL: TimeInterval = 1

  init(
    providerId: String,
    transport: AgentProviderTransport,
    localProtocol: AgentProtocolRange,
    runStartReceipts: AgentRunStartReceiptStore = InMemoryAgentRunStartReceiptStore()
  ) {
    self.providerId = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.transport = transport
    self.localProtocol = localProtocol
    self.runStartReceipts = runStartReceipts
  }

  func connect() async throws -> AgentProtocolAgreement {
    if let agreement {
      return agreement
    }
    let remoteProtocol = try await transport.open()
    guard let negotiated = AgentProtocolNegotiator.negotiate(local: localProtocol, remote: remoteProtocol) else {
      await transport.close()
      throw AgentControlPlaneAdapterError(message: "No compatible GalaxySSI Provider protocol version")
    }
    agreement = negotiated
    return negotiated
  }

  func disconnect() async {
    await transport.close()
    agreement = nil
    registrationCacheLock.lock()
    cachedRegistrations = []
    registrationsCachedAt = nil
    registrationCacheLock.unlock()
  }

  func registrations() async throws -> [AgentRegistration] {
    _ = try await ensureConnected()
    if let cached = registrationCacheSnapshot() {
      return cached
    }
    let registrations = try await transport.registrations()
      .filter { $0.providerId == providerId }
    registrationCacheLock.lock()
    cachedRegistrations = registrations
    registrationsCachedAt = Date()
    registrationCacheLock.unlock()
    return registrations
  }

  func adapter(agentId: String) async throws -> AgentAdapter? {
    _ = try await ensureConnected()
    guard let (registration, adapterTransport) = try await transport.adapterTransport(agentId: agentId) else {
      return nil
    }
    guard registration.providerId == providerId else {
      throw AgentControlPlaneAdapterError(message: "Agent belongs to a different provider")
    }
    return TransportBackedAgentAdapter(
      initialRegistration: registration,
      transport: adapterTransport,
      localProtocol: localProtocol,
      runStartReceipts: runStartReceipts
    )
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    let negotiated = try await ensureConnected()
    guard negotiated.features.contains("run.recover") else {
      return []
    }
    return try await transport.recoverRuns()
  }

  private func ensureConnected() async throws -> AgentProtocolAgreement {
    if let agreement {
      return agreement
    }
    return try await connect()
  }

  private func registrationCacheSnapshot(now: Date = Date()) -> [AgentRegistration]? {
    registrationCacheLock.lock()
    defer { registrationCacheLock.unlock() }
    guard let cachedAt = registrationsCachedAt,
          now.timeIntervalSince(cachedAt) <= Self.registrationCacheTTL else {
      return nil
    }
    return cachedRegistrations
  }
}

final class AgentAdapterDirectory {
  private let lock = NSRecursiveLock()
  private var adaptersById: [String: AgentAdapter] = [:]
  private var providersById: [String: AgentProvider] = [:]

  @discardableResult
  func register(_ adapter: AgentAdapter) throws -> AgentAdapter? {
    let agentId = adapter.registration.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !agentId.isEmpty else {
      throw AgentControlPlaneAdapterError(message: "Agent id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    let previous = adaptersById[agentId]
    adaptersById[agentId] = adapter
    return previous
  }

  @discardableResult
  func register(_ provider: AgentProvider) throws -> AgentProvider? {
    let providerId = provider.providerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !providerId.isEmpty else {
      throw AgentControlPlaneAdapterError(message: "Provider id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    let previous = providersById[providerId]
    providersById[providerId] = provider
    return previous
  }

  func adapter(_ agentId: String) -> AgentAdapter? {
    lock.lock()
    defer { lock.unlock() }
    return adaptersById[agentId]
  }

  func provider(_ providerId: String) -> AgentProvider? {
    lock.lock()
    defer { lock.unlock() }
    return providersById[providerId]
  }

  func resolveAdapter(_ agentId: String) async throws -> AgentAdapter? {
    if let local = adapter(agentId) {
      return local
    }
    let providers = snapshotProviders()
    for provider in providers {
      if let resolved = try await provider.adapter(agentId: agentId) {
        lock.lock()
        let current = adaptersById[agentId]
        if current == nil {
          adaptersById[agentId] = resolved
        }
        let result = adaptersById[agentId]
        lock.unlock()
        return result
      }
    }
    return nil
  }

  func registrations() async throws -> [AgentRegistration] {
    var registrations = localRegistrations()
    for provider in snapshotProviders() {
      registrations.append(contentsOf: try await provider.registrations())
    }
    var seen = Set<String>()
    return registrations
      .filter { seen.insert($0.agentId).inserted }
      .sorted {
        if $0.displayName == $1.displayName {
          return $0.agentId < $1.agentId
        }
        return $0.displayName < $1.displayName
      }
  }

  func searchAgents(
    _ query: AgentNetworkSearchQuery,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) async throws -> AgentNetworkSearchPage {
    let registrations = try await registrations()
    return AgentNetworkIndex(registrations).search(query, nowMillis: nowMillis)
  }

  func localRegistrations() -> [AgentRegistration] {
    lock.lock()
    defer { lock.unlock() }
    return adaptersById.values
      .map(\.registration)
      .sorted {
        if $0.displayName == $1.displayName {
          return $0.agentId < $1.agentId
        }
        return $0.displayName < $1.displayName
      }
  }

  @discardableResult
  func unregisterAgent(_ agentId: String) -> AgentAdapter? {
    lock.lock()
    defer { lock.unlock() }
    return adaptersById.removeValue(forKey: agentId)
  }

  @discardableResult
  func unregisterProvider(_ providerId: String) -> AgentProvider? {
    lock.lock()
    defer { lock.unlock() }
    return providersById.removeValue(forKey: providerId)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    adaptersById.removeAll()
    providersById.removeAll()
  }

  private func snapshotProviders() -> [AgentProvider] {
    lock.lock()
    defer { lock.unlock() }
    return Array(providersById.values)
  }
}

struct AgentTeamRun: Codable, Equatable {
  var teamId: String
  var taskId: String
  var primaryRun: AgentRunHandle
  var memberRuns: [String: AgentRunHandle]
  var unavailableMembers: [String: String]
  var visibilityMode: AgentTeamVisibilityMode

  enum CodingKeys: String, CodingKey {
    case teamId = "team_id"
    case taskId = "task_id"
    case primaryRun = "primary_run"
    case memberRuns = "member_runs"
    case unavailableMembers = "unavailable_members"
    case visibilityMode = "visibility_mode"
  }
}

final class AgentTeamCoordinator {
  private let directory: AgentAdapterDirectory
  private let executionCoordinator: AgentTeamExecutionCoordinator

  init(
    directory: AgentAdapterDirectory,
    executionStore: AgentTeamExecutionStore = UserDefaultsAgentTeamExecutionStore(),
    completionSink: AgentTeamCompletionSink? = nil
  ) {
    self.directory = directory
    self.executionCoordinator = AgentTeamExecutionCoordinator(
      directory: directory,
      store: executionStore,
      completionSink: completionSink
    )
  }

  func compile(
    request: AgentDynamicTeamRequest,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) async throws -> AgentDynamicTeamCompilation {
    AgentDynamicTeamCompiler().compile(
      request: request,
      registrations: try await directory.registrations(),
      nowMillis: nowMillis
    )
  }

  func startExecution(
    definition: AgentTeamDefinition,
    request: AgentRunRequest
  ) throws -> AgentTeamExecutionHandle {
    try executionCoordinator.start(definition: definition, request: request)
  }

  func executionSnapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    executionCoordinator.runtime.snapshot(supervisorRunId: supervisorRunId)
  }

  func executionSnapshots() -> [AgentTeamExecutionSnapshot] {
    executionCoordinator.runtime.snapshots()
  }

  func recoverInterruptedExecutions(
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> [AgentTeamExecutionSnapshot] {
    executionCoordinator.runtime.recoverInterrupted(nowMillis: nowMillis)
  }

  func closeExecutionRuntime() {
    executionCoordinator.runtime.close()
  }

  func start(definition: AgentTeamDefinition, request: AgentRunRequest) async throws -> AgentTeamRun {
    let members = definition.members.distinctByAgentId()
    guard !definition.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentControlPlaneAdapterError(message: "Team id must not be blank")
    }
    guard members.contains(where: { $0.agentId == definition.primaryAgentId && $0.deliveryMode == .respond }) else {
      throw AgentControlPlaneAdapterError(message: "The primary Agent must be a responding team member")
    }
    guard members.filter({ $0.deliveryMode == .respond }).count == 1 else {
      throw AgentControlPlaneAdapterError(message: "A team must expose exactly one responding Agent")
    }
    let primaryMember = members.first { $0.agentId == definition.primaryAgentId }!
    guard let primaryAdapter = try await directory.resolveAdapter(primaryMember.agentId) else {
      throw AgentControlPlaneAdapterError(message: "Primary Agent is unavailable: \(primaryMember.agentId)")
    }
    guard primaryMember.requiredCapabilities.isSubset(of: primaryAdapter.registration.capabilities) else {
      throw AgentControlPlaneAdapterError(message: "Primary Agent lacks required capabilities")
    }
    let primaryRun = try await primaryAdapter.startRun(
      request.copyForControlPlane(
        runId: request.runId,
        parentRunId: request.parentRunId,
        deliveryMode: .respond,
        requiredCapabilities: requiredCapabilities(
          request: request,
          member: primaryMember,
          definition: definition
        ),
        idempotencyKey: request.idempotencyKey
      )
    )
    var runs: [String: AgentRunHandle] = [primaryMember.agentId: primaryRun]
    var unavailable: [String: String] = [:]
    for member in members where member.agentId != primaryMember.agentId && member.deliveryMode != .ignore {
      guard let adapter = try await directory.resolveAdapter(member.agentId) else {
        unavailable[member.agentId] = "agent_unavailable"
        continue
      }
      guard member.requiredCapabilities.isSubset(of: adapter.registration.capabilities) else {
        unavailable[member.agentId] = "capability_mismatch"
        continue
      }
      do {
        let handle = try await adapter.startRun(
          request.copyForControlPlane(
            runId: UUID().uuidString,
            parentRunId: primaryRun.runId,
            deliveryMode: member.deliveryMode,
            requiredCapabilities: requiredCapabilities(request: request, member: member, definition: definition),
            idempotencyKey: "\(request.idempotencyKey):\(member.agentId)"
          )
        )
        runs[member.agentId] = handle
      } catch {
        unavailable[member.agentId] = error.localizedDescription.isEmpty ? "start_failed" : error.localizedDescription
      }
    }
    return AgentTeamRun(
      teamId: definition.teamId,
      taskId: request.taskId,
      primaryRun: primaryRun,
      memberRuns: runs,
      unavailableMembers: unavailable,
      visibilityMode: definition.visibilityMode
    )
  }

  private func requiredCapabilities(
    request: AgentRunRequest,
    member: AgentTeamMember,
    definition: AgentTeamDefinition
  ) -> Set<AgentCapability> {
    if definition.collectiveCapabilities.isEmpty {
      return request.requiredCapabilities.union(member.requiredCapabilities)
    }
    return member.requiredCapabilities
  }
}

private extension AgentRunRequest {
  func copyForControlPlane(
    runId: String,
    parentRunId: String,
    deliveryMode: AgentDeliveryMode,
    requiredCapabilities: Set<AgentCapability>,
    idempotencyKey: String
  ) -> AgentRunRequest {
    AgentRunRequest(
      conversationId: conversationId,
      messageId: messageId,
      taskId: taskId,
      runId: runId,
      parentRunId: parentRunId,
      goal: goal,
      deliveryMode: deliveryMode,
      requiredCapabilities: requiredCapabilities,
      context: context,
      idempotencyKey: idempotencyKey,
      createdAtMillis: createdAtMillis
    )
  }
}

private extension Array where Element == AgentTeamMember {
  func distinctByAgentId() -> [AgentTeamMember] {
    var seen = Set<String>()
    return filter { seen.insert($0.agentId).inserted }
  }
}

import Foundation

enum AgentTeamExecutionRuntimeError: Error, Equatable {
  case invalid(String)
  case duplicateRun(String)
  case missingRun(String)
  case closed
}

extension AgentTeamExecutionRuntimeError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalid(let message), .duplicateRun(let message), .missingRun(let message):
      return message
    case .closed:
      return "Agent team runtime is closed"
    }
  }
}

struct AgentTeamExecutionRecord: Codable, Equatable {
  var definition: AgentTeamDefinition
  var request: AgentRunRequest
  var events: [AgentSubagentEvent]
  var interruptedAtMillis: Int64
  var updatedAtMillis: Int64

  init(
    definition: AgentTeamDefinition,
    request: AgentRunRequest,
    events: [AgentSubagentEvent] = [],
    interruptedAtMillis: Int64 = 0,
    updatedAtMillis: Int64? = nil
  ) {
    self.definition = definition
    self.request = request
    self.events = Array(events.suffix(AgentTeamExecutionStoreLimits.maxEventsPerRun))
    self.interruptedAtMillis = max(interruptedAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis ?? request.createdAtMillis, 0)
  }
}

enum AgentTeamExecutionStoreLimits {
  static let maxRuns = 200
  static let maxEventsPerRun = 512
}

protocol AgentTeamExecutionStore: AnyObject, AgentSubagentEventHook {
  func create(definition: AgentTeamDefinition, request: AgentRunRequest) throws
  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot?
  func snapshots() -> [AgentTeamExecutionSnapshot]
  func markInterrupted(supervisorRunId: String, nowMillis: Int64) -> AgentTeamExecutionSnapshot?
  func markNonTerminalInterrupted(nowMillis: Int64) -> [AgentTeamExecutionSnapshot]
  func remove(supervisorRunId: String)
  func clear()
}

final class InMemoryAgentTeamExecutionStore: AgentTeamExecutionStore {
  private let lock = NSRecursiveLock()
  private var records: [String: AgentTeamExecutionRecord] = [:]

  func create(definition: AgentTeamDefinition, request: AgentRunRequest) throws {
    let runId = clean(request.runId)
    guard !runId.isEmpty else {
      throw AgentTeamExecutionRuntimeError.invalid("Team supervisor run id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    if let existing = records[runId] {
      guard existing.definition.teamId == definition.teamId,
        existing.request.taskId == request.taskId else {
        throw AgentTeamExecutionRuntimeError.duplicateRun(runId)
      }
      return
    }
    records[runId] = AgentTeamExecutionRecord(definition: definition, request: request)
    trimLocked()
  }

  func append(_ event: AgentSubagentEvent) async throws {
    let runId = clean(event.supervisorId)
    guard !runId.isEmpty else {
      throw AgentTeamExecutionRuntimeError.invalid("Team event supervisor id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    guard var record = records[runId] else {
      throw AgentTeamExecutionRuntimeError.missingRun(runId)
    }
    if let existing = record.events.first(where: { $0.sequence == event.sequence }) {
      guard existing.kind == event.kind, existing.childId == event.childId else {
        throw AgentTeamExecutionRuntimeError.invalid("Conflicting event sequence for " + runId)
      }
      return
    }
    record.events = Array((record.events + [event]).sorted { $0.sequence < $1.sequence }
      .suffix(AgentTeamExecutionStoreLimits.maxEventsPerRun))
    record.updatedAtMillis = max(record.updatedAtMillis, event.timestampMillis)
    records[runId] = record
  }

  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return records[clean(supervisorRunId)]?.snapshot
  }

  func snapshots() -> [AgentTeamExecutionSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return records.values.map(\.snapshot).sorted { $0.updatedAtMillis > $1.updatedAtMillis }
  }

  func markInterrupted(supervisorRunId: String, nowMillis: Int64) -> AgentTeamExecutionSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    let runId = clean(supervisorRunId)
    guard var record = records[runId], !record.snapshot.state.isTerminal else {
      return records[runId]?.snapshot
    }
    record.interruptedAtMillis = max(nowMillis, 0)
    record.updatedAtMillis = max(record.updatedAtMillis, nowMillis)
    records[runId] = record
    return record.snapshot
  }

  func markNonTerminalInterrupted(nowMillis: Int64) -> [AgentTeamExecutionSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    for runId in records.keys {
      guard var record = records[runId], !record.snapshot.state.isTerminal else { continue }
      record.interruptedAtMillis = max(nowMillis, 0)
      record.updatedAtMillis = max(record.updatedAtMillis, nowMillis)
      records[runId] = record
    }
    return records.values.map(\.snapshot).filter { $0.state == .interrupted }
  }

  func remove(supervisorRunId: String) {
    lock.lock()
    records.removeValue(forKey: clean(supervisorRunId))
    lock.unlock()
  }

  func clear() {
    lock.lock()
    records.removeAll()
    lock.unlock()
  }

  private func trimLocked() {
    guard records.count > AgentTeamExecutionStoreLimits.maxRuns else { return }
    let keep = records.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
      .prefix(AgentTeamExecutionStoreLimits.maxRuns)
    records = Dictionary(uniqueKeysWithValues: keep.map { ($0.request.runId, $0) })
  }
}

final class UserDefaultsAgentTeamExecutionStore: AgentTeamExecutionStore {
  static let defaultKey = "galaxyssi_agent_team_execution_v1"

  private let defaults: UserDefaults
  private let key: String
  private let secrets: GalaxySSISecretStore
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    key: String = "galaxyssi_agent_team_execution_v1",
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.key = key
    self.secrets = secrets
  }

  func create(definition: AgentTeamDefinition, request: AgentRunRequest) throws {
    lock.lock()
    var records = loadLocked()
    if let existing = records.first(where: { $0.request.runId == request.runId }) {
      guard existing.definition.teamId == definition.teamId,
        existing.request.taskId == request.taskId else {
        lock.unlock()
        throw AgentTeamExecutionRuntimeError.duplicateRun(request.runId)
      }
      lock.unlock()
      return
    }
    records.append(AgentTeamExecutionRecord(definition: definition, request: request))
    saveLocked(records)
    lock.unlock()
    postUpdate(runId: request.runId)
  }

  func append(_ event: AgentSubagentEvent) async throws {
    lock.lock()
    var records = loadLocked()
    guard let index = records.firstIndex(where: { $0.request.runId == event.supervisorId }) else {
      lock.unlock()
      throw AgentTeamExecutionRuntimeError.missingRun(event.supervisorId)
    }
    var record = records[index]
    if let existing = record.events.first(where: { $0.sequence == event.sequence }) {
      guard existing.kind == event.kind, existing.childId == event.childId else {
        lock.unlock()
        throw AgentTeamExecutionRuntimeError.invalid("Conflicting event sequence for " + event.supervisorId)
      }
      lock.unlock()
      return
    }
    record.events = Array((record.events + [event]).sorted { $0.sequence < $1.sequence }
      .suffix(AgentTeamExecutionStoreLimits.maxEventsPerRun))
    record.updatedAtMillis = max(record.updatedAtMillis, event.timestampMillis)
    records[index] = record
    saveLocked(records)
    lock.unlock()
    postUpdate(runId: event.supervisorId)
  }

  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked().first { $0.request.runId == clean(supervisorRunId) }?.snapshot
  }

  func snapshots() -> [AgentTeamExecutionSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked().map(\.snapshot).sorted { $0.updatedAtMillis > $1.updatedAtMillis }
  }

  func markInterrupted(supervisorRunId: String, nowMillis: Int64) -> AgentTeamExecutionSnapshot? {
    lock.lock()
    var records = loadLocked()
    guard let index = records.firstIndex(where: { $0.request.runId == clean(supervisorRunId) }) else {
      lock.unlock()
      return nil
    }
    var changed = false
    if !records[index].snapshot.state.isTerminal {
      records[index].interruptedAtMillis = max(nowMillis, 0)
      records[index].updatedAtMillis = max(records[index].updatedAtMillis, nowMillis)
      saveLocked(records)
      changed = true
    }
    let snapshot = records[index].snapshot
    lock.unlock()
    if changed {
      postUpdate(runId: supervisorRunId)
    }
    return snapshot
  }

  func markNonTerminalInterrupted(nowMillis: Int64) -> [AgentTeamExecutionSnapshot] {
    lock.lock()
    var records = loadLocked()
    var changed = false
    for index in records.indices where !records[index].snapshot.state.isTerminal {
      records[index].interruptedAtMillis = max(nowMillis, 0)
      records[index].updatedAtMillis = max(records[index].updatedAtMillis, nowMillis)
      changed = true
    }
    if changed {
      saveLocked(records)
    }
    let snapshots = records.map(\.snapshot).filter { $0.state == .interrupted }
    lock.unlock()
    if changed {
      postUpdate(runId: nil)
    }
    return snapshots
  }

  func remove(supervisorRunId: String) {
    lock.lock()
    let runId = clean(supervisorRunId)
    let records = loadLocked()
    let remaining = records.filter { $0.request.runId != runId }
    let changed = remaining.count != records.count
    if changed {
      saveLocked(remaining)
    }
    lock.unlock()
    if changed {
      postUpdate(runId: runId)
    }
  }

  func clear() {
    lock.lock()
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    lock.unlock()
    postUpdate(runId: nil)
  }

  static func destroy(
    defaults: UserDefaults = .standard,
    key: String = "galaxyssi_agent_team_execution_v1",
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  private func loadLocked() -> [AgentTeamExecutionRecord] {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: key,
      secrets: secrets
    ), let records = try? decoder.decode([AgentTeamExecutionRecord].self, from: data) else {
      return []
    }
    return Array(records.suffix(AgentTeamExecutionStoreLimits.maxRuns))
  }

  private func saveLocked(_ records: [AgentTeamExecutionRecord]) {
    let sorted = records.sorted { $0.updatedAtMillis < $1.updatedAtMillis }
      .suffix(AgentTeamExecutionStoreLimits.maxRuns)
    guard let data = try? encoder.encode(Array(sorted)) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: key,
      secrets: secrets
    )
  }

  private func postUpdate(runId: String?) {
    NotificationCenter.default.post(
      name: .galaxySSIAgentTeamExecutionHistoryDidUpdate,
      object: runId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    )
  }
}

struct AgentTeamMemberExecutionContext {
  var member: AgentTeamMember
  var request: AgentRunRequest
  var handoff: AgentSubagentContextHandoff
  var depth: Int
  var provenance: AgentSubagentProvenance
}

protocol AgentTeamMemberWorker {
  func execute(context: AgentTeamMemberExecutionContext) async throws -> AgentSubagentOutput
}

struct ClosureAgentTeamMemberWorker: AgentTeamMemberWorker {
  let body: (AgentTeamMemberExecutionContext) async throws -> AgentSubagentOutput

  func execute(context: AgentTeamMemberExecutionContext) async throws -> AgentSubagentOutput {
    try await body(context)
  }
}

final class AgentTeamExecutionHandle {
  let supervisorRunId: String
  private let delegate: AgentSubagentRunHandle
  private let store: AgentTeamExecutionStore

  fileprivate init(
    supervisorRunId: String,
    delegate: AgentSubagentRunHandle,
    store: AgentTeamExecutionStore
  ) {
    self.supervisorRunId = supervisorRunId
    self.delegate = delegate
    self.store = store
  }

  var isActive: Bool { delegate.isActive }

  func wait() async throws -> AgentTeamExecutionSnapshot {
    _ = try await delegate.wait()
    guard let snapshot = store.snapshot(supervisorRunId: supervisorRunId) else {
      throw AgentTeamExecutionRuntimeError.missingRun(supervisorRunId)
    }
    return snapshot
  }

  @discardableResult
  func cancel(reason: String = "Agent team cancellation requested") -> Bool {
    delegate.cancel(reason: reason)
  }
}

final class AgentTeamExecutionRuntime {
  private let store: AgentTeamExecutionStore
  private let mailbox: AgentTeamMailbox
  private let completionSink: AgentTeamCompletionSink?
  private let runtime: AgentSubagentRuntime
  private let lock = NSRecursiveLock()
  private var closed = false
  private var watchers: [String: Task<Void, Never>] = [:]

  init(
    store: AgentTeamExecutionStore = UserDefaultsAgentTeamExecutionStore(),
    mailbox: AgentTeamMailbox = UserDefaultsAgentTeamMailbox(),
    limits: AgentSubagentLimits = AgentSubagentLimits(),
    completionSink: AgentTeamCompletionSink? = nil
  ) {
    self.store = store
    self.mailbox = mailbox
    self.completionSink = completionSink
    self.runtime = AgentSubagentRuntime(limits: limits, eventHook: store)
  }

  func start(
    definition: AgentTeamDefinition,
    request: AgentRunRequest,
    worker: AgentTeamMemberWorker
  ) throws -> AgentTeamExecutionHandle {
    lock.lock()
    guard !closed else {
      lock.unlock()
      throw AgentTeamExecutionRuntimeError.closed
    }
    lock.unlock()

    let normalizedMembers = try validate(definition)
    let normalizedDefinition = AgentTeamDefinition(
      teamId: definition.teamId.trimmingCharacters(in: .whitespacesAndNewlines),
      primaryAgentId: definition.primaryAgentId.trimmingCharacters(in: .whitespacesAndNewlines),
      members: normalizedMembers,
      visibilityMode: definition.visibilityMode,
      collectiveCapabilities: definition.collectiveCapabilities,
      primaryInstanceId: definition.primaryMemberId
    )
    try store.create(definition: normalizedDefinition, request: request)
    let membersById = Dictionary(uniqueKeysWithValues: normalizedMembers.map { ($0.memberId, $0) })
    let observerIds = Set(normalizedMembers.filter { $0.deliveryMode == .observe }.map(\.memberId))
    let children = normalizedMembers.filter { $0.deliveryMode != .ignore }.map { member in
      let dependencies = member.memberId == normalizedDefinition.primaryMemberId
        ? member.dependsOnAgentIds.union(observerIds).subtracting([member.memberId])
        : member.dependsOnAgentIds
      return AgentSubagentChild(
        childId: member.memberId,
        dependencies: dependencies,
        dependencyPolicy: member.memberId == normalizedDefinition.primaryMemberId ? .allowTerminal : .requireSuccess,
        context: String(member.objective.ifBlank(request.goal).prefix(8_000)),
        provenance: AgentSubagentProvenance(
          source: "agent-team",
          sourceId: normalizedDefinition.teamId,
          traceId: request.runId,
          metadata: [
            "delivery_mode": member.deliveryMode.rawValue,
            "role": String(member.role.prefix(80)),
            "task_id": String(request.taskId.prefix(160))
          ]
        )
      )
    }
    let plan = AgentSubagentPlan(
      supervisorId: request.runId,
      children: children,
      provenance: AgentSubagentProvenance(
        source: "agent-team-supervisor",
        sourceId: normalizedDefinition.teamId,
        traceId: request.runId,
        metadata: [
          "primary_agent_id": normalizedDefinition.primaryAgentId,
          "visibility": normalizedDefinition.visibilityMode.rawValue
        ]
      )
    )
    let delegate = try runtime.start(plan: plan, worker: ClosureAgentSubagentWorker { [request, membersById, mailbox] context in
      guard let member = membersById[context.childId] else {
        throw AgentTeamExecutionRuntimeError.missingRun(context.childId)
      }
      var childRequest = request
      childRequest.runId = Self.stableChildRunId(supervisorRunId: request.runId, instanceId: member.memberId)
      childRequest.parentRunId = request.runId
      childRequest.deliveryMode = member.deliveryMode
      childRequest.requiredCapabilities = member.requiredCapabilities.union(
        member.memberId == normalizedDefinition.primaryMemberId && normalizedDefinition.collectiveCapabilities.isEmpty
          ? request.requiredCapabilities
          : []
      )
      member.context.forEach { childRequest.context[$0.key] = .string(String($0.value.prefix(8_000))) }
      childRequest.context["team_id"] = .string(normalizedDefinition.teamId)
      childRequest.context["team_role"] = .string(String(member.role.prefix(80)))
      childRequest.context["team_visibility"] = .string(normalizedDefinition.visibilityMode.rawValue.lowercased())
      childRequest.context["team_instance_id"] = .string(member.memberId)
      let queuedMessages = mailbox.messages(
        supervisorRunId: request.runId,
        instanceId: member.memberId,
        afterSequence: 0
      ).filter { $0.state == .pending }
      if !queuedMessages.isEmpty {
        childRequest.context["team_messages"] = .array(queuedMessages.map { message in
          .object([
            "message_id": .string(message.messageId),
            "from_instance_id": .string(message.fromInstanceId),
            "kind": .string(message.kind.rawValue),
            "text": .string(message.text),
            "sequence": .int(message.sequence)
          ])
        })
        queuedMessages.forEach {
          _ = mailbox.markDelivered(
            messageId: $0.messageId,
            atMillis: AgentControlPlaneClock.nowMillis()
          )
        }
      }
      childRequest.idempotencyKey = request.idempotencyKey + ":" + member.memberId
      let output = try await worker.execute(context: AgentTeamMemberExecutionContext(
        member: member,
        request: childRequest,
        handoff: context.handoff,
        depth: context.depth,
        provenance: context.provenance
      ))
      queuedMessages.forEach {
        _ = mailbox.acknowledge(
          messageId: $0.messageId,
          atMillis: AgentControlPlaneClock.nowMillis()
        )
      }
      return output
    })
    let handle = AgentTeamExecutionHandle(
      supervisorRunId: request.runId,
      delegate: delegate,
      store: store
    )
    watch(handle)
    return handle
  }

  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    store.snapshot(supervisorRunId: supervisorRunId)
  }

  func snapshots() -> [AgentTeamExecutionSnapshot] {
    store.snapshots()
  }

  func sendMessage(
    supervisorRunId: String,
    fromInstanceId: String = "user",
    toInstanceId: String = "",
    kind: AgentTeamMessageKind = .userDirective,
    text: String,
    metadata: [String: String] = [:]
  ) throws -> AgentTeamMessageEnvelope {
    guard let snapshot = store.snapshot(supervisorRunId: supervisorRunId),
      !snapshot.state.isTerminal else {
      throw AgentTeamExecutionRuntimeError.missingRun(supervisorRunId)
    }
    let recipient = toInstanceId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !recipient.isEmpty {
      guard let member = snapshot.members.first(where: { $0.memberId == recipient }),
        !member.status.isTerminal else {
        throw AgentTeamExecutionRuntimeError.invalid("The selected team member cannot receive messages")
      }
    }
    return try mailbox.append(AgentTeamMessageEnvelope(
      teamId: snapshot.teamId,
      conversationId: snapshot.conversationId,
      supervisorRunId: supervisorRunId,
      fromInstanceId: fromInstanceId,
      toInstanceId: recipient,
      kind: kind,
      text: text,
      metadata: metadata
    ))
  }

  func messages(
    supervisorRunId: String,
    instanceId: String = "",
    afterSequence: Int64 = 0
  ) -> [AgentTeamMessageEnvelope] {
    mailbox.messages(
      supervisorRunId: supervisorRunId,
      instanceId: instanceId,
      afterSequence: afterSequence
    )
  }

  @discardableResult
  func markMessageDelivered(
    messageId: String,
    atMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentTeamMessageEnvelope? {
    mailbox.markDelivered(messageId: messageId, atMillis: atMillis)
  }

  @discardableResult
  func acknowledgeMessage(
    messageId: String,
    atMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentTeamMessageEnvelope? {
    mailbox.acknowledge(messageId: messageId, atMillis: atMillis)
  }

  func recoverInterrupted(nowMillis: Int64 = AgentControlPlaneClock.nowMillis()) -> [AgentTeamExecutionSnapshot] {
    store.markNonTerminalInterrupted(nowMillis: nowMillis)
  }

  func close() {
    lock.lock()
    guard !closed else {
      lock.unlock()
      return
    }
    closed = true
    let tasks = Array(watchers.values)
    watchers.removeAll()
    lock.unlock()
    tasks.forEach { $0.cancel() }
    runtime.close()
  }

  private func watch(_ handle: AgentTeamExecutionHandle) {
    let task = Task { [weak self] in
      _ = try? await handle.wait()
      guard let self else { return }
      if let snapshot = self.store.snapshot(supervisorRunId: handle.supervisorRunId), snapshot.state.isTerminal {
        _ = self.completionSink?.publish(snapshot)
      }
      self.lock.lock()
      self.watchers.removeValue(forKey: handle.supervisorRunId)
      self.lock.unlock()
    }
    lock.lock()
    watchers[handle.supervisorRunId] = task
    lock.unlock()
  }

  private func validate(_ definition: AgentTeamDefinition) throws -> [AgentTeamMember] {
    let teamId = definition.teamId.trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryId = definition.primaryAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryMemberId = definition.primaryMemberId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !teamId.isEmpty, !primaryId.isEmpty, !primaryMemberId.isEmpty else {
      throw AgentTeamExecutionRuntimeError.invalid("Team id and primary Agent id must not be blank")
    }
    var seen = Set<String>()
    let members = definition.members.compactMap { member -> AgentTeamMember? in
      let agentId = member.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
      let memberId = member.memberId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !agentId.isEmpty, !memberId.isEmpty, seen.insert(memberId).inserted else { return nil }
      return AgentTeamMember(
        agentId: agentId,
        deliveryMode: member.deliveryMode,
        requiredCapabilities: member.requiredCapabilities,
        role: String(member.role.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
        objective: String(member.objective.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000)),
        dependsOnAgentIds: Set(member.dependsOnAgentIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }),
        context: member.context.reduce(into: [String: String]()) { $0[String($1.key.prefix(160))] = String($1.value.prefix(8_000)) },
        instanceId: memberId
      )
    }
    guard members.count == definition.members.count else {
      throw AgentTeamExecutionRuntimeError.invalid("Agent ids must be unique and nonblank")
    }
    guard members.filter({ $0.deliveryMode == .respond }).count == 1,
      members.contains(where: {
        $0.agentId == primaryId && $0.memberId == primaryMemberId && $0.deliveryMode == .respond
      }) else {
      throw AgentTeamExecutionRuntimeError.invalid("A team must expose exactly one responding primary Agent")
    }
    let memberIds = Set(members.map(\.memberId))
    guard members.allSatisfy({ member in
      !member.dependsOnAgentIds.contains(member.memberId) && member.dependsOnAgentIds.isSubset(of: memberIds)
    }) else {
      throw AgentTeamExecutionRuntimeError.invalid("Agent team dependencies must reference other members")
    }
    var visiting = Set<String>()
    var visited = Set<String>()
    let dependencies = Dictionary(uniqueKeysWithValues: members.map { member in
      let primaryDependencies = member.memberId == primaryMemberId
        ? member.dependsOnAgentIds.union(members.filter { $0.deliveryMode == .observe }.map(\.memberId))
        : member.dependsOnAgentIds
      return (member.memberId, primaryDependencies)
    })
    func visit(_ agentId: String) -> Bool {
      if visiting.contains(agentId) { return false }
      if visited.contains(agentId) { return true }
      visiting.insert(agentId)
      for dependency in dependencies[agentId, default: []] where !visit(dependency) { return false }
      visiting.remove(agentId)
      visited.insert(agentId)
      return true
    }
    guard members.allSatisfy({ visit($0.memberId) }) else {
      throw AgentTeamExecutionRuntimeError.invalid("Agent team dependencies must be acyclic")
    }
    if !definition.collectiveCapabilities.isEmpty {
      let declared = Set(members.flatMap(\.requiredCapabilities))
      guard definition.collectiveCapabilities.isSubset(of: declared) else {
        throw AgentTeamExecutionRuntimeError.invalid("Team members do not cover collective capabilities")
      }
    }
    return members
  }

  static func stableChildRunId(supervisorRunId: String, instanceId: String) -> String {
    UUID(uuidString: supervisorRunId).map { uuid in
      uuid.uuidString.lowercased() + ":" + instanceId
    } ?? supervisorRunId + ":" + instanceId
  }
}

final class AgentAdapterTeamMemberWorker: AgentTeamMemberWorker {
  private let directory: AgentAdapterDirectory
  private let livenessProbeNanoseconds: UInt64

  init(
    directory: AgentAdapterDirectory,
    livenessProbeNanoseconds: UInt64 = 6 * 60 * 1_000_000_000
  ) {
    self.directory = directory
    self.livenessProbeNanoseconds = max(livenessProbeNanoseconds, 10_000_000)
  }

  func execute(context: AgentTeamMemberExecutionContext) async throws -> AgentSubagentOutput {
    guard let adapter = try await directory.resolveAdapter(context.member.agentId) else {
      throw AgentControlPlaneAdapterError(message: "Agent is unavailable: " + context.member.agentId)
    }
    let handle = try await adapter.startRun(context.request)
    let livenessProbe = AgentRunLivenessProbe.start(
      adapter: adapter,
      request: context.request,
      remoteRunId: handle.runId,
      intervalNanoseconds: livenessProbeNanoseconds
    )
    defer { livenessProbe.cancel() }
    var terminalEvent: AgentRunControlEvent?
    for await event in adapter.observeEvents(runId: handle.runId) {
      switch event.type {
      case .runCompleted, .runFailed, .runCancelled:
        terminalEvent = event
      default:
        continue
      }
      break
    }
    guard let terminalEvent else {
      throw AgentControlPlaneAdapterError(message: "Agent completed without a terminal event")
    }
    switch terminalEvent.type {
    case .runCompleted:
      return AgentSubagentOutput(content: Self.payloadText(terminalEvent.payload))
    case .runCancelled:
      throw CancellationError()
    default:
      throw AgentControlPlaneAdapterError(message: Self.payloadText(terminalEvent.payload).ifBlank("Agent run failed"))
    }
  }

  private static func payloadText(_ payload: AgentRunControlPayload) -> String {
    for key in ["content", "text", "output", "result", "error", "message"] {
      if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
        return value
      }
    }
    return ""
  }
}

enum AgentRunLivenessProbe {
  static func start(
    adapter: AgentAdapter,
    request: AgentRunRequest,
    remoteRunId: String,
    intervalNanoseconds: UInt64
  ) -> Task<Void, Never> {
    let interval = max(intervalNanoseconds, minimumIntervalNanoseconds)
    return Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: interval)
        } catch {
          break
        }
        guard !Task.isCancelled else { break }
        await diagnose(adapter: adapter, request: request, remoteRunId: remoteRunId)
      }
    }
  }

  private static func diagnose(
    adapter: AgentAdapter,
    request: AgentRunRequest,
    remoteRunId: String
  ) async {
    let diagnostic = Task {
      _ = try? await adapter.status()
      let recoverable = (try? await adapter.recoverRuns()) ?? []
      _ = recoverable.first { run in
        let handle = run.handle
        return handle.runId == remoteRunId ||
          (handle.taskId == request.taskId && handle.remoteRunId == remoteRunId)
      }
    }
    let cancellation = Task {
      try? await Task.sleep(nanoseconds: maximumOperationNanoseconds)
      diagnostic.cancel()
    }
    _ = await diagnostic.result
    cancellation.cancel()
  }

  private static let minimumIntervalNanoseconds: UInt64 = 10_000_000
  private static let maximumOperationNanoseconds: UInt64 = 30 * 1_000_000_000
}

final class AgentTeamExecutionCoordinator {
  let runtime: AgentTeamExecutionRuntime
  private let directory: AgentAdapterDirectory

  init(
    directory: AgentAdapterDirectory,
    store: AgentTeamExecutionStore = UserDefaultsAgentTeamExecutionStore(),
    completionSink: AgentTeamCompletionSink? = nil
  ) {
    self.directory = directory
    self.runtime = AgentTeamExecutionRuntime(store: store, completionSink: completionSink)
  }

  func start(definition: AgentTeamDefinition, request: AgentRunRequest) throws -> AgentTeamExecutionHandle {
    try runtime.start(
      definition: definition,
      request: request,
      worker: AgentAdapterTeamMemberWorker(directory: directory)
    )
  }

  func sendMessage(
    supervisorRunId: String,
    toInstanceId: String,
    text: String,
    kind: AgentTeamMessageKind = .userDirective
  ) async throws -> AgentTeamMessageEnvelope {
    let envelope = try runtime.sendMessage(
      supervisorRunId: supervisorRunId,
      toInstanceId: toInstanceId,
      kind: kind,
      text: text
    )
    guard let snapshot = runtime.snapshot(supervisorRunId: supervisorRunId) else { return envelope }
    let recipients = envelope.isBroadcast
      ? snapshot.members.filter { !$0.status.isTerminal }
      : snapshot.members.filter { $0.memberId == envelope.toInstanceId }
    var delivered = false
    for member in recipients {
      guard let adapter = try await directory.resolveAdapter(member.agentId) else { continue }
      let runId = member.memberId == snapshot.primaryMemberId
        ? supervisorRunId
        : AgentTeamExecutionRuntime.stableChildRunId(
          supervisorRunId: supervisorRunId,
          instanceId: member.memberId
        )
      do {
        try await adapter.sendMessage(
          runId: runId,
          message: AgentControlMessage(
            messageId: envelope.messageId,
            role: envelope.kind.rawValue.lowercased(),
            text: envelope.text,
            deliveryMode: .observe
          )
        )
        delivered = true
      } catch where envelope.isBroadcast {
        continue
      }
    }
    return delivered
      ? runtime.markMessageDelivered(messageId: envelope.messageId) ?? envelope
      : envelope
  }
}

private extension AgentTeamExecutionRecord {
  var snapshot: AgentTeamExecutionSnapshot {
    let latestByChild = Dictionary(grouping: events.filter { !$0.childId.isEmpty }, by: \.childId)
      .compactMapValues { $0.max { $0.sequence < $1.sequence } }
    let members = definition.members.map { member in
      let event = latestByChild[member.memberId]
      let result = event?.result
      let updatedAt = max(result?.completedAtMillis ?? 0, event?.timestampMillis ?? 0)
      return AgentTeamMemberSnapshot(
        agentId: member.agentId,
        role: member.role,
        deliveryMode: member.deliveryMode,
        status: member.deliveryMode == .ignore ? .skipped : event?.childStatus ?? .queued,
        output: result?.output ?? "",
        errorMessage: (result?.errorMessage ?? "").ifBlank(event?.message ?? ""),
        updatedAtMillis: updatedAt,
        instanceId: member.memberId
      )
    }
    let terminal = events.last { $0.runStatus != nil }
    let state: AgentTeamExecutionState
    if interruptedAtMillis > 0, terminal == nil {
      state = .interrupted
    } else if terminal?.runStatus == .succeeded {
      state = .succeeded
    } else if terminal?.runStatus == .completedWithFailures {
      state = .completedWithFailures
    } else if terminal?.runStatus == .failed {
      state = .failed
    } else if terminal?.runStatus == .cancelled {
      state = .cancelled
    } else if events.contains(where: { $0.kind == AgentSubagentEventKinds.supervisorStarted }) {
      state = .running
    } else {
      state = .queued
    }
    let primaryOutput = members.first { $0.memberId == definition.primaryMemberId }
      .flatMap { $0.status == .succeeded ? $0.output : nil } ?? ""
    return AgentTeamExecutionSnapshot(
      supervisorRunId: request.runId,
      teamId: definition.teamId,
      conversationId: request.conversationId,
      taskId: request.taskId,
      primaryAgentId: definition.primaryAgentId,
      goal: request.goal,
      visibilityMode: definition.visibilityMode,
      state: state,
      members: members,
      finalOutput: primaryOutput,
      createdAtMillis: request.createdAtMillis,
      updatedAtMillis: max(updatedAtMillis, events.map(\.timestampMillis).max() ?? 0),
      interruptedAtMillis: interruptedAtMillis,
      primaryInstanceId: definition.primaryMemberId
    )
  }
}

private func clean(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
}

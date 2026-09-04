import Foundation

struct AgentEvolutionLabRuntimeSnapshot: Equatable {
  var runningCampaignIds: Set<String>
  var availableAgents: [AgentRegistration]
  var maximumParallelTrials: Int
}

struct AgentEvolutionLabRuntimeError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }
}

final class AgentEvolutionLabRuntime {
  private let directory: AgentAdapterDirectory
  private let labStore: AgentLabStore
  private let evalStore: AgentEvalOpsStore
  private let recordedRunStore: AgentRecordedRunStoring
  private let eventStore: AgentRunEventPersistence
  private let memoryTrustStore: AgentMemoryTrustStore
  private let maximumParallelTrials: Int
  private let trialLivenessProbeNanoseconds: UInt64
  private let staleCampaignMillis: Int64
  private let watchdogIntervalNanoseconds: UInt64
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()
  private var campaignTasks: [String: Task<Void, Never>] = [:]
  private var campaignTaskGenerations: [String: UUID] = [:]
  private var activeAdapters: [String: [String: AgentAdapter]] = [:]
  private var watchdogTask: Task<Void, Never>?

  init(
    directory: AgentAdapterDirectory,
    labStore: AgentLabStore = AgentLabStore(),
    evalStore: AgentEvalOpsStore = AgentEvalOpsStore(),
    recordedRunStore: AgentRecordedRunStoring = UserDefaultsAgentRecordedRunStore(),
    eventStore: AgentRunEventPersistence = UserDefaultsAgentRunEventStore(),
    memoryTrustStore: AgentMemoryTrustStore = AgentMemoryTrustStore(),
    maximumParallelTrials: Int = 3,
    trialLivenessProbeNanoseconds: UInt64 = 6 * 60 * 1_000_000_000,
    staleCampaignMillis: Int64 = 8 * 60 * 1_000,
    watchdogIntervalNanoseconds: UInt64 = 60 * 1_000_000_000,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.directory = directory
    self.labStore = labStore
    self.evalStore = evalStore
    self.recordedRunStore = recordedRunStore
    self.eventStore = eventStore
    self.memoryTrustStore = memoryTrustStore
    self.maximumParallelTrials = min(max(maximumParallelTrials, 1), 10)
    self.trialLivenessProbeNanoseconds = max(10_000_000, trialLivenessProbeNanoseconds)
    self.staleCampaignMillis = max(1, staleCampaignMillis)
    self.watchdogIntervalNanoseconds = max(1_000_000, watchdogIntervalNanoseconds)
    self.nowMillis = nowMillis
  }

  deinit {
    watchdogTask?.cancel()
  }

  func availableAgents() async throws -> [AgentRegistration] {
    let values = (try await directory.registrations()).filter {
      [.agent, .model].contains($0.kind) &&
        [.online, .idle, .busy].contains($0.status) &&
        $0.hasCapacity
    }
    return AgentLabAgentSelectionPolicy.independentAgents(values)
  }

  func snapshot() async throws -> AgentEvolutionLabRuntimeSnapshot {
    AgentEvolutionLabRuntimeSnapshot(
      runningCampaignIds: locked { Set(campaignTasks.keys) },
      availableAgents: try await availableAgents(),
      maximumParallelTrials: maximumParallelTrials
    )
  }

  @discardableResult
  func createAndStart(task: String, agentIds: [String], repetitions: Int) async throws -> AgentLabCampaign {
    let available = Set((try await availableAgents()).map(\.agentId))
    let requested = Set(agentIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    guard !requested.isEmpty, requested.isSubset(of: available) else {
      throw AgentEvolutionLabRuntimeError(message: "Every selected Agent must be online and available")
    }
    guard let campaign = labStore.create(task: task, agentIds: Array(requested).sorted(), repetitions: repetitions) else {
      throw AgentEvolutionLabRuntimeError(message: "A Lab campaign requires a task and at least one Agent")
    }
    try start(campaignId: campaign.id)
    return campaign
  }

  func start(campaignId: String) throws {
    let campaignId = campaignId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let campaign = labStore.get(id: campaignId),
          campaign.status != .completed,
          campaign.status != .cancelled,
          campaign.trials.contains(where: { $0.status == .pending }) else {
      throw AgentEvolutionLabRuntimeError(message: "Lab campaign has no pending trials")
    }
    ensureWatchdog()
    let generation = UUID()
    let created = locked { () -> Bool in
      guard campaignTasks[campaignId] == nil else { return false }
      campaignTaskGenerations[campaignId] = generation
      campaignTasks[campaignId] = Task { [weak self] in
        guard let self else { return }
        await self.runCampaign(campaignId: campaignId, generation: generation)
      }
      return true
    }
    guard created else {
      throw AgentEvolutionLabRuntimeError(message: "Lab campaign is already running")
    }
  }

  @discardableResult
  func resumeInterrupted(
    campaignId: String,
    condition: AgentEvalCondition = .processDeath,
    reason: String = "Agent Lab trial was interrupted and resumed"
  ) throws -> AgentLabCampaign {
    let running = labStore.get(id: campaignId)?.trials.filter { $0.status == .running && !$0.runId.isBlank } ?? []
    guard let campaign = labStore.resetInterruptedTrials(campaignId: campaignId, condition: condition) else {
      throw AgentEvolutionLabRuntimeError(message: "Lab campaign cannot be resumed")
    }
    running.forEach {
      _ = AgentEvalOpsService.observeRunInterrupted(
        runId: $0.runId, condition: condition, reason: reason,
        store: evalStore, runStore: recordedRunStore, eventStore: eventStore
      )
    }
    try start(campaignId: campaign.id)
    return campaign
  }

  @discardableResult
  func resumeIncomplete(
    campaignIds: [String],
    condition: AgentEvalCondition = .processDeath,
    reason: String = "Agent Lab campaign was incomplete and resumed"
  ) -> Int {
    var seen = Set<String>()
    return campaignIds.reduce(into: 0) { resumed, value in
      let campaignId = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !campaignId.isEmpty, seen.insert(campaignId).inserted,
            recoverAndStart(
              campaignId: campaignId,
              condition: condition,
              reason: reason,
              replaceActive: false
            ) else { return }
      resumed += 1
    }
  }

  @discardableResult
  func cancel(campaignId: String) async -> AgentLabCampaign? {
    let campaignId = campaignId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cancellation = locked { () -> (Task<Void, Never>?, [String: AgentAdapter]) in
      let task = campaignTasks.removeValue(forKey: campaignId)
      let adapters = activeAdapters.removeValue(forKey: campaignId) ?? [:]
      return (task, adapters)
    }
    cancellation.0?.cancel()
    for (runId, adapter) in cancellation.1 {
      try? await adapter.cancelRun(runId: runId)
    }
    return labStore.cancel(campaignId: campaignId)
  }

  private func runCampaign(campaignId: String, generation: UUID) async {
    defer {
      let removed = locked { () -> Bool in
        guard campaignTaskGenerations[campaignId] == generation else { return false }
        campaignTasks.removeValue(forKey: campaignId)
        campaignTaskGenerations.removeValue(forKey: campaignId)
        activeAdapters.removeValue(forKey: campaignId)
        return true
      }
      if removed { scheduleRestartIfIncomplete(campaignId: campaignId) }
    }
    guard let campaign = labStore.get(id: campaignId) else { return }
    let pending = campaign.trials.filter { $0.status == .pending }
    for batchStart in stride(from: 0, to: pending.count, by: maximumParallelTrials) {
      if Task.isCancelled { break }
      let batch = Array(pending[batchStart..<min(batchStart + maximumParallelTrials, pending.count)])
      await withTaskGroup(of: Void.self) { group in
        for trial in batch {
          group.addTask { [weak self] in
            await self?.runTrial(campaign: campaign, trial: trial)
          }
        }
        await group.waitForAll()
      }
    }
  }

  private func runTrial(campaign: AgentLabCampaign, trial: AgentLabTrial) async {
    let runId = UUID().uuidString
    let conversationId = "lab:\(campaign.id)"
    let createdAt = nowMillis()
    var run = AgentRecordedRun(
      runId: runId,
      conversationId: conversationId,
      taskThreadId: trial.id,
      originalRequest: campaign.task,
      normalizedIntent: "agent_lab_trial",
      extractedInputs: [
        "campaign_id": .string(campaign.id),
        "trial_id": .string(trial.id),
        "blind_alias": .string(trial.blindAlias)
      ],
      executionResourceId: trial.agentId,
      status: .running,
      createdAtMillis: createdAt
    )
    recordedRunStore.upsert(run)
    AgentEvalOpsService.observeRunStarted(run, store: evalStore, conditionOverride: trial.recoveryCondition)
    guard labStore.bindRun(campaignId: campaign.id, trialId: trial.id, runId: runId) != nil else { return }
    appendEvent(type: .runCreated, run: run, agentId: trial.agentId)
    appendEvent(type: .runStarted, run: run, agentId: trial.agentId)
    if trial.recoveryCondition != .normal, !trial.previousRunId.isBlank {
      appendEvent(
        type: .runRecovered,
        run: run,
        agentId: trial.agentId,
        payload: [
          "condition": .string(trial.recoveryCondition.rawValue),
          "previous_run_id": .string(trial.previousRunId)
        ]
      )
    }

    do {
      try Task.checkCancellation()
      guard let adapter = try await directory.resolveAdapter(trial.agentId) else {
        throw AgentEvolutionLabRuntimeError(message: "Selected Agent is unavailable")
      }
      locked { activeAdapters[campaign.id, default: [:]][runId] = adapter }
      defer { locked { activeAdapters[campaign.id]?.removeValue(forKey: runId) } }
      let request = AgentRunRequest(
        conversationId: conversationId,
        messageId: trial.id,
        taskId: trial.id,
        runId: runId,
        parentRunId: campaign.id,
        goal: campaign.task,
        deliveryMode: .respond,
        requiredCapabilities: [],
        context: [
          "managed_team": .bool(true),
          "agent_lab": .bool(true),
          "campaign_id": .string(campaign.id),
          "trial_id": .string(trial.id),
          "recovery_condition": .string(trial.recoveryCondition.rawValue),
          "previous_run_id": .string(trial.previousRunId),
          "recovery_attempt": .int(Int64(trial.recoveryAttempt)),
          "outcome_contract": .string(Self.encodedContract(campaign.outcomeContract))
        ],
        idempotencyKey: AgentLabRunIdentity.idempotencyKey(campaignId: campaign.id, trial: trial),
        createdAtMillis: createdAt
      )
      let handle = try await adapter.startRun(request)
      let terminal = try await observeTerminalEvent(
        adapter: adapter,
        request: request,
        remoteRunId: handle.runId,
        localRunId: runId,
        conversationId: conversationId,
        trial: trial
      )
      let completedAt = max(terminal.timestampMillis, nowMillis())
      let terminalText = Self.payloadText(terminal.payload)
      let text = terminal.type == .runCompleted ? terminalText : ""
      let richOutput = terminal.type == .runCompleted
        ? terminal.payload["rich_output"]?.stringValue ?? text
        : ""
      let failureCode = AgentLabRunFailurePolicy.code(
        error: nil,
        terminalType: terminal.type,
        output: text,
        detail: terminalText
      )
      run.finalOutput = [
        "message": .string(text),
        "rich_output": .string(richOutput),
        "campaign_id": .string(campaign.id),
        "trial_id": .string(trial.id),
        "error": .string(terminal.type == .runCompleted ? "" : terminalText),
        "failure_code": .string(failureCode)
      ]
      switch terminal.type {
      case .runCompleted: run.status = .completed
      case .runCancelled: run.status = .cancelled
      default: run.status = .failed
      }
      run.completedAtMillis = completedAt
      recordedRunStore.upsert(run)
      if let sample = AgentEvalOpsService.observeRunCompleted(
        run,
        store: evalStore,
        memoryTrustStore: memoryTrustStore,
        events: eventStore.events(runId: runId)
      ) {
        _ = labStore.observe(sample)
      } else if run.status != .completed {
        _ = labStore.markTrialFailed(campaignId: campaign.id, trialId: trial.id)
      }
    } catch is CancellationError {
      run.status = .cancelled
      run.completedAtMillis = nowMillis()
      run.finalOutput = ["failure_code": .string("cancelled")]
      recordedRunStore.upsert(run)
      appendEvent(type: .runCancelled, run: run, agentId: trial.agentId)
    } catch {
      run.status = .failed
      run.completedAtMillis = nowMillis()
      run.finalOutput = [
        "error": .string(String(error.localizedDescription.prefix(2_000))),
        "failure_code": .string(AgentLabRunFailurePolicy.code(
          error: error,
          terminalType: nil,
          output: "",
          detail: error.localizedDescription
        ))
      ]
      recordedRunStore.upsert(run)
      appendEvent(
        type: .runFailed,
        run: run,
        agentId: trial.agentId,
        payload: ["error": .string(String(error.localizedDescription.prefix(2_000)))]
      )
      _ = AgentEvalOpsService.observeRunCompleted(
        run,
        store: evalStore,
        memoryTrustStore: memoryTrustStore,
        events: eventStore.events(runId: runId)
      )
      _ = labStore.markTrialFailed(campaignId: campaign.id, trialId: trial.id)
    }
  }

  private func observeTerminalEvent(
    adapter: AgentAdapter,
    request: AgentRunRequest,
    remoteRunId: String,
    localRunId: String,
    conversationId: String,
    trial: AgentLabTrial
  ) async throws -> AgentRunControlEvent {
    let persistentEventStore = eventStore
    let livenessProbe = AgentRunLivenessProbe.start(
      adapter: adapter,
      request: request,
      remoteRunId: remoteRunId,
      intervalNanoseconds: trialLivenessProbeNanoseconds
    )
    defer { livenessProbe.cancel() }
    for await event in adapter.observeEvents(runId: remoteRunId) {
      try Task.checkCancellation()
      let localEvent = AgentRunControlEvent(
        eventId: "lab:\(localRunId):\(event.eventId)",
        conversationId: conversationId,
        messageId: trial.id,
        taskId: trial.id,
        runId: localRunId,
        stepId: event.stepId,
        toolCallId: event.toolCallId,
        agentId: trial.agentId,
        deviceId: event.deviceId,
        type: event.type,
        sequence: 0,
        timestampMillis: event.timestampMillis,
        payload: event.payload
      )
      _ = persistentEventStore.appendNext(localEvent)
      if [.runCompleted, .runFailed, .runCancelled].contains(event.type) {
        return localEvent
      }
    }
    throw AgentEvolutionLabRuntimeError(message: "Agent completed without a terminal event")
  }

  private func ensureWatchdog() {
    locked {
      guard watchdogTask == nil else { return }
      watchdogTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: self.watchdogIntervalNanoseconds)
          guard !Task.isCancelled else { return }
          self.recoverStalledCampaigns()
        }
      }
    }
  }

  private func recoverStalledCampaigns() {
    let now = nowMillis()
    for campaign in labStore.list() {
      let hasActiveTask = locked { campaignTasks[campaign.id] != nil }
      guard AgentLabStallRecoveryPolicy.shouldRecover(
        campaign: campaign,
        hasActiveTask: hasActiveTask,
        nowMillis: now,
        staleAfterMillis: staleCampaignMillis
      ) else { continue }
      _ = recoverAndStart(
        campaignId: campaign.id,
        condition: .processDeath,
        reason: "Agent Lab campaign made no progress before its watchdog deadline",
        replaceActive: hasActiveTask
      )
    }
  }

  private func recoverAndStart(
    campaignId: String,
    condition: AgentEvalCondition,
    reason: String,
    replaceActive: Bool
  ) -> Bool {
    let cancellation = locked { () -> (Task<Void, Never>?, [String: AgentAdapter]) in
      let active = campaignTasks[campaignId]
      guard replaceActive || active == nil else { return (nil, [:]) }
      campaignTasks.removeValue(forKey: campaignId)
      campaignTaskGenerations.removeValue(forKey: campaignId)
      return (active, activeAdapters.removeValue(forKey: campaignId) ?? [:])
    }
    if cancellation.0 == nil,
       locked({ campaignTasks[campaignId] != nil }) {
      return false
    }
    cancellation.0?.cancel()
    if !cancellation.1.isEmpty {
      Task {
        for (runId, adapter) in cancellation.1 {
          try? await adapter.cancelRun(runId: runId)
        }
      }
    }
    guard let campaign = labStore.get(id: campaignId),
          ![.readyForReview, .completed, .cancelled].contains(campaign.status),
          campaign.trials.contains(where: { !AgentLabRecoveryPolicy.terminalTrials.contains($0.status) }) else {
      return false
    }
    let interrupted = campaign.trials.filter {
      !AgentLabRecoveryPolicy.terminalTrials.contains($0.status) && !$0.runId.isBlank
    }
    guard let recovered = labStore.resetIncompleteTrials(
      campaignId: campaignId,
      condition: condition
    ) else { return false }
    interrupted.forEach {
      _ = AgentEvalOpsService.observeRunInterrupted(
        runId: $0.runId,
        condition: condition,
        reason: reason,
        store: evalStore,
        runStore: recordedRunStore,
        eventStore: eventStore
      )
    }
    do {
      try start(campaignId: recovered.id)
      return true
    } catch {
      return false
    }
  }

  private func scheduleRestartIfIncomplete(campaignId: String) {
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard let self else { return }
      _ = self.resumeIncomplete(
        campaignIds: [campaignId],
        condition: .processDeath,
        reason: "Agent Lab campaign worker exited before all trials became terminal"
      )
    }
  }

  private func appendEvent(
    type: AgentRunControlEventType,
    run: AgentRecordedRun,
    agentId: String,
    payload: AgentRunControlPayload = [:]
  ) {
    _ = eventStore.appendNext(AgentRunControlEvent(
      conversationId: run.conversationId,
      messageId: run.taskThreadId,
      taskId: run.taskThreadId,
      runId: run.runId,
      agentId: agentId,
      deviceId: "ios",
      type: type,
      sequence: 0,
      timestampMillis: nowMillis(),
      payload: payload
    ))
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  private static func payloadText(_ payload: AgentRunControlPayload) -> String {
    for key in ["content", "text", "output", "result", "error", "message"] {
      if let value = payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
        return value
      }
    }
    return ""
  }

  private static func encodedContract(_ contract: AgentOutcomeContract) -> String {
    guard let data = try? JSONEncoder().encode(contract) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
}

enum AgentLabAgentSelectionPolicy {
  static func independentAgents(_ registrations: [AgentRegistration]) -> [AgentRegistration] {
    var byId: [String: AgentRegistration] = [:]
    registrations.forEach { byId[$0.agentId] = $0 }
    var byRuntime: [String: AgentRegistration] = [:]
    for registration in byId.values {
      let scope = registration.runtimeHealthScope()
      if let current = byRuntime[scope], !prefers(registration, over: current) { continue }
      byRuntime[scope] = registration
    }
    return byRuntime.values.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  private static func prefers(_ candidate: AgentRegistration, over current: AgentRegistration) -> Bool {
    let candidateConcrete = candidate.agentId.contains(":")
    let currentConcrete = current.agentId.contains(":")
    if candidateConcrete != currentConcrete { return candidateConcrete }
    let candidateNamed = candidate.displayName.contains("\u{00b7}")
    let currentNamed = current.displayName.contains("\u{00b7}")
    if candidateNamed != currentNamed { return candidateNamed }
    return candidate.updatedAtMillis > current.updatedAtMillis
  }
}

enum AgentLabRunFailurePolicy {
  static func code(
    error: Error?,
    terminalType: AgentRunControlEventType?,
    output: String,
    detail: String = ""
  ) -> String {
    let failure = ([error?.localizedDescription, detail].compactMap { $0 })
      .joined(separator: " ")
      .lowercased()
    if failure.contains("timeout") || failure.contains("timed out") { return "response_timeout" }
    if error is CancellationError || terminalType == .runCancelled { return "cancelled" }
    if error != nil { return "worker_failure" }
    if terminalType == .runFailed { return "dispatch_failed" }
    if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "empty_response" }
    return ""
  }
}

final class AgentEvolutionLabRuntimeRegistry {
  static let shared = AgentEvolutionLabRuntimeRegistry()
  private let lock = NSRecursiveLock()
  private var runtime: AgentEvolutionLabRuntime?

  private init() {}

  func install(_ runtime: AgentEvolutionLabRuntime) {
    lock.lock()
    self.runtime = runtime
    lock.unlock()
  }

  func current() -> AgentEvolutionLabRuntime? {
    lock.lock()
    defer { lock.unlock() }
    return runtime
  }

  func clear() {
    lock.lock()
    runtime = nil
    lock.unlock()
  }
}

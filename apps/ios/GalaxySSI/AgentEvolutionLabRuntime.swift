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
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()
  private var campaignTasks: [String: Task<Void, Never>] = [:]
  private var activeAdapters: [String: [String: AgentAdapter]] = [:]

  init(
    directory: AgentAdapterDirectory,
    labStore: AgentLabStore = AgentLabStore(),
    evalStore: AgentEvalOpsStore = AgentEvalOpsStore(),
    recordedRunStore: AgentRecordedRunStoring = UserDefaultsAgentRecordedRunStore(),
    eventStore: AgentRunEventPersistence = UserDefaultsAgentRunEventStore(),
    memoryTrustStore: AgentMemoryTrustStore = AgentMemoryTrustStore(),
    maximumParallelTrials: Int = 3,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.directory = directory
    self.labStore = labStore
    self.evalStore = evalStore
    self.recordedRunStore = recordedRunStore
    self.eventStore = eventStore
    self.memoryTrustStore = memoryTrustStore
    self.maximumParallelTrials = min(max(maximumParallelTrials, 1), 10)
    self.nowMillis = nowMillis
  }

  func availableAgents() async throws -> [AgentRegistration] {
    (try await directory.registrations()).filter {
      [.agent, .model].contains($0.kind) &&
        ![.offline, .unreachable, .updating, .permissionRequired].contains($0.status) &&
        $0.hasCapacity
    }
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
    guard requested.count >= 2, requested.isSubset(of: available) else {
      throw AgentEvolutionLabRuntimeError(message: "Every selected Agent must be online and available")
    }
    guard let campaign = labStore.create(task: task, agentIds: Array(requested).sorted(), repetitions: repetitions) else {
      throw AgentEvolutionLabRuntimeError(message: "A Lab campaign requires a task and at least two Agents")
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
    let created = locked { () -> Bool in
      guard campaignTasks[campaignId] == nil else { return false }
      campaignTasks[campaignId] = Task { [weak self] in
        guard let self else { return }
        await self.runCampaign(campaignId: campaignId)
      }
      return true
    }
    guard created else {
      throw AgentEvolutionLabRuntimeError(message: "Lab campaign is already running")
    }
  }

  @discardableResult
  func resumeInterrupted(campaignId: String) throws -> AgentLabCampaign {
    guard let campaign = labStore.resetInterruptedTrials(campaignId: campaignId) else {
      throw AgentEvolutionLabRuntimeError(message: "Lab campaign cannot be resumed")
    }
    try start(campaignId: campaign.id)
    return campaign
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

  private func runCampaign(campaignId: String) async {
    defer {
      locked {
        campaignTasks.removeValue(forKey: campaignId)
        activeAdapters.removeValue(forKey: campaignId)
      }
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
    if Task.isCancelled { _ = labStore.cancel(campaignId: campaignId) }
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
    AgentEvalOpsService.observeRunStarted(run, store: evalStore)
    guard labStore.bindRun(campaignId: campaign.id, trialId: trial.id, runId: runId) != nil else { return }
    appendEvent(type: .runCreated, run: run, agentId: trial.agentId)
    appendEvent(type: .runStarted, run: run, agentId: trial.agentId)

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
          "outcome_contract": .string(Self.encodedContract(campaign.outcomeContract))
        ],
        idempotencyKey: "lab:\(campaign.id):\(trial.id)",
        createdAtMillis: createdAt
      )
      let handle = try await adapter.startRun(request)
      var terminal: AgentRunControlEvent?
      for await event in adapter.observeEvents(runId: handle.runId) {
        try Task.checkCancellation()
        let localEvent = AgentRunControlEvent(
          eventId: "lab:\(runId):\(event.eventId)",
          conversationId: conversationId,
          messageId: trial.id,
          taskId: trial.id,
          runId: runId,
          stepId: event.stepId,
          toolCallId: event.toolCallId,
          agentId: trial.agentId,
          deviceId: event.deviceId,
          type: event.type,
          sequence: 0,
          timestampMillis: event.timestampMillis,
          payload: event.payload
        )
        _ = eventStore.appendNext(localEvent)
        if [.runCompleted, .runFailed, .runCancelled].contains(event.type) {
          terminal = localEvent
          break
        }
      }
      guard let terminal else {
        throw AgentEvolutionLabRuntimeError(message: "Agent completed without a terminal event")
      }
      let completedAt = max(terminal.timestampMillis, nowMillis())
      let text = Self.payloadText(terminal.payload)
      let richOutput = terminal.payload["rich_output"]?.stringValue ?? text
      run.finalOutput = [
        "message": .string(text),
        "rich_output": .string(richOutput),
        "campaign_id": .string(campaign.id),
        "trial_id": .string(trial.id)
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
      recordedRunStore.upsert(run)
      appendEvent(type: .runCancelled, run: run, agentId: trial.agentId)
      _ = labStore.cancel(campaignId: campaign.id)
    } catch {
      run.status = .failed
      run.completedAtMillis = nowMillis()
      run.finalOutput = ["error": .string(String(error.localizedDescription.prefix(2_000)))]
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

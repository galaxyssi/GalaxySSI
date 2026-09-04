import Foundation

final class GalaxySSIGlobalProactiveDiscoveryRuntimeStore {
  private struct Snapshot: Codable {
    var formatVersion: Int
    var state: GlobalProactiveDiscoveryState
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private(set) var lastErrorDescription: String = ""

  init(
    fileURL: URL = GalaxySSIGlobalProactiveDiscoveryRuntimeStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("global-proactive-discovery", isDirectory: true)
      .appendingPathComponent("state.json", isDirectory: false)
  }

  static func destroyPersistentStore(
    fileURL: URL = GalaxySSIGlobalProactiveDiscoveryRuntimeStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(at: fileURL)
  }

  func state() -> GlobalProactiveDiscoveryState {
    locked { load() }
  }

  func save(_ state: GlobalProactiveDiscoveryState) {
    locked { persist(state) }
  }

  @discardableResult
  func makeDue(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> GlobalProactiveDiscoveryState {
    let next = GlobalProactiveDiscoveryPolicy.makeDue(state(), nowMillis: nowMillis)
    save(next)
    return next
  }

  private func load() -> GlobalProactiveDiscoveryState {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return GlobalProactiveDiscoveryState()
    }
    do {
      let data = try Data(contentsOf: fileURL)
      guard !data.isEmpty else { return GlobalProactiveDiscoveryState() }
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
      guard snapshot.formatVersion == formatVersion else {
        lastErrorDescription = "Unsupported proactive discovery store format"
        return GlobalProactiveDiscoveryState()
      }
      lastErrorDescription = ""
      return snapshot.state
    } catch {
      lastErrorDescription = error.localizedDescription
      return GlobalProactiveDiscoveryState()
    }
  }

  private func persist(_ state: GlobalProactiveDiscoveryState) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let snapshot = Snapshot(formatVersion: formatVersion, state: state)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
      lastErrorDescription = ""
    } catch {
      lastErrorDescription = error.localizedDescription
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private let formatVersion = 1
}

struct GalaxySSIGlobalResearchCycleResult: Codable, Equatable {
  var result: GlobalResearchExecutionResult?
  var dispatchRequests: [GlobalResearchDispatchRequest]

  init(
    result: GlobalResearchExecutionResult? = nil,
    dispatchRequests: [GlobalResearchDispatchRequest] = []
  ) {
    self.result = result
    self.dispatchRequests = dispatchRequests
  }
}

final class GalaxySSIGlobalResearchRuntimeStore {
  private struct Snapshot: Codable {
    var formatVersion: Int
    var state: GlobalResearchExecutorState
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private(set) var lastErrorDescription: String = ""

  init(
    fileURL: URL = GalaxySSIGlobalResearchRuntimeStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("global-research", isDirectory: true)
      .appendingPathComponent("state.json", isDirectory: false)
  }

  static func destroyPersistentStore(
    fileURL: URL = GalaxySSIGlobalResearchRuntimeStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(at: fileURL)
  }

  func state() -> GlobalResearchExecutorState {
    locked { load() }
  }

  func save(_ state: GlobalResearchExecutorState) {
    locked { persist(bounded(state)) }
  }

  private func load() -> GlobalResearchExecutorState {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return GlobalResearchExecutorState()
    }
    do {
      let data = try Data(contentsOf: fileURL)
      guard !data.isEmpty else { return GlobalResearchExecutorState() }
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
      guard snapshot.formatVersion == formatVersion else {
        lastErrorDescription = "Unsupported global research store format"
        return GlobalResearchExecutorState()
      }
      lastErrorDescription = ""
      return bounded(snapshot.state)
    } catch {
      lastErrorDescription = error.localizedDescription
      return GlobalResearchExecutorState()
    }
  }

  private func persist(_ state: GlobalResearchExecutorState) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let snapshot = Snapshot(formatVersion: formatVersion, state: bounded(state))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
      lastErrorDescription = ""
    } catch {
      lastErrorDescription = error.localizedDescription
    }
  }

  private func bounded(_ state: GlobalResearchExecutorState) -> GlobalResearchExecutorState {
    var bounded = state
    bounded.tasks = Array(state.tasks
      .sorted {
        if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
        return $0.id < $1.id
      }
      .suffix(300))
    bounded.dispatchRequests = Array(state.dispatchRequests.suffix(100))
    bounded.proactiveMessages = Array(state.proactiveMessages.suffix(500))
    bounded.events = Array(state.events.suffix(500))
    bounded.healthUpdates = Array(state.healthUpdates.suffix(300))
    return bounded
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private let formatVersion = 1
}

struct GalaxySSIGlobalCognitionDispatchRequest: Equatable {
  var taskId: String
  var resourceId: String
  var transport: GlobalResearchResourceTransport
  var contactId: String
  var sourceMessageId: Int64
  var conversationId: String
  var turnId: String
  var systemPrompt: String
  var prompt: String
}

struct GalaxySSIGlobalCognitionExecutionResult: Equatable {
  var taskId: String
  var status: GlobalCognitionTaskStatus
  var resourceId: String
  var detail: String
}

enum GalaxySSIGlobalModelUnderstandingParser {
  static func parse(_ raw: String) -> GlobalModelUnderstanding? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = trimmed.firstIndex(of: "{"),
          let end = trimmed.lastIndex(of: "}"),
          start <= end else {
      return nil
    }
    let candidate = String(trimmed[start...end])
    guard let data = candidate.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else {
      return nil
    }
    let payload: Any
    if let dictionary = object as? [String: Any],
       let nested = dictionary["understanding"] ?? dictionary["result"] {
      payload = nested
    } else {
      payload = object
    }
    guard let normalized = normalize(payload),
          JSONSerialization.isValidJSONObject(normalized),
          let normalizedData = try? JSONSerialization.data(withJSONObject: normalized) else {
      return nil
    }
    return try? JSONDecoder().decode(GlobalModelUnderstanding.self, from: normalizedData)
  }

  private static func normalize(_ value: Any) -> Any? {
    if let dictionary = value as? [String: Any] {
      return dictionary.reduce(into: [String: Any]()) { result, entry in
        guard let normalized = normalize(entry.value) else { return }
        result[camelCase(entry.key)] = normalized
      }
    }
    if let array = value as? [Any] {
      return array.compactMap { normalize($0) }
    }
    if value is NSNull || value is String || value is NSNumber {
      return value
    }
    return nil
  }

  private static func camelCase(_ value: String) -> String {
    let parts = value.split(separator: "_")
    guard let first = parts.first else { return value }
    return String(first) + parts.dropFirst().map { part in
      let text = String(part)
      return text.prefix(1).uppercased() + text.dropFirst()
    }.joined()
  }
}

final class GalaxySSIGlobalLongHorizonRuntimeStore: GlobalLongHorizonRuntimeStore {
  private var settingsValue: GlobalAgentSettings
  private var worldValue: PersonalWorldModel
  private let graphValue: GlobalTopicProjectGraph
  private let deliberationStore: GlobalAgentDeliberationStore
  private(set) var emittedProactiveMessages: [GlobalProactiveMessage] = []

  init(
    settings: GlobalAgentSettings,
    world: PersonalWorldModel,
    topicGraph: GlobalTopicProjectGraph,
    deliberationStore: GlobalAgentDeliberationStore = GlobalAgentDeliberationStore()
  ) {
    self.settingsValue = settings
    self.worldValue = world
    self.graphValue = topicGraph
    self.deliberationStore = deliberationStore
  }

  func settings() -> GlobalAgentSettings {
    settingsValue
  }

  func loadWorld() -> PersonalWorldModel {
    worldValue
  }

  func saveWorld(_ world: PersonalWorldModel) {
    worldValue = world
  }

  func topicGraph() -> GlobalTopicProjectGraph {
    graphValue
  }

  func cognitionTasks() -> [GlobalCognitionTask] {
    deliberationStore.cognitionTasks()
  }

  func upsertCognitionTask(_ task: GlobalCognitionTask) {
    deliberationStore.upsertCognitionTask(task)
  }

  func autonomousRuns() -> [GlobalAutonomousRun] {
    deliberationStore.autonomousRuns()
  }

  func appendProactiveMessage(_ message: GlobalProactiveMessage) {
    guard !emittedProactiveMessages.contains(where: { $0.id == message.id }) else { return }
    emittedProactiveMessages.append(message)
  }
}

@MainActor
enum GalaxySSIGlobalAgentRuntimeBridge {
  @discardableResult
  static func processProactiveDiscoveryCycle(
    store: GalaxySSIStore,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    force: Bool = false,
    maxTasks: Int = 2
  ) -> GlobalProactiveDiscoveryCycleResult {
    let settings = store.globalAgentSettings
    guard settings.enabled,
          settings.proactiveDiscoveryEnabled,
          settings.modelUnderstandingEnabled else {
      return GlobalProactiveDiscoveryCycleResult(
        scanned: false,
        candidateCount: 0,
        queuedTaskCount: 0,
        nextWakeAtMillis: 0
      )
    }

    let discoveryStore = GalaxySSIGlobalProactiveDiscoveryRuntimeStore()
    let current = discoveryStore.state()
    guard let (claimed, claim) = GlobalProactiveDiscoveryPolicy.claim(
      state: current,
      nowMillis: nowMillis,
      force: force
    ) else {
      return GlobalProactiveDiscoveryCycleResult(
        scanned: false,
        candidateCount: 0,
        queuedTaskCount: 0,
        nextWakeAtMillis: GlobalProactiveDiscoveryPolicy.nextWakeAt(current, nowMillis: nowMillis)
      )
    }

    let excludedConversationIds = Set(
      store.agentSessions(includeArchived: true)
        .filter { $0.privateMode || $0.trackingPaused }
        .map(\.id)
    )
    let candidates = GlobalProactiveDiscoveryPolicy.scan(
      world: worldModel(from: store.agentMemorySnapshot(), nowMillis: nowMillis),
      goals: GlobalLongHorizonGoalStore().goals(),
      excludedConversationIds: excludedConversationIds,
      nowMillis: nowMillis,
      topicGraph: topicGraph(from: store.agentSessions(includeArchived: true), nowMillis: nowMillis)
    )
    let deliberationStore = GlobalAgentDeliberationStore()
    let selected = GlobalProactiveDiscoveryPolicy.selectForDeliberation(
      candidates: candidates,
      state: claimed,
      existingTasks: deliberationStore.cognitionTasks(),
      settings: settings,
      nowMillis: nowMillis,
      maxTasks: max(1, min(maxTasks, 12))
    )
    selected.forEach { candidate in
      deliberationStore.upsertCognitionTask(
        GlobalProactiveDiscoveryPolicy.task(candidate, nowMillis: nowMillis)
      )
    }
    let completed = GlobalProactiveDiscoveryPolicy.complete(
      state: claimed,
      claim: claim,
      emitted: selected,
      nowMillis: nowMillis,
      intervalMillis: settings.discoveryIntervalMillis
    )
    discoveryStore.save(completed)
    return GlobalProactiveDiscoveryCycleResult(
      scanned: true,
      candidateCount: candidates.count,
      queuedTaskCount: selected.count,
      nextWakeAtMillis: GlobalProactiveDiscoveryPolicy.nextWakeAt(completed, nowMillis: nowMillis)
    )
  }

  static func proactiveDiscoveryState() -> GlobalProactiveDiscoveryState {
    GalaxySSIGlobalProactiveDiscoveryRuntimeStore().state()
  }

  @discardableResult
  static func requestImmediateProactiveDiscovery(
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalProactiveDiscoveryState {
    GalaxySSIGlobalProactiveDiscoveryRuntimeStore().makeDue(nowMillis: nowMillis)
  }

  @discardableResult
  static func processCognitionCycle(
    store: GalaxySSIStore,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GalaxySSIGlobalCognitionDispatchRequest? {
    let settings = store.globalAgentSettings
    guard settings.enabled, settings.modelUnderstandingEnabled else { return nil }
    let deliberationStore = GlobalAgentDeliberationStore()
    guard let claimed = deliberationStore.claimCognitionTask(nowMillis: nowMillis) else { return nil }
    let resource = cognitionResource(
      from: store,
      allowPaired: settings.allowPairedAgentCognition,
      allowCloud: settings.allowCloudCognition,
      excluding: Set(claimed.attemptedResourceIds)
    )
    guard let resource else {
      _ = deliberationStore.updateCognitionTask(taskId: claimed.id) { current in
        var waiting = current
        waiting.status = .waitingForResource
        waiting.sourceMessageId = 0
        waiting.leaseExpiresAtMillis = 0
        waiting.nextAttemptAtMillis = nowMillis + GlobalCognitionTaskPolicy.retryDelayMillis(attemptCount: current.attemptCount)
        waiting.lastError = "No trusted reasoning resource is currently available"
        waiting.updatedAtMillis = nowMillis
        return waiting
      }
      return nil
    }

    let sourceMessageId = cognitionCorrelationId(taskId: claimed.id, nowMillis: nowMillis)
    let running = deliberationStore.updateCognitionTask(taskId: claimed.id) { current in
      var next = current
      next.status = .running
      next.resourceId = resource.id
      next.sourceMessageId = sourceMessageId
      next.leaseExpiresAtMillis = nowMillis + GlobalCognitionTaskPolicy.leaseMillis
      next.lastError = ""
      next.updatedAtMillis = nowMillis
      return next
    } ?? claimed
    let context = GlobalRealtimeContextProvider(
      cognitionTasksSource: { [running] }
    ).build(
      query: running.sourceEvent.content,
      currentConversationId: running.sourceEvent.conversationId,
      maximumItems: 12,
      maximumCharacters: 12_000,
      nowMillis: nowMillis
    )
    return GalaxySSIGlobalCognitionDispatchRequest(
      taskId: running.id,
      resourceId: resource.id,
      transport: resource.transport,
      contactId: resource.contactId,
      sourceMessageId: sourceMessageId,
      conversationId: "global-cognition:\(running.id)",
      turnId: running.id,
      systemPrompt: cognitionSystemPrompt,
      prompt: cognitionPrompt(task: running, realtimeContext: context)
    )
  }

  @discardableResult
  static func consumeCognitionResponse(
    _ response: AgentConnectorResponse,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GalaxySSIGlobalCognitionExecutionResult? {
    let deliberationStore = GlobalAgentDeliberationStore()
    guard let task = deliberationStore.cognitionTasks().first(where: {
      $0.status == .running && $0.sourceMessageId == response.sourceMessageId
    }) else {
      return nil
    }
    guard response.success,
          let understanding = GalaxySSIGlobalModelUnderstandingParser.parse(response.content) else {
      let retry = deliberationStore.updateCognitionTask(taskId: task.id) { current in
        var next = current
        next.status = current.attemptCount >= GlobalCognitionTaskPolicy.maxAttempts ? .failed : .waitingForResource
        next.sourceMessageId = 0
        next.leaseExpiresAtMillis = 0
        next.nextAttemptAtMillis = next.status == .failed
          ? 0
          : nowMillis + GlobalCognitionTaskPolicy.retryDelayMillis(attemptCount: current.attemptCount)
        next.lastError = response.content.ifBlank("The reasoning result was not valid structured cognition data")
        next.updatedAtMillis = nowMillis
        return next
      }
      return retry.map {
        GalaxySSIGlobalCognitionExecutionResult(
          taskId: $0.id,
          status: $0.status,
          resourceId: $0.resourceId,
          detail: $0.lastError
        )
      }
    }
    let completed = deliberationStore.updateCognitionTask(taskId: task.id) { current in
      var next = current
      next.status = .completed
      next.sourceMessageId = 0
      next.leaseExpiresAtMillis = 0
      next.nextAttemptAtMillis = 0
      next.lastError = ""
      next.result = understanding
      next.updatedAtMillis = nowMillis
      return next
    }
    if let completed {
      _ = GalaxySSIGlobalAutonomousRunPlanner.upsertRun(
        store: deliberationStore,
        task: completed,
        nowMillis: nowMillis
      )
    }
    return completed.map {
      GalaxySSIGlobalCognitionExecutionResult(
        taskId: $0.id,
        status: $0.status,
        resourceId: $0.resourceId.ifBlank(response.contactId),
        detail: understanding.userInsight.ifBlank(understanding.progressSummary)
      )
    }
  }

  private static func cognitionResource(
    from store: GalaxySSIStore,
    allowPaired: Bool,
    allowCloud: Bool,
    excluding: Set<String>
  ) -> GlobalResearchExecutorResource? {
    let localRuntime = LocalModelCooperativeRuntime.shared
    let localProfile = localRuntime.displayProfile()
    let localResourceId = "phone-local-model"
    let localReady = localRuntime.readyForBackground()
    let localDescriptor = backgroundResourceDescriptor(
      id: localResourceId,
      type: .onDeviceModel,
      location: .phone,
      status: localReady ? .available : .needsSetup,
      trust: .phoneSystem,
      supportsBackground: true
    )
    if !excluding.contains(localResourceId),
       GlobalBackgroundReasoningResourcePolicy.allowed(
         localDescriptor,
         allowPaired: allowPaired,
         allowCloud: allowCloud,
         localModelReady: localReady
       ) {
      return GlobalResearchExecutorResource(
        id: localResourceId,
        transport: .onDeviceModel,
        capabilities: [.reasoning, .chat, .localInference],
        displayName: localProfile.displayName
      )
    }
    let paired = store.visibleContacts.first { contact in
      !contact.deleted &&
        contact.trustState == .verified &&
        contact.deliveryMode.isGalaxySSILinkFamily &&
        AgentConnectorAvailability.desktopAgentReady(contact: contact) &&
        !excluding.contains(contact.id) &&
        GlobalBackgroundReasoningResourcePolicy.allowed(
          backgroundResourceDescriptor(
            id: contact.id,
            type: .remoteAgent,
            location: .trustedDesktop,
            status: .available,
            trust: .verifiedPaired,
            supportsBackground: true
          ),
          allowPaired: allowPaired,
          allowCloud: allowCloud,
          localModelReady: localReady
        )
    }
    if let paired {
      return GlobalResearchExecutorResource(
        id: paired.id,
        transport: .pairedAgent,
        contactId: paired.id,
        capabilities: [.reasoning, .chat],
        displayName: paired.displayName.ifBlank(paired.name)
      )
    }
    return store.visibleContacts.first { contact in
      !contact.deleted &&
        contact.deliveryMode == .cloudAPI &&
        !excluding.contains(contact.id) &&
        AgentConnectorAvailability.cloudModelReady(contact: contact, apiKey: contact.selectedCloudModel.flatMap(store.apiKey(for:))) &&
        GlobalBackgroundReasoningResourcePolicy.allowed(
          backgroundResourceDescriptor(
            id: contact.id,
            type: .cloudModel,
            location: .cloud,
            status: .available,
            trust: .cloudConfigured,
            supportsBackground: true
          ),
          allowPaired: allowPaired,
          allowCloud: allowCloud,
          localModelReady: localReady
        )
    }.map { contact in
      GlobalResearchExecutorResource(
        id: contact.id,
        transport: .cloudModel,
        contactId: contact.id,
        capabilities: [.reasoning, .chat],
        displayName: contact.selectedCloudModel?.displayName.ifBlank(contact.displayName) ?? contact.displayName
      )
    }
  }

  private static func cognitionCorrelationId(taskId: String, nowMillis: Int64) -> Int64 {
    let fingerprintInput = ["ios-cognition", taskId, String(nowMillis)].joined(separator: "\u{001f}")
    let hex = String(GlobalAgentText.privateFingerprint(fingerprintInput).prefix(15))
    return max(Int64(hex, radix: 16) ?? 1, 1)
  }

  private static func cognitionPrompt(task: GlobalCognitionTask, realtimeContext: String) -> String {
    let source = task.sourceEvent
    return """
    Analyze this authorized global-agent event for durable personal context. Do not include private conversations. Return one JSON object only using camelCase keys matching GlobalModelUnderstanding: topic, project, relatedTopics, intent, entities, goals, tasks, decisions, preferences, risks, opportunities, researchQuestions, goalDependencies, actions, userInsight, goalState, progressSummary, nextCheckHours, confidence.

    Conversation: \(source.conversationTitle)
    Event: \(source.content)
    Baseline topic: \(task.baselineUnderstanding.topic)
    Baseline intent: \(task.baselineIntent)
    Realtime global context:
    \(realtimeContext)
    """
  }

  private static let cognitionSystemPrompt = "You are GalaxySSI's structured global cognition engine. Respect privacy boundaries, use only supplied context, and return valid JSON with no markdown."

  @discardableResult
  static func processLongHorizonCycle(
    store: GalaxySSIStore,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalLongHorizonCycleResult {
    let runtimeStore = GalaxySSIGlobalLongHorizonRuntimeStore(
      settings: store.globalAgentSettings,
      world: worldModel(from: store.agentMemorySnapshot(), nowMillis: nowMillis),
      topicGraph: topicGraph(from: store.agentSessions(includeArchived: true), nowMillis: nowMillis)
    )
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtimeStore)
    let result = coordinator.processDue(nowMillis: nowMillis)
    runtimeStore.emittedProactiveMessages.forEach { store.appendGlobalProactiveMessage($0) }
    return result
  }

  @discardableResult
  static func processResearchCycle(
    store: GalaxySSIStore,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GalaxySSIGlobalResearchCycleResult {
    let stateStore = GalaxySSIGlobalResearchRuntimeStore()
    var state = stateStore.state()
    seedResearchTasks(from: GlobalAgentDeliberationStore().cognitionTasks(), into: &state, nowMillis: nowMillis)
    let existingDispatchIds = Set(state.dispatchRequests.map(\.id))
    let task = state.tasks.first {
      [.queued, .scheduled, .waitingForResource].contains($0.status) && $0.nextAttemptAtMillis <= nowMillis
    } ?? state.tasks.first(where: { $0.status == .running })
    let context = researchContext(
      store: store,
      state: state,
      task: task,
      nowMillis: nowMillis
    )
    let resources = researchResources(from: store, settings: store.globalAgentSettings)
    guard let step = GlobalResearchExecutorPolicy.executeNext(
      state: state,
      resources: resources,
      context: context,
      nowMillis: nowMillis
    ) else {
      stateStore.save(state)
      return GalaxySSIGlobalResearchCycleResult()
    }
    stateStore.save(step.state)
    step.state.proactiveMessages.forEach { store.appendGlobalProactiveMessage($0) }
    let requests = step.state.dispatchRequests.filter { !existingDispatchIds.contains($0.id) }
    return GalaxySSIGlobalResearchCycleResult(
      result: step.result,
      dispatchRequests: requests
    )
  }

  @discardableResult
  static func consumeResearchResponse(
    store: GalaxySSIStore,
    response: AgentConnectorResponse,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    let stateStore = GalaxySSIGlobalResearchRuntimeStore()
    let state = stateStore.state()
    let task = state.tasks.first {
      $0.sourceMessageId == response.sourceMessageId ||
        $0.researchPlan.synthesisSourceMessageId == response.sourceMessageId ||
        $0.researchPlan.units.contains { $0.sourceMessageId == response.sourceMessageId }
    }
    let step = GlobalResearchExecutorPolicy.consumeConnectorResponse(
      response,
      state: state,
      context: researchContext(store: store, state: state, task: task, nowMillis: nowMillis),
      nowMillis: nowMillis
    )
    guard let step else { return false }
    stateStore.save(step.state)
    step.state.proactiveMessages.forEach { store.appendGlobalProactiveMessage($0) }
    return true
  }

  static func researchState() -> GlobalResearchExecutorState {
    GalaxySSIGlobalResearchRuntimeStore().state()
  }

  private static func seedResearchTasks(
    from cognitionTasks: [GlobalCognitionTask],
    into state: inout GlobalResearchExecutorState,
    nowMillis: Int64
  ) {
    for cognition in cognitionTasks where cognition.baselineUnderstanding.externalResearchUseful {
      let sourceEventId = cognition.sourceEvent.id
      guard !sourceEventId.isBlank,
            !state.tasks.contains(where: { $0.sourceEventId == sourceEventId && $0.status != .failed }) else {
        continue
      }
      let understanding = cognition.result
      let baseline = cognition.baselineUnderstanding
      let depth: GlobalResearchDepth = baseline.complexity >= 0.62 ? .deepResearch : .quickFact
      let topic = understanding.topic.ifBlank(baseline.topic).ifBlank(cognition.sourceEvent.conversationTitle)
      let question = cognition.sourceEvent.content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(understanding.topic)
      state.upsert(GlobalResearchTask(
        id: "ios-research:\(GlobalAgentText.stableKey(sourceEventId))",
        sourceEventId: sourceEventId,
        sourceConversationId: cognition.sourceEvent.conversationId,
        topic: topic,
        question: String(question.prefix(2_000)),
        depth: depth,
        preferredSources: ["official", "primary", "repository", "paper"],
        causalEventIds: cognition.sourceEvent.causalEventIds,
        status: .queued,
        monitorIntervalMillis: depth == .continuousMonitor ? GlobalResearchTaskPolicy.monitorIntervalMillis(0) : 0,
        createdAtMillis: cognition.createdAtMillis > 0 ? cognition.createdAtMillis : nowMillis,
        updatedAtMillis: cognition.updatedAtMillis > 0 ? cognition.updatedAtMillis : nowMillis
      ))
    }
  }

  private static func researchResources(
    from store: GalaxySSIStore,
    settings: GlobalAgentSettings
  ) -> [GlobalResearchExecutorResource] {
    let localRuntime = LocalModelCooperativeRuntime.shared
    let localProfile = localRuntime.displayProfile()
    let localResourceId = "phone-local-model"
    let localReady = localRuntime.readyForBackground()
    var resources: [GlobalResearchExecutorResource] = []
    let localDescriptor = backgroundResourceDescriptor(
      id: localResourceId,
      type: .onDeviceModel,
      location: .phone,
      status: localReady ? .available : .needsSetup,
      trust: .phoneSystem,
      supportsBackground: true
    )
    if GlobalBackgroundReasoningResourcePolicy.allowed(
      localDescriptor,
      allowPaired: settings.allowPairedAgentCognition,
      allowCloud: settings.allowCloudCognition,
      localModelReady: localReady
    ) {
      resources.append(GlobalResearchExecutorResource(
        id: localResourceId,
        transport: .onDeviceModel,
        capabilities: [.research, .reasoning, .chat, .localInference],
        displayName: localProfile.displayName
      ))
    }
    resources.append(contentsOf: store.visibleContacts.compactMap { contact in
      guard !contact.deleted else { return nil }
      switch contact.deliveryMode {
      case .cloudAPI:
        guard let model = contact.selectedCloudModel,
              AgentConnectorAvailability.cloudModelReady(
                model: model,
                apiKey: store.apiKey(for: model),
                provider: contact.cloudProvider,
                setupStatus: contact.setupStatus
              ),
              GlobalBackgroundReasoningResourcePolicy.allowed(
                backgroundResourceDescriptor(
                  id: contact.id,
                  type: .cloudModel,
                  location: .cloud,
                  status: .available,
                  trust: .cloudConfigured,
                  supportsBackground: true
                ),
                allowPaired: settings.allowPairedAgentCognition,
                allowCloud: settings.allowCloudCognition,
                localModelReady: localReady
              ) else { return nil }
        return GlobalResearchExecutorResource(
          id: contact.id,
          transport: .cloudModel,
          contactId: contact.id,
          capabilities: [.research, .reasoning, .liveData, .chat],
          displayName: model.displayName.ifBlank(contact.displayName)
        )
      case .link, .pcConnector:
        let setup = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard contact.trustState == .verified,
              contact.deliveryMode.isGalaxySSILinkFamily,
              setup == "ready" || setup == "verified",
              GlobalBackgroundReasoningResourcePolicy.allowed(
                backgroundResourceDescriptor(
                  id: contact.id,
                  type: .remoteAgent,
                  location: .trustedDesktop,
                  status: .available,
                  trust: .verifiedPaired,
                  supportsBackground: true
                ),
                allowPaired: settings.allowPairedAgentCognition,
                allowCloud: settings.allowCloudCognition,
                localModelReady: localReady
              ) else { return nil }
        return GlobalResearchExecutorResource(
          id: contact.id,
          transport: .pairedAgent,
          contactId: contact.id,
          capabilities: [.research, .reasoning, .liveData, .chat],
          displayName: contact.displayName.ifBlank(contact.name).ifBlank(contact.id)
        )
      case .local:
        return nil
      }
    })
    return resources
  }

  private static func backgroundResourceDescriptor(
    id: String,
    type: AgentResourceType,
    location: AgentResourceLocation,
    status: AgentConnectorStatus,
    trust: AgentResourceTrust,
    supportsBackground: Bool
  ) -> AgentResourceDescriptor {
    AgentResourceDescriptor(
      id: id,
      title: id,
      type: type,
      location: location,
      status: status,
      capabilities: [.reasoning],
      cost: .free,
      latency: .normal,
      quality: .standard,
      supportsTools: false,
      targetId: id,
      trust: trust,
      supportsBackground: supportsBackground
    )
  }

  private static func researchContext(
    store: GalaxySSIStore,
    state: GlobalResearchExecutorState,
    task: GlobalResearchTask?,
    nowMillis: Int64
  ) -> GlobalResearchExecutionContext {
    let conversationId = task?.sourceConversationId ?? ""
    let conversationContext = store.agentSessionMessages(conversationId)
      .filter { !$0.isSystem }
      .suffix(12)
      .map { message in
        let role = message.isMine ? "User" : "Agent"
        return "\(role): \(message.content)"
      }
      .joined(separator: "\n")
    let realtime = GlobalRealtimeContextProvider(
      researchTasksSource: { state.tasks }
    ).build(
      query: task?.question ?? "",
      currentConversationId: conversationId,
      maximumItems: 12,
      maximumCharacters: GlobalResearchExecutorLimits.maxContextCharacters,
      nowMillis: nowMillis
    )
    return GlobalResearchExecutionContext(
      conversationContext: String(conversationContext.prefix(GlobalResearchExecutorLimits.maxContextCharacters)),
      realtimeContext: realtime
    )
  }

  static func compiledConversationContext(
    store: GalaxySSIStore,
    query: String,
    conversationId: String,
    maximumCharacters: Int = 8_000,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> String {
    let core = store.agentCoreMemoryContext(maximumCharacters: 1_800)
    guard store.globalAgentSettings.enabled else {
      return String(core.prefix(maximumCharacters))
    }
    let sessions = store.agentSessions(includeArchived: true)
    let durable = GlobalMemoryPromptCompiler.compile(
      world: worldModel(from: store.agentMemorySnapshot(), nowMillis: nowMillis),
      topicGraph: topicGraph(from: sessions, nowMillis: nowMillis),
      entityGraph: GlobalEntityMemoryGraph(),
      query: query,
      currentConversationId: conversationId,
      maximumCharacters: 5_000,
      nowMillis: nowMillis
    )
    let excluded = Set(sessions.filter { $0.privateMode || $0.trackingPaused }.map(\.id))
    let realtime = GlobalRealtimeContextProvider().buildNonBlocking(
      query: query,
      currentConversationId: conversationId,
      excludedConversationIds: excluded,
      maximumItems: 10,
      maximumCharacters: 2_000,
      nowMillis: nowMillis
    )
    return String([core, durable, realtime]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n\n")
      .prefix(max(0, min(maximumCharacters, 12_000))))
  }

  private static func worldModel(
    from snapshot: AgentMemorySnapshot,
    nowMillis: Int64
  ) -> PersonalWorldModel {
    let items = snapshot.activeItems.compactMap { item -> GlobalWorldItem? in
      let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      let topic = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(item.kind.rawValue.lowercased())
      let conversationIds = item.scope == .conversation && !item.scopeId.isBlank
        ? Set([item.scopeId])
        : []
      let timestamp = max(item.timestampMillis, 0)
      return GlobalWorldItem(
        id: item.id,
        stableKey: GlobalAgentText.stableKey("ios-memory", item.kind.rawValue, topic, value),
        kind: worldKind(for: item.kind),
        layer: item.scope == .conversation ? .conversation : .user,
        namespace: worldNamespace(for: item.scope),
        namespaceId: item.scopeId,
        topic: topic,
        value: value,
        confidence: item.confidence,
        contextVisibility: item.scope == .conversation ? .localOnly : .shareable,
        evidenceCount: item.evidenceCount,
        conversationIds: conversationIds,
        evidenceEventIds: [item.id],
        evidenceProvenance: [GlobalEvidenceRef(
          eventId: item.id,
          conversationId: item.scopeId,
          timestampMillis: timestamp
        )],
        status: item.status == .conflicted ? .conflicted : .active,
        temporalState: .current,
        conflictGroupId: item.conflictGroupId,
        firstSeenAtMillis: timestamp,
        lastSeenAtMillis: max(item.lastAccessedAtMillis, timestamp),
        expiresAtMillis: item.expiresAtMillis
      )
    }
    return PersonalWorldModel(items: items, updatedAtMillis: max(nowMillis, 0))
  }

  private static func topicGraph(
    from conversations: [AgentConversation],
    nowMillis: Int64
  ) -> GlobalTopicProjectGraph {
    let nodes = conversations.compactMap { conversation -> GlobalTopicNode? in
      let topicKey = conversation.globalTopicKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !topicKey.isEmpty else { return nil }
      let timestamp = max(conversation.updatedAt, conversation.createdAt)
      return GlobalTopicNode(
        id: topicKey,
        stableKey: topicKey,
        name: conversation.title,
        kind: conversation.createdByAgent ? .project : .topic,
        status: conversation.status == .archived ? .archived : .active,
        conversationIds: [conversation.id],
        confidence: 0.85,
        firstSeenAtMillis: max(conversation.createdAt, 0),
        lastSeenAtMillis: max(timestamp, 0)
      )
    }
    return GlobalTopicProjectGraph(nodes: nodes, updatedAtMillis: max(nowMillis, 0))
  }

  private static func worldKind(for kind: AgentMemoryKind) -> GlobalWorldItemKind {
    switch kind {
    case .preference:
      return .preference
    case .task, .workflow:
      return .task
    case .identity, .contact, .knowledge, .safety:
      return .fact
    }
  }

  private static func worldNamespace(for scope: AgentMemoryScope) -> GlobalMemoryNamespace {
    switch scope {
    case .device:
      return .device
    case .workspace, .application:
      return .project
    case .contact, .conversation, .global:
      return .user
    }
  }
}

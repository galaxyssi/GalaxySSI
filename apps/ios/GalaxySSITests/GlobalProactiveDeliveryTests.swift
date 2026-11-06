import XCTest
@testable import GalaxySSI

final class GlobalProactiveDeliveryTests: XCTestCase {
  func testPublicAttentionDispatchExcludesPrivateContextAndUsesScopedRoute() throws {
    var settings = GlobalAgentSettings()
    var preferences = PublicAttentionPreferences()
    preferences.enabled = true
    preferences.allowPairedModel = true
    settings.publicAttention = preferences
    var state = GlobalResearchExecutorState()
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 100_000)
    let privateRoute = GlobalResearchExecutorResource(id: "private-model", transport: .cloudModel)
    let publicRoute = GlobalResearchExecutorResource(id: "paired-public", transport: .pairedAgent)
    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(state: state, resources: [privateRoute],
      publicAttentionResources: [publicRoute], context: .init(conversationContext: "PRIVATE_CHAT_MARKER",
        realtimeContext: "PRIVATE_REALTIME_MARKER", worldContext: "PRIVATE_MEMORY_MARKER"), nowMillis: 100_000))
    let request = try XCTUnwrap(step.state.dispatchRequests.first)
    XCTAssertEqual(step.state.dispatchRequests.count, 1)
    XCTAssertEqual(request.resourceId, publicRoute.id)
    XCTAssertTrue(request.conversationId.hasPrefix(PublicAttentionResearchPolicy.conversationPrefix))
    XCTAssertFalse(request.prompt.contains("PRIVATE_"))
    XCTAssertFalse(settings.allowPairedAgentCognition)
    XCTAssertTrue(PublicAttentionResearchPolicy.allows(request, settings: settings))
    var reply = AgentConnectorResponse(sourceMessageId: request.sourceMessageId, contactId: request.contactId,
      conversationId: request.conversationId, turnId: request.turnId, taskId: request.taskId)
    XCTAssertTrue(PublicAttentionResearchPolicy.matches(reply, request: request))
    reply.turnId = "different-turn"
    XCTAssertFalse(PublicAttentionResearchPolicy.matches(reply, request: request))
    settings.publicAttention?.allowPairedModel = false
    XCTAssertFalse(PublicAttentionResearchPolicy.allows(request, settings: settings))
  }

  func testPublicAttentionAcceptsOnlyExactOriginalExcerptsOnSupportedPublishers() throws {
    let quote = "This release includes a new API for running the task without connecting to a remote service."
    let data = try JSONSerialization.data(withJSONObject: ["items": [
      ["url": "https://github.blog/release", "quote": quote],
      ["url": "https://127.0.0.1/internal", "quote": quote],
      ["url": "https://github.blog/release", "quote": quote]
    ]])
    let candidates = PublicAttentionResearchPolicy.candidates(String(decoding: data, as: UTF8.self))
    XCTAssertEqual(candidates.count, 1)
    let candidate = try XCTUnwrap(candidates.first)
    let changed = PublicNewsOriginalBody(title: "Publisher", paragraphs: [quote + " Additional context."])
    let excerpt = try XCTUnwrap(PublicAttentionResearchPolicy.capturedExcerpt(candidate, in: changed))
    XCTAssertEqual(PublicAttentionResearchPolicy.sourceLinks(excerpt), [candidate.url])
    XCTAssertNil(PublicAttentionResearchPolicy.capturedExcerpt(candidate,
      in: PublicNewsOriginalBody(title: "Publisher", paragraphs: [quote.replacingOccurrences(of: "without", with: "by")])))
  }

  func testPublicAttentionAlertRespectsModeAndTopicOptIn() {
    var settings = GlobalAgentSettings()
    var preferences = PublicAttentionPreferences()
    preferences.enabled = true
    settings.publicAttention = preferences
    var finding = message(id: "finding")
    finding.sourceConversationId = "attention-research:macro"
    finding.status = .delivered
    finding.urgent = false
    XCTAssertFalse(PublicAttentionResearchPolicy.shouldAlert(finding, settings: settings))
    settings.publicAttention?.alertMode = .all
    XCTAssertTrue(PublicAttentionResearchPolicy.shouldAlert(finding, settings: settings))
    settings.publicAttention?.alertMode = .silent
    XCTAssertFalse(PublicAttentionResearchPolicy.shouldAlert(finding, settings: settings))
    settings.publicAttention?.alertMode = .all
    settings.publicAttention?.enabled = false
    XCTAssertFalse(PublicAttentionResearchPolicy.shouldAlert(finding, settings: settings))
  }

  func testAttentionCatalogAndPreferencesSurviveGlobalSettingsRoundTrip() throws {
    XCTAssertEqual(PublicAttentionCatalog.defaults.count, 31)
    XCTAssertEqual(Set(PublicAttentionCatalog.defaults.map(\.id)).count, 31)
    XCTAssertEqual(PublicAttentionCatalog.defaults.filter { $0.group == .finance }.count, 15)
    var preferences = PublicAttentionPreferences()
    let definition = try XCTUnwrap(PublicAttentionCatalog.defaults.first)
    var edited = definition
    edited.enabled = false
    edited.scope = "Central bank publications only"
    preferences.setTopic(edited, relativeTo: definition)
    let custom = PublicAttentionCatalog.Topic(id: UUID().uuidString, group: .custom, title: "Custom", scope: "Public releases")
    preferences.setTopic(custom, relativeTo: nil)
    preferences.toggleSaved("finding", retaining: ["finding"])
    let settings = GlobalAgentSettings(publicAttention: preferences).normalized
    let roundTrip = try JSONDecoder().decode(GlobalAgentSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(roundTrip.publicAttention, preferences)
    XCTAssertEqual(roundTrip.publicAttention?.catalog.count, 32)
    XCTAssertEqual(roundTrip.publicAttention?.topics[definition.id]?.scope, edited.scope)
    XCTAssertEqual(roundTrip.publicAttention?.topics[definition.id]?.enabled, false)
    XCTAssertEqual(roundTrip.publicAttention?.savedKeys, ["finding"])
    XCTAssertNil(try JSONDecoder().decode(GlobalAgentSettings.self, from: Data("{}".utf8)).publicAttention)
  }

  func testPublicAttentionTaskLifecycleLeavesUnrelatedResearchAlone() throws {
    var state = GlobalResearchExecutorState()
    let privateTask = GlobalResearchTask(id: "private", sourceEventId: "private-event",
      sourceConversationId: "private-chat", topic: "Private topic", question: "Private context",
      depth: .quickFact, preferredSources: [], createdAtMillis: 1, updatedAtMillis: 1)
    state.upsert(privateTask)
    var settings = GlobalAgentSettings()
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 2)
    XCTAssertEqual(state.tasks, [privateTask])
    var preferences = PublicAttentionPreferences()
    preferences.enabled = true
    settings.publicAttention = preferences
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 3)
    XCTAssertEqual(state.tasks.count, 32)

    var tracked = try XCTUnwrap(state.task(id: "attention-research:macro"))
    tracked.status = .running
    tracked.result = "Previously observed public announcement"
    tracked.lastResultFingerprint = "baseline"
    state.upsert(tracked)
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 4)
    XCTAssertEqual(state.task(id: tracked.id), tracked)

    let topic = try XCTUnwrap(PublicAttentionCatalog.defaults.first)
    preferences.setEnabled(false, topic: topic)
    settings.publicAttention = preferences
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 5)
    XCTAssertEqual(state.task(id: tracked.id)?.status, .paused)
    XCTAssertEqual(state.task(id: tracked.id)?.result, tracked.result)
    preferences.setEnabled(true, topic: topic)
    settings.publicAttention = preferences
    PublicAttentionResearchPolicy.reconcile(&state, settings: settings, nowMillis: 6)
    XCTAssertEqual(state.task(id: tracked.id)?.status, .queued)
    XCTAssertEqual(state.task(id: tracked.id)?.lastResultFingerprint, tracked.lastResultFingerprint)
    XCTAssertEqual(state.task(id: privateTask.id), privateTask)
  }

  func testDeliveryWakeKeepsOneSuccessorWhenResultsArriveDuringDelivery() {
    var state = GlobalProactiveDeliveryWake.State()
    XCTAssertTrue(state.request())
    XCTAssertFalse(state.request())
    state.begin()
    XCTAssertFalse(state.request())
    XCTAssertFalse(state.request())
    XCTAssertTrue(state.end())
    state.begin()
    XCTAssertFalse(state.end())
    XCTAssertTrue(state.request())
  }

  @MainActor
  func testBatchPublicationDoesNotRewriteOrWakeForDeliveredReplays() throws {
    let suite = "proactive-replay-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let original = message(id: "committed")
    var delivered = original
    delivered.status = .delivered
    var wakes = 0
    let listener = GlobalProactiveDeliveryListener { wakes += 1 }
    GlobalProactiveDeliveryBus.addListener(listener)
    defer { GlobalProactiveDeliveryBus.removeListener(listener) }
    XCTAssertEqual(store.appendGlobalProactiveMessages([delivered, original]).count, 1)
    XCTAssertEqual(wakes, 1)
    XCTAssertTrue(store.appendGlobalProactiveMessages([original]).isEmpty)
    XCTAssertTrue(store.appendGlobalProactiveMessages([]).isEmpty)
    XCTAssertEqual(store.appendGlobalProactiveMessage(original).status, .delivered)
    XCTAssertEqual(wakes, 1)
  }

  func testNewsEligibilityDoesNotEnableOrUnpauseLearning() {
    let news = message(id: "attention-feed:news-1")
    let insight = message(id: "world-model:insight")
    var settings = GlobalAgentSettings(enabled: false, proactiveInsightsEnabled: false)
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.allowsInboxDelivery(news, settings: settings))
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.allowsNotification(news, settings: settings))
    XCTAssertFalse(GlobalProactiveDeliveryPolicy.allowsInboxDelivery(insight, settings: settings))
    XCTAssertFalse(GlobalProactiveDeliveryPolicy.allowsNotification(insight, settings: settings))
    settings.notificationsEnabled = false
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.allowsInboxDelivery(news, settings: settings))
    XCTAssertFalse(GlobalProactiveDeliveryPolicy.allowsNotification(news, settings: settings))
    XCTAssertFalse(settings.enabled)
  }

  @MainActor
  func testPausedStoreRetainsInsightsAndDeliversOnlyNewsAcrossReload() throws {
    let suite = "paused-learning-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let conversation = store.createAgentSession(title: "News and insights")
    var news = message(id: "attention-feed:news-1")
    var insight = message(id: "world-model:insight")
    news.sourceConversationId = conversation.id
    insight.sourceConversationId = conversation.id
    news.urgent = true
    insight.urgent = true
    store.updateGlobalAgentSettings { $0.enabled = false }
    store.appendGlobalProactiveMessage(news)
    store.appendGlobalProactiveMessage(insight)
    XCTAssertTrue(store.save())

    let reopened = GalaxySSIStore(defaults: defaults, secrets: secrets)
    XCTAssertFalse(reopened.globalAgentSettings.enabled)
    XCTAssertNotNil(reopened.agentSession(id: conversation.id))
    XCTAssertEqual(reopened.deliverPendingGlobalProactiveMessages().map(\.id), [news.id])
    XCTAssertEqual(reopened.globalProactiveMessages.first { $0.id == insight.id }?.status, .pending)
    XCTAssertEqual(reopened.globalProactiveMessages.first { $0.id == news.id }?.status, .delivered)
    XCTAssertTrue(reopened.deliverPendingGlobalProactiveMessages().isEmpty)
    XCTAssertTrue(GalaxySSIGlobalAgentRuntimeBridge.processResearchCycle(store: reopened).dispatchRequests.isEmpty)
    XCTAssertEqual(GalaxySSIGlobalAgentRuntimeBridge.processLongHorizonCycle(store: reopened).reconciledGoalCount, 0)
    XCTAssertFalse(reopened.globalAgentSettings.enabled)
  }

  func testForegroundDeliverySignalCanBeSubscribedAndRemoved() {
    var calls = 0
    let listener = GlobalProactiveDeliveryListener {
      calls += 1
    }

    GlobalProactiveDeliveryBus.addListener(listener)
    GlobalProactiveDeliveryBus.signalReady()
    GlobalProactiveDeliveryBus.removeListener(listener)
    GlobalProactiveDeliveryBus.signalReady()

    XCTAssertEqual(calls, 1)
  }

  func testCurrentConversationDeliveryUsesItsEligibleSource() {
    let source = conversation(id: "source", title: "Current work")

    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .currentConversation),
      conversations: [source],
      autoCreateConversationsEnabled: true
    )

    XCTAssertEqual(route?.kind, .source)
    XCTAssertEqual(route?.conversationId, source.id)
    XCTAssertEqual(route?.bindTopic, false)
  }

  func testRenamedAgentWorkspaceIsReusedThroughStableTopicOwnership() {
    let topicKey = GlobalProactiveConversationRouter.topicKey(topic)
    let renamed = conversation(
      id: "topic-workspace",
      title: "A user-selected title",
      createdByAgent: true,
      globalTopicKey: topicKey
    )

    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [renamed],
      autoCreateConversationsEnabled: true
    )

    XCTAssertEqual(route?.kind, .boundTopic)
    XCTAssertEqual(route?.conversationId, renamed.id)
    XCTAssertEqual(route?.createConversation, false)
  }

  func testStrongestGraphWorkspaceWinsBeforeMostRecentlyUpdatedWorkspace() {
    let strongest = conversation(id: "strongest", title: "Primary project", updatedAt: 10)
    let newest = conversation(id: "newest", title: "Secondary project", updatedAt: 100)

    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [newest, strongest],
      relatedConversationIds: [strongest.id, newest.id],
      autoCreateConversationsEnabled: true
    )

    XCTAssertEqual(route?.kind, .relatedTopic)
    XCTAssertEqual(route?.conversationId, strongest.id)
    XCTAssertEqual(route?.bindTopic, true)
  }

  func testPrivateOrPausedSourceCannotLeakIntoAnotherWorkspace() {
    let privateSource = conversation(id: "source", title: "Private", privateMode: true)
    let publicTopic = conversation(id: "topic", title: topic, createdByAgent: true)

    let privateRoute = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [privateSource, publicTopic],
      autoCreateConversationsEnabled: true
    )
    let pausedSource = conversation(id: "source", title: "Paused", trackingPaused: true)
    let pausedRoute = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [pausedSource, publicTopic],
      autoCreateConversationsEnabled: true
    )

    XCTAssertNil(privateRoute)
    XCTAssertNil(pausedRoute)
  }

  func testDeletedExternalSourceCannotRecreateItsTopicWorkspace() {
    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [],
      autoCreateConversationsEnabled: true,
      excludedConversationIds: ["source"]
    )

    XCTAssertNil(route)
  }

  func testUnmatchedDurableTopicCreatesOneOwnedChildWorkspace() {
    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [conversation(id: "source", title: "Current work")],
      autoCreateConversationsEnabled: true
    )

    XCTAssertEqual(route?.kind, .createTopic)
    XCTAssertEqual(route?.createConversation, true)
    XCTAssertEqual(route?.parentConversationId, "source")
    XCTAssertEqual(route?.topicKey, GlobalProactiveConversationRouter.topicKey(topic))
  }

  func testAgentCreatedTopicProducesOneSourceWorkspaceNoticeContract() {
    let destination = conversation(
      id: "topic-workspace",
      title: "Runtime reliability",
      createdByAgent: true,
      parentConversationId: "source"
    )

    let notice = GlobalProactiveTopicNoticePolicy.create(
      message: message(target: .newConversation),
      destination: destination
    )

    XCTAssertEqual(notice?.parentConversationId, "source")
    XCTAssertEqual(notice?.destinationConversationId, "topic-workspace")
    XCTAssertEqual(notice?.dedupeKey, "global-agent-topic-created:topic-workspace")
    XCTAssertEqual(notice?.actionLabel, "Open topic")
    XCTAssertTrue(notice?.text.contains("Runtime reliability") == true)
  }

  func testSourceNoticeCannotBeCreatedForUserOwnedOrUnrelatedWorkspace() {
    let userOwned = conversation(id: "user-topic", title: "User topic")
    let unrelated = conversation(
      id: "agent-topic",
      title: "Agent topic",
      createdByAgent: true,
      parentConversationId: "different-source"
    )

    XCTAssertNil(GlobalProactiveTopicNoticePolicy.create(
      message: message(target: .newConversation),
      destination: userOwned
    ))
    XCTAssertNil(GlobalProactiveTopicNoticePolicy.create(
      message: message(target: .newConversation),
      destination: unrelated
    ))
  }

  func testDisabledAutoCreationFallsBackToEligibleSource() {
    let source = conversation(id: "source", title: "Current work")

    let route = GlobalProactiveConversationRouter.resolve(
      message: message(target: .newConversation),
      conversations: [source],
      autoCreateConversationsEnabled: false
    )

    XCTAssertEqual(route?.kind, .sourceFallback)
    XCTAssertEqual(route?.conversationId, source.id)
  }

  func testExternalConversationFallsBackToMostRecentWorkspaceWhenCreationIsDisabled() {
    let older = conversation(id: "older", title: "Older workspace", updatedAt: 10)
    let recent = conversation(id: "recent", title: "Recent workspace", updatedAt: 20)
    var external = message(target: .currentConversation)
    external.sourceConversationId = "contact:external"

    let route = GlobalProactiveConversationRouter.resolve(
      message: external,
      conversations: [older, recent],
      autoCreateConversationsEnabled: false
    )

    XCTAssertEqual(route?.kind, .sourceFallback)
    XCTAssertEqual(route?.conversationId, recent.id)
  }

  private func message(
    id: String = "message",
    target: GlobalProactiveTarget = .currentConversation
  ) -> GlobalProactiveMessage {
    GlobalProactiveMessage(
      id: id,
      sourceEventId: "event",
      sourceConversationId: "source",
      target: target,
      title: "GalaxySSI insight",
      content: "A material result is ready.",
      topic: topic,
      urgent: false,
      createdAtMillis: 1
    )
  }

  private func conversation(
    id: String,
    title: String,
    updatedAt: Int64 = 1,
    privateMode: Bool = false,
    trackingPaused: Bool = false,
    createdByAgent: Bool = false,
    globalTopicKey: String = "",
    parentConversationId: String = ""
  ) -> AgentConversation {
    AgentConversation(
      id: id,
      title: title,
      createdAt: 1,
      updatedAt: updatedAt,
      privateMode: privateMode,
      createdByAgent: createdByAgent,
      parentConversationId: parentConversationId,
      trackingPaused: trackingPaused,
      globalTopicKey: globalTopicKey
    )
  }

  private let topic = "GalaxySSI global autonomy"
}

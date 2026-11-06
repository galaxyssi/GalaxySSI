import XCTest
@testable import GalaxySSI

final class GlobalProactiveDeliveryTests: XCTestCase {
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

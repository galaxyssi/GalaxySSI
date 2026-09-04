import XCTest
@testable import GalaxySSI

final class GlobalProactiveDeliveryPolicyTests: XCTestCase {
  func testDeliveryLeaseOnlyRecoversAfterExpiry() {
    let now: Int64 = 10_000
    var fresh = message()
    fresh.status = .delivering
    fresh.deliveryLeaseExpiresAtMillis = now + 1_000
    var stale = fresh
    stale.deliveryLeaseExpiresAtMillis = now

    XCTAssertFalse(GlobalProactiveDeliveryPolicy.isRecoverable(fresh, nowMillis: now))
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.isRecoverable(stale, nowMillis: now))
  }

  func testBudgetAndTopicCooldownAreRecheckedAtDeliveryTime() {
    let now = 2 * dayMillis
    let settings = GlobalAgentSettings(dailyMessageBudget: 2, topicCooldownMillis: 6 * hourMillis)
    let profile = GlobalAgentAdaptiveProfile()
    let budgetFull = GlobalInterventionHistory(
      notificationTimestamps: [now - 100, now - 200]
    )
    let topicCoolingDown = GlobalInterventionHistory(
      notificationTimestamps: [now - dayMillis],
      lastTopicNotificationMillis: [GlobalAgentText.normalize(topic): now - hourMillis]
    )
    var urgent = message()
    urgent.urgent = true
    var counted = message()
    counted.deliveryBudgetCounted = true

    XCTAssertFalse(GlobalProactiveDeliveryPolicy.canDeliver(
      message: message(),
      settings: settings,
      profile: profile,
      history: budgetFull,
      nowMillis: now
    ))
    XCTAssertFalse(GlobalProactiveDeliveryPolicy.canDeliver(
      message: message(),
      settings: settings,
      profile: profile,
      history: topicCoolingDown,
      nowMillis: now
    ))
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.canDeliver(
      message: urgent,
      settings: settings,
      profile: profile,
      history: budgetFull,
      nowMillis: now
    ))
    XCTAssertTrue(GlobalProactiveDeliveryPolicy.canDeliver(
      message: counted,
      settings: settings,
      profile: profile,
      history: budgetFull,
      nowMillis: now
    ))
  }

  func testDigestSelectionDeliversOneBoundedBatchAndLeavesOverflowForLater() {
    let now = 100 * hourMillis
    let messages = (1...7).map { index -> GlobalProactiveMessage in
      var item = message(id: "message-\(index)", target: .globalDigest)
      item.createdAtMillis = now - hourMillis + Int64(index)
      return item
    }

    let selected = GlobalProactiveDeliveryPolicy.digestBatch(
      messages: messages,
      settings: GlobalAgentSettings(dailyMessageBudget: 4),
      profile: GlobalAgentAdaptiveProfile(),
      history: GlobalInterventionHistory(),
      nowMillis: now,
      minimumItems: 3,
      maximumItems: 4,
      maximumWaitMillis: 12 * hourMillis
    )

    XCTAssertEqual(selected.map(\.id), ["message-1", "message-2", "message-3", "message-4"])
    XCTAssertNotEqual(Set(messages.map(\.id)), Set(selected.map(\.id)))
  }

  func testAdaptiveProfileAdjustsBudgetAndCooldown() {
    let now = 40 * dayMillis
    let feedback = [
      feedback(kind: .tooFrequent, topic: topic, createdAtMillis: now - 1_000),
      feedback(kind: .tooFrequent, topic: topic, createdAtMillis: now - 2_000),
      feedback(kind: .notRelevant, topic: topic, createdAtMillis: now - 3_000)
    ]
    let profile = GlobalAgentLearningPolicy.profile(feedback: feedback, nowMillis: now)

    XCTAssertLessThan(GlobalAgentLearningPolicy.dailyMessageBudget(
      settings: GlobalAgentSettings(dailyMessageBudget: 4),
      profile: profile
    ), 4)
    XCTAssertGreaterThan(GlobalAgentLearningPolicy.topicCooldownMillis(
      settings: GlobalAgentSettings(topicCooldownMillis: hourMillis),
      profile: profile,
      topic: topic
    ), hourMillis)
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

  private func feedback(
    kind: GlobalAgentFeedbackKind,
    topic: String,
    createdAtMillis: Int64
  ) -> GlobalAgentFeedback {
    GlobalAgentFeedback(
      proactiveMessageId: "message-\(createdAtMillis)",
      deliveryGroupId: "",
      conversationId: "conversation",
      topic: topic,
      target: .currentConversation,
      kind: kind,
      createdAtMillis: createdAtMillis
    )
  }

  private let topic = "GalaxySSI global autonomy"
  private let hourMillis: Int64 = 60 * 60 * 1_000
  private var dayMillis: Int64 { 24 * hourMillis }
}

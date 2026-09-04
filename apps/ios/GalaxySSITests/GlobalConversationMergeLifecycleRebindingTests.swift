import XCTest
@testable import GalaxySSI

final class GlobalConversationMergeLifecycleRebindingTests: XCTestCase {
  func testRebindsWorldAndTopicGraphWithoutCreatingNewEvidence() {
    let merge = mergeEvent()
    let childEvidence = GlobalEvidenceRef(eventId: "evidence-child", conversationId: "child")
    let parentEvidence = GlobalEvidenceRef(eventId: "evidence-parent", conversationId: "parent")
    let world = PersonalWorldModel(
      items: [
        GlobalWorldItem(
          stableKey: "item",
          kind: .goal,
          layer: .topic,
          topic: "Runtime",
          value: "Finish the runtime",
          confidence: 0.9,
          conversationIds: ["child", "other"],
          evidenceProvenance: [childEvidence]
        )
      ],
      links: [
        GlobalConversationLink(
          id: "self-after-merge",
          leftConversationId: "child",
          rightConversationId: "parent",
          topic: "Runtime",
          strength: 0.8,
          evidenceProvenance: [childEvidence],
          lastSeenAtMillis: 1_000
        ),
        GlobalConversationLink(
          id: "child-other",
          leftConversationId: "child",
          rightConversationId: "other",
          topic: "Runtime",
          strength: 0.7,
          evidenceProvenance: [childEvidence],
          lastSeenAtMillis: 1_200
        ),
        GlobalConversationLink(
          id: "parent-other",
          leftConversationId: "parent",
          rightConversationId: "other",
          topic: "runtime",
          strength: 0.4,
          evidenceProvenance: [parentEvidence],
          lastSeenAtMillis: 1_400
        )
      ],
      processedEventIds: ["older"],
      updatedAtMillis: 900
    )
    let graph = GlobalTopicProjectGraph(
      nodes: [
        GlobalTopicNode(
          stableKey: "runtime",
          name: "Runtime",
          conversationIds: ["child"],
          evidenceProvenance: [childEvidence]
        )
      ],
      updatedAtMillis: 800
    )

    let reboundWorld = GlobalConversationMergeLifecycle.rebindWorld(world, event: merge)
    let reboundGraph = GlobalConversationMergeLifecycle.rebindTopicGraph(graph, event: merge)

    XCTAssertEqual(reboundWorld.items.single.conversationIds, ["parent", "other"])
    XCTAssertEqual(reboundWorld.items.single.evidenceProvenance.single.conversationId, "parent")
    XCTAssertEqual(reboundWorld.updatedAtMillis, 1_500)
    XCTAssertEqual(reboundWorld.processedEventIds, ["older", "merge"])
    XCTAssertEqual(reboundWorld.links.count, 1)
    XCTAssertEqual(reboundWorld.links.single.leftConversationId, "parent")
    XCTAssertEqual(reboundWorld.links.single.rightConversationId, "other")
    XCTAssertEqual(reboundWorld.links.single.id, "parent-other")
    XCTAssertEqual(reboundWorld.links.single.strength, 0.7)
    XCTAssertEqual(Set(reboundWorld.links.single.evidenceProvenance.map(\.eventId)), ["evidence-child", "evidence-parent"])
    XCTAssertFalse(reboundWorld.links.contains { $0.leftConversationId == "child" || $0.rightConversationId == "child" })

    XCTAssertEqual(reboundGraph.nodes.single.conversationIds, ["parent"])
    XCTAssertEqual(reboundGraph.nodes.single.evidenceProvenance.single.conversationId, "parent")
    XCTAssertEqual(reboundGraph.updatedAtMillis, 1_500)
  }

  func testRebindsActiveGlobalWorkToTargetConversation() {
    let merge = mergeEvent()
    let source = GlobalConversationEvent(
      id: "source-event",
      type: .messageCreated,
      conversationId: "child",
      actor: .user,
      timestampMillis: 1_000,
      content: "Continue the runtime"
    )
    let research = GlobalResearchTask(
      id: "research",
      sourceEventId: "source-event",
      sourceConversationId: "child",
      topic: "Runtime",
      question: "Check it",
      depth: .quickFact,
      preferredSources: [],
      updatedAtMillis: 1_000
    )
    let cognition = GlobalCognitionTask(
      id: "cognition",
      sourceEvent: source,
      baselineUnderstanding: GlobalUnderstanding(topic: "Runtime"),
      updatedAtMillis: 1_000
    )
    let run = GlobalAutonomousRun(
      id: "run",
      sourceCognitionTaskId: "cognition",
      sourceEventId: "source-event",
      sourceConversationId: "child",
      topic: "Runtime",
      goal: "Finish",
      actions: [],
      updatedAtMillis: 1_000
    )
    let message = GlobalProactiveMessage(
      id: "message",
      sourceEventId: "source-event",
      sourceConversationId: "child",
      target: .currentConversation,
      title: "Update",
      content: "Ready",
      topic: "Runtime",
      urgent: false,
      deliveryConversationId: "child",
      deliveredConversationId: "child"
    )
    let goal = GlobalLongHorizonGoal(
      id: "goal",
      stableKey: "goal",
      topic: "Runtime",
      title: "Finish",
      sourceConversationIds: ["child", "other"],
      updatedAtMillis: 1_000
    )

    let reboundResearch = GlobalConversationMergeLifecycle.rebindResearchTasks([research], event: merge).single
    let reboundCognition = GlobalConversationMergeLifecycle.rebindCognitionTasks([cognition], event: merge).single
    let reboundRun = GlobalConversationMergeLifecycle.rebindAutonomousRuns([run], event: merge).single
    let reboundMessage = GlobalConversationMergeLifecycle.rebindProactiveMessages([message], event: merge).single
    let reboundGoal = GlobalConversationMergeLifecycle.rebindLongHorizonGoals([goal], event: merge).single

    XCTAssertEqual(reboundResearch.sourceConversationId, "parent")
    XCTAssertEqual(reboundResearch.updatedAtMillis, 1_500)
    XCTAssertEqual(reboundCognition.sourceEvent.conversationId, "parent")
    XCTAssertEqual(reboundCognition.sourceEvent.metadata["merged_from_conversation_id"], "child")
    XCTAssertEqual(reboundCognition.updatedAtMillis, 1_500)
    XCTAssertEqual(reboundRun.sourceConversationId, "parent")
    XCTAssertEqual(reboundRun.updatedAtMillis, 1_500)
    XCTAssertEqual(reboundMessage.sourceConversationId, "parent")
    XCTAssertEqual(reboundMessage.deliveryConversationId, "parent")
    XCTAssertEqual(reboundMessage.deliveredConversationId, "parent")
    XCTAssertEqual(reboundGoal.sourceConversationIds, ["parent", "other"])
    XCTAssertEqual(reboundGoal.updatedAtMillis, 1_500)
  }

  func testInvalidMergeLeavesWorldAndWorkUnchanged() {
    let invalid = GlobalConversationEvent(
      id: "not-merge",
      type: .messageCreated,
      conversationId: "parent",
      actor: .system,
      timestampMillis: 1_500,
      metadata: [
        GlobalConversationMergeLifecycle.sourceConversationIdKey: "child",
        GlobalConversationMergeLifecycle.targetConversationIdKey: "parent"
      ]
    )
    let world = PersonalWorldModel(
      items: [
        GlobalWorldItem(
          stableKey: "item",
          kind: .fact,
          layer: .conversation,
          topic: "Runtime",
          value: "A fact",
          confidence: 0.8,
          conversationIds: ["child"]
        )
      ]
    )
    let goal = GlobalLongHorizonGoal(
      stableKey: "goal",
      topic: "Runtime",
      title: "Finish",
      sourceConversationIds: ["child"]
    )

    XCTAssertEqual(GlobalConversationMergeLifecycle.rebindWorld(world, event: invalid), world)
    XCTAssertEqual(GlobalConversationMergeLifecycle.rebindLongHorizonGoals([goal], event: invalid), [goal])
  }

  private func mergeEvent() -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: "merge",
      type: .conversationMerged,
      conversationId: "parent",
      actor: .system,
      timestampMillis: 1_500,
      metadata: [
        GlobalConversationMergeLifecycle.sourceConversationIdKey: "child",
        GlobalConversationMergeLifecycle.targetConversationIdKey: "parent"
      ]
    )
  }
}

private extension Array {
  var single: Element {
    XCTAssertEqual(count, 1)
    return self[0]
  }
}

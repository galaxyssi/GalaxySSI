import Foundation
import XCTest
@testable import GalaxySSI

final class GlobalBackgroundCognitionScopeTests: XCTestCase {
  func testPrimaryAndMetadataSourcesMustAllRemainEligible() {
    var task = task()
    task.sourceEvent.metadata["source_conversation_ids"] = " a, b ,, "
    XCTAssertTrue(scope([session("a"), session("b")]).allowsSource(task))
    XCTAssertFalse(scope([session("a"), session("b", privateMode: true)]).allowsSource(task))
    XCTAssertFalse(scope([session("a"), session("b", trackingPaused: true)]).allowsSource(task))
    XCTAssertFalse(scope([session("a")]).allowsSource(task))
  }

  func testPrivateSensitivityInvalidatedEvidenceAndDisabledFeatureAreDenied() {
    var task = task()
    let allowed = scope([session("a")])
    task.sourceEvent.sensitivity = .sessionPrivate
    XCTAssertFalse(allowed.allowsSource(task))
    task.sourceEvent.sensitivity = .personal
    task.lastError = GlobalAgentEvidenceLifecyclePolicy.invalidatedReason
    XCTAssertFalse(allowed.allowsSource(task))
    task.lastError = ""
    XCTAssertFalse(GlobalBackgroundCognitionScope(enabled: false, conversations: [session("a")]).allowsSource(task))
  }

  func testLegacyRunningTasksWithoutProvenanceOrTransportAreNotInferredAuthorized() {
    let allowed = scope([session("a")])
    var legacy = task()
    legacy.contextConversationIds = nil
    XCTAssertTrue(allowed.allowsSource(legacy))
    XCTAssertFalse(allowed.allowsRunning(legacy))
    legacy.contextConversationIds = []
    legacy.resourceTransport = nil
    XCTAssertFalse(allowed.allowsRunning(legacy))
  }

  func testARevokedContextSourceBlocksCompletionEvenWhenPrimarySourceStaysPublic() {
    var task = task()
    task.contextConversationIds = ["a", "context"]
    XCTAssertTrue(scope([session("a"), session("context")]).allowsRunning(task))
    XCTAssertFalse(scope([session("a"), session("context", privateMode: true)]).allowsRunning(task))
    XCTAssertFalse(scope([session("a"), session("context", trackingPaused: true)]).allowsRunning(task))
    XCTAssertFalse(scope([session("a")]).allowsRunning(task))
  }

  func testUnrelatedNewConversationDoesNotInvalidateSelectedContextProvenance() {
    let task = task()
    XCTAssertTrue(scope([session("a")]).allowsRunning(task))
    XCTAssertTrue(scope([session("a"), session("unrelated")]).allowsRunning(task))
  }

  func testSyntheticGoalIdentityNeedsMatchingHostGoalAndCompleteSourceMetadata() {
    var global = task()
    global.longHorizonGoalId = "goal"
    global.sourceEvent.conversationId = "global-goal:goal"
    global.sourceEvent.metadata = ["long_horizon_goal_id": "goal", "origin": "global_long_horizon_scheduler"]
    let allowed = scope([session("a")])
    XCTAssertFalse(allowed.allowsSource(global))
    global.sourceEvent.metadata["source_conversation_ids"] = ""
    XCTAssertTrue(allowed.allowsSource(global))
    global.sourceEvent.metadata["origin"] = "other"
    XCTAssertFalse(allowed.allowsSource(global))
    global.sourceEvent.metadata["origin"] = "global_long_horizon_scheduler"
    global.sourceEvent.metadata["long_horizon_goal_id"] = "different"
    XCTAssertFalse(allowed.allowsSource(global))
  }

  func testLongHorizonMixedSourcesCannotLoseTheirPrivateMember() {
    var shared = task()
    shared.longHorizonGoalId = "goal"
    shared.sourceEvent.metadata = ["long_horizon_goal_id": "goal", "source_conversation_ids": "a,b",
      "origin": "global_long_horizon_scheduler"]
    XCTAssertTrue(scope([session("a"), session("b")]).allowsSource(shared))
    XCTAssertFalse(scope([session("a"), session("b", privateMode: true)]).allowsSource(shared))
    shared.sourceEvent.metadata.removeValue(forKey: "source_conversation_ids")
    XCTAssertFalse(scope([session("a"), session("b")]).allowsSource(shared))
  }

  func testRequestMustMatchTaskAttemptResourceTransportAndAllHostScopeFields() {
    let task = task(), allowed = scope([session("a")])
    let original = request(task)
    XCTAssertTrue(allowed.accepts(task, request: original))
    for variant in 0..<7 {
      var invalid = original
      switch variant {
      case 0: invalid.sourceMessageId += 1
      case 1: invalid.resourceId = "other"
      case 2: invalid.transport = .cloudModel
      case 3: invalid.taskId = "other"
      case 4: invalid.conversationId = "other"
      case 5: invalid.turnId = "other"
      default: invalid.contactId = "other"
      }
      XCTAssertFalse(allowed.accepts(task, request: invalid))
    }
  }

  func testResponseRequiresPositiveCorrelationAndResourceWithOptionalLegacyContainment() {
    let task = task(), allowed = scope([session("a")])
    let original = response(task)
    XCTAssertTrue(allowed.accepts(task, response: original))
    for variant in 0..<6 {
      var invalid = original
      switch variant {
      case 0: invalid.sourceMessageId = 0
      case 1: invalid.sourceMessageId += 1
      case 2: invalid.contactId = "other"
      case 3: invalid.conversationId = "other"
      case 4: invalid.turnId = "other"
      default: invalid.taskId = "other"
      }
      XCTAssertFalse(allowed.accepts(task, response: invalid))
    }
    var legacy = original
    legacy.conversationId = ""; legacy.turnId = ""; legacy.taskId = ""
    XCTAssertTrue(allowed.accepts(task, response: legacy))
  }

  func testOptionalProvenanceRoundTripsAndLegacyJSONRemainsReadableButUntrusted() throws {
    let original = task()
    let encoded = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode(GlobalCognitionTask.self, from: encoded), original)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "contextConversationIds")
    object.removeValue(forKey: "resourceTransport")
    let legacy = try JSONDecoder().decode(GlobalCognitionTask.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.contextConversationIds)
    XCTAssertNil(legacy.resourceTransport)
    XCTAssertTrue(scope([session("a")]).allowsSource(legacy))
    XCTAssertFalse(scope([session("a")]).allowsRunning(legacy))
  }

  func testQueueClaimSkipsIneligibleHigherPriorityTaskWithoutConsumingItsAttempt() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = GlobalAgentDeliberationStore(fileURL: file)
    var blocked = task("blocked")
    blocked.status = .queued; blocked.sourceMessageId = 0
    blocked.sourceEvent.conversationId = "private"
    blocked.baselineUnderstanding.urgency = 1
    var ready = task("ready")
    ready.status = .queued; ready.sourceMessageId = 0
    ready.baselineUnderstanding.urgency = 0
    store.upsertCognitionTask(blocked); store.upsertCognitionTask(ready)
    let allowed = scope([session("a"), session("private", privateMode: true)])
    let claimed = store.claimCognitionTask(nowMillis: 1_000, eligible: allowed.allowsSource)
    XCTAssertEqual(claimed?.id, "ready")
    XCTAssertEqual(claimed?.attemptCount, ready.attemptCount + 1)
    XCTAssertEqual(store.cognitionTasks().first { $0.id == "blocked" }?.attemptCount, blocked.attemptCount)
  }

  func testProjectionCapturesSelectedSourcesNotEveryKnownConversation() {
    let provider = GlobalRealtimeContextProvider(cognitionTasksSource: { [] }, researchTasksSource: { [] },
      autonomousRunsSource: { [] }, longHorizonGoalsSource: {
        [self.goal("Primary goal", ["a"]), self.goal("Other goal", ["b"]), self.goal("Mixed private goal", ["a", "private"])]
      }, continuitySource: { nil })
    let projected = provider.buildProjection(query: "Show all tasks and current status", currentConversationId: "a",
      excludedConversationIds: ["private"], allowedConversationIds: ["a", "b", "unrelated"],
      maximumItems: 1, nowMillis: 1_000)
    XCTAssertTrue(projected.text.contains("Primary goal"))
    XCTAssertFalse(projected.text.contains("Mixed private goal"))
    XCTAssertEqual(projected.conversationIds, ["a"])
  }

  func testExpectedTaskUpdateRejectsAnObservedInterveningChange() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let store = GlobalAgentDeliberationStore(fileURL: file)
    let original = task()
    store.upsertCognitionTask(original)
    var changed = original
    changed.lastError = "Another task update"
    store.upsertCognitionTask(changed)
    XCTAssertNil(store.updateCognitionTask(taskId: original.id, expected: original) { current in
      var next = current; next.status = .completed; return next
    })
    XCTAssertEqual(store.cognitionTasks().first, changed)
    XCTAssertNotNil(store.updateCognitionTask(taskId: changed.id, expected: changed) { $0 })
  }

  func testScopedStringBuildMatchesProjectionWithoutChangingOriginalDefaultContract() {
    let provider = GlobalRealtimeContextProvider(cognitionTasksSource: { [] }, researchTasksSource: { [] },
      autonomousRunsSource: { [] }, longHorizonGoalsSource: { [self.goal("Current goal", ["a"])] }, continuitySource: { nil })
    let projected = provider.buildProjection(query: "Status", currentConversationId: "a", excludedConversationIds: [],
      allowedConversationIds: ["a"], nowMillis: 1_000)
    XCTAssertEqual(provider.build(query: "Status", currentConversationId: "a", nowMillis: 1_000), projected.text)
    XCTAssertEqual(provider.build(query: "Status", currentConversationId: "a", nowMillis: 1_000,
      allowedConversationIds: ["a"]), projected.text)
  }

  private func task(_ id: String = "task") -> GlobalCognitionTask {
    .init(id: id, sourceEvent: .init(id: "event-" + id, type: .messageCreated, conversationId: "a", actor: .user),
      baselineUnderstanding: .init(), status: .running, resourceId: "phone-local-model", sourceMessageId: 42,
      createdAtMillis: 1_000, updatedAtMillis: 1_000, contextConversationIds: ["a"], resourceTransport: .onDeviceModel)
  }
  private func scope(_ sessions: [AgentConversation]) -> GlobalBackgroundCognitionScope {
    .init(enabled: true, conversations: sessions)
  }
  private func session(_ id: String, privateMode: Bool = false, trackingPaused: Bool = false) -> AgentConversation {
    .init(id: id, title: id, createdAt: 1, updatedAt: 1, privateMode: privateMode, trackingPaused: trackingPaused)
  }
  private func goal(_ title: String, _ ids: Set<String>) -> GlobalLongHorizonGoal {
    .init(id: title, stableKey: title, topic: "GalaxySSI", title: title, status: .blocked,
      sourceConversationIds: ids, updatedAtMillis: 1_000)
  }
  private func request(_ task: GlobalCognitionTask) -> GalaxySSIGlobalCognitionDispatchRequest {
    .init(taskId: task.id, resourceId: task.resourceId, transport: .onDeviceModel, contactId: "", sourceMessageId: task.sourceMessageId,
      conversationId: "global-cognition:" + task.id, turnId: task.id, systemPrompt: "System", prompt: "Question")
  }
  private func response(_ task: GlobalCognitionTask) -> AgentConnectorResponse {
    .init(sourceMessageId: task.sourceMessageId, contactId: task.resourceId, content: "Result",
      conversationId: "global-cognition:" + task.id, turnId: task.id, taskId: task.id, success: true, receivedAtMillis: 1_000)
  }
}

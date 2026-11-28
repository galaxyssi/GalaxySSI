import XCTest
@testable import GalaxySSI

final class AgentPlanningRecoveryScopeTests: XCTestCase {
  private struct Fixture {
    var task: AgentTaskRecord
    var source: ChatMessage
    var conversation: AgentConversation
    var input: AgentInitialPlanningInput
    func scope() -> AgentPlanningRecoveryScope? {
      AgentPlanningRecoveryScope(profile: "profile-a", task: task, source: source, conversation: conversation)
    }
    func matches(_ scope: AgentPlanningRecoveryScope) -> Bool {
      scope.matches(profile: "profile-a", task: task, source: source, conversation: conversation, cancelled: false)
    }
  }
  private func fixture(replanning: Bool = false, privateMode: Bool = false) -> Fixture {
    let source = ChatMessage(contactId: "hermes", content: "Synthetic planning request", isMine: true,
      conversationId: "conversation", turnId: "planning-turn")
    let conversation = AgentConversation(id: source.conversationId, title: "Fixture", createdAt: 1, updatedAt: 1, privateMode: privateMode)
    var task = AgentTaskRecord(taskId: source.turnId, sessionId: source.conversationId, goal: source.content,
      phase: .planning, routeKind: .localSystem, targetTitle: "Fixture", risk: .low, blocked: false)
    if replanning {
      task.activePlan = AgentPlan(goal: task.goal, screen: .init(foregroundApp: "GalaxySSI"), steps: [], actions: [], route: AgentRoute())
    }
    task.pendingPlanning = .init(sessionId: task.sessionId, conversationId: task.sessionId, turnId: task.taskId,
      inputSha256: String(repeating: "a", count: 64), basePlanId: task.activePlan?.planId, baseRevision: task.activePlan?.revision)
    var input = AgentInitialPlanningInput(goal: task.goal,
      conversation: .init(conversationId: task.sessionId, summary: "", turns: [], privateMode: privateMode),
      turnId: task.taskId, executionMode: .planOnly, hasAttachments: false, allowsDirectResponse: true,
      completionRequirements: nil, plannerConfigurationSha256: "fixture-configuration")
    if let plan = task.activePlan {
      input.replanning = .init(planId: plan.planId, revision: plan.revision,
        planSha256: AgentInitialPlanningJournal(journal: InMemoryAgentModelLoopJournal()).planFingerprint(plan, goal: task.goal),
        reason: "Fixture replanning")
    }
    task.pendingPlanning?.inputSha256 = AgentModelLoopRecoveryIdentity.sha256(input)
    return Fixture(task: task, source: source, conversation: conversation, input: input)
  }

  func testInitialAndReplanningRecoveryKeepTheirExactTaskAndInput() throws {
    for replanning in [false, true] {
      let f = fixture(replanning: replanning), scope = try XCTUnwrap(f.scope())
      XCTAssertTrue(f.matches(scope))
      XCTAssertTrue(scope.acceptsInput(f.input))
    }
  }

  func testProfileCancellationAndUnavailableStateRejectRecoveryCallbacks() throws {
    let f = fixture(), scope = try XCTUnwrap(f.scope())
    XCTAssertFalse(scope.matches(profile: "profile-b", task: f.task, source: f.source, conversation: f.conversation, cancelled: false))
    XCTAssertFalse(scope.matches(profile: "profile-a", task: f.task, source: f.source, conversation: f.conversation, cancelled: true))
    XCTAssertFalse(scope.matches(profile: "profile-a", task: nil, source: f.source, conversation: f.conversation, cancelled: false))
    XCTAssertFalse(scope.matches(profile: "profile-a", task: f.task, source: nil, conversation: f.conversation, cancelled: false))
    XCTAssertFalse(scope.matches(profile: "profile-a", task: f.task, source: f.source, conversation: nil, cancelled: false))
  }

  func testChangedTaskReferenceGoalOrPhaseCannotBeOverwritten() throws {
    let original = fixture(replanning: true), scope = try XCTUnwrap(original.scope())
    for variation in 0..<5 {
      var f = original
      if variation == 0 { f.task.pendingPlanning?.inputSha256 = "changed" }
      if variation == 1 { f.task.goal = "Different task" }
      if variation == 2 { f.task.phase = .cancelled }
      if variation == 3 { f.task.activePlan?.revision += 1 }
      if variation == 4 { f.task.executionLog.append("Concurrent update") }
      XCTAssertFalse(f.matches(scope))
    }
  }

  func testChangedOriginalSourceCannotReceiveAnOldPlan() throws {
    let original = fixture(), scope = try XCTUnwrap(original.scope())
    for variation in 0..<5 {
      var f = original
      if variation == 0 { f.source.id = UUID() }
      if variation == 1 { f.source.content = "Edited request" }
      if variation == 2 { f.source.richOutputJson = "changed-attachments" }
      if variation == 3 { f.source.voiceTranscript = "Edited transcript" }
      if variation == 4 { f.source.conversationId = "other-conversation" }
      XCTAssertFalse(f.matches(scope))
    }
  }

  func testSessionPrivacyTrackingArchiveMergeAndPinnedPreferenceChangesRejectCallbacks() throws {
    let original = fixture(), scope = try XCTUnwrap(original.scope())
    for variation in 0..<5 {
      var f = original
      if variation == 0 { f.conversation.privateMode = true }
      if variation == 1 { f.conversation.trackingPaused = true }
      if variation == 2 { f.conversation.status = .archived }
      if variation == 3 { f.conversation.mergedIntoConversationId = "other-conversation" }
      if variation == 4 { f.conversation.sessionRequirement = "Changed pinned preference" }
      XCTAssertFalse(f.matches(scope))
    }
  }

  func testSavedInputCannotBypassCurrentPrivacyOrConversationScope() throws {
    let f = fixture(), scope = try XCTUnwrap(f.scope())
    for variation in 0..<4 {
      var input = f.input
      if variation == 0 { input.conversation.privateMode = true }
      if variation == 1 { input.conversation.trackingPaused = true }
      if variation == 2 { input.conversation.conversationId = "other-conversation" }
      if variation == 3 { input.turnId = "other-turn" }
      XCTAssertFalse(scope.acceptsInput(input))
    }
  }

  func testMatchingPrivateScopeDoesNotInventAnyNetworkAuthorization() throws {
    let f = fixture(privateMode: true), scope = try XCTUnwrap(f.scope())
    XCTAssertTrue(f.matches(scope))
    XCTAssertTrue(scope.acceptsInput(f.input))
    XCTAssertTrue(scope.privateMode)
    // Actual provider/privacy admission stays outside this identity-only policy.
  }

  func testInvalidOrReplacedPlanningReferencesCannotOpenRecoveryScope() {
    let original = fixture(replanning: true)
    for variation in 0..<6 {
      var f = original
      if variation == 0 { f.task.pendingPlanning = nil }
      if variation == 1 { f.task.pendingPlanning?.conversationId = "other-conversation" }
      if variation == 2 { f.task.pendingPlanning?.turnId = "other-turn" }
      if variation == 3 { f.task.pendingPlanning?.baseRevision = 999 }
      if variation == 4 { f.task.blocked = true; f.task.pendingPlanning?.basePlanId = nil }
      if variation == 5 { f.conversation.status = .archived }
      XCTAssertNil(f.scope())
    }
  }

  func testExplicitUserReplanCanBindTheExistingBlockedTaskWithoutGrantingExecution() throws {
    var f = fixture()
    f.task.phase = .blocked
    f.task.blocked = true
    f.task.pendingPlanning = nil
    XCTAssertNil(f.scope())
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .userReplan))
    XCTAssertTrue(f.matches(scope))
    XCTAssertEqual(scope.task.phase, .blocked)
    XCTAssertTrue(scope.task.blocked)
    XCTAssertNil(scope.task.pendingPlanning)
  }

  func testExplicitUserReplanKeepsUnchangedTrackingPauseAndRestorableReplanState() throws {
    var f = fixture(replanning: true)
    f.task.blocked = true
    f.conversation.trackingPaused = true
    f.input.conversation.trackingPaused = true
    f.task.pendingPlanning?.inputSha256 = AgentModelLoopRecoveryIdentity.sha256(f.input)
    XCTAssertNotNil(f.scope())
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .userReplan))
    XCTAssertTrue(f.matches(scope))
    XCTAssertTrue(scope.acceptsInput(f.input))
    f.conversation.trackingPaused = false
    XCTAssertFalse(f.matches(scope))
  }

  func testExplicitUserReplanCannotAdoptAnotherLiveOrTerminalPhase() {
    for phase in [AgentPhase.executing, .completed, .cancelled, .waitingResponse] {
      var f = fixture()
      f.task.phase = phase
      XCTAssertNil(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
        source: f.source, conversation: f.conversation, use: .userReplan))
    }
  }

  func testUnjournaledUserReplanCallbackRejectsSamePhaseTaskAndSourceChanges() throws {
    var f = fixture()
    f.task.phase = .failed
    f.task.pendingPlanning = nil
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .userReplan))
    XCTAssertTrue(f.matches(scope))
    f.task.goal = "A newer goal still in failed phase"
    XCTAssertFalse(f.matches(scope))
    f.task = scope.task
    f.source.content = "Edited original request"
    XCTAssertFalse(f.matches(scope))
  }

  private func rollingFixture(planning: Bool = false) -> Fixture {
    var f = fixture(replanning: true)
    f.task.lastNativeActionResult = .init(actionId: "prior-action", success: true, message: "Fixture returned",
      metadata: ["awaiting_response": "false"])
    if !planning {
      f.task.phase = .waitingResponse
      f.task.pendingPlanning = nil
    }
    return f
  }

  func testRollingContinuationBindsOnlyTheCompletedBatchWaitingScope() throws {
    let f = rollingFixture()
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .rollingContinuation))
    XCTAssertTrue(f.matches(scope))
    XCTAssertTrue(scope.acceptsInput(f.input))
    XCTAssertNil(f.scope())
    XCTAssertNil(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .userReplan))
  }

  func testRollingContinuationCannotAdoptPendingExternalOrUnownedWork() {
    let original = rollingFixture()
    for variation in 0..<7 {
      var f = original
      if variation == 0 { f.task.lastNativeActionResult?.metadata["awaiting_response"] = "true" }
      if variation == 1 { f.task.lastNativeActionResult = nil }
      if variation == 2 { f.task.activePlan = nil }
      if variation == 3 { f.task.phase = .completed }
      if variation == 4 { f.task.phase = .cancelled }
      if variation == 5 { f.task.phase = .failed }
      if variation == 6 { f.task.phase = .planning }
      XCTAssertNil(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
        source: f.source, conversation: f.conversation, use: .rollingContinuation))
    }
  }

  func testRollingPendingSnapshotKeepsReferenceAndTrackingPauseWithoutGrantingExecution() throws {
    var f = rollingFixture(planning: true)
    f.task.blocked = true
    f.conversation.trackingPaused = true
    f.input.conversation.trackingPaused = true
    f.task.pendingPlanning?.inputSha256 = AgentModelLoopRecoveryIdentity.sha256(f.input)
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: f.task,
      source: f.source, conversation: f.conversation, use: .rollingContinuation))
    XCTAssertTrue(f.matches(scope))
    XCTAssertTrue(scope.acceptsInput(f.input))
    XCTAssertTrue(scope.task.blocked)
    XCTAssertNotNil(f.scope())
    f.task.pendingPlanning?.inputSha256 = "changed-reference"
    XCTAssertFalse(f.matches(scope))
  }

  func testRollingCallbackRejectsSamePhasePlanGoalSourceAndPrivacyChanges() throws {
    let original = rollingFixture()
    let scope = try XCTUnwrap(AgentPlanningRecoveryScope(profile: "profile-a", task: original.task,
      source: original.source, conversation: original.conversation, use: .rollingContinuation))
    for variation in 0..<4 {
      var f = original
      if variation == 0 { f.task.goal = "Changed same-phase goal" }
      if variation == 1 { f.task.activePlan?.revision += 1 }
      if variation == 2 { f.source.content = "Changed source" }
      if variation == 3 { f.conversation.privateMode = true }
      XCTAssertFalse(f.matches(scope))
    }
  }

  func testStartupRetainsBlockedReplanningReadbackButNotBlockedInitialPlanning() throws {
    var replan = fixture(replanning: true)
    replan.task.blocked = true
    let restored = try XCTUnwrap(replan.scope())
    XCTAssertTrue(replan.matches(restored))
    XCTAssertTrue(restored.task.blocked)
    var initial = fixture()
    initial.task.blocked = true
    XCTAssertNil(initial.scope())
  }

  func testStartupRetainsMatchingMemoryPauseAndRejectsChangedSavedInputFlag() throws {
    var f = fixture()
    f.conversation.trackingPaused = true
    f.input.conversation.trackingPaused = true
    f.task.pendingPlanning?.inputSha256 = AgentModelLoopRecoveryIdentity.sha256(f.input)
    let scope = try XCTUnwrap(f.scope())
    XCTAssertTrue(f.matches(scope))
    XCTAssertTrue(scope.acceptsInput(f.input))
    f.input.conversation.trackingPaused = false
    XCTAssertFalse(scope.acceptsInput(f.input))
  }
}

import XCTest
@testable import GalaxySSI

@MainActor
final class AgentResumedPlannerRouteTests: XCTestCase {
  func testSavedSnapshotIsRetainedWithoutRebindingOrGlobalSelection() throws {
    let fixture = try fixture()
    var task = fixture.task
    let snapshot = try XCTUnwrap(AgentModelPlannerContactResolver(store: fixture.store)
      .capturePhoneTurnSnapshot(settings: fixture.store.modelPlannerSettings, selectedContact: fixture.model))
    task.plannerSnapshot = snapshot
    manual("missing", in: fixture)
    fixture.store.updateModelPlannerSettings { $0.cloudContactId = "other" }
    let coordinator = MessageCoordinator(store: fixture.store)
    XCTAssertEqual(try coordinator.resumedNativePlannerSnapshot(task: task, outgoing: fixture.outgoing), snapshot)
    XCTAssertNil(fixture.store.agentSession(id: task.sessionId)?.stableAutoRoute)
  }

  func testMissingSnapshotUsesManualConversationModelNotGlobalPlanner() throws {
    let fixture = try fixture()
    let global = try addModel("global", store: fixture.store)
    fixture.store.updateModelPlannerSettings { $0.cloudContactId = global.id }
    manual(fixture.model.id, in: fixture)
    let coordinator = MessageCoordinator(store: fixture.store)
    let snapshot = try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing)
    XCTAssertEqual(snapshot.route?.contactId, fixture.model.id)
    XCTAssertEqual(snapshot.route?.modelId, "selected")
    XCTAssertEqual(snapshot.selectedForPhoneTurn, true)
    XCTAssertNil(fixture.store.agentSession(id: fixture.task.sessionId)?.stableAutoRoute)
  }

  func testLegacyTaskKeyedByOutgoingMessageCanRetainItsSnapshot() throws {
    let fixture = try fixture()
    var task = fixture.task
    task.taskId = fixture.outgoing.id.uuidString
    let snapshot = try XCTUnwrap(AgentModelPlannerContactResolver(store: fixture.store)
      .capturePhoneTurnSnapshot(settings: fixture.store.modelPlannerSettings, selectedContact: fixture.model))
    task.plannerSnapshot = snapshot
    let coordinator = MessageCoordinator(store: fixture.store)
    XCTAssertEqual(try coordinator.resumedNativePlannerSnapshot(task: task, outgoing: fixture.outgoing), snapshot)
    XCTAssertNil(fixture.store.agentSession(id: task.sessionId)?.stableAutoRoute)
  }

  func testUnavailableManualSelectionDoesNotSubstituteReadyGlobalModel() throws {
    let fixture = try fixture()
    fixture.store.updateModelPlannerSettings { $0.cloudContactId = fixture.model.id }
    manual("missing", in: fixture)
    let coordinator = MessageCoordinator(store: fixture.store)
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    XCTAssertNil(fixture.store.agentSession(id: fixture.task.sessionId)?.stableAutoRoute)
  }

  func testOldSnapshotlessAutoTurnCannotReplaceNewTurnBinding() throws {
    let fixture = try fixture()
    let targets = AgentCallableTargetCatalog.build(contacts: fixture.store.visibleContacts,
      apiKey: { fixture.store.apiKey(for: $0) })
    var newer = fixture.outgoing
    newer.turnId = UUID().uuidString
    newer.createdAt = fixture.outgoing.createdAt.addingTimeInterval(60)
    XCTAssertTrue(fixture.store.beginAgentAutoRouteTurn(for: newer, targets: targets))
    XCTAssertTrue(fixture.store.recordAgentAutoRouteDispatch(conversationId: newer.conversationId,
      turnId: newer.turnId, targetId: fixture.model.id))
    let retained = fixture.store.agentSession(id: newer.conversationId)?.stableAutoRoute
    let coordinator = MessageCoordinator(store: fixture.store)
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    XCTAssertEqual(fixture.store.agentSession(id: newer.conversationId)?.stableAutoRoute, retained)
  }

  func testScopeMismatchCannotReuseEvenASavedSnapshot() throws {
    let fixture = try fixture()
    var task = fixture.task
    task.plannerSnapshot = AgentModelPlannerContactResolver(store: fixture.store)
      .capturePhoneTurnSnapshot(settings: fixture.store.modelPlannerSettings, selectedContact: fixture.model)
    let coordinator = MessageCoordinator(store: fixture.store)
    var messages = [ChatMessage]()
    var changed = fixture.outgoing
    changed.conversationId = "foreign"
    messages.append(changed)
    changed = fixture.outgoing
    changed.turnId = "foreign"
    messages.append(changed)
    changed = fixture.outgoing
    changed.isMine = false
    messages.append(changed)
    changed = fixture.outgoing
    changed.contactId = fixture.model.id
    messages.append(changed)
    changed = fixture.outgoing
    changed.isSystem = true
    messages.append(changed)
    for message in messages {
      XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: task, outgoing: message))
    }
  }

  func testSnapshotlessCloudSelectionHonorsPrivateLocalAndConnectorGates() throws {
    let fixture = try fixture()
    manual(fixture.model.id, in: fixture)
    let coordinator = MessageCoordinator(store: fixture.store)
    XCTAssertTrue(fixture.store.setAgentSessionPrivateMode(id: fixture.task.sessionId, privateMode: true))
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    XCTAssertTrue(fixture.store.setAgentSessionPrivateMode(id: fixture.task.sessionId, privateMode: false))
    fixture.store.agentSafetySettings.connectorCallsAllowed = false
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    fixture.store.agentSafetySettings.connectorCallsAllowed = true
    var localOnly = fixture.task
    localOnly.goal = "Keep this task local only and offline"
    XCTAssertTrue(AgentTaskRequirementAnalyzer.analyze(localOnly.goal).localOnly)
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: localOnly, outgoing: fixture.outgoing))
  }

  func testSnapshotlessSelectionHonorsPauseTrackingAndCancellation() throws {
    let fixture = try fixture()
    manual(fixture.model.id, in: fixture)
    let coordinator = MessageCoordinator(store: fixture.store)
    fixture.store.agentSafetySettings.executionPaused = true
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    fixture.store.agentSafetySettings.executionPaused = false
    XCTAssertTrue(fixture.store.setAgentSessionTrackingPaused(id: fixture.task.sessionId, paused: true))
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
    XCTAssertTrue(fixture.store.setAgentSessionTrackingPaused(id: fixture.task.sessionId, paused: false))
    PhoneExecutionAuthority.requestCancellation(taskId: fixture.task.taskId)
    defer { PhoneExecutionAuthority.clearCancellation(taskId: fixture.task.taskId) }
    XCTAssertThrowsError(try coordinator.resumedNativePlannerSnapshot(task: fixture.task, outgoing: fixture.outgoing))
  }

  private struct Fixture {
    let store: GalaxySSIStore
    let model: GalaxySSIContact
    let outgoing: ChatMessage
    let task: AgentTaskRecord
  }

  private func fixture() throws -> Fixture {
    let suite = "AgentResumedPlannerRouteTests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    store.agentSafetySettings.permissionMode = .askBeforeAction
    store.agentSafetySettings.executionPaused = false
    store.agentSafetySettings.connectorCallsAllowed = true
    let model = try addModel("selected", store: store)
    let session = store.createAgentSession(title: "Resume")
    let outgoing = ChatMessage(contactId: "hermes", content: "Summarize this task", isMine: true,
      conversationId: session.id, turnId: UUID().uuidString)
    let task = AgentTaskRecord(taskId: outgoing.turnId, sessionId: session.id, goal: outgoing.content,
      phase: .waitingResponse, routeKind: .localSystem, targetTitle: "Phone", risk: .low, blocked: false)
    addTeardownBlock {
      AgentModelSelectionSettings.clearConversation(session.id)
      defaults.removePersistentDomain(forName: suite)
    }
    return Fixture(store: store, model: model, outgoing: outgoing, task: task)
  }

  private func addModel(_ id: String, store: GalaxySSIStore) throws -> GalaxySSIContact {
    try store.addCloudModelContact(displayName: id, provider: "OpenAI", modelId: id,
      endpoint: "https://api.openai.com/v1/chat/completions", apiKey: "fixture-key", apiStyle: .openAICompatible)
  }

  private func manual(_ target: String, in fixture: Fixture) {
    for defaults in [UserDefaults.standard, fixture.store.defaults] {
      AgentModelSelectionSettings.selectManual(for: fixture.outgoing.conversationId, targetId: target,
        modelId: "selected", displayName: "Selected", rememberAsDefault: false, defaults: defaults)
    }
  }
}

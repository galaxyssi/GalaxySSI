import XCTest
@testable import GalaxySSI

@MainActor
final class AgentLocalWorkspaceDeviceTests: XCTestCase {
  func testFastDeviceGetterPreservesTheExistingPairingIdentifier() throws {
    try withStore { store, _, _ in
      var profile = store.profile
      for fingerprint in [profile.identityFingerprint, "", "  short  ", "AbCd0123456789ef-LONG", " spaced\nidentity "] {
        profile.identityFingerprint = fingerprint
        XCTAssertEqual(GalaxySSIDeviceIdentity.localDeviceId(profile: profile),
          GalaxySSIDeviceIdentity.current(profile: profile).deviceId)
        let clean = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(48)
        XCTAssertEqual(GalaxySSIDeviceIdentity.localDeviceId(profile: profile), "ios-" + String(clean.prefix(16)))
        XCTAssertEqual(profile.identityFingerprint, fingerprint)
      }
    }
  }

  func testNewLocalProjectionUsesExistingPhoneDeviceIdentity() throws {
    try withStore { store, workspaces, session in
      let task = self.task(session)
      store.upsertAgentTask(task)
      let saved = try XCTUnwrap(workspaces.find(task.taskId))
      XCTAssertEqual(saved.deviceId, GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId)
      XCTAssertTrue(saved.agentId.isEmpty)
      XCTAssertTrue(saved.remoteRunId.isEmpty)
      XCTAssertEqual(saved.toolCalls.first?.status, .running)
    }
  }

  func testLegacyBlankDeviceIsStampedEvenWithoutToolOrStatusChanges() throws {
    try withStore { store, workspaces, session in
      var task = self.task(session)
      store.upsertAgentTask(task)
      var legacy = try XCTUnwrap(workspaces.find(task.taskId))
      legacy.deviceId = ""
      legacy = try workspaces.upsert(legacy, expectedRevision: legacy.revision)
      task.executionLog.append("Refresh metadata")
      store.upsertAgentTask(task)
      let updated = try XCTUnwrap(workspaces.find(task.taskId))
      XCTAssertEqual(updated.deviceId, GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId)
      XCTAssertEqual(updated.status, legacy.status)
      XCTAssertEqual(updated.toolCalls, legacy.toolCalls)
      XCTAssertGreaterThan(updated.revision, legacy.revision)
    }
  }

  func testForeignDeviceWorkspaceIsNotRelabeledByLocalTaskProjection() throws {
    try withStore { store, workspaces, session in
      let task = self.task(session)
      var foreign = self.workspace(task)
      foreign.deviceId = "foreign-phone"
      let original = try workspaces.upsert(foreign)
      store.upsertAgentTask(task)
      XCTAssertEqual(workspaces.find(task.taskId), original)
    }
  }

  func testCurrentAndLegacyDeviceWorkspacesRemainCancellable() throws {
    try withStore { store, workspaces, session in
      for device in ["", GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId] {
        let task = self.task(session)
        var scope = self.workspace(task)
        scope.deviceId = device
        _ = try workspaces.upsert(scope)
        XCTAssertTrue(store.persistLocalWorkspaceCancellation(for: task, at: 300))
        XCTAssertEqual(workspaces.find(task.taskId)?.status, .cancelled)
        XCTAssertEqual(workspaces.find(task.taskId)?.cancellationRequested, true)
      }
    }
  }

  func testForeignOrRemoteScopesCannotBeCancelledAsLocal() throws {
    try withStore { store, workspaces, session in
      for variant in 0..<6 {
        let task = self.task(session)
        var foreign = self.workspace(task)
        foreign.deviceId = GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId
        switch variant {
        case 0: foreign.deviceId = "foreign-device"
        case 1: foreign.agentId = "desktop-agent"
        case 2: foreign.remoteRunId = "remote-run"
        case 3: foreign.parentRunId = "parent"
        case 4: foreign.conversationId = "another-conversation"
        default: foreign.deliveryMode = AgentDeliveryMode.observe.rawValue
        }
        let original = try workspaces.upsert(foreign)
        XCTAssertTrue(store.persistLocalWorkspaceCancellation(for: task, at: 300))
        XCTAssertEqual(workspaces.find(task.taskId), original)
      }
    }
  }

  func testInterruptedCancellationRecoveryAcceptsOnlyCurrentOrLegacyDevices() throws {
    try withStore { store, workspaces, session in
      var expected: Set<String> = []
      for device in ["", GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId, "foreign"] {
        let task = self.task(session)
        store.upsertAgentTask(task)
        var cancelled = try XCTUnwrap(workspaces.find(task.taskId))
        cancelled.deviceId = device
        cancelled.status = .cancelled
        cancelled.cancellationRequested = true
        _ = try workspaces.upsert(cancelled, expectedRevision: cancelled.revision)
        if device != "foreign" { expected.insert(task.taskId) }
      }
      XCTAssertEqual(Set(store.interruptedLocalWorkspaceCancellations().map(\.taskId)), expected)
    }
  }

  func testWorkspaceOnlyPhoneProjectionDoesNotBecomeDesktopWhenDeviceIsSet() throws {
    try withStore { store, workspaces, session in
      let device = GalaxySSIDeviceIdentity.current(profile: store.profile).deviceId
      for id in ["", device, "desktop-device"] {
        let task = self.task(session)
        var workspace = self.workspace(task)
        workspace.deviceId = id
        _ = try workspaces.upsert(workspace)
        let projected = try XCTUnwrap(store.mergedAgentTaskRecords().first { $0.taskId == task.taskId })
        XCTAssertEqual(projected.executionLocationKind, id == "desktop-device" ? .desktop : .phone)
        XCTAssertEqual(projected.executionRuntimeKind, id == "desktop-device" ? .desktopAgent : .phoneNative)
      }
      let remoteTask = self.task(session)
      var remote = self.workspace(remoteTask)
      remote.deviceId = device
      remote.remoteRunId = "remote-run"
      _ = try workspaces.upsert(remote)
      let projected = try XCTUnwrap(store.mergedAgentTaskRecords().first { $0.taskId == remoteTask.taskId })
      XCTAssertEqual(projected.routeKind, .desktopAgent)
      XCTAssertEqual(projected.executionLocationKind, .desktop)
    }
  }

  func testPrivateAndTrackingPausedSessionsStillDoNotProjectWorkspaces() throws {
    try withStore { store, workspaces, _ in
      let privateSession = store.createAgentSession(title: "Private", privateMode: true)
      let pausedSession = store.createAgentSession(title: "Paused")
      XCTAssertTrue(store.setAgentSessionTrackingPaused(id: pausedSession.id, paused: true))
      for session in [privateSession, pausedSession] {
        let task = self.task(session)
        store.upsertAgentTask(task)
        XCTAssertNil(workspaces.find(task.taskId))
      }
    }
  }

  private func withStore(_ body: (GalaxySSIStore, InMemoryAgentWorkspaceStore, AgentConversation) throws -> Void) throws {
    let domain = "LocalWorkspaceDevice-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let workspaces = InMemoryAgentWorkspaceStore(clock: { 200 })
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore(), workspaceStore: workspaces)
    try body(store, workspaces, store.createAgentSession(title: "Device scope"))
  }

  private func task(_ session: AgentConversation) -> AgentTaskRecord {
    let id = UUID().uuidString
    let action = AgentPlanContinuationScope(conversationId: session.id, turnId: id).bind(
      AgentAction(id: "read", kind: .callNativeTool, target: "tool.read", risk: .low,
        status: .running, description: "Read phone state"))
    var task = AgentTaskRecord(taskId: id, sessionId: session.id, goal: "Inspect", phase: .executing,
      routeKind: .localSystem, targetTitle: "Phone", risk: .low, blocked: false,
      createdAtMillis: 10, updatedAtMillis: 200)
    task.activePlan = AgentPlan(goal: task.goal, screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [], actions: [action])
    return task
  }

  private func workspace(_ task: AgentTaskRecord) -> AgentWorkspace {
    .init(workspaceId: task.taskId, sessionId: task.sessionId, conversationId: task.sessionId,
      taskId: task.taskId, goal: task.goal, status: .running, createdAtMillis: 10, updatedAtMillis: 200)
  }
}

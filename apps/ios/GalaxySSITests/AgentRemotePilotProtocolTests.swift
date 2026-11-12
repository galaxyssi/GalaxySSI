import Darwin
import XCTest
@testable import GalaxySSI

final class AgentRemotePilotProtocolTests: XCTestCase {
  private typealias Pilot = AgentRemotePilotProtocol
  private let bytes = Data("""
    {"format":"galaxyssi.remote-collaboration-pilot.v1","pilot_id":"remote-fixture","target_id":"fixture:codex",
     "model_id":"selected-model","reasoning_effort":"xhigh","tool_scope":"production_tools_not_isolated","trial_timeout_ms":60000,
     "slots":[{"id":"a","case_id":"case","arm":"single","prompt":"Synthetic task."},
              {"id":"b","case_id":"case","arm":"team","prompt":"Synthetic task."}]}
    """.utf8)
  private let selection = AgentModelSelection(mode: .manual, targetId: "fixture:codex", modelId: "selected-model",
    reasoningEffort: .xhigh)

  func testPlanRequiresIdenticalPairsAndIndependentPhoneDispatchAllowance() throws {
    let plan = try Pilot.Plan.read(bytes, authorized: 6)
    XCTAssertNoThrow(try plan.requireSelection(selection))
    XCTAssertThrowsError(try plan.requireSelection(.init()))
    XCTAssertThrowsError(try Pilot.Plan.read(bytes, authorized: 5))
    let raw = String(decoding: bytes, as: UTF8.self)
    for (old, new) in [("production_tools_not_isolated", "closed_book"), ("fixture:codex", "other-agent"), ("xhigh", "automatic"),
      ("\"arm\":\"team\"", "\"arm\":\"single\""), ("\"id\":\"b\"", "\"id\":\"a\""),
      ("\"case_id\":\"case\",\"arm\":\"team\"", "\"case_id\":\"other\",\"arm\":\"team\"")] {
      XCTAssertThrowsError(try Pilot.Plan.read(Data(raw.replacingOccurrences(of: old, with: new).utf8), authorized: 6))
    }
  }

  func testExactAppSelectionIsPerConversationAndDoesNotFallBack() throws {
    let suite = "remote-pilot-selection-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let plan = try Pilot.Plan.read(bytes, authorized: 6)
    AgentModelSelectionSettings.selectManual(for: "selected", targetId: selection.targetId, modelId: selection.modelId,
      displayName: "Fixture", reasoningEffort: selection.reasoningEffort, rememberAsDefault: false, defaults: defaults)
    XCTAssertNoThrow(try plan.requireSelection(AgentModelSelectionSettings.selection(for: "selected", defaults: defaults)))
    XCTAssertThrowsError(try plan.requireSelection(AgentModelSelectionSettings.selection(for: "other", defaults: defaults)))
    AgentModelSelectionSettings.selectManual(for: "selected", targetId: selection.targetId, modelId: selection.modelId,
      displayName: "Fixture", reasoningEffort: .low, rememberAsDefault: false, defaults: defaults)
    XCTAssertThrowsError(try plan.requireSelection(AgentModelSelectionSettings.selection(for: "selected", defaults: defaults)))
  }

  func testSchedulerAdmissionsAreDurableAndNextSlotNeedsCleanup() async throws {
    let plan = try Pilot.Plan.read(bytes, authorized: 6)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let digest = Pilot.digest(bytes)
    let journal = try Pilot.Journal(directory: root, plan: plan, digest: digest, selection: selection,
      selectionConversation: "fixture-selection")
    let identity = try await journal.start(0)
    let slot = try XCTUnwrap(plan.slots.first)
    let definition = plan.definition(for: slot, identity: identity)
    let gate = Pilot.Gate(plan: plan, slot: slot, identity: identity, index: 0, journal: journal, deadline: .max)
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 3, maxConcurrency: 1))
    defer { runtime.close() }
    let selected = selection
    let handle = try runtime.start(definition: definition, request: identity.request(goal: slot.prompt),
      worker: ClosureAgentTeamMemberWorker { context in
        let prepared = try await gate.admit(context, selection: selected)
        XCTAssertEqual(prepared.receipt.promptSHA256, Pilot.digest(Data(prepared.prompt.utf8)))
        let saved = try JSONDecoder().decode(Pilot.Report.self, from: Data(contentsOf: root.appendingPathComponent("report.json")))
        XCTAssertEqual(saved.slots.first?.dispatches.last, prepared.receipt)
        return AgentSubagentOutput(content: "Synthetic result for " + prepared.receipt.node.rawValue)
      })
    let result = try await handle.wait()
    XCTAssertEqual(result.state, .succeeded)
    try await journal.recordOutcome(index: 0, identity: identity, succeeded: true)
    let saved = await journal.snapshot()
    let first = try XCTUnwrap(saved.slots.first)
    XCTAssertEqual(first.dispatches.map(\.node), [.draft, .review, .final])
    XCTAssertEqual(first.dispatches.map(\.person), ["analyst", "analyst", "analyst"])
    XCTAssertEqual(Set(first.dispatches.map(\.sourceID)).count, 3)
    XCTAssertFalse(first.remoteCleanupConfirmed)
    XCTAssertThrowsError(try Pilot.Journal(directory: root, plan: plan, digest: digest, selection: selection,
      selectionConversation: "fixture-selection"))
    do {
      _ = try await journal.start(1)
      XCTFail("Unconfirmed remote cleanup cannot authorize another slot")
    } catch Pilot.Failure.cleanup {}
    try await journal.requestStop(index: 0, identity: identity)
    try await journal.confirmCleanup(index: 0, identity: identity)
    let second = try await journal.start(1)
    XCTAssertNotEqual(identity, second)
  }

  #if DEBUG
  @MainActor
  func testOptInAppSelectedRemotePilot() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_REMOTE_PILOT_RUN"] == "1" else { throw XCTSkip("Remote pilot is opt-in") }
    #if targetEnvironment(simulator)
    throw Pilot.Failure.scope
    #else
    var hardware = utsname()
    guard uname(&hardware) == 0 else { throw Pilot.Failure.scope }
    let model = withUnsafeBytes(of: hardware.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    guard !model.isEmpty, env["GALAXYSSI_REMOTE_PILOT_DEVICE_MODEL"] == model,
          env["GALAXYSSI_REMOTE_PILOT_TOOLS"] == Pilot.toolScope else { throw Pilot.Failure.scope }
    let file = URL(fileURLWithPath: try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_PLAN"]))
    let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard metadata.isRegularFile == true, metadata.isSymbolicLink == false,
          let size = metadata.fileSize, (1...512_000).contains(size) else { throw Pilot.Failure.manifest }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: 512_001) ?? Data()
    let digest = Pilot.digest(bytes)
    guard bytes.count == size, digest == env["GALAXYSSI_REMOTE_PILOT_SHA256"] else { throw Pilot.Failure.manifest }
    let authorized = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_MAX_DISPATCHES"].flatMap(Int.init))
    let plan = try Pilot.Plan.read(bytes, authorized: authorized)
    let conversation = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_SELECTION_CONVERSATION"])
    let waitUntil = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
    while MessageCoordinator.activeRemotePilotCoordinator == nil, DispatchTime.now().uptimeNanoseconds < waitUntil {
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    let coordinator = try XCTUnwrap(MessageCoordinator.activeRemotePilotCoordinator)
    let store = coordinator.store
    let binding = try Pilot.AppBinding.read(plan: plan, conversation: conversation, store: store)
    let link = try XCTUnwrap(store.serverLinks.first { $0.paired && $0.desktopId == binding.desktop &&
      $0.desktopFingerprint == binding.desktopFingerprint && $0.routes.clientRouteId == binding.clientRoute })
    while !coordinator.canSendRemotePilot(to: link), DispatchTime.now().uptimeNanoseconds < waitUntil {
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    guard coordinator.canSendRemotePilot(to: link) else { throw Pilot.Failure.scope }
    let originalSelection = store.activeAgentConversationId
    defer { XCTAssertEqual(store.activeAgentConversationId, originalSelection) }
    let root = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
      .appendingPathComponent("XCTest-AppSelectedRemotePilot", isDirectory: true)
      .appendingPathComponent(plan.pilot, isDirectory: true)
    let journal = try Pilot.Journal(directory: root, plan: plan, digest: digest, selection: binding.selection,
      selectionConversation: binding.selectionConversation)
    for (index, slot) in plan.slots.enumerated() {
      guard try Pilot.AppBinding.read(plan: plan, conversation: conversation, store: store) == binding,
            store.activeAgentConversationId == originalSelection else { throw Pilot.Failure.selection }
      let identity = try await journal.start(index)
      let succeeded = try await executeRemoteSlot(plan: plan, slot: slot, index: index, identity: identity,
        journal: journal, root: root, coordinator: coordinator, binding: binding)
      let report = await journal.snapshot()
      guard report.slots[index].remoteCleanupConfirmed else { throw Pilot.Failure.cleanup }
      XCTAssertTrue(succeeded, "Remote slot failed; inspect its preserved report.")
    }
    #endif
  }

  @MainActor
  private func executeRemoteSlot(plan: Pilot.Plan, slot: Pilot.Slot, index: Int, identity: Pilot.Identity,
      journal: Pilot.Journal, root: URL, coordinator: MessageCoordinator, binding: Pilot.AppBinding) async throws -> Bool {
    let store = coordinator.store, history = AgentTeamExecutionHistoryStore.shared
    let now = AgentControlPlaneClock.nowMillis()
    guard store.agentConversationDatabase.confirmsAbsent(identity.group), history.snapshot(supervisorRunId: identity.run) == nil,
          store.agentConversationDatabase.upsert(.init(id: identity.group, title: "Remote calibration fixture",
            createdAt: now, updatedAt: now, createdByAgent: true)) else { throw Pilot.Failure.scope }
    let definition = plan.definition(for: slot, identity: identity)
    let observers = try Pilot.Node.allCases.map { node -> AgentTeamMemberSnapshot in
      let source = try XCTUnwrap(identity.sources[node])
      return .init(agentId: binding.contact, deliveryMode: .observe, instanceId: node.rawValue,
        sourceMessageId: source.uuidString, dispatchCheckpoint: .notStarted)
    }
    let initial = AgentTeamExecutionSnapshot(supervisorRunId: identity.run, teamId: definition.teamId,
      conversationId: identity.group, taskId: identity.turn, primaryAgentId: binding.contact, goal: slot.prompt,
      state: .running, members: observers, createdAtMillis: now, updatedAtMillis: now, primaryInstanceId: "final")
    guard history.upsert(initial) else { throw Pilot.Failure.scope }
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(plan.timeoutMillis) * 1_000_000
    let gate = Pilot.Gate(plan: plan, slot: slot, identity: identity, index: index, journal: journal, deadline: deadline)
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 3, maxConcurrency: 1, maxContextCharacters: 60_000))
    defer { runtime.close() }
    let handle = try runtime.start(definition: definition, request: identity.request(goal: slot.prompt),
      worker: ClosureAgentTeamMemberWorker { context in
        let current = try await Pilot.AppBinding.read(plan: plan, conversation: binding.selectionConversation, store: store)
        guard current == binding else { throw Pilot.Failure.selection }
        let prepared = try await gate.admit(context, selection: current.selection)
        let result = try await coordinator.sendRemotePilotMember(prompt: prepared.prompt, runID: identity.run,
          conversation: identity.group, turn: identity.turn, member: prepared.receipt.node.rawValue,
          source: prepared.receipt.sourceID, contactID: binding.contact, desktopID: binding.desktop,
          fingerprint: binding.desktopFingerprint, routeID: binding.clientRoute, profile: binding.profile,
          selectionConversation: binding.selectionConversation, selection: binding.selection,
          invocation: binding.invocation, deadline: deadline)
        guard !result.isBlank, result.utf16.count <= AgentSubagentLimits.defaultMaxOutputCharacters else { throw Pilot.Failure.incomplete }
        return AgentSubagentOutput(content: result)
      })
    let timer = Task {
      let now = DispatchTime.now().uptimeNanoseconds
      if deadline > now {
        do { try await Task.sleep(nanoseconds: deadline - now) } catch { return }
      }
      handle.cancel(reason: "Remote pilot slot deadline")
    }
    let snapshot = try? await withTaskCancellationHandler(operation: { try await handle.wait() }, onCancel: { handle.cancel() })
    timer.cancel()
    let report = await journal.snapshot()
    let sources = report.slots[index].dispatches.map(\.sourceID)
    var finalSHA256: String?
    let final = snapshot?.finalOutput
    let saved = history.snapshot(supervisorRunId: identity.run)?.members.first {
      $0.sourceMessageId == identity.sources[.final]?.uuidString && $0.status == .succeeded
    }
    let exactFinal = final.map { answer in
      saved.map { answer.utf8.elementsEqual(($0.replyContent ?? $0.output).utf8) } ?? false
    } ?? false
    let succeeded = snapshot?.state == .succeeded && sources.count == 3 && exactFinal
    var archiveError: Error?
    do {
      if let final, succeeded {
        let bytes = Data(final.utf8)
        try bytes.write(to: root.appendingPathComponent(slot.id + ".result.txt"), options: .withoutOverwriting)
        finalSHA256 = Pilot.digest(bytes)
      }
      try await journal.recordOutcome(index: index, identity: identity, succeeded: succeeded, finalSHA256: finalSHA256)
      try await journal.requestStop(index: index, identity: identity)
    } catch {
      archiveError = error
    }
    let cleanup = Task { @MainActor in
      await coordinator.settleRemotePilotOwners(runID: identity.run, conversation: identity.group, turn: identity.turn,
        sources: sources, contactID: binding.contact, desktopID: binding.desktop,
        fingerprint: binding.desktopFingerprint, routeID: binding.clientRoute, profile: binding.profile)
    }
    let settled = await cleanup.value
    if let archiveError { throw archiveError }
    // Do not remove a test scope while its exact remote owners are unresolved.
    if settled, !handle.isActive, store.profile.identityFingerprint == binding.profile {
      history.remove(supervisorRunId: identity.run)
      if store.deleteAgentSession(id: identity.group), store.agentConversationDatabase.confirmsAbsent(identity.group),
         history.snapshot(supervisorRunId: identity.run) == nil {
        try await journal.confirmCleanup(index: index, identity: identity)
      }
    }
    return succeeded
  }
  #endif
}

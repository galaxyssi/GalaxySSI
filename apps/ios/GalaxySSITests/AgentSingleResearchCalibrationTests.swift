import CryptoKit
import Darwin
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentSingleResearchCalibrationTests: XCTestCase {
  private let legacyFormat = "galaxyssi.single-agent-calibration.v1"
  private let objective = "  Inspect the supplied fixture.\n\nPreserve the original conditions.\n"
  private let selection = AgentModelSelection(mode: .manual, targetId: "fixture:codex",
    modelId: "selected-model", reasoningEffort: .high)

  func testResearchCalibrationRequiresExplicitProtocolSelectionAndSingleDispatch() {
    let scope = scope(run: "first", turn: "first-turn")
    func enroll(_ format: String, _ model: AgentModelSelection, _ limit: Int) -> AgentSingleResearchCalibration? {
      .init(format: format, scope: scope, selection: model, objective: objective, maximumDispatches: limit)
    }
    XCTAssertNil(enroll(legacyFormat, selection, 1))
    XCTAssertNil(enroll("unknown", selection, 1))
    XCTAssertNil(enroll(AgentSingleResearchCalibration.format, AgentModelSelection(), 1))
    XCTAssertNil(enroll(AgentSingleResearchCalibration.format, selection, 2))
    let enrolled = enroll(AgentSingleResearchCalibration.format, selection, 1)
    XCTAssertEqual(enrolled?.modelID, selection.modelId)
    XCTAssertEqual(enrolled?.reasoningEffort, selection.reasoningEffort)
  }

  func testSingleResearchAssignmentPublishesAndRecallsAnUnverifiedMethodAfterReopen() async throws {
    try await runCalibration(persistSelection: true)
  }

  func testCalibrationDoesNotCreateASelectionFromTheNewestConversation() async throws {
    try await runCalibration(persistSelection: false)
  }

  func testCalibrationDeviceBindingRejectsMissingAmbiguousAndMismatchedModels() throws {
    let actual = "iPhone16,2"
    XCTAssertNoThrow(try Self.requirePilotDevice(actual: actual, expected: actual))
    XCTAssertThrowsError(try Self.requirePilotDevice(actual: actual, expected: nil))
    XCTAssertThrowsError(try Self.requirePilotDevice(actual: actual, expected: "iPhone17,2"))
    for invalid in ["", " ", "*", "iPhone16,2,iPhone17,2", "iPhone16,2\n", " iPhone16,2", "iPhone16,2;iPhone17,2"] {
      XCTAssertThrowsError(try Self.requirePilotDevice(actual: invalid, expected: invalid))
    }
  }

  func testDeviceBoundCalibrationPreservesPersistedSelection() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["GALAXYSSI_CALIBRATION_DEVICE_TEST"] == "1" else {
      throw XCTSkip("Device-bound calibration is opt-in")
    }
    #if targetEnvironment(simulator)
    XCTFail("Device-bound calibration requires a physical iOS device")
    #else
    var hardware = utsname()
    guard uname(&hardware) == 0 else { throw PilotDeviceError.unavailable }
    let model = withUnsafeBytes(of: hardware.machine) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    try Self.requirePilotDevice(actual: model, expected: environment["GALAXYSSI_CALIBRATION_DEVICE_MODEL"])
    try await runCalibration(persistSelection: true)
    try await runCalibration(persistSelection: false)
    let attachment = XCTAttachment(string: "device_model=\(model)\nselection_check=persisted_conversation_selection")
    attachment.name = "Calibration device and check"
    attachment.lifetime = .keepAlways
    add(attachment)
    #endif
  }

  private enum PilotDeviceError: Error { case unavailable, invalid, mismatch }

  private static func requirePilotDevice(actual: String, expected: String?) throws {
    // A hardware identifier contains one comma; it is not a list of models.
    guard let expected,
          expected.utf8.count <= 128,
          expected.range(of: #"\Ai(?:Phone|Pad|Pod)[0-9]+,[0-9]+\z"#, options: .regularExpression) != nil
    else { throw PilotDeviceError.invalid }
    guard actual == expected else { throw PilotDeviceError.mismatch }
  }

  private func runCalibration(persistSelection: Bool) async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    let history = fixture.history()
    let scope = scope(run: "original-run", turn: "original-turn")
    let conversationFile = fixture.root.appendingPathComponent("conversations.sqlite3")
    let conversations = AgentConversationDatabase(fileURL: conversationFile, secrets: fixture.secrets)
    let existing = AgentConversation(id: "existing-conversation", title: "Existing conversation", createdAt: 1, updatedAt: 1)
    XCTAssertTrue(conversations.upsert(existing))
    if persistSelection { conversations.setActiveConversationId(existing.id) }
    let priorSelection = conversations.activeConversationId
    XCTAssertEqual(priorSelection, persistSelection ? existing.id : "")
    let pilot = AgentConversation(id: scope.conversationId, title: "Isolated calibration", createdAt: 2, updatedAt: 2)
    XCTAssertTrue(conversations.upsert(pilot))
    XCTAssertEqual(conversations.readAll().max { $0.updatedAt < $1.updatedAt }?.id, pilot.id)
    XCTAssertEqual(conversations.activeConversationId, priorSelection)
    let calibration = try XCTUnwrap(AgentSingleResearchCalibration(format: AgentSingleResearchCalibration.format,
      scope: scope, selection: selection, objective: objective, maximumDispatches: 1))
    let final = #"{"format":"galaxyssi.research-artifact.v1","summary":"Synthetic delivery only","milestones":["candidate"]}"#
    let plan = definition(scope: scope, research: true)
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 1, maxConcurrency: 1))
    defer { runtime.close() }
    let counter = DispatchCounter()
    let request = AgentRunRequest(conversationId: scope.conversationId, messageId: scope.turnId, taskId: scope.turnId,
      runId: scope.runId, parentRunId: "", goal: objective, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: scope.runId, createdAtMillis: 1)
    let assignment = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    let handle = try runtime.start(definition: plan, request: request,
      worker: ClosureAgentTeamMemberWorker { context in
        try await counter.admit()
        XCTAssertEqual(Data(context.request.goal.utf8), Data(request.goal.utf8))
        XCTAssertEqual(context.member.objective, request.goal.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(context.member.deliveryMode, .respond)
        XCTAssertEqual(context.member.memberId, scope.memberId)
        XCTAssertTrue(context.member.dependsOnAgentIds.isEmpty)
        XCTAssertEqual(context.member.agentId, calibration.targetID)
        XCTAssertEqual(context.request.context.string("_galaxyssi_member_model_id"), calibration.modelID)
        XCTAssertEqual(context.request.context.string(AgentCollaborationReasoningSelection.contextKey),
          calibration.reasoningEffort.rawValue)
        XCTAssertEqual(context.request.context.string("_galaxyssi_research_stage"), AgentSingleResearchCalibration.stage)
        XCTAssertTrue(history.upsert(assignment))
        XCTAssertEqual(try history.milestoneCapability(scope: scope), .notEnrolled)
        try history.enrollSingleResearchCalibration(calibration)
        let reopened = fixture.history()
        XCTAssertEqual(try reopened.milestoneCapability(scope: scope), .available)
        let initial = try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)
        XCTAssertEqual(initial["milestones"]?.arrayValue, [])
        let receipt = try reopened.publishCollaborationMilestone([
          "mode": .string("publish"), "milestone_id": .string("candidate"), "artifact": .string(Self.method)
        ], scope: scope)
        XCTAssertEqual(receipt["status"], .string("published"))
        XCTAssertEqual(receipt["references"]?.arrayValue?.count, 1)
        XCTAssertEqual(reopened.snapshot(supervisorRunId: scope.runId)?.state, .running)
        let archive = try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)
        XCTAssertEqual(archive["next_cursor"], .null)
        await counter.archive(archive["milestones"]?.arrayValue ?? [])
        return AgentSubagentOutput(content: final)
      })
    let delivered = try await handle.wait()
    let count = await counter.count
    XCTAssertEqual(count, 1)
    XCTAssertEqual(delivered.members.count, 1)
    XCTAssertEqual(delivered.finalOutput, final)
    let archive = await counter.milestones
    var originals = InterimPilotArchive(conversation: scope.conversationId, run: scope.runId, turn: scope.turnId)
    try originals.capture(assignment, database: fixture.database())
    XCTAssertEqual(originals.entries.values.map(\.milestoneID), ["candidate"])
    let report = Self.deliveryReport(snapshot: delivered, dispatches: count, archive: archive, originals: originals)
    XCTAssertTrue(Self.acceptsDeliveryOnly(report))
    XCTAssertEqual(archive.first?.objectValue?.string("milestone_id"), "candidate")
    var overclaim = report
    overclaim["scientific_capability_gain_proven"] = .bool(true)
    XCTAssertFalse(Self.acceptsDeliveryOnly(overclaim))
    var incomplete = report
    incomplete["milestone_archive_complete"] = .bool(false)
    XCTAssertFalse(Self.acceptsDeliveryOnly(incomplete))
    incomplete = report
    var purportedRead = originals.report
    purportedRead["peer_read_proven"] = .bool(true)
    incomplete["interim_evidence"] = .object(purportedRead)
    XCTAssertFalse(Self.acceptsDeliveryOnly(incomplete))
    let committed = try XCTUnwrap(history.applyReply(supervisorRunId: scope.runId, source: scope.sourceId,
      conversation: scope.conversationId, turn: scope.turnId, task: scope.sourceId,
      contact: calibration.targetID, content: final, success: true, now: 2))
    XCTAssertEqual(committed.state, .succeeded)
    try history.publishSavedResearchReply(final, scope: scope)

    let reopened = fixture.history()
    XCTAssertEqual(try reopened.milestoneCapability(scope: scope), .finalized)
    let saved = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope)?.first)
    let future = self.scope(run: "next-run", turn: "next-turn")
    XCTAssertTrue(reopened.upsert(activeSnapshot(future, stage: nil)))
    let page = try reopened.recallCollaborationOriginal(["mode": .string("workspace"),
      "object_id": .string(saved.reference.objectId), "revision": .int(saved.reference.revision),
      "sha256": .string(saved.reference.sha256)], scope: future)
    XCTAssertEqual(page["sha256"], .string(saved.reference.sha256))
    XCTAssertTrue(page.string("content").contains("Synthetic method, not learned"))
    let directory = try reopened.recallCollaborationOriginal(["mode": .string("capabilities")], scope: future)
    XCTAssertEqual(directory["capabilities"]?.arrayValue?.first?.objectValue?.string("state"), "unverified_candidate")
    XCTAssertEqual(directory["grants_permissions"], .bool(false))
    XCTAssertEqual(try reopened.milestoneCapability(scope: future), .notEnrolled)

    let persisted = AgentConversationDatabase(fileURL: conversationFile, secrets: fixture.secrets)
    XCTAssertEqual(persisted.activeConversationId, priorSelection)
    XCTAssertEqual(persisted.read(pilot.id), pilot)
    XCTAssertEqual(persisted.delete(pilot.id), pilot)
    XCTAssertTrue(persisted.confirmsAbsent(pilot.id))
    XCTAssertEqual(persisted.read(existing.id), existing)
    XCTAssertEqual(persisted.activeConversationId, priorSelection)
  }

  func testEnrollmentCannotAuthorizeChangedObjectiveMultipleMembersOrRevokedGroup() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    let history = fixture.history()
    let scope = scope(run: "guarded", turn: "guarded-turn")
    let enrollment = try XCTUnwrap(AgentSingleResearchCalibration(format: AgentSingleResearchCalibration.format,
      scope: scope, selection: selection, objective: objective, maximumDispatches: 1))
    var team = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    team.goal = "A substituted task"
    XCTAssertFalse(enrollment.owns(team, member: team.members[0]))
    team = activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)
    team.members.append(.init(agentId: "another", sourceMessageId: "another-source"))
    XCTAssertFalse(enrollment.owns(team, member: team.members[0]))
    XCTAssertTrue(history.upsert(activeSnapshot(scope, stage: AgentSingleResearchCalibration.stage)))
    try history.enrollSingleResearchCalibration(enrollment)
    var foreign = scope
    foreign.sourceId = "foreign"
    XCTAssertThrowsError(try history.publishCollaborationMilestone(["mode": .string("status")], scope: foreign))
    history.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertThrowsError(try history.enrollSingleResearchCalibration(enrollment))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(["mode": .string("status")], scope: scope))
  }

  @MainActor func testPilotContinuityRetainsExactMethodAcrossFreshAssignments() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let seed = try continuityPhase(at: root, secrets: secrets, phase: 1, previous: "")
    XCTAssertThrowsError(try continuityPhase(at: root, secrets: secrets, phase: 1, previous: ""))
    XCTAssertThrowsError(try continuityPhase(at: root, secrets: secrets, phase: 2, previous: String(repeating: "0", count: 64)))
    let archive = root.appendingPathComponent("phase-1").appendingPathComponent("original.json")
    let original = try Data(contentsOf: archive)
    try Data("tampered".utf8).write(to: archive, options: .atomic)
    XCTAssertThrowsError(try continuityPhase(at: root, secrets: secrets, phase: 2, previous: seed))
    try original.write(to: archive, options: .atomic)
    let restored = try continuityPhase(at: root, secrets: secrets, phase: 2, previous: seed)
    XCTAssertNotEqual(seed, restored)
    XCTAssertThrowsError(try continuityPhase(at: root, secrets: secrets, phase: 2, previous: seed))
  }

  @MainActor func testOptInPilotContinuityAcrossTestProcesses() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let rawPhase = environment["GALAXYSSI_CONTINUITY_PHASE"] else {
      throw XCTSkip("Set GALAXYSSI_CONTINUITY_PHASE and an isolated study token to opt in.")
    }
    let phase = try XCTUnwrap(Int(rawPhase))
    let token = try XCTUnwrap(environment["GALAXYSSI_CONTINUITY_TOKEN"].flatMap { UUID(uuidString: $0) })
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    let root = support.appendingPathComponent("XCTest-PilotContinuity", isDirectory: true)
      .appendingPathComponent(token.uuidString.lowercased(), isDirectory: true)
    let secrets = ContinuitySecrets(prefix: Self.continuityStorageKey(root))
    let digest = try continuityPhase(at: root, secrets: secrets, phase: phase,
      previous: environment["GALAXYSSI_CONTINUITY_PREVIOUS_REPORT_SHA256"] ?? "", requireFreshProcess: true)
    if phase == 2 {
      try FileManager.default.removeItem(at: root.appendingPathComponent("workspace", isDirectory: true))
      secrets.erase()
    }
    print("GALAXYSSI_CONTINUITY_REPORT_SHA256=\(digest)")
  }

  private struct ContinuityReservation: Codable, Equatable {
    let phase: Int
    let group: String
    let run: String
    let turn: String
    let signature: String
    let protocolDigest: String
    let previousDigest: String
  }

  private struct ContinuityReport: Codable {
    let reservation: ContinuityReservation
    let reference: AgentCollaborationResearchReference
    let observerOriginalDigest: String
    let runnerProcess: String
    let retained: Bool
    let archiveComplete: Bool
    let cleanupConfirmed: Bool
    let pendingRemoteOwners: [String]
    let executionState: String
    let autonomousRetrievalProven: Bool
    let retainedLearningProven: Bool
    let freshProviderThreadVerified: Bool
  }

  private final class ContinuitySecrets: GalaxySSISecretStore {
    private let prefix: String
    private var accounts: Set<String> = []

    init(prefix: String) { self.prefix = prefix + ":" }

    func string(account: String) -> String? {
      accounts.insert(account)
      return KeychainSecretStore.shared.string(account: prefix + account)
    }

    func setString(_ value: String, account: String) throws {
      accounts.insert(account)
      try KeychainSecretStore.shared.setString(value, account: prefix + account)
    }

    func delete(account: String) {
      KeychainSecretStore.shared.delete(account: prefix + account)
    }

    func erase() { for account in accounts { delete(account: account) } }
  }

  private static func continuityStorageKey(_ root: URL) -> String {
    "xctest-pilot-continuity:" + root.lastPathComponent
  }

  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  @MainActor private func continuityPhase(at root: URL, secrets: GalaxySSISecretStore, phase: Int, previous: String,
                                         requireFreshProcess: Bool = false) throws -> String {
    let fs = FileManager.default
    let failure = AgentTeamHistoryDatabase.Failure.stale
    guard phase == 1 || phase == 2 else { throw failure }
    let work = root.appendingPathComponent("workspace", isDirectory: true)
    let file = work.appendingPathComponent("history.sqlite3")
    let directory = root.appendingPathComponent("phase-\(phase)", isDirectory: true)
    let device = requireFreshProcess ? try XCTUnwrap(UIDevice.current.identifierForVendor?.uuidString) : "unit-fixture"
    let signature = AgentMcpJSONCodec.sha256(["target": .string(selection.targetId), "model": .string(selection.modelId),
      "effort": .string(selection.reasoningEffort.rawValue), "roster": .array([.string("solo:researcher")]),
      "device": .string(device)])
    let goal = phase == 1 ? objective : "Inspect a new fixture and check the original method's applicability."
    let protocolDigest = AgentMcpJSONCodec.sha256(["signature": .string(signature), "phase": .int(Int64(phase)),
      "goal": .string(goal), "previous_report_sha256": .string(previous), "retain_history": .bool(phase == 1)])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    let prior: ContinuityReport?
    if phase == 1 {
      guard previous.isEmpty else { throw failure }
      prior = nil
    } else {
      let seed = root.appendingPathComponent("phase-1", isDirectory: true)
      let bytes = try Data(contentsOf: seed.appendingPathComponent("report.json"))
      let saved = try decoder.decode(ContinuityReport.self, from: bytes)
      let original = try decoder.decode(ContinuityReservation.self,
        from: Data(contentsOf: seed.appendingPathComponent("reservation.json")))
      let archivedOriginal = try Data(contentsOf: seed.appendingPathComponent("original.json"))
      guard Self.digest(bytes) == previous, saved.reservation == original, original.phase == 1,
            original.signature == signature, saved.retained, saved.archiveComplete, saved.cleanupConfirmed,
            saved.pendingRemoteOwners.isEmpty, fs.fileExists(atPath: file.path),
            Self.digest(archivedOriginal) == saved.observerOriginalDigest,
            !requireFreshProcess || saved.runnerProcess != Self.runnerProcess else { throw failure }
      prior = saved
    }
    try fs.createDirectory(at: root, withIntermediateDirectories: true)
    // A reserved phase survives a failed test and cannot be retried against an uncertain workspace.
    try Data([1]).write(to: root.appendingPathComponent("phase-\(phase).reserved"), options: .withoutOverwriting)
    try fs.createDirectory(at: directory, withIntermediateDirectories: false)
    let run = "pilot-" + UUID().uuidString.lowercased()
    let reservation = ContinuityReservation(phase: phase, group: prior?.reservation.group ?? UUID().uuidString.lowercased(),
      run: run, turn: "turn-" + run, signature: signature, protocolDigest: protocolDigest, previousDigest: previous)
    try encoder.encode(reservation).write(to: directory.appendingPathComponent("reservation.json"), options: .atomic)
    if phase == 1 { try fs.createDirectory(at: work, withIntermediateDirectories: false) }
    let suite = Self.continuityStorageKey(root)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, storageKey: suite, secrets: secrets,
      executionStore: InMemoryAgentTeamExecutionStore(), fileURL: file)
    if let prior {
      let previousRun = try XCTUnwrap(history.snapshot(supervisorRunId: prior.reservation.run))
      guard previousRun.conversationId == reservation.group, previousRun.taskId == prior.reservation.turn,
            previousRun.state.isTerminal, previousRun.state.rawValue == prior.executionState else { throw failure }
    }
    let scope = AgentCollaborationToolEvidenceScope(runId: run, conversationId: reservation.group,
      turnId: reservation.turn, memberId: "solo", sourceId: run + "-source")
    var assignment = activeSnapshot(scope, stage: phase == 1 ? AgentSingleResearchCalibration.stage : nil)
    assignment.goal = goal
    guard history.upsert(assignment) else { throw failure }
    let reference: AgentCollaborationResearchReference
    if let prior {
      reference = prior.reference
    } else {
      let enrollment = try XCTUnwrap(AgentSingleResearchCalibration(format: AgentSingleResearchCalibration.format,
        scope: scope, selection: selection, objective: goal, maximumDispatches: 1))
      try history.enrollSingleResearchCalibration(enrollment)
      let receipt = try history.publishCollaborationMilestone(["mode": .string("publish"),
        "milestone_id": .string("candidate"), "artifact": .string(Self.method)], scope: scope)
      let row = try XCTUnwrap(receipt["references"]?.arrayValue?.first?.objectValue)
      reference = try decoder.decode(AgentCollaborationResearchReference.self,
        from: Data(AgentMcpJSONCodec.stringify(row).utf8))
    }
    let recall: AgentMcpJSONObject = ["mode": .string("workspace"),
      "object_id": .string(reference.objectId), "revision": .int(reference.revision),
      "sha256": .string(reference.sha256)]
    let page = try history.recallCollaborationOriginal(recall, scope: scope)
    var foreign = scope
    foreign.conversationId = UUID().uuidString
    XCTAssertThrowsError(try history.recallCollaborationOriginal(recall, scope: foreign))
    let content = page.string("content")
    guard page["sha256"] == .string(reference.sha256), page["next_offset"] == .null,
          content.contains("Missing input"), content.contains("Synthetic method, not learned") else { throw failure }
    let original = Data(content.utf8)
    let observerDigest = Self.digest(original)
    if let prior, prior.observerOriginalDigest != observerDigest { throw failure }
    try original.write(to: directory.appendingPathComponent("original.json"), options: .atomic)
    let settled = try XCTUnwrap(history.applyReply(supervisorRunId: run, source: scope.sourceId,
      conversation: reservation.group, turn: reservation.turn, task: scope.sourceId,
      contact: selection.targetId, content: "Synthetic continuity observation only.", success: phase == 2, now: 2))
    guard settled.state == (phase == 2 ? .succeeded : .failed) else { throw failure }
    let report = ContinuityReport(reservation: reservation, reference: reference, observerOriginalDigest: observerDigest,
      runnerProcess: Self.runnerProcess, retained: phase == 1, archiveComplete: true, cleanupConfirmed: true,
      pendingRemoteOwners: [], executionState: settled.state.rawValue,
      autonomousRetrievalProven: false, retainedLearningProven: false, freshProviderThreadVerified: false)
    let bytes = try encoder.encode(report)
    try bytes.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
    return Self.digest(bytes)
  }

  private static let runnerProcess = UUID().uuidString

  private func scope(run: String, turn: String) -> AgentCollaborationToolEvidenceScope {
    .init(runId: run, conversationId: "isolated-calibration", turnId: turn, memberId: "solo", sourceId: run + "-source")
  }

  private func definition(scope: AgentCollaborationToolEvidenceScope, research: Bool) -> AgentTeamDefinition {
    var context = ["_galaxyssi_member_model_id": selection.modelId,
      AgentCollaborationReasoningSelection.contextKey: selection.reasoningEffort.rawValue]
    if research { context["_galaxyssi_research_stage"] = AgentSingleResearchCalibration.stage }
    return .init(teamId: scope.runId + "-team", primaryAgentId: selection.targetId, members: [
      .init(agentId: selection.targetId, deliveryMode: .respond, requiredCapabilities: [], role: "Researcher",
        objective: objective.trimmingCharacters(in: .whitespacesAndNewlines), dependsOnAgentIds: [],
        context: context, instanceId: scope.memberId)
    ], visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: scope.memberId)
  }

  private func activeSnapshot(_ scope: AgentCollaborationToolEvidenceScope, stage: String?) -> AgentTeamExecutionSnapshot {
    .init(supervisorRunId: scope.runId, teamId: scope.runId + "-team", conversationId: scope.conversationId,
      taskId: scope.turnId, primaryAgentId: selection.targetId, goal: objective, state: .running,
      members: [.init(agentId: selection.targetId, deliveryMode: .respond, status: .running, instanceId: scope.memberId,
        sourceMessageId: scope.sourceId, dispatchCheckpoint: .dispatching, researchStage: stage)],
      createdAtMillis: 1, updatedAtMillis: 1, primaryInstanceId: scope.memberId)
  }

  private func makeFixture() throws -> Fixture {
    let suite = "single-research-" + UUID().uuidString
    return try Fixture(suite: suite, defaults: XCTUnwrap(UserDefaults(suiteName: suite)),
      root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }

  private struct Fixture {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let secrets = InMemorySecretStore()

    func history() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: InMemoryAgentTeamExecutionStore(), fileURL: root.appendingPathComponent("history.sqlite3"))
    }

    func database() throws -> AgentTeamHistoryDatabase {
      try AgentTeamHistoryDatabase(fileURL: root.appendingPathComponent("history.sqlite3"),
        storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    }

    func cleanup() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  private actor DispatchCounter {
    private(set) var count = 0
    private(set) var milestones: [AgentMcpJSONValue] = []
    func admit() throws {
      guard count == 0 else { throw AgentTeamHistoryDatabase.Failure.stale }
      count += 1
    }
    func archive(_ values: [AgentMcpJSONValue]) { milestones = values }
  }

  private static func deliveryReport(snapshot: AgentTeamExecutionSnapshot, dispatches: Int,
                                     archive: [AgentMcpJSONValue], originals: InterimPilotArchive) -> AgentMcpJSONObject {
    ["execution_mode": .string("single_agent_research"), "test_scope": .string("execution_delivery_only"),
     "status": .string(snapshot.hasSuccessfulOutput ? "single_agent_returned_goal_unverified" : "interrupted_or_failed"),
     "phone_dispatches": .int(Int64(dispatches)), "goal_verified_by_external_evaluator": .bool(false),
     "scientific_capability_gain_proven": .bool(false), "milestones": .array(archive),
     "milestone_archive_complete": .bool(originals.mayCleanUp), "interim_evidence": .object(originals.report)]
  }

  private static func acceptsDeliveryOnly(_ report: AgentMcpJSONObject) -> Bool {
    let archive = report["interim_evidence"]?.objectValue
    return report["execution_mode"] == .string("single_agent_research") &&
      report["test_scope"] == .string("execution_delivery_only") &&
      report["status"] == .string("single_agent_returned_goal_unverified") &&
      report["phone_dispatches"] == .int(1) && report["milestones"]?.arrayValue != nil &&
      report["milestone_archive_complete"] == .bool(true) &&
      archive?["format"] == .string("galaxyssi.adaptive-pilot-milestones.v1") &&
      archive?["capture_role"] == .string("test_observer_not_agent") &&
      archive?["milestones"]?.arrayValue != nil && archive?["peer_read_proven"] == .bool(false) &&
      archive?["scientific_acceptance_proven"] == .bool(false) &&
      report["goal_verified_by_external_evaluator"] == .bool(false) &&
      report["scientific_capability_gain_proven"] == .bool(false)
  }

  private static let method = """
  {"format":"galaxyssi.research-artifact.v1","summary":"Synthetic method, not learned",
   "workspace":[{"id":"inspection","base_revision":0,"kind":"workflow_method","title":"Synthetic method, not learned",
   "parents":[],"body":{"workflow_method":{"purpose":"Check an input","domain":"fixture","bottleneck":"stale data",
   "change_rationale":"Inspect before reuse","applies_when":"Input is readable","avoid_when":"Missing input",
   "risks":"Incomplete check","expected_gain":"Fewer stale results","falsifier":"A stale result is reused",
   "dimensions":["verification"],"roles":["analyst"],"inputs":["source"],"steps":[{"id":"inspect","role":"analyst",
   "stage":"EXECUTE","assignment":"Inspect the fixture before reuse","depends_on":[]}]}}}]}
  """
}

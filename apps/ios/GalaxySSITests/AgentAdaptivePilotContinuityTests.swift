import Darwin
import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentAdaptivePilotContinuityTests: XCTestCase {
  private static let process = UUID().uuidString
  private static let format = "galaxyssi.ios.adaptive-pilot-phase.v2"

  private struct Binding: Codable, Equatable {
    let member: String
    let target: String
    var model: String
    let effort: String
  }

  private struct Phase: Codable {
    let format: String
    var deviceModel: String
    let index: Int
    let objective: String
    let roster: [Binding]
    let replies: [String: String]
    let retainWorkspace: Bool
    var previousReportSHA256: String

    enum CodingKeys: String, CodingKey {
      case format, deviceModel = "device_model", index, objective, roster, replies, retainWorkspace, previousReportSHA256
    }
  }

  private struct DeviceBinding {
    let installation: String
    let actualModel: String
    let operatorModel: String?

    func require(_ phase: Phase) throws {
      guard !installation.isEmpty,
            phase.deviceModel.range(of: #"\A(?:iPhone|iPad|iPod)[0-9]{1,3},[0-9]{1,3}\z"#,
              options: .regularExpression) != nil,
            actualModel == phase.deviceModel, operatorModel == phase.deviceModel else { throw Failure.deviceMismatch }
    }
  }

  private struct Reservation: Codable, Equatable {
    let index: Int
    let group: String
    let run: String
    let turn: String
    let device: String
    let deviceModel: String
    let process: String
    let frozenPlanSHA256: String
    let previousReportSHA256: String
  }

  private struct Report: Codable {
    let reservation: Reservation
    let workspaceBeforeSHA256: String
    let workspaceAfterSHA256: String
    let executionSHA256: String
    let executionState: String
    let workspaceRetained: Bool
    let cleanupConfirmed: Bool
    var captureRole = "observer_only"
    var worker = "offline_fixture"
    var autonomousRetrievalProven = false
    var retainedLearningProven = false
    var freshProviderThreadVerified = false
  }

  private enum Failure: Error {
    case invalidPlan, deviceMismatch, invalidPredecessor, workspaceChanged, unconfirmedOutcome, cleanupFailed, fixtureFailure
  }

  private actor Dispatches {
    private var observed: Set<String> = []
    func admit(_ member: String) throws {
      guard observed.insert(member).inserted else { throw Failure.unconfirmedOutcome }
    }
    func matches(_ expected: Set<String>) -> Bool { observed == expected }
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private static func digest(_ data: Data) -> String { InterimPilotArchive.digest(data) }

  private static func read(_ url: URL, limit: Int = 8 * 1024 * 1024) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let bytes = try file.read(upToCount: limit + 1) ?? Data()
    guard bytes.count <= limit else { throw Failure.invalidPlan }
    return bytes
  }

  private static func decodePhase(_ bytes: Data) throws -> Phase {
    let keys: Set<String> = ["format", "device_model", "index", "objective", "roster", "replies",
      "retainWorkspace", "previousReportSHA256"]
    guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          Set(json.keys) == keys, json["format"] as? String == format else { throw Failure.invalidPlan }
    return try JSONDecoder().decode(Phase.self, from: bytes)
  }

  @MainActor private static func authorizedDevice(_ operatorModel: String?) throws -> DeviceBinding {
    #if targetEnvironment(simulator)
    throw Failure.deviceMismatch
    #else
    var hardware = utsname()
    guard uname(&hardware) == 0, let installation = UIDevice.current.identifierForVendor?.uuidString
    else { throw Failure.deviceMismatch }
    let actual = withUnsafeBytes(of: hardware.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    return .init(installation: installation, actualModel: actual, operatorModel: operatorModel)
    #endif
  }

  @MainActor func testOptInAdaptivePilotPhase() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let planPath = env["GALAXYSSI_ADAPTIVE_PILOT_PLAN"] else {
      throw XCTSkip("Set a frozen adaptive pilot phase file to opt in.")
    }
    let token = try XCTUnwrap(env["GALAXYSSI_ADAPTIVE_PILOT_TOKEN"].flatMap { UUID(uuidString: $0) })
    let bytes = try Self.read(URL(fileURLWithPath: planPath), limit: 128 * 1024)
    guard Self.digest(bytes) == env["GALAXYSSI_ADAPTIVE_PILOT_PLAN_SHA256"] else { throw Failure.invalidPlan }
    let device = try Self.authorizedDevice(env["GALAXYSSI_ADAPTIVE_PILOT_DEVICE_MODEL"])
    try device.require(Self.decodePhase(bytes))
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    let root = support.appendingPathComponent("XCTest-AdaptivePilot", isDirectory: true)
      .appendingPathComponent(token.uuidString.lowercased(), isDirectory: true)
    let secrets = AgentSingleResearchCalibrationTests.ContinuitySecrets(prefix: "adaptive:" + token.uuidString)
    let report = try await run(bytes, root: root, secrets: secrets, device: device, process: Self.process) {
      secrets.erase()
      return secrets.isErased
    }
    print("GALAXYSSI_ADAPTIVE_PILOT_REPORT_SHA256=\(report)")
  }

  @MainActor private func run(_ planBytes: Data, root: URL, secrets: GalaxySSISecretStore,
                              device: DeviceBinding, process: String, eraseSecrets: () -> Bool) async throws -> String {
    let fs = FileManager.default
    let decoder = JSONDecoder()
    let plan = try Self.decodePhase(planBytes)
    try device.require(plan)
    let ids = Set(plan.roster.map(\.member))
    func valid(_ value: String) -> Bool {
      !value.isEmpty && value.utf8.count <= 160 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard plan.format == Self.format, (1...100).contains(plan.index), (2...4).contains(plan.roster.count),
          ids.count == plan.roster.count, Set(plan.replies.keys).isSubset(of: ids),
          !plan.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, plan.objective.utf8.count <= 4_000,
          plan.roster.allSatisfy({ valid($0.member) && valid($0.target) && valid($0.model) &&
            AgentModelReasoningEffort(rawValue: $0.effort) != nil }),
          plan.replies.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 12_000 }) else { throw Failure.invalidPlan }
    let workspace = root.appendingPathComponent("workspace", isDirectory: true)
    let file = workspace.appendingPathComponent("history.sqlite3")
    let directory = root.appendingPathComponent("phase-\(plan.index)", isDirectory: true)
    let prior: Report?
    if plan.index == 1 {
      guard plan.previousReportSHA256.isEmpty, !fs.fileExists(atPath: workspace.path) else {
        throw Failure.invalidPredecessor
      }
      prior = nil
    } else {
      let previous = root.appendingPathComponent("phase-\(plan.index - 1)", isDirectory: true)
      let bytes = try Self.read(previous.appendingPathComponent("report.json"))
      let saved = try decoder.decode(Report.self, from: bytes)
      let reserved = try decoder.decode(Reservation.self,
        from: Self.read(root.appendingPathComponent("phase-\(plan.index - 1).reserved")))
      let frozen = try Self.read(previous.appendingPathComponent("plan.json"))
      let oldPlan = try Self.decodePhase(frozen)
      guard Self.digest(bytes) == plan.previousReportSHA256, saved.reservation == reserved,
            reserved.index == plan.index - 1, reserved.device == device.installation, reserved.process != process,
            reserved.deviceModel == plan.deviceModel, oldPlan.deviceModel == plan.deviceModel,
            reserved.frozenPlanSHA256 == Self.digest(frozen), oldPlan.roster == plan.roster,
            oldPlan.retainWorkspace, saved.workspaceRetained, saved.cleanupConfirmed,
            saved.captureRole == "observer_only", saved.worker == "offline_fixture",
            !saved.autonomousRetrievalProven, !saved.retainedLearningProven, !saved.freshProviderThreadVerified,
            fs.fileExists(atPath: file.path) else { throw Failure.invalidPredecessor }
      for (name, hash) in [("workspace-before.json", saved.workspaceBeforeSHA256),
                           ("workspace-after.json", saved.workspaceAfterSHA256), ("execution.json", saved.executionSHA256)] {
        guard try Self.digest(Self.read(previous.appendingPathComponent(name))) == hash else {
          throw Failure.invalidPredecessor
        }
      }
      prior = saved
    }
    try fs.createDirectory(at: root, withIntermediateDirectories: true)
    let reservation = Reservation(index: plan.index, group: prior?.reservation.group ?? UUID().uuidString,
      run: "pilot-" + UUID().uuidString, turn: "pilot-turn-" + UUID().uuidString, device: device.installation,
      deviceModel: plan.deviceModel, process: process,
      frozenPlanSHA256: Self.digest(planBytes), previousReportSHA256: plan.previousReportSHA256)
    // Reserve before opening SQLite. An interrupted writer cannot be replaced by a retry.
    try Self.encode(reservation).write(to: root.appendingPathComponent("phase-\(plan.index).reserved"),
      options: .withoutOverwriting)
    try fs.createDirectory(at: directory, withIntermediateDirectories: false)
    try planBytes.write(to: directory.appendingPathComponent("plan.json"), options: .atomic)
    if prior == nil { try fs.createDirectory(at: workspace, withIntermediateDirectories: false) }

    let suite = "adaptive-pilot:" + root.lastPathComponent
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let report = try await execute(plan, reservation: reservation, prior: prior, directory: directory, file: file,
      defaults: defaults, suite: suite, secrets: secrets)
    if !plan.retainWorkspace {
      try fs.removeItem(at: workspace)
      guard !fs.fileExists(atPath: workspace.path), eraseSecrets() else { throw Failure.cleanupFailed }
    }
    let bytes = try Self.encode(report)
    try bytes.write(to: directory.appendingPathComponent("report.json"), options: .atomic)
    return Self.digest(bytes)
  }

  @MainActor private func execute(_ plan: Phase, reservation: Reservation, prior: Report?, directory: URL, file: URL,
                                  defaults: UserDefaults, suite: String, secrets: GalaxySSISecretStore) async throws -> Report {
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, storageKey: suite, secrets: secrets,
      executionStore: InMemoryAgentTeamExecutionStore(), fileURL: file)
    let database = try AgentTeamHistoryDatabase(fileURL: file, storageKey: suite, secrets: secrets)
    let group = reservation.group
    let before = try Self.archive(database, group: group)
    if let prior {
      let old = try XCTUnwrap(history.snapshot(supervisorRunId: prior.reservation.run))
      guard old.conversationId == group, old.taskId == prior.reservation.turn,
            old.state.isTerminal, old.state.rawValue == prior.executionState,
            try Self.digest(Self.encode(old)) == prior.executionSHA256,
            Self.digest(before) == prior.workspaceAfterSHA256 else { throw Failure.workspaceChanged }
    }
    try before.write(to: directory.appendingPathComponent("workspace-before.json"), options: .atomic)
    let run = reservation.run
    let turn = reservation.turn
    let primary = try XCTUnwrap(plan.roster.first)
    let definition = AgentTeamDefinition(teamId: group, primaryAgentId: primary.target,
      members: plan.roster.map { binding in
        .init(agentId: binding.target, deliveryMode: binding.member == primary.member ? .respond : .observe,
          requiredCapabilities: [], role: binding.member, objective: plan.objective, dependsOnAgentIds: [],
          context: ["_galaxyssi_member_model_id": binding.model,
                    AgentCollaborationReasoningSelection.contextKey: binding.effort], instanceId: binding.member)
      }, visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: primary.member)
    let request = AgentRunRequest(conversationId: group, messageId: turn, taskId: turn,
      runId: run, parentRunId: "", goal: plan.objective, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: run, createdAtMillis: Int64(Date().timeIntervalSince1970 * 1_000))
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 4, maxConcurrency: 1))
    defer { runtime.close() }
    let dispatches = Dispatches()
    let handle = try runtime.start(definition: definition, request: request, worker: ClosureAgentTeamMemberWorker { context in
      guard let binding = plan.roster.first(where: { $0.member == context.member.memberId }),
            context.member.agentId == binding.target,
            context.request.context.string("_galaxyssi_member_model_id") == binding.model,
            context.request.context.string(AgentCollaborationReasoningSelection.contextKey) == binding.effort,
            context.request.goal == plan.objective else { throw Failure.unconfirmedOutcome }
      try await dispatches.admit(binding.member)
      guard let reply = plan.replies[binding.member] else { throw Failure.fixtureFailure }
      return AgentSubagentOutput(content: reply)
    })
    var snapshot = try await handle.wait()
    guard snapshot.state.isTerminal, snapshot.supervisorRunId == run, snapshot.taskId == turn,
          snapshot.conversationId == group, snapshot.members.count == plan.roster.count,
          await dispatches.matches(Set(plan.roster.map(\.member))) else {
      throw Failure.unconfirmedOutcome
    }
    for i in snapshot.members.indices {
      let member = snapshot.members[i].memberId
      snapshot.members[i].sourceMessageId = run + ":" + member
      if let reply = plan.replies[member] {
        guard snapshot.members[i].status == .succeeded, snapshot.members[i].output == reply else {
          throw Failure.unconfirmedOutcome
        }
        snapshot.members[i].replyContent = snapshot.members[i].output
      } else {
        guard snapshot.members[i].status == .failed else { throw Failure.unconfirmedOutcome }
      }
    }
    guard history.upsert(snapshot) else { throw Failure.unconfirmedOutcome }
    for member in snapshot.members where member.status == .succeeded {
      let scope = AgentCollaborationToolEvidenceScope(runId: run, conversationId: group,
        turnId: turn, memberId: member.memberId, sourceId: member.sourceMessageId)
      try history.publishSavedResearchReply(try XCTUnwrap(member.replyContent), scope: scope)
    }
    let after = try Self.archive(database, group: group)
    let persisted = try XCTUnwrap(history.snapshot(supervisorRunId: run))
    let execution = try Self.encode(persisted)
    try after.write(to: directory.appendingPathComponent("workspace-after.json"), options: .atomic)
    try execution.write(to: directory.appendingPathComponent("execution.json"), options: .atomic)
    return Report(reservation: reservation, workspaceBeforeSHA256: Self.digest(before),
      workspaceAfterSHA256: Self.digest(after), executionSHA256: Self.digest(execution),
      executionState: persisted.state.rawValue, workspaceRetained: plan.retainWorkspace, cleanupConfirmed: true)
  }

  private static func archive(_ db: AgentTeamHistoryDatabase, group: String) throws -> Data {
    try db.transaction {
      let rows = try db.researchObjectRevisions(conversationId: group, after: ("", 0), limit: 129)
      guard rows.count <= 128 else { throw Failure.workspaceChanged }
      var records: [Data] = []
      var bytes = 0
      for row in rows {
        let record = try XCTUnwrap(db.researchRecord(AgentCollaborationResearchRevision.self, conversationId: group,
          key: "object:" + row.objectID, revision: row.revision))
        var unhashed = record
        unhashed.reference.sha256 = ""
        guard record.reference.objectId == row.objectID, record.reference.revision == row.revision,
              try Self.digest(Self.encode(unhashed)) == record.reference.sha256 else { throw Failure.workspaceChanged }
        let original = try Self.encode(record)
        bytes += original.count
        guard bytes <= 4 * 1024 * 1024 else { throw Failure.workspaceChanged }
        records.append(original)
      }
      return try Self.encode(records)
    }
  }

  @MainActor func testFrozenDeviceMismatchDoesNotReserveOrCreateWorkspace() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let plan = Phase(format: Self.format, deviceModel: "iPhone17,1", index: 1, objective: "Inspect the fixture.",
      roster: [.init(member: "lead", target: "fixture:lead", model: "model", effort: "high"),
               .init(member: "review", target: "fixture:review", model: "model", effort: "high")],
      replies: [:], retainWorkspace: true, previousReportSHA256: "")
    let exact = DeviceBinding(installation: "fixture-installation", actualModel: "iPhone17,1", operatorModel: "iPhone17,1")
    XCTAssertNoThrow(try exact.require(plan))
    var wildcard = plan
    wildcard.deviceModel = "iPhone*"
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.encode(plan)) as? [String: Any])
    legacy["format"] = "galaxyssi.ios.adaptive-pilot-phase.v1"
    legacy.removeValue(forKey: "device_model")
    let cases: [(Data, DeviceBinding)] = [
      (try Self.encode(plan), .init(installation: "fixture", actualModel: "iPhone17,1", operatorModel: nil)),
      (try Self.encode(plan), .init(installation: "fixture", actualModel: "iPhone17,1", operatorModel: "iPhone17,2")),
      (try Self.encode(plan), .init(installation: "fixture", actualModel: "iPhone17,2", operatorModel: "iPhone17,1")),
      (try Self.encode(wildcard), .init(installation: "fixture", actualModel: "iPhone*", operatorModel: "iPhone*")),
      (try JSONSerialization.data(withJSONObject: legacy), exact)
    ]
    for (bytes, binding) in cases {
      do {
        _ = try await run(bytes, root: root, secrets: secrets, device: binding, process: "unauthorized") { true }
        XCTFail("An unbound phase was admitted.")
      } catch Failure.deviceMismatch {
      } catch Failure.invalidPlan {}
      XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
  }

  @MainActor func testFrozenPhasesKeepNegativeOutcomeAndOriginalWorkspace() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let roster = [Binding(member: "lead", target: "fixture:lead", model: "lead-model", effort: "high"),
                  Binding(member: "observer", target: "fixture:observer", model: "observer-model", effort: "low")]
    let original = #"{"format":"galaxyssi.research-artifact.v1","workspace":[{"id":"note","base_revision":0,"kind":"artifact","title":"Note","body":{"content":"Original negative condition"},"parents":[]}]}"#
    func phase(_ index: Int, previous: String = "", roster: [Binding]) -> Phase {
      Phase(format: Self.format, deviceModel: "iPhone17,1", index: index, objective: "Inspect fixture \(index).", roster: roster,
        replies: index == 1 ? ["observer": original] : ["lead": "New fixture.", "observer": "New observation."],
        retainWorkspace: index == 1, previousReportSHA256: previous)
    }
    func execute(_ plan: Phase, process: String, device: String = "fixture-device") async throws -> String {
      let binding = DeviceBinding(installation: device, actualModel: "iPhone17,1", operatorModel: "iPhone17,1")
      return try await run(Self.encode(plan), root: root, secrets: secrets, device: binding, process: process) { true }
    }
    func reject(_ plan: Phase, process: String, device: String = "fixture-device") async {
      do {
        _ = try await execute(plan, process: process, device: device)
        XCTFail("Invalid phase was admitted.")
      } catch {}
    }
    await reject(phase(2, roster: roster), process: "early")
    let first = phase(1, roster: roster)
    let digest = try await execute(first, process: "first")
    await reject(first, process: "duplicate")
    let second = phase(2, previous: digest, roster: roster)
    await reject(second, process: "first")
    await reject(second, process: "second", device: "different-device")
    var changed = roster
    changed[1].model = "changed-model"
    await reject(phase(2, previous: digest, roster: changed), process: "second")
    await reject(phase(2, previous: String(repeating: "0", count: 64), roster: roster), process: "second")
    let archive = root.appendingPathComponent("phase-1/workspace-after.json")
    let preserved = try Self.read(archive)
    try Data("[]".utf8).write(to: archive, options: .atomic)
    await reject(second, process: "second")
    try preserved.write(to: archive, options: .atomic)
    _ = try await execute(second, process: "second")
    let decoder = JSONDecoder()
    let seed = try decoder.decode(Report.self, from: Self.read(root.appendingPathComponent("phase-1/report.json")))
    let follow = try decoder.decode(Report.self, from: Self.read(root.appendingPathComponent("phase-2/report.json")))
    XCTAssertEqual(seed.executionState, AgentTeamExecutionState.completedWithFailures.rawValue)
    XCTAssertEqual(follow.executionState, AgentTeamExecutionState.succeeded.rawValue)
    XCTAssertNotEqual(seed.workspaceBeforeSHA256, seed.workspaceAfterSHA256)
    XCTAssertEqual(seed.workspaceAfterSHA256, follow.workspaceBeforeSHA256)
    XCTAssertEqual(seed.reservation.group, follow.reservation.group)
    XCTAssertEqual(seed.reservation.deviceModel, "iPhone17,1")
    XCTAssertEqual(seed.reservation.deviceModel, follow.reservation.deviceModel)
    XCTAssertNotEqual(seed.reservation.run, follow.reservation.run)
    XCTAssertNotEqual(seed.reservation.turn, follow.reservation.turn)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("workspace").path))
    await reject(phase(3, previous: try Self.digest(Self.read(root.appendingPathComponent("phase-2/report.json"))),
      roster: roster), process: "third")
  }
}

import Darwin
import XCTest
@testable import GalaxySSI

final class AgentRemotePilotSelectionTests: XCTestCase {
  private typealias Pilot = AgentRemotePilotProtocol
  private static let title = "Remote pilot model selection"
  private static let prefix = "pilot-selection-"

  private struct SelectionReceipt: Codable {
    var source = "app_conversation_snapshot"
    let conversation: String
    let profile: String
    let createdAt: Int64
    let selection: AgentModelSelection

    func permitsCleanup(report: Pilot.Report, protocolSHA: String) -> Bool {
      source == "app_conversation_snapshot" && conversation.hasPrefix(AgentRemotePilotSelectionTests.prefix) &&
        report.protocolSHA256 == protocolSHA && report.toolScope == Pilot.toolScope &&
        report.selectionConversation == conversation && report.selection == selection &&
        (2...32).contains(report.slots.count) && Set(report.slots.map(\.slot)).count == report.slots.count &&
        report.slots.allSatisfy {
          ["completed", "failed"].contains($0.state) && $0.remoteCleanupConfirmed &&
            $0.stopRequestedAtMillis != nil && $0.cleanupAtMillis != nil
        }
    }
  }

  func testCleanupRequiresExactSelectionAndEveryConfirmedStop() throws {
    let selection = AgentModelSelection(mode: .manual, targetId: "paired:codex", modelId: "fixture-model", reasoningEffort: .high)
    let receipt = SelectionReceipt(conversation: "pilot-selection-fixture", profile: "fixture", createdAt: 1, selection: selection)
    let protocolSHA = String(repeating: "a", count: 64)
    var report = Pilot.Report(protocolSHA256: protocolSHA, selection: selection, selectionConversation: receipt.conversation,
      toolScope: Pilot.toolScope, slots: [
        .init(slot: "single", caseID: "case", arm: .single, identity: .fresh()),
        .init(slot: "team", caseID: "case", arm: .team, identity: .fresh())
      ])
    for index in report.slots.indices {
      report.slots[index].state = "completed"
      report.slots[index].remoteCleanupConfirmed = true
      report.slots[index].stopRequestedAtMillis = 2
      report.slots[index].cleanupAtMillis = 3
    }
    XCTAssertTrue(receipt.permitsCleanup(report: report, protocolSHA: protocolSHA))
    XCTAssertFalse(receipt.permitsCleanup(report: report, protocolSHA: String(repeating: "b", count: 64)))
    let changedConversation = Pilot.Report(protocolSHA256: protocolSHA, selection: selection,
      selectionConversation: "ordinary-conversation", toolScope: Pilot.toolScope, slots: report.slots)
    XCTAssertFalse(receipt.permitsCleanup(report: changedConversation, protocolSHA: protocolSHA))
    var changedSelection = selection
    changedSelection.reasoningEffort = .low
    let changedModel = Pilot.Report(protocolSHA256: protocolSHA, selection: changedSelection,
      selectionConversation: receipt.conversation, toolScope: Pilot.toolScope, slots: report.slots)
    XCTAssertFalse(receipt.permitsCleanup(report: changedModel, protocolSHA: protocolSHA))
    report.slots[1].state = "started"
    XCTAssertFalse(receipt.permitsCleanup(report: report, protocolSHA: protocolSHA))
    report.slots[1].state = "completed"
    report.slots[1].remoteCleanupConfirmed = false
    XCTAssertFalse(receipt.permitsCleanup(report: report, protocolSHA: protocolSHA))
    report.slots[1].remoteCleanupConfirmed = true
    report.slots[1].stopRequestedAtMillis = nil
    XCTAssertFalse(receipt.permitsCleanup(report: report, protocolSHA: protocolSHA))
  }

  #if DEBUG
  @MainActor
  func testOptInPrepareRemotePilotSelectionWithoutDispatch() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_REMOTE_PILOT_PREPARE_SELECTION"] == "1" else { throw XCTSkip("Selection preparation is opt-in") }
    let store = try await authorizedStore(env)
    let target = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_TARGET"])
    let model = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_MODEL"])
    let effort = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_EFFORT"].flatMap(AgentModelReasoningEffort.init(rawValue:)))
    guard target.hasSuffix(":codex"), !model.isBlank, model.count <= 120, effort != .automatic,
          let contact = store.contact(id: target), contact.id == target, contact.trustState == .verified,
          contact.connectorAgentId == "codex", contact.deliveryMode.isGalaxySSILinkFamily,
          store.serverLinks.filter({ $0.paired && $0.desktopId == contact.desktopId }).count == 1,
          let invocation = AgentCollaborationReasoningSelection.rosterInvocation(model: model, effort: effort.rawValue,
            adapter: contact.connectorAdapterName, profile: contact.connectorInvocationProfile),
          invocation["model_id"] == model, invocation["reasoning_effort"] == effort.rawValue
    else { throw Pilot.Failure.selection }
    let file = try selectionFile(env)
    let folder = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let reservation = file.appendingPathExtension("reserved")
    try Data().write(to: reservation, options: .withoutOverwriting)
    guard !FileManager.default.fileExists(atPath: file.path) else { throw Pilot.Failure.selection }
    let id = Self.prefix + UUID().uuidString.lowercased()
    let now = AgentControlPlaneClock.nowMillis()
    let active = store.activeAgentConversationId, defaults = modelDefaults(store.defaults)
    guard store.agentConversationDatabase.confirmsAbsent(id),
          store.agentConversationDatabase.upsert(.init(id: id, title: Self.title, createdAt: now, updatedAt: now,
            status: .archived, createdByAgent: true)) else { throw Pilot.Failure.selection }
    do {
      AgentModelSelectionSettings.selectManual(for: id, targetId: target, modelId: model, displayName: contact.displayName,
        reasoningEffort: effort, rememberAsDefault: false, defaults: store.defaults)
      let saved = AgentModelSelectionSettings.selection(for: id, defaults: store.defaults)
      guard saved.mode == .manual, saved.targetId == target, saved.modelId == model, saved.reasoningEffort == effort,
            store.defaults.synchronize(), store.activeAgentConversationId == active,
            defaults == modelDefaults(store.defaults) else { throw Pilot.Failure.selection }
      let receipt = SelectionReceipt(conversation: id, profile: store.profile.identityFingerprint,
        createdAt: now, selection: saved)
      let bytes = try JSONEncoder().encode(receipt)
      try bytes.write(to: file, options: .withoutOverwriting)
      let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
      attachment.name = "Prepared remote pilot selection"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      _ = store.deleteAgentSession(id: id)
      throw error
    }
  }

  @MainActor
  func testOptInRemoveOnlySettledRemotePilotSelection() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_REMOTE_PILOT_CLEANUP_SELECTION"] == "1" else { throw XCTSkip("Selection cleanup is opt-in") }
    let store = try await authorizedStore(env)
    let receipt = try JSONDecoder().decode(SelectionReceipt.self, from: read(selectionFile(env), limit: 16_000))
    let pilot = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_ID"])
    guard Pilot.identifier(pilot) else { throw Pilot.Failure.scope }
    let reportURL = try root().appendingPathComponent(pilot, isDirectory: true).appendingPathComponent("report.json")
    let bytes = try read(reportURL, limit: 512_000)
    guard Pilot.digest(bytes) == env["GALAXYSSI_REMOTE_PILOT_REPORT_SHA256"],
          let protocolSHA = env["GALAXYSSI_REMOTE_PILOT_SHA256"] else { throw Pilot.Failure.cleanup }
    let report = try JSONDecoder().decode(Pilot.Report.self, from: bytes)
    let id = receipt.conversation, active = store.activeAgentConversationId
    let defaults = modelDefaults(store.defaults)
    let transcript = UserDefaultsAgentTranscriptEntryStore(defaults: store.defaults, secrets: store.secrets)
    guard receipt.profile == store.profile.identityFingerprint, receipt.permitsCleanup(report: report, protocolSHA: protocolSHA),
          id != active, let conversation = store.agentConversationDatabase.read(id),
          conversation.title == Self.title, conversation.createdAt == receipt.createdAt, conversation.createdByAgent,
          conversation.status == .archived, conversation.collaborationRoster == nil, !conversation.pinned,
          AgentModelSelectionSettings.selection(for: id, defaults: store.defaults) == receipt.selection,
          transcript.listConversationPage(conversationId: id, beforeSequenceExclusive: nil, pageSize: 1).entries.isEmpty,
          store.chatHistoryDatabase.latestMessage(conversationId: id) == nil,
          store.agentTasks(forSession: id, limit: 1).isEmpty else { throw Pilot.Failure.cleanup }
    guard store.deleteAgentSession(id: id), store.agentConversationDatabase.confirmsAbsent(id),
          store.defaults.synchronize(), store.activeAgentConversationId == active,
          defaults == modelDefaults(store.defaults) else { throw Pilot.Failure.cleanup }
  }

  @MainActor
  private func authorizedStore(_ env: [String: String]) async throws -> GalaxySSIStore {
    #if targetEnvironment(simulator)
    throw Pilot.Failure.scope
    #else
    var machine = utsname()
    guard uname(&machine) == 0 else { throw Pilot.Failure.scope }
    let model = withUnsafeBytes(of: machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    guard !model.isEmpty, model == env["GALAXYSSI_REMOTE_PILOT_DEVICE_MODEL"] else { throw Pilot.Failure.scope }
    let deadline = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
    while MessageCoordinator.activeRemotePilotCoordinator == nil, DispatchTime.now().uptimeNanoseconds < deadline {
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    return try XCTUnwrap(MessageCoordinator.activeRemotePilotCoordinator).store
    #endif
  }

  private func selectionFile(_ env: [String: String]) throws -> URL {
    let name = try XCTUnwrap(env["GALAXYSSI_REMOTE_PILOT_SELECTION_RECEIPT"])
    guard Pilot.identifier(name) else { throw Pilot.Failure.scope }
    return try root().appendingPathComponent("selection-" + name + ".json")
  }

  private func root() throws -> URL {
    try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
      .appendingPathComponent("XCTest-AppSelectedRemotePilot", isDirectory: true)
  }

  private func read(_ file: URL, limit: Int) throws -> Data {
    let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard metadata.isRegularFile == true, metadata.isSymbolicLink == false,
          let size = metadata.fileSize, (1...limit).contains(size) else { throw Pilot.Failure.scope }
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    let bytes = try input.read(upToCount: limit + 1) ?? Data()
    guard bytes.count == size else { throw Pilot.Failure.scope }
    return bytes
  }

  private func modelDefaults(_ defaults: UserDefaults) -> NSDictionary {
    NSDictionary(dictionary: defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("default.") })
  }
  #endif
}

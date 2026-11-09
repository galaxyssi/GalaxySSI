import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

extension FrozenPilot {
  static let recoveredFormat = "galaxyssi.ios.remote-pilot-candidate.v2"

  // Android's name-based UUID uses MD5. This reproduces an ID, not an integrity check.
  static func androidSourceID(_ key: String) -> Int64 {
    var bytes = Array(Insecure.MD5.hash(data: Data("galaxyssi-agent-team-response\u{001f}member:\(key)".utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    func word(_ start: Int) -> UInt64 { bytes[start..<(start + 8)].reduce(0) { ($0 << 8) | UInt64($1) } }
    let namespace: UInt64 = 1 << 62
    return Int64(((word(0) ^ word(8)) & (namespace - 1)) | namespace)
  }

  static func recoverCompletedReport(protocolBytes: Data, protocolSHA256: String, reportBytes: Data,
      reportSHA256: String, authorizedDispatches: Int) throws -> [Payload] {
    guard (1...512_000).contains(protocolBytes.count), (1...2_000_000).contains(reportBytes.count),
          digest(protocolBytes) == protocolSHA256, digest(reportBytes) == reportSHA256 else { throw Failure.integrity }
    let decoder = JSONDecoder()
    let plan = try decoder.decode(AgentMcpJSONObject.self, from: protocolBytes)
    let report = try decoder.decode(AgentMcpJSONObject.self, from: reportBytes)
    // Require a real empty JSON array; the shared MCP value decoder tolerates some malformed collections.
    guard let rawReport = try JSONSerialization.jsonObject(with: reportBytes) as? [String: Any],
          let rawOutcomes = rawReport["slots"] as? [[String: Any]],
          rawOutcomes.allSatisfy({ ($0["pending_remote_owners"] as? [Any])?.isEmpty == true })
    else { throw Failure.source }
    let planKeys: Set<String> = ["format", "pilot_id", "target_id", "model_id", "reasoning_effort",
      "tool_scope", "trial_timeout_ms", "slots"]
    let pilot = try text(plan, "pilot_id"), target = try text(plan, "target_id")
    let model = try text(plan, "model_id"), effort = try text(plan, "reasoning_effort")
    guard Set(plan.keys) == planKeys, plan["format"] == .string("galaxyssi.remote-collaboration-pilot.v1"),
          plan["tool_scope"] == .string("production_tools_not_isolated"),
          target.hasSuffix(":codex"), target.utf8.count <= 256, !model.isBlank,
          let level = AgentModelReasoningEffort(rawValue: effort), level != .automatic,
          case .int(let timeout)? = plan["trial_timeout_ms"], (60_000...900_000).contains(timeout),
          let slots = plan["slots"]?.arrayValue, (2...32).contains(slots.count), slots.count * 3 <= authorizedDispatches,
          report["format"] == .string("galaxyssi.remote-pilot-report.v1"), report["finished"] == .bool(true),
          report["pilot_id"] == .string(pilot), report["protocol_sha256"] == .string(protocolSHA256),
          report["selection_source"] == .string("app_conversation_snapshot"),
          !(try text(report, "selection_conversation_id")).isBlank,
          let selection = report["model_selection"]?.objectValue,
          selection["requested_model"] == .string(model), selection["requested_reasoning_effort"] == .string(effort),
          let outcomes = report["slots"]?.arrayValue, outcomes.count == slots.count else { throw Failure.source }
    var assigned = Set<String>(), identities = Set<String>()
    var pairs: [String: [(String, Data)]] = [:]
    var artifacts: [Payload] = []
    for (slotValue, outcomeValue) in zip(slots, outcomes) {
      guard let slot = slotValue.objectValue, Set(slot.keys) == ["id", "case_id", "arm", "prompt"],
            let outcome = outcomeValue.objectValue,
            ["id", "case_id", "arm"].allSatisfy({ outcome[$0] == slot[$0] }) else { throw Failure.source }
      let id = try text(slot, "id"), caseID = try text(slot, "case_id"), arm = try text(slot, "arm")
      let prompt = try text(slot, "prompt")
      let run = "remote-pilot-" + pilot + "-" + id
      let identity = Identity(run: run, conversation: try text(outcome, "conversation_id"),
        turn: "turn-" + run, task: "task-" + run)
      let binding = Binding(source: .init(pilot: pilot, identity: identity, protocolSHA256: protocolSHA256,
        goalSHA256: digest(Data(prompt.utf8)), target: target, model: model, effort: effort),
        slot: id, caseID: caseID, arm: arm)
      _ = try binding.artifactID()
      guard assigned.insert(id).inserted, !prompt.isBlank, prompt.utf8.count <= 12_000,
            !identity.conversation.isBlank, identities.insert(identity.conversation).inserted,
            outcome["run_id"] == .string(run), outcome["turn_id"] == .string(identity.turn),
            outcome["status"] == .string("completed"), outcome["state"] == .string("SUCCEEDED"),
            outcome["result_truncated"] == .bool(false), outcome["cleanup_confirmed"] == .bool(true),
            outcome["durable_control"] == .string("STOP"), outcome["pending_remote_owners"]?.arrayValue == [],
            let members = outcome["members"]?.arrayValue, members.count == nodes.count,
            let dispatches = outcome["phone_dispatches"]?.arrayValue, dispatches.count == nodes.count
      else { throw Failure.source }
      pairs[caseID, default: []].append((arm, Data(prompt.utf8)))
      let final = try text(outcome, "final_output")
      var outputs: [Output] = [], receipts: [Dispatch] = []
      for (index, node) in nodes.enumerated() {
        let person = binding.person(for: node)
        guard let member = members[index].objectValue, member["node"] == .string(node),
              member["person_id"] == .string(person), member["status"] == .string("SUCCEEDED"),
              member["error"] == .string(""), let dispatch = dispatches[index].objectValue
        else { throw Failure.dispatch }
        let fields = ["node_id": node, "person_id": person, "transport_instance_id": person,
          "parent_run_id": run, "turn_id": identity.turn, "conversation_id": identity.conversation, "task_id": identity.task,
          "target_id": target, "requested_model": model, "requested_reasoning_effort": effort,
          "accounting_scope": "phone_delegate_dispatch_not_provider_request"]
        guard fields.allSatisfy({ dispatch[$0.key] == .string($0.value) }),
              case .int(let sourceID)? = dispatch["source_message_id"] else { throw Failure.dispatch }
        let output = try text(member, "output")
        outputs.append(.init(node: node, text: output))
        receipts.append(.init(node: node, person: person, identity: identity,
          child: try text(dispatch, "owner_run_id"), key: try text(dispatch, "idempotency_key"), target: target,
          model: model, effort: effort, promptSHA256: try text(dispatch, "prepared_prompt_sha256"),
          returnedOutputSHA256: digest(Data(output.utf8)), androidSourceMessageID: sourceID))
      }
      let artifact = Payload(format: recoveredFormat, binding: binding, finalOutput: final,
        finalOutputSHA256: digest(Data(final.utf8)), outputs: outputs, dispatches: receipts,
        reportRecovery: .init(reportSHA256: reportSHA256))
      try artifact.validate(expected: binding)
      artifacts.append(artifact)
    }
    guard pairs.values.allSatisfy({ pair in
      pair.count == 2 && Set(pair.map { $0.0 }) == ["single", "team"] && pair[0].1 == pair[1].1
    }) else { throw Failure.source }
    return artifacts
  }

  private static func text(_ value: AgentMcpJSONObject, _ key: String) throws -> String {
    guard case .string(let result)? = value[key] else { throw Failure.source }
    return result
  }
}

final class AgentPilotReportRecoveryTests: XCTestCase {
  private typealias Pilot = FrozenPilot
  private let finalText = "  Exact method.\n\n"

  private struct RecoveryReceipt: Encodable {
    struct Candidate: Encodable {
      let locator: Pilot.Locator
      let finalOutputSHA256: String
    }
    let format = "galaxyssi.ios.pilot-report-recovery.v1"
    let reportSHA256: String
    let protocolSHA256: String
    let trust = "unverified_candidate"
    let providerAttested = false
    let modelCalls = 0
    let sources: [Candidate]
  }

  func testPinnedReportReopensExactEncryptedCandidateAndRejectsConflicts() throws {
    let (plan, report) = try fixture()
    let artifacts = try recover(plan, report)
    XCTAssertEqual(Pilot.androidSourceID("run:draft"), 6_979_664_516_405_962_813)
    XCTAssertEqual(artifacts.count, 2)
    XCTAssertEqual(artifacts.last?.dispatches.map(\.person), ["analyst", "reviewer", "analyst"])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let store = Pilot.Store(directory: root, secrets: secrets, account: "report-recovery-test")
    let original = try XCTUnwrap(artifacts.last)
    let reference = try store.freeze(original)
    let reopened = try Pilot.Store(directory: root, secrets: secrets, account: "report-recovery-test")
      .read(expected: original.binding, reference: reference)
    XCTAssertEqual(Data(reopened.finalOutput.utf8), Data(finalText.utf8))
    XCTAssertEqual(reopened.reportRecovery?.reportSHA256, Pilot.digest(report))
    XCTAssertEqual(reopened.reportRecovery?.providerAttested, false)
    XCTAssertEqual(try store.freeze(original), reference)
    var conflicting = original
    conflicting.reportRecovery = .init(reportSHA256: String(repeating: "b", count: 64))
    XCTAssertThrowsError(try store.freeze(conflicting))
    XCTAssertThrowsError(try Pilot.recoverCompletedReport(protocolBytes: plan, protocolSHA256: Pilot.digest(plan),
      reportBytes: report, reportSHA256: String(repeating: "c", count: 64), authorizedDispatches: 6))
  }

  func testReportRecoveryRejectsUnsettledTruncatedOrMisattributedSlots() throws {
    let (plan, report) = try fixture()
    XCTAssertThrowsError(try recover(plan, report, budget: 5))
    var source = try JSONDecoder().decode(AgentMcpJSONObject.self, from: report)
    let slots = try XCTUnwrap(source["slots"]?.arrayValue)
    let first = try XCTUnwrap(slots.first?.objectValue)
    let invalid: [(String, AgentMcpJSONValue)] = [
      ("cleanup_confirmed", .bool(false)), ("durable_control", .string("RUN")), ("result_truncated", .bool(true)),
      ("pending_remote_owners", .array([.string("pending")])), ("state", .string("FAILED")),
      ("final_output", .string(finalText.trimmingCharacters(in: .whitespacesAndNewlines))), ("arm", .string("team"))
    ]
    for (key, value) in invalid {
      var changed = first
      changed[key] = value
      source["slots"] = .array([.object(changed)] + Array(slots.dropFirst()))
      XCTAssertThrowsError(try recover(plan, Pilot.encode(source)), key)
    }
    var changed = first
    var dispatches = try XCTUnwrap(first["phone_dispatches"]?.arrayValue)
    var dispatch = try XCTUnwrap(dispatches.first?.objectValue)
    dispatch["source_message_id"] = .int(7)
    dispatches[0] = .object(dispatch)
    changed["phone_dispatches"] = .array(dispatches)
    source["slots"] = .array([.object(changed)] + Array(slots.dropFirst()))
    XCTAssertThrowsError(try recover(plan, Pilot.encode(source)))
  }

  func testOptInRecoverCompletedAndroidPilotReport() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_PILOT_REPORT_RECOVERY"] == "1" else { throw XCTSkip("Report recovery is opt-in") }
    func bytes(_ variable: String, limit: Int) throws -> Data {
      try Pilot.boundedRead(URL(fileURLWithPath: XCTUnwrap(env[variable])), limit: limit)
    }
    let plan = try bytes("GALAXYSSI_PILOT_REPORT_PROTOCOL", limit: 512_000)
    let report = try bytes("GALAXYSSI_PILOT_REPORT_INPUT", limit: 2_000_000)
    let protocolSHA = try XCTUnwrap(env["GALAXYSSI_PILOT_REPORT_PROTOCOL_SHA256"])
    let reportSHA = try XCTUnwrap(env["GALAXYSSI_PILOT_REPORT_SHA256"])
    let budget = try XCTUnwrap(env["GALAXYSSI_PILOT_REPORT_MAX_DISPATCHES"].flatMap(Int.init))
    let candidates = try Pilot.recoverCompletedReport(protocolBytes: plan, protocolSHA256: protocolSHA,
      reportBytes: report, reportSHA256: reportSHA, authorizedDispatches: budget)
    let pilot = try XCTUnwrap(candidates.first?.binding.source.pilot)
    let folder = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
      .appendingPathComponent("XCTest-FrozenPilotArtifacts", isDirectory: true)
      .appendingPathComponent(pilot, isDirectory: true)
    let store = Pilot.Store(directory: folder, secrets: KeychainSecretStore.shared, account: "xc-test-frozen-pilot:" + pilot)
    var sources: [RecoveryReceipt.Candidate] = []
    for candidate in candidates {
      let reference = try store.freeze(candidate)
      let saved = try store.read(expected: candidate.binding, reference: reference)
      XCTAssertEqual(Data(saved.finalOutput.utf8), Data(candidate.finalOutput.utf8))
      let locator = Pilot.Locator(binding: candidate.binding, reference: reference)
      sources.append(.init(locator: locator, finalOutputSHA256: saved.finalOutputSHA256))
      let receipt = XCTAttachment(data: try Pilot.encode(locator), uniformTypeIdentifier: "public.json")
      receipt.name = "Recovered candidate " + candidate.binding.slot
      receipt.lifetime = .keepAlways
      add(receipt)
    }
    let summary = RecoveryReceipt(reportSHA256: reportSHA, protocolSHA256: protocolSHA, sources: sources)
    let receipt = XCTAttachment(data: try Pilot.encode(summary), uniformTypeIdentifier: "public.json")
    receipt.name = "Completed pilot report recovery"
    receipt.lifetime = .keepAlways
    add(receipt)
  }

  private func recover(_ plan: Data, _ report: Data, budget: Int = 6) throws -> [Pilot.Payload] {
    try Pilot.recoverCompletedReport(protocolBytes: plan, protocolSHA256: Pilot.digest(plan),
      reportBytes: report, reportSHA256: Pilot.digest(report), authorizedDispatches: budget)
  }

  private func fixture() throws -> (Data, Data) {
    let plan = Data("""
      {"format":"galaxyssi.remote-collaboration-pilot.v1","pilot_id":"fixture","target_id":"fixture:codex",
       "model_id":"fixture-model","reasoning_effort":"high","tool_scope":"production_tools_not_isolated",
       "trial_timeout_ms":60000,"slots":[{"id":"single","case_id":"case","arm":"single","prompt":"Same task"},
       {"id":"team","case_id":"case","arm":"team","prompt":"Same task"}]}
      """.utf8)
    let slots = ["single", "team"].map { arm -> AgentMcpJSONValue in
      let run = "remote-pilot-fixture-" + arm, conversation = "group-" + arm
      var members: [AgentMcpJSONValue] = [], dispatches: [AgentMcpJSONValue] = []
      for node in Pilot.nodes {
        let person = arm == "team" && node == "review" ? "reviewer" : "analyst"
        let key = run + ":" + node
        members.append(.object(["node": .string(node), "person_id": .string(person), "status": .string("SUCCEEDED"),
          "error": .string(""), "output": .string(node == "final" ? finalText : "Prior " + node)]))
        dispatches.append(.object(["node_id": .string(node), "person_id": .string(person),
          "transport_instance_id": .string(person), "parent_run_id": .string(run), "turn_id": .string("turn-" + run),
          "conversation_id": .string(conversation), "task_id": .string("task-" + run), "target_id": .string("fixture:codex"),
          "requested_model": .string("fixture-model"), "requested_reasoning_effort": .string("high"),
          "owner_run_id": .string("child-" + key), "idempotency_key": .string(key), "source_message_id": .int(Pilot.androidSourceID(key)),
          "prepared_prompt_sha256": .string(String(repeating: "a", count: 64)),
          "accounting_scope": .string("phone_delegate_dispatch_not_provider_request")]))
      }
      return .object(["id": .string(arm), "case_id": .string("case"), "arm": .string(arm), "status": .string("completed"),
        "state": .string("SUCCEEDED"), "result_truncated": .bool(false), "cleanup_confirmed": .bool(true),
        "durable_control": .string("STOP"), "pending_remote_owners": .array([]), "run_id": .string(run),
        "turn_id": .string("turn-" + run), "conversation_id": .string(conversation), "final_output": .string(finalText),
        "members": .array(members), "phone_dispatches": .array(dispatches)])
    }
    let report: AgentMcpJSONObject = ["format": .string("galaxyssi.remote-pilot-report.v1"), "finished": .bool(true),
      "pilot_id": .string("fixture"), "protocol_sha256": .string(Pilot.digest(plan)), "selection_source": .string("app_conversation_snapshot"),
      "selection_conversation_id": .string("selected"), "model_selection": .object(["requested_model": .string("fixture-model"),
        "requested_reasoning_effort": .string("high")]), "slots": .array(slots)]
    return (plan, try Pilot.encode(report))
  }
}

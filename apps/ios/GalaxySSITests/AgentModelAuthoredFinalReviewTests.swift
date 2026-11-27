import XCTest
@testable import GalaxySSI

private actor SyntheticAuthoredReviewWire {
  let count: Int
  private var requests: [String] = []
  init(_ count: Int) { self.count = count }
  func ask(_ system: String, _ prompt: String) throws -> String {
    requests.append(prompt)
    let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(prompt.utf8))
    switch input["stage"] {
    case .string("plan"):
      return AgentMcpJSONCodec.stringify(["roles": .array((0..<count).map { .string("Model-chosen assignment \($0 + 1)") }),
        "synthesis": .string("Compare actual findings"), "final_review": .string("Audit the actual draft against the supplied schedules")])
    case .string("role"):
      let id = input["id"]?.strictStringValue ?? ""
      return AgentMcpJSONCodec.stringify(["finding": .string("Actual finding from " + id), "dissent": .string("Reservation from " + id)])
    case .string("synthesis"): return #"{"answer":"The actual unreviewed schedule draft"}"#
    case .string("audit"):
      return #"{"verdict":"revise","objection":"A schedule constraint was omitted","answer":"The independently corrected schedule"}"#
    default: throw AgentConversationalTeamProtocol.Failure.stalled
    }
  }
  func inputs() -> [String] { requests }
}

@MainActor
final class AgentModelAuthoredFinalReviewTests: XCTestCase {
  private let wire = AgentTeamPlanWire(constrained: false, finalReview: true)
  private func plan(_ roles: [AgentMcpJSONValue], final: AgentMcpJSONValue? = .string("Review the completed draft")) -> String {
    var root: AgentMcpJSONObject = ["roles": .array(roles), "synthesis": .string("Compare findings")]
    root["final_review"] = final
    return AgentMcpJSONCodec.stringify(root)
  }
  func testModelAuthoredBriefBecomesOneAllocatedIndependentFinalEditor() throws {
    let canonical = try wire.decode(plan([.string("Compare the schedules")]))
    let parsed = try AgentConversationalTeamProtocol.plan(canonical)
    XCTAssertEqual(parsed.roles.count, 2)
    XCTAssertEqual(parsed.roles[0].assignment, "Compare the schedules")
    XCTAssertEqual(parsed.finalEditor?.assignment, "Review the completed draft")
    XCTAssertEqual(parsed.finalEditor?.parents, [])
    XCTAssertEqual(parsed.finalEditor?.id, "role2")
  }
  func testTypedContributorsKeepTheirOwnGraphBeforeTheDedicatedEditor() throws {
    let roles: [AgentMcpJSONValue] = [
      .object(["kind": .string("WORK"), "parents": .array([]), "task": .string("Count")]),
      .object(["kind": .string("REVIEW"), "parents": .array([.int(1)]), "task": .string("Check counts")]),
      .object(["kind": .string("CRITIC"), "parents": .array([.int(2)]), "task": .string("Challenge assumptions")])]
    let parsed = try AgentConversationalTeamProtocol.plan(wire.decode(plan(roles)))
    XCTAssertEqual(parsed.roles[1].parents, ["role1"]); XCTAssertEqual(parsed.roles[2].parents, ["role2"])
    XCTAssertEqual(parsed.finalEditor?.id, "role4"); XCTAssertEqual(parsed.finalEditor?.parents, [])
  }
  func testMissingNullOrBlankReviewDoesNotInventAnAssignment() {
    for final in [nil, .some(AgentMcpJSONValue.null), .some(.string("")), .some(.string("  "))] {
      XCTAssertThrowsError(try wire.decode(plan([.string("Compare")], final: final))) { error in
        guard case AgentConversationalTeamProtocol.Failure.finalAuditMissing = error else { return XCTFail("Expected missing review") }
      }
    }
    for final in [AgentMcpJSONValue.bool(true), .int(1), .string("A\nB"), .string("A|B"), .string(String(repeating: "x", count: 401))] {
      XCTAssertThrowsError(try wire.decode(plan([], final: final)))
    }
  }
  func testNineContributorsUseTenSlotsButTenthContributorIsRejected() throws {
    let contributors = Array(repeating: AgentMcpJSONValue.string("Independent calculation"), count: 9)
    XCTAssertEqual(try AgentConversationalTeamProtocol.plan(wire.decode(plan(contributors))).roles.count, 10)
    XCTAssertThrowsError(try wire.decode(plan(contributors + [.string("Excess contributor")])))
    XCTAssertEqual(try AgentConversationalTeamProtocol.plan(wire.decode(plan([]))).roles.count, 1)
  }
  func testOlderNumberedFinalReviewPlansRemainValidWithoutChangingDefaultMode() throws {
    let numbered = "WORK|-|Compare\nREVIEW|1|Audit\nSYNTHESIS|Report"
    XCTAssertEqual(try wire.decode(numbered), numbered)
    XCTAssertThrowsError(try AgentTeamPlanWire(constrained: true, finalReview: true).decode(numbered))
    XCTAssertThrowsError(try wire.decode("ROLE|review|reviewer|-|Audit\nSYNTHESIS|Report"))
    XCTAssertThrowsError(try AgentTeamPlanWire(constrained: false).decode(plan([.string("Compare")])))
    XCTAssertThrowsError(try wire.decode(plan([.string("Compare")], final: nil)))
  }
  func testOnlyTheExactFinalPlannerUsesTheThreeFieldOptionalSchema() throws {
    let system = AgentConversationalTeamProtocol.finalReviewPlanner
    let selected = try XCTUnwrap(AgentTeamPlanWire.select(system: system, endpoint: "http://127.0.0.1:8080/v1/chat/completions",
      apiStyle: .openAICompatible, constrained: true))
    XCTAssertTrue(selected.finalReview); XCTAssertEqual(selected.system, system)
    let properties = try XCTUnwrap(selected.format["json_schema"]?.objectValue?["schema"]?.objectValue?["properties"]?.objectValue)
    XCTAssertEqual(Set(properties.keys), ["roles", "synthesis", "final_review"])
    XCTAssertEqual(properties["roles"]?.objectValue?["maxItems"], .int(9))
    XCTAssertEqual(properties["roles"]?.objectValue?["items"]?.objectValue?["anyOf"]?.arrayValue?.count, 2)
    XCTAssertNil(AgentTeamPlanWire.select(system: system + "\n", endpoint: "http://127.0.0.1:8080/v1/chat/completions", apiStyle: .openAICompatible, constrained: true))
  }
  func testActualFindingsReachWriterAndActualDraftReachesIndependentEditor() async throws {
    let fixture = SyntheticAuthoredReviewWire(2)
    let outcome = try await AgentConversationalTeamEngine.run(objective: "Compare schedules, then independently audit the final answer.", ask: { try await fixture.ask($0, $1) })
    let raw = await fixture.inputs(), requests = try raw.map { try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data($0.utf8)) }
    let synthesis = try XCTUnwrap(requests.first { $0["stage"] == .string("synthesis") })
    XCTAssertEqual(synthesis["reports"]?.arrayValue?.compactMap { $0.objectValue?["finding"]?.strictStringValue },
      ["Actual finding from role1", "Actual finding from role2"])
    let audit = try XCTUnwrap(requests.last)
    XCTAssertEqual(audit["draft"], .string("The actual unreviewed schedule draft"))
    XCTAssertEqual(audit["assignment"], .string("Audit the actual draft against the supplied schedules"))
    XCTAssertEqual(audit["reports"], .array([]))
    XCTAssertEqual(audit["additional_objections"]?.arrayValue?.count, 2)
    XCTAssertEqual(outcome.answer, "The independently corrected schedule"); XCTAssertEqual(outcome.calls, 5)
    XCTAssertFalse(outcome.publicText(disagreementsTitle: "Reservations").contains("unreviewed schedule draft"))
  }
  func testAllocatedEditorDoesNotAddCallsBeyondTheExistingTwelveCallLimit() async throws {
    let fixture = SyntheticAuthoredReviewWire(9)
    let outcome = try await AgentConversationalTeamEngine.run(objective: "Compare schedules, then independently audit the final answer.", ask: { try await fixture.ask($0, $1) })
    XCTAssertEqual(outcome.calls, 12); XCTAssertEqual(outcome.roleCount, 10); XCTAssertEqual(outcome.reports.count, 9)
  }
}

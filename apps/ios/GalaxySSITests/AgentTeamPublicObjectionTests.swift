import XCTest
@testable import GalaxySSI

private actor SyntheticObjectionWire {
  enum Mode { case optional(Bool), parentOnly, tableMismatch, fullBudget }
  let mode: Mode
  private var requests: [String] = []
  init(_ mode: Mode) { self.mode = mode }
  func ask(_ system: String, _ prompt: String) throws -> String {
    requests.append(prompt)
    let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(prompt.utf8))
    let stage = input["stage"]?.strictStringValue ?? ""
    if stage == "plan" {
      switch mode {
      case .parentOnly: return "WORK|-|Summarize\nREVIEW|1|Audit\nSYNTHESIS|Deliver"
      case .fullBudget:
        return ((1...9).map { "WORK|-|Assignment \($0)" } + ["REVIEW|2,5|Audit", "SYNTHESIS|Deliver"]).joined(separator: "\n")
      default: return "WORK|-|Summarize\nCRITIC|-|Check provenance\nREVIEW|1|Audit\nSYNTHESIS|Deliver"
      }
    }
    if stage == "role" {
      let id = input["id"]?.strictStringValue ?? ""
      var nonParent = id == "role2"
      if case .fullBudget = mode { nonParent = id == "role9" }
      var output: AgentMcpJSONObject = ["finding": .string(nonParent ? "NONPARENT FINDING" : "Reported readings")]
      switch mode {
      case .optional(let disputed): if id == "role2" && disputed { output["dissent"] = .string("These readings are simulated, not measured") }
      case .parentOnly: output["dissent"] = .string("Parent reservation")
      case .tableMismatch: output["dissent"] = .string("No delivery times supplied")
      case .fullBudget: if id == "role9" { output["dissent"] = .string("Independent reservation") }
      }
      return AgentMcpJSONCodec.stringify(output)
    }
    if stage == "synthesis" { return #"{"answer":"The candidate was experimentally verified."}"# }
    if stage == "audit" {
      switch mode {
      case .optional:
        return input["additional_objections"] == nil ? #"{"verdict":"accept"}"# :
          #"{"verdict":"withhold","objection":"No candidate-specific measurements supplied"}"#
      case .tableMismatch: return #"{"pass_all":["west"],"purpose":"Compare bids","limitation":"Quoted bids"}"#
      default: return #"{"verdict":"accept"}"#
      }
    }
    throw AgentTeamDraftAudit.Failure.invalid
  }
  func inputs() -> [String] { requests }
}

@MainActor
final class AgentTeamPublicObjectionTests: XCTestCase {
  private func inputs(_ wire: SyntheticObjectionWire) async throws -> [AgentMcpJSONObject] {
    try await wire.inputs().map { try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data($0.utf8)) }
  }
  func testNonParentObjectionCanWithholdIdenticalDraftWithoutSharingItsReport() async throws {
    for disputed in [false, true] {
      let wire = SyntheticObjectionWire(.optional(disputed))
      do {
        let outcome = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic alternatives", ask: { try await wire.ask($0, $1) })
        XCTAssertFalse(disputed); XCTAssertEqual(outcome.answer, "The candidate was experimentally verified.")
      } catch let rejection as AgentTeamDraftAudit.Rejected {
        XCTAssertTrue(disputed)
        guard case .withheld(let reason) = rejection.issue else { return XCTFail("Expected withholding") }
        XCTAssertEqual(reason, "No candidate-specific measurements supplied")
        XCTAssertEqual(rejection.objections.map(\.id), ["role2"])
        XCTAssertFalse(reason.contains("experimentally verified"))
      }
      let requests = try await inputs(wire)
      XCTAssertEqual(requests.count, 5)
      for worker in requests.filter({ $0["stage"] == .string("role") }) {
        XCTAssertNil(worker["additional_objections"]); XCTAssertEqual(worker["reports"], .array([]))
      }
      let audit = try XCTUnwrap(requests.first { $0["stage"] == .string("audit") })
      XCTAssertFalse(AgentMcpJSONCodec.stringify(audit).contains("NONPARENT FINDING"))
      if disputed {
        let extra = try XCTUnwrap(audit["additional_objections"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(Set(extra.keys), ["id", "dissent"])
        XCTAssertEqual(extra["id"], .string("role2"))
      } else { XCTAssertNil(audit["additional_objections"]) }
    }
  }
  func testNamedParentReservationsAreNotDuplicatedAsAdditionalObjections() async throws {
    let wire = SyntheticObjectionWire(.parentOnly)
    let outcome = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic alternatives", ask: { try await wire.ask($0, $1) })
    let requests = try await inputs(wire), audit = try XCTUnwrap(requests.last)
    XCTAssertNil(audit["additional_objections"])
    XCTAssertEqual(audit["reports"]?.arrayValue?.first?.objectValue?["dissent"], .string("Parent reservation"))
    XCTAssertEqual(outcome.publicText(disagreementsTitle: "Model reservations").components(separatedBy: "Parent reservation").count, 2)
    XCTAssertEqual(outcome.calls, 4)
  }
  func testDisputedTableKeepsCalculatedValuesSeparateFromModelReservationsAndRejectedDraft() async throws {
    let objective = "|input|gate|west|east|\n|---|---|---|---|\n|price|< 2.10|2.10|2.09|"
    let wire = SyntheticObjectionWire(.tableMismatch)
    do { _ = try await AgentConversationalTeamEngine.run(objective: objective, ask: { try await wire.ask($0, $1) }); XCTFail("Expected mismatch") }
    catch let rejection as AgentTeamDraftAudit.Rejected {
      guard case .tableMismatch(let verified) = rejection.issue else { return XCTFail("Expected table mismatch") }
      XCTAssertTrue(verified.contains("Pass all gates: east"))
      XCTAssertFalse(verified.contains("No delivery times")); XCTAssertFalse(verified.contains("experimentally verified"))
      XCTAssertEqual(rejection.objections.map(\.id), ["role1", "role2"])
      let reservations = AgentConversationalTeamProtocol.renderObjections(rejection.objections, title: "Model reservations")
      XCTAssertTrue(reservations.contains("No delivery times")); XCTAssertFalse(reservations.contains("NONPARENT FINDING"))
    }
  }
  func testAdditionalObjectionsDoNotAddCallsOrExposeAssignmentsAtTheTenRoleLimit() async throws {
    let wire = SyntheticObjectionWire(.fullBudget)
    let outcome = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic alternatives", ask: { try await wire.ask($0, $1) })
    let requests = try await inputs(wire), audit = try XCTUnwrap(requests.last)
    XCTAssertEqual(outcome.calls, 12); XCTAssertEqual(outcome.roleCount, 10)
    let extras = try XCTUnwrap(audit["additional_objections"]?.arrayValue)
    XCTAssertEqual(extras.count, 1)
    let extra = try XCTUnwrap(extras.first?.objectValue)
    XCTAssertEqual(Set(extra.keys), ["id", "dissent"]); XCTAssertEqual(extra["id"], .string("role9"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(audit).contains("NONPARENT FINDING"))
  }
}

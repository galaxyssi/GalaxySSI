import XCTest
@testable import GalaxySSI

final class AgentConversationalTeamProtocolTests: XCTestCase {
  private typealias Contract = AgentConversationalTeamProtocol
  func testZeroRolesStillRequiresOneSynthesisBrief() throws {
    let plan = try Contract.plan("SYNTHESIS|Answer directly.\r\n")
    XCTAssertEqual(plan.roles, [])
    XCTAssertEqual(plan.synthesis, "Answer directly.")
    XCTAssertThrowsError(try Contract.plan(""))
    XCTAssertThrowsError(try Contract.plan("SYNTHESIS|"))
  }
  func testForwardEdgesAndRoleKindsRemainInOriginalPlanOrder() throws {
    let plan = try Contract.plan("ROLE|review|reviewer|draft,critic|Review public findings.\nROLE|critic|dissent|-|Counterposition.\nROLE|draft|worker|-|Draft.\nSYNTHESIS|Combine.")
    XCTAssertEqual(plan.roles.map(\.id), ["review", "critic", "draft"])
    XCTAssertEqual(plan.roles[0].parents, ["draft", "critic"])
    XCTAssertEqual(plan.roles[1].kind, .dissent)
  }
  func testDuplicateUnknownSelfAndCyclicDependenciesAreRejected() {
    for roles in ["ROLE|a|worker|-|A\nROLE|a|worker|-|Duplicate", "ROLE|a|worker|missing|A",
      "ROLE|a|worker|a|A", "ROLE|ok|worker|-|Root\nROLE|a|worker|b|A\nROLE|b|worker|a|B",
      "ROLE|a|worker|-|A\nROLE|b|worker|a,a|B"] {
      XCTAssertThrowsError(try Contract.plan(roles + "\nSYNTHESIS|Combine."), roles)
    }
  }
  func testRoleCountAndBothEdgeDegreeLimitsAreEnforced() {
    let tooMany = (1...11).map { "ROLE|r\($0)|worker|-|Work." }.joined(separator: "\n")
    let outgoing = ["ROLE|root|worker|-|Root"] + (1...4).map { "ROLE|r\($0)|worker|root|Work." }
    let incoming = (1...4).map { "ROLE|r\($0)|worker|-|Work." } + ["ROLE|sink|worker|r1,r2,r3,r4|Review."]
    for value in [tooMany, outgoing.joined(separator: "\n"), incoming.joined(separator: "\n")] {
      XCTAssertThrowsError(try Contract.plan(value + "\nSYNTHESIS|Combine."))
    }
  }
  func testMalformedPlannerFieldsAndUnboundedTextAreRejected() {
    for value in ["ROLE|bad id|worker|-|Work.\nSYNTHESIS|Combine.", "ROLE|a|executor|-|Work.\nSYNTHESIS|Combine.",
      "ROLE|a|worker|-|\nSYNTHESIS|Combine.", "ROLE|a|worker|-|Extra|field\nSYNTHESIS|Combine.",
      "SYNTHESIS|Combine.\nextra", "```\nSYNTHESIS|Combine.\n```", "SYNTHESIS|" + String(repeating: "x", count: 401)] {
      XCTAssertThrowsError(try Contract.plan(value), value)
    }
  }
  func testRoleReportRequiresCompletePublicFindingAndDissentFields() throws {
    let role = Contract.Role(id: "draft", kind: .worker, parents: [], assignment: "Draft.")
    let report = try Contract.report("FINDING|Public result.\r\nDISSENT|The dates are unconfirmed.\r\nEND\r\n", role: role)
    XCTAssertEqual(report.finding, "Public result.")
    XCTAssertEqual(report.dissent, "The dates are unconfirmed.")
    XCTAssertEqual(report.json["id"] as? String, "draft")
    for value in ["FINDING|Partial.\nDISSENT|-", "FINDING|\nDISSENT|-\nEND", "FINDING|Result.\nDISSENT|\nEND",
      "FINDING|Result.\nDISSENT|-\nEND\nextra", "FINDING|" + String(repeating: "x", count: 2_001) + "\nDISSENT|-\nEND"] {
      XCTAssertThrowsError(try Contract.report(value, role: role), value)
    }
  }
  func testSynthesisPreservesInternalLineEndingsAndRequiresEndMarker() throws {
    XCTAssertEqual(try Contract.synthesis("First line.\r\nSecond line.\r\nEND\r\n"), "First line.\r\nSecond line.")
    for value in ["Partial answer", "END", "Answer.\nEND\nextra", String(repeating: "x", count: 8_001) + "\nEND"] {
      XCTAssertThrowsError(try Contract.synthesis(value), value)
    }
  }
  func testExecutableRichBlocksCannotBecomePublicTeamResults() {
    let role = Contract.Role(id: "draft", kind: .worker, parents: [], assignment: "Draft.")
    XCTAssertThrowsError(try Contract.report("FINDING|```galaxyssi-rich\nDISSENT|-\nEND", role: role))
    XCTAssertThrowsError(try Contract.synthesis("```galaxyssi-rich\nEND"))
  }
}

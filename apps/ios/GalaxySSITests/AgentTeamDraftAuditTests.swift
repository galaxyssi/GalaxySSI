import XCTest
@testable import GalaxySSI

private actor SyntheticDraftAuditWire {
  let plan: String
  let review: String
  private var stages: [String] = []
  private var auditParents: [String] = []
  private var receivedDraft = ""
  init(plan: String, review: String) { self.plan = plan; self.review = review }
  func ask(_ system: String, _ prompt: String) throws -> String {
    let body = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(prompt.utf8))
    let stage = body["stage"]?.strictStringValue ?? ""
    stages.append(stage)
    switch stage {
    case "plan": return plan
    case "role":
      return body["id"] == .string("role9") ? #"{"finding":"A source count","dissent":"A limitation remains"}"# : #"{"finding":"A source count"}"#
    case "synthesis": return #"{"answer":"Both cases pass."}"#
    case "audit":
      auditParents = body["reports"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.strictStringValue } ?? []
      receivedDraft = body["draft"]?.strictStringValue ?? ""
      if review == "cancel" { throw CancellationError() }
      return review
    default: throw AgentTeamDraftAudit.Failure.invalid
    }
  }
  func snapshot() -> ([String], [String], String) { (stages, auditParents, receivedDraft) }
}

@MainActor
final class AgentTeamDraftAuditTests: XCTestCase {
  func testAcceptAndRevisionRequireExactFieldsAndVisibleCorrections() throws {
    let accept = try AgentTeamDraftAudit.parse(#"{"verdict":"accept"}"#, draft: "Draft", sheet: nil, labels: .english)
    XCTAssertEqual(accept.answer, "Draft"); XCTAssertNil(accept.correction)
    let fixed = try AgentTeamDraftAudit.parse(#"{"verdict":"revise","objection":"One gate was missed","answer":"Only east passes."}"#,
      draft: "Draft", sheet: nil, labels: .english)
    XCTAssertEqual(fixed.answer, "Only east passes."); XCTAssertEqual(fixed.correction, "One gate was missed")
    XCTAssertFalse(fixed.requiresHandback)
    let unchanged = try AgentTeamDraftAudit.parse(#"{"verdict":"revise","objection":"Not corrected","answer":"Draft"}"#,
      draft: "Draft", sheet: nil, labels: .english)
    XCTAssertTrue(unchanged.requiresHandback); XCTAssertEqual(unchanged.correction, "Not corrected")
    for raw in [#"{"verdict":"accept","answer":"Extra"}"#, #"{"verdict":"revise","objection":"Missing answer"}"#,
      #"{"verdict":true}"#,
      #"{"verdict":"accept"} trailing"#] {
      XCTAssertThrowsError(try AgentTeamDraftAudit.parse(raw, draft: "Draft", sheet: nil, labels: .english))
    }
  }
  func testWithheldAndInvalidReviewsDoNotExposeTheDraft() throws {
    do {
      _ = try AgentTeamDraftAudit.parse(#"{"verdict":"withhold","objection":"No measured evidence"}"#, draft: "Unsafe draft", sheet: nil, labels: .english)
      XCTFail("Expected withholding")
    } catch AgentTeamDraftAudit.Failure.withheld(let objection) { XCTAssertEqual(objection, "No measured evidence") }
    for raw in [#"{"verdict":"withhold","objection":true}"#, #"{"verdict":"withhold","objection":"Reason","answer":"Leak"}"#,
      #"{"verdict":"revise","objection":"Reason","answer":"```galaxyssi-rich"}"#] {
      XCTAssertThrowsError(try AgentTeamDraftAudit.parse(raw, draft: "Unsafe draft", sheet: nil, labels: .english))
    }
  }
  func testTableAuditMustConfirmExactlyTheHostSetAndNeverReuseDraftClaims() throws {
    let sheet = try XCTUnwrap(AgentTeamComparisonSheet.evaluate("|input|gate|west|east|\n|---|---|---|---|\n|price|< 2.10|2.10|2.09|"))
    let good = #"{"purpose":"Compare bids","pass_all":["east"],"limitation":"Quoted bids only"}"#
    let result = try AgentTeamDraftAudit.parse(good, draft: "Both pass", sheet: sheet, labels: .english)
    XCTAssertTrue(result.answer.contains("Pass all gates: east")); XCTAssertFalse(result.answer.contains("Both pass"))
    for raw in [good.replacingOccurrences(of: "[\"east\"]", with: "[\"west\"]"),
      good.replacingOccurrences(of: "[\"east\"]", with: "[\"east\",\"east\"]"),
      #"{"purpose":"Compare bids","limitation":"Quoted bids only"}"#] {
      do { _ = try AgentTeamDraftAudit.parse(raw, draft: "Both pass", sheet: sheet, labels: .english); XCTFail("Expected mismatch") }
      catch AgentTeamDraftAudit.Failure.tableMismatch(let verified) {
        XCTAssertTrue(verified.contains("Pass all gates: east")); XCTAssertFalse(verified.contains("Both pass"))
      }
    }
  }
  func testConstrainedSchemaIsShapeOnlyAndRestrictedToExactLoopbackAudit() throws {
    let system = AgentTeamDraftAudit.tableSystem
    let format = try XCTUnwrap(AgentTeamDraftAudit.responseFormat(system: system, endpoint: "http://127.0.0.1:8080/v1/chat/completions"))
    let json = AgentMcpJSONCodec.stringify(format)
    XCTAssertTrue(json.contains("json_schema")); XCTAssertFalse(json.contains("enum")); XCTAssertFalse(json.contains("east"))
    for endpoint in ["https://localhost/v1", "http://127.0.0.2/v1", "https://example.invalid/v1", "http://user@127.0.0.1/v1"] {
      XCTAssertNil(AgentTeamDraftAudit.responseFormat(system: system, endpoint: endpoint))
    }
    XCTAssertNil(AgentTeamDraftAudit.responseFormat(system: AgentTeamDraftAudit.system, endpoint: "http://127.0.0.1/v1"))
  }
  func testFinalEditorUsesOneAllocatedRoleAndAuditsTheActualSynthesisWithinTwelveCalls() async throws {
    let jobs = (1...9).map { "WORK|-|Evaluate item \($0)" } + ["REVIEW|2,5|Audit edge cases", "SYNTHESIS|Compare"]
    let wire = SyntheticDraftAuditWire(plan: jobs.joined(separator: "\n"),
      review: #"{"verdict":"revise","objection":"One threshold was missed","answer":"Only the second passes."}"#)
    let result = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic cases", ask: { try await wire.ask($0, $1) })
    let snapshot = await wire.snapshot()
    XCTAssertEqual(result.calls, 12); XCTAssertEqual(result.roleCount, 10); XCTAssertEqual(result.reports.count, 9)
    XCTAssertEqual(Array(snapshot.0.suffix(2)), ["synthesis", "audit"])
    XCTAssertEqual(snapshot.1, ["role2", "role5"]); XCTAssertEqual(snapshot.2, "Both cases pass.")
    let publicText = result.publicText(disagreementsTitle: "Dissent")
    XCTAssertFalse(publicText.contains("Both cases pass.")); XCTAssertTrue(publicText.contains("One threshold was missed"))
    XCTAssertTrue(publicText.contains("A limitation remains"))
  }
  func testReviewersWithDownstreamConsumersRemainInPreSynthesisGraph() async throws {
    let wire = SyntheticDraftAuditWire(plan: "WORK|-|Count\nREVIEW|1|Check\nWORK|2|Estimate\nSYNTHESIS|Compare", review: "unexpected")
    let result = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic cases", ask: { try await wire.ask($0, $1) })
    let snapshot = await wire.snapshot()
    XCTAssertEqual(result.calls, 5); XCTAssertFalse(snapshot.0.contains("audit"))
  }
  func testCancelledWithheldAndMalformedAuditsCannotReturnAnOutcome() async {
    for review in ["cancel", #"{"verdict":"withhold","objection":"No source"}"#, #"{"verdict":"accept","answer":"Extra"}"#, "partial"] {
      let wire = SyntheticDraftAuditWire(plan: "WORK|-|Count\nREVIEW|1|Audit\nSYNTHESIS|Compare", review: review)
      do { _ = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic cases", ask: { try await wire.ask($0, $1) }); XCTFail("Unreviewed draft returned") }
      catch { if review == "cancel" { XCTAssertTrue(error is CancellationError) } }
    }
  }
  func testLegacyNamedReviewersRetainTheirOriginalPreSynthesisMeaning() throws {
    let plan = try AgentConversationalTeamProtocol.plan("ROLE|a|worker|-|Count\nROLE|b|reviewer|a|Review\nSYNTHESIS|Compare")
    XCTAssertNil(plan.finalEditor)
    let numbered = try AgentConversationalTeamProtocol.plan("WORK|-|Count\nREVIEW|1|Review\nSYNTHESIS|Compare")
    XCTAssertEqual(numbered.finalEditor?.id, "role2")
  }
}

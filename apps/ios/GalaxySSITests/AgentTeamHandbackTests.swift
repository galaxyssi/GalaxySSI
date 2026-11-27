import XCTest
@testable import GalaxySSI

private actor SyntheticHandbackWire {
  let workers: Int
  let audit: String
  let rewrite: String
  let recheck: String
  let failure: String?
  private var requests: [AgentMcpJSONObject] = []
  init(workers: Int = 2,
    audit: String = #"{"verdict":"revise","objection":"Original reservation","answer":"Disputed draft"}"#,
    rewrite: String = #"{"answer":"Corrected answer"}"#,
    recheck: String = #"{"verdict":"accept"}"#, failure: String? = nil) {
    self.workers = workers; self.audit = audit; self.rewrite = rewrite; self.recheck = recheck; self.failure = failure
  }
  func ask(_ system: String, _ prompt: String) throws -> String {
    let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(prompt.utf8))
    requests.append(input)
    let stage = input["stage"]?.strictStringValue ?? ""
    if failure == stage + "-cancel" { throw CancellationError() }
    if failure == stage { throw AgentConversationalTeamProtocol.Failure.transport }
    switch stage {
    case "plan": return ((1...workers).map { "WORK|-|Calculate item \($0)" } + ["REVIEW|1|Audit the actual draft", "SYNTHESIS|Compare every finding"]).joined(separator: "\n")
    case "role": return #"{"finding":"Actual contributor finding","dissent":"Contributor reservation"}"#
    case "synthesis": return #"{"answer":"Disputed draft"}"#
    case "audit": return audit
    case "rewrite": return rewrite
    case "recheck": return recheck
    default: throw AgentTeamDraftAudit.Failure.invalid
    }
  }
  func inputs() -> [AgentMcpJSONObject] { requests }
}

@MainActor
final class AgentTeamHandbackTests: XCTestCase {
  private func run(_ wire: SyntheticHandbackWire) async throws -> AgentConversationalTeamEngine.Outcome {
    try await AgentConversationalTeamEngine.run(objective: "Compare synthetic assumptions", ask: { try await wire.ask($0, $1) })
  }
  private func assertWithheld(_ wire: SyntheticHandbackWire, reason: String = "Original reservation") async {
    do { _ = try await run(wire); XCTFail("Disputed answer must not be published") }
    catch let rejected as AgentTeamDraftAudit.Rejected {
      guard case .withheld(let value) = rejected.issue else { return XCTFail("Expected withholding") }
      XCTAssertEqual(value, reason)
      XCTAssertEqual(rejected.objections.count, 2)
      XCTAssertTrue(rejected.objections.allSatisfy { $0.dissent == "Contributor reservation" })
    } catch { XCTFail("Existing objections must survive: \(error)") }
  }
  func testWriterGetsActualFindingsAndSameEditorRechecksActualReplacement() async throws {
    let wire = SyntheticHandbackWire()
    var events: [AgentConversationalTeamEngine.Event] = []
    let result = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic assumptions",
      ask: { try await wire.ask($0, $1) }, onEvent: { events.append($0) })
    let inputs = await wire.inputs()
    let rewrite = try XCTUnwrap(inputs.first { $0["stage"] == .string("rewrite") })
    let audit = try XCTUnwrap(inputs.first { $0["stage"] == .string("audit") })
    let recheck = try XCTUnwrap(inputs.first { $0["stage"] == .string("recheck") })
    XCTAssertEqual(rewrite["brief"], .string("Compare every finding"))
    XCTAssertEqual(rewrite["reports"]?.arrayValue?.count, 2)
    XCTAssertTrue(rewrite["reports"]?.arrayValue?.allSatisfy { $0.objectValue?["finding"] == .string("Actual contributor finding") } == true)
    for key in ["id", "kind", "assignment", "reports", "additional_objections", "objective"] { XCTAssertEqual(recheck[key], audit[key]) }
    XCTAssertEqual(rewrite["draft"], .string("Disputed draft")); XCTAssertEqual(recheck["rejected_draft"], rewrite["draft"])
    XCTAssertEqual(recheck["draft"], .string("Corrected answer")); XCTAssertEqual(recheck["objection"], .string("Original reservation"))
    XCTAssertEqual(result.answer, "Corrected answer"); XCTAssertEqual(result.calls, 7); XCTAssertEqual(result.roleCount, 3)
    XCTAssertTrue(events.contains(.rewriting)); XCTAssertTrue(events.contains(.rechecking(3, 3)))
    XCTAssertTrue(result.publicText(disagreementsTitle: "Dissent").contains("Contributor reservation"))
    XCTAssertTrue(result.publicText(disagreementsTitle: "Dissent").contains("Original reservation"))
  }
  func testEightAllocatedRolesCanUseExactlyTwelveCalls() async throws {
    let wire = SyntheticHandbackWire(workers: 7)
    let outcome = try await run(wire)
    XCTAssertEqual(outcome.calls, 12); XCTAssertEqual(outcome.roleCount, 8)
  }
  func testNineOrTenRolesNeverStartAnUnfundedPair() async {
    for workers in [8, 9] {
      let wire = SyntheticHandbackWire(workers: workers)
      do { _ = try await run(wire); XCTFail("Expected budget withholding") }
      catch let rejected as AgentTeamDraftAudit.Rejected {
        guard case .withheld(let reason) = rejected.issue else { return XCTFail("Expected withholding") }
        XCTAssertEqual(reason, "Original reservation"); XCTAssertEqual(rejected.objections.count, workers)
      } catch { XCTFail("Expected typed rejection") }
      let inputs = await wire.inputs()
      XCTAssertFalse(inputs.contains { $0["stage"] == .string("rewrite") || $0["stage"] == .string("recheck") })
      XCTAssertEqual(inputs.count, workers + 3)
    }
  }
  func testWhitespaceOnlyRevisionRequiresHandbackWithoutChangingCaseOrPunctuationRules() throws {
    XCTAssertTrue(AgentTeamDraftAudit.sameDraft(" A\u{00A0}\u{0085}B\n", "A B"))
    XCTAssertFalse(AgentTeamDraftAudit.sameDraft("A B", "a B")); XCTAssertFalse(AgentTeamDraftAudit.sameDraft("A B", "A B."))
    let raw = #"{"verdict":"revise","objection":"Still wrong","answer":" Disputed\u00a0draft "}"#
    XCTAssertTrue(try AgentTeamDraftAudit.parse(raw, draft: "Disputed draft", sheet: nil, labels: .english).requiresHandback)
  }
  func testGenuineEditorCorrectionDoesNotAskWriterAgain() async throws {
    let wire = SyntheticHandbackWire(audit: #"{"verdict":"revise","objection":"Original reservation","answer":"Actual corrected draft"}"#)
    let result = try await run(wire), inputs = await wire.inputs()
    XCTAssertEqual(result.answer, "Actual corrected draft"); XCTAssertEqual(result.calls, 5)
    XCTAssertFalse(inputs.contains { $0["stage"] == .string("rewrite") })
  }
  func testMalformedDuplicateAndUnchangedRewritesRetainOriginalObjections() async {
    for raw in ["partial", #"{"answer":"Disputed draft"}"#, #"{"answer":"Disputed\u00a0draft"}"#,
      #"{"answer":"First","answer":"Second"}"#, #"{"answer":"First","\u0061nswer":"Second"}"#,
      #"{"answer":"Replacement","tool_calls":[]}"#, #"{"answer":true}"#, #"{"answer":"```galaxyssi-rich"}"#] {
      let wire = SyntheticHandbackWire(rewrite: raw)
      await assertWithheld(wire)
      let inputs = await wire.inputs()
      XCTAssertFalse(inputs.contains { $0["stage"] == .string("recheck") })
    }
  }
  func testRecheckCannotReviseAgainOrEraseTheOriginalObjectionWithAmbiguousJSON() async {
    for raw in ["partial", #"{"verdict":"accept","answer":"Extra"}"#,
      #"{"verdict":"revise","objection":"Retry","answer":"Other"}"#,
      #"{"verdict":"withhold","objection":"No","verdict":"accept"}"#,
      #"{"verdict":"withhold","objection":false}"#] {
      let wire = SyntheticHandbackWire(recheck: raw)
      await assertWithheld(wire)
      let inputs = await wire.inputs()
      XCTAssertEqual(inputs.filter { $0["stage"] == .string("rewrite") }.count, 1)
      XCTAssertEqual(inputs.filter { $0["stage"] == .string("recheck") }.count, 1)
    }
  }
  func testExplicitRecheckVetoSurvivesAlongsideContributorDissent() async {
    await assertWithheld(SyntheticHandbackWire(recheck: #"{"verdict":"withhold","objection":"Replacement still contradicts the source"}"#),
      reason: "Replacement still contradicts the source")
  }
  func testTransportFailuresRetainObjectionsWhileCancellationWins() async {
    for stage in ["rewrite", "recheck"] {
      await assertWithheld(SyntheticHandbackWire(failure: stage))
      let wire = SyntheticHandbackWire(failure: stage + "-cancel")
      do { _ = try await run(wire); XCTFail("Cancellation must interrupt") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
  }
  func testInitialAuditRejectsConflictingAndEscapedDuplicateVerdicts() {
    for raw in [#"{"verdict":"withhold","verdict":"accept"}"#,
      #"{"verdict":"withhold","\u0076erdict":"accept"}"#,
      #"{"verdict":"accept","extra":{"nested":true,"nested":false}}"#] {
      XCTAssertThrowsError(try AgentTeamDraftAudit.parse(raw, draft: "Disputed draft", sheet: nil, labels: .english))
    }
  }
  func testExplicitRequestChangesUsesOneWriterAndSameEditorWithoutAnAnswerField() async throws {
    let wire = SyntheticHandbackWire(audit: #"{"verdict":"request_changes","objection":"Original reservation"}"#)
    let result = try await run(wire), inputs = await wire.inputs()
    XCTAssertEqual(result.answer, "Corrected answer"); XCTAssertEqual(result.calls, 7)
    XCTAssertEqual(inputs.filter { $0["stage"] == .string("rewrite") }.count, 1)
    XCTAssertEqual(inputs.filter { $0["stage"] == .string("recheck") }.count, 1)
    XCTAssertEqual(inputs.last?["objection"], .string("Original reservation"))
  }
  func testRequestChangesRejectsAnswerFieldsMissingReasonsAndWrongTypes() {
    for raw in [#"{"verdict":"request_changes","objection":"Reason","answer":"Ambiguous"}"#,
      #"{"verdict":"request_changes"}"#, #"{"verdict":"request_changes","objection":true}"#,
      #"{"verdict":"request_changes","objection":""}"#] {
      XCTAssertThrowsError(try AgentTeamDraftAudit.parse(raw, draft: "Draft", sheet: nil, labels: .english))
    }
  }
  func testPlaceholderAuditReasonsUseLocalizedReceiptAndRetainContributorDissent() async {
    for verdict in ["request_changes", "withhold", "revise"] {
      var object: AgentMcpJSONObject = ["verdict": .string(verdict), "objection": .string("Brief error in draft.")]
      if verdict == "revise" { object["answer"] = .string("Another answer") }
      let wire = SyntheticHandbackWire(audit: AgentMcpJSONCodec.stringify(object))
      let labels = AgentTeamDraftAudit.Labels(passing: "Pass", none: "None", limitation: "Limit", noReviewReason: "Localized missing reason")
      do {
        _ = try await AgentConversationalTeamEngine.run(objective: "Compare synthetic assumptions", labels: labels, ask: { try await wire.ask($0, $1) })
        XCTFail("Placeholder is not an audit")
      } catch let rejected as AgentTeamDraftAudit.Rejected {
        guard case .withheld(let reason) = rejected.issue else { return XCTFail("Expected withholding") }
        XCTAssertEqual(reason, "Localized missing reason"); XCTAssertEqual(rejected.objections.count, 2)
      } catch { XCTFail("Expected public rejection") }
      let inputs = await wire.inputs()
      XCTAssertFalse(inputs.contains { $0["stage"] == .string("rewrite") })
    }
  }
  func testRecheckRequestChangesIsATerminalVetoAndPlaceholderFallsBackToOriginal() async {
    await assertWithheld(SyntheticHandbackWire(recheck: #"{"verdict":"request_changes","objection":"Replacement still uses a failed measurement"}"#),
      reason: "Replacement still uses a failed measurement")
    for reason in ["brief reason", "what the writer must correct", "specific reason in the language of the objective"] {
      let raw = AgentMcpJSONCodec.stringify(["verdict": .string("request_changes"), "objection": .string(reason)])
      await assertWithheld(SyntheticHandbackWire(recheck: raw))
    }
  }
  func testPlaceholderRecognitionDoesNotDiscardActualSpecificObjections() {
    for reason in ["Brief error in draft.", "brief reason...", "WHAT THE WRITER MUST CORRECT", "specific reason in the language of the objective"] {
      XCTAssertTrue(AgentTeamDraftAudit.isReviewPlaceholder(reason))
    }
    XCTAssertFalse(AgentTeamDraftAudit.isReviewPlaceholder("The brief reason is that the reporter failed."))
    XCTAssertFalse(AgentTeamDraftAudit.isReviewPlaceholder("The writer must distinguish measurement failure from counterevidence."))
  }
  func testEveryJudgmentRoleGetsPredictionCheckWithoutChangingPlannerAuthority() {
    let check = AgentConversationalTeamProtocol.predictionCheck
    for system in [AgentConversationalTeamProtocol.worker, AgentConversationalTeamProtocol.synthesizer,
      AgentTeamDraftAudit.system, AgentTeamDraftAudit.rewriteSystem, AgentTeamDraftAudit.recheckSystem] {
      XCTAssertTrue(system.contains(check)); XCTAssertTrue(system.contains(AgentConversationalTeamProtocol.boundary))
    }
    XCTAssertFalse(AgentConversationalTeamProtocol.planner.contains(check))
    XCTAssertTrue(check.contains("uninterpretable observation")); XCTAssertTrue(check.contains("Do not invent data."))
  }
}

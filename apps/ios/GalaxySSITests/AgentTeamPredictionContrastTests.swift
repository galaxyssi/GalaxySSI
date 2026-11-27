import XCTest
@testable import GalaxySSI

private func syntheticDirectionalClaim(_ input: String = "load") -> AgentMcpJSONObject {
  ["purpose": .string("A hypothetical strain gauge"), "input": .string(input), "input_direction": .string("higher"),
    "readout": .string("voltage"), "expected_direction": .string("lower"),
    "alternative": .string("Temperature can change voltage independently"), "gap": .string("No calibration evidence")]
}

private actor SyntheticDirectionalWire {
  let mode: String
  let workers: Int
  private var inputs: [AgentMcpJSONObject] = []
  private var instructions: [String] = []
  init(_ mode: String, workers: Int = 1) { self.mode = mode; self.workers = workers }
  func ask(_ system: String, _ raw: String) throws -> String {
    let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    inputs.append(input); instructions.append(system)
    switch input["stage"] {
    case .string("plan"):
      return AgentMcpJSONCodec.stringify(["roles": .array(Array(repeating: .string("Assess the gauge"), count: workers)),
        "synthesis": .string("Propose a testable response"), "final_review": .string("Check the published contrast")])
    case .string("role"): return #"{"finding":"No observations were provided.","dissent":"Calibration is missing"}"#
    case .string("synthesis"):
      if mode == "qualitative" { return #"{"answer":"A qualitative explanation."}"# }
      var claim = syntheticDirectionalClaim()
      if mode == "invalid" { claim["expected_direction"] = .string("sideways") }
      return AgentMcpJSONCodec.stringify(claim)
    case .string("audit"):
      if mode == "approve" || mode == "qualitative" { return #"{"verdict":"accept"}"# }
      if mode == "replace" { return #"{"verdict":"revise","objection":"Which load?","answer":"Never checked."}"# }
      return #"{"verdict":"request_changes","objection":"Which load?"}"#
    case .string("rewrite"):
      if mode == "cancel" { throw CancellationError() }
      if mode == "bypass" { return #"{"answer":"Never checked."}"# }
      return AgentMcpJSONCodec.stringify(syntheticDirectionalClaim(mode == "unchanged" ? "load" : "axial load"))
    case .string("recheck"):
      return mode == "reject" ? #"{"verdict":"withhold","objection":"Not supported."}"# : #"{"verdict":"accept"}"#
    default: throw AgentTeamDraftAudit.Failure.invalid
    }
  }
  func snapshot() -> ([AgentMcpJSONObject], [String]) { (inputs, instructions) }
}

@MainActor
final class AgentTeamPredictionContrastTests: XCTestCase {
  private let objective = "Compare two sensor readings. What observation would contradict this prediction? Independently audit the final answer."
  private func run(_ wire: SyntheticDirectionalWire, labels: AgentTeamDraftAudit.Labels = .english) async throws -> AgentConversationalTeamEngine.Outcome {
    try await AgentConversationalTeamEngine.run(objective: objective, labels: labels, ask: { try await wire.ask($0, $1) })
  }
  func testOppositeReadoutDirectionsKeepTheExactSameInputCondition() throws {
    for input in ["lower", "higher"] {
      for expected in ["lower", "higher"] {
        var claim = syntheticDirectionalClaim(); claim["input_direction"] = .string(input); claim["expected_direction"] = .string(expected)
        let answer = try AgentTeamPredictionContrast.render(claim, text: .english), lines = answer.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "Prediction: If load is \(input), a valid reading of voltage should be \(expected).")
        XCTAssertTrue(lines[2].contains("if load is \(input), a valid reading of voltage that is \(expected == "higher" ? "lower" : "higher")"))
        XCTAssertTrue(lines[2].contains("missing, invalid or uninterpretable measurement would not"))
        XCTAssertTrue(lines[3].contains("not an experimental or clinical conclusion"))
      }
    }
  }
  func testLocalizedTemplateMayReorderAndRepeatSlots() throws {
    let text = AgentTeamPredictionContrast.Text(format: "%8$@|%7$@|%2$@ %3$@|%4$@ %5$@|%2$@ %3$@|%4$@ %6$@|%1$@", higher: "UP", lower: "DOWN")
    XCTAssertEqual(try AgentTeamPredictionContrast.render(syntheticDirectionalClaim(), text: text),
      "No calibration evidence|Temperature can change voltage independently|load UP|voltage DOWN|load UP|voltage UP|A hypothetical strain gauge")
  }
  func testAllSevenKeysRequireActualStringsAndExactDirectionEnums() {
    let base = syntheticDirectionalClaim()
    for key in base.keys {
      var missing = base; missing.removeValue(forKey: key)
      XCTAssertThrowsError(try AgentTeamPredictionContrast.render(missing, text: .english))
      for wrong in [AgentMcpJSONValue.null, .bool(true), .int(42), .object([:])] {
        var claim = base; claim[key] = wrong
        XCTAssertThrowsError(try AgentTeamPredictionContrast.render(claim, text: .english))
      }
    }
    for key in ["input_direction", "expected_direction"] {
      for wrong in ["Higher", "down", "lower "] {
        var claim = base; claim[key] = .string(wrong)
        XCTAssertThrowsError(try AgentTeamPredictionContrast.render(claim, text: .english))
      }
    }
    var extra = base; extra["contrary_direction"] = .string("higher")
    XCTAssertThrowsError(try AgentTeamPredictionContrast.render(extra, text: .english))
  }
  func testEquivalentLabelsPlaceholdersControlsAndOversizedFieldsAreRejected() {
    for (key, value) in [("input", " VOLTAGE "), ("purpose", "TBD"), ("gap", "  "), ("input", "input"),
      ("alternative", "[insert explanation]"), ("gap", "count\n"), ("alternative", "one\u{2028}two"),
      ("gap", "one\u{202e}two"), ("input", "<tag>"), ("purpose", "slot %1$s"), ("purpose", "slot %1$@"),
      ("readout", String(repeating: "a", count: 121)), ("purpose", String(repeating: "b", count: 401))] {
      var claim = syntheticDirectionalClaim(); claim[key] = .string(value)
      XCTAssertThrowsError(try AgentTeamPredictionContrast.render(claim, text: .english), key)
    }
    var equivalent = syntheticDirectionalClaim()
    equivalent["input"] = .string("\u{ff36}\u{ff2f}\u{ff2c}\u{ff34}\u{ff21}\u{ff27}\u{ff25}")
    XCTAssertThrowsError(try AgentTeamPredictionContrast.render(equivalent, text: .english))
  }
  func testOnlyExplicitUnquotedContraryObservationQuestionsEnableTheOffer() {
    for question in ["Under the same assumptions, which observation would be incompatible with the prediction?",
      "What would make you abandon this explanation?", "What result would prove this hypothesis wrong?",
      "Which observation would falsify the prediction?", "How could we falsify the hypothesis?",
      AgentConversationalTeamCommand.text("contrast_sample_request", "", language: LanguagePolicySettings.zhCN)] {
      XCTAssertTrue(AgentTeamPredictionContrast.requested(question), question)
    }
    for question in ["Predict queue length and identify missing evidence.", "Discuss falsifiability.",
      "Which result supports the prediction?", "What result would not contradict this prediction?",
      "Translate: What would make you abandon this explanation?", "The title is \"Which observation would falsify the prediction?\"",
      "`What would make you abandon this explanation?`", "Do not discuss what would falsify the prediction.",
      AgentConversationalTeamCommand.text("contrast_sample_excluded", "", language: LanguagePolicySettings.zhCN)] {
      XCTAssertFalse(AgentTeamPredictionContrast.requested(question), question)
    }
    XCTAssertFalse(AgentTeamPredictionContrast.requested(String(repeating: "x", count: 8_001)))
  }
  func testStructuredOfferStillAcceptsQualitativeAnswersButRejectsDuplicateOrExtraFields() throws {
    let raw = AgentMcpJSONCodec.stringify(syntheticDirectionalClaim())
    XCTAssertNotNil(try AgentTeamPredictionContrast.synthesis(raw, offered: true, text: .english).claim)
    XCTAssertThrowsError(try AgentTeamPredictionContrast.synthesis(raw, offered: false, text: .english))
    XCTAssertThrowsError(try AgentTeamPredictionContrast.synthesis(raw, offered: true, text: .init(format: "")))
    let prose = try AgentTeamPredictionContrast.synthesis(#"{"answer":"A qualitative explanation."}"#, offered: true, text: .english)
    XCTAssertNil(prose.claim); XCTAssertEqual(prose.answer, "A qualitative explanation.")
    XCTAssertEqual(try AgentTeamPredictionContrast.synthesis("Legacy answer\nEND", offered: true, text: .english).answer, "Legacy answer")
    for bad in [#"{"answer":"A","answer":"B"}"#, "```json\r\n{\"answer\":\"A\",\"answer\":\"B\"}\r\n```", #"{"answer":"A","purpose":"Other"}"#,
      String(raw.dropLast()) + #","input":"other"}"#] {
      XCTAssertThrowsError(try AgentTeamPredictionContrast.synthesis(String(bad), offered: true, text: .english))
    }
  }
  func testOnlyExactAuditedDraftOrRecheckedReplacementCanBePublished() async throws {
    for mode in ["approve", "return", "replace", "bypass", "reject", "qualitative"] {
      let wire = SyntheticDirectionalWire(mode)
      var outcome: AgentConversationalTeamEngine.Outcome?, failure: Error?
      do { outcome = try await run(wire) } catch { failure = error }
      let (inputs, systems) = await wire.snapshot()
      let audit = try XCTUnwrap(inputs.first { $0["stage"] == .string("audit") })
      if ["bypass", "reject"].contains(mode) {
        XCTAssertNil(outcome)
        let rejected = try XCTUnwrap(failure as? AgentTeamDraftAudit.Rejected)
        XCTAssertEqual(rejected.objections.count, 1)
        XCTAssertFalse(inputs.contains { $0["stage"] == .string("recheck") } && mode == "bypass")
      } else {
        let result = try XCTUnwrap(outcome)
        let lastDraft = inputs.last(where: { $0["stage"] == .string("recheck") })?["draft"] ?? audit["draft"]
        XCTAssertEqual(.string(result.answer), lastDraft); XCTAssertFalse(result.answer.contains("Never checked."))
        XCTAssertEqual(result.calls, ["return", "replace"].contains(mode) ? 6 : 4)
      }
      if inputs.contains(where: { $0["stage"] == .string("rewrite") }) {
        let rewrite = try XCTUnwrap(inputs.first { $0["stage"] == .string("rewrite") })
        XCTAssertEqual(rewrite["draft"], audit["draft"]); XCTAssertEqual(rewrite["original_claim"]?.objectValue, syntheticDirectionalClaim())
        XCTAssertEqual(rewrite["objection"], .string("Which load?"))
      }
      if let recheck = inputs.first(where: { $0["stage"] == .string("recheck") }) {
        for key in ["id", "kind", "assignment", "reports", "additional_objections", "objective"] { XCTAssertEqual(recheck[key], audit[key]) }
        XCTAssertEqual(recheck["rejected_draft"], audit["draft"])
      }
      XCTAssertTrue(systems.contains(AgentTeamPredictionContrast.writer))
      XCTAssertEqual(systems.contains(AgentTeamPredictionContrast.auditor), mode != "qualitative")
    }
  }
  func testExactLocalizedDraftIsReviewedAgainAfterAChangedClaim() async throws {
    func t(_ key: String, _ fallback: String) -> String {
      AgentConversationalTeamCommand.text(key, fallback, language: LanguagePolicySettings.zhCN)
    }
    let english = AgentTeamPredictionContrast.Text.english
    let text = AgentTeamPredictionContrast.Text(format: t("contrast_format", english.format),
      higher: t("contrast_higher", english.higher), lower: t("contrast_lower", english.lower))
    let labels = AgentTeamDraftAudit.Labels(passing: "Pass", none: "None", limitation: "Limit", contrast: text)
    let wire = SyntheticDirectionalWire("return"), result = try await run(wire, labels: labels)
    let (inputs, _) = await wire.snapshot()
    let audit = try XCTUnwrap(inputs.first { $0["stage"] == .string("audit") })
    XCTAssertEqual(audit["draft"], .string(try AgentTeamPredictionContrast.render(syntheticDirectionalClaim(), text: text)))
    XCTAssertEqual(result.answer, try AgentTeamPredictionContrast.render(syntheticDirectionalClaim("axial load"), text: text))
    XCTAssertNotEqual(result.answer, try AgentTeamPredictionContrast.render(syntheticDirectionalClaim("axial load"), text: .english))
  }
  func testUnfundedStructuredRewriteCannotStartAndUnchangedRewriteRetainsObjection() async {
    for workers in [1, 8] {
      let wire = SyntheticDirectionalWire(workers == 8 ? "return" : "unchanged", workers: workers)
      do { _ = try await run(wire); XCTFail("An unreviewed draft must not escape") }
      catch let rejected as AgentTeamDraftAudit.Rejected {
        guard case .withheld(let reason) = rejected.issue else { return XCTFail("Expected withholding") }
        XCTAssertEqual(reason, "Which load?")
      } catch { XCTFail("Expected retained objection") }
      let (inputs, _) = await wire.snapshot()
      XCTAssertFalse(inputs.contains { $0["stage"] == .string("recheck") })
      XCTAssertEqual(inputs.contains { $0["stage"] == .string("rewrite") }, workers == 1)
    }
  }
  func testInvalidWriterDirectionStopsBeforeAuditAndCancellationRemainsCancellation() async {
    let invalid = SyntheticDirectionalWire("invalid")
    do { _ = try await run(invalid); XCTFail("Invalid direction accepted") } catch { }
    let (inputs, _) = await invalid.snapshot()
    XCTAssertFalse(inputs.contains { $0["stage"] == .string("audit") })
    let cancelled = SyntheticDirectionalWire("cancel")
    do { _ = try await run(cancelled); XCTFail("Cancellation swallowed") } catch { XCTAssertTrue(error is CancellationError) }
  }
}

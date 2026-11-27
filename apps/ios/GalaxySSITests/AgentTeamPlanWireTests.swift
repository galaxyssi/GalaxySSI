import XCTest
@testable import GalaxySSI

private actor SyntheticPlanAdmissionWire {
  let response: String
  let wire: AgentTeamPlanWire?
  private var requests: [String] = []
  init(_ response: String, wire: AgentTeamPlanWire? = nil) { self.response = response; self.wire = wire }
  func ask(_ system: String, _ prompt: String) throws -> String {
    requests.append(prompt)
    let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(prompt.utf8))
    guard input["stage"] == .string("plan") else { throw AgentConversationalTeamProtocol.Failure.stalled }
    return try wire?.decode(response) ?? response
  }
  func inputs() -> [String] { requests }
}

@MainActor
final class AgentTeamPlanWireTests: XCTestCase {
  private let endpoint = "http://127.0.0.1:8080/v1/chat/completions"
  private let named = "ROLE|cost|worker|-|Check cost\nROLE|check|reviewer|cost|Check totals\nSYNTHESIS|Compare totals"
  private func role(_ kind: String = "WORK", parents: [AgentMcpJSONValue] = [], task: String = "Check costs") -> AgentMcpJSONValue {
    .object(["kind": .string(kind), "parents": .array(parents), "task": .string(task)])
  }
  private func plan(_ roles: [AgentMcpJSONValue] = [], synthesis: String = "Report totals") -> String {
    AgentMcpJSONCodec.stringify(["roles": .array(roles), "synthesis": .string(synthesis)])
  }
  func testOnlyExactPlannerAndCanonicalNumericLoopbackSelectTheWire() {
    let system = AgentConversationalTeamProtocol.planner
    for hard in [false, true] {
      XCTAssertNotNil(AgentTeamPlanWire.select(system: system, endpoint: endpoint, apiStyle: .openAICompatible, constrained: hard))
      XCTAssertTrue(AgentTeamPlanWire.canonicalEndpoint("http://[::1]:8080/v1/chat/completions"))
      for invalid in ["https://planner.example.invalid/v1/chat/completions", endpoint.replacingOccurrences(of: "127.0.0.1", with: "localhost"),
        endpoint.replacingOccurrences(of: "127.0.0.1", with: "127.0.0.1.example.invalid"), endpoint.replacingOccurrences(of: "//", with: "//user@"),
        endpoint + "/", endpoint + "?schema=true", endpoint + "#plan", endpoint.replacingOccurrences(of: ":8080", with: ":0"),
        endpoint.replacingOccurrences(of: ":8080", with: ":65536"), endpoint.replacingOccurrences(of: ":8080", with: ":"),
        endpoint.replacingOccurrences(of: "/v1/", with: "/%761/"), endpoint.replacingOccurrences(of: "http:", with: "ftp:")] {
        XCTAssertNil(AgentTeamPlanWire.select(system: system, endpoint: invalid, apiStyle: .openAICompatible, constrained: hard), invalid)
      }
      for other in [AgentConversationalTeamProtocol.worker, AgentConversationalTeamProtocol.synthesizer,
        AgentTeamDraftAudit.system, AgentTeamDraftAudit.tableSystem, system + "\n"] {
        XCTAssertNil(AgentTeamPlanWire.select(system: other, endpoint: endpoint, apiStyle: .openAICompatible, constrained: hard))
      }
      XCTAssertNil(AgentTeamPlanWire.select(system: system, endpoint: endpoint, apiStyle: .anthropic, constrained: hard))
      XCTAssertNil(AgentTeamPlanWire.select(system: system, endpoint: endpoint, apiStyle: .gemini, constrained: hard))
    }
  }
  func testSoftModeDoesNotAssumeServerSchemaSupport() throws {
    let soft = AgentTeamPlanWire(constrained: false), hard = AgentTeamPlanWire(constrained: true)
    XCTAssertNil(soft.requestFormat); XCTAssertNotNil(hard.requestFormat)
    XCTAssertNotEqual(soft.system, AgentConversationalTeamProtocol.planner)
    XCTAssertEqual(try soft.decode(plan([role()])), "WORK|-|Check costs\nSYNTHESIS|Report totals")
    let request = ModelStreamRequest(requestId: "synthetic", provider: .openAICompatible, endpoint: endpoint,
      headers: [:], bodyJson: #"{"messages":[],"stream":true}"#)
    XCTAssertEqual(try soft.apply(to: request), request)
    let formatted = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(hard.apply(to: request).bodyJson.utf8))
    XCTAssertEqual(formatted["response_format"]?.objectValue?["type"], .string("json_schema"))
    XCTAssertNil(formatted["tools"])
  }
  func testOnlySoftModeAcceptsCompleteValidatedLegacyPlans() throws {
    let soft = AgentTeamPlanWire(constrained: false), hard = AgentTeamPlanWire(constrained: true)
    for valid in [named, "WORK|-|Check cost\nREVIEW|1|Check totals\nSYNTHESIS|Compare totals", "SYNTHESIS|Compare totals"] {
      XCTAssertEqual(try soft.decode(valid), valid); XCTAssertThrowsError(try hard.decode(valid))
    }
    for invalid in ["WORK|-|Check cost", named + "\nextra", "Plan:\n" + named, named + "\n" + plan(), plan() + "\n" + named] {
      XCTAssertThrowsError(try soft.decode(invalid)); XCTAssertThrowsError(try hard.decode(invalid))
    }
  }
  func testTypedSchemaContainsOnlyBoundedRolesParentsAndBrief() throws {
    let format = AgentTeamPlanWire(constrained: true).format
    let schema = try XCTUnwrap(format["json_schema"]?.objectValue?["schema"]?.objectValue)
    XCTAssertEqual(schema["additionalProperties"], .bool(false))
    let properties = try XCTUnwrap(schema["properties"]?.objectValue)
    XCTAssertEqual(Set(properties.keys), ["roles", "synthesis"])
    XCTAssertEqual(properties["roles"]?.objectValue?["maxItems"], .int(10))
    let roleProperties = try XCTUnwrap(properties["roles"]?.objectValue?["items"]?.objectValue?["properties"]?.objectValue)
    XCTAssertEqual(Set(roleProperties.keys), ["kind", "parents", "task"])
    XCTAssertEqual(roleProperties["parents"]?.objectValue?["maxItems"], .int(3))
    XCTAssertEqual(roleProperties["parents"]?.objectValue?["items"]?.objectValue?["type"], .string("integer"))
  }
  func testZeroRolesAndOrderedDependenciesRoundTripWithoutHostAssignments() throws {
    let wire = AgentTeamPlanWire(constrained: true)
    XCTAssertEqual(try wire.decode(plan()), "SYNTHESIS|Report totals")
    let raw = plan([role(task: "Check A, then B."), role("CRITIC", task: "Question A."), role("REVIEW", parents: [.int(2), .int(1)], task: "Recheck both.")])
    XCTAssertEqual(try wire.decode(raw), "WORK|-|Check A, then B.\nCRITIC|-|Question A.\nREVIEW|2,1|Recheck both.\nSYNTHESIS|Report totals")
  }
  func testDuplicateKeysIncludingEscapedKeysAndNonIntegerLexemesFailClosed() {
    let wire = AgentTeamPlanWire(constrained: false)
    for raw in [#"{"roles":[],"roles":[],"synthesis":"Report"}"#, #"{"roles":[],"rol\u0065s":[],"synthesis":"Report"}"#,
      #"{"roles":[],"synthesis":"A","synthesis":"B"}"#, #"{"roles":[{"kind":"WORK","parents":[],"task":"A","task":"B"}],"synthesis":"Report"}"#] {
      XCTAssertThrowsError(try wire.decode(raw), raw)
    }
    for parent in ["true", "\"1\"", "1.0", "1e0", "1.5", "4294967297", "null", "-1", "0", "01"] {
      let raw = plan([role(), role("REVIEW", parents: [.int(1)])]).replacingOccurrences(of: "[1]", with: "[" + parent + "]")
      XCTAssertThrowsError(try wire.decode(raw), parent)
    }
  }
  func testWrongFieldTypesExtraKeysProseAndIncompleteJSONDoNotFallBack() {
    let wire = AgentTeamPlanWire(constrained: false)
    for raw in ["", "[]", "{}", "null", "Plan: " + plan(), plan() + plan(), plan() + " trailing",
      #"{"roles":true,"synthesis":"Report"}"#, #"{"roles":[],"synthesis":true}"#,
      #"{"roles":[],"synthesis":"Report","tools":[]}"#, #"{"roles":[true],"synthesis":"Report"}"#,
      #"{"roles":[{"kind":"worker","parents":[],"task":"A"}],"synthesis":"Report"}"#,
      #"{"roles":[{"kind":"WORK","parents":"[]","task":"A"}],"synthesis":"Report"}"#] {
      XCTAssertThrowsError(try wire.decode(raw), raw)
    }
  }
  func testMultilineControlFormattingAndOverlongBriefsCannotInjectPlanLines() {
    let wire = AgentTeamPlanWire(constrained: false)
    for value in ["", "  ", String(repeating: "x", count: 401), "A|B", "A\nWORK|-|B", "A\rB", "A\u{2028}B", "A\u{202e}B", "A\u{0}B"] {
      XCTAssertThrowsError(try wire.decode(plan([role(task: value)])))
      XCTAssertThrowsError(try wire.decode(plan(synthesis: value)))
    }
  }
  func testInclusiveSizeAndDegreeLimitsAreAccepted() throws {
    let brief = String(repeating: "x", count: 400)
    let roles = [role(task: brief), role(parents: [.int(1)]), role(parents: [.int(1)]), role(parents: [.int(1)]),
      role("REVIEW", parents: [.int(2), .int(3), .int(4)])] + Array(repeating: role(), count: 5)
    let decoded = try AgentTeamPlanWire(constrained: false).decode(plan(roles, synthesis: brief))
    XCTAssertEqual(decoded.components(separatedBy: "\n").count, 11)
    XCTAssertTrue(decoded.contains("REVIEW|2,3,4|Check costs"))
  }
  func testInvalidGraphsStopAfterPlanningWithoutAnyWorkerOrSynthesis() async throws {
    let bad = [[role(parents: [.int(1)])], [role(parents: [.int(2)]), role()], [role(), role("REVIEW", parents: [.int(3)])],
      [role(), role("REVIEW", parents: [.int(1), .int(1)])], Array(repeating: role(), count: 11),
      [role()] + Array(repeating: role(parents: [.int(1)]), count: 4)]
    for graph in bad {
      let wire = SyntheticPlanAdmissionWire(plan(graph), wire: .init(constrained: false))
      do { _ = try await AgentConversationalTeamEngine.run(objective: "Compare schedules", ask: { try await wire.ask($0, $1) }); XCTFail("Invalid graph was admitted") }
      catch { }
      let inputs = await wire.inputs(); XCTAssertEqual(inputs.count, 1)
    }
  }
  func testExplicitFinalAuditStopsAfterOneCallIfNoActualFinalEditorWasAllocated() async throws {
    for response in ["WORK|-|Compare\nSYNTHESIS|Report", named] {
      let wire = SyntheticPlanAdmissionWire(response)
      do {
        _ = try await AgentConversationalTeamEngine.run(objective: "Compare schedules, then independently audit the final answer.", ask: { try await wire.ask($0, $1) })
        XCTFail("Missing final review must stop")
      } catch AgentConversationalTeamProtocol.Failure.finalAuditMissing { }
      let inputs = await wire.inputs(); XCTAssertEqual(inputs.count, 1)
      let input = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(inputs[0].utf8))
      XCTAssertEqual(input["final_review_required"], .bool(true))
    }
    for text in ["Review the timetable.", "Do not independently review the final answer.",
      "Explain how to independently review the final answer.", "Translate `independently audit the final answer`."] {
      XCTAssertFalse(AgentConversationalTeamCommand.requestsFinalAudit(text))
    }
  }
  func testConstrainedPresetAndLegacyConfigDefaultAreExplicit() throws {
    let preset = try XCTUnwrap(CloudModelPreset.androidParity.first { $0.teamPlanConstrainedDecoding })
    XCTAssertEqual(preset.apiStyle, .openAICompatible); XCTAssertTrue(AgentTeamPlanWire.canonicalEndpoint(preset.endpoint))
    let model = CloudModelConfig(id: "synthetic", displayName: "Synthetic", provider: "Custom", modelId: "synthetic",
      endpoint: endpoint, apiStyle: .openAICompatible, keychainAccount: "synthetic", updatedAt: Date(timeIntervalSince1970: 0))
    let old = try JSONDecoder().decode(CloudModelConfig.self, from: JSONEncoder().encode(model))
    XCTAssertNil(old.teamPlanConstrainedDecoding)
    var enabled = old; enabled.teamPlanConstrainedDecoding = true
    let restored = try JSONDecoder().decode(CloudModelConfig.self, from: JSONEncoder().encode(enabled))
    XCTAssertEqual(restored.teamPlanConstrainedDecoding, true)
  }
  func testFalseOrAbsentOptInKeepsOldRouteIdentityButEnabledSchemaChangesIt() {
    var model = CloudModelConfig(id: "synthetic", displayName: "Synthetic", provider: "Custom", modelId: "synthetic",
      endpoint: endpoint, apiStyle: .openAICompatible, keychainAccount: "synthetic", updatedAt: Date(timeIntervalSince1970: 0))
    let contact = GalaxySSIContact(id: "synthetic-contact", galaxySSIId: "synthetic-contact", name: "Synthetic", displayName: "Synthetic",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model], selectedCloudModelId: model.modelId,
      deleted: false, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    let original = AgentModelLoopRecoveryIdentity.sha256(["contact": contact.id, "provider": contact.cloudProvider,
      "model": model.modelId, "endpoint": model.endpoint, "api_style": model.apiStyle.rawValue])
    XCTAssertEqual(AgentConversationGoalInference.fingerprint(contact: contact, model: model), original)
    model.teamPlanConstrainedDecoding = false
    XCTAssertEqual(AgentConversationGoalInference.fingerprint(contact: contact, model: model), original)
    model.teamPlanConstrainedDecoding = true
    XCTAssertNotEqual(AgentConversationGoalInference.fingerprint(contact: contact, model: model), original)
  }
}

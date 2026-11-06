import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelPlanParserTests: XCTestCase {
  func testRejectionDiagnosticsDistinguishSyntaxToolGraphAndCompletion() {
    let cases: [(String, String, String)] = [
      ("{", "$", "invalid_json"),
      (#"{"actions":{}}"#, "actions", "array_required"),
      (#"{"actions":[]}"#, "actions", "batch_size"),
      (#"{"actions":[{"ref":"same","kind":"READ_SCREEN"},{"ref":"same","kind":"READ_SCREEN"}]}"#,
        "actions[1].ref", "duplicate_ref"),
      (#"{"actions":[{"kind":"CALL_NATIVE_TOOL","parameters":{"tool_id":"invented-private-marker"}}]}"#,
        "actions[0].parameters.tool_id", "native_tool_unavailable"),
      (#"{"actions":[{"kind":"READ_SCREEN","depends_on":["later"]},{"ref":"later","kind":"READ_SCREEN"}]}"#,
        "actions[0].depends_on", "invalid_dependency"),
      (#"{"actions":[{"kind":"READ_SCREEN"},{"kind":"TASK_COMPLETE","description":"Done"}]}"#,
        "actions", "completion_mixed_with_execution")
    ]
    let settings = AgentModelPlannerSettings(maxActions: 4, multiAgentCoordination: true)
    for (raw, field, code) in cases {
      guard case .failure(let rejection) = AgentModelPlanParser.parseWithDiagnostics(
        request: request(), raw: raw, settings: settings, context: context()
      ) else { XCTFail("Expected local rejection for \(field)"); continue }
      XCTAssertEqual(rejection.field, field)
      XCTAssertEqual(rejection.code, code)
      XCTAssertFalse(rejection.correction.isEmpty)
      XCTAssertFalse(rejection.repairInstruction.contains("invented-private-marker"))
      XCTAssertNil(AgentModelPlanParser.parse(request: request(), raw: raw, settings: settings, context: context()))
    }
  }

  func testPhoneReadAndCompletionMustUseSeparateResponses() throws {
    let battery = AgentIOSHardwareNativeToolCatalog.batteryStatus
    let tools = AgentIOSHardwareNativeToolCatalog.descriptors().filter { $0.id == battery }
    var previous = AgentCompletionRequirements(publication: .none, phoneLinux: false)
    let settings = AgentModelPlannerSettings(maxActions: 4)
    let read = """
    {"ref":"battery","kind":"CALL_NATIVE_TOOL","parameters":{"tool_id":"\(battery)","arguments":{}}}
    """
    let completion = #"{"kind":"DRAFT_PLAN","target":"task-complete","description":"Battery level is 64 percent.","parameters":{},"depends_on":[],"use_outputs_from":[]}"#
    func parse(_ raw: String, review: Bool = false) -> Result<AgentPlan, AgentModelPlanRejection> {
      AgentModelPlanParser.parseWithDiagnostics(
        request: AgentPlanRequest(goal: "Read this phone's battery level",
          screen: AgentScreenContext(foregroundApp: "GalaxySSI"), nativeTools: tools,
          completionRequirements: previous),
        raw: raw, settings: settings,
        context: context(replanReason: review ? "rolling_batch_completed:revision=1" : ""),
        allowsNativeDependencies: true
      )
    }
    XCTAssertEqual(try parse("{\"actions\":[\(read)]}").get().actions.first?.kind, .callNativeTool)
    for kind in ["DRAFT_PLAN", "TASK_COMPLETE"] {
      let mixed = """
      {"actions":[\(read),{"kind":"\(kind)","target":"task-complete","description":"Done","depends_on":["battery"]}]}
      """
      guard case .failure(let rejection) = parse(mixed, review: true) else {
        return XCTFail("A speculative completion was admitted")
      }
      XCTAssertEqual(rejection.code, "completion_mixed_with_execution")
    }
    XCTAssertThrowsError(try parse("{\"actions\":[\(completion)]}").get())

    func reviewed(_ id: String, reason: String) -> String {
      """
      {"completion_requirements":{"publication":"none","phone_linux":false,"reason":"\(reason)",
      "outcomes":[{"id":"\(id)","tool_id":"\(battery)","subject":{"/metadata/device":"fixture"},
      "checks":{"/metadata/percent":64},"after_tool_id":""}]},"actions":[\(completion)]}
      """
    }
    XCTAssertThrowsError(try parse(reviewed("battery-level", reason: ""), review: true).get())
    let final = try parse(reviewed("battery-level", reason: "Bind the fields from the battery read."), review: true).get()
    XCTAssertEqual(final.actions.map(\.kind), [.draftPlan])
    XCTAssertEqual(final.completionRequirements?.outcomes?.first?.checks["/metadata/percent"], .int(64))
    previous = try XCTUnwrap(final.completionRequirements)
    XCTAssertThrowsError(try parse(reviewed("unrelated", reason: "Replace the outcome."), review: true).get())
  }

  func testSerialHardwareReadsShareAPlanButDispatchInOrder() throws {
    let battery = AgentIOSHardwareNativeToolCatalog.batteryStatus
    let storage = AgentIOSHardwareNativeToolCatalog.storageStatus
    let ids = [battery, storage, AgentIOSHardwareNativeToolCatalog.flashlightSet]
    let tools = AgentIOSHardwareNativeToolCatalog.descriptors().filter { ids.contains($0.id) }
    let descriptors = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
    let planRequest = AgentPlanRequest(goal: "Read phone battery and storage",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"), nativeTools: tools)
    let settings = AgentModelPlannerSettings(multiAgentCoordination: false)
    let raw = """
    {"actions":[
      {"ref":"battery","kind":"CALL_NATIVE_TOOL","parameters":{"tool_id":"\(battery)","arguments":{}}},
      {"ref":"storage","kind":"CALL_NATIVE_TOOL","depends_on":[],"parameters":{"tool_id":"\(storage)","arguments":{}}}]}
    """
    func parse(_ raw: String) -> Result<AgentPlan, AgentModelPlanRejection> {
      AgentModelPlanParser.parseWithDiagnostics(request: planRequest, raw: raw, settings: settings,
        allowsNativeDependencies: true)
    }
    var plan = try parse(raw).get()
    XCTAssertTrue(AgentPlanExecutionBatchPolicy.accepts(actions: plan.actions, descriptorFor: { descriptors[$0] }))
    for id in [battery, storage] {
      XCTAssertEqual(descriptors[id]?.concurrency, .serial)
      XCTAssertEqual(descriptors[id]?.requiresEffectClaim, false)
    }
    let first = AgentPlanExecutionBatchPolicy.select(plan: plan, maximumParallelReads: 8,
      descriptorFor: { descriptors[$0] })
    XCTAssertFalse(first.parallel)
    XCTAssertEqual(first.actions.compactMap { $0.parameters["tool_id"] }, [battery])
    plan.actions[0].status = .completed
    let second = AgentPlanExecutionBatchPolicy.select(plan: plan, maximumParallelReads: 8, workspaceId: "thread",
      descriptorFor: { descriptors[$0] })
    XCTAssertFalse(second.parallel)
    XCTAssertEqual(second.actions.compactMap { $0.parameters["tool_id"] }, [storage])
    let ordered = try parse(raw.replacingOccurrences(of: #""depends_on":[]"#, with: #""depends_on":["battery"]"#)).get()
    XCTAssertEqual(ordered.actions[1].parameters["depends_on"], ordered.actions[0].id)
    for bad in [#""depends_on":["model-1-battery"]"#, #""depends_on":["storage"]"#, #""depends_on":"battery""#] {
      let rejected = parse(raw.replacingOccurrences(of: #""depends_on":[]"#, with: bad))
      guard case .failure(let error) = rejected else { XCTFail("Invalid graph accepted"); continue }
      XCTAssertEqual(error.field, "actions[1].depends_on")
      XCTAssertEqual(error.code, "invalid_dependency")
      if bad.contains("[") { XCTAssertTrue(error.correction.contains("Available earlier refs: battery")) }
    }
    var mutation = plan.actions[1]
    let flashlight = AgentIOSHardwareNativeToolCatalog.flashlightSet
    mutation.target = flashlight
    mutation.parameters["tool_id"] = flashlight
    XCTAssertEqual(AgentPlanExecutionBatchPolicy.rejectionReason(actions: [plan.actions[0], mutation],
      descriptorFor: { descriptors[$0] }), "unordered_resource_conflict")
    let prompt = AgentModelPlanningPrompt.build(request: AgentModelPlanningPromptRequest(
      planRequest: planRequest, phoneOwnsExecution: true), settings: settings)
    XCTAssertTrue(prompt.contains("effect=read_only | concurrency=serial"))
    XCTAssertTrue(prompt.contains("depends_on names earlier refs"))
  }

  func testAgentModelPlanParserBuildsBoundedExecutablePlanFromFencedJson() throws {
    let descriptor = try nativeToolDescriptor(id: "galaxyssi.web.search", risk: .low)
    let raw = """
    ```json
    {
      "expected_result": "Search result captured",
      "rollback_strategy": "Stop and report the last verified receipt.",
      "actions": [
        {"ref": "read", "kind": "READ_SCREEN", "description": "Read visible context", "parameters": {}},
        {"ref": "search", "kind": "CALL_NATIVE_TOOL", "description": "Search locally",
         "depends_on": ["read"], "parameters": {
          "tool_id": "galaxyssi.web.search",
          "arguments": {"query": "GalaxySSI iOS"}
        }},
        {"ref": "finish", "kind": "CALL_CONNECTOR", "target": "Codex",
         "depends_on": ["search"], "use_outputs_from": ["search"],
         "parameters": {"connector_id": "desktop:codex", "prompt": "Summarize result"}}
      ]
    }
    ```
    """

    let plan = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(nativeTools: [descriptor]),
      raw: raw,
      settings: AgentModelPlannerSettings(maxActions: 3, multiAgentCoordination: true),
      context: context()
    ))

    XCTAssertEqual(plan.actions.map(\.id), ["model-1-read", "model-2-search", "model-3-finish"])
    XCTAssertEqual(plan.expectedResult, "Search result captured")
    XCTAssertEqual(plan.rollbackStrategy, "Stop and report the last verified receipt.")
    XCTAssertEqual(plan.actions[1].parameters["tool_id"], "galaxyssi.web.search")
    XCTAssertEqual(plan.actions[1].parameters["tool_version"], "1.0.0")
    XCTAssertEqual(plan.actions[1].parameters["native_tool_risk"], "low")
    XCTAssertEqual(plan.actions[1].parameters["input_json"], #"{"query":"GalaxySSI iOS"}"#)
    XCTAssertEqual(plan.actions[2].parameters["depends_on"], "model-2-search")
    XCTAssertEqual(plan.actions[2].parameters["use_outputs_from"], "model-2-search")
    XCTAssertEqual(plan.route.kind, .desktopAgent)
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentModelPlanParserResolvesScreenElementsAppsUrlsAndNotifications() throws {
    let raw = """
    {"actions":[
      {"ref":"tap_continue","kind":"TAP","parameters":{"element_query":"continue"}},
      {"ref":"type_email","kind":"TYPE_TEXT","depends_on":["tap_continue"],"parameters":{"field_query":"email","text":"a@example.com"}},
      {"ref":"open_app","kind":"OPEN_APP","parameters":{"package":"com.apple.mobilesafari"}},
      {"ref":"open_url","kind":"OPEN_URL","parameters":{"url":"https://galaxyssi.com/docs"}},
      {"ref":"notify","kind":"CREATE_NOTIFICATION","parameters":{"text":"Done"}}
    ]}
    """

    let plan = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(),
      raw: raw,
      settings: AgentModelPlannerSettings(maxActions: 5),
      context: context()
    ))

    XCTAssertEqual(plan.actions[0].parameters["bounds"], "0,0,100,44")
    XCTAssertEqual(plan.actions[1].parameters["field_bounds"], "0,100,300,144")
    XCTAssertEqual(plan.actions[1].parameters["text"], "a@example.com")
    XCTAssertEqual(plan.actions[2].target, "Safari")
    XCTAssertEqual(plan.actions[3].parameters["url"], "https://galaxyssi.com/docs")
    XCTAssertEqual(plan.actions[4].parameters["title"], "GalaxySSI Agent")
  }

  func testAgentModelPlanParserRejectsOversizedUnknownAndUnsafePlans() throws {
    let validTwoActions = planJson(
      actionJson(ref: "first", kind: "READ_SCREEN"),
      actionJson(ref: "second", kind: "BACK")
    )
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: validTwoActions,
      settings: AgentModelPlannerSettings(maxActions: 1),
      context: context()
    ))
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson(actionJson(ref: "bad", kind: "REPLY_NOTIFICATION")),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson("""
      {"ref":"bad_url","kind":"OPEN_URL","parameters":{"url":"file:///private/var/mobile/secret"}}
      """),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson("""
      {"ref":"password","kind":"TYPE_TEXT","parameters":{"field_query":"password","text":"secret"}}
      """),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
  }

  func testAgentModelPlanParserAllowsPhoneRuntimeBatchOverride() {
    let actions = (1...13).map { index in
      actionJson(ref: "read_\(index)", kind: "READ_SCREEN")
    }
    let raw = #"{"actions":["# + actions.joined(separator: ",") + #"]}"#

    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: raw,
      settings: AgentModelPlannerSettings(maxActions: 12),
      context: context()
    ))
    XCTAssertEqual(AgentModelPlanParser.parse(
      request: request(),
      raw: raw,
      settings: AgentModelPlannerSettings(maxActions: 12),
      context: AgentModelPlanParsingContext(maximumActionsOverride: 64)
    )?.actions.count, 13)
  }

  func testAgentModelPlanParserEnforcesDependencyAndOutputGraphPolicy() throws {
    let dependencyPlan = planJson(
      actionJson(ref: "first", kind: "READ_SCREEN"),
      actionJson(ref: "second", kind: "BACK", dependsOn: ["first"])
    )
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: dependencyPlan,
      settings: AgentModelPlannerSettings(multiAgentCoordination: false),
      context: context()
    ))
    XCTAssertNotNil(AgentModelPlanParser.parse(
      request: request(),
      raw: dependencyPlan,
      settings: AgentModelPlannerSettings(multiAgentCoordination: true),
      context: context()
    ))

    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson(
        actionJson(ref: "first", kind: "READ_SCREEN"),
        actionJson(ref: "second", kind: "BACK", dependsOn: ["third"]),
        actionJson(ref: "third", kind: "HOME")
      ),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson(
        actionJson(ref: "first", kind: "READ_SCREEN"),
        actionJson(ref: "second", kind: "BACK", dependsOn: ["first"], outputs: ["first"])
      ),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
  }

  func testAgentModelPlanParserLimitsAgentGraphDepthAndDraftPlanSemantics() throws {
    let deepPlan = planJson(
      actionJson(ref: "first", kind: "READ_SCREEN"),
      actionJson(ref: "second", kind: "BACK", dependsOn: ["first"]),
      actionJson(ref: "third", kind: "HOME", dependsOn: ["second"])
    )

    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: deepPlan,
      settings: AgentModelPlannerSettings(maxAgentHops: 2),
      context: context()
    ))
    XCTAssertNotNil(AgentModelPlanParser.parse(
      request: request(),
      raw: deepPlan,
      settings: AgentModelPlannerSettings(maxAgentHops: 3),
      context: context()
    ))

    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(),
      raw: planJson(actionJson(ref: "draft", kind: "DRAFT_PLAN", target: "local-agent-runtime")),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    let completed = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(),
      raw: #"{"actions":[{"ref":"done","kind":"DRAFT_PLAN","target":"task-complete","description":"Verified answer."}]}"#,
      settings: AgentModelPlannerSettings(),
      context: context(replanReason: "connector_response_received")
    ))
    XCTAssertEqual(completed.actions.singleValue().target, "task-complete")
  }

  func testAnswerOnlyAliasesAndStructuredRepairPreserveTheAnswer() throws {
    let answer = "Verified answer with [source](https://example.com/reference)."
    for kind in ["task-complete", "TASK_COMPLETE"] {
      let raw = """
      {"actions":[{"kind":"\(kind)","description":"\(answer)","parameters":{}}]}
      """
      XCTAssertEqual(AgentModelPlanParser.answerOnlyAction(raw), answer)
      XCTAssertNil(AgentModelPlanParser.answerOnlyAction(raw.replacingOccurrences(of: "\"parameters\":{}",
        with: "\"parameters\":{\"tool_id\":\"galaxyssi.runtime.execute\"}")))
      XCTAssertNil(AgentModelPlanParser.answerOnlyAction(raw.replacingOccurrences(of: "\"parameters\":{}",
        with: "\"execution_site\":\"phone\"")))
    }
    let envelope = """
    {"disposition":"respond","final_response":"\(answer)"}
    """
    let repaired = try XCTUnwrap(AgentModelPlanParser.parse(request: request(), raw: envelope,
      settings: AgentModelPlannerSettings(), context: context(replanReason: AgentRollingPlanPolicy.replanReasonPrefix + "repair")))
    XCTAssertEqual(repaired.actions.singleValue().description, answer)
    XCTAssertNil(AgentModelDirectResponseCodec.parse(#"{"disposition":"respond","final_response":"<tool_call>fake</tool_call>"}"#))
    XCTAssertNil(AgentModelDirectResponseCodec.parse(#"{"disposition":"respond","final_response":"Answer","actions":[]}"#))
  }

  func testAgentModelPlanParserRejectsUnavailableNativeToolAndConnector() throws {
    let unavailableTool = try nativeToolDescriptor(
      id: "galaxyssi.web.search",
      availability: AgentNativeToolAvailability(status: .requiresSetup)
    )
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(nativeTools: [unavailableTool]),
      raw: planJson("""
      {"ref":"tool","kind":"CALL_NATIVE_TOOL","parameters":{"tool_id":"galaxyssi.web.search","arguments":{}}}
      """),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(targets: [target(status: .needsSetup)]),
      raw: planJson("""
      {"ref":"connector","kind":"CALL_CONNECTOR","parameters":{"connector_id":"desktop:codex","prompt":"Run"}}
      """),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
  }

  func testAgentModelPlanParserPreservesAndValidatesCompletionRequirements() throws {
    let previous = AgentCompletionRequirements(publication: .commit, phoneLinux: true)
    let inherited = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(completionRequirements: previous),
      raw: planJson(actionJson(ref: "read", kind: "READ_SCREEN")),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertEqual(inherited.completionRequirements, previous)

    let changedWithoutReason = """
    {"completion_requirements":{"publication":"none","phone_linux":false},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(completionRequirements: previous),
      raw: changedWithoutReason,
      settings: AgentModelPlannerSettings(),
      context: context()
    ))

    let corrected = """
    {"completion_requirements":{"publication":"none","phone_linux":false,
     "reason":"The user explicitly excluded committing and Linux execution."},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    let parsed = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(completionRequirements: previous),
      raw: corrected,
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
    XCTAssertEqual(parsed.completionRequirements?.publication, .none)
    XCTAssertEqual(parsed.completionRequirements?.phoneLinux, false)
    XCTAssertFalse(parsed.completionRequirements?.reason.isEmpty ?? true)

    let malformed = """
    {"completion_requirements":{"publication":"none","phone_linux":"false"},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    XCTAssertNil(AgentModelPlanParser.parse(
      request: request(completionRequirements: previous),
      raw: malformed,
      settings: AgentModelPlannerSettings(),
      context: context()
    ))
  }

  func testMalformedObservedOutcomeReturnsARejection() {
    let raw = """
    {"completion_requirements":{"publication":"none","phone_linux":false,"outcomes":{}},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    let result = AgentModelPlanParser.parseWithDiagnostics(request: request(), raw: raw,
      settings: AgentModelPlannerSettings(), context: context())
    guard case .failure(let rejection) = result else { return XCTFail("Invalid outcomes were accepted") }
    XCTAssertEqual(rejection.field, "completion_requirements.outcomes")
    XCTAssertEqual(rejection.code, "invalid_completion_shape")
  }

  func testFileAndVideoCompletionRequirementsRemainIndependent() throws {
    let raw = """
    {"completion_requirements":{"publication":"none","phone_linux":false,
      "artifacts":[{"path":"demo.mp4","workspace_id":"workspace"}],
      "file_artifacts":[{"path":"report.txt","workspace_id":"workspace:linux"}]},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    let plan = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(), raw: raw, settings: AgentModelPlannerSettings(), context: context()
    ))
    let requirements = try XCTUnwrap(plan.completionRequirements)
    XCTAssertEqual(requirements.artifacts?.map(\.path), ["demo.mp4"])
    XCTAssertEqual(requirements.fileArtifacts?.map(\.path), ["report.txt"])
    XCTAssertEqual(try JSONDecoder().decode(AgentCompletionRequirements.self,
      from: JSONEncoder().encode(requirements)), requirements)
    XCTAssertNil(AgentModelPlanParser.parse(request: request(),
      raw: raw.replacingOccurrences(of: "demo.mp4", with: "demo.txt"),
      settings: AgentModelPlannerSettings(), context: context()))
  }

  func testRequestedResultIdsSurvivePersistenceAndCannotBeDropped() throws {
    let raw = """
    {"completion_requirements":{"publication":"none","phone_linux":false,"results":[
      {"id":"battery","description":"Battery percent"},
      {"id":"storage","description":"Available storage","outcome_ids":[],"artifact_paths":[],"answer":""}]},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    func parse(_ raw: String, previous: AgentCompletionRequirements? = nil) -> AgentPlan? {
      AgentModelPlanParser.parse(request: request(completionRequirements: previous), raw: raw,
        settings: AgentModelPlannerSettings(), context: context())
    }
    let plan = try XCTUnwrap(parse(raw))
    let persisted = try JSONDecoder().decode(AgentPlan.self, from: JSONEncoder().encode(plan))
    let previous = try XCTUnwrap(persisted.completionRequirements)
    XCTAssertEqual(previous.results?.map(\.id), ["battery", "storage"])
    XCTAssertEqual(previous.results?.first?.answer, "")
    XCTAssertNil(parse(raw.replacingOccurrences(of: #""id":"storage""#, with: #""id":"battery""#)))
    XCTAssertNil(parse(raw.replacingOccurrences(of: #""answer":"""#, with: #""answer":7"#)))
    XCTAssertNil(parse(raw.replacingOccurrences(of: #""artifact_paths":[]"#, with: #""artifact_paths":["../report.csv"]"#)))
    XCTAssertNil(parse(raw.replacingOccurrences(of: #""outcome_ids":[]"#, with: #""outcome_ids":[1]"#)))
    let erased = """
    {"completion_requirements":{"publication":"none","phone_linux":false,"reason":"Updated","results":[]},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    XCTAssertNil(parse(erased, previous: previous))
    let inherited = parse(planJson(actionJson(ref: "read", kind: "READ_SCREEN")), previous: previous)
    XCTAssertEqual(inherited?.completionRequirements?.results, previous.results)
    let changed = raw.replacingOccurrences(of: "Battery percent", with: "Battery state")
    XCTAssertNil(parse(changed, previous: previous))
    XCTAssertNotNil(parse(changed.replacingOccurrences(of: #""results":"#, with: #""reason":"Corrected the requested state","results":"#),
      previous: previous))
  }

  func testRequestedResultsRequireTypedEvidenceLinksAndEveryDeliveredAnswer() throws {
    let raw = """
    {"completion_requirements":{"publication":"none","phone_linux":false,
      "outcomes":[{"id":"battery-read","tool_id":"galaxyssi.hardware.device.status",
        "subject":{"/scope":"ios_app_visible_device"},"checks":{"/battery/percent":40}}],
      "file_artifacts":[{"path":"report.txt"}],
      "results":[{"id":"battery","description":"Battery percent","outcome_ids":["battery-read"],"answer":"Battery: 40%."},
                 {"id":"report","description":"Export report","artifact_paths":["report.txt"],"answer":"Report: report.txt."}]},
     "actions":[{"ref":"read","kind":"READ_SCREEN","parameters":{}}]}
    """
    let plan = try XCTUnwrap(AgentModelPlanParser.parse(request: request(), raw: raw,
      settings: AgentModelPlannerSettings(), context: context()))
    var requirements = try XCTUnwrap(plan.completionRequirements)
    let final = "Battery: 40%.\nReport: report.txt."
    XCTAssertTrue(AgentGoalResultEvidence.missing(requirements, finalAnswer: final, required: true).isEmpty)
    XCTAssertTrue(AgentGoalResultEvidence.missing(requirements, finalAnswer: "Battery: 40%.", required: true)
      .contains { $0.contains("report is missing from the final answer") })
    XCTAssertFalse(AgentCompletionEvidencePolicy.missingEvidence(requirements: requirements, history: []).isEmpty)
    requirements.fileArtifacts = nil
    XCTAssertTrue(AgentGoalResultEvidence.missing(requirements, finalAnswer: final, required: true)
      .contains { $0.contains("undeclared artifact report.txt") })
    XCTAssertFalse(AgentGoalResultEvidence.missing(nil, finalAnswer: final, required: true).isEmpty)
    XCTAssertTrue(AgentGoalResultEvidence.missing(nil, finalAnswer: final, required: false).isEmpty)
    let status = AgentAction(id: "status", kind: .callNativeTool, target: AgentIOSHardwareNativeToolCatalog.deviceStatus,
      risk: .low, status: .completed, description: "Inspect", evidence: #"{"scope":"ios_app_visible_device","battery":{"percent":40}}"#)
    XCTAssertTrue(AgentGoalResultEvidence.requiresDeclaration(for: [status]))
    XCTAssertTrue(AgentCompletionEvidencePolicy.missingEvidence(requirements: requirements, history: [status]).isEmpty)
    var stale = status
    stale.id = "later-read"
    stale.evidence = "{}"
    XCTAssertFalse(AgentCompletionEvidencePolicy.missingEvidence(requirements: requirements, history: [status, stale]).isEmpty)
  }

  func testDeviceByteLabelsUseBinaryUnits() {
    XCTAssertEqual(AgentIOSDeviceHealthStatusPresentation.formatBytes(1_023), "1023 B")
    XCTAssertEqual(AgentIOSDeviceHealthStatusPresentation.formatBytes(1_024), "1.0 KiB")
    XCTAssertEqual(AgentIOSDeviceHealthStatusPresentation.formatBytes(1_048_576), "1.0 MiB")
    XCTAssertEqual(AgentIOSDeviceHealthStatusPresentation.formatBytes(1_073_741_824), "1.0 GiB")
  }

  func testAgentModelPlanParserUsesMcpCallToolProvisionalRisk() throws {
    let callTool = try nativeToolDescriptor(id: AgentMcpNativeTools.callTool, risk: .low)
    let plan = try XCTUnwrap(AgentModelPlanParser.parse(
      request: request(nativeTools: [callTool]),
      raw: planJson("""
      {"ref":"mcp","kind":"CALL_NATIVE_TOOL","parameters":{
        "tool_id":"galaxyssi.mcp.tool.call",
        "arguments":{"tool_name":"delete_database_records"}
      }}
      """),
      settings: AgentModelPlannerSettings(),
      context: context()
    ))

    XCTAssertEqual(plan.actions.singleValue().parameters["native_tool_risk"], "high")
    XCTAssertEqual(plan.actions.singleValue().risk, .high)
  }

  private func request(
    targets: [AgentCallableTarget]? = nil,
    nativeTools: [AgentNativeToolDescriptor] = [],
    completionRequirements: AgentCompletionRequirements? = nil
  ) -> AgentPlanRequest {
    AgentPlanRequest(
      goal: "Complete the task",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent", isAccessibilityEnabled: true),
      targets: targets ?? [target()],
      nativeTools: nativeTools,
      contextDigest: "model-plan-parser-test",
      completionRequirements: completionRequirements
    )
  }

  private func context(replanReason: String = "") -> AgentModelPlanParsingContext {
    AgentModelPlanParsingContext(
      replanReason: replanReason,
      clickableElements: [
        AgentScreenElement(
          label: "Continue",
          viewId: "primary_action",
          className: "Button",
          bounds: "0,0,100,44",
          origin: .accessibility,
          confidence: 0.94,
          visualRole: .button
        )
      ],
      inputFields: [
        AgentScreenElement(
          label: "Email",
          viewId: "email",
          className: "TextField",
          bounds: "0,100,300,144",
          origin: .accessibility,
          confidence: 0.91,
          visualRole: .input
        ),
        AgentScreenElement(
          label: "Password",
          viewId: "password",
          className: "SecureTextField",
          bounds: "0,150,300,194",
          origin: .accessibility,
          confidence: 0.91,
          visualRole: .input
        )
      ],
      focusedInputField: AgentScreenElement(
        label: "Message",
        viewId: "message",
        className: "TextField",
        bounds: "0,200,300,244",
        visualRole: .input
      ),
      installedApps: [
        AgentModelPlanInstalledApp(packageName: "com.apple.mobilesafari", label: "Safari")
      ]
    )
  }

  private func target(
    id: String = "desktop:codex",
    title: String = "Codex",
    kind: AgentConnectorKind = .agent,
    status: AgentConnectorStatus = .available
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: kind,
      status: status,
      capabilities: [.chat, .reasoning],
      failureDomain: "desktop",
      desktopAccessProfile: GalaxySSILinkProtocol.accessDesktopExecutor
    )
  }

  private func nativeToolDescriptor(
    id: String,
    risk: AgentNativeToolRisk = .low,
    availability: AgentNativeToolAvailability = .available
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Test native tool",
      location: .phone,
      risk: risk,
      availability: availability
    )
  }

  private func planJson(_ actions: String...) -> String {
    #"{"actions":["# + actions.joined(separator: ",") + #"]}"#
  }

  private func actionJson(
    ref: String,
    kind: String,
    dependsOn: [String] = [],
    outputs: [String] = [],
    target: String = ""
  ) -> String {
    let dependencies = dependsOn.map { "\"\($0)\"" }.joined(separator: ",")
    let outputRefs = outputs.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"ref":"\(ref)","kind":"\(kind)","target":"\(target)","depends_on":[\(dependencies)],"use_outputs_from":[\(outputRefs)],"parameters":{}}
    """
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}

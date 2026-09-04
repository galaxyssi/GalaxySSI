import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelPlanParserTests: XCTestCase {
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
      raw: planJson(actionJson(ref: "done", kind: "DRAFT_PLAN", target: "task-complete")),
      settings: AgentModelPlannerSettings(),
      context: context(replanReason: "connector_response_received")
    ))
    XCTAssertEqual(completed.actions.singleValue().target, "task-complete")
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
    nativeTools: [AgentNativeToolDescriptor] = []
  ) -> AgentPlanRequest {
    AgentPlanRequest(
      goal: "Complete the task",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent", isAccessibilityEnabled: true),
      targets: targets ?? [target()],
      nativeTools: nativeTools,
      contextDigest: "model-plan-parser-test"
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

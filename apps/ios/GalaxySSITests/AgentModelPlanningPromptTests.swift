import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelPlanningPromptTests: XCTestCase {
  func testAgentModelPlanningPromptBuildsSchemaAndInventories() throws {
    let prompt = AgentModelPlanningPrompt.build(
      request: promptRequest(nativeTools: [
        try nativeToolDescriptor(id: AgentIOSWebIntelligenceNativeToolCatalog.search, title: "Search web")
      ]),
      settings: AgentModelPlannerSettings(maxActions: 4, shareScreenText: true)
    )

    XCTAssertTrue(prompt.contains("JSON schema:"))
    XCTAssertTrue(prompt.contains("\"actions\":[{\"ref\":\"step_name\""))
    XCTAssertTrue(prompt.contains("Allowed kinds:"))
    XCTAssertTrue(prompt.contains("Never create more than 4 actions."))
    XCTAssertTrue(prompt.contains("User goal: Research GalaxySSI and summarize"))
    XCTAssertTrue(prompt.contains("Visible text:"))
    XCTAssertTrue(prompt.contains("- Welcome to GalaxySSI"))
    XCTAssertTrue(prompt.contains("Clickable elements:"))
    XCTAssertTrue(prompt.contains("id=primary_action | label=Continue | bounds=0,0,100,44"))
    XCTAssertTrue(prompt.contains("Input fields:"))
    XCTAssertTrue(prompt.contains("id=search | label=Search | bounds=0,100,300,144"))
    XCTAssertTrue(prompt.contains("Installed apps:"))
    XCTAssertTrue(prompt.contains("Safari | com.apple.mobilesafari"))
    XCTAssertTrue(prompt.contains("Callable connectors:"))
    XCTAssertTrue(prompt.contains("desktop:codex | Codex | AGENT"))
    XCTAssertFalse(prompt.contains("desktop:offline"))
    XCTAssertTrue(prompt.contains("Phone-native tools:"))
    XCTAssertTrue(prompt.contains("\(AgentIOSWebIntelligenceNativeToolCatalog.search) | Search web | risk=low"))
  }

  func testAgentModelPlanningPromptUsesCompactLimitsAndDisablesGraphWhenRequested() throws {
    let visibleTexts = (0..<30).map { "visible-\($0)" }
    let apps = (0..<40).map {
      AgentModelPlanInstalledApp(packageName: "com.example.app\($0)", label: "App \($0)")
    }
    let prompt = AgentModelPlanningPrompt.build(
      request: promptRequest(
        visibleTexts: visibleTexts,
        parsingContext: context(installedApps: apps),
        requirements: AgentTaskRequirements(mode: .fast)
      ),
      settings: AgentModelPlannerSettings(shareScreenText: true, multiAgentCoordination: false)
    )

    XCTAssertLessThanOrEqual(prompt.count, 12_000)
    XCTAssertTrue(prompt.contains("Do not use depends_on or use_outputs_from."))
    XCTAssertTrue(prompt.contains("visible-15"))
    XCTAssertFalse(prompt.contains("visible-16"))
    XCTAssertTrue(prompt.contains("App 29 | com.example.app29"))
    XCTAssertFalse(prompt.contains("App 30 | com.example.app30"))
  }

  func testAgentModelPlanningPromptAddsReplanAndRedactsConnectorOutput() throws {
    let history = AgentAction(
      id: "codex",
      kind: .callConnector,
      target: "Codex",
      risk: .low,
      status: .completed,
      description: "Ask Codex",
      parameters: ["connector_id": "desktop:codex"],
      result: "The API key is sk-live-secret and should not be exposed."
    )
    let prompt = AgentModelPlanningPrompt.build(
      request: promptRequest(
        parsingContext: context(replanReason: "connector_response_received"),
        executionHistory: [history]
      ),
      settings: AgentModelPlannerSettings(shareAgentOutputsWithPlanner: true)
    )

    XCTAssertTrue(prompt.contains("Replan reason: connector_response_received"))
    XCTAssertTrue(prompt.contains("target task-complete"))
    XCTAssertTrue(prompt.contains("Execution history:"))
    XCTAssertTrue(prompt.contains("CALL_CONNECTOR | COMPLETED | Ask Codex"))
    XCTAssertTrue(prompt.contains("[redacted sensitive output]"))
    XCTAssertFalse(prompt.contains("sk-live-secret"))
  }

  func testAgentModelPlanningPromptRequestsBoundedRollingBatch() {
    let reason = "rolling_batch_completed:revision=4;completed=3;last_action=verify"
    let prompt = AgentModelPlanningPrompt.build(
      request: promptRequest(parsingContext: context(replanReason: reason)),
      settings: AgentModelPlannerSettings(maxActions: 6)
    )

    XCTAssertTrue(prompt.contains("Plan only the next bounded execution batch"))
    XCTAssertTrue(prompt.contains("prefer 3 to 6 actionable steps"))
    XCTAssertTrue(prompt.contains("The previous execution batch finished"))
    XCTAssertTrue(prompt.contains("add, remove, reorder, or replace future actions"))
    XCTAssertTrue(prompt.contains("finalize only when the requested outcome is actually verified"))
  }

  func testAgentModelPlanningPromptFiltersAndSortsRuntimeToolsByEligibility() throws {
    let runtime = try nativeToolDescriptor(id: AgentIOSOnDeviceRuntimeNativeToolCatalog.status, title: "Runtime status")
    let softwareSearch = try nativeToolDescriptor(
      id: AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSearch,
      title: "Search runtime software"
    )
    let workspace = try nativeToolDescriptor(id: AgentPhoneNativeToolCatalog.workspaceReadText, title: "Read workspace file")
    let web = try nativeToolDescriptor(id: AgentIOSWebIntelligenceNativeToolCatalog.search, title: "Search web")
    let blocked = try nativeToolDescriptor(
      id: "galaxyssi.local.blocked",
      title: "Blocked",
      availability: AgentNativeToolAvailability(status: .unavailable)
    )

    let ordinaryPrompt = AgentModelPlanningPrompt.build(
      request: promptRequest(nativeTools: [web, workspace, runtime, softwareSearch, blocked], allowsPhoneRuntimeTools: false),
      settings: AgentModelPlannerSettings()
    )
    XCTAssertFalse(ordinaryPrompt.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
    XCTAssertFalse(ordinaryPrompt.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSearch))
    XCTAssertFalse(ordinaryPrompt.contains(AgentPhoneNativeToolCatalog.workspaceReadText))
    XCTAssertFalse(ordinaryPrompt.contains("galaxyssi.local.blocked"))
    XCTAssertTrue(ordinaryPrompt.contains(AgentIOSWebIntelligenceNativeToolCatalog.search))

    let runtimePrompt = AgentModelPlanningPrompt.build(
      request: promptRequest(nativeTools: [web, workspace, runtime, softwareSearch], allowsPhoneRuntimeTools: true),
      settings: AgentModelPlannerSettings()
    )
    let runtimeIndex = try XCTUnwrap(runtimePrompt.range(of: AgentIOSOnDeviceRuntimeNativeToolCatalog.status)?.lowerBound)
    let softwareSearchIndex = try XCTUnwrap(runtimePrompt.range(of: AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSearch)?.lowerBound)
    let workspaceIndex = try XCTUnwrap(runtimePrompt.range(of: AgentPhoneNativeToolCatalog.workspaceReadText)?.lowerBound)
    let webIndex = try XCTUnwrap(runtimePrompt.range(of: AgentIOSWebIntelligenceNativeToolCatalog.search)?.lowerBound)

    XCTAssertLessThan(runtimeIndex, workspaceIndex)
    XCTAssertLessThan(softwareSearchIndex, workspaceIndex)
    XCTAssertLessThan(workspaceIndex, webIndex)
    XCTAssertTrue(runtimePrompt.contains("Use workspace_id=current"))
    XCTAssertTrue(runtimePrompt.contains(AgentIOSProjectRepositoryReadToolCatalog.observe))
    XCTAssertTrue(runtimePrompt.contains("repository status, diff, and history"))
    XCTAssertTrue(runtimePrompt.contains("prefer 3-8 independent reads or disjoint workspace mutations"))
    XCTAssertTrue(runtimePrompt.contains("up to 64 independent actions"))
    XCTAssertTrue(runtimePrompt.contains("Never batch runtime, installation, build, test"))
    XCTAssertTrue(runtimePrompt.contains("Use next_cursor for lists"))
    XCTAssertTrue(runtimePrompt.contains("choose a realistic task-aware timeout_ms"))
    XCTAssertTrue(runtimePrompt.contains("runtime watchdog use progress"))
  }

  func testAgentModelPlanningPromptRequestUsesAndroidWireNames() throws {
    let request = promptRequest(allowsPhoneRuntimeTools: true, allowsDirectResponse: true)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

    XCTAssertNotNil(object["plan_request"])
    XCTAssertNotNil(object["parsing_context"])
    XCTAssertNotNil(object["conversation_context"])
    XCTAssertNotNil(object["execution_history"])
    XCTAssertEqual(object["allows_phone_runtime_tools"] as? Bool, true)
    XCTAssertEqual(object["allows_direct_response"] as? Bool, true)
    XCTAssertNil(object["planRequest"])
    XCTAssertNil(object["parsingContext"])
    XCTAssertNil(object["allowsPhoneRuntimeTools"])
    XCTAssertNil(object["allowsDirectResponse"])
  }

  func testAgentModelPlanningPromptOffersDirectResponseOnlyForInitialEligibleTurn() {
    let directPrompt = AgentModelPlanningPrompt.build(
      request: promptRequest(allowsDirectResponse: true),
      settings: AgentModelPlannerSettings()
    )
    let actionOnlyPrompt = AgentModelPlanningPrompt.build(
      request: promptRequest(allowsDirectResponse: false),
      settings: AgentModelPlannerSettings()
    )

    XCTAssertTrue(directPrompt.contains("\"disposition\":\"respond\""))
    XCTAssertTrue(directPrompt.contains("Use the user's language"))
    XCTAssertTrue(directPrompt.contains("omit runtime, workspace, permission, and tool availability"))
    XCTAssertTrue(directPrompt.contains("ActionPlan JSON schema:"))
    XCTAssertFalse(actionOnlyPrompt.contains("\"disposition\":\"respond\""))
  }

  func testAgentModelPlanningPromptAppliesAndroidGlobalContextDispatchPolicy() {
    let globalContext = "Durable global memory should be reserved for real tasks."
    let context = AgentConversationContext(
      conversationId: "conversation-1",
      summary: "Earlier summary",
      turns: [],
      privateMode: false,
      globalContext: globalContext
    )
    let greeting = AgentModelPlanningPrompt.build(
      request: promptRequest(goal: "Hello!", conversationContext: context),
      settings: AgentModelPlannerSettings()
    )
    let attachedGreeting = AgentModelPlanningPrompt.build(
      request: promptRequest(goal: "hello", conversationContext: context, hasAttachments: true),
      settings: AgentModelPlannerSettings()
    )
    let taskGreeting = AgentModelPlanningPrompt.build(
      request: promptRequest(goal: "hello, summarize the attachment", conversationContext: context),
      settings: AgentModelPlannerSettings()
    )
    let freshTask = AgentModelPlanningPrompt.build(
      request: promptRequest(
        goal: "What is my name?",
        conversationContext: AgentConversationContext(
          conversationId: "new-session",
          summary: "",
          turns: [],
          privateMode: false,
          globalContext: globalContext
        )
      ),
      settings: AgentModelPlannerSettings()
    )
    let privateTask = AgentModelPlanningPrompt.build(
      request: promptRequest(
        goal: "What is my name?",
        conversationContext: AgentConversationContext(
          conversationId: "private-session",
          summary: "",
          turns: [],
          privateMode: true,
          globalContext: globalContext
        )
      ),
      settings: AgentModelPlannerSettings()
    )

    XCTAssertTrue(greeting.contains("Earlier summary"))
    XCTAssertFalse(greeting.contains(globalContext))
    XCTAssertFalse(attachedGreeting.contains(globalContext))
    XCTAssertTrue(taskGreeting.contains(globalContext))
    XCTAssertTrue(freshTask.contains(globalContext))
    XCTAssertFalse(privateTask.contains(globalContext))
  }

  private func promptRequest(
    goal: String = "Research GalaxySSI and summarize",
    visibleTexts: [String] = ["Welcome to GalaxySSI"],
    parsingContext: AgentModelPlanParsingContext? = nil,
    conversationContext: AgentConversationContext? = nil,
    executionHistory: [AgentAction] = [],
    nativeTools: [AgentNativeToolDescriptor] = [],
    requirements: AgentTaskRequirements = AgentTaskRequirements(mode: .balanced),
    hasAttachments: Bool? = nil,
    allowsPhoneRuntimeTools: Bool? = nil,
    allowsDirectResponse: Bool = false
  ) -> AgentModelPlanningPromptRequest {
    AgentModelPlanningPromptRequest(
      planRequest: AgentPlanRequest(
        goal: goal,
        screen: AgentScreenContext(
          foregroundApp: "GalaxySSI",
          pageTitle: "Agent",
          visibleTexts: visibleTexts,
          isAccessibilityEnabled: true
        ),
        targets: [
          target(),
          target(id: "desktop:offline", title: "Offline", status: .disconnected)
        ],
        nativeTools: nativeTools,
        contextDigest: "prompt-test"
      ),
      parsingContext: parsingContext ?? context(),
      conversationContext: conversationContext ?? AgentConversationContext(
        conversationId: "conversation-1",
        summary: "The user is comparing mobile parity.",
        turns: [
          AgentTranscriptEntry(id: "turn-1", role: .user, text: "Please continue", timestampMillis: 1_000)
        ],
        privateMode: false
      ),
      executionHistory: executionHistory,
      requirements: requirements,
      hasAttachments: hasAttachments,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
      allowsDirectResponse: allowsDirectResponse
    )
  }

  private func context(
    replanReason: String = "",
    installedApps: [AgentModelPlanInstalledApp] = [
      AgentModelPlanInstalledApp(packageName: "com.apple.mobilesafari", label: "Safari")
    ]
  ) -> AgentModelPlanParsingContext {
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
          label: "Search",
          viewId: "search",
          className: "TextField",
          bounds: "0,100,300,144",
          origin: .fused,
          confidence: 0.9,
          visualRole: .input
        )
      ],
      installedApps: installedApps
    )
  }

  private func target(
    id: String = "desktop:codex",
    title: String = "Codex",
    status: AgentConnectorStatus = .available
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: .agent,
      status: status,
      capabilities: [.chat, .reasoning],
      failureDomain: "desktop",
      desktopAccessProfile: GalaxySSILinkProtocol.accessDesktopExecutor
    )
  }

  private func nativeToolDescriptor(
    id: String,
    title: String,
    risk: AgentNativeToolRisk = .low,
    availability: AgentNativeToolAvailability = .available
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: title,
      description: "Prompt test tool",
      location: .phone,
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["query": .object(["type": .string("string")])])
      ],
      risk: risk,
      availability: availability
    )
  }
}

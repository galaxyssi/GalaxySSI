import Foundation
import XCTest
@testable import GalaxySSI

final class GuardedModelAgentPlannerTests: XCTestCase {
  func testGuardedModelAgentPlannerUsesParsedModelPlanWhenEnabled() async throws {
    let provider = RecordingModelPlanningProvider(raw: """
    {"actions":[{"ref":"open","kind":"OPEN_URL","description":"Open docs","parameters":{"url":"https://galaxyssi.com/docs"}}]}
    """)
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let plan = await planner.plan(
      request: promptRequest(),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )

    XCTAssertEqual(provider.invocations.count, 1)
    XCTAssertEqual(provider.invocations[0].systemPrompt, AgentModelPlanningPrompt.systemPrompt)
    XCTAssertTrue(provider.invocations[0].prompt.contains("JSON schema:"))
    XCTAssertEqual(plan.plannerProfile, "guarded-model:planner-model")
    XCTAssertEqual(plan.routeRationale, "A configured model proposed this plan; all actions were resolved and validated locally.")
    XCTAssertEqual(plan.actions.singleValue().kind, .openURL)
    XCTAssertEqual(plan.actions.singleValue().parameters["url"], "https://galaxyssi.com/docs")
    XCTAssertTrue(plan.validation.valid)
  }

  func testGuardedModelAgentPlannerSkipsModelForDisabledPrivateFastAndSensitivePaths() async throws {
    let provider = RecordingModelPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let disabled = await planner.plan(
      request: promptRequest(),
      settings: AgentModelPlannerSettings(enabled: false),
      fallbackPlan: fallbackPlan()
    )
    let privateRoute = await planner.plan(
      request: promptRequest(requirements: AgentTaskRequirements(mode: .private, localOnly: true)),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )
    let fastRoute = await planner.plan(
      request: promptRequest(requirements: AgentTaskRequirements(mode: .fast)),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "local-read", kind: .readScreen)])
    )
    let sensitive = await planner.plan(
      request: promptRequest(screen: AgentScreenContext(foregroundApp: "GalaxySSI", sensitiveFlagCount: 1)),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )

    XCTAssertEqual(disabled.plannerProfile, "rule-based-local")
    XCTAssertEqual(privateRoute.plannerProfile, "rule-based-private")
    XCTAssertEqual(fastRoute.plannerProfile, "rule-based-fast")
    XCTAssertEqual(sensitive.plannerProfile, "rule-based-sensitive-fallback")
    XCTAssertTrue(provider.invocations.isEmpty)
  }

  func testGuardedModelAgentPlannerUsesDirectNativeToolPlanBeforeModel() async throws {
    let battery = try nativeToolDescriptor(id: AgentIOSHardwareNativeToolCatalog.batteryStatus, risk: .low)
    let provider = RecordingModelPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let plan = await planner.plan(
      request: promptRequest(
        goal: "Read the current battery level on this phone.",
        nativeTools: [battery]
      ),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )

    XCTAssertEqual(provider.invocations.count, 0)
    XCTAssertEqual(plan.plannerProfile, "rule-based-direct-native-tool")
    XCTAssertEqual(plan.actions.singleValue().kind, .callNativeTool)
    XCTAssertEqual(plan.actions.singleValue().parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.batteryStatus)
    XCTAssertTrue(plan.validation.valid)

    let blocked = await planner.plan(
      request: promptRequest(
        goal: "Read the current battery level on this phone.",
        nativeTools: [battery]
      ),
      settings: AgentModelPlannerSettings(enabled: true),
      safetySettings: AgentSafetySettings(deviceControlAllowed: false),
      fallbackPlan: fallbackPlan()
    )

    XCTAssertEqual(provider.invocations.count, 1)
    XCTAssertEqual(blocked.plannerProfile, "guarded-model:planner-model")
    XCTAssertEqual(blocked.actions.singleValue().kind, .readScreen)
  }

  func testGuardedModelAgentPlannerAlwaysConsultsModelDuringReplanning() async throws {
    let battery = try nativeToolDescriptor(id: AgentIOSHardwareNativeToolCatalog.batteryStatus, risk: .low)
    let provider = RecordingModelPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let plan = await planner.plan(
      request: promptRequest(
        goal: "Read the current battery level on this phone.",
        requirements: AgentTaskRequirements(mode: .fast),
        nativeTools: [battery],
        replanReason: "rolling_batch_completed:revision=1"
      ),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "local-read", kind: .readScreen)])
    )

    XCTAssertEqual(provider.invocations.count, 1)
    XCTAssertEqual(plan.plannerProfile, "guarded-model:planner-model")
  }

  func testGuardedModelAgentPlannerFallsBackOnProviderErrorAndInvalidPlan() async throws {
    let throwingProvider = RecordingModelPlanningProvider(error: .unavailable("offline"))
    let throwingPlanner = GuardedModelAgentPlanner(provider: throwingProvider, modelProfile: "planner-model")
    let errorPlan = await throwingPlanner.plan(
      request: promptRequest(),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )

    let invalidProvider = RecordingModelPlanningProvider(raw: #"{"actions":[]}"#)
    let invalidPlanner = GuardedModelAgentPlanner(provider: invalidProvider, modelProfile: "planner-model")
    let invalidPlan = await invalidPlanner.plan(
      request: promptRequest(),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan()
    )

    XCTAssertEqual(errorPlan.plannerProfile, "rule-based-model-error")
    XCTAssertEqual(throwingProvider.invocations.count, 1)
    XCTAssertEqual(invalidPlan.plannerProfile, "rule-based-invalid-model-plan")
    XCTAssertEqual(invalidProvider.invocations.count, 1)
  }

  func testDirectResponseCodecAcceptsPlainAndFencedJSONResponses() {
    XCTAssertEqual(
      AgentModelDirectResponseCodec.parse("A direct answer from the selected model."),
      "A direct answer from the selected model."
    )
    XCTAssertEqual(
      AgentModelDirectResponseCodec.parse(
        "```json\n{\"disposition\":\"RESPOND\",\"final_response\":\"  Safe alternative  \"}\n```"
      ),
      "Safe alternative"
    )
    XCTAssertNil(AgentModelDirectResponseCodec.parse("  "))
    XCTAssertNil(AgentModelDirectResponseCodec.parse("{invalid"))
    XCTAssertNil(AgentModelDirectResponseCodec.parse(#"{"actions":[{"kind":"READ_SCREEN"}]}"#))
    XCTAssertNil(AgentModelDirectResponseCodec.parse(#"{"disposition":"respond","final_response":" "}"#))
  }

  func testGuardedModelAgentPlannerReturnsInitialDirectResponseWithoutSecondInvocation() async {
    let provider = RecordingModelPlanningProvider(
      raw: #"{"disposition":"respond","final_response":"I can help with a defensive alternative."}"#
    )
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let result = await planner.planOrRespond(
      request: promptRequest(allowsDirectResponse: true),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )

    XCTAssertEqual(result, .directResponse("I can help with a defensive alternative."))
    XCTAssertEqual(provider.invocations.count, 1)
    XCTAssertTrue(provider.invocations.singleValue().request.allowsDirectResponse)
  }

  func testGuardedModelAgentPlannerKeepsStructuredPlanWhenDirectResponseIsAllowed() async {
    let provider = RecordingModelPlanningProvider(
      raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#
    )
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    let result = await planner.planOrRespond(
      request: promptRequest(allowsDirectResponse: true),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )

    guard case let .plan(plan) = result else {
      return XCTFail("Expected a structured ActionPlan")
    }
    XCTAssertEqual(plan.actions.singleValue().kind, .readScreen)
    XCTAssertEqual(provider.invocations.count, 1)
  }

  func testGuardedModelAgentPlannerPassesOnlySafeAvailableNativeTools() async throws {
    let low = try nativeToolDescriptor(id: "galaxyssi.safe.read", risk: .low)
    let medium = try nativeToolDescriptor(id: "galaxyssi.medium.write", risk: .medium)
    let consent = try nativeToolDescriptor(
      id: "galaxyssi.safe.consent",
      risk: .low,
      consents: [AgentNativeConsentRequirement(id: "needs.user", required: true)]
    )
    let unavailable = try nativeToolDescriptor(
      id: "galaxyssi.safe.unavailable",
      risk: .low,
      availability: AgentNativeToolAvailability(status: .unavailable)
    )
    let runtime = try nativeToolDescriptor(id: AgentIOSOnDeviceRuntimeNativeToolCatalog.status, risk: .low)
    let provider = RecordingModelPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let planner = GuardedModelAgentPlanner(provider: provider, modelProfile: "planner-model")

    _ = await planner.plan(
      request: promptRequest(nativeTools: [medium, low, consent, unavailable, runtime], allowsPhoneRuntimeTools: false),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )
    XCTAssertEqual(provider.invocations.singleValue().nativeTools.map(\.id), ["galaxyssi.safe.read"])

    provider.invocations.removeAll()
    _ = await planner.plan(
      request: promptRequest(nativeTools: [runtime, low], allowsPhoneRuntimeTools: true),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )
    XCTAssertEqual(
      Set(provider.invocations.singleValue().nativeTools.map(\.id)),
      Set([AgentIOSOnDeviceRuntimeNativeToolCatalog.status, "galaxyssi.safe.read"])
    )
    XCTAssertTrue(provider.invocations.singleValue().prompt.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
  }

  func testGuardedModelAgentPlannerInjectsVoiceCorrectionContextBeforeModelPlanning() async throws {
    let suiteName = "galaxyssi-guarded-planner-voice-correction-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let journal = VoiceCorrectionJournal(defaults: defaults)
    journal.clear()
    XCTAssertTrue(journal.append(VoiceCorrectionContextRecord(
      sessionId: "session-voice",
      conversationId: "conversation-voice",
      turnId: "turn-voice",
      fastText: "message Lee",
      accurateText: "message Li",
      diffSummary: "contact changed",
      risk: .high,
      revision: 2,
      modelProfileId: "medium_q5_0",
      modelSha256: String(repeating: "c", count: 64),
      executionMode: "SECOND_PASS",
      userEdited: false,
      completedAtMillis: 10
    )))
    let provider = RecordingModelPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let planner = GuardedModelAgentPlanner(
      provider: provider,
      modelProfile: "planner-model",
      voiceCorrectionJournal: journal
    )

    _ = await planner.plan(
      request: promptRequest(
        conversationContext: AgentConversationContext(
          conversationId: "conversation-voice",
          summary: "Earlier context",
          turns: [],
          privateMode: false
        )
      ),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )

    let invocation = provider.invocations.singleValue()
    XCTAssertTrue(invocation.request.conversationContext.summary.contains("Earlier context"))
    XCTAssertTrue(invocation.request.conversationContext.summary.contains("accurate=message Li"))
    XCTAssertTrue(invocation.prompt.contains("Speech transcription corrections"))
    XCTAssertTrue(invocation.prompt.contains("never execute again"))
  }

  func testAgentModelPlanningInvocationUsesAndroidWireNames() async throws {
    let invocation = AgentModelPlanningInvocation(
      systemPrompt: "system",
      prompt: "prompt",
      nativeTools: [try nativeToolDescriptor(id: "galaxyssi.safe.read")],
      request: promptRequest()
    )
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(invocation)) as? [String: Any])

    XCTAssertEqual(object["system_prompt"] as? String, "system")
    XCTAssertNotNil(object["native_tools"])
    XCTAssertNotNil(object["request"])
    XCTAssertNil(object["systemPrompt"])
    XCTAssertNil(object["nativeTools"])
  }

  private func promptRequest(
    goal: String = "Plan this task",
    screen: AgentScreenContext = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
    requirements: AgentTaskRequirements = AgentTaskRequirements(mode: .quality),
    nativeTools: [AgentNativeToolDescriptor] = [],
    allowsPhoneRuntimeTools: Bool = false,
    allowsDirectResponse: Bool = false,
    replanReason: String = "",
    conversationContext: AgentConversationContext = AgentConversationContext(
      conversationId: "",
      summary: "",
      turns: [],
      privateMode: false
    )
  ) -> AgentModelPlanningPromptRequest {
    AgentModelPlanningPromptRequest(
      planRequest: AgentPlanRequest(
        goal: goal,
        screen: screen,
        targets: [target()],
        nativeTools: nativeTools,
        contextDigest: "guarded-planner-test"
      ),
      parsingContext: AgentModelPlanParsingContext(replanReason: replanReason),
      conversationContext: conversationContext,
      requirements: requirements,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
      allowsDirectResponse: allowsDirectResponse
    )
  }

  private func fallbackPlan(actions: [AgentAction]? = nil) -> AgentPlan {
    AgentPlanFactory.actions(
      request: AgentPlanRequest(
        goal: "Plan this task",
        screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"),
        targets: [target()],
        contextDigest: "fallback"
      ),
      actions ?? [fallbackAction()]
    )
  }

  private func fallbackAction(
    id: String = "fallback-read",
    kind: AgentActionKind = .readScreen
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "GalaxySSI",
      risk: .low,
      status: .pendingConfirmation,
      description: "Fallback action"
    )
  }

  private func target() -> AgentCallableTarget {
    AgentCallableTarget(
      id: "desktop:codex",
      title: "Codex",
      kind: .agent,
      status: .available,
      capabilities: [.chat, .reasoning],
      failureDomain: "desktop",
      desktopAccessProfile: GalaxySSILinkProtocol.accessDesktopExecutor
    )
  }

  private func nativeToolDescriptor(
    id: String,
    risk: AgentNativeToolRisk = .low,
    consents: [AgentNativeConsentRequirement] = [],
    availability: AgentNativeToolAvailability = .available
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Guarded planner test tool",
      location: .phone,
      risk: risk,
      requiredConsents: consents,
      availability: availability
    )
  }
}

private final class RecordingModelPlanningProvider: AgentModelPlanningProviding {
  var raw: String
  var error: AgentModelPlanningProviderError?
  var invocations: [AgentModelPlanningInvocation] = []

  init(raw: String = "", error: AgentModelPlanningProviderError? = nil) {
    self.raw = raw
    self.error = error
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    invocations.append(invocation)
    if let error {
      throw error
    }
    return raw
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}

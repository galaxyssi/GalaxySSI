import Foundation
import XCTest
@testable import SignalASI

final class GuardedModelAgentPlannerTests: XCTestCase {
  func testGuardedModelAgentPlannerUsesParsedModelPlanWhenEnabled() async throws {
    let provider = RecordingModelPlanningProvider(raw: """
    {"actions":[{"ref":"open","kind":"OPEN_URL","description":"Open docs","parameters":{"url":"https://signalasi.com/docs"}}]}
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
    XCTAssertEqual(plan.actions.singleValue().parameters["url"], "https://signalasi.com/docs")
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
      request: promptRequest(screen: AgentScreenContext(foregroundApp: "SignalASI", sensitiveFlagCount: 1)),
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

  func testGuardedModelAgentPlannerPassesOnlySafeAvailableNativeTools() async throws {
    let low = try nativeToolDescriptor(id: "signalasi.safe.read", risk: .low)
    let medium = try nativeToolDescriptor(id: "signalasi.medium.write", risk: .medium)
    let consent = try nativeToolDescriptor(
      id: "signalasi.safe.consent",
      risk: .low,
      consents: [AgentNativeConsentRequirement(id: "needs.user", required: true)]
    )
    let unavailable = try nativeToolDescriptor(
      id: "signalasi.safe.unavailable",
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
    XCTAssertEqual(provider.invocations.singleValue().nativeTools.map(\.id), ["signalasi.safe.read"])

    provider.invocations.removeAll()
    _ = await planner.plan(
      request: promptRequest(nativeTools: [runtime, low], allowsPhoneRuntimeTools: true),
      settings: AgentModelPlannerSettings(enabled: true),
      fallbackPlan: fallbackPlan(actions: [fallbackAction(id: "draft", kind: .draftPlan)])
    )
    XCTAssertEqual(
      Set(provider.invocations.singleValue().nativeTools.map(\.id)),
      Set([AgentIOSOnDeviceRuntimeNativeToolCatalog.status, "signalasi.safe.read"])
    )
    XCTAssertTrue(provider.invocations.singleValue().prompt.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
  }

  func testAgentModelPlanningInvocationUsesAndroidWireNames() async throws {
    let invocation = AgentModelPlanningInvocation(
      systemPrompt: "system",
      prompt: "prompt",
      nativeTools: [try nativeToolDescriptor(id: "signalasi.safe.read")],
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
    screen: AgentScreenContext = AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
    requirements: AgentTaskRequirements = AgentTaskRequirements(mode: .quality),
    nativeTools: [AgentNativeToolDescriptor] = [],
    allowsPhoneRuntimeTools: Bool = false
  ) -> AgentModelPlanningPromptRequest {
    AgentModelPlanningPromptRequest(
      planRequest: AgentPlanRequest(
        goal: goal,
        screen: screen,
        targets: [target()],
        nativeTools: nativeTools,
        contextDigest: "guarded-planner-test"
      ),
      parsingContext: AgentModelPlanParsingContext(),
      requirements: requirements,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools
    )
  }

  private func fallbackPlan(actions: [AgentAction]? = nil) -> AgentPlan {
    AgentPlanFactory.actions(
      request: AgentPlanRequest(
        goal: "Plan this task",
        screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
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
      target: "SignalASI",
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
      desktopAccessProfile: SignalASILinkProtocol.accessDesktopExecutor
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

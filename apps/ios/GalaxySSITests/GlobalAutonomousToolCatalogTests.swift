import XCTest
@testable import GalaxySSI

final class GlobalAutonomousToolCatalogTests: XCTestCase {
  func testCatalogSelectsRelevantAvailableToolsAndExcludesBlockedOrUnavailable() throws {
    let battery = try descriptor(
      "galaxyssi.hardware.battery.status",
      title: "Battery Status",
      description: "Read current battery power and charge state.",
      capabilities: ["battery", "power"]
    )
    let timer = try descriptor(
      "galaxyssi.clock.timer.create",
      title: "Timer",
      description: "Create countdown timers and alarms.",
      capabilities: ["alarm", "timer"]
    )
    let unavailable = try descriptor(
      "galaxyssi.web.search",
      title: "Search",
      description: "Search public web pages.",
      capabilities: ["web", "search"],
      availability: AgentNativeToolAvailability(status: .unavailable, reason: "Network disabled")
    )
    let blocked = try descriptor(
      "galaxyssi.private.delete",
      title: "Delete Private Data",
      description: "Delete local private data.",
      risk: .blocked,
      capabilities: ["delete"]
    )

    let selected = GlobalAutonomousToolCatalogPolicy.select(
      descriptors: [unavailable, blocked, timer, battery],
      goal: "\u{5e2e}\u{6211}\u{770b}\u{4e00}\u{4e0b}\u{7535}\u{91cf}",
      maximumTools: 8
    )

    XCTAssertEqual(selected.first?.id, battery.id)
    XCTAssertFalse(selected.contains { $0.id == unavailable.id })
    XCTAssertFalse(selected.contains { $0.id == blocked.id })
  }

  func testPromptBlockNamesHostValidationAndExactSchemas() throws {
    let search = try descriptor(
      "galaxyssi.web.search",
      title: "Search",
      description: "Search public web pages with bounded result counts.",
      inputSchema: Self.querySchema,
      capabilities: ["web", "search"]
    )

    let prompt = GlobalAutonomousToolCatalogPolicy.promptBlock(descriptors: [search])

    XCTAssertTrue(prompt.contains("The iOS host independently validates risk, permissions, consent, idempotency, and input before execution."))
    XCTAssertTrue(prompt.contains("id=galaxyssi.web.search"))
    XCTAssertTrue(prompt.contains(#""query""#))
    XCTAssertTrue(prompt.contains(#""additionalProperties":false"#))
    XCTAssertLessThanOrEqual(prompt.count, 9_000)
  }

  func testInspectRejectsBadActionsAndWaitsForConfirmationWhenRiskRequiresIt() throws {
    let descriptor = try descriptor(
      "galaxyssi.messages.send",
      title: "Send Message",
      description: "Send a user-visible message through a configured account.",
      inputSchema: Self.messageSchema,
      risk: .medium,
      capabilities: ["sms", "message"],
      requiredConsents: [AgentNativeConsentRequirement(id: "send.message", required: true)]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let host = GlobalAutonomousToolHost(registry: registry)

    let nonTool = host.inspect(action: GlobalAutonomousAction(kind: .analyze, goal: "Inspect"))
    XCTAssertEqual(nonTool.status, .rejected)

    let malformed = host.inspect(action: action(toolId: descriptor.id, inputJson: "[]"))
    XCTAssertEqual(malformed.status, .rejected)

    let invalid = host.inspect(action: action(toolId: descriptor.id, inputJson: #"{"body":""}"#))
    XCTAssertEqual(invalid.status, .rejected)

    let waiting = host.inspect(action: action(toolId: descriptor.id, inputJson: #"{"recipient":"Ada","body":"hi"}"#))
    XCTAssertEqual(waiting.status, .waitingConfirmation)
    XCTAssertEqual(waiting.descriptor?.id, descriptor.id)

    let ready = host.inspect(
      action: action(toolId: descriptor.id, inputJson: #"{"recipient":"Ada","body":"hi"}"#),
      confirmationGranted: true
    )
    XCTAssertEqual(ready.status, .ready)
    XCTAssertEqual(ready.input["recipient"], .string("Ada"))
  }

  func testExecuteProducesNativeToolReceiptEvidence() throws {
    var observedContext: AgentNativeToolInvocationContext?
    let descriptor = try descriptor(
      "galaxyssi.test.echo",
      title: "Echo",
      description: "Echo a bounded value.",
      inputSchema: Self.querySchema,
      capabilities: ["echo"]
    )
    let registry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      executor: { invocation in
        observedContext = invocation.context
        return .success(output: ["query": invocation.input["query"] ?? .null], message: "done")
      },
      verifier: { _, _ in
        AgentNativeToolVerification(status: .passed, message: "ok")
      }
    ))
    let host = GlobalAutonomousToolHost(registry: registry)
    let toolAction = action(
      toolId: descriptor.id,
      inputJson: #"{"query":"hello"}"#,
      confirmationGranted: true
    )
    let decision = host.inspect(action: toolAction)
    let execution = host.execute(
      run: run(action: toolAction),
      action: toolAction,
      decision: decision,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 1_000 })
    )

    XCTAssertTrue(execution.result.isSuccess)
    XCTAssertEqual(execution.result.output["query"], .string("hello"))
    XCTAssertEqual(execution.evidence.kind, .nativeToolReceipt)
    XCTAssertTrue(execution.evidence.verified)
    XCTAssertTrue(execution.evidence.sourceRef.contains(execution.result.receipt.invocationId))
    XCTAssertEqual(observedContext?.callerId, "galaxyssi.global_super_agent")
    XCTAssertEqual(observedContext?.attributes["execution_authority"], "galaxyssi-ios")
  }

  func testActionVerificationDefaultsAndBackCompatDecode() throws {
    let raw = #"{"id":"action-old","kind":"INVOKE_TOOL","goal":"Run a native tool"}"#
    let action = try JSONDecoder().decode(GlobalAutonomousAction.self, from: Data(raw.utf8))

    XCTAssertEqual(action.verificationStatus, .pending)
    XCTAssertEqual(action.verificationContract.acceptedEvidenceKinds, [.nativeToolReceipt])

    let supported = GlobalActionVerificationPolicy.evaluate(
      contract: action.verificationContract,
      evidence: [
        GlobalActionEvidence(
          kind: .nativeToolReceipt,
          summary: "Native receipt",
          confidence: 0.82,
          verified: false
        )
      ]
    )
    let verified = GlobalActionVerificationPolicy.evaluate(
      contract: action.verificationContract,
      evidence: [
        GlobalActionEvidence(
          kind: .nativeToolReceipt,
          summary: "Verified native receipt",
          confidence: 1.0,
          verified: true
        )
      ]
    )

    XCTAssertEqual(supported, .supported)
    XCTAssertEqual(verified, .verified)
  }

  private static var querySchema: AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object([
        "query": .object([
          "type": .string("string"),
          "minLength": .int(1)
        ])
      ]),
      "required": .array([.string("query")]),
      "additionalProperties": .bool(false)
    ]
  }

  private static var messageSchema: AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object([
        "recipient": .object(["type": .string("string"), "minLength": .int(1)]),
        "body": .object(["type": .string("string"), "minLength": .int(1)])
      ]),
      "required": .array([.string("recipient"), .string("body")]),
      "additionalProperties": .bool(false)
    ]
  }

  private func descriptor(
    _ id: String,
    title: String,
    description: String,
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    risk: AgentNativeToolRisk = .low,
    capabilities: Set<String> = [],
    requiredConsents: [AgentNativeConsentRequirement] = [],
    availability: AgentNativeToolAvailability = .available
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      risk: risk,
      capabilities: capabilities,
      requiredConsents: requiredConsents,
      availability: availability
    )
  }

  private func action(
    toolId: String,
    inputJson: String,
    confirmationGranted: Bool = false
  ) -> GlobalAutonomousAction {
    GlobalAutonomousAction(
      id: "action-1",
      kind: .invokeTool,
      goal: "Run native tool",
      rationale: "Needed for the task",
      expectedResult: "Native result",
      toolId: toolId,
      toolInputJson: inputJson,
      externalEffect: confirmationGranted,
      confirmationGranted: confirmationGranted
    )
  }

  private func run(action: GlobalAutonomousAction) -> GlobalAutonomousRun {
    GlobalAutonomousRun(
      id: "run-1",
      sourceCognitionTaskId: "cognition-1",
      sourceEventId: "event-1",
      sourceConversationId: "conversation-1",
      topic: "Tests",
      goal: "Run native tool",
      actions: [action]
    )
  }
}

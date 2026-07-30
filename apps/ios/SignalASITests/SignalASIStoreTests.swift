import XCTest
@testable import SignalASI

private final class TestAgentActionExecutor: AgentActionExecutor {
  var callCount = 0
  private let handler: (AgentAction, AgentScreenContext) -> AgentActionResult

  init(_ handler: @escaping (AgentAction, AgentScreenContext) -> AgentActionResult) {
    self.handler = handler
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    callCount += 1
    return handler(action, screen)
  }
}

private final class FakeMcpLocalRuntimeExecutor: AgentMcpLocalRuntimeExecuting {
  var requests: [AgentMcpLocalRuntimeExecutionRequest] = []
  private var responses: [AgentMcpLocalRuntimeExecutionResponse]

  init(_ responses: [AgentMcpLocalRuntimeExecutionResponse]) {
    self.responses = responses
  }

  func execute(_ request: AgentMcpLocalRuntimeExecutionRequest) throws -> AgentMcpLocalRuntimeExecutionResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP runtime response is queued")
    }
    return responses.removeFirst()
  }
}

private final class FakeMcpDeclarativeHTTPTransport: AgentMcpDeclarativeHTTPTransport {
  var requests: [AgentMcpDeclarativeHTTPRequest] = []
  private var responses: [AgentMcpDeclarativeHTTPResponse]

  init(_ responses: [AgentMcpDeclarativeHTTPResponse]) {
    self.responses = responses
  }

  func execute(_ request: AgentMcpDeclarativeHTTPRequest) async throws -> AgentMcpDeclarativeHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP HTTP response is queued")
    }
    return responses.removeFirst()
  }
}

private final class FakeMcpStreamableHTTPNetworking: AgentMcpStreamableHTTPNetworking {
  var requests: [AgentMcpStreamableHTTPRequest] = []
  private var responses: [AgentMcpStreamableHTTPResponse]

  init(_ responses: [AgentMcpStreamableHTTPResponse]) {
    self.responses = responses
  }

  func post(_ request: AgentMcpStreamableHTTPRequest) async throws -> AgentMcpStreamableHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("No fake MCP streamable HTTP response is queued")
    }
    return responses.removeFirst()
  }
}

private final class TestMcpRemoteSessionListener: AgentMcpRemoteSessionListener {
  var notifications: [AgentMcpNotification] = []
  var issues: [AgentMcpRemoteSessionError] = []

  func onNotification(_ notification: AgentMcpNotification) {
    notifications.append(notification)
  }

  func onProtocolIssue(_ error: AgentMcpRemoteSessionError) {
    issues.append(error)
  }
}

private extension AgentRuntimePackCatalogEntry {
  func with(
    version: String? = nil,
    downloadUrl: String? = nil,
    minimumHostVersionCode: Int64? = nil,
    guestApiVersion: Int? = nil
  ) -> AgentRuntimePackCatalogEntry {
    var copy = self
    if let version {
      copy.version = version
    }
    if let downloadUrl {
      copy.downloadUrl = downloadUrl
    }
    if let minimumHostVersionCode {
      copy.minimumHostVersionCode = minimumHostVersionCode
    }
    if let guestApiVersion {
      copy.guestApiVersion = guestApiVersion
    }
    return copy
  }
}

@MainActor
final class SignalASIStoreTests: XCTestCase {
  func testInitialStoreContainsAndroidParityContacts() {
    let store = makeStore()

    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "system")?.trustState, .verified)
    XCTAssertTrue(store.profile.identityFingerprint.count == 64)
  }

  func testContactSearchMatchesAndroidNameAndIdFiltering() throws {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "gpt-5",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(store.visibleContacts(matching: "alice").map(\.id), ["friend-alice"])
    XCTAssertEqual(store.visibleContacts(matching: "cloud:openai").map(\.id), ["cloud:openai"])
    XCTAssertEqual(store.contactList(matching: "gpt-5").map(\.id), ["cloud:openai"])
    XCTAssertTrue(store.visibleContacts(matching: "missing-contact").isEmpty)
  }

  func testCloudModelContactsAreGroupedByProvider() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    let contact = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertEqual(contact.id, "cloud:openai")
    XCTAssertEqual(contact.cloudModels.count, 2)
    XCTAssertEqual(store.contacts.filter { $0.id == "cloud:openai" }.count, 1)
    XCTAssertEqual(store.apiKey(for: contact.cloudModels[1]), "key-b")
  }

  func testRenamesContactLocally() {
    let store = makeStore()
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-alice", name: "Alice"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))

    XCTAssertTrue(store.renameContact(id: "friend-alice", displayName: "  Alice Remark  "))

    let contact = store.contact(id: "friend-alice")
    XCTAssertEqual(contact?.name, "Alice Remark")
    XCTAssertEqual(contact?.displayName, "Alice Remark")
  }

  func testDeleteContactSoftDeletesAndOptionallyRemovesMessages() {
    let store = makeStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let request = store.addFriendRequest(makeFriendRequest(signalASIId: "friend-bob", name: "Bob"))
    XCTAssertTrue(store.approveFriendRequest(id: request.id))
    store.appendOutgoing("hello", to: "friend-bob")

    XCTAssertTrue(store.deleteContact(id: "friend-bob", deleteMessages: true, now: now))

    let contact = store.contact(id: "friend-bob")
    XCTAssertEqual(contact?.deleted, true)
    XCTAssertEqual(contact?.trustState, .deleted)
    XCTAssertEqual(contact?.deletedAt, now)
    XCTAssertTrue(store.messages(for: "friend-bob").isEmpty)
    XCTAssertEqual(store.friendRequest(id: request.id)?.status, .deleted)
    XCTAssertEqual(store.friendRequest(id: request.id)?.readdRequired, true)
  }

  func testDeleteMessageRemovesOnlyTargetMessage() {
    let store = makeStore()
    let first = store.appendOutgoing("first", to: "hermes")
    let second = store.appendOutgoing("second", to: "hermes")

    XCTAssertTrue(store.deleteMessage(first.id, contactId: "hermes"))

    XCTAssertEqual(store.messages(for: "hermes").map(\.content), [
      "Pair SignalASI Desktop to start a trusted Link conversation.",
      "second"
    ])
    XCTAssertFalse(store.deleteMessage(first.id, contactId: "hermes"))
    XCTAssertEqual(store.messages(for: "hermes").last?.id, second.id)
  }

  func testDeleteChatHistoryKeepsContact() {
    let store = makeStore()
    store.appendOutgoing("hello", to: "hermes")

    store.deleteMessages(for: "hermes")

    XCTAssertTrue(store.messages(for: "hermes").isEmpty)
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertEqual(store.contact(id: "hermes")?.deleted, false)
  }

  func testConversationSummaryTracksUnreadMessagesAndReadState() {
    let store = makeStore()

    XCTAssertEqual(store.conversationSummary(for: "hermes").unreadCount, 0)

    store.appendIncoming("desktop reply", from: "hermes")
    store.appendSystem("local notice", to: "hermes")
    store.appendOutgoing("ack", to: "hermes")

    let summary = store.conversationSummary(for: "hermes")
    XCTAssertEqual(summary.lastMessage?.content, "ack")
    XCTAssertEqual(summary.unreadCount, 1)
    XCTAssertTrue(summary.hasUnreadMessages)

    XCTAssertEqual(store.markContactRead("hermes"), 1)
    XCTAssertEqual(store.conversationSummary(for: "hermes").unreadCount, 0)
    XCTAssertEqual(store.markContactRead("hermes"), 0)
  }

  func testLanguagePolicyNormalizesAndUpdatesVoiceLocale() {
    let store = makeStore()

    store.updateLanguagePolicy {
      $0.interfaceLanguage = "zh-CN"
      $0.responseLanguage = "en-US"
      $0.asrLanguage = "zh-HK"
      $0.ttsLanguage = "not-supported"
    }

    XCTAssertEqual(store.languagePolicy.interfaceLanguage, "zh-CN")
    XCTAssertEqual(store.languagePolicy.responseLanguage, "en-US")
    XCTAssertEqual(store.languagePolicy.asrLanguage, "zh-HK")
    XCTAssertEqual(store.languagePolicy.ttsLanguage, "auto")
    XCTAssertEqual(store.voiceSettings.preferredLocaleIdentifier, "zh_HK")
  }

  func testCloudSystemPromptUsesConfiguredResponseLanguage() {
    let prompt = CloudModelClient.systemPrompt(languagePolicy: LanguagePolicySettings(responseLanguage: "zh-CN"))

    XCTAssertTrue(prompt.contains("Reply in Simplified Chinese"))
  }

  func testCloudContextOverflowPolicyMatchesAndroidContextErrorDetection() {
    XCTAssertTrue(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 400, responseBody: #"{"code":"context_length_exceeded"}"#)
      )
    )
    XCTAssertTrue(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 413, responseBody: "Request too large")
      )
    )
    XCTAssertFalse(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 401, responseBody: "Too many tokens in the supplied credential")
      )
    )
    XCTAssertFalse(
      CloudContextOverflowPolicy.isContextOverflow(
        CloudHTTPFailure(statusCode: 400, responseBody: "Unknown model")
      )
    )
  }

  func testCloudContextOverflowPolicyRetryWindowsShrinkByTokenCapacity() {
    XCTAssertEqual(
      CloudContextOverflowPolicy.retryWindows(configuredWindowTokens: 64_000),
      [64_000, 32_000, 16_000, 8_000]
    )
    XCTAssertEqual(
      CloudContextOverflowPolicy.retryWindows(configuredWindowTokens: 8_192),
      [8_192, 4_096]
    )
  }

  func testVoiceSettingsNormalizeAdvancedAndroidParityFields() {
    let store = makeStore()

    store.updateVoiceSettings {
      $0.wakeWords = VoiceSettings.wakeWords(from: " SignalASI, , hello, custom wake ")
      $0.wakeThreshold = 2
      $0.welcomeText = "  "
      $0.targetContactId = ""
      $0.speakReplies = false
      $0.routingMode = .contact
    }

    XCTAssertEqual(store.voiceSettings.wakeWords, ["SignalASI", "hello", "custom wake"])
    XCTAssertEqual(store.voiceSettings.wakeThreshold, 0.99)
    XCTAssertEqual(store.voiceSettings.welcomeText, VoiceSettings.defaultWelcomeText)
    XCTAssertEqual(store.voiceSettings.targetContactId, "hermes")
    XCTAssertFalse(store.voiceSettings.speakReplies)
    XCTAssertEqual(store.voiceSettings.routingMode, .contact)
  }

  func testDisplaySettingsNormalizeAndroidTextScaleWireValues() throws {
    let extraLarge = try JSONDecoder.signalASI.decode(
      AppDisplaySettings.self,
      from: Data(#"{"text_scale":"EXTRA_LARGE"}"#.utf8)
    )
    let fallback = try JSONDecoder.signalASI.decode(
      AppDisplaySettings.self,
      from: Data(#"{"text_scale":"not-supported"}"#.utf8)
    )
    let store = makeStore()

    XCTAssertEqual(extraLarge.textScale, .extraLarge)
    XCTAssertEqual(fallback.textScale, .comfortable)
    XCTAssertEqual(store.displaySettings.textScale, .comfortable)

    store.updateDisplaySettings {
      $0.textScale = .large
    }

    XCTAssertEqual(store.displaySettings.textScale, .large)
  }

  func testAgentSafetySettingsDecodeAndroidPolicyAndEncodeStoredNames() throws {
    let settings = try JSONDecoder.signalASI.decode(
      AgentSafetySettings.self,
      from: Data(#"{"task_execution_mode":"plan_only","permission_mode":"AUTO_LOW_RISK","high_risk_guard":false,"memory_capture":false,"screen_observation_allowed":false,"local_actions_allowed":false,"connector_calls_allowed":false,"device_control_allowed":false,"execution_paused":true}"#.utf8)
    )
    let fallback = try JSONDecoder.signalASI.decode(
      AgentSafetySettings.self,
      from: Data(#"{"task_execution_mode":"unknown","permission_mode":"unknown"}"#.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(settings.taskExecutionMode, .planOnly)
    XCTAssertEqual(settings.permissionMode, .autoLowRisk)
    XCTAssertFalse(settings.highRiskGuard)
    XCTAssertFalse(settings.memoryCapture)
    XCTAssertFalse(settings.screenObservationAllowed)
    XCTAssertFalse(settings.localActionsAllowed)
    XCTAssertFalse(settings.connectorCallsAllowed)
    XCTAssertFalse(settings.deviceControlAllowed)
    XCTAssertTrue(settings.executionPaused)
    XCTAssertEqual(fallback.taskExecutionMode, .autoComplete)
    XCTAssertEqual(fallback.permissionMode, .askBeforeAction)
    XCTAssertEqual(object["task_execution_mode"] as? String, "PLAN_ONLY")
    XCTAssertEqual(object["permission_mode"] as? String, "AUTO_LOW_RISK")

    let store = makeStore()
    store.updateAgentSafetySettings {
      $0.taskExecutionMode = .planOnly
      $0.permissionMode = .observeOnly
      $0.executionPaused = true
    }

    XCTAssertEqual(store.agentSafetySettings.taskExecutionMode, .planOnly)
    XCTAssertEqual(store.agentSafetySettings.permissionMode, .observeOnly)
    XCTAssertTrue(store.agentSafetySettings.executionPaused)
  }

  func testAgentTaskExecutionModePolicyMatchesAndroidExplicitSignals() {
    let planOnly = AgentTaskExecutionModePolicy.resolve(
      request: "\u{5148}\u{7ed9}\u{65b9}\u{6848}\u{ff0c}\u{4e0d}\u{8981}\u{6267}\u{884c}\u{4efb}\u{4f55}\u{64cd}\u{4f5c}",
      configuredMode: .autoComplete
    )
    let autoComplete = AgentTaskExecutionModePolicy.resolve(
      request: "\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}\u{6267}\u{884c}\u{ff0c}\u{7ee7}\u{7eed}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
      configuredMode: .planOnly
    )

    XCTAssertEqual(planOnly.mode, .planOnly)
    XCTAssertTrue(planOnly.explicitlyRequested)
    XCTAssertEqual(planOnly.matchedSignal, "\u{5148}\u{7ed9}\u{65b9}\u{6848}")
    XCTAssertEqual(autoComplete.mode, .autoComplete)
    XCTAssertTrue(autoComplete.explicitlyRequested)
    XCTAssertEqual(autoComplete.matchedSignal, "\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}\u{6267}\u{884c}")
  }

  func testAgentTaskExecutionModePolicyKeepsDefaultsAndScopedNegatives() {
    let configuredDefault = AgentTaskExecutionModePolicy.resolve(
      request: "\u{68c0}\u{67e5}\u{8fd9}\u{4e2a}\u{9879}\u{76ee}\u{7684}\u{6784}\u{5efa}\u{72b6}\u{6001}",
      configuredMode: .planOnly
    )
    let scopedNegative = AgentTaskExecutionModePolicy.resolve(
      request: "\u{68c0}\u{67e5}\u{9879}\u{76ee}\u{ff0c}\u{4f46}\u{4e0d}\u{8981}\u{6267}\u{884c}\u{5220}\u{9664}\u{64cd}\u{4f5c}",
      configuredMode: .autoComplete
    )

    XCTAssertEqual(configuredDefault.mode, .planOnly)
    XCTAssertFalse(configuredDefault.explicitlyRequested)
    XCTAssertEqual(scopedNegative.mode, .autoComplete)
    XCTAssertFalse(scopedNegative.explicitlyRequested)
    XCTAssertEqual(AgentTaskExecutionMode.fromWireValue("plan_only"), .planOnly)
    XCTAssertEqual(AgentTaskExecutionMode.fromWireValue("AUTO_COMPLETE"), .autoComplete)
  }

  func testAgentTaskBudgetDecodesAndroidProfilesAndNormalizesLimits() throws {
    let decoded = try JSONDecoder.signalASI.decode(
      AgentTaskBudget.self,
      from: Data("""
      {
        "version": 1,
        "profile": "PRIVATE",
        "max_elapsed_seconds": 999999999,
        "max_cost_micros": 9999999999,
        "max_input_tokens": -25,
        "max_output_tokens": 999999999,
        "max_network_bytes": 999999999999,
        "minimum_battery_percent": 250,
        "max_memory_bytes": 999999999999,
        "network_policy": "TRUSTED_ONLY",
        "allow_cloud": false,
        "allow_paid_providers": false
      }
      """.utf8)
    )
    let fallback = try JSONDecoder.signalASI.decode(
      AgentTaskBudget.self,
      from: Data(#"{"profile":"not-supported","network_policy":"not-supported"}"#.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(AgentTaskBudget.forProfile(.fast))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let store = makeStore()

    XCTAssertEqual(decoded.profile, .privateMode)
    XCTAssertEqual(decoded.maxElapsedSeconds, AgentTaskBudget.maximumElapsedSeconds)
    XCTAssertEqual(decoded.maxCostMicros, AgentTaskBudget.maximumCostMicros)
    XCTAssertEqual(decoded.maxInputTokens, 0)
    XCTAssertEqual(decoded.maxOutputTokens, AgentTaskBudget.maximumTokens)
    XCTAssertEqual(decoded.maxNetworkBytes, AgentTaskBudget.maximumNetworkBytes)
    XCTAssertEqual(decoded.minimumBatteryPercent, 100)
    XCTAssertEqual(decoded.maxMemoryBytes, AgentTaskBudget.maximumMemoryBytes)
    XCTAssertEqual(decoded.networkPolicy, .trustedOnly)
    XCTAssertFalse(decoded.allowCloud)
    XCTAssertFalse(decoded.allowPaidProviders)
    XCTAssertEqual(fallback.profile, .adaptive)
    XCTAssertEqual(fallback.networkPolicy, .any)
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual(object["profile"] as? String, "fast")
    XCTAssertEqual(object["max_elapsed_seconds"] as? Int, 300)
    XCTAssertEqual(object["max_network_bytes"] as? Int, 128 * 1_048_576)

    XCTAssertEqual(store.agentTaskBudget.profile, .adaptive)
    store.selectAgentTaskBudgetProfile(.economy)
    XCTAssertEqual(store.agentTaskBudget.maxCostMicros, 250_000)
    XCTAssertEqual(store.agentTaskBudget.minimumBatteryPercent, 15)

    store.updateAgentTaskBudget {
      $0.maxInputTokens = 999_999_999
      $0.allowPaidProviders = false
    }

    XCTAssertEqual(store.agentTaskBudget.profile, .custom)
    XCTAssertEqual(store.agentTaskBudget.maxInputTokens, AgentTaskBudget.maximumTokens)
    XCTAssertFalse(store.agentTaskBudget.allowPaidProviders)
  }

  func testAgentTaskBudgetPolicyMatchesAndroidLimitDecisions() {
    let timeDecision = AgentTaskBudgetPolicy.evaluate(
      budget: .forProfile(.fast),
      usage: AgentTaskBudgetUsage(elapsedMillis: 301_000)
    )
    let cloudDecision = AgentTaskBudgetPolicy.evaluate(
      budget: .forProfile(.privateMode),
      usage: AgentTaskBudgetUsage(),
      cloudProvider: true
    )
    let networkDecision = AgentTaskBudgetPolicy.evaluate(
      budget: AgentTaskBudget(networkPolicy: .offlineOnly),
      usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(networkAvailable: true),
      networkRequired: true
    )

    XCTAssertFalse(timeDecision.allowed)
    XCTAssertEqual(timeDecision.limit, .time)
    XCTAssertFalse(cloudDecision.allowed)
    XCTAssertEqual(cloudDecision.limit, .cloud)
    XCTAssertFalse(networkDecision.allowed)
    XCTAssertEqual(networkDecision.limit, .network)
  }

  func testGlobalBackgroundExecutionBudgetDefersForPowerAndBattery() {
    let now: Int64 = 10_000
    let settings = GlobalAgentSettings.default
    let power = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(
        powerSaveMode: true,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let critical = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .autonomousWork,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 14,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let lowReasoning = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 20,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let lowResearch = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 20,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let charging = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        batteryPercent: 10,
        charging: true,
        networkAvailable: true,
        networkValidated: true
      ),
      settings: settings,
      nowMillis: now
    )
    let override = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(powerSaveMode: true),
      settings: settings,
      nowMillis: now,
      explicitUserOverride: true
    )

    XCTAssertFalse(power.allowed)
    XCTAssertEqual(power.reason, .powerSave)
    XCTAssertEqual(power.nextEligibleAtMillis, now + GlobalBackgroundExecutionBudgetPolicy.powerSaveRetryMillis)
    XCTAssertFalse(critical.allowed)
    XCTAssertEqual(critical.reason, .criticalBattery)
    XCTAssertEqual(
      critical.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.criticalBatteryRetryMillis
    )
    XCTAssertFalse(lowReasoning.allowed)
    XCTAssertEqual(lowReasoning.reason, .lowBattery)
    XCTAssertEqual(
      lowReasoning.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.lowBatteryReasoningRetryMillis
    )
    XCTAssertFalse(lowResearch.allowed)
    XCTAssertEqual(lowResearch.reason, .lowBattery)
    XCTAssertEqual(
      lowResearch.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.lowBatteryResearchRetryMillis
    )
    XCTAssertTrue(charging.allowed)
    XCTAssertEqual(charging.reason, .none)
    XCTAssertTrue(override.allowed)
    XCTAssertEqual(override.nextEligibleAtMillis, now)
  }

  func testGlobalBackgroundExecutionBudgetHandlesResearchNetworkGates() {
    let now: Int64 = 20_000
    let settings = GlobalAgentSettings.default
    let unavailable = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(networkAvailable: false),
      settings: settings,
      nowMillis: now
    )
    let unvalidated = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(networkAvailable: true, networkValidated: false),
      settings: settings,
      nowMillis: now
    )
    let metered = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        networkAvailable: true,
        networkValidated: true,
        networkMetered: true
      ),
      settings: settings,
      nowMillis: now
    )
    let allowedMetered = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .research,
      environment: AgentTaskBudgetEnvironment(
        networkAvailable: true,
        networkValidated: true,
        networkMetered: true
      ),
      settings: GlobalAgentSettings(allowMeteredBackgroundResearch: true),
      nowMillis: now
    )
    let autonomousOffline = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .autonomousWork,
      environment: AgentTaskBudgetEnvironment(networkAvailable: false, networkValidated: false),
      settings: settings,
      nowMillis: now
    )
    let noBatteryProtection = GlobalBackgroundExecutionBudgetPolicy.decide(
      kind: .cognition,
      environment: AgentTaskBudgetEnvironment(batteryPercent: 5),
      settings: GlobalAgentSettings(protectBatteryForBackgroundWork: false),
      nowMillis: now
    )

    XCTAssertFalse(unavailable.allowed)
    XCTAssertEqual(unavailable.reason, .networkUnavailable)
    XCTAssertEqual(
      unavailable.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.networkRecoveryRetryMillis
    )
    XCTAssertFalse(unvalidated.allowed)
    XCTAssertEqual(unvalidated.reason, .networkUnvalidated)
    XCTAssertFalse(metered.allowed)
    XCTAssertEqual(metered.reason, .meteredNetwork)
    XCTAssertEqual(
      metered.nextEligibleAtMillis,
      now + GlobalBackgroundExecutionBudgetPolicy.meteredNetworkRetryMillis
    )
    XCTAssertTrue(allowedMetered.allowed)
    XCTAssertTrue(autonomousOffline.allowed)
    XCTAssertTrue(noBatteryProtection.allowed)
  }

  func testGlobalBackgroundExecutionBudgetModelsUseAndroidWireNames() throws {
    let decodedSettings = try JSONDecoder.signalASI.decode(
      GlobalAgentSettings.self,
      from: Data(
        """
        {
          "protect_battery_for_background_work": false,
          "allow_metered_background_research": true,
          "daily_background_model_call_budget": 9999,
          "max_concurrent_background_model_calls": 0,
          "daily_background_token_budget": -10,
          "discovery_interval_millis": 1
        }
        """.utf8
      )
    )
    let workKind = try JSONDecoder.signalASI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""autonomous-work""#.utf8)
    )
    let fallbackWorkKind = try JSONDecoder.signalASI.decode(
      GlobalBackgroundWorkKind.self,
      from: Data(#""future""#.utf8)
    )
    let reason = try JSONDecoder.signalASI.decode(
      GlobalBackgroundDeferralReason.self,
      from: Data(#""network_unvalidated""#.utf8)
    )
    let fallbackReason = try JSONDecoder.signalASI.decode(
      GlobalBackgroundDeferralReason.self,
      from: Data(#""future""#.utf8)
    )
    let encodedDecision = String(decoding: try JSONEncoder.signalASI.encode(
      GlobalBackgroundExecutionDecision(
        allowed: false,
        nextEligibleAtMillis: 9_999,
        reason: .lowBattery
      )
    ), as: UTF8.self)
    let powerConstrained = AgentTaskBudgetEnvironment(powerSaveMode: true)
    let lowBatteryConstrained = AgentTaskBudgetEnvironment(batteryPercent: 19)
    let chargingLowBattery = AgentTaskBudgetEnvironment(batteryPercent: 19, charging: true)

    XCTAssertFalse(decodedSettings.protectBatteryForBackgroundWork)
    XCTAssertTrue(decodedSettings.allowMeteredBackgroundResearch)
    XCTAssertEqual(decodedSettings.dailyBackgroundModelCallBudget, 1_000)
    XCTAssertEqual(decodedSettings.maxConcurrentBackgroundModelCalls, 1)
    XCTAssertEqual(decodedSettings.dailyBackgroundTokenBudget, 0)
    XCTAssertEqual(decodedSettings.discoveryIntervalMillis, 60_000)
    XCTAssertEqual(workKind, .autonomousWork)
    XCTAssertEqual(fallbackWorkKind, .cognition)
    XCTAssertEqual(reason, .networkUnvalidated)
    XCTAssertEqual(fallbackReason, .none)
    XCTAssertTrue(encodedDecision.contains(#""next_eligible_at_millis":9999"#))
    XCTAssertTrue(encodedDecision.contains(#""reason":"LOW_BATTERY""#))
    XCTAssertTrue(powerConstrained.energyConstrained)
    XCTAssertTrue(lowBatteryConstrained.energyConstrained)
    XCTAssertFalse(chargingLowBattery.energyConstrained)
  }

  func testGlobalModelCallBudgetAcquisitionIdempotencyAndConcurrency() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", concurrencyLimit: 1)
    let duplicateActive = acquireModelCall(first.state, "call-1", concurrencyLimit: 1)
    let blocked = acquireModelCall(first.state, "call-2", concurrencyLimit: 1)
    let released = GlobalModelCallBudgetPolicy.release(
      state: first.state,
      leaseId: first.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let second = acquireModelCall(
      released,
      "call-2",
      concurrencyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )
    let duplicateReleased = acquireModelCall(
      released,
      "call-1",
      nowMillis: globalBudgetNow + 100
    )

    XCTAssertTrue(first.granted)
    XCTAssertTrue(first.leaseId.hasPrefix("model-call:"))
    XCTAssertEqual(first.state.dispatches.count, 1)
    XCTAssertEqual(first.state.activeLeases.count, 1)
    XCTAssertEqual(first.state.activeLeases.first?.ownerKey, "call-1")
    XCTAssertTrue(duplicateActive.granted)
    XCTAssertEqual(duplicateActive.leaseId, first.leaseId)
    XCTAssertEqual(duplicateActive.state.dispatches.count, 1)
    XCTAssertFalse(blocked.granted)
    XCTAssertEqual(blocked.denial, .concurrencyLimit)
    XCTAssertEqual(blocked.nextEligibleAtMillis, globalBudgetNow + globalBudgetLeaseMillis)
    XCTAssertTrue(second.granted)
    XCTAssertEqual(second.state.dispatches.count, 2)
    XCTAssertEqual(second.state.activeLeases.count, 1)
    XCTAssertFalse(duplicateReleased.granted)
    XCTAssertEqual(duplicateReleased.denial, .duplicateDispatch)
  }

  func testGlobalModelCallBudgetRollingDailyTokenAndCostLimits() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", dailyLimit: 1)
    let released = GlobalModelCallBudgetPolicy.release(
      state: first.state,
      leaseId: first.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let dailyDenied = acquireModelCall(
      released,
      "call-2",
      dailyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )
    let afterWindow = acquireModelCall(
      dailyDenied.state,
      "call-2",
      dailyLimit: 1,
      nowMillis: globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis + 1
    )

    let tokenReserved = acquireModelCall(
      GlobalModelCallBudgetState(),
      "token-1",
      estimatedInputTokens: 9_000,
      dailyTokenLimit: 10_000
    )
    let tokenCompleted = GlobalModelCallBudgetPolicy.complete(
      state: tokenReserved.state,
      leaseId: tokenReserved.leaseId,
      inputTokens: 9_000,
      outputTokens: 900,
      reportedCostMicros: 0,
      responseText: "done",
      nowMillis: globalBudgetNow + 100
    )
    let tokenDenied = acquireModelCall(
      tokenCompleted,
      "token-2",
      estimatedInputTokens: 500,
      dailyTokenLimit: 10_000,
      nowMillis: globalBudgetNow + 200
    )

    let oversized = acquireModelCall(
      GlobalModelCallBudgetState(),
      "oversized",
      estimatedInputTokens: 20_000,
      dailyTokenLimit: 10_000
    )
    let oversizedReleased = GlobalModelCallBudgetPolicy.release(
      state: oversized.state,
      leaseId: oversized.leaseId,
      nowMillis: globalBudgetNow + 1
    )
    let oversizedFollowUp = acquireModelCall(
      oversizedReleased,
      "oversized-next",
      estimatedInputTokens: 1,
      dailyTokenLimit: 10_000,
      nowMillis: globalBudgetNow + 2
    )

    let costFirst = acquireModelCall(
      GlobalModelCallBudgetState(),
      "cost-1",
      dailyReportedCostLimitMicros: 10_000
    )
    let costCompleted = GlobalModelCallBudgetPolicy.complete(
      state: costFirst.state,
      leaseId: costFirst.leaseId,
      inputTokens: 10,
      outputTokens: 5,
      reportedCostMicros: 10_000,
      responseText: "done",
      nowMillis: globalBudgetNow + 100
    )
    let costDenied = acquireModelCall(
      costCompleted,
      "cost-2",
      dailyReportedCostLimitMicros: 10_000,
      nowMillis: globalBudgetNow + 200
    )

    XCTAssertFalse(dailyDenied.granted)
    XCTAssertEqual(dailyDenied.denial, .dailyLimit)
    XCTAssertEqual(dailyDenied.nextEligibleAtMillis, globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis)
    XCTAssertTrue(afterWindow.granted)
    XCTAssertEqual(afterWindow.state.dispatches.count, 1)
    XCTAssertFalse(tokenDenied.granted)
    XCTAssertEqual(tokenDenied.denial, .tokenLimit)
    XCTAssertTrue(oversized.granted)
    XCTAssertFalse(oversizedFollowUp.granted)
    XCTAssertEqual(oversizedFollowUp.denial, .tokenLimit)
    XCTAssertFalse(costDenied.granted)
    XCTAssertEqual(costDenied.denial, .reportedCostLimit)
    XCTAssertEqual(costDenied.nextEligibleAtMillis, globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis)
  }

  func testGlobalModelCallBudgetCompletionCancellationAndAvailability() {
    let acquired = acquireModelCall(
      GlobalModelCallBudgetState(),
      "call-1",
      resourceId: "cloud-model:primary",
      estimatedInputTokens: 120
    )
    let completed = GlobalModelCallBudgetPolicy.complete(
      state: acquired.state,
      leaseId: acquired.leaseId,
      inputTokens: 180,
      outputTokens: 45,
      reportedCostMicros: 2_500,
      responseText: "done",
      nowMillis: globalBudgetNow + 500
    )
    let estimatedAcquired = acquireModelCall(GlobalModelCallBudgetState(), "call-2", estimatedInputTokens: 80)
    let estimated = GlobalModelCallBudgetPolicy.complete(
      state: estimatedAcquired.state,
      leaseId: estimatedAcquired.leaseId,
      inputTokens: 0,
      outputTokens: 0,
      reportedCostMicros: 0,
      responseText: "A useful answer",
      nowMillis: globalBudgetNow + 500
    )
    let cancelledFirst = acquireModelCall(GlobalModelCallBudgetState(), "cancel-1", dailyLimit: 1)
    let cancelled = GlobalModelCallBudgetPolicy.cancel(
      state: cancelledFirst.state,
      leaseId: cancelledFirst.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let afterCancel = acquireModelCall(cancelled, "cancel-2", dailyLimit: 1, nowMillis: globalBudgetNow + 100)
    let busy = GlobalModelCallBudgetPolicy.availability(
      state: acquired.state,
      dailyLimit: 48,
      concurrencyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )

    let dispatch = completed.dispatches.first
    XCTAssertEqual(dispatch?.inputTokens, 180)
    XCTAssertEqual(dispatch?.outputTokens, 45)
    XCTAssertEqual(dispatch?.totalTokens, 225)
    XCTAssertEqual(dispatch?.reportedCostMicros, 2_500)
    XCTAssertEqual(dispatch?.usageEstimated, false)
    XCTAssertEqual(dispatch?.completedAtMillis, globalBudgetNow + 500)
    XCTAssertTrue(completed.activeLeases.isEmpty)
    XCTAssertEqual(estimated.dispatches.first?.inputTokens, 80)
    XCTAssertTrue((estimated.dispatches.first?.outputTokens ?? 0) > 0)
    XCTAssertEqual(estimated.dispatches.first?.usageEstimated, true)
    XCTAssertTrue(afterCancel.granted)
    XCTAssertEqual(afterCancel.state.dispatches.count, 1)
    XCTAssertFalse(busy.granted)
    XCTAssertEqual(busy.denial, .concurrencyLimit)
    XCTAssertEqual(busy.state.dispatches.count, 1)
  }

  func testGlobalModelCallBudgetResourceUsageSnapshotAndSaturation() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", resourceId: "model-a")
    let firstDone = GlobalModelCallBudgetPolicy.complete(
      state: first.state,
      leaseId: first.leaseId,
      inputTokens: 100,
      outputTokens: 20,
      reportedCostMicros: 1_000,
      responseText: "a",
      nowMillis: globalBudgetNow + 1
    )
    let second = acquireModelCall(firstDone, "call-2", resourceId: "model-a", nowMillis: globalBudgetNow + 2)
    let secondDone = GlobalModelCallBudgetPolicy.complete(
      state: second.state,
      leaseId: second.leaseId,
      inputTokens: 200,
      outputTokens: 40,
      reportedCostMicros: 3_000,
      responseText: "b",
      nowMillis: globalBudgetNow + 3
    )
    let third = acquireModelCall(secondDone, "call-3", resourceId: "model-b", nowMillis: globalBudgetNow + 4)
    let usage = GlobalModelCallBudgetPolicy.resourceUsage(
      dispatches: third.state.dispatches,
      resourceId: "model-a"
    )
    let saturated = GlobalModelCallBudgetPolicy.totalTokens([
      GlobalModelCallDispatch(leaseId: "a", kind: .cognition, startedAtMillis: globalBudgetNow, inputTokens: Int64.max),
      GlobalModelCallDispatch(leaseId: "b", kind: .cognition, startedAtMillis: globalBudgetNow + 1, outputTokens: Int64.max)
    ])
    let snapshot = GlobalModelCallBudgetPolicy.snapshot(
      state: third.state,
      dailyLimit: 999,
      concurrencyLimit: 99,
      nowMillis: globalBudgetNow + 5,
      dailyTokenLimit: 999_999_999,
      dailyReportedCostLimitMicros: 999_999_999
    )

    XCTAssertEqual(usage.dispatches, 2)
    XCTAssertEqual(usage.averageInputTokens, 150)
    XCTAssertEqual(usage.averageOutputTokens, 30)
    XCTAssertEqual(usage.averageTotalTokens, 180)
    XCTAssertEqual(usage.averageReportedCostMicros, 2_000)
    XCTAssertEqual(saturated, Int64.max)
    XCTAssertEqual(snapshot.dailyLimit, GlobalModelCallBudgetPolicy.maxDailyLimit)
    XCTAssertEqual(snapshot.concurrencyLimit, GlobalModelCallBudgetPolicy.maxConcurrencyLimit)
    XCTAssertEqual(snapshot.dailyTokenLimit, GlobalModelCallBudgetPolicy.maxDailyTokenLimit)
    XCTAssertEqual(snapshot.dailyReportedCostLimitMicros, GlobalModelCallBudgetPolicy.maxDailyReportedCostLimitMicros)
    XCTAssertEqual(snapshot.dispatchesByKind[GlobalModelCallKind.cognition.rawValue] ?? 0, 3)
    XCTAssertEqual(snapshot.totalTokensInWindow, 360)
    XCTAssertEqual(snapshot.reportedCostMicrosInWindow, 4_000)
  }

  func testGlobalModelCallBudgetModelsUseAndroidWireNames() throws {
    let state = try JSONDecoder.signalASI.decode(
      GlobalModelCallBudgetState.self,
      from: Data(
        #"""
        {
          "dispatches": [
            {
              "lease_id": "lease-1",
              "kind": "RESEARCH_EVIDENCE",
              "started_at_millis": 1000,
              "resource_id": "model-a",
              "input_tokens": 10,
              "output_tokens": 20,
              "reported_cost_micros": 30,
              "usage_estimated": false,
              "completed_at_millis": 1200
            }
          ],
          "active_leases": [
            {
              "id": "lease-2",
              "kind": "PLAN_REVIEW",
              "owner_key": "review",
              "started_at_millis": 1000,
              "expires_at_millis": 2000
            }
          ]
        }
        """#.utf8
      )
    )
    let fallbackKind = try JSONDecoder.signalASI.decode(
      GlobalModelCallKind.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackDenial = try JSONDecoder.signalASI.decode(
      GlobalModelCallBudgetDenial.self,
      from: Data(#""future""#.utf8)
    )
    let decision = GlobalModelCallBudgetDecision(
      granted: false,
      state: state,
      denial: .dailyLimit,
      nextEligibleAtMillis: 9_999
    )
    let encodedDecision = String(decoding: try JSONEncoder.signalASI.encode(decision), as: UTF8.self)
    let encodedSnapshot = String(decoding: try JSONEncoder.signalASI.encode(
      GlobalModelCallBudgetPolicy.snapshot(
        state: state,
        dailyLimit: 48,
        concurrencyLimit: 3,
        nowMillis: 1_500
      )
    ), as: UTF8.self)

    XCTAssertEqual(state.dispatches.first?.kind, .researchEvidence)
    XCTAssertEqual(state.activeLeases.first?.kind, .planReview)
    XCTAssertEqual(fallbackKind, .cognition)
    XCTAssertEqual(fallbackDenial, .dailyLimit)
    XCTAssertTrue(encodedDecision.contains(#""next_eligible_at_millis":9999"#))
    XCTAssertTrue(encodedDecision.contains(#""active_leases""#))
    XCTAssertTrue(encodedSnapshot.contains(#""dispatches_by_kind""#))
    XCTAssertEqual(
      GlobalModelCallBudgetPolicy.leaseId(kind: .cognition, ownerKey: "Call 1"),
      GlobalModelCallBudgetPolicy.leaseId(kind: .cognition, ownerKey: " call   1 ")
    )
  }

  func testCustomDeviceConnectorsDecodeAndroidFieldsAndStoreTokensInKeychain() throws {
    let connector = try JSONDecoder.signalASI.decode(
      CustomDeviceConnector.self,
      from: Data("""
      {
        "id": " custom-device-office ",
        "name": " Office Light ",
        "transport": "mqtt",
        "endpoint": " mqtt://broker.local ",
        "command_target": " topic/light/office ",
        "username": " user ",
        "auth_token": " token ",
        "risk": "HIGH",
        "enabled": true
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(connector)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)

    XCTAssertEqual(connector.id, "custom-device-office")
    XCTAssertEqual(connector.name, "Office Light")
    XCTAssertEqual(connector.transport, .mqtt)
    XCTAssertEqual(connector.endpoint, "mqtt://broker.local")
    XCTAssertEqual(connector.commandTarget, "topic/light/office")
    XCTAssertEqual(connector.username, "user")
    XCTAssertEqual(connector.authToken, "token")
    XCTAssertEqual(connector.risk, .high)
    XCTAssertTrue(connector.configured)
    XCTAssertEqual(object["transport"] as? String, "MQTT")
    XCTAssertEqual(object["command_target"] as? String, "topic/light/office")
    XCTAssertEqual(object["auth_token"] as? String, "token")
    XCTAssertEqual(object["risk"] as? String, "HIGH")

    store.upsertCustomDeviceConnector(connector)

    XCTAssertEqual(store.customDeviceConnectors.count, 1)
    XCTAssertEqual(store.customDeviceConnectors[0].transport, .mqtt)
    XCTAssertEqual(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"), "token")

    let overflow = (0..<55).map { index in
      CustomDeviceConnector(id: "device-\(index)", name: "Device \(index)", endpoint: "http://device-\(index).local")
    }
    for item in overflow {
      store.upsertCustomDeviceConnector(item)
    }

    XCTAssertEqual(store.customDeviceConnectors.count, CustomDeviceConnector.maximumConnectors)
    XCTAssertNil(store.customDeviceConnectors.first { $0.id == "custom-device-office" })

    store.upsertCustomDeviceConnector(connector)
    XCTAssertTrue(store.deleteCustomDeviceConnector(id: connector.id))
    XCTAssertNil(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"))
  }

  func testModelPlannerSettingsDecodeAndroidFieldsAndNormalizeBounds() throws {
    let longContactId = String(repeating: "x", count: 160)
    let settings = try JSONDecoder.signalASI.decode(
      AgentModelPlannerSettings.self,
      from: Data("""
      {
        "version": 5,
        "enabled": true,
        "share_screen_text": true,
        "max_actions": 99,
        "cloud_contact_id": "  \(longContactId)  ",
        "dynamic_replanning": false,
        "max_replans": 99,
        "multi_agent_coordination": false,
        "share_agent_outputs_with_planner": true,
        "max_agent_hops": 99,
        "max_tool_calls": 1,
        "max_loop_iterations": 99,
        "max_phase_retries": -1,
        "no_progress_timeout_seconds": 99999
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let store = makeStore()

    XCTAssertTrue(settings.enabled)
    XCTAssertTrue(settings.shareScreenText)
    XCTAssertEqual(settings.maxActions, AgentModelPlannerSettings.maximumActions)
    XCTAssertEqual(settings.cloudContactId.count, AgentModelPlannerSettings.maximumCloudContactIdLength)
    XCTAssertFalse(settings.dynamicReplanning)
    XCTAssertEqual(settings.maxReplans, AgentModelPlannerSettings.maximumReplans)
    XCTAssertFalse(settings.multiAgentCoordination)
    XCTAssertTrue(settings.shareAgentOutputsWithPlanner)
    XCTAssertEqual(settings.maxAgentHops, AgentModelPlannerSettings.maximumAgentHops)
    XCTAssertEqual(settings.maxToolCalls, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(settings.maxLoopIterations, AgentModelPlannerSettings.maximumLoopIterations)
    XCTAssertEqual(settings.maxPhaseRetries, AgentModelPlannerSettings.minimumPhaseRetries)
    XCTAssertEqual(settings.noProgressTimeoutSeconds, AgentModelPlannerSettings.maximumNoProgressTimeoutSeconds)
    XCTAssertEqual(object["version"] as? Int, 5)
    XCTAssertEqual(object["max_actions"] as? Int, AgentModelPlannerSettings.maximumActions)
    XCTAssertEqual(object["max_tool_calls"] as? Int, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(object["no_progress_timeout_seconds"] as? Int, AgentModelPlannerSettings.maximumNoProgressTimeoutSeconds)

    XCTAssertEqual(store.modelPlannerSettings, .default)
    store.updateModelPlannerSettings {
      $0.enabled = true
      $0.maxActions = 0
      $0.maxPhaseRetries = 99
      $0.noProgressTimeoutSeconds = 30
    }

    XCTAssertTrue(store.modelPlannerSettings.enabled)
    XCTAssertEqual(store.modelPlannerSettings.maxActions, 1)
    XCTAssertEqual(store.modelPlannerSettings.maxPhaseRetries, AgentModelPlannerSettings.maximumPhaseRetries)
    XCTAssertEqual(store.modelPlannerSettings.noProgressTimeoutSeconds, AgentModelPlannerSettings.minimumNoProgressTimeoutSeconds)
  }

  func testAgentAutonomyGuardStopsWhenToolCallBudgetIsReached() {
    let completed = (0..<AgentModelPlannerSettings.minimumToolCalls).map {
      agentAutonomyAction(id: "completed-\($0)", status: .completed, package: "com.signalasi.\($0)")
    }
    let pending = agentAutonomyAction(id: "pending", status: .pendingConfirmation)
    let plan = agentAutonomyPlan(actions: [pending], actionHistory: completed)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: pending,
      settings: AgentModelPlannerSettings(maxToolCalls: AgentModelPlannerSettings.minimumToolCalls)
    )

    XCTAssertFalse(decision.allowed)
    XCTAssertEqual(decision.reason, "Autonomous tool-call budget reached")
    XCTAssertEqual(decision.completedToolCalls, AgentModelPlannerSettings.minimumToolCalls)
    XCTAssertEqual(decision.repeatedCalls, 0)
  }

  func testAgentAutonomyGuardIgnoresReadScreenDraftAndPendingActionsForBudget() {
    let history = [
      agentAutonomyAction(id: "screen", kind: .readScreen, status: .completed),
      agentAutonomyAction(id: "draft", kind: .draftPlan, status: .failed),
      agentAutonomyAction(id: "pending", kind: .openApp, status: .pendingConfirmation),
      agentAutonomyAction(id: "blocked", kind: .openApp, status: .blocked, package: "com.signalasi.blocked")
    ]
    let next = agentAutonomyAction(id: "next", kind: .callConnector, status: .pendingConfirmation, connectorId: "calendar")
    let plan = agentAutonomyPlan(actions: [next], actionHistory: history)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: next,
      settings: AgentModelPlannerSettings(maxToolCalls: 8)
    )

    XCTAssertTrue(decision.allowed)
    XCTAssertEqual(AgentAutonomyGuard.completedToolCalls(plan: plan), 1)
    XCTAssertEqual(decision.completedToolCalls, 1)
  }

  func testAgentAutonomyGuardBlocksRepeatedLoopSensitiveToolCalls() {
    let repeated = [
      agentAutonomyAction(id: "first", kind: .openApp, status: .completed, package: "com.signalasi.chat"),
      agentAutonomyAction(id: "second", kind: .openApp, status: .failed, package: "com.signalasi.chat")
    ]
    let pending = agentAutonomyAction(
      id: "third",
      kind: .openApp,
      status: .pendingConfirmation,
      package: "com.signalasi.chat"
    )
    let plan = agentAutonomyPlan(actions: [pending], actionHistory: repeated)

    let decision = AgentAutonomyGuard.review(
      plan: plan,
      action: pending,
      settings: AgentModelPlannerSettings(maxToolCalls: 8)
    )

    XCTAssertFalse(decision.allowed)
    XCTAssertEqual(decision.reason, "Repeated autonomous tool-call loop blocked")
    XCTAssertEqual(decision.completedToolCalls, 2)
    XCTAssertEqual(decision.repeatedCalls, AgentAutonomyGuard.maxRepeatedToolCalls)
  }

  func testAgentAutonomyGuardAllowsDistinctPromptSignaturesAndNonLoopActions() {
    let first = agentAutonomyAction(
      id: "first",
      kind: .callConnector,
      status: .completed,
      connectorId: "research",
      prompt: "Find the latest note"
    )
    let second = agentAutonomyAction(
      id: "second",
      kind: .callConnector,
      status: .failed,
      connectorId: "research",
      prompt: "Find the latest note"
    )
    let distinctPrompt = agentAutonomyAction(
      id: "distinct",
      kind: .callConnector,
      status: .pendingConfirmation,
      connectorId: "research",
      prompt: "Find the latest note again"
    )
    let nonLoopRepeated = agentAutonomyAction(
      id: "type",
      kind: .typeText,
      status: .pendingConfirmation,
      prompt: "Find the latest note"
    )
    let plan = agentAutonomyPlan(actions: [distinctPrompt], actionHistory: [first, second])

    XCTAssertTrue(
      AgentAutonomyGuard.review(
        plan: plan,
        action: distinctPrompt,
        settings: AgentModelPlannerSettings(maxToolCalls: 8)
      ).allowed
    )
    XCTAssertTrue(
      AgentAutonomyGuard.review(
        plan: agentAutonomyPlan(actions: [nonLoopRepeated], actionHistory: [first, second]),
        action: nonLoopRepeated,
        settings: AgentModelPlannerSettings(maxToolCalls: 8)
      ).allowed
    )
  }

  func testAgentAutonomyGuardModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.signalASI.decode(
      AgentAutonomyDecision.self,
      from: Data(
        #"{"allowed":false,"reason":"Repeated autonomous tool-call loop blocked","completed_tool_calls":2,"repeated_calls":2}"#.utf8
      )
    )
    let encoded = String(
      decoding: try JSONEncoder.signalASI.encode(decoded),
      as: UTF8.self
    )

    XCTAssertFalse(decoded.allowed)
    XCTAssertEqual(decoded.completedToolCalls, 2)
    XCTAssertEqual(decoded.repeatedCalls, 2)
    XCTAssertTrue(encoded.contains(#""completed_tool_calls":2"#))
    XCTAssertTrue(encoded.contains(#""repeated_calls":2"#))
  }

  func testHomeAssistantSettingsDecodeAndroidFieldsAndStoreTokenInKeychain() throws {
    let longURL = "http://homeassistant.local:8123/" + String(repeating: "x", count: 2_200)
    let longToken = String(repeating: "t", count: 8_400)
    let settings = try JSONDecoder.signalASI.decode(
      HomeAssistantSettings.self,
      from: Data("""
      {
        "version": 1,
        "enabled": true,
        "base_url": "  \(longURL)//  ",
        "access_token": "  \(longToken)  ",
        "default_entity_id": "  light.living_room  "
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(settings)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)

    XCTAssertTrue(settings.enabled)
    XCTAssertTrue(settings.credentialsConfigured)
    XCTAssertTrue(settings.configured)
    XCTAssertFalse(settings.baseUrl.hasSuffix("/"))
    XCTAssertEqual(settings.baseUrl.count, HomeAssistantSettings.maximumBaseURLLength)
    XCTAssertEqual(settings.accessToken.count, HomeAssistantSettings.maximumAccessTokenLength)
    XCTAssertEqual(settings.defaultEntityId, "light.living_room")
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual(object["base_url"] as? String, settings.baseUrl)
    XCTAssertEqual(object["access_token"] as? String, settings.accessToken)

    store.updateHomeAssistantSettings {
      $0.enabled = true
      $0.baseUrl = " http://homeassistant.local:8123/ "
      $0.accessToken = " ha-token "
      $0.defaultEntityId = " light.office "
    }

    XCTAssertTrue(store.homeAssistantSettings.configured)
    XCTAssertEqual(store.homeAssistantSettings.baseUrl, "http://homeassistant.local:8123")
    XCTAssertEqual(store.homeAssistantSettings.accessToken, "ha-token")
    XCTAssertEqual(store.homeAssistantSettings.defaultEntityId, "light.office")
    XCTAssertEqual(secrets.string(account: "home_assistant.access_token"), "ha-token")

    store.updateHomeAssistantSettings {
      $0.accessToken = ""
    }

    XCTAssertFalse(store.homeAssistantSettings.credentialsConfigured)
    XCTAssertNil(secrets.string(account: "home_assistant.access_token"))
  }

  func testAgentActiveTurnPolicyMatchesAndroidContinuationDecisions() {
    for request in [
      "Stop",
      "Cancel the current task.",
      "\u{505c}\u{6b62}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
      "\u{4e0d}\u{7528}\u{7ee7}\u{7eed}\u{4e86}"
    ] {
      let decision = AgentActiveTurnPolicy.decide(
        request: request,
        activeGoal: "Build an Android app"
      )

      XCTAssertEqual(decision.disposition, .interrupt)
      XCTAssertEqual(decision.interventionKind, .interrupt)
    }

    let newTask = AgentActiveTurnPolicy.decide(
      request: "\u{65b0}\u{4efb}\u{52a1}: \u{67e5}\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}",
      activeGoal: "\u{6784}\u{5efa} Android \u{5e94}\u{7528}"
    )
    XCTAssertEqual(newTask.disposition, .independent)
    XCTAssertFalse(newTask.intervenes)

    let goalChange = AgentActiveTurnPolicy.decide(
      request: "\u{6539}\u{6210} Android \u{539f}\u{751f}\u{5e94}\u{7528}",
      activeGoal: "\u{505a}\u{4e00}\u{4e2a}\u{7f51}\u{9875}\u{5e94}\u{7528}"
    )
    XCTAssertEqual(goalChange.disposition, .steer)
    XCTAssertEqual(goalChange.interventionKind, .goalChange)

    let constraint = AgentActiveTurnPolicy.decide(
      request: "Do not stop after the first page.",
      activeGoal: "Export the whole report"
    )
    XCTAssertEqual(constraint.disposition, .steer)
    XCTAssertEqual(constraint.interventionKind, .constraint)

    let prompt = AgentActiveTurnPolicy.supersedingGoal(
      activeGoal: "Build a web game",
      intervention: "Change the goal to an Android game",
      kind: .goalChange
    )
    XCTAssertTrue(prompt.contains("Build a web game"))
    XCTAssertTrue(prompt.contains("Change the goal to an Android game"))
    XCTAssertTrue(prompt.contains("latest instruction has priority"))

    XCTAssertEqual(
      AgentActiveTurnPolicy.decide(
        request: "Review this image",
        activeGoal: "Build an Android app",
        hasNewAttachments: true
      ).disposition,
      .independent
    )
    XCTAssertEqual(
      AgentActiveTurnPolicy.decide(
        request: "Use this image instead",
        activeGoal: "Review the earlier image",
        hasNewAttachments: true
      ).disposition,
      .steer
    )
  }

  func testAgentRuntimeCapabilityMatrixKeepsUnavailableAndBlockedVisibleButNotExecutable() throws {
    let available = try nativeToolDescriptor("signalasi.test.available")
    let setup = try nativeToolDescriptor(
      "signalasi.test.setup",
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Permission missing"
      )
    )
    let unavailable = try nativeToolDescriptor(
      "signalasi.test.unavailable",
      availability: AgentNativeToolAvailability(
        status: .unavailable,
        reason: "Runtime missing"
      )
    )
    let blocked = try nativeToolDescriptor("signalasi.test.blocked", risk: .blocked)

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [available, setup, unavailable, blocked],
      systemTools: [],
      targets: []
    )

    XCTAssertEqual(snapshot.availableNativeToolIds, Set([available.id]))
    XCTAssertEqual(snapshot.entries.count, 4)
    XCTAssertEqual(snapshot.setupRequiredEntries.count, 1)
    XCTAssertEqual(snapshot.unavailableEntries.count, 2)
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: setup.id))
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: unavailable.id))
    XCTAssertFalse(snapshot.isNativeToolExecutable(id: blocked.id))
  }

  func testAgentRuntimeCapabilityMatrixUsesLiveNativeAdapterStateForSystemTools() throws {
    let native = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.openApp),
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "No matching activity"
      ),
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.open_app")
      ]
    )
    let action = AgentSystemTool(
      id: "open-app",
      title: "Open app",
      kind: .openApp,
      risk: .low,
      capabilities: [.appNavigation]
    )
    let workflow = AgentSystemTool(
      id: "workflow:daily",
      title: "Daily workflow",
      kind: .draftPlan,
      risk: .low,
      capabilities: [.taskExecution]
    )

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [native],
      systemTools: [action, workflow],
      targets: []
    )
    let actionEntry = try XCTUnwrap(snapshot.entry(source: .systemTool, id: action.id))
    let workflowEntry = try XCTUnwrap(snapshot.entry(source: .systemTool, id: workflow.id))

    XCTAssertEqual(actionEntry.state, .requiresSetup)
    XCTAssertEqual(actionEntry.reason, "No matching activity")
    XCTAssertEqual(actionEntry.requiredPermissions, ["ios.open_app"])
    XCTAssertEqual(workflowEntry.state, .available)
    XCTAssertEqual(workflowEntry.reason, "Host-owned workflow is installed")
  }

  func testAgentRuntimeCapabilityMatrixProjectsConnectorAndNativeStatusTogether() throws {
    let available = try nativeToolDescriptor("signalasi.test.available")
    let unavailable = try nativeToolDescriptor(
      "signalasi.test.unavailable",
      availability: AgentNativeToolAvailability(status: .unavailable, reason: "Missing")
    )
    let target = AgentCallableTarget(
      id: "codex",
      title: "Codex",
      kind: .agent,
      status: .disconnected,
      capabilities: [.code],
      failureDomain: "desktop"
    )

    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [available, unavailable],
      systemTools: [],
      targets: [target]
    )

    XCTAssertEqual(snapshot.entry(source: .connector, id: "codex")?.state, .unavailable)
    XCTAssertEqual(snapshot.entry(source: .nativeTool, id: available.id)?.state, .available)
    XCTAssertEqual(snapshot.entry(source: .nativeTool, id: unavailable.id)?.state, .unavailable)
    XCTAssertEqual(
      AgentRuntimeCapabilityMatrix.availableNativeTools(
        nativeTools: [available, unavailable],
        targets: [target]
      ).map(\.id),
      [available.id]
    )
  }

  func testAgentRuntimeCapabilityMatrixModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.wire",
      capabilities: ["test.execute", "test.inspect"],
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.camera", title: "Camera")
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "capture.once", title: "Capture once")
      ]
    )
    let snapshot = AgentRuntimeCapabilityMatrix.build(
      nativeTools: [descriptor],
      systemTools: [],
      targets: []
    )
    let descriptorObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any]
    )
    let entryObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.entries[0])) as? [String: Any]
    )
    let source = try JSONDecoder().decode(
      AgentRuntimeCapabilitySource.self,
      from: Data(#""NATIVE_TOOL""#.utf8)
    )
    let capability = try JSONDecoder().decode(
      AgentCapability.self,
      from: Data(#""app-navigation""#.utf8)
    )

    XCTAssertNotNil(descriptorObject["input_schema"] as? [String: Any])
    XCTAssertNotNil(descriptorObject["output_schema"] as? [String: Any])
    XCTAssertNotNil(descriptorObject["required_permissions"] as? [[String: Any]])
    XCTAssertNotNil(descriptorObject["required_consents"] as? [[String: Any]])
    XCTAssertEqual(descriptorObject["timeout_millis"] as? Int, 30_000)
    XCTAssertEqual((descriptorObject["availability"] as? [String: Any])?["status"] as? String, "available")
    XCTAssertEqual(entryObject["source"] as? String, "NATIVE_TOOL")
    XCTAssertEqual(entryObject["state"] as? String, "AVAILABLE")
    XCTAssertEqual(entryObject["required_permissions"] as? [String], ["ios.camera"])
    XCTAssertEqual(entryObject["required_consents"] as? [String], ["capture.once"])
    XCTAssertEqual(source, .nativeTool)
    XCTAssertEqual(capability, .appNavigation)
  }

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let result = nativeToolResult(
      invocationId: "invoke-1",
      idempotencyKey: "native-replay-key",
      verification: AgentNativeToolVerification(
        status: .passed,
        evidence: ["receipt": .string("verified")]
      )
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    let verification = try XCTUnwrap(object["verification"] as? [String: Any])
    let decodedStatus = try JSONDecoder().decode(
      AgentNativeToolResultStatus.self,
      from: Data(#""unknown_status""#.utf8)
    )
    let decodedVerification = try JSONDecoder().decode(
      AgentNativeVerificationStatus.self,
      from: Data(#""unknown_verification""#.utf8)
    )
    let roundTripped = try XCTUnwrap(AgentNativeToolResult.fromJSONObject(result.toJSONObject()))

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(object["status"] as? String, "succeeded")
    XCTAssertNotNil(object["output"] as? [String: Any])
    XCTAssertEqual(receipt["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(receipt["idempotency_key"] as? String, "native-replay-key")
    XCTAssertEqual(receipt["started_at_epoch_ms"] as? Int, 1_000)
    XCTAssertEqual(receipt["finished_at_epoch_ms"] as? Int, 1_050)
    XCTAssertEqual(receipt["duration_ms"] as? Int, 50)
    XCTAssertEqual(receipt["input_sha256"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(receipt["output_sha256"] as? String, String(repeating: "b", count: 64))
    XCTAssertEqual(receipt["replayed"] as? Bool, false)
    XCTAssertEqual(provenance["tool_id"] as? String, "signalasi.test.native")
    XCTAssertEqual(provenance["tool_version"] as? String, "1.0.0")
    XCTAssertEqual(provenance["executor_id"] as? String, "ios-native")
    XCTAssertEqual(provenance["contract_version"] as? String, "signalasi.native-tool/1.0")
    XCTAssertEqual(verification["status"] as? String, "passed")
    XCTAssertEqual(decodedStatus, .failed)
    XCTAssertEqual(decodedVerification, .skipped)
    XCTAssertEqual(roundTripped, result)
  }

  func testAgentNativeToolReplayStoreEvictsOldestAndClears() throws {
    let store = InMemoryAgentNativeToolReplayStore()
    let firstKey = AgentNativeToolReplayKey(
      toolId: "signalasi.test.first",
      toolVersion: "1.0.0",
      idempotencyKey: "first"
    )
    try store.put(firstKey, result: nativeToolResult(invocationId: "first", idempotencyKey: "first"))

    for index in 1...InMemoryAgentNativeToolReplayStore.maxEntries {
      let key = AgentNativeToolReplayKey(
        toolId: "signalasi.test.\(index)",
        toolVersion: "1.0.0",
        idempotencyKey: "key-\(index)"
      )
      try store.put(key, result: nativeToolResult(invocationId: "invoke-\(index)", idempotencyKey: key.idempotencyKey))
    }

    let retainedKey = AgentNativeToolReplayKey(
      toolId: "signalasi.test.1",
      toolVersion: "1.0.0",
      idempotencyKey: "key-1"
    )
    let lastKey = AgentNativeToolReplayKey(
      toolId: "signalasi.test.\(InMemoryAgentNativeToolReplayStore.maxEntries)",
      toolVersion: "1.0.0",
      idempotencyKey: "key-\(InMemoryAgentNativeToolReplayStore.maxEntries)"
    )

    XCTAssertNil(store.get(firstKey))
    XCTAssertEqual(store.get(retainedKey)?.receipt.invocationId, "invoke-1")
    XCTAssertEqual(store.get(lastKey)?.receipt.invocationId, "invoke-\(InMemoryAgentNativeToolReplayStore.maxEntries)")

    store.clear()

    XCTAssertNil(store.get(retainedKey))
    XCTAssertNil(store.get(lastKey))
  }

  func testAgentNativeToolReplaySnapshotStoreKeepsSuccessfulFreshResults() throws {
    var now: Int64 = 1_000
    let key = AgentNativeToolReplayKey(
      toolId: "signalasi.test.native",
      toolVersion: "1.0.0",
      idempotencyKey: "replay-once"
    )
    let store = AgentNativeToolReplaySnapshotStore(nowMillis: { now })

    try store.put(key, result: nativeToolResult(invocationId: "fresh", idempotencyKey: "replay-once"))

    let serialized = store.serializedSnapshot()
    let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(serialized.utf8)) as? [[String: Any]])
    let first = try XCTUnwrap(entries.first)
    let restored = AgentNativeToolReplaySnapshotStore(serializedEntries: serialized, nowMillis: { now })
    let replayed = try XCTUnwrap(restored.get(key))

    XCTAssertEqual(first["tool_id"] as? String, "signalasi.test.native")
    XCTAssertEqual(first["tool_version"] as? String, "1.0.0")
    XCTAssertEqual(first["idempotency_key"] as? String, "replay-once")
    XCTAssertEqual(first["saved_at_millis"] as? Int, 1_000)
    XCTAssertNotNil(first["result"] as? [String: Any])
    XCTAssertEqual(replayed.receipt.invocationId, "fresh")
    XCTAssertThrowsError(
      try restored.put(
        AgentNativeToolReplayKey(toolId: "signalasi.test.native", toolVersion: "1.0.0", idempotencyKey: "failed"),
        result: nativeToolResult(status: .failed, invocationId: "failed", idempotencyKey: "failed")
      )
    ) { error in
      XCTAssertEqual(error as? AgentNativeToolReplayError, .unsuccessfulResult)
    }

    now += AgentNativeToolReplaySnapshotStore.retentionMillis + 1

    XCTAssertNil(restored.get(key))
    XCTAssertEqual(restored.serializedSnapshot(), "[]")
  }

  func testAgentNativeToolReplayJsonCodecSkipsMalformedEntries() throws {
    let key = AgentNativeToolReplayKey(
      toolId: "signalasi.test.native",
      toolVersion: "1.0.0",
      idempotencyKey: "valid"
    )
    let valid = AgentNativeToolReplayEntry(
      key: key,
      result: nativeToolResult(invocationId: "valid", idempotencyKey: "valid"),
      savedAtMillis: 2_000
    )
    let raw = AgentMcpJSONCodec.stringify(.array([
      .string("ignored"),
      .object([
        "tool_id": .string(""),
        "tool_version": .string("1.0.0"),
        "idempotency_key": .string("blank"),
        "saved_at_millis": .int(1_000),
        "result": valid.result.toJsonValue()
      ]),
      .object([
        "tool_id": .string(valid.key.toolId),
        "tool_version": .string(valid.key.toolVersion),
        "idempotency_key": .string(valid.key.idempotencyKey),
        "saved_at_millis": .int(valid.savedAtMillis),
        "result": valid.result.toJsonValue()
      ])
    ]))
    let decoded = AgentNativeToolReplayJsonCodec.decode(raw)

    XCTAssertEqual(decoded, [valid])
    XCTAssertTrue(AgentNativeToolReplayJsonCodec.decode("{broken").isEmpty)
  }

  func testAgentCapabilityCatalogIdsAreStableAndUnique() {
    let mcp = AgentDefaultCapabilityCatalog.mcpEntries
    let skills = AgentDefaultCapabilityCatalog.skillEntries

    XCTAssertGreaterThanOrEqual(mcp.count, 4)
    XCTAssertGreaterThanOrEqual(skills.count, 5)
    XCTAssertEqual(Set(mcp.map(\.id)).count, mcp.count)
    XCTAssertEqual(Set(skills.map(\.id)).count, skills.count)
    XCTAssertTrue(mcp.contains { $0.requiresPackage })
    XCTAssertTrue(skills.contains { !$0.requiredMcpCatalogIds.isEmpty })
  }

  func testAgentCapabilityCatalogMarketplaceUnifiesToolsMcpAndAutomationState() throws {
    let nativeTool = try nativeToolDescriptor(
      AgentMcpNativeTools.callTool,
      risk: .medium,
      capabilities: ["mcp.call"],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "mcp.call.once", title: "MCP call")
      ]
    )
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 1_000 })

    let initial = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [nativeTool],
      installedMcp: registry.list(),
      installedAutomations: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(initial.first { $0.id == AgentMcpNativeTools.callTool }?.installState, .builtIn)
    let github = try XCTUnwrap(initial.first { $0.id == "signalasi.mcp.github" })
    XCTAssertEqual(github.installState, .available)
    XCTAssertTrue(github.permissionDiff.requiresApproval)
    XCTAssertTrue(github.capabilities.contains("github.repositories"))
    XCTAssertEqual(initial.first { $0.id == "signalasi.catalog.github-triage" }?.installState, .needsSetup)

    _ = try registry.addRemote(
      displayName: "GitHub",
      endpoint: "https://api.githubcopilot.com/mcp/",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "signalasi.mcp.github",
      id: "github"
    )
    let ready = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [nativeTool],
      installedMcp: registry.list(),
      installedAutomations: [],
      nowMillis: 1_000
    )

    XCTAssertEqual(ready.first { $0.id == "signalasi.mcp.github" }?.installState, .installed)
    XCTAssertTrue(ready.first { $0.id == "signalasi.mcp.github" }?.revocable == true)
    XCTAssertFalse(ready.first { $0.id == "signalasi.mcp.github" }?.permissionDiff.requiresApproval ?? true)
    XCTAssertEqual(ready.first { $0.id == "signalasi.catalog.github-triage" }?.installState, .available)
  }

  func testAgentCapabilityCatalogReportsAutomationRollbackAndPermissionChanges() {
    let entry = AgentDefaultCapabilityCatalog.skill("signalasi.catalog.device-health")!
    var previousManifest = entry.manifest
    previousManifest.version = "0.9.0"
    previousManifest.permissions = []
    previousManifest.nativeTools.remove("signalasi.hardware.network.status")
    let previous = AgentSkillInstallation(manifest: previousManifest, enabled: false)
    let current = AgentSkillInstallation(manifest: entry.manifest, enabled: true)

    let item = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: [],
      installedMcp: [],
      installedAutomations: [previous, current],
      nowMillis: 1_000
    ).first { $0.id == entry.id }

    XCTAssertEqual(item?.installedVersion, "1.0.0")
    XCTAssertEqual(item?.rollbackVersions, ["0.9.0"])
    XCTAssertTrue(item?.revocable == true)
    XCTAssertFalse(item?.permissionDiff.requiresApproval ?? true)
  }

  func testAgentMcpRegistryDynamicAuthenticationAdvancesStepsAndExpires() throws {
    var now: Int64 = 1_000
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { now })
    let profile = try AgentMcpAuthProfile(
      .dynamic,
      accessTokenTtlMillis: 10_000,
      refreshLeadMillis: 2_000,
      supportsRefresh: true
    )
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/mcp",
      authProfile: profile,
      id: "relay-1"
    )

    XCTAssertEqual(connection.authState, .notConfigured)
    XCTAssertEqual(try registry.beginAuthentication(connection.id)?.id, "credentials")
    XCTAssertThrowsError(try registry.submitAuthenticationStep(connection.id, values: ["username": "operator"]))

    let challenge = try registry.submitAuthenticationStep(
      connection.id,
      values: ["username": "operator", "password": "secret"]
    )
    XCTAssertEqual(challenge.authState, .challengeRequired)
    XCTAssertEqual(challenge.currentAuthStep?.id, "verification")

    let authenticated = try registry.submitAuthenticationStep(
      connection.id,
      values: ["otp": "123456", "access_token": "session-token"]
    )
    XCTAssertEqual(authenticated.authState, .authenticated)
    let headers = try registry.requestHeaders(connection.id)
    XCTAssertEqual(headers["Authorization"], "Bearer session-token")
    XCTAssertTrue(authenticated.isCallable(nowMillis: now))

    now = authenticated.refreshAtMillis
    XCTAssertEqual(registry.get(connection.id)?.effectiveAuthState(nowMillis: now), .refreshing)
    XCTAssertTrue(registry.get(connection.id)?.isCallable(nowMillis: now) == true)

    now = authenticated.expiresAtMillis
    XCTAssertEqual(registry.get(connection.id)?.effectiveAuthState(nowMillis: now), .reauthenticationRequired)
    XCTAssertFalse(registry.get(connection.id)?.isCallable(nowMillis: now) ?? true)
  }

  func testAgentMcpConnectionCodecPreservesDynamicExchangeWithoutSecrets() throws {
    let exchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "/api/login",
      bodyTemplate: #"{"username":{{field.username}}}"#,
      responseMappings: ["access_token": "$.token"],
      acceptedStatusCodes: [200, 201]
    )
    let step = try AgentMcpAuthStepSpec(
      id: "login",
      title: "Sign in",
      fields: [try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text)],
      exchange: exchange
    )
    let connection = AgentMcpConnection(
      id: "codec-1",
      displayName: "Codec",
      endpoint: "https://codec.example/mcp",
      distribution: .localPackage,
      transport: .declarativeHTTP,
      authProfile: try AgentMcpAuthProfile(.dynamic, steps: [step]),
      authState: .challengeRequired,
      permissionMode: .readOnly
    )

    let encoded = AgentMcpConnectionCodec.encode([connection])
    let decoded = AgentMcpConnectionCodec.decode(encoded).first

    XCTAssertEqual(decoded?.id, connection.id)
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.pathTemplate, "/api/login")
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.responseMappings["access_token"], "$.token")
    XCTAssertEqual(decoded?.currentAuthStep?.exchange?.acceptedStatusCodes, Set([200, 201]))
    XCTAssertEqual(decoded?.permissionMode, .readOnly)
    XCTAssertFalse(encoded.contains("session-token"))
  }

  func testAgentMcpAuthenticationCoordinatorSubmitsExchangeAndMapsToken() async throws {
    let root = try temporaryDirectory("mcp-auth-exchange-submit")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 201, body: #"{"session":{"access_token":"mapped-token"}}"#)
    ])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { 10_000 }
    )

    let authenticated = try await coordinator.submitStep(
      connectionId: installed.id,
      values: ["username": "alice", "password": "pw"]
    )
    let request = try XCTUnwrap(transport.requests.first)
    let headers = try registry.requestHeaders(installed.id)

    XCTAssertEqual(authenticated.authState, .authenticated)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.url, "https://relay.example/api/login")
    XCTAssertEqual(request.headers["Accept"], "application/json")
    XCTAssertEqual(request.body, #"{"username":"alice","password":"pw"}"#)
    XCTAssertEqual(headers["Authorization"], "Bearer mapped-token")
    XCTAssertTrue(authenticated.expiresAtMillis > 10_000)
  }

  func testAgentMcpAuthenticationCoordinatorRejectsEscapedExchangeAndMarksReauth() async throws {
    let exchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "//evil.example/login",
      bodyTemplate: #"{"username":{{field.username}}}"#,
      responseMappings: ["access_token": "$.token"]
    )
    let step = try AgentMcpAuthStepSpec(
      id: "login",
      title: "Sign in",
      fields: [try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text)],
      exchange: exchange
    )
    let profile = try AgentMcpAuthProfile(.dynamic, steps: [step])
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/api/",
      authProfile: profile,
      id: "relay-escaped-auth"
    )
    _ = try registry.beginAuthentication(connection.id)
    let transport = FakeMcpDeclarativeHTTPTransport([])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await coordinator.submitStep(connectionId: connection.id, values: ["username": "alice"])
      XCTFail("Expected escaped MCP authentication exchange to be rejected")
    } catch {
      let stored = try XCTUnwrap(registry.get(connection.id))
      XCTAssertEqual(transport.requests.count, 0)
      XCTAssertEqual(stored.state, .needsSetup)
      XCTAssertEqual(stored.authState, .reauthenticationRequired)
      XCTAssertTrue(stored.lastError.contains("configured server"))
    }
  }

  func testAgentMcpAuthenticationCoordinatorRefreshesWhenTokenNearExpiry() async throws {
    var now: Int64 = 10_000
    let refreshExchange = try AgentMcpAuthExchangeSpec(
      method: "POST",
      pathTemplate: "/oauth/refresh",
      headerTemplates: ["Authorization": "Bearer {{auth.access_token}}"],
      bodyTemplate: #"{"refresh":{{auth.refresh_token}}}"#,
      responseMappings: ["access_token": "$.access_token"]
    )
    let profile = try AgentMcpAuthProfile(
      .bearerToken,
      accessTokenTtlMillis: 10_000,
      refreshLeadMillis: 2_000,
      supportsRefresh: true,
      refreshExchange: refreshExchange
    )
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { now })
    let connection = try registry.addRemote(
      displayName: "Relay",
      endpoint: "https://relay.example/api/",
      authProfile: profile,
      id: "relay-refresh"
    )
    _ = try registry.beginAuthentication(connection.id)
    let authenticated = try registry.submitAuthenticationStep(
      connection.id,
      values: ["access_token": "old-token", "refresh_token": "refresh-1"]
    )
    now = authenticated.refreshAtMillis
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 200, body: #"{"access_token":"fresh-token"}"#)
    ])
    let coordinator = AgentMcpAuthenticationCoordinator(
      registry: registry,
      transport: transport,
      nowMillis: { now }
    )

    let refreshed = try await coordinator.refreshIfNeeded(connectionId: connection.id)
    let request = try XCTUnwrap(transport.requests.first)
    let headers = try registry.requestHeaders(connection.id)

    XCTAssertEqual(request.url, "https://relay.example/oauth/refresh")
    XCTAssertEqual(request.headers["Authorization"], "Bearer old-token")
    XCTAssertEqual(request.body, #"{"refresh":"refresh-1"}"#)
    XCTAssertEqual(refreshed.authState, .authenticated)
    XCTAssertEqual(headers["Authorization"], "Bearer fresh-token")
    XCTAssertTrue(refreshed.expiresAtMillis > now)
  }

  func testAgentMcpStreamableHTTPTransportSendsHeadersAndReceivesJson() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: [
          "Mcp-Session-Id": " session-1 ",
          "Content-Type": "application/json"
        ],
        body: #"{"jsonrpc":"2.0","id":1,"result":{}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(
      endpoint: "https://mcp.example/rpc",
      requestHeaders: [
        "Authorization": "Bearer token",
        "Content-Length": "999",
        "Bad\nName": "drop",
        "X-Unsafe": "line\nbreak"
      ],
      networking: networking
    )

    try transport.open()
    transport.onProtocolVersionNegotiated("2025-06-18")
    try await transport.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
    try await transport.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

    XCTAssertEqual(networking.requests.count, 2)
    XCTAssertEqual(networking.requests[0].endpoint, "https://mcp.example/rpc")
    XCTAssertEqual(networking.requests[0].headers["Accept"], "application/json, text/event-stream")
    XCTAssertEqual(networking.requests[0].headers["Content-Type"], "application/json")
    XCTAssertEqual(networking.requests[0].headers["User-Agent"], "SignalASI-iOS-MCP/1")
    XCTAssertEqual(networking.requests[0].headers["Authorization"], "Bearer token")
    XCTAssertEqual(networking.requests[0].headers["MCP-Protocol-Version"], "2025-06-18")
    XCTAssertNil(networking.requests[0].headers["Content-Length"])
    XCTAssertNil(networking.requests[0].headers["Bad\nName"])
    XCTAssertNil(networking.requests[0].headers["X-Unsafe"])
    XCTAssertEqual(networking.requests[0].body, #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","id":1,"result":{}}"#)
    XCTAssertNil(transport.receive())
    XCTAssertEqual(transport.currentSessionId, "session-1")
    XCTAssertEqual(networking.requests[1].headers["Mcp-Session-Id"], "session-1")
  }

  func testAgentMcpStreamableHTTPTransportParsesSseDataEvents() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "text/event-stream; charset=utf-8"],
        body: """
        : keepalive
        data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}

        data: {"jsonrpc":"2.0","method":"tools/list_changed"}

        """
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)

    try transport.open()
    try await transport.send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#)
    XCTAssertEqual(transport.receive(), #"{"jsonrpc":"2.0","method":"tools/list_changed"}"#)
    XCTAssertNil(transport.receive())
  }

  func testAgentMcpStreamableHTTPTransportRejectsClosedStateAndHttpFailure() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(statusCode: 401, headers: [:], body: "expired")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)

    do {
      try await transport.send("{}")
      XCTFail("Expected unopened MCP streamable transport to reject sends")
    } catch {
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("MCP transport is not open"))
    }

    try transport.open()
    do {
      try await transport.send("{}")
      XCTFail("Expected HTTP failure from MCP streamable transport")
    } catch {
      let http = try XCTUnwrap(error as? AgentMcpStreamableHTTPError)
      XCTAssertEqual(http.statusCode, 401)
      XCTAssertEqual(http.authenticationFailure, true)
      XCTAssertTrue(http.message.contains("expired"))
    }

    transport.close()
    XCTAssertNil(transport.receive())
  }

  func testAgentMcpRemoteSessionInitializesListsAndCallsTools() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}},"instructions":"ready"}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"relay.switch","title":"Switch relay","description":"Turns relay on","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}],"nextCursor":"next-page"}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"done"}],"structuredContent":{"state":"on"},"isError":false}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)

    let initialized = try await session.initialize(
      clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1")
    )
    let tools = try await session.listTools()
    let call = try await session.callTool(name: "relay.switch", arguments: ["enabled": .bool(true)])

    XCTAssertEqual(session.state, .active)
    XCTAssertEqual(initialized.protocolVersion, "2025-06-18")
    XCTAssertEqual(initialized.serverInfo.name, "relay-mcp")
    XCTAssertTrue(initialized.capabilities.tools)
    XCTAssertEqual(tools.items.map(\.name), ["relay.switch"])
    XCTAssertEqual(tools.nextCursor, "next-page")
    XCTAssertEqual(tools.items.first?.inputSchema["type"], .string("object"))
    XCTAssertEqual(tools.items.first?.annotations?["readOnlyHint"], .bool(false))
    XCTAssertEqual(call.content.first?.text, "done")
    XCTAssertEqual(call.structuredContent?["state"], .string("on"))
    XCTAssertEqual(networking.requests.count, 4)
    XCTAssertTrue(networking.requests[0].body.contains(#""method":"initialize""#))
    XCTAssertTrue(networking.requests[1].body.contains(#""method":"notifications/initialized""#))
    XCTAssertTrue(networking.requests[2].body.contains(#""method":"tools/list""#))
    XCTAssertTrue(networking.requests[3].body.contains(#""method":"tools/call""#))
  }

  func testAgentMcpRemoteSessionReceivesNotificationsAndRespondsToPing() async throws {
    let listener = TestMcpRemoteSessionListener()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "text/event-stream"],
        body: """
        data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"step":"connecting"}}

        data: {"jsonrpc":"2.0","id":"server-ping","method":"ping"}

        data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}

        """
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport, listener: listener)

    let initialized = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1"))

    XCTAssertTrue(initialized.capabilities.tools)
    XCTAssertEqual(listener.notifications.map(\.method), ["notifications/progress"])
    XCTAssertEqual(listener.notifications.first?.params?["step"], .string("connecting"))
    XCTAssertTrue(listener.issues.isEmpty)
    XCTAssertEqual(networking.requests.count, 3)
    XCTAssertTrue(networking.requests[1].body.contains(#""id":"server-ping""#))
    XCTAssertTrue(networking.requests[1].body.contains(#""result":{}"#))
    XCTAssertTrue(networking.requests[2].body.contains(#""method":"notifications/initialized""#))
  }

  func testAgentMcpRemoteSessionReturnsMethodNotFoundForUnknownServerRequest() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "text/event-stream"],
        body: """
        data: {"jsonrpc":"2.0","id":7,"method":"sampling/createMessage"}

        data: {"jsonrpc":"2.0","id":2,"result":{"tools":[]}}

        """
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1"))

    let tools = try await session.listTools()

    XCTAssertTrue(tools.items.isEmpty)
    XCTAssertEqual(networking.requests.count, 4)
    XCTAssertTrue(networking.requests[3].body.contains(#""id":7"#))
    XCTAssertTrue(networking.requests[3].body.contains(#""code":-32601"#))
    XCTAssertTrue(networking.requests[3].body.contains("Method not found: sampling/createMessage"))
  }

  func testAgentMcpRemoteSessionListsReadsResourcesAndPrompts() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"resources":{},"prompts":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"resources":[{"uri":"file:///README.md","name":"README.md","title":"Project readme","mimeType":"text/markdown","size":42,"annotations":{"priority":0.8}}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"contents":[{"uri":"file:///README.md","mimeType":"text/markdown","text":"# SignalASI"}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":4,"result":{"prompts":[{"name":"review","title":"Review","arguments":[{"name":"focus","description":"Review focus","required":true}]}],"nextCursor":"prompt-page-2"}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":5,"result":{"description":"Focused review","messages":[{"role":"user","content":{"type":"text","text":"Review cancellation behavior"}},{"role":"assistant","content":{"type":"resource","resource":{"uri":"file:///README.md","mimeType":"text/markdown","text":"# SignalASI"}}}]}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1"))

    let resources = try await session.listResources()
    let resource = try await session.readResource(uri: "file:///README.md")
    let prompts = try await session.listPrompts(cursor: "prompt-page-1")
    let prompt = try await session.getPrompt(name: "review", arguments: ["focus": "cancellation"])

    XCTAssertEqual(resources.items.first?.name, "README.md")
    XCTAssertEqual(resources.items.first?.size, 42)
    XCTAssertEqual(resources.items.first?.annotations?["priority"], .double(0.8))
    XCTAssertEqual(resource.contents.first?.text, "# SignalASI")
    XCTAssertNil(resource.contents.first?.blob)
    XCTAssertEqual(prompts.nextCursor, "prompt-page-2")
    XCTAssertEqual(prompts.items.first?.arguments.first?.required, true)
    XCTAssertEqual(prompt.description, "Focused review")
    XCTAssertEqual(prompt.messages.first?.role, "user")
    XCTAssertEqual(prompt.messages.first?.content.text, "Review cancellation behavior")
    XCTAssertEqual(prompt.messages.last?.content.resource?.uri, "file:///README.md")
    XCTAssertEqual(prompt.messages.last?.content.resource?.text, "# SignalASI")
    XCTAssertEqual(networking.requests.count, 6)
    XCTAssertTrue(networking.requests[4].body.contains(#""method":"prompts/list""#))
    XCTAssertTrue(networking.requests[4].body.contains(#""cursor":"prompt-page-1""#))
    XCTAssertTrue(networking.requests[5].body.contains(#""method":"prompts/get""#))
    XCTAssertTrue(networking.requests[5].body.contains(#""focus":"cancellation""#))
  }

  func testAgentMcpRemoteSessionMapsJsonRpcError() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"tools unavailable","data":{"reason":"disabled"}}}"#
      )
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1"))

    do {
      _ = try await session.listTools()
      XCTFail("Expected JSON-RPC error from MCP tools/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .remote)
      XCTAssertEqual(sessionError.requestId, 2)
      XCTAssertEqual(sessionError.method, "tools/list")
      XCTAssertEqual(sessionError.rpcCode, -32601)
      XCTAssertEqual(sessionError.data?.objectValue?["reason"], .string("disabled"))
      XCTAssertEqual(sessionError.message, "tools unavailable")
    }
  }

  func testAgentMcpRemoteSessionRequiresNegotiatedToolsCapability() async throws {
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: "")
    ])
    let transport = try AgentMcpStreamableHTTPTransport(endpoint: "https://mcp.example/rpc", networking: networking)
    let session = AgentMcpRemoteSession(transport: transport)
    _ = try await session.initialize(clientInfo: AgentMcpImplementationInfo(name: "SignalASI iOS", version: "1"))

    do {
      _ = try await session.listTools()
      XCTFail("Expected missing tools capability to reject tools/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .capabilityNotNegotiated)
      XCTAssertEqual(sessionError.method, "tools/list")
      XCTAssertEqual(networking.requests.count, 2)
    }

    do {
      _ = try await session.listResources()
      XCTFail("Expected missing resources capability to reject resources/list")
    } catch {
      let sessionError = try XCTUnwrap(error as? AgentMcpRemoteSessionError)
      XCTAssertEqual(sessionError.kind, .capabilityNotNegotiated)
      XCTAssertEqual(sessionError.method, "resources/list")
      XCTAssertEqual(networking.requests.count, 2)
    }
  }

  func testAgentMcpClientManagerListsCallsRemoteAndAudits() async throws {
    let root = try temporaryDirectory("mcp-client-manager-remote")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      id: "relay-remote"
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"update_document","title":"Update document","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}]}}"#
      ),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"updated"}],"structuredContent":{"ok":true}}}"#
      )
    ])
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      remoteSessionFactory: { connection, headers in
        XCTAssertEqual(connection.id, "relay-remote")
        XCTAssertTrue(headers.isEmpty)
        let transport = try AgentMcpStreamableHTTPTransport(
          endpoint: connection.endpoint,
          requestHeaders: headers,
          networking: networking
        )
        return AgentMcpRemoteSession(transport: transport)
      },
      nowMillis: { 10_000 }
    )

    let tools = try await manager.listTools(connectionId: connection.id)
    let result = await manager.callTool(
      connectionId: connection.id,
      toolName: "update_document",
      arguments: ["content": .string("new")],
      context: AgentNativeToolInvocationContext(attributes: ["explicit_user_approval": "true", "task_id": "task-1"])
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: connection.id, limit: 10).first)

    XCTAssertEqual(tools.map(\.name), ["update_document"])
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.message, "updated")
    XCTAssertEqual(result.output["structured_content"]?.objectValue?["ok"], .bool(true))
    XCTAssertEqual(result.metadata["mcp_permission_decision"], .string("allowed_explicit_change"))
    XCTAssertNotNil(result.metadata["mcp_security"]?.objectValue)
    XCTAssertEqual(result.metadata["mcp_audit_id"], .string(audit.auditId))
    XCTAssertEqual(audit.status, "succeeded")
    XCTAssertEqual(audit.taskId, "task-1")
    XCTAssertEqual(audit.permissionDecision, "allowed_explicit_change")
    XCTAssertEqual(registry.get(connection.id)?.state, .connected)
    XCTAssertEqual(networking.requests.count, 4)
  }

  func testAgentMcpClientManagerDeniesUnapprovedMutatingCallAndAudits() async throws {
    let root = try temporaryDirectory("mcp-client-manager-denied")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.addRemote(
      displayName: "Relay MCP",
      endpoint: "https://mcp.example/rpc",
      authProfile: try AgentMcpAuthProfile(.none),
      id: "relay-denied"
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let networking = FakeMcpStreamableHTTPNetworking([
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"relay-mcp","version":"1.0.0"},"capabilities":{"tools":{}}}}"#
      ),
      AgentMcpStreamableHTTPResponse(statusCode: 200, headers: [:], body: ""),
      AgentMcpStreamableHTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"update_document","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":false}}]}}"#
      )
    ])
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      remoteSessionFactory: { connection, headers in
        let transport = try AgentMcpStreamableHTTPTransport(
          endpoint: connection.endpoint,
          requestHeaders: headers,
          networking: networking
        )
        return AgentMcpRemoteSession(transport: transport)
      },
      nowMillis: { 10_000 }
    )

    let result = await manager.callTool(
      connectionId: connection.id,
      toolName: "update_document",
      arguments: ["content": .string("new")]
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: connection.id, limit: 10).first)

    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "mcp_approval_required")
    XCTAssertEqual(result.error?.details["required_user_action"], .string("approve_tool_call"))
    XCTAssertEqual(result.metadata["mcp_permission_decision"], .string("mcp_approval_required"))
    XCTAssertEqual(audit.status, "denied")
    XCTAssertEqual(audit.errorCode, "mcp_approval_required")
    XCTAssertEqual(networking.requests.count, 3)
  }

  func testAgentMcpClientManagerReturnsAuthenticationFailureForDeclarativeHttp() async throws {
    let root = try temporaryDirectory("mcp-client-manager-declarative-auth")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: ["username": "alice", "password": "pw", "access_token": "expired-token"]
    )
    let auditStore = InMemoryAgentMcpAuditStore()
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 401, body: #"{"error":"expired"}"#)
    ])
    let declarative = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )
    let manager = AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore,
      declarativeHTTPClient: declarative,
      nowMillis: { 10_000 }
    )

    let result = await manager.callTool(
      connectionId: authenticated.id,
      toolName: "relay.switch",
      arguments: ["device_id": .string("relay-1"), "enabled": .bool(true)],
      context: AgentNativeToolInvocationContext(attributes: ["explicit_user_approval": "true"])
    )
    let audit = try XCTUnwrap(manager.audit(connectionId: authenticated.id, limit: 10).first)

    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "mcp_authentication_required")
    XCTAssertEqual(audit.status, "failed")
    XCTAssertEqual(audit.errorCode, "mcp_authentication_required")
    XCTAssertEqual(registry.get(authenticated.id)?.state, .needsSetup)
    XCTAssertEqual(registry.get(authenticated.id)?.authState, .reauthenticationRequired)
  }

  func testAgentMcpLocalRuntimeResponseCodecDecodesLastStructuredBridgeResult() throws {
    let result = try AgentMcpLocalRuntimeResponseCodec.decode(
      """
      __SIGNALASI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"stale.tool"}]}}
      server starting
      {"unrelated":true}
      __SIGNALASI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"device.read"}]}}
      """
    )
    guard case .array(let tools)? = result["tools"],
          case .object(let firstTool)? = tools.first else {
      XCTFail("Expected decoded tool list")
      return
    }

    XCTAssertEqual(firstTool["name"], .string("device.read"))
  }

  func testAgentMcpLocalRuntimeResponseCodecSurfacesBridgeFailure() {
    XCTAssertThrowsError(
      try AgentMcpLocalRuntimeResponseCodec.decode(
        #"__SIGNALASI_MCP_RESULT__{"ok":false,"error":"server authentication failed"}"#
      )
    ) { error in
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("server authentication failed"))
    }
  }

  func testAgentMcpLocalRuntimeResponseCodecRejectsUnstructuredOutput() {
    XCTAssertThrowsError(try AgentMcpLocalRuntimeResponseCodec.decode("plain process output")) { error in
      XCTAssertEqual(error as? AgentRuntimeCapabilityError, .invalid("Local MCP bridge returned no structured result"))
    }
  }

  func testAgentMcpPackageManifestCodecDecodesDeclarativeHttpAndDynamicAuthExchange() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpDeclarativePackageManifest())
    let exchange = manifest.authProfiles.first?.steps.first?.exchange
    let tool = try XCTUnwrap(manifest.tools.first)

    XCTAssertEqual(manifest.id, "example.relay")
    XCTAssertEqual(manifest.endpoint, "https://relay.example/api/")
    XCTAssertEqual(manifest.transport, .declarativeHTTP)
    XCTAssertEqual(manifest.authProfiles.first?.method, .dynamic)
    XCTAssertEqual(exchange?.pathTemplate, "/api/login")
    XCTAssertEqual(exchange?.responseMappings["access_token"], "$.session.access_token")
    XCTAssertEqual(exchange?.acceptedStatusCodes, Set([200, 201]))
    XCTAssertEqual(tool.name, "relay.switch")
    XCTAssertEqual(tool.method, "POST")
    XCTAssertEqual(tool.pathTemplate, "/api/relay/{{args.device_id}}")
    XCTAssertEqual(tool.inputSchema["type"], .string("object"))
    XCTAssertTrue(tool.mutating)
    XCTAssertTrue(try AgentMcpPackageManifestCodec.encode(manifest).contains(#""declarative_http""#))
  }

  func testAgentMcpPackageManifestCodecAcceptsSandboxedLocalStdioRuntime() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpLocalStdioPackageManifest())
    let runtime = try XCTUnwrap(manifest.localRuntime)

    XCTAssertEqual(manifest.transport, .localStdio)
    XCTAssertEqual(manifest.endpoint, "local-mcp:example.local_mcp")
    XCTAssertEqual(runtime.language, .python)
    XCTAssertEqual(runtime.entrypoint, "runtime/server.py")
    XCTAssertEqual(runtime.arguments, ["--stdio"])
    XCTAssertEqual(runtime.environment["ACCESS_TOKEN"], "{{auth.access_token}}")
    XCTAssertTrue(runtime.allowedNetworkDomains.isEmpty)
    XCTAssertEqual(runtime.timeoutMillis, 45_000)
    let encoded = try AgentMcpPackageManifestCodec.encode(manifest)
    XCTAssertTrue(encoded.contains(#""local_stdio""#))
    XCTAssertTrue(encoded.contains(#""timeout_ms":45000"#))
  }

  func testAgentMcpPackageManifestCodecRejectsUnsafeLocalRuntimeAndHttpAuthExchange() {
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(entrypoint: "../server.py")
    ))
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(authentication: """
      [{"method":"username_password","steps":[{"id":"login","title":"Sign in","fields":[],"exchange":{"method":"POST","path":"/login"}}]}]
      """)
    ))
    XCTAssertThrowsError(try AgentMcpPackageManifestCodec.decode(
      mcpLocalStdioPackageManifest(allowedNetworkDomains: #""example.com""#)
    ))
  }

  func testAgentMcpPackageInstallerInspectsIntegrityAndRuntimeFiles() throws {
    let manifest = mcpLocalStdioPackageManifest()
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("integrity.json", mcpPackageIntegrity(for: manifest)),
      ("runtime/server.py", runtime),
      ("README.md", "# Local MCP")
    ))

    XCTAssertTrue(inspection.integrityVerified)
    XCTAssertEqual(inspection.manifest.transport, .localStdio)
    XCTAssertEqual(inspection.manifest.endpoint, "local-mcp:example.local_mcp")
    XCTAssertEqual(inspection.manifestSha256, AgentMcpPackageInstaller.sha256(Data(manifest.utf8)))
    XCTAssertEqual(inspection.packageSha256.count, 64)
    XCTAssertEqual(inspection.archiveEntries, ["README.md", "integrity.json", "mcp.json", "runtime/server.py"])
    XCTAssertEqual(inspection.runtimeFiles["runtime/server.py"], Data(runtime.utf8))
  }

  func testAgentMcpPackageInstallerAcceptsDeflatedZipEntries() throws {
    let manifest = mcpLocalStdioPackageManifest()
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(deflatedZipArchive(
      ("mcp.json", manifest),
      ("integrity.json", mcpPackageIntegrity(for: manifest)),
      ("runtime/server.py", runtime)
    ))

    XCTAssertTrue(inspection.integrityVerified)
    XCTAssertEqual(inspection.archiveEntries, ["integrity.json", "mcp.json", "runtime/server.py"])
    XCTAssertEqual(inspection.runtimeFiles["runtime/server.py"], Data(runtime.utf8))
  }

  func testAgentMcpPackageInstallerAcceptsUnsignedPackageButReportsItForReview() throws {
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))

    XCTAssertFalse(inspection.integrityVerified)
    XCTAssertEqual(inspection.manifest.transport, .declarativeHTTP)
    XCTAssertEqual(inspection.manifest.tools.first?.name, "relay.switch")
    XCTAssertTrue(inspection.runtimeFiles.isEmpty)
  }

  func testAgentMcpPackageInstallerRejectsTraversalUnsupportedAndTamperedPackages() {
    let manifest = mcpDeclarativePackageManifest()
    let installer = AgentMcpPackageInstaller()

    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(("../mcp.json", manifest))))
    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("server.js", "run()")
    )))
    XCTAssertThrowsError(try installer.inspect(storedMcpPackage(
      ("mcp.json", manifest),
      ("integrity.json", #"{"manifest_sha256":"0000000000000000000000000000000000000000000000000000000000000000"}"#)
    )))
  }

  func testAgentMcpPackageInstallerRejectsLocalStdioPackageMissingEntrypoint() {
    XCTAssertThrowsError(try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest())
    )))
  }

  func testAgentMcpRegistryInstallsPackageConnection() throws {
    let manifest = try AgentMcpPackageManifestCodec.decode(mcpDeclarativePackageManifest())
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 9_000 })

    let connection = try registry.installPackage(manifest, packageSha256: String(repeating: "a", count: 64))

    XCTAssertEqual(connection.id, "example.relay")
    XCTAssertEqual(connection.catalogId, "signalasi.mcp.relay")
    XCTAssertEqual(connection.displayName, "Relay Controller")
    XCTAssertEqual(connection.endpoint, "https://relay.example/api/")
    XCTAssertEqual(connection.distribution, .localPackage)
    XCTAssertEqual(connection.transport, .declarativeHTTP)
    XCTAssertEqual(connection.authProfile.method, .dynamic)
    XCTAssertEqual(connection.authState, .notConfigured)
    XCTAssertEqual(connection.state, .needsSetup)
    XCTAssertEqual(connection.toolIds, ["relay.switch"])
    XCTAssertEqual(connection.packageVersion, "1.0.0")
    XCTAssertEqual(connection.packageSha256, String(repeating: "a", count: 64))
    XCTAssertEqual(connection.installedAtMillis, 9_000)
    XCTAssertEqual(registry.get("example.relay"), connection)
  }

  func testAgentMcpPackageRepositorySavesAndPreparesLocalInvocation() throws {
    let root = try temporaryDirectory("mcp-package-repository")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let runtime = "print('server')"
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest()),
      ("runtime/server.py", runtime)
    ))

    try repository.save(inspection)
    let saved = try XCTUnwrap(repository.get("example.local_mcp"))
    let invocation = try repository.prepareLocalInvocation(
      id: "example.local_mcp",
      payload: #"{"operation":"list_tools"}"#
    )

    let workspace = root
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
      .appendingPathComponent(invocation.workspaceId, isDirectory: true)
    let runtimeFile = workspace.appendingPathComponent("runtime/server.py", isDirectory: false)
    let requestFile = relativeFile(invocation.requestPath, under: workspace)

    XCTAssertEqual(saved.id, "example.local_mcp")
    XCTAssertTrue(invocation.workspaceId.hasPrefix("mcp-"))
    XCTAssertTrue(invocation.requestPath.hasPrefix(".signalasi-mcp/request-"))
    XCTAssertEqual(try String(contentsOf: runtimeFile, encoding: .utf8), runtime)
    XCTAssertEqual(try String(contentsOf: requestFile, encoding: .utf8), #"{"operation":"list_tools"}"#)

    repository.completeLocalInvocation(invocation)
    XCTAssertFalse(FileManager.default.fileExists(atPath: requestFile.path))
    repository.delete("example.local_mcp")
    XCTAssertNil(repository.get("example.local_mcp"))
  }

  func testAgentMcpLocalRuntimeClientListsToolsAndRendersSecretEnvironment() throws {
    let root = try temporaryDirectory("mcp-local-runtime-list")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest()),
      ("runtime/server.py", "print('server')")
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(installed.id, values: ["access_token": "secret-token"])
    let executor = FakeMcpLocalRuntimeExecutor([
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: """
        bridge booted
        __SIGNALASI_MCP_RESULT__{"ok":true,"result":{"tools":[{"name":"device.read","title":"Read device","description":"Reads state","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}]}}
        """,
        stderr: "",
        exitCode: 0
      )
    ])
    let client = AgentMcpLocalRuntimeClient(
      registry: registry,
      packageRepository: repository,
      executor: executor,
      nowMillis: { 10_000 }
    )

    let tools = try client.listTools(connection: authenticated)
    let request = try XCTUnwrap(executor.requests.first)
    let workspace = root
      .appendingPathComponent("agent-native-workspaces", isDirectory: true)
      .appendingPathComponent(request.workspaceId, isDirectory: true)
    let requestFile = relativeFile(try XCTUnwrap(request.arguments.first), under: workspace)

    XCTAssertEqual(tools.map(\.name), ["device.read"])
    XCTAssertEqual(tools.first?.title, "Read device")
    XCTAssertEqual(tools.first?.inputSchema["type"], .string("object"))
    XCTAssertEqual(tools.first?.annotations?["readOnlyHint"], .bool(true))
    XCTAssertEqual(request.language, .python)
    XCTAssertTrue(request.source.contains("SIGNALASI_MCP_SANDBOX"))
    XCTAssertTrue(request.arguments.first?.hasPrefix(".signalasi-mcp/request-") == true)
    XCTAssertEqual(request.secretEnvironment["ACCESS_TOKEN"], "secret-token")
    XCTAssertFalse(FileManager.default.fileExists(atPath: requestFile.path))
  }

  func testAgentMcpLocalRuntimeClientCallsToolAndMapsServerErrorResult() throws {
    let root = try temporaryDirectory("mcp-local-runtime-call")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpLocalStdioPackageManifest(authentication: #"[{"method":"none"}]"#)),
      ("runtime/server.py", "print('server')")
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let connection = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    let executor = FakeMcpLocalRuntimeExecutor([
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: #"__SIGNALASI_MCP_RESULT__{"ok":true,"result":{"content":[{"type":"text","text":"done"}],"structuredContent":{"ok":true}}}"#,
        stderr: "",
        exitCode: 0
      ),
      AgentMcpLocalRuntimeExecutionResponse(
        stdout: #"__SIGNALASI_MCP_RESULT__{"ok":true,"result":{"isError":true,"content":[{"type":"text","text":"denied"}]}}"#,
        stderr: "",
        exitCode: 0
      )
    ])
    let client = AgentMcpLocalRuntimeClient(
      registry: registry,
      packageRepository: repository,
      executor: executor,
      nowMillis: { 10_000 }
    )

    let success = try client.callTool(connection: connection, toolName: "device.read", arguments: ["enabled": .bool(true)])
    let failure = try client.callTool(connection: connection, toolName: "device.write", arguments: [:])

    XCTAssertTrue(success.isSuccess)
    XCTAssertEqual(success.message, "done")
    XCTAssertEqual(success.output["structured_content"]?.objectValue?["ok"], .bool(true))
    XCTAssertEqual(success.metadata["transport"], .string("local_stdio"))
    XCTAssertFalse(failure.isSuccess)
    XCTAssertEqual(failure.error?.code, "mcp_tool_error")
    XCTAssertEqual(failure.message, "denied")
    XCTAssertEqual(executor.requests.map(\.requestId).count, 2)
    XCTAssertEqual(executor.requests[0].workspaceId, executor.requests[1].workspaceId)
  }

  func testAgentMcpDeclarativeHTTPClientListsAndCallsPackageTool() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-call")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 200, body: #"{"relay":{"state":"on"}}"#)
    ])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    let tools = try client.listTools(connection: authenticated)
    let result = try await client.callTool(
      connection: authenticated,
      toolName: "relay.switch",
      arguments: [
        "device_id": .string("relay 1"),
        "enabled": .bool(true)
      ]
    )
    let request = try XCTUnwrap(transport.requests.first)
    let stored = try XCTUnwrap(registry.get(installed.id))

    XCTAssertEqual(tools.map(\.name), ["relay.switch"])
    XCTAssertEqual(tools.first?.annotations?["readOnlyHint"], .bool(false))
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.url, "https://relay.example/api/relay/relay%201")
    XCTAssertEqual(request.headers["Accept"], "application/json, text/plain")
    XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
    XCTAssertEqual(request.body, #"{"enabled":true}"#)
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["result"]?.objectValue?["state"], .string("on"))
    XCTAssertEqual(result.output["http_status"], .int(200))
    XCTAssertEqual(result.metadata["transport"], .string("declarative_http"))
    XCTAssertEqual(stored.state, .connected)
    XCTAssertEqual(stored.toolIds, ["relay.switch"])
  }

  func testAgentMcpDeclarativeHTTPClientRejectsEscapedTargetAndMarksFailure() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-escaped")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let manifest = mcpDeclarativePackageManifest().replacingOccurrences(
      of: #""path": "/api/relay/{{args.device_id}}""#,
      with: #""path": "//evil.example/{{args.device_id}}""#
    )
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", manifest)
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await client.callTool(
        connection: authenticated,
        toolName: "relay.switch",
        arguments: ["device_id": .string("relay-1")]
      )
      XCTFail("Expected escaped declarative MCP target to be rejected")
    } catch {
      let stored = try XCTUnwrap(registry.get(installed.id))
      XCTAssertEqual(transport.requests.count, 0)
      XCTAssertEqual(stored.state, .error)
      XCTAssertTrue(stored.lastError.contains("configured server"))
    }
  }

  func testAgentMcpDeclarativeHTTPClientMarksAuthenticationFailureOnHttp401() async throws {
    let root = try temporaryDirectory("mcp-declarative-http-401")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = AgentMcpPackageRepository(rootDirectory: root)
    let inspection = try AgentMcpPackageInstaller().inspect(storedMcpPackage(
      ("mcp.json", mcpDeclarativePackageManifest())
    ))
    try repository.save(inspection)
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 10_000 })
    let installed = try registry.installPackage(inspection.manifest, packageSha256: inspection.packageSha256)
    _ = try registry.beginAuthentication(installed.id)
    let authenticated = try registry.submitAuthenticationStep(
      installed.id,
      values: [
        "username": "alice",
        "password": "pw",
        "access_token": "secret-token"
      ]
    )
    let transport = FakeMcpDeclarativeHTTPTransport([
      AgentMcpDeclarativeHTTPResponse(statusCode: 401, body: #"{"error":"expired"}"#)
    ])
    let client = AgentMcpDeclarativeHTTPClient(
      registry: registry,
      packageRepository: repository,
      transport: transport,
      nowMillis: { 10_000 }
    )

    do {
      _ = try await client.callTool(
        connection: authenticated,
        toolName: "relay.switch",
        arguments: [
          "device_id": .string("relay-1"),
          "enabled": .bool(true)
        ]
      )
      XCTFail("Expected HTTP 401 to require MCP reauthentication")
    } catch {
      let stored = try XCTUnwrap(registry.get(installed.id))
      XCTAssertEqual(transport.requests.count, 1)
      XCTAssertEqual(stored.state, .needsSetup)
      XCTAssertEqual(stored.authState, .reauthenticationRequired)
      XCTAssertEqual(stored.lastError, "MCP authentication expired")
    }
  }

  func testAgentCapabilityDependencyResolverAndEndpointPolicyMatchAndroid() throws {
    let skill = AgentDefaultCapabilityCatalog.skill("signalasi.catalog.github-triage")!
    let registry = AgentMcpRegistry(InMemoryAgentMcpStore(), nowMillis: { 1_000 })
    let missing = AgentCapabilityDependencyResolver.resolve(
      skill,
      installedMcp: registry.list(),
      nativeToolIds: [AgentMcpNativeTools.callTool],
      nowMillis: 1_000
    )
    XCTAssertFalse(missing.available)
    XCTAssertEqual(missing.missingMcpCatalogIds, ["signalasi.mcp.github"])

    _ = try registry.addRemote(
      displayName: "GitHub",
      endpoint: "https://api.githubcopilot.com/mcp/",
      authProfile: try AgentMcpAuthProfile(.none),
      catalogId: "signalasi.mcp.github",
      id: "github"
    )
    let ready = AgentCapabilityDependencyResolver.resolve(
      skill,
      installedMcp: registry.list(),
      nativeToolIds: [AgentMcpNativeTools.callTool],
      nowMillis: 1_000
    )
    XCTAssertTrue(ready.available)

    XCTAssertEqual(try AgentMcpEndpointPolicy.normalize(" https://example.com/mcp "), "https://example.com/mcp")
    XCTAssertThrowsError(try AgentMcpEndpointPolicy.normalize("https://user:password@example.com/mcp"))
    XCTAssertThrowsError(try AgentMcpEndpointPolicy.normalize("file:///tmp/server"))
  }

  func testGlobalCapabilityObservationExtractorAuthorizationAndSafetyUseLocalOnlyProjection() {
    let authorizationEvents = GlobalCapabilityObservationExtractor.authorizationMutations(
      before: ["location"],
      after: ["location", "microphone"],
      timestampMillis: 42
    )
    let revokedEvents = GlobalCapabilityObservationExtractor.authorizationMutations(
      before: ["downloads"],
      after: [],
      timestampMillis: 43
    )
    let safety = GlobalCapabilityObservationExtractor.safetyPolicyMutation(
      before: .default,
      after: AgentSafetySettings(
        taskExecutionMode: .planOnly,
        permissionMode: .autoLowRisk,
        highRiskGuard: true,
        memoryCapture: false,
        screenObservationAllowed: false,
        localActionsAllowed: true,
        connectorCallsAllowed: false,
        deviceControlAllowed: false,
        executionPaused: true
      ),
      timestampMillis: 44
    )

    XCTAssertEqual(authorizationEvents.count, 1)
    XCTAssertEqual(authorizationEvents[0].type, .authorizationGranted)
    XCTAssertTrue(authorizationEvents[0].type.isCapabilityLifecycleEvent)
    XCTAssertEqual(authorizationEvents[0].conversationId, "global-capabilities")
    XCTAssertEqual(authorizationEvents[0].conversationTitle, "Local authorization")
    XCTAssertEqual(authorizationEvents[0].metadata["origin"], "confirmation_consent")
    XCTAssertEqual(authorizationEvents[0].metadata["authorization_scope"], "microphone use")
    XCTAssertEqual(authorizationEvents[0].metadata["authorization_state"], "granted")
    XCTAssertEqual(authorizationEvents[0].metadata["context_visibility"], "LOCAL_ONLY")
    XCTAssertEqual(authorizationEvents[0].metadata["projection"], "replace")
    XCTAssertEqual(revokedEvents.first?.type, .authorizationRevoked)
    XCTAssertEqual(revokedEvents.first?.metadata["authorization_state"], "revoked")
    XCTAssertNotNil(safety)
    XCTAssertEqual(safety?.type, .authorizationPolicyChanged)
    XCTAssertEqual(safety?.contentRef, "encrypted://agent-authorization/safety-policy")
    XCTAssertEqual(safety?.metadata["task_execution_mode"], "plan_only")
    XCTAssertEqual(safety?.metadata["permission_mode"], "auto_low_risk")
    XCTAssertEqual(safety?.metadata["screen_observation_allowed"], "false")
    XCTAssertEqual(safety?.metadata["connector_calls_allowed"], "false")
    XCTAssertEqual(safety?.metadata["execution_paused"], "true")
    XCTAssertEqual(safety?.metadata["identity_kind"], "DECISION")
    XCTAssertEqual(safety?.metadata["identity_layer"], "USER")
    XCTAssertNil(GlobalCapabilityObservationExtractor.safetyPolicyMutation(before: .default, after: .default))
  }

  func testGlobalCapabilityObservationExtractorMcpAgentAndHealthAreRedacted() throws {
    let endpoint = "https://secret.example/mcp"
    let connection = AgentMcpConnection(
      id: "github",
      catalogId: "signalasi.mcp.github",
      displayName: "  GitHub   MCP  ",
      endpoint: endpoint,
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired,
      state: .connected,
      toolIds: ["issues.search", "repo.read", "repo.read"]
    )
    let mcp = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.mcpMutations(
        before: [],
        after: [connection],
        timestampMillis: 100
      ).first
    )
    let agent = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.agentMutations(
        before: [],
        after: [
          networkRegistration(
            agentId: "desktop-agent",
            displayName: "Desktop Agent",
            location: .trustedDesktop,
            status: .online,
            capabilities: [.chat, .code],
            activeRuns: 4,
            maxParallelRuns: 4
          )
        ],
        timestampMillis: 101
      ).first
    )
    let resourceId = "target:https://secret.example/runtime"
    let health = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.resourceHealthTransition(
        resourceId: resourceId,
        before: AgentResourceHealth(),
        after: AgentResourceHealth(failures: 3, consecutiveFailures: 3, circuitOpenUntil: 2_000),
        timestampMillis: 102
      )
    )

    XCTAssertEqual(mcp.type, .resourceRegistered)
    XCTAssertEqual(mcp.metadata["resource_kind"], "mcp")
    XCTAssertEqual(mcp.metadata["resource_state"], "available")
    XCTAssertEqual(mcp.metadata["auth_state"], "not_required")
    XCTAssertEqual(mcp.metadata["connection_state"], "connected")
    XCTAssertEqual(mcp.metadata["tool_count"], "2")
    assertGlobalCapabilityEventDoesNotExpose(mcp, secrets: [endpoint, "secret.example"])
    XCTAssertEqual(agent.metadata["resource_kind"], "agent")
    XCTAssertEqual(agent.metadata["resource_state"], "busy")
    XCTAssertEqual(agent.metadata["endpoint_state"], "online")
    XCTAssertEqual(agent.metadata["capability_count"], "2")
    XCTAssertEqual(agent.metadata["at_capacity"], "true")
    XCTAssertEqual(health.type, .resourceStateChanged)
    XCTAssertEqual(health.metadata["origin"], "resource_health")
    XCTAssertEqual(health.metadata["resource_kind"], "health")
    XCTAssertEqual(health.metadata["resource_state"], "unavailable")
    XCTAssertEqual(health.metadata["consecutive_failures"], "3")
    XCTAssertEqual(health.metadata["reliability_percent"], "0")
    assertGlobalCapabilityEventDoesNotExpose(health, secrets: [resourceId, "secret.example/runtime"])
  }

  func testGlobalCapabilityObservationExtractorDeviceResourcesAreRedacted() throws {
    let home = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.homeAssistantMutations(
        before: .default,
        after: HomeAssistantSettings(
          enabled: true,
          baseUrl: "https://home.secret.local",
          accessToken: "ha-token-secret",
          defaultEntityId: "light.private_room"
        ),
        timestampMillis: 200
      ).first
    )
    let device = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.customDeviceMutations(
        before: [],
        after: [
          CustomDeviceConnector(
            id: "door-lock",
            name: "Door Lock",
            transport: .mqtt,
            endpoint: "mqtt://device.secret.local",
            commandTarget: "locks/private-door",
            username: "private-user",
            authToken: "device-token-secret",
            risk: .high,
            enabled: true
          )
        ],
        timestampMillis: 201
      ).first
    )

    XCTAssertEqual(home.metadata["resource_kind"], "home_assistant")
    XCTAssertEqual(home.metadata["resource_state"], "ready")
    XCTAssertEqual(home.metadata["credentials_configured"], "true")
    XCTAssertEqual(home.metadata["default_target_configured"], "true")
    XCTAssertEqual(device.metadata["resource_kind"], "custom_device")
    XCTAssertEqual(device.metadata["resource_state"], "ready")
    XCTAssertEqual(device.metadata["transport"], "mqtt")
    XCTAssertEqual(device.metadata["risk"], "high")
    XCTAssertEqual(device.metadata["configured"], "true")
    assertGlobalCapabilityEventDoesNotExpose(
      home,
      secrets: ["home.secret.local", "ha-token-secret", "light.private_room"]
    )
    assertGlobalCapabilityEventDoesNotExpose(
      device,
      secrets: ["device.secret.local", "locks/private-door", "private-user", "device-token-secret"]
    )
  }

  func testGlobalCapabilityObservationModelsUseAndroidWireNames() throws {
    let reset = GlobalCapabilityObservationExtractor.snapshotReset(timestampMillis: 300)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(reset)) as? [String: Any]
    )
    let health = AgentResourceHealth(
      successes: 3,
      failures: 1,
      consecutiveFailures: 0,
      averageLatencyMs: 250,
      circuitOpenUntil: 0,
      lastUpdatedAt: 123
    )
    let healthObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(health)) as? [String: Any]
    )

    XCTAssertEqual(object["type"] as? String, "CAPABILITY_SNAPSHOT_RESET")
    XCTAssertEqual(object["conversation_id"] as? String, "global-capabilities")
    XCTAssertEqual(object["timestamp_millis"] as? Int, 300)
    XCTAssertNotNil(object["message_id"])
    XCTAssertNotNil(object["content_ref"])
    XCTAssertNotNil(object["conversation_title"])
    XCTAssertNotNil(object["topic_hints"])
    XCTAssertNotNil(object["causal_event_ids"])
    XCTAssertNotNil(object["retracted_event_ids"])
    XCTAssertEqual(object["actor"] as? String, "SYSTEM")
    XCTAssertEqual(object["sensitivity"] as? String, "PERSONAL")
    XCTAssertEqual((object["metadata"] as? [String: Any])?["context_visibility"] as? String, "LOCAL_ONLY")
    XCTAssertEqual(healthObject["consecutive_failures"] as? Int, 0)
    XCTAssertEqual(healthObject["average_latency_ms"] as? Int, 250)
    XCTAssertEqual(healthObject["circuit_open_until"] as? Int, 0)
    XCTAssertEqual(healthObject["last_updated_at"] as? Int, 123)
    XCTAssertEqual(health.reliabilityPercent, 75)
    XCTAssertTrue(GlobalConversationEventType.resourceRegistered.isCapabilityLifecycleEvent)
    XCTAssertFalse(GlobalConversationEventType.messageCreated.isCapabilityLifecycleEvent)
  }

  func testAgentConfirmationPolicyMatchesAndroidTiersAndConsentKeys() throws {
    func action(
      id: String,
      kind: AgentActionKind,
      description: String,
      risk: AgentRisk = .medium,
      target: String = "iOS",
      parameters: [String: String] = [:]
    ) -> AgentAction {
      AgentAction(
        id: id,
        kind: kind,
        target: target,
        risk: risk,
        status: .pendingConfirmation,
        description: description,
        parameters: parameters
      )
    }

    func nativeAction(_ toolId: String, _ description: String, id: String = "native-tool", inputJson: String = "{}") -> AgentAction {
      action(
        id: id,
        kind: .callNativeTool,
        description: description,
        parameters: ["tool_id": toolId, "input_json": inputJson]
      )
    }

    let decoded = try JSONDecoder.signalASI.decode(
      AgentAction.self,
      from: Data("""
      {
        "id": "sms-send",
        "kind": "CALL_NATIVE_TOOL",
        "target": "iOS",
        "risk": "MEDIUM",
        "status": "PENDING_CONFIRMATION",
        "description": "Send SMS message",
        "parameters": {
          "tool_id": "signalasi.notifications.reply",
          "input_json": "{}"
        },
        "requires_confirmation": true
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.signalASI.encode(decoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(decoded.kind, .callNativeTool)
    XCTAssertEqual(decoded.risk, .medium)
    XCTAssertEqual(decoded.status, .pendingConfirmation)
    XCTAssertEqual(object["kind"] as? String, "CALL_NATIVE_TOOL")
    XCTAssertEqual(object["requires_confirmation"] as? Bool, true)

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "set-timer", kind: .setAlarm, description: "Set timer for 60 seconds")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "open-camera", kind: .openApp, description: "Open camera and take photo")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.android.audio.volume.set", "Set Android stream volume")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.hardware.bluetooth.pairing.handoff", "Open Bluetooth pairing settings")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.desktop.workspace.file.read.text", "Read an authorized Desktop file")), .direct)

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "location", kind: .callNativeTool, description: "Read location")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "download", kind: .callNativeTool, description: "Download file")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.hardware.bluetooth.discovery.foreground", "Discover nearby Bluetooth devices once")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.hardware.apps.installed.list", "List query-visible installed apps")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeAction("signalasi.microphone.record.visible", "Record audio")), .confirmOnce)

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: decoded), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "delete-file", kind: .callNativeTool, description: "Delete file")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: action(id: "lock", kind: .lockScreen, description: "Lock device")), .confirmAlways)

    let firstBluetooth = nativeAction(
      "signalasi.hardware.bluetooth.discovery.foreground",
      "Discover nearby Bluetooth devices once",
      id: "native-first"
    )
    let secondBluetooth = nativeAction(
      "signalasi.hardware.bluetooth.discovery.foreground",
      "Scan for nearby Bluetooth devices",
      id: "native-second"
    )
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), "bluetooth_discovery")
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), AgentConfirmationPolicy.consentKey(for: secondBluetooth))

    let homeAssistantInput = #"{"entity_id":"lock.front_door","service_domain":"lock","service":"unlock"}"#
    let homeAssistantAction = nativeAction(
      "signalasi.home_assistant.service.call",
      "Unlock front door",
      inputJson: homeAssistantInput
    )
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: homeAssistantAction), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: homeAssistantAction), "home_assistant_control:lock.front_door")

    let connectorAction = AgentAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      risk: .low,
      status: .pendingConfirmation,
      description: "Ask Codex",
      parameters: [
        "prompt": "Show an animated letter",
        "_signalasi_conversation_context": "Earlier the user asked to send a message"
      ]
    )
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: connectorAction), .direct)
  }

  func testAgentActionRiskHardenerRaisesConnectorAndVisualOcrRisk() {
    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "connector-deploy",
        kind: .callConnector,
        risk: .low,
        target: "Codex",
        description: "Ask Codex to prepare a release",
        parameters: ["prompt": "Deploy and send email release notes"]
      ),
      riskHardenerAction(
        id: "tap-low-confidence",
        kind: .tap,
        risk: .low,
        parameters: [
          "element_origin": AgentElementOrigin.visualOcr.rawValue,
          "element_confidence": "0.42"
        ]
      ),
      riskHardenerAction(
        id: "type-confident-ocr",
        kind: .typeText,
        risk: .low,
        parameters: [
          "field_origin": AgentElementOrigin.visualOcr.rawValue,
          "field_confidence": "0.91"
        ]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(plan: plan)

    XCTAssertEqual(hardened.actions.first { $0.id == "connector-deploy" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "tap-low-confidence" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "type-confident-ocr" }?.risk, .medium)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentActionRiskHardenerUsesCustomDeviceAndHomeAssistantRisk() {
    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "known-custom-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "custom-device:kitchen-light"]
      ),
      riskHardenerAction(
        id: "unknown-custom-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "custom-device:missing-device"]
      ),
      riskHardenerAction(
        id: "home-assistant-lock",
        kind: .controlDevice,
        risk: .low,
        parameters: [
          "connector_id": "home-assistant",
          "prompt": "Unlock the front door"
        ]
      ),
      riskHardenerAction(
        id: "unknown-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "zigbee-hub"]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(
      plan: plan,
      customDeviceConnectors: [
        CustomDeviceConnector(
          id: "kitchen-light",
          name: "Kitchen Light",
          endpoint: "http://kitchen-light.local",
          risk: .medium
        )
      ],
      homeAssistantSettings: HomeAssistantSettings(
        enabled: true,
        baseUrl: "http://homeassistant.local:8123",
        accessToken: "token",
        defaultEntityId: "lock.front_door"
      )
    )

    XCTAssertEqual(hardened.actions.first { $0.id == "known-custom-device" }?.risk, .medium)
    XCTAssertEqual(hardened.actions.first { $0.id == "unknown-custom-device" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "home-assistant-lock" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "unknown-device" }?.risk, .high)
    XCTAssertEqual(AgentHomeAssistantRiskPolicy.riskForPrompt("Turn on switch.kitchen"), .medium)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentActionRiskHardenerNeverLowersExistingRiskAndModelsUseAndroidSignals() throws {
    let decoded = try JSONDecoder.signalASI.decode(AgentElementOrigin.self, from: Data(#""visual-ocr""#.utf8))
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(AgentElementOrigin.visualOcr), as: UTF8.self)
    XCTAssertEqual(decoded, .visualOcr)
    XCTAssertEqual(encoded, #""VISUAL_OCR""#)
    XCTAssertEqual(AgentElementOrigin.fromWireValue("visual ocr"), .visualOcr)
    XCTAssertEqual(AgentElementOrigin.fromWireValue(nil), .unknown)

    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "existing-high",
        kind: .tap,
        risk: .high,
        parameters: [
          "element_origin": AgentElementOrigin.visualOcr.rawValue,
          "element_confidence": "0.99"
        ]
      ),
      riskHardenerAction(
        id: "accessibility-long-press",
        kind: .longPress,
        risk: .medium,
        parameters: [
          "element_origin": AgentElementOrigin.accessibility.rawValue,
          "element_confidence": "0.20"
        ]
      ),
      riskHardenerAction(
        id: "connector-transfer",
        kind: .callConnector,
        risk: .low,
        target: "Payments",
        description: "Ask connector",
        parameters: ["prompt": "\u{8bf7}\u{8f6c}\u{8d26}\u{7ed9}\u{4f9b}\u{5e94}\u{5546}"]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(plan: plan)

    XCTAssertEqual(hardened.actions.first { $0.id == "existing-high" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "accessibility-long-press" }?.risk, .medium)
    XCTAssertEqual(hardened.actions.first { $0.id == "connector-transfer" }?.risk, .high)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentVisualGroundingAnalyzesRolesAndAndroidWireNames() throws {
    let scene = AgentVisualGrounding.analyze(
      rawElements: [
        AgentVisualElement(text: "  Continue\nnow ", bounds: "20,1500,320,1580", confidence: 1.4),
        AgentVisualElement(text: "Continue now", bounds: "20,1500,320,1580", confidence: 0.9),
        AgentVisualElement(text: "Account Settings", bounds: "20,20,600,110", confidence: 0.8),
        AgentVisualElement(text: "Email address", bounds: "30,620,860,690", confidence: 0.7),
        AgentVisualElement(text: "Home", bounds: "20,1650,200,1740", confidence: 0.6),
        AgentVisualElement(text: " ", bounds: "10,10,20,20"),
        AgentVisualElement(text: "Broken", bounds: "10,10,8,20")
      ],
      width: 1_080,
      height: 1_800,
      timestampMillis: 12_345
    )
    let encoded = try JSONEncoder.signalASI.encode(scene)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let firstElement = try XCTUnwrap((object["elements"] as? [[String: Any]])?.first)

    XCTAssertTrue(scene.available)
    XCTAssertEqual(scene.width, 1_080)
    XCTAssertEqual(scene.height, 1_800)
    XCTAssertEqual(scene.modelProfile, "mlkit-ocr-layout-v1")
    XCTAssertEqual(scene.timestampMillis, 12_345)
    XCTAssertEqual(scene.elements.count, 4)
    XCTAssertEqual(scene.elements.first?.text, "Continue now")
    XCTAssertEqual(scene.elements.first?.confidence, 1)
    XCTAssertEqual(scene.elements.first?.role, .button)
    XCTAssertEqual(scene.elements.first { $0.text == "Account Settings" }?.role, .title)
    XCTAssertEqual(scene.elements.first { $0.text == "Email address" }?.role, .input)
    XCTAssertEqual(scene.elements.first { $0.text == "Home" }?.role, .navigation)
    XCTAssertEqual(scene.actionCandidateCount, 2)
    XCTAssertEqual(scene.inputCandidateCount, 1)
    XCTAssertEqual(object["model_profile"] as? String, "mlkit-ocr-layout-v1")
    XCTAssertEqual(object["action_candidate_count"] as? Int, 2)
    XCTAssertEqual(object["input_candidate_count"] as? Int, 1)
    XCTAssertEqual(firstElement["input_candidate"] as? Bool, false)
    XCTAssertEqual(AgentVisualRole.fromWireValue("list item"), .listItem)
    XCTAssertEqual(AgentElementOrigin.fromWireValue("fused"), .fused)
  }

  func testAgentVisualGroundingFusesAccessibilityAndVisualElements() {
    let accessibility = [
      agentScreenElement(
        label: "",
        viewId: "android:id/button1",
        className: "Button",
        bounds: "100,100,300,180",
        confidence: 0.6,
        actionable: true
      )
    ]
    let scene = AgentVisualScene(
      width: 1_080,
      height: 1_800,
      elements: [
        AgentVisualElement(
          text: "Continue",
          bounds: "104,104,296,176",
          confidence: 0.8,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Save",
          bounds: "400,100,620,180",
          confidence: 0.7,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Maybe",
          bounds: "700,100,820,180",
          confidence: 0.3,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Email",
          bounds: "80,500,900,580",
          confidence: 0.9,
          role: .input,
          actionable: false,
          inputCandidate: true
        )
      ]
    )

    let fusedActions = AgentVisualGrounding.fuseClickableElements(accessibilityElements: accessibility, scene: scene)
    let fusedFields = AgentVisualGrounding.fuseInputFields(accessibilityElements: [], scene: scene)

    XCTAssertEqual(fusedActions.count, 2)
    XCTAssertEqual(fusedActions[0].label, "Continue")
    XCTAssertEqual(fusedActions[0].origin, .fused)
    XCTAssertEqual(fusedActions[0].confidence, 0.8)
    XCTAssertEqual(fusedActions[0].visualRole, .button)
    XCTAssertEqual(fusedActions[1].label, "Save")
    XCTAssertEqual(fusedActions[1].viewId, "visual:button:0")
    XCTAssertEqual(fusedActions[1].className, "AgentVisualButton")
    XCTAssertEqual(fusedActions[1].origin, .visualOcr)
    XCTAssertEqual(fusedFields.count, 1)
    XCTAssertEqual(fusedFields.first?.label, "Email")
    XCTAssertEqual(fusedFields.first?.viewId, "visual:input:0")
    XCTAssertEqual(fusedFields.first?.origin, .visualOcr)
  }

  func testAgentScreenElementMatcherResolvesAndroidStyleQueries() {
    let accessibility = agentScreenElement(
      label: "Continue",
      viewId: "primary_action",
      className: "Button",
      bounds: "10,10,210,80",
      origin: .accessibility,
      confidence: 0.8,
      visualRole: .button
    )
    let visual = agentScreenElement(
      label: "Continue",
      viewId: "visual:button:0",
      className: "AgentVisualButton",
      bounds: "10,10,210,80",
      origin: .visualOcr,
      confidence: 0.8,
      visualRole: .button
    )
    let input = agentScreenElement(
      label: "Email address",
      viewId: "field_email",
      className: "EditText",
      bounds: "10,200,600,280",
      confidence: 0.7,
      visualRole: .input
    )
    let elements = [visual, input, accessibility]

    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "Continue", elements: elements), accessibility)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "primary action", elements: elements), accessibility)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "email", elements: elements), input)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "input", elements: elements), input)
    XCTAssertNil(AgentScreenElementMatcher.resolve(query: "   ", elements: elements))
  }

  func testAgentRemoteApprovalValidTaskApprovalRoundTripsExactDecision() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )

    XCTAssertEqual(request.approvalId, "approval-12345678")
    XCTAssertEqual(request.detail, "python verify.py")
    XCTAssertEqual(request.parametersJson, #"{"command":"python verify.py","cwd":"C:/workspace"}"#)
    XCTAssertEqual(request.compactActionHash, "aaaaaaaa...aaaaaaaa")
    XCTAssertEqual(request.dedupeKey, "remote-approval:task-approval:approval-12345678")

    let approved = try XCTUnwrap(AgentRemoteApprovalDecision.decode(request.decision(approved: true).encode()))

    XCTAssertTrue(approved.approved)
    XCTAssertEqual(approved.taskId, request.taskId)
    XCTAssertEqual(approved.clientRouteId, request.clientRouteId)
    XCTAssertEqual(approved.conversationId, request.conversationId)
    XCTAssertEqual(approved.turnId, request.turnId)
    XCTAssertEqual(approved.actionHash, request.actionHash)
  }

  func testAgentRemoteApprovalRejectsExpiredOrMalformedApprovals() {
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 1_500),
        nowMillis: 2_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(actionHash: "changed"),
        nowMillis: 1_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(sourceMessageId: 0),
        nowMillis: 1_000
      )
    )
    XCTAssertNil(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(taskStatus: "running"),
        nowMillis: 1_000
      )
    )
  }

  func testAgentRemoteApprovalDecisionDecoderRejectsChangedIdentityFields() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(request.decision(approved: false).encode().utf8)) as? [String: Any]
    )
    object["approval_id"] = "short"
    let mutated = String(
      decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      as: UTF8.self
    )

    XCTAssertNil(AgentRemoteApprovalDecision.decode(mutated))
    XCTAssertFalse(request.decision(approved: false).approved)
  }

  func testAgentRemoteApprovalModelsUseAndroidWireNames() throws {
    let request = try XCTUnwrap(
      AgentRemoteApprovalRequest.fromTaskEvent(
        remoteApprovalTaskEvent(sourceMessageId: 42, expiresAtMillis: 2_000_000),
        nowMillis: 1_700_000
      )
    )
    let decision = request.decision(approved: true)
    let decisionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(decision.encode().utf8)) as? [String: Any]
    )
    let requestObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(decisionObject["task_id"] as? String, "task-approval")
    XCTAssertEqual(decisionObject["client_route_id"] as? String, "client-route")
    XCTAssertEqual(decisionObject["conversation_id"] as? String, "conversation-approval")
    XCTAssertEqual(decisionObject["turn_id"] as? String, "turn-approval")
    XCTAssertEqual(decisionObject["contact_id"] as? String, "codex-contact")
    XCTAssertEqual(decisionObject["source_message_id"] as? Int, 42)
    XCTAssertEqual(decisionObject["approval_id"] as? String, "approval-12345678")
    XCTAssertEqual(decisionObject["action_hash"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(decisionObject["approved"] as? Bool, true)
    XCTAssertNil(decisionObject["sourceMessageId"])
    XCTAssertEqual(requestObject["requested_at_millis"] as? Int, 1_700_000)
    XCTAssertEqual(requestObject["expires_at_millis"] as? Int, 2_000_000)
    XCTAssertEqual(requestObject["parameters_json"] as? String, #"{"command":"python verify.py","cwd":"C:/workspace"}"#)
  }

  func testAgentRemoteReputationDecodesDesktopReceiptAndPreservesCanonicalFieldOrder() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))

    XCTAssertEqual(receipt.agentId, remoteReputationContactId)
    XCTAssertEqual(receipt.capabilities, Set([AgentCapability.chat, AgentCapability.code]))
    XCTAssertEqual(receipt.provenance, .hostObserved)

    let canonical = String(decoding: receipt.canonicalPayload(), as: UTF8.self)
    let taskHash = agentReputationSha256(Data(remoteReputationTaskId.utf8))
    XCTAssertTrue(canonical.hasPrefix("{\"actual_cost_units\":0,\"agent_id\":\"\(remoteReputationContactId)\""))
    XCTAssertTrue(
      canonical.hasSuffix(
        "\"started_at_millis\":1000,\"task_id_hash\":\"\(taskHash)\",\"version\":1}"
      )
    )
    XCTAssertEqual(
      agentReputationSha256(Data(canonical.utf8)),
      "fe6995403d63a8ca06ab70ae20d0e3b62749d3ab9eac8b2a2e3e62e775ecf4e7"
    )
  }

  func testAgentRemoteReputationBindsReceiptToPairedDesktopAgentAndTask() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let envelope = remoteReputationEnvelope()

    XCTAssertNil(AgentRemoteReputation.bindingFailure(envelope, receipt: receipt))
    XCTAssertEqual(AgentRemoteReputation.boundReceipt(from: envelope)?.receiptId, receipt.receiptId)

    var changedTask = envelope
    changedTask["task_id"] = .string("other-task")
    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(changedTask, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
  }

  func testAgentRemoteReputationRejectsCrossDesktopOrCrossAgentClaims() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let crossDesktop = remoteReputationEnvelope(
      desktopId: "desktop_fedcba9876543210",
      contactId: "desktop_fedcba9876543210:codex"
    )
    let crossAgent = remoteReputationEnvelope(contactId: "\(remoteReputationDesktopId):browser")

    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(crossDesktop, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(crossAgent, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
  }

  func testAgentRemoteReputationRejectsMalformedReceiptsAndUsesAndroidWireNames() throws {
    var invalidReceipt = remoteReputationReceiptObject()
    invalidReceipt["outcome"] = .string("DONE")
    XCTAssertNil(AgentReputationWireCodec.decodeReceipt(invalidReceipt))

    var invalidEnvelope = remoteReputationEnvelope()
    invalidEnvelope["execution_receipt"] = .object(invalidReceipt)
    XCTAssertEqual(
      AgentRemoteReputation.receiptFailureReason(from: invalidEnvelope),
      AgentRemoteReputation.invalidReceiptReason
    )

    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any]
    )
    XCTAssertEqual(object["receipt_id"] as? String, "receipt-1")
    XCTAssertEqual(object["task_id_hash"] as? String, agentReputationSha256(Data(remoteReputationTaskId.utf8)))
    XCTAssertEqual(object["executor_failure_domain"] as? String, remoteReputationDesktopId)
    XCTAssertEqual(object["started_at_millis"] as? Int, 1_000)
    XCTAssertEqual(object["completed_at_millis"] as? Int, 2_000)
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "a", count: 64))
    XCTAssertNil(object["taskIdHash"])
    XCTAssertNil(object["startedAtMillis"])
  }

  func testAgentReputationAttestationCanonicalPayloadBindsReceiptHash() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )

    XCTAssertEqual(attestation.verdict, .passed)
    XCTAssertEqual(attestation.receiptId, receipt.receiptId)
    XCTAssertEqual(attestation.receiptPayloadHash, agentReputationSha256(receipt.canonicalPayload()))
    XCTAssertNil(attestation.validationFailure(for: receipt, nowMillis: 10_000))

    let canonical = String(decoding: attestation.canonicalPayload(), as: UTF8.self)
    XCTAssertTrue(canonical.hasPrefix("{\"attestation_id\":\"\(attestation.attestationId)\""))
    XCTAssertTrue(canonical.hasSuffix("\"verifier_installation_id\":\"verifier-host\",\"version\":1}"))
    XCTAssertEqual(
      agentReputationSha256(attestation.canonicalPayload()),
      "ad01c99d132f3e0458d43c9deaec1365445a14b429bd486ec57fe68ea6f3f18c"
    )
  }

  func testAgentReputationAttestationRejectsDependentOrTamperedClaims() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )

    var tamperedHash = attestation
    tamperedHash.receiptPayloadHash = String(repeating: "f", count: 64)
    XCTAssertEqual(
      tamperedHash.validationFailure(for: receipt, nowMillis: 10_000),
      AgentRemoteReputation.invalidBindingReason
    )

    var sameAgent = attestation
    sameAgent.verifierAgentId = receipt.agentId
    XCTAssertEqual(
      sameAgent.validationFailure(for: receipt, nowMillis: 10_000),
      "independence_boundary_invalid"
    )

    var signerMismatch = attestation
    signerMismatch.signerId = "other-verifier"
    signerMismatch.signatureKeyId = String(repeating: "e", count: 64)
    XCTAssertEqual(
      signerMismatch.validationFailure(for: receipt, nowMillis: 10_000),
      "signer_subject_mismatch"
    )

    var tooEarly = attestation
    tooEarly.createdAtMillis = receipt.completedAtMillis - 1
    XCTAssertEqual(
      tooEarly.validationFailure(for: receipt, nowMillis: 10_000),
      "time_boundary_invalid"
    )
  }

  func testAgentReputationAttestationModelsUseAndroidWireNames() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(attestation)) as? [String: Any]
    )

    XCTAssertEqual(object["attestation_id"] as? String, attestation.attestationId)
    XCTAssertEqual(object["receipt_payload_hash"] as? String, agentReputationSha256(receipt.canonicalPayload()))
    XCTAssertEqual(object["verifier_agent_id"] as? String, "independent-verifier")
    XCTAssertEqual(object["verifier_installation_id"] as? String, "verifier-host")
    XCTAssertEqual(object["verifier_failure_domain"] as? String, "phone-b")
    XCTAssertEqual(object["created_at_millis"] as? Int, 2_100)
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "d", count: 64))
    XCTAssertNil(object["receiptPayloadHash"])
    XCTAssertNil(object["verifierAgentId"])

    var invalid = remoteReputationAttestationObject(for: receipt)
    invalid["verdict"] = .string("UNKNOWN")
    XCTAssertNil(AgentReputationWireCodec.decodeAttestation(invalid))
  }

  func testAgentReputationSnapshotNeutralAndIndependentPassRaiseConfidence() {
    let receipt = reputationReceipt("run-1", outcome: .succeeded)
    let neutral = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [],
      attestations: [],
      nowMillis: reputationNow
    )
    let before = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let after = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [reputationAttestation(for: receipt, verdict: .passed)],
      nowMillis: reputationNow + 1_000
    )

    XCTAssertEqual(neutral, AgentReputationSnapshot.neutral(receipt.agentId))
    XCTAssertTrue(after.confidence > before.confidence)
    XCTAssertTrue(after.score >= before.score)
    XCTAssertEqual(after.independentlyVerifiedRuns, 1)
    XCTAssertEqual(after.independentFailureDomains, 1)
    XCTAssertEqual(after.lastEvidenceAtMillis, receipt.completedAtMillis + 100)
  }

  func testAgentReputationSnapshotFailureTimeoutAndBudgetDimensions() {
    let succeeded = reputationReceipt("run-1", outcome: .succeeded)
    let beforeFailure = AgentReputationScoring.snapshot(
      agentId: succeeded.agentId,
      receipts: [succeeded],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let afterFailure = AgentReputationScoring.snapshot(
      agentId: succeeded.agentId,
      receipts: [succeeded],
      attestations: [reputationAttestation(for: succeeded, verdict: .failed)],
      nowMillis: reputationNow + 1_000
    )
    let timeout = reputationReceipt(
      "run-timeout",
      outcome: .timedOut,
      deadlineAtMillis: reputationNow - 500,
      estimatedCostUnits: 2,
      actualCostUnits: 8
    )
    let timeoutProfile = AgentReputationScoring.snapshot(
      agentId: timeout.agentId,
      receipts: [timeout],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )

    XCTAssertTrue(afterFailure.score < beforeFailure.score)
    XCTAssertEqual(afterFailure.disputedRuns, 1)
    XCTAssertEqual(afterFailure.independentlyVerifiedRuns, 0)
    XCTAssertEqual(timeoutProfile.timeoutRuns, 1)
    XCTAssertTrue(timeoutProfile.timeliness < 70)
    XCTAssertTrue(timeoutProfile.costEfficiency < 70)
    XCTAssertTrue(timeoutProfile.reliability < 70)
  }

  func testAgentReputationSnapshotFiltersCapabilitiesAndUsesLatestRunVersion() {
    let codeReceipts = (0..<4).map {
      reputationReceipt("code-\($0)", outcome: .succeeded, capabilities: [.code])
    }
    let researchFailure = reputationReceipt(
      "research-failure",
      outcome: .failed,
      capabilities: [.research]
    )
    let code = AgentReputationScoring.snapshot(
      agentId: "codex-agent",
      capabilities: [.code],
      receipts: codeReceipts + [researchFailure],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let research = AgentReputationScoring.snapshot(
      agentId: "codex-agent",
      capabilities: [.research],
      receipts: codeReceipts + [researchFailure],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let failed = reputationReceipt("run-1", outcome: .failed)
    let corrected = reputationReceipt("run-1", outcome: .succeeded, completedAtMillis: reputationNow + 100)
    let correctedProfile = AgentReputationScoring.snapshot(
      agentId: failed.agentId,
      receipts: [failed, corrected],
      attestations: [],
      nowMillis: reputationNow + 100
    )

    XCTAssertTrue(code.score > research.score)
    XCTAssertEqual(code.evaluatedRuns, 4)
    XCTAssertEqual(research.evaluatedRuns, 1)
    XCTAssertEqual(correctedProfile.evaluatedRuns, 1)
    XCTAssertTrue(correctedProfile.score > 70)
  }

  func testAgentReputationSnapshotModelsUseAndroidWireNames() throws {
    let receipt = reputationReceipt("run-1", outcome: .succeeded)
    let snapshot = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [reputationAttestation(for: receipt, verdict: .passed)],
      nowMillis: reputationNow + 1_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
    )

    XCTAssertEqual(object["agent_id"] as? String, "codex-agent")
    XCTAssertEqual(object["cost_efficiency"] as? Int, snapshot.costEfficiency)
    XCTAssertEqual(object["evaluated_runs"] as? Int, 1)
    XCTAssertEqual(object["independently_verified_runs"] as? Int, 1)
    XCTAssertEqual(object["independent_failure_domains"] as? Int, 1)
    XCTAssertEqual(object["last_evidence_at_millis"] as? Int, Int(reputationNow + 100))
    XCTAssertEqual(object["routing_adjustment"] as? Int, snapshot.routingAdjustment)
    XCTAssertNil(object["costEfficiency"])
    XCTAssertNil(object["evaluatedRuns"])
  }

  func testAgentNetworkSearchRanksCapableNamedAgentsWithoutCollapsingIdentity() {
    let index = AgentNetworkIndex([
      networkRegistration(
        agentId: "codex.office",
        displayName: "Codex - Office PC",
        capabilities: [.chat, .code, .taskExecution],
        latency: .fast
      ),
      networkRegistration(
        agentId: "claude-code.home",
        displayName: "Claude Code - Home PC",
        capabilities: [.chat, .code, .reasoning],
        latency: .normal
      ),
      networkRegistration(
        agentId: "hermes.research",
        displayName: "Hermes - Research PC",
        capabilities: [.chat, .research, .liveData]
      )
    ])

    let page = index.search(
      AgentNetworkSearchQuery(text: "Find a fast Agent to debug a Python project"),
      nowMillis: 1_000_000
    )

    XCTAssertEqual(page.totalMatches, 2)
    XCTAssertEqual(page.hits.first?.registration.agentId, "codex.office")
    XCTAssertEqual(page.hits.first?.registration.displayName, "Codex - Office PC")
    XCTAssertTrue(page.hits.first?.matchedCapabilities.contains(.code) == true)
    XCTAssertFalse(page.hits.contains { $0.registration.agentId == "hermes.research" })
  }

  func testAgentNetworkSearchEnforcesTrustCapacityCostAndStaleHeartbeat() {
    let now: Int64 = 1_000_000
    let staleHeartbeat = now - AgentNetworkIndex.heartbeatTTLMillis - 1
    let index = AgentNetworkIndex([
      networkRegistration(
        agentId: "phone.local",
        displayName: "Phone Agent",
        location: .phone,
        trust: .phoneSystem,
        cost: .free,
        lastHeartbeatMillis: staleHeartbeat
      ),
      networkRegistration(
        agentId: "desktop.busy",
        displayName: "Codex - Busy PC",
        activeRuns: 2,
        maxParallelRuns: 2,
        cost: .low
      ),
      networkRegistration(
        agentId: "cloud.unknown",
        displayName: "Unknown Cloud Agent",
        location: .cloud,
        trust: .unknown,
        cost: .high
      ),
      networkRegistration(
        agentId: "desktop.stale",
        displayName: "Codex - Stale PC",
        lastHeartbeatMillis: staleHeartbeat
      )
    ])

    let filtered = index.search(
      AgentNetworkSearchQuery(trustedOnly: true, maximumCost: .low),
      nowMillis: now
    )
    let all = index.search(AgentNetworkSearchQuery(routableOnly: false), nowMillis: now)

    XCTAssertEqual(filtered.hits.map { $0.registration.agentId }, ["phone.local"])
    XCTAssertEqual(
      all.hits.first { $0.registration.agentId == "desktop.stale" }?.registration.status,
      .unreachable
    )
  }

  func testAgentNetworkSearchCursorInvalidatesAfterDirectoryOrReputationMutation() {
    let registrations = (0..<75).map {
      networkRegistration(
        agentId: "agent-\($0)",
        displayName: "Agent \(String(format: "%03d", $0))"
      )
    }
    let index = AgentNetworkIndex(registrations)
    let query = AgentNetworkSearchQuery(pageSize: 25)
    let first = index.search(query, nowMillis: 1_000_000)
    let second = index.search(AgentNetworkSearchQuery(pageSize: 25, cursor: first.nextCursor), nowMillis: 1_000_000)

    XCTAssertEqual(first.hits.count, 25)
    XCTAssertEqual(second.hits.count, 25)
    XCTAssertTrue(Set(first.hits.map { $0.registration.agentId }).isDisjoint(with: second.hits.map { $0.registration.agentId }))
    XCTAssertFalse(second.cursorReset)

    index.upsert(networkRegistration(agentId: "agent-new", displayName: "Agent New"))
    let resetAfterDirectoryChange = index.search(
      AgentNetworkSearchQuery(pageSize: 25, cursor: second.nextCursor),
      nowMillis: 1_000_000
    )
    XCTAssertTrue(resetAfterDirectoryChange.cursorReset)

    let reputation = AgentReputationSnapshot(
      agentId: "agent-new",
      score: 92,
      confidence: 60,
      reliability: 92,
      quality: 92,
      timeliness: 92,
      costEfficiency: 92,
      evaluatedRuns: 5,
      independentlyVerifiedRuns: 5,
      disputedRuns: 0,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: 65
    )
    let pageBeforeReputationChange = index.search(query, nowMillis: 1_000_000)
    index.replaceReputations(["agent-new": reputation], revision: 7)
    let resetAfterReputationChange = index.search(
      AgentNetworkSearchQuery(pageSize: 25, cursor: pageBeforeReputationChange.nextCursor),
      nowMillis: 1_000_000
    )
    XCTAssertTrue(resetAfterReputationChange.cursorReset)
    XCTAssertTrue(resetAfterReputationChange.revision > pageBeforeReputationChange.revision)
  }

  func testAgentNetworkSearchUsesReputationButDoesNotBlockColdStart() {
    let proven = AgentReputationSnapshot(
      agentId: "z-proven",
      score: 94,
      confidence: 63,
      reliability: 94,
      quality: 94,
      timeliness: 94,
      costEfficiency: 94,
      evaluatedRuns: 5,
      independentlyVerifiedRuns: 5,
      disputedRuns: 0,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: 73
    )
    let poor = AgentReputationSnapshot(
      agentId: "a-poor",
      score: 31,
      confidence: 80,
      reliability: 31,
      quality: 31,
      timeliness: 31,
      costEfficiency: 31,
      evaluatedRuns: 8,
      independentlyVerifiedRuns: 0,
      disputedRuns: 8,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: -109
    )
    let index = AgentNetworkIndex(
      [
        networkRegistration(agentId: "a-new", displayName: "New Agent", capabilities: [.chat, .reasoning]),
        networkRegistration(agentId: "z-proven", displayName: "Proven Agent", capabilities: [.chat, .reasoning]),
        networkRegistration(agentId: "a-poor", displayName: "Poor Agent", capabilities: [.chat, .reasoning])
      ],
      reputations: ["z-proven": proven, "a-poor": poor],
      reputationRevision: 3
    )

    let ranked = index.search(
      AgentNetworkSearchQuery(preferredCapabilities: [.reasoning], pageSize: 10),
      nowMillis: 1_000_000
    )
    let thresholded = index.search(
      AgentNetworkSearchQuery(
        minimumReputationScore: 80,
        minimumReputationConfidence: 40,
        pageSize: 10
      ),
      nowMillis: 1_000_000
    )

    XCTAssertEqual(ranked.hits.first?.registration.agentId, "z-proven")
    XCTAssertTrue(ranked.hits.first?.reasons.contains("reputation:94") == true)
    XCTAssertTrue(thresholded.hits.contains { $0.registration.agentId == "a-new" })
    XCTAssertFalse(thresholded.hits.contains { $0.registration.agentId == "a-poor" })
  }

  func testAgentNetworkSearchModelsUseAndroidWireNames() throws {
    let registration = networkRegistration(agentId: "codex.office", displayName: "Codex Office")
    let index = AgentNetworkIndex([registration])
    let page = index.search(
      AgentNetworkSearchQuery(
        text: "codex",
        requiredCapabilities: [.chat],
        preferredCapabilities: [.code],
        trustedOnly: true,
        maximumCost: .low,
        pageSize: 10
      ),
      nowMillis: 1_000_000
    )
    let pageObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any]
    )
    let registrationObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any]
    )

    XCTAssertEqual(registrationObject["agent_id"] as? String, "codex.office")
    XCTAssertEqual(registrationObject["installation_id"] as? String, "installation-codex.office")
    XCTAssertEqual(registrationObject["provider_id"] as? String, "desktop-provider")
    XCTAssertEqual(registrationObject["display_name"] as? String, "Codex Office")
    XCTAssertEqual(registrationObject["connection_kind"] as? String, "SIGNALASI_LINK")
    XCTAssertEqual(registrationObject["last_heartbeat_millis"] as? Int, 0)
    XCTAssertNil(registrationObject["agentId"])
    XCTAssertEqual(pageObject["query_id"] as? String, page.queryId)
    XCTAssertEqual(pageObject["total_matches"] as? Int, 1)
    XCTAssertEqual(pageObject["next_cursor"] as? String, "")
    XCTAssertEqual(pageObject["cursor_reset"] as? Bool, false)
    XCTAssertEqual(pageObject["generated_at_millis"] as? Int, 1_000_000)
    XCTAssertNil(pageObject["totalMatches"])
  }

  func testProviderProfileCatalogContainsAndroidModelProviders() {
    XCTAssertEqual(
      Set(ProviderProfileCatalog.modelProviders.map(\.providerId)),
      Set(["openai", "anthropic", "gemini", "deepseek", "qwen", "ollama", "lm-studio", "openrouter"])
    )
    XCTAssertTrue(ProviderProfileCatalog.modelProviders.allSatisfy { $0.contextWindowTokens > 0 })
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Claude"), "anthropic")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Google Gemini"), "gemini")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("dashscope"), "qwen")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Open Router"), "openrouter")
  }

  func testProviderProfileCatalogBuildsCloudAndLocalModelProfiles() {
    let deepseek = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:deepseek",
      provider: "DeepSeek",
      displayName: "DeepSeek V4",
      model: providerCloudModel(
        provider: "DeepSeek",
        modelId: "deepseek-v4-pro",
        endpoint: "https://api.deepseek.com/chat/completions"
      ),
      apiKey: "stored-key",
      status: .available,
      performance: ProviderPerformanceProfile(
        attempts: 10,
        successes: 8,
        failures: 2,
        failureRate: 0.2,
        ewmaLatencyMs: 1_100
      )
    )

    XCTAssertEqual(deepseek.profileId, "model:deepseek")
    XCTAssertEqual(deepseek.kind, .cloudModel)
    XCTAssertEqual(deepseek.location, .cloud)
    XCTAssertEqual(deepseek.modelId, "deepseek-v4-pro")
    XCTAssertEqual(deepseek.contextWindowTokens, 128_000)
    XCTAssertEqual(deepseek.maxParallelRuns, 4)
    XCTAssertEqual(deepseek.quality, .frontier)
    XCTAssertEqual(deepseek.pricing.tier, .low)
    XCTAssertTrue(deepseek.credentialConfigured)
    XCTAssertTrue(deepseek.supportsTools)
    XCTAssertTrue(deepseek.supportsStreaming)
    XCTAssertTrue(deepseek.supportsBackground)
    XCTAssertTrue(deepseek.capabilities.isSuperset(of: Set([.chat, .reasoning, .toolUse, .liveData])))
    XCTAssertEqual(deepseek.performance.failures, 2)

    let ollama = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:ollama",
      provider: "Ollama",
      model: providerCloudModel(
        provider: "Ollama",
        modelId: "llama3",
        endpoint: "http://localhost:11434/v1/chat/completions"
      )
    )

    XCTAssertEqual(ollama.displayName, "Ollama")
    XCTAssertEqual(ollama.kind, .localModel)
    XCTAssertEqual(ollama.location, .privateNetwork)
    XCTAssertEqual(ollama.trust, .privateConfigured)
    XCTAssertEqual(ollama.maxParallelRuns, 2)
    XCTAssertEqual(ollama.pricing.tier, .free)
    XCTAssertTrue(ollama.credentialConfigured)
    XCTAssertTrue(ollama.capabilities.contains(.localInference))
    XCTAssertFalse(ollama.supportsTools)
  }

  func testProviderProfileModelsRoundTripAndroidWireNamesAndNoCredentials() throws {
    var profile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:openai",
      provider: "OpenAI",
      model: providerCloudModel(
        provider: "OpenAI",
        modelId: "gpt-5.4-mini",
        endpoint: "https://api.openai.com/v1/chat/completions"
      ),
      apiKey: "private-secret",
      performance: ProviderPerformanceProfile(attempts: 3, successes: 2, failures: 1, ewmaLatencyMs: 940)
    )
    profile.pricing = ProviderPricingProfile(
      tier: profile.pricing.tier,
      inputMicrosPerMillionTokens: 200_000,
      outputMicrosPerMillionTokens: 600_000,
      source: "catalog_estimate"
    )
    let encoded = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let pricing = try XCTUnwrap(object["pricing"] as? [String: Any])
    let performance = try XCTUnwrap(object["performance"] as? [String: Any])
    let capabilities = try XCTUnwrap(object["capabilities"] as? [String])
    let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    let restored = try JSONDecoder().decode(ProviderProfile.self, from: encoded)

    XCTAssertEqual(object["schema_version"] as? Int, ProviderProfile.schemaVersion)
    XCTAssertEqual(object["profile_id"] as? String, "model:openai")
    XCTAssertEqual(object["resource_id"] as? String, "cloud:openai")
    XCTAssertEqual(object["kind"] as? String, "cloud_model")
    XCTAssertEqual(object["location"] as? String, "cloud")
    XCTAssertEqual(object["status"] as? String, "available")
    XCTAssertEqual(object["quality_tier"] as? String, "frontier")
    XCTAssertEqual(object["protocol_family"] as? String, "openai")
    XCTAssertEqual(object["credential_configured"] as? Bool, true)
    XCTAssertNil(object["profileId"])
    XCTAssertEqual(pricing["tier"] as? String, "medium")
    XCTAssertEqual(pricing["input_micros_per_million_tokens"] as? Int, 200_000)
    XCTAssertEqual(pricing["output_micros_per_million_tokens"] as? Int, 600_000)
    XCTAssertNotNil(performance["ewma_latency_ms"])
    XCTAssertTrue(capabilities.contains("live_data"))
    XCTAssertFalse(json.contains("private-secret"))
    XCTAssertEqual(restored, profile)

    let minimal = try JSONDecoder().decode(
      ProviderProfile.self,
      from: Data(
        #"{"schema_version":1,"profile_id":"model:future","resource_id":"cloud:future","provider_id":"future","product_id":"future","display_name":"Future","kind":"future","location":"private_network","status":"ready","pricing":{"tier":"medium"},"performance":{"attempts":2}}"#.utf8
      )
    )

    XCTAssertEqual(minimal.kind, .agent)
    XCTAssertEqual(minimal.status, .available)
    XCTAssertEqual(minimal.location, .privateNetwork)
    XCTAssertEqual(minimal.pricing.tier, .medium)
    XCTAssertEqual(minimal.performance.attempts, 2)
    XCTAssertEqual(minimal.performance.failures, 0)
  }

  func testProviderProfileCatalogBuildsAgentAndTargetProfiles() throws {
    let registration = networkRegistration(
      agentId: "desktop_a:codex",
      displayName: "Codex Workstation",
      providerId: "desktop_a",
      capabilities: [.chat, .code, .taskExecution, .toolUse],
      cost: .low,
      latency: .fast,
      failureDomain: "desktop_a",
      adapterType: "codex-app-server"
    )
    let profile = ProviderProfileCatalog.fromRegistration(registration)

    XCTAssertEqual(profile.profileId, "agent:desktop_a:codex")
    XCTAssertEqual(profile.productId, "codex")
    XCTAssertEqual(profile.providerId, "desktop_a")
    XCTAssertEqual(profile.kind, .agent)
    XCTAssertEqual(profile.location, .trustedDesktop)
    XCTAssertEqual(profile.status, .available)
    XCTAssertEqual(profile.adapterType, "codex-app-server")
    XCTAssertEqual(profile.pricing.tier, .low)
    XCTAssertTrue(profile.supportsTools)
    XCTAssertTrue(profile.supportsBackground)

    let embedded = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:qwen",
      provider: "Qwen",
      model: providerCloudModel(
        provider: "Qwen",
        modelId: "qwen3.7-max",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      ),
      apiKey: "stored-key"
    )
    let target = AgentCallableTarget(
      id: "cloud:qwen",
      title: "Qwen",
      kind: .model,
      status: .available,
      capabilities: Array(embedded.capabilities),
      providerProfile: embedded
    )
    let inferred = ProviderProfileCatalog.fromTarget(
      AgentCallableTarget(
        id: "codex",
        title: "Codex",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .taskExecution],
        failureDomain: "desktop_a",
        adapterType: "codex-app-server"
      )
    )
    let targetObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any]
    )

    XCTAssertEqual(ProviderProfileCatalog.fromTarget(target), embedded)
    XCTAssertNotNil(targetObject["provider_profile"])
    XCTAssertNil(targetObject["providerProfile"])
    XCTAssertEqual(inferred.kind, .agent)
    XCTAssertEqual(inferred.location, .trustedDesktop)
    XCTAssertEqual(inferred.trust, .verifiedPaired)
    XCTAssertTrue(inferred.supportsBackground)
  }

  func testAgentConnectorRouteSelectorSelectsCodexWhenPhoneToolIsTopScoredResource() throws {
    let codex = routeTarget("codex", kind: .agent)
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(phoneWeb, score: 900),
      fallbacks: [resourceCandidate(codexResource, score: 800)],
      catalog: [phoneWeb, codexResource]
    )

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [codex], decision: decision))

    XCTAssertEqual(selected.target.id, codex.id)
    XCTAssertEqual(selected.decision?.primary?.resource.targetId, codex.id)
    XCTAssertEqual(selected.decision?.orderedTargetIds, [codex.id])
  }

  func testAgentConnectorRouteSelectorUsesOnlyConnectorFallbacks() throws {
    let codex = routeTarget("codex", kind: .agent)
    let cloud = routeTarget("cloud-model:deepseek", kind: .model)
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let cloudResource = routingResource(
      targetId: cloud.id,
      type: .cloudModel,
      location: .cloud
    )
    let decision = routingDecision(
      primary: resourceCandidate(codexResource, score: 900),
      fallbacks: [resourceCandidate(phoneWeb, score: 850), resourceCandidate(cloudResource, score: 700)],
      catalog: [codexResource, phoneWeb, cloudResource]
    )

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [codex, cloud], decision: decision))

    XCTAssertEqual(selected.target.id, codex.id)
    XCTAssertEqual(selected.decision?.fallbacks.map(\.resource.targetId), [cloud.id])
  }

  func testAgentConnectorRouteSelectorHonorsExplicitConnectorPreference() throws {
    let codex = routeTarget("codex", kind: .agent)
    let cloud = routeTarget("cloud-model:deepseek", kind: .model)
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let cloudResource = routingResource(
      targetId: cloud.id,
      type: .cloudModel,
      location: .cloud
    )
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(phoneWeb, score: 950),
      fallbacks: [resourceCandidate(cloudResource, score: 900), resourceCandidate(codexResource, score: 800)],
      catalog: [phoneWeb, cloudResource, codexResource]
    )

    let selected = try XCTUnwrap(
      AgentConnectorRouteSelector.select(
        targets: [codex, cloud],
        decision: decision,
        preferredTargetId: codex.id
      )
    )

    XCTAssertEqual(selected.decision?.primary?.resource.targetId, codex.id)
    XCTAssertEqual(selected.decision?.fallbacks.map(\.resource.targetId), [cloud.id])
  }

  func testAgentConnectorRouteSelectorRecoversReasoningTargetDuringHeartbeat() throws {
    var recovering = routeTarget("codex", kind: .agent)
    recovering.status = .disconnected

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [recovering], decision: nil))

    XCTAssertEqual(selected.target.id, "codex")
    XCTAssertTrue(AgentConnectorRouteSelector.isDeliverable(recovering))
  }

  func testAgentConnectorRouteSelectorRejectsSetupAndDeviceOnlyTargets() {
    var unavailable = routeTarget("codex", kind: .agent)
    unavailable.status = .needsSetup
    let device = AgentCallableTarget(
      id: "device:lamp",
      title: "Lamp",
      kind: .device,
      status: .available,
      capabilities: [.deviceControl]
    )

    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [unavailable], decision: nil))
    XCTAssertFalse(AgentConnectorRouteSelector.isDeliverable(device))
    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [device], decision: nil))
  }

  func testAgentResourceRoutingModelsUseAndroidWireNames() throws {
    let codexResource = routingResource(
      targetId: "codex",
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(codexResource, score: 800),
      fallbacks: [],
      catalog: [codexResource]
    )
    let encoded = try JSONEncoder().encode(decision)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let requirements = try XCTUnwrap(object["requirements"] as? [String: Any])
    let primary = try XCTUnwrap(object["primary"] as? [String: Any])
    let resource = try XCTUnwrap(primary["resource"] as? [String: Any])

    XCTAssertEqual(requirements["live_data_required"] as? Bool, true)
    XCTAssertEqual(requirements["estimated_input_tokens"] as? Int, 200)
    XCTAssertEqual(requirements["execution_horizon"] as? String, "INTERACTIVE")
    XCTAssertEqual(resource["target_id"] as? String, "codex")
    XCTAssertEqual(resource["supports_tools"] as? Bool, false)
    XCTAssertEqual(resource["context_window_tokens"] as? Int, 8_192)
    XCTAssertEqual(resource["max_parallel_tasks"] as? Int, 1)
    XCTAssertNotNil(object["task_budget"])
    XCTAssertNil(resource["targetId"])

    let decoded = try JSONDecoder().decode(
      AgentRoutingDecision.self,
      from: Data(
        #"{"requirements":{"capabilities":["live_data"],"mode":"fast"},"primary":{"resource":{"id":"resource:cloud","title":"Cloud","type":"cloud_model","location":"cloud","status":"available","capabilities":["research"],"cost":"low","latency":"fast","quality":"strong","supports_tools":true,"target_id":"cloud-model:deepseek"},"score":10,"reasons":["capability_match"]}}"#.utf8
      )
    )

    XCTAssertEqual(decoded.requirements.mode, .fast)
    XCTAssertEqual(decoded.requirements.liveDataRequired, true)
    XCTAssertEqual(decoded.requirements.executionHorizon, .interactive)
    XCTAssertEqual(decoded.primary?.resource.type, .cloudModel)
    XCTAssertEqual(decoded.primary?.resource.cost, .low)
    XCTAssertEqual(decoded.primary?.resource.latency, .fast)
    XCTAssertEqual(decoded.primary?.resource.quality, .strong)
    XCTAssertEqual(decoded.fallbacks, [])
  }

  func testAgentResourceCatalogBuildsTargetsToolsAndNativeTools() throws {
    let codex = AgentCallableTarget(
      id: "desktop:codex",
      title: "Codex",
      kind: .agent,
      status: .available,
      capabilities: [.chat, .code, .taskExecution, .toolUse],
      failureDomain: "desktop-dev",
      adapterType: "codex-app-server"
    )
    let qwenProfile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:qwen",
      provider: "Qwen",
      model: providerCloudModel(
        provider: "Qwen",
        modelId: "qwen3.7-max",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      ),
      apiKey: "stored-key",
      performance: ProviderPerformanceProfile(attempts: 10, successes: 8, failures: 2, failureRate: 0.2)
    )
    let cloud = AgentCallableTarget(
      id: "cloud:qwen",
      title: "Qwen",
      kind: .model,
      status: .available,
      capabilities: Array(qwenProfile.capabilities),
      providerProfile: qwenProfile
    )
    let workflow = AgentSystemTool(
      id: "workflow:daily",
      title: "Daily workflow",
      kind: .draftPlan,
      risk: .low,
      capabilities: [.taskExecution]
    )
    let native = try nativeToolDescriptor(
      "signalasi.runtime.python",
      capabilities: ["runtime.python", "workspace.files"]
    )

    let catalog = AgentResourceCatalog.build(
      targets: [codex, cloud],
      tools: [workflow],
      nativeTools: [native]
    )
    let codexResource = try XCTUnwrap(catalog.first { $0.id == "target:desktop:codex" })
    let cloudResource = try XCTUnwrap(catalog.first { $0.id == "target:cloud:qwen" })
    let workflowResource = try XCTUnwrap(catalog.first { $0.id == "tool:workflow:daily" })
    let nativeResource = try XCTUnwrap(catalog.first { $0.id == "native:\(native.id)" })

    XCTAssertEqual(codexResource.type, .remoteAgent)
    XCTAssertEqual(codexResource.location, .trustedDesktop)
    XCTAssertEqual(codexResource.targetId, codex.id)
    XCTAssertEqual(codexResource.failureDomain, "desktop-dev")
    XCTAssertTrue(codexResource.supportsBackground)
    XCTAssertEqual(cloudResource.contextWindowTokens, qwenProfile.contextWindowTokens)
    XCTAssertEqual(cloudResource.cost, qwenProfile.pricing.tier)
    XCTAssertEqual(cloudResource.latency, qwenProfile.latency)
    XCTAssertEqual(cloudResource.providerProfile?.performance.failureRate, 0.2)
    XCTAssertEqual(workflowResource.type, .localSkill)
    XCTAssertEqual(workflowResource.status, .available)
    XCTAssertEqual(workflowResource.trust, .phoneSystem)
    XCTAssertEqual(workflowResource.energy, .minimal)
    XCTAssertEqual(workflowResource.maxParallelTasks, 4)
    XCTAssertEqual(nativeResource.type, .localTool)
    XCTAssertEqual(nativeResource.energy, .high)
    XCTAssertTrue(nativeResource.supportsBackground)
    XCTAssertTrue(nativeResource.capabilities.isSuperset(of: Set([.toolUse, .code, .taskExecution])))
  }

  func testAgentResourceCatalogMapsCapabilitySnapshotStatus() throws {
    let available = try nativeToolDescriptor("signalasi.test.available")
    let unavailable = try nativeToolDescriptor(
      "signalasi.test.unavailable",
      availability: AgentNativeToolAvailability(status: .unavailable, reason: "Missing")
    )
    let target = AgentCallableTarget(
      id: "codex",
      title: "Codex",
      kind: .agent,
      status: .disconnected,
      capabilities: [.code]
    )

    let catalog = AgentResourceCatalog.build(
      targets: [target],
      tools: [],
      nativeTools: [available, unavailable]
    )

    XCTAssertEqual(catalog.first { $0.id == "target:codex" }?.status, .disconnected)
    XCTAssertEqual(catalog.first { $0.id == "native:\(available.id)" }?.status, .available)
    XCTAssertEqual(catalog.first { $0.id == "native:\(unavailable.id)" }?.status, .disconnected)
  }

  func testAgentResourceCatalogClassifiesRemoteTargets() {
    let targets = [
      AgentCallableTarget(
        id: "home-assistant",
        title: "Home Assistant",
        kind: .device,
        status: .available,
        capabilities: [.smartHome]
      ),
      AgentCallableTarget(
        id: "custom-device:lamp",
        title: "Lamp",
        kind: .device,
        status: .available,
        capabilities: [.deviceControl]
      ),
      AgentCallableTarget(
        id: "remote-mcp:github",
        title: "GitHub MCP",
        kind: .agent,
        status: .available,
        capabilities: [.mcp, .toolUse]
      ),
      AgentCallableTarget(
        id: "remote-skill:summary",
        title: "Summary Skill",
        kind: .agent,
        status: .available,
        capabilities: [.skill, .toolUse]
      ),
      AgentCallableTarget(
        id: "knowledge:docs",
        title: "Docs",
        kind: .knowledge,
        status: .available,
        capabilities: [.knowledgeSearch]
      ),
      AgentCallableTarget(
        id: "local-llm",
        title: "Local LLM",
        kind: .model,
        status: .available,
        capabilities: [.chat, .localInference]
      )
    ]

    let catalog = AgentResourceCatalog.build(targets: targets, tools: [])

    XCTAssertEqual(catalog.first { $0.targetId == "home-assistant" }?.type, .homeAssistant)
    XCTAssertEqual(catalog.first { $0.targetId == "home-assistant" }?.location, .privateNetwork)
    XCTAssertEqual(catalog.first { $0.targetId == "custom-device:lamp" }?.type, .customDevice)
    XCTAssertEqual(catalog.first { $0.targetId == "remote-mcp:github" }?.type, .remoteMcp)
    XCTAssertEqual(catalog.first { $0.targetId == "remote-skill:summary" }?.type, .remoteSkill)
    XCTAssertEqual(catalog.first { $0.targetId == "knowledge:docs" }?.location, .phone)
    XCTAssertEqual(catalog.first { $0.targetId == "local-llm" }?.type, .remoteLocalModel)
    XCTAssertEqual(catalog.first { $0.targetId == "local-llm" }?.maxParallelTasks, 2)
  }

  func testAgentResourceCatalogModelsUseAndroidWireNames() throws {
    let profile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:deepseek",
      provider: "DeepSeek",
      model: providerCloudModel(
        provider: "DeepSeek",
        modelId: "deepseek-v4-pro",
        endpoint: "https://api.deepseek.com/chat/completions"
      ),
      apiKey: "stored-key"
    )
    let catalog = AgentResourceCatalog.build(
      targets: [
        AgentCallableTarget(
          id: "cloud:deepseek",
          title: "DeepSeek",
          kind: .model,
          status: .available,
          capabilities: Array(profile.capabilities),
          providerProfile: profile
        )
      ],
      tools: []
    )
    let resource = try XCTUnwrap(catalog.first)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(resource)) as? [String: Any]
    )

    XCTAssertEqual(object["target_id"] as? String, "cloud:deepseek")
    XCTAssertEqual(object["supports_background"] as? Bool, true)
    XCTAssertEqual(object["max_parallel_tasks"] as? Int, 4)
    XCTAssertNotNil(object["provider_profile"])
    XCTAssertNil(object["targetId"])
    XCTAssertNil(object["supportsBackground"])
  }

  func testAgentTaskRequirementAnalyzerDetectsRestrictedChineseIdentityAndPaymentGoals() {
    let identity = AgentTaskRequirementAnalyzer.analyze(
      "\u{8bf7}\u{8bfb}\u{53d6}\u{6211}\u{7684}\u{8eab}\u{4efd}\u{8bc1}\u{5e76}\u{5b8c}\u{6210}\u{652f}\u{4ed8}"
    )

    XCTAssertEqual(identity.dataSensitivity, .restricted)
  }

  func testAgentTaskRequirementAnalyzerDetectsChineseBackgroundAndLongRunningGoals() {
    let background = AgentTaskRequirementAnalyzer.analyze(
      "\u{5728}\u{540e}\u{53f0}\u{76d1}\u{63a7}\u{4efb}\u{52a1}\u{72b6}\u{6001}"
    )
    let longRunning = AgentTaskRequirementAnalyzer.analyze(
      "\u{6301}\u{7eed}\u{8fd0}\u{884c}\u{76f4}\u{5230}\u{5b8c}\u{6210}"
    )

    XCTAssertEqual(background.executionHorizon, .background)
    XCTAssertEqual(longRunning.executionHorizon, .longRunning)
  }

  func testAgentTaskRequirementAnalyzerKeepsOfflineGoalsPrivate() {
    let requirements = AgentTaskRequirementAnalyzer.analyze("Keep this offline and local only")

    XCTAssertEqual(requirements.mode, .private)
    XCTAssertTrue(requirements.localOnly)
    XCTAssertEqual(requirements.dataSensitivity, .confidential)
  }

  func testAgentTaskRequirementAnalyzerClassifiesLiveCodeAndToolNeeds() {
    let live = AgentTaskRequirementAnalyzer.analyze("What is the current weather in Shanghai today?")
    let code = AgentTaskRequirementAnalyzer.analyze("Debug C:\\Temp\\next.py and test the program")

    XCTAssertTrue(live.liveDataRequired)
    XCTAssertTrue(live.capabilities.isSuperset(of: Set([.liveData, .research, .toolUse])))
    XCTAssertGreaterThan(live.estimatedInputTokens, 0)
    XCTAssertTrue(code.complexReasoning)
    XCTAssertTrue(code.capabilities.isSuperset(of: Set([.code, .taskExecution, .reasoning])))
  }

  func testAgentPhoneCapabilityCatalogCoversEveryCapabilityWithHonestBoundary() {
    let capabilities = AgentPhoneCapabilityCatalog.capabilities

    XCTAssertEqual(Set(AgentPhoneCapabilityId.allCases), Set(capabilities.map(\.id)))
    XCTAssertEqual(capabilities.count, Set(capabilities.map(\.id)).count)
    XCTAssertEqual("phone.accessibility.ui.tree", AgentPhoneCapabilityId.accessibilityUITree.wireId)
    capabilities.forEach { capability in
      XCTAssertFalse(capability.userConsent.isEmpty, "\(capability.id) must declare user-consent requirements")
      XCTAssertFalse(capability.limitation.isEmpty, "\(capability.id) must state an honest limitation")
      XCTAssertNotEqual("none", capability.limitation.lowercased())
    }
  }

  func testAgentPhoneCapabilityPolicyNeverPromotesBlockedOrPrivilegedCapabilities() {
    let permissiveObservation = AgentPhoneCapabilityObservation(
      platformSupported: true,
      implementationPresent: true,
      permissionsGranted: true,
      specialAccessGranted: true,
      userConsentGranted: true,
      configured: true
    )
    let blocked = AgentPhoneCapabilityCatalog.find(.root)
    let blockedAvailability = AgentPhoneCapabilityPolicy.resolve(blocked, observation: permissiveObservation)
    let blockedStatus = AgentPhoneCapabilityStatus(
      boundary: blocked,
      availability: blockedAvailability,
      evidence: "permissive test probe"
    )

    XCTAssertEqual(blockedAvailability, .blockedByPolicy)
    XCTAssertFalse(blockedStatus.advertisedAsReady)
    let privileged = AgentPhoneCapabilityCatalog.capabilities.filter { !$0.normalAppCanExecute }
    XCTAssertFalse(privileged.isEmpty)
    privileged.forEach { boundary in
      let availability = AgentPhoneCapabilityPolicy.resolve(boundary, observation: permissiveObservation)
      let status = AgentPhoneCapabilityStatus(boundary: boundary, availability: availability, evidence: "permissive")
      XCTAssertNotEqual(availability, .ready)
      XCTAssertFalse(status.advertisedAsReady)
    }
  }

  func testAgentPhoneCapabilityPolicyReportsRuntimeAndConfigurationGates() {
    let camera = AgentPhoneCapabilityCatalog.find(.camera)
    let location = AgentPhoneCapabilityCatalog.find(.location)
    let transcode = AgentPhoneCapabilityCatalog.find(.mediaTranscode)

    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(camera, observation: AgentPhoneCapabilityObservation(permissionsGranted: false)),
      .needsRuntimePermission
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(camera, observation: AgentPhoneCapabilityObservation()),
      .ready
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(location, observation: AgentPhoneCapabilityObservation()),
      .ready
    )
    XCTAssertEqual(
      AgentPhoneCapabilityPolicy.resolve(transcode, observation: AgentPhoneCapabilityObservation(configured: false)),
      .needsConfiguration
    )
  }

  func testAgentPhoneCapabilityNativeCoverageUsesStableAndroidToolIds() {
    let expected: Set<AgentPhoneCapabilityId> = [
      .notificationRead,
      .notificationReply,
      .camera,
      .microphone,
      .location,
      .sensors,
      .bluetooth,
      .nfc,
      .battery,
      .network,
      .installedApps,
      .mediaPlayback,
      .mediaTranscode
    ]

    XCTAssertEqual(expected, Set(AgentPhoneCapabilityNativeCoverage.toolIdsByCapability.keys))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.toolIdsByCapability.values.allSatisfy { !$0.isEmpty })
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.isImplemented(.camera))
    XCTAssertFalse(AgentPhoneCapabilityNativeCoverage.isImplemented(.root))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.coveredToolIds.contains("signalasi.camera.capture.visible"))
    XCTAssertTrue(AgentPhoneCapabilityNativeCoverage.coveredToolIds.contains("signalasi.media.ffmpeg.transcode"))
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.sensors).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.bluetooth).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.nfc).availability, .limited)
    XCTAssertEqual(AgentPhoneCapabilityCatalog.find(.mediaTranscode).availability, .needsConfiguration)
  }

  func testAgentPhoneCapabilityModelsUseAndroidWireNames() throws {
    let boundary = AgentPhoneCapabilityCatalog.find(.camera)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(boundary)) as? [String: Any]
    )
    let observation = AgentPhoneCapabilityObservation(
      probeSucceeded: false,
      implementationPresent: false,
      permissionsGranted: false,
      evidence: "camera unavailable"
    )
    let observationObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any]
    )

    XCTAssertEqual(object["id"] as? String, "CAMERA")
    XCTAssertEqual(object["execution_location"] as? String, "APP_PROCESS")
    XCTAssertEqual(object["availability"] as? String, "NEEDS_RUNTIME_PERMISSION")
    XCTAssertNotNil(object["platform_permissions"])
    XCTAssertNil(object["executionLocation"])
    XCTAssertNil(object["platformPermissions"])
    XCTAssertEqual(observationObject["probe_succeeded"] as? Bool, false)
    XCTAssertEqual(observationObject["implementation_present"] as? Bool, false)
    XCTAssertEqual(observationObject["permissions_granted"] as? Bool, false)
    XCTAssertNil(observationObject["probeSucceeded"])
  }

  func testAgentIOSSystemNativeToolCatalogMirrorsAndroidSystemIdsWithIOSBoundaries() throws {
    let ids = AgentIOSSystemNativeToolCatalog.toolIds
    let definitions = AgentIOSSystemNativeToolCatalog.definitions()

    XCTAssertEqual(ids.count, 32)
    XCTAssertEqual(Set(AgentIOSSystemNativeToolCatalog.orderedToolIds), ids)
    XCTAssertEqual(Set(definitions.map(\.id)), ids)
    XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("signalasi.android.") })
    XCTAssertTrue(ids.allSatisfy { !$0.contains(" ") })
    [
      ".telephony.", ".sms.", ".contacts.", ".calendar.", ".wifi.",
      ".audio.", ".download.", ".biometric.", ".vpn.", ".device_policy."
    ].forEach { domain in
      XCTAssertTrue(ids.contains { $0.contains(domain) }, "Missing \(domain) tools")
    }

    definitions.forEach { definition in
      let descriptor = definition.descriptor
      XCTAssertEqual(definition.executorId, AgentIOSSystemNativeToolCatalog.executorId)
      XCTAssertEqual(descriptor.location, .androidSystem)
      if AgentIOSSystemNativeToolCatalog.handoffToolIds.contains(descriptor.id) {
        XCTAssertEqual(descriptor.availability.status, .available)
        XCTAssertTrue(descriptor.availability.reason.contains("handoff request"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "handoff_request_on_ios15")
      } else {
        XCTAssertEqual(descriptor.availability.status, .unavailable)
        XCTAssertTrue(descriptor.availability.reason.contains("iOS 15+ app sandbox"), descriptor.id)
        XCTAssertEqual(definition.provenanceMetadata["execution_policy"], "descriptor_only_unavailable_on_ios15")
      }
      XCTAssertTrue(descriptor.requiredPermissions.contains {
        $0.id == AgentIOSSystemNativeToolCatalog.androidSystemPermission
      }, descriptor.id)
      XCTAssertTrue(descriptor.requiredConsents.contains {
        $0.id == AgentIOSSystemNativeToolCatalog.compatibilityConsent
      }, descriptor.id)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios")
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentAndroidSystemNativeTools")
    }

    let smsSend = try XCTUnwrap(definitions.first { $0.id == AgentIOSSystemNativeToolCatalog.smsSend })
    XCTAssertEqual(smsSend.descriptor.risk, .high)
    XCTAssertEqual(smsSend.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(smsSend.descriptor.requiredPermissions.contains { $0.id == "android.permission.SEND_SMS" })
    XCTAssertTrue(smsSend.descriptor.requiredConsents.contains { $0.id == "signalasi.consent.sms.send" })
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("phone_number")))
    XCTAssertTrue((smsSend.descriptor.inputSchema["required"]?.arrayValue ?? []).contains(.string("message")))

    let registry = try AgentNativeToolRegistry(definitions: definitions)
    let unavailable = registry.authorize(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: [
        "phone_number": .string("+15551234567"),
        "message": .string("hello")
      ],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "sms-1",
        grantedPermissions: [
          AgentIOSSystemNativeToolCatalog.androidSystemPermission,
          "android.permission.SEND_SMS"
        ],
        grantedConsents: ["signalasi.consent.sms.send"]
      )
    )
    let invalid = registry.validateInput(
      AgentIOSSystemNativeToolCatalog.smsSend,
      input: ["phone_number": .string("+15551234567")]
    )

    XCTAssertEqual(unavailable.code, "tool_unavailable")
    XCTAssertFalse(unavailable.allowed)
    XCTAssertFalse(invalid.isValid)
  }

  func testAgentIOSSystemNativeToolExecutorBuildsUserVisibleHandoffs() throws {
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.systemExecutableDefinitions()
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSystemNativeToolCatalog.androidSystemPermission]
    )

    let dial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("+1 (555) 123-4567")],
      context: context
    )
    let sms = registry.invoke(
      AgentIOSSystemNativeToolCatalog.smsComposeHandoff,
      input: [
        "phone_number": .string("+1-555-123-4567"),
        "message": .string("hello")
      ],
      context: context
    )
    let wifi = registry.invoke(
      AgentIOSSystemNativeToolCatalog.wifiPanelOpen,
      input: [:],
      context: context
    )
    let invalidDial = registry.invoke(
      AgentIOSSystemNativeToolCatalog.telephonyDialHandoff,
      input: ["phone_number": .string("call-me")],
      context: context
    )

    XCTAssertEqual(registry.ids(), AgentIOSSystemNativeToolCatalog.handoffToolIds)
    XCTAssertTrue(dial.isSuccess)
    XCTAssertEqual(dial.output["handoff_kind"], .string("dial"))
    XCTAssertEqual(dial.output["url"], .string("tel:+15551234567"))
    XCTAssertEqual(dial.output["requires_user_action"], .bool(true))
    XCTAssertEqual(dial.output["completion_untrusted"], .bool(true))
    XCTAssertEqual(dial.provenance.executorId, AgentIOSSystemNativeToolCatalog.executorId)

    XCTAssertTrue(sms.isSuccess)
    XCTAssertEqual(sms.output["handoff_kind"], .string("sms_compose"))
    XCTAssertEqual(sms.output["url"], .string("sms:+15551234567"))
    XCTAssertEqual(sms.output["prefill_body"], .string("hello"))
    XCTAssertEqual(sms.output["body_in_url"], .bool(false))

    XCTAssertTrue(wifi.isSuccess)
    XCTAssertEqual(wifi.output["handoff_kind"], .string("settings"))
    XCTAssertEqual(wifi.output["url"], .string("app-settings:"))
    XCTAssertEqual(wifi.output["settings_target"], .string("wifi"))

    XCTAssertEqual(invalidDial.status, .failed)
    XCTAssertEqual(invalidDial.error?.code, "invalid_phone_number")
  }

  func testAgentIOSHardwareNativeToolCatalogAndExecutorExposeAppVisibleStatus() throws {
    struct FakeHardwareProvider: AgentIOSHardwareStatusProviding {
      func batteryStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "percent": .int(73),
          "charging": .bool(true),
          "plugged": .string("usb"),
          "status": .string("charging"),
          "health": .string("unknown"),
          "scope": .string("app_visible_ios"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func powerStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "interactive": .bool(true),
          "low_power_mode": .bool(false),
          "thermal_state": .string("nominal"),
          "settings_changed": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func storageStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "scope": .string("app_private_volume"),
          "total_bytes": .int(1_000),
          "available_bytes": .int(300),
          "used_bytes": .int(700),
          "low_storage": .bool(false),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }

      func networkStatus(nowMillis: Int64) -> AgentMcpJSONObject {
        [
          "connected": .bool(true),
          "validated": .bool(true),
          "metered": .bool(false),
          "roaming": .bool(false),
          "transports": .array([.string("wifi")]),
          "identifiers_included": .bool(false),
          "scope": .string("app_visible_ios"),
          "observed_at_epoch_ms": .int(nowMillis)
        ]
      }
    }

    let ids = AgentIOSHardwareNativeToolCatalog.toolIds
    let definitions = AgentIOSHardwareNativeToolCatalog.definitions()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.hardwareExecutableDefinitions(
        executor: AgentIOSHardwareNativeToolExecutor(provider: FakeHardwareProvider(), nowMillis: { 4_200 })
      )
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSHardwareNativeToolCatalog.hardwareStatusPermission],
      grantedConsents: [AgentIOSHardwareNativeToolCatalog.userVisibleHandoffConsent]
    )

    XCTAssertEqual(ids.count, 14)
    XCTAssertEqual(Set(AgentIOSHardwareNativeToolCatalog.orderedToolIds), ids)
    XCTAssertEqual(Set(definitions.map(\.id)), ids)
    XCTAssertEqual(registry.ids(), AgentIOSHardwareNativeToolCatalog.executableToolIds)
    XCTAssertTrue(ids.contains(AgentIOSHardwareNativeToolCatalog.storageStatus))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSHardwareNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentHardwareNativeTools")
      XCTAssertEqual(definition.provenanceMetadata["background_capture"], "false")
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty, definition.id)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty, definition.id)
    }

    let battery = registry.invoke(AgentIOSHardwareNativeToolCatalog.batteryStatus, input: [:], context: context)
    let power = registry.invoke(AgentIOSHardwareNativeToolCatalog.powerStatus, input: [:], context: context)
    let storage = registry.invoke(AgentIOSHardwareNativeToolCatalog.storageStatus, input: [:], context: context)
    let network = registry.invoke(AgentIOSHardwareNativeToolCatalog.networkStatus, input: [:], context: context)
    let pairing = registry.invoke(AgentIOSHardwareNativeToolCatalog.bluetoothPairingHandoff, input: [:], context: context)
    let location = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSHardwareNativeToolCatalog.locationForegroundRead }
    )

    XCTAssertTrue(battery.isSuccess)
    XCTAssertEqual(battery.output["percent"], .int(73))
    XCTAssertEqual(battery.output["observed_at_epoch_ms"], .int(4_200))
    XCTAssertTrue(power.isSuccess)
    XCTAssertEqual(power.output["thermal_state"], .string("nominal"))
    XCTAssertTrue(storage.isSuccess)
    XCTAssertEqual(storage.output["used_bytes"], .int(700))
    XCTAssertTrue(network.isSuccess)
    XCTAssertEqual(network.output["identifiers_included"], .bool(false))
    XCTAssertTrue(pairing.isSuccess)
    XCTAssertEqual(pairing.output["settings_target"], .string("bluetooth"))
    XCTAssertEqual(pairing.output["completion_untrusted"], .bool(true))
    XCTAssertEqual(location.descriptor.availability.status, .unavailable)
    XCTAssertEqual(location.descriptor.risk, .high)
  }

  func testAgentIOSHomeAssistantNativeToolCatalogAndExecutorPreserveSecretSafePolicy() throws {
    struct FakeHomeAssistantProvider: AgentIOSHomeAssistantToolProviding {
      var implementationId = "fake.ios.home_assistant"
      var verified = true

      func availability() -> AgentNativeToolAvailability { .available }

      func connectionStatus(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "connected": .bool(true),
            "credentials_exposed": .bool(false),
            "checked_at_epoch_ms": .int(nowMillis)
          ],
          message: "Connected"
        )
      }

      func listEntities(query: String, domains: [String], limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "entities": .array([.object([
              "entity_id": .string("light.office"),
              "friendly_name": .string("Office"),
              "state": .string("on"),
              "domain": .string("light"),
              "protected": .bool(false)
            ])]),
            "result_count": .int(1),
            "total_matched": .int(1),
            "truncated": .bool(false),
            "observed_at_epoch_ms": .int(nowMillis),
            "protected_state_count": .int(0)
          ],
          message: "Entities listed",
          metadata: ["query": .string(query), "domain_count": .int(Int64(domains.count))]
        )
      }

      func readEntity(entityId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "entity": .object([
              "entity_id": .string(entityId),
              "friendly_name": .string("Office"),
              "state": .string("on"),
              "domain": .string("light"),
              "protected": .bool(false)
            ]),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Entity read"
        )
      }

      func callService(
        serviceDomain: String,
        service: String,
        entityId: String,
        serviceData: AgentMcpJSONObject,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "request_accepted": .bool(true),
            "service_domain": .string(serviceDomain),
            "service": .string(service),
            "entity_id": .string(entityId),
            "verification_supported": .bool(true),
            "controller_state_observed": .bool(true),
            "controller_state_verified": .bool(verified),
            "previous_state": .string("off"),
            "current_state": .string(verified ? "on" : "off"),
            "state_protected": .bool(false),
            "changed_state_count": .int(verified ? 1 : 0),
            "physical_outcome_verified": .bool(false)
          ],
          message: "Service accepted",
          metadata: ["single_entity_scope": .bool(true)]
        )
      }
    }

    func serviceInput(
      _ serviceDomain: String,
      _ service: String,
      _ entityId: String,
      serviceData: AgentMcpJSONObject = [:]
    ) -> AgentMcpJSONObject {
      [
        "service_domain": .string(serviceDomain),
        "service": .string(service),
        "entity_id": .string(entityId),
        "service_data": .object(serviceData)
      ]
    }

    let definitions = AgentIOSHomeAssistantNativeToolCatalog.definitions(provider: FakeHomeAssistantProvider())
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.homeAssistantExecutableDefinitions(
        provider: FakeHomeAssistantProvider(),
        nowMillis: { 7_000 }
      )
    )
    let readContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.readConsent]
    )
    let controlContext = AgentNativeToolInvocationContext(
      invocationId: "ha-service",
      idempotencyKey: "ha-service-1",
      grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSHomeAssistantNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["credential_exposure"], "none")
      XCTAssertEqual(definition.provenanceMetadata["access_token_exposed"], "false")
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentIOSHomeAssistantNativeToolCatalog.networkPermission])
    }
    let connection = try XCTUnwrap(definitions.first { $0.id == AgentIOSHomeAssistantNativeToolCatalog.connectionStatus })
    let serviceDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSHomeAssistantNativeToolCatalog.serviceCall })
    XCTAssertEqual(connection.descriptor.requiredConsents.map(\.id), ["signalasi.consent.none"])
    XCTAssertFalse(connection.descriptor.requiredConsents.first?.required ?? true)
    XCTAssertEqual(serviceDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(serviceDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSHomeAssistantNativeToolCatalog.controlConsent])

    let deniedList = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entitiesList,
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission]
      )
    )
    let listed = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entitiesList,
      input: [
        "query": .string("office"),
        "domains": .array([.string("light")]),
        "limit": .int(5)
      ],
      context: readContext
    )
    let read = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entityRead,
      input: ["entity_id": .string("light.office")],
      context: readContext
    )
    let missingKey = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office"),
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )
    let service = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office"),
      context: controlContext
    )
    let mismatch = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("switch", "turn_on", "light.office"),
      context: AgentNativeToolInvocationContext(
        invocationId: "ha-mismatch",
        idempotencyKey: "ha-mismatch",
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )
    let secret = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office", serviceData: ["access_token": .string("secret")]),
      context: AgentNativeToolInvocationContext(
        invocationId: "ha-secret",
        idempotencyKey: "ha-secret",
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )

    XCTAssertEqual(deniedList.status, .rejected)
    XCTAssertEqual(deniedList.error?.code, "missing_consents")
    XCTAssertTrue(listed.isSuccess)
    XCTAssertEqual(listed.metadata["access_token_exposed"], .bool(false))
    XCTAssertEqual((listed.output["entities"]?.arrayValue ?? []).count, 1)
    XCTAssertTrue(read.isSuccess)
    XCTAssertEqual(read.output["observed_at_epoch_ms"], .int(7_000))
    XCTAssertEqual(missingKey.status, .rejected)
    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(service.isSuccess)
    XCTAssertEqual(service.verification?.status, .passed)
    XCTAssertEqual(service.output["physical_outcome_verified"], .bool(false))
    XCTAssertEqual(mismatch.status, .failed)
    XCTAssertEqual(mismatch.error?.code, "domain_mismatch")
    XCTAssertEqual(secret.status, .failed)
    XCTAssertEqual(secret.error?.code, "invalid_service_data")
  }

  func testAgentIOSNotificationNativeToolCatalogAndExecutorRedactsAndRepliesHonestly() throws {
    final class FakeNotificationProvider: AgentIOSNotificationToolProviding {
      var implementationId = "fake.ios.notification"
      var replyCalls = 0
      var replyResult = AgentIOSNotificationReplyResult(
        success: true,
        message: "Reply dispatched",
        code: "notification_reply_dispatched",
        notificationPackage: "com.example.chat",
        notificationTitle: "Example"
      )

      func availability() -> AgentNativeToolAvailability { .available }

      func snapshot(limit: Int) -> AgentIOSNotificationContext {
        AgentIOSNotificationContext(
          hasAccess: true,
          items: [
            AgentIOSNotificationItem(
              key: "normal-key",
              packageName: "com.example.chat",
              title: "Build",
              textPreview: "Ready",
              category: "chat",
              postedAtMillis: 100,
              canReply: true
            ),
            AgentIOSNotificationItem(
              key: "secret-key",
              packageName: "com.example.auth",
              title: "Verification code",
              textPreview: "Code 123456",
              category: "sms",
              postedAtMillis: 90,
              canReply: true,
              sensitiveFlags: ["verification_code"]
            )
          ].prefix(limit).map { $0 },
          sensitiveFlags: ["verification_code"],
          totalCount: 2
        )
      }

      func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
        replyCalls += 1
        return replyResult
      }
    }

    let provider = FakeNotificationProvider()
    let definitions = AgentIOSNotificationNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.notificationExecutableDefinitions(
        provider: provider,
        nowMillis: { 8_000 }
      )
    )
    let listContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
      grantedConsents: [AgentIOSNotificationNativeToolCatalog.readConsent]
    )
    let replyContext = AgentNativeToolInvocationContext(
      invocationId: "reply-first",
      idempotencyKey: "reply-once",
      grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
      grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSNotificationNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSNotificationNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSNotificationNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["sensitive_content_policy"], "redact")
      XCTAssertEqual(definition.provenanceMetadata["reply_completion_semantics"], "reply_action_dispatched_not_delivered")
      XCTAssertEqual(definition.descriptor.risk, .high)
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission])
    }

    let listed = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationsList,
      input: ["limit": .int(12)],
      context: listContext
    )
    let deniedReply = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-denied",
        idempotencyKey: "reply-denied",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission]
      )
    )
    let firstReply = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: replyContext
    )
    let replay = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("reply-key"),
        "reply_text": .string("Hello")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-replay",
        idempotencyKey: "reply-once",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
        grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
      )
    )
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(provider.replyCalls, 1)
    provider.replyResult = AgentIOSNotificationReplyResult(
      success: false,
      message: "The notification is no longer available",
      code: "notification_stale",
      retryable: true,
      notificationPackage: "com.example.chat"
    )
    let stale = registry.invoke(
      AgentIOSNotificationNativeToolCatalog.notificationReply,
      input: [
        "notification_key": .string("stale-key"),
        "reply_text": .string("Secret reply")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "reply-stale",
        idempotencyKey: "reply-stale",
        grantedPermissions: [AgentIOSNotificationNativeToolCatalog.notificationAccessPermission],
        grantedConsents: [AgentIOSNotificationNativeToolCatalog.replyConsent]
      )
    )

    XCTAssertTrue(listed.isSuccess)
    let notifications = listed.output["notifications"]?.arrayValue ?? []
    XCTAssertEqual(notifications.count, 2)
    let normal = notifications[0].objectValue ?? [:]
    let sensitive = notifications[1].objectValue ?? [:]
    XCTAssertEqual(normal["text_preview"], .string("Ready"))
    XCTAssertEqual(normal["redacted"], .bool(false))
    XCTAssertEqual(sensitive["notification_key"], .string(""))
    XCTAssertEqual(sensitive["title"], .string(""))
    XCTAssertEqual(sensitive["text_preview"], .string(""))
    XCTAssertEqual(sensitive["redacted"], .bool(true))
    XCTAssertEqual(sensitive["can_reply"], .bool(false))
    XCTAssertEqual(listed.metadata["raw_sensitive_content_exposed"], .bool(false))

    XCTAssertEqual(deniedReply.status, .rejected)
    XCTAssertEqual(deniedReply.error?.code, "missing_consents")
    XCTAssertTrue(firstReply.isSuccess)
    XCTAssertEqual(firstReply.output["dispatch_accepted"], .bool(true))
    XCTAssertEqual(firstReply.output["delivery_verified"], .bool(false))
    XCTAssertEqual(firstReply.metadata["handoff_only"], .bool(true))
    XCTAssertEqual(firstReply.metadata["reply_text_retained"], .bool(false))
    XCTAssertEqual(firstReply.output["reply_length"], .int(5))
    XCTAssertEqual(firstReply.output["notification_key_sha256"]?.stringValue?.count, 64)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(provider.replyCalls, 2)
    XCTAssertEqual(stale.status, .failed)
    XCTAssertEqual(stale.error?.code, "notification_stale")
    XCTAssertEqual(stale.error?.retryable, true)
    XCTAssertFalse(stale.toJson().contains("Secret reply"))
  }

  func testAgentIOSVisibleCaptureNativeToolCatalogAndExecutorRequiresForegroundReceipts() throws {
    final class FakeVisibleCaptureProvider: AgentIOSVisibleCaptureToolProviding {
      var implementationId = "fake.ios.visible_capture"
      var currentAvailability: AgentNativeToolAvailability = .available
      var photoCalls = 0
      var audioCalls = 0
      var capturedFacing = ""
      var capturedAudioDuration = 0

      func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func capturePhoto(
        facing: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentIOSVisibleCaptureOutcome {
        photoCalls += 1
        capturedFacing = facing
        return AgentIOSVisibleCaptureOutcome(
          status: .succeeded,
          artifact: AgentIOSVisibleCaptureArtifact(
            kind: .photo,
            contentUri: "content://signalasi.test/photo/1",
            mimeType: "image/jpeg",
            sizeBytes: 8_192,
            widthPixels: 1_920,
            heightPixels: 1_080,
            capturedAtEpochMillis: 1_000,
            completedBy: "autofocus_capture"
          )
        )
      }

      func recordAudio(
        maxDurationSeconds: Int,
        invocation: AgentNativeToolInvocation
      ) -> AgentIOSVisibleCaptureOutcome {
        audioCalls += 1
        capturedAudioDuration = maxDurationSeconds
        return AgentIOSVisibleCaptureOutcome(
          status: .succeeded,
          artifact: AgentIOSVisibleCaptureArtifact(
            kind: .audio,
            contentUri: "content://signalasi.test/audio/1",
            mimeType: "audio/mp4",
            sizeBytes: 4_096,
            durationMillis: Int64(maxDurationSeconds * 1_000),
            capturedAtEpochMillis: 1_000,
            completedBy: "max_duration"
          )
        )
      }
    }

    let provider = FakeVisibleCaptureProvider()
    let definitions = AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.visibleCaptureExecutableDefinitions(provider: provider)
    )
    let photoContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.cameraPermission],
      grantedConsents: [
        AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent,
        AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      ]
    )
    let audioContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.microphonePermission],
      grantedConsents: [
        AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent,
        AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      ]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSVisibleCaptureNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.risk, .high)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertEqual(definition.provenanceMetadata["background_capture"], "false")
      XCTAssertEqual(definition.provenanceMetadata["artifact_contract"], "content-uri-v1")
      XCTAssertTrue(definition.descriptor.requiredConsents.contains {
        $0.id == AgentIOSVisibleCaptureNativeToolCatalog.userVisibleCaptureConsent
      })
    }

    let denied = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("front")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSVisibleCaptureNativeToolCatalog.cameraPermission],
        grantedConsents: [AgentIOSVisibleCaptureNativeToolCatalog.runtimePermissionConsent]
      )
    )
    let photo = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("front")],
      context: photoContext
    )
    let audio = registry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord,
      input: ["max_duration_seconds": .int(2)],
      context: audioContext
    )
    let unavailableProvider = FakeVisibleCaptureProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .unavailable,
      reason: "No capture hardware"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.visibleCaptureExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
      input: ["facing": .string("back")],
      context: photoContext
    )

    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertEqual(provider.photoCalls, 1)
    XCTAssertTrue(photo.isSuccess)
    XCTAssertEqual(provider.capturedFacing, "front")
    XCTAssertEqual(photo.output["kind"], .string("photo"))
    XCTAssertEqual(photo.output["content_uri"], .string("content://signalasi.test/photo/1"))
    XCTAssertEqual(photo.output["user_visible"], .bool(true))
    XCTAssertEqual(photo.metadata["background_capture"], .bool(false))
    XCTAssertEqual(photo.metadata["raw_media_in_receipt"], .bool(false))
    XCTAssertEqual(photo.verification?.status, .passed)
    XCTAssertTrue(audio.isSuccess)
    XCTAssertEqual(provider.audioCalls, 1)
    XCTAssertEqual(provider.capturedAudioDuration, 2)
    XCTAssertEqual(audio.output["kind"], .string("audio"))
    XCTAssertEqual(audio.output["duration_ms"], .int(2_000))
    XCTAssertEqual(audio.output["user_visible"], .bool(true))
    XCTAssertEqual(audio.verification?.status, .passed)
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(unavailableProvider.photoCalls, 0)
  }

  func testAgentIOSWebMediaNativeToolCatalogAndExecutorMirrorsAndroidDefaultTools() throws {
    final class FakeWebMediaProvider: AgentIOSWebMediaToolProviding {
      var implementationId = "fake.ios.web_media"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSWebMediaOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSWebMediaOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        let sha = String(repeating: "a", count: 64)
        switch operation {
        case .webSearch:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "query": input["query"] ?? .string("SignalASI"),
              "results": .array([.object(["title": .string("SignalASI"), "url": .string("https://signalasi.example")])]),
              "result_count": .int(1)
            ]) { current, _ in current }
          )
        case .webOpen, .browserRender:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "text": .string("SignalASI page"),
              "html_sha256": .string(sha),
              "render_mode": .string(operation == .browserRender ? "isolated_static_dom" : "bounded_http")
            ]) { current, _ in current }
          )
        case .browserSessionCreate, .browserSessionNavigate:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "browser_id": .string("browser-session-0001"),
              "current_url": .string("https://signalasi.example"),
              "history_count": .int(operation == .browserSessionNavigate ? 2 : 1),
              "expires_at_epoch_ms": .int(5_000),
              "text": .string("session page"),
              "html_sha256": .string(sha)
            ]) { current, _ in current }
          )
        case .browserSessionClose:
          return AgentNativeToolExecutionResult.success(
            output: [
              "browser_id": input["browser_id"] ?? .string("browser-session-0001"),
              "closed": .bool(true),
              "expires_at_epoch_ms": .int(0)
            ]
          )
        case .httpRequest:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: input["method"]?.stringValue?.lowercased() == "head" ? "head" : "get")
              .merging(["text": .string("ok")]) { current, _ in current }
          )
        case .fileDownload, .webDownload:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "destination_content_uri": input["destination_content_uri"] ?? .string("content://downloads/item"),
              "size_bytes": .int(128),
              "sha256": .string(sha)
            ]) { current, _ in current },
            metadata: ["writer_implementation": .string("fake.content.writer")]
          )
        case .webHead:
          return AgentNativeToolExecutionResult.success(output: commonWeb(method: "head"))
        case .webFetch:
          return AgentNativeToolExecutionResult.success(
            output: commonWeb(method: "get").merging([
              "text": .string("hello"),
              "charset": .string("UTF-8"),
              "size_bytes": .int(5),
              "sha256": .string(sha)
            ]) { current, _ in current }
          )
        case .ocrRecognizeContent:
          return AgentNativeToolExecutionResult.success(
            output: [
              "text": .string("invoice total"),
              "lines": .array([
                .object([
                  "text": .string("invoice total"),
                  "left": .int(0),
                  "top": .int(0),
                  "right": .int(200),
                  "bottom": .int(40),
                  "language_tag": .string("en"),
                  "block_index": .int(0),
                  "line_index": .int(0)
                ])
              ]),
              "blocks": .array([
                .object([
                  "text": .string("invoice total"),
                  "left": .int(0),
                  "top": .int(0),
                  "right": .int(200),
                  "bottom": .int(40),
                  "line_count": .int(1)
                ])
              ]),
              "content_uri": input["content_uri"] ?? .string("content://captures/1"),
              "source_kind": input["source_kind"] ?? .string("image"),
              "script_hint": input["script_hint"] ?? .string("auto"),
              "observed_at_epoch_ms": .int(1_000)
            ]
          )
        case .contentExtract:
          return AgentNativeToolExecutionResult.failure(code: "unexpected_provider_call", message: "content.extract should run locally")
        }
      }

      private func commonWeb(method: String) -> AgentMcpJSONObject {
        [
          "method": .string(method),
          "status_code": .int(200),
          "content_type": .string("text/html; charset=utf-8"),
          "content_length_bytes": .int(128),
          "requested_at_epoch_ms": .int(1_000),
          "retrieved_at_epoch_ms": .int(1_100),
          "response_headers": .object(["content-type": .string("text/html; charset=utf-8")]),
          "source": .object([
            "requested_url": .string("https://signalasi.example"),
            "final_url": .string("https://signalasi.example"),
            "redirect_chain": .array([]),
            "dns_resolution": .array([
              .object([
                "host": .string("signalasi.example"),
                "addresses": .array([.string("203.0.113.10")])
              ])
            ])
          ])
        ]
      }
    }

    let provider = FakeWebMediaProvider()
    let definitions = AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.publicWebConsent]
    )
    let sessionContext = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
        AgentIOSWebMediaNativeToolCatalog.browserSessionPermission
      ],
      grantedConsents: [
        AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
        AgentIOSWebMediaNativeToolCatalog.browserSessionConsent
      ]
    )
    let downloadContext = AgentNativeToolInvocationContext(
      idempotencyKey: "download-1",
      grantedPermissions: [
        AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
        AgentIOSWebMediaNativeToolCatalog.contentUriPermission
      ],
      grantedConsents: [
        AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
        AgentIOSWebMediaNativeToolCatalog.webDownloadConsent,
        AgentIOSWebMediaNativeToolCatalog.contentUriWriteConsent
      ]
    )
    let ocrContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.contentUriReadConsent]
    )
    let extractContext = AgentNativeToolInvocationContext(
      grantedConsents: [AgentIOSWebMediaNativeToolCatalog.localContentExtractConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSWebMediaNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSWebMediaNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSWebMediaNativeToolCatalog.toolIds.isDisjoint(with: AgentIOSMediaNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.webSearch))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.webFetch))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSWebMediaNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertFalse(definition.descriptor.capabilities.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios_phone")
      XCTAssertEqual(definition.provenanceMetadata["result_policy"], "bounded-v1")
    }

    let webDownload = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebMediaNativeToolCatalog.webDownload })
    XCTAssertEqual(webDownload.descriptor.risk, .medium)
    XCTAssertEqual(webDownload.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(webDownload.descriptor.requiredConsents.contains { $0.id == AgentIOSWebMediaNativeToolCatalog.webDownloadConsent })
    XCTAssertEqual(webDownload.provenanceMetadata["destination_scope"], "user_authorized_content_uri")

    let extracted = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.contentExtract,
      input: ["content": .string("<p>Hello&nbsp;ASI</p><script>secret()</script>")],
      context: extractContext
    )
    let search = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("SignalASI"), "max_results": .int(1)],
      context: networkContext
    )
    let session = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
      input: ["url": .string("https://signalasi.example")],
      context: sessionContext
    )
    let invalidURL = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("http://signalasi.example")],
      context: networkContext
    )
    let missingDownloadKey = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webDownload,
      input: [
        "url": .string("https://signalasi.example/file.txt"),
        "destination_content_uri": .string("content://downloads/file.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSWebMediaNativeToolCatalog.publicHttpsNetworkPermission,
          AgentIOSWebMediaNativeToolCatalog.contentUriPermission
        ],
        grantedConsents: [
          AgentIOSWebMediaNativeToolCatalog.publicWebConsent,
          AgentIOSWebMediaNativeToolCatalog.webDownloadConsent,
          AgentIOSWebMediaNativeToolCatalog.contentUriWriteConsent
        ]
      )
    )
    let download = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.fileDownload,
      input: [
        "url": .string("https://signalasi.example/file.txt"),
        "destination_content_uri": .string("content://downloads/file.txt")
      ],
      context: downloadContext
    )
    let ocr = registry.invoke(
      AgentIOSWebMediaNativeToolCatalog.ocrRecognizeContent,
      input: [
        "content_uri": .string("file://selected/capture.png"),
        "source_kind": .string("image")
      ],
      context: ocrContext
    )
    let unavailableProvider = FakeWebMediaProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Web provider missing"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webMediaExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSWebMediaNativeToolCatalog.webFetch,
      input: ["url": .string("https://signalasi.example")],
      context: networkContext
    )

    XCTAssertTrue(extracted.isSuccess)
    XCTAssertEqual(extracted.output["text"], .string("Hello ASI"))
    XCTAssertEqual(extracted.metadata["script_execution"], .bool(false))
    XCTAssertFalse(provider.invokedOperations.contains(.contentExtract))
    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["operation"], .string("web.search"))
    XCTAssertEqual(search.metadata["network_policy"], .string("public_https_pinned_dns_v1"))
    XCTAssertTrue(session.isSuccess)
    XCTAssertEqual(session.output["browser_id"], .string("browser-session-0001"))
    XCTAssertEqual(invalidURL.status, .failed)
    XCTAssertEqual(invalidURL.error?.code, "invalid_url")
    XCTAssertEqual(missingDownloadKey.status, .rejected)
    XCTAssertEqual(missingDownloadKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(download.isSuccess)
    XCTAssertEqual(download.metadata["auto_execute"], .bool(false))
    XCTAssertTrue(ocr.isSuccess)
    XCTAssertEqual(ocr.output["script_hint"], .string("auto"))
    XCTAssertEqual(provider.invokedOperations, [.webSearch, .browserSessionCreate, .fileDownload, .ocrRecognizeContent])
    XCTAssertEqual(provider.capturedInputs.last?["script_hint"], .string("auto"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSWebIntelligenceNativeToolCatalogAndExecutorUsesProviderBoundaries() throws {
    final class FakeWebIntelligenceProvider: AgentIOSWebIntelligenceToolProviding {
      var implementationId = "fake.ios.web_intelligence"
      var engineCatalogSize = 7
      var rankerId = "feature-hash-ranker-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSWebIntelligenceOperation] = []

      func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSWebIntelligenceOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        return AgentNativeToolExecutionResult.success(
          output: [
            "request_id": .string("req-\(operation.rawValue)"),
            "result_count": .int(1)
          ],
          message: "",
          metadata: ["provider_operation": .string(operation.rawValue)]
        )
      }
    }

    let provider = FakeWebIntelligenceProvider()
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]
    )
    let cacheContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSWebIntelligenceNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .phone)
      XCTAssertEqual(definition.descriptor.risk, .low)
      XCTAssertEqual(definition.descriptor.idempotency, .idempotent)
      XCTAssertTrue(definition.descriptor.capabilities.contains("web_intelligence.native"))
      XCTAssertTrue(definition.descriptor.capabilities.contains("source.receipts"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
      XCTAssertEqual(definition.provenanceMetadata["engine_catalog_size"], "7")
      XCTAssertEqual(definition.provenanceMetadata["cookies"], "none")
    }
    let fetch = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch })
    let cache = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.cache })
    XCTAssertEqual(fetch.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission])
    XCTAssertEqual(fetch.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
    XCTAssertEqual(cache.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission])
    XCTAssertEqual(cache.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])

    let denied = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission]
      )
    )
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertTrue(provider.invokedOperations.isEmpty)

    let search = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI"), "limit": .int(3)],
      context: networkContext
    )
    let cacheStatus = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("status")],
      context: cacheContext
    )
    let unavailableProvider = FakeWebIntelligenceProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Network provider missing"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI")],
      context: networkContext
    )

    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["protocol"], .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId))
    XCTAssertEqual(search.output["operation"], .string("search"))
    XCTAssertEqual(search.output["status"], .string("completed"))
    XCTAssertEqual(search.metadata["source_isolation"], .bool(true))
    XCTAssertEqual(search.metadata["evidence_is_untrusted"], .bool(true))
    XCTAssertEqual(search.message, "Search across independent web sources completed")
    XCTAssertTrue(cacheStatus.isSuccess)
    XCTAssertEqual(cacheStatus.output["operation"], .string("cache"))
    XCTAssertEqual(provider.invokedOperations, [.search, .cache])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSMediaNativeToolCatalogAndExecutorBoundsMetadataPlaybackAndTranscode() throws {
    final class FakeMediaProvider: AgentIOSMediaNativeToolProviding {
      var implementationId = "fake.ios.media"
      var currentAvailability: AgentNativeToolAvailability = .available
      var metadataUri = ""
      var playbackUri = ""
      var playbackContentType = ""
      var transcodeRequest: AgentIOSMediaTranscodeRequest?
      var transcodeCalls = 0

      func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func inspectMetadata(
        contentUri: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        metadataUri = contentUri
        return AgentNativeToolExecutionResult.success(
          output: [
            "content_uri": .string(contentUri),
            "content_type": .string("video/mp4"),
            "display_name": .string("clip.mp4"),
            "size_bytes": .int(4_096),
            "duration_ms": .int(4_000),
            "width": .int(1_920),
            "height": .int(1_080),
            "rotation_degrees": .int(0),
            "has_audio": .bool(true),
            "has_video": .bool(true),
            "observed_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func handoffPlayback(
        contentUri: String,
        contentType: String,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        playbackUri = contentUri
        playbackContentType = contentType
        return AgentNativeToolExecutionResult.success(
          output: [
            "launched": .bool(true),
            "action": .string("ios.media.open"),
            "handler_package": .string("com.apple.avplayer"),
            "completed": .bool(false),
            "handed_off_at_epoch_ms": .int(1_000),
            "source": .object(["content_uri": .string(contentUri)])
          ]
        )
      }

      func transcode(
        request: AgentIOSMediaTranscodeRequest,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        transcodeCalls += 1
        transcodeRequest = request
        let sha = String(repeating: "a", count: 64)
        return AgentNativeToolExecutionResult.success(
          output: [
            "source_path": .string(request.sourcePath.isEmpty ? "selected/input.mov" : request.sourcePath),
            "destination_path": .string(request.destinationPath.isEmpty ? "outputs/clip.mp4" : request.destinationPath),
            "target_format": .string(request.targetFormat),
            "mime_type": .string("video/mp4"),
            "size_bytes": .int(8_192),
            "sha256": .string(sha),
            "execution_duration_ms": .int(250),
            "artifacts": .array([
              .object([
                "relative_path": .string("outputs/clip.mp4"),
                "size_bytes": .int(8_192),
                "sha256": .string(sha),
                "artifact_kind": .string("media")
              ])
            ]),
            "execution_receipt": .object(["runtime": .string("ffmpeg")]),
            "network_enabled": .bool(false),
            "completed_at_epoch_ms": .int(1_000)
          ]
        )
      }
    }

    let provider = FakeMediaProvider()
    let definitions = AgentIOSMediaNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: provider, nowMillis: { 2_000 })
    )
    let contentContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [AgentIOSMediaNativeToolCatalog.contentUriReadConsent]
    )
    let playbackContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSMediaNativeToolCatalog.contentUriPermission],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.mediaPlaybackConsent
      ]
    )
    let transcodeContext = AgentNativeToolInvocationContext(
      invocationId: "media-transcode-1",
      sessionId: "session-1",
      conversationId: "conversation-1",
      grantedPermissions: [
        AgentIOSMediaNativeToolCatalog.workspaceMediaPermission,
        AgentIOSMediaNativeToolCatalog.mediaRuntimePermission
      ],
      grantedConsents: [
        AgentIOSMediaNativeToolCatalog.contentUriReadConsent,
        AgentIOSMediaNativeToolCatalog.contentUriWriteConsent,
        AgentIOSMediaNativeToolCatalog.mediaTranscodeConsent
      ],
      attributes: ["workspace_id": "workspace-1"]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSMediaNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSMediaNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSMediaNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios_phone")
    }

    let metadata = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaMetadata,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let deniedPlayback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: ["content_uri": .string("content://media/item-7")],
      context: contentContext
    )
    let playback = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaPlaybackHandoff,
      input: [
        "content_uri": .string("content://media/item-7"),
        "content_type": .string("video/mp4")
      ],
      context: playbackContext
    )
    let transcode = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "destination_path": .string("outputs/clip.mp4"),
        "target_format": .string("mp4"),
        "preset": .string("compact"),
        "timeout_ms": .int(30_000)
      ],
      context: transcodeContext
    )
    let duplicateSource = registry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "content_uri": .string("content://media/item-7"),
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )
    let unavailableProvider = FakeMediaProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed FFmpeg runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mediaExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
      input: [
        "source_path": .string("inputs/turn/clip.mov"),
        "target_format": .string("mp4")
      ],
      context: transcodeContext
    )

    XCTAssertTrue(metadata.isSuccess)
    XCTAssertEqual(metadata.output["duration_ms"], .int(4_000))
    XCTAssertEqual(metadata.output["has_video"], .bool(true))
    XCTAssertEqual(provider.metadataUri, "content://media/item-7")
    XCTAssertEqual(deniedPlayback.status, .rejected)
    XCTAssertEqual(deniedPlayback.error?.code, "missing_consents")
    XCTAssertTrue(playback.isSuccess)
    XCTAssertEqual(playback.output["launched"], .bool(true))
    XCTAssertEqual(playback.output["completed"], .bool(false))
    XCTAssertEqual(provider.playbackUri, "content://media/item-7")
    XCTAssertEqual(provider.playbackContentType, "video/mp4")
    XCTAssertTrue(transcode.isSuccess)
    XCTAssertEqual(provider.transcodeRequest?.workspaceId, "workspace-1")
    XCTAssertEqual(provider.transcodeRequest?.sourcePath, "inputs/turn/clip.mov")
    XCTAssertEqual(provider.transcodeRequest?.targetFormat, "mp4")
    XCTAssertEqual(provider.transcodeRequest?.preset, "compact")
    XCTAssertEqual(transcode.output["mime_type"], .string("video/mp4"))
    XCTAssertEqual(transcode.output["network_enabled"], .bool(false))
    XCTAssertEqual(duplicateSource.status, .failed)
    XCTAssertEqual(duplicateSource.error?.code, "invalid_transcode_source")
    XCTAssertEqual(provider.transcodeCalls, 1)
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(unavailableProvider.transcodeCalls, 0)
  }

  func testAgentIOSSelfEvolutionNativeToolCatalogAndExecutorMirrorsAndroidWireProtocol() throws {
    final class FakeSelfEvolutionProvider: AgentIOSSelfEvolutionToolProviding {
      var implementationId = "fake.ios.self_evolution"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSSelfEvolutionOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSSelfEvolutionOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "execution_target": .string("ios"),
              "runtime_ready": .bool(true),
              "runtime_reason": .string("ready"),
              "task_count": .int(1),
              "active_tasks": .int(0),
              "health": .object(["total_tasks": .int(1), "active_tasks": .int(0)])
            ],
            message: "iOS-local self-evolution inspected"
          )
        case .tasksList:
          return AgentNativeToolExecutionResult.success(
            output: [
              "tasks": .array([.object(taskValue(status: "proposed"))]),
              "health": .object(["total_tasks": .int(1)])
            ],
            message: "iOS-local evolution tasks listed"
          )
        case .tasksCreate:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "proposed")),
              "candidate_workspace_id": .string(""),
              "candidate_source_root": .string("")
            ],
            message: "Evolution task created"
          )
        case .candidatePrepare:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "running")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source")
            ],
            message: "Evolution candidate prepared"
          )
        case .candidatePatch:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "waiting_approval")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source"),
              "unified_diff": .string("diff --git a/secret b/secret")
            ],
            message: "Evolution candidate validated",
            metadata: ["unified_diff": .string("diff --git a/secret b/secret")]
          )
        case .candidateRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "rolled_back")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("")
            ],
            message: "Evolution candidate rolled back"
          )
        }
      }

      private func taskValue(status: String) -> AgentMcpJSONObject {
        [
          "protocol": .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId),
          "task_id": .string("evolve-ios-1"),
          "problem": .string("Mirror Android self-evolution tools on iOS"),
          "reproduction_steps": .array([.string("Open iOS agent tool catalog")]),
          "scope": .array([.string("apps/ios")]),
          "acceptance": .array([.string("Android wire-compatible tool ids are registered")]),
          "risk_level": .string("medium"),
          "max_attempts": .int(3),
          "status": .string(status),
          "execution_target": .string("ios"),
          "base_commit": .string("base"),
          "candidate_commit": .string(status == "waiting_approval" ? "candidate" : ""),
          "candidate_branch": .string(status == "waiting_approval" ? "evolution/evolve-ios-1-a1" : ""),
          "approval_hash": .string(status == "waiting_approval" ? "approval" : ""),
          "attempts": .array([]),
          "last_error_code": .string(""),
          "last_error": .string(""),
          "created_at_millis": .int(1_000),
          "updated_at_millis": .int(2_000)
        ]
      }
    }

    let provider = FakeSelfEvolutionProvider()
    let definitions = AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: provider, nowMillis: { 44_000 })
    )
    let readContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSelfEvolutionNativeToolCatalog.storePermission]
    )
    let candidateContext = AgentNativeToolInvocationContext(
      invocationId: "evolution-patch-1",
      idempotencyKey: "patch-key-1",
      grantedPermissions: [
        AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
      ],
      grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
    )

    XCTAssertEqual(Set(AgentIOSSelfEvolutionNativeToolCatalog.orderedToolIds), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSSelfEvolutionNativeToolCatalog.toolIds.contains("signalasi.evolution.candidate.patch"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSSelfEvolutionNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("evolution.self"))
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentSelfEvolutionNativeTools")
      XCTAssertEqual(definition.provenanceMetadata["production_mutation"], "disabled")
    }
    let prepareDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare })
    let patchDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch })
    let createDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate })
    XCTAssertEqual(createDescriptor.descriptor.risk, .low)
    XCTAssertEqual(createDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertEqual(prepareDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent])
    XCTAssertEqual(patchDescriptor.descriptor.risk, .high)
    XCTAssertEqual(patchDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(patchDescriptor.descriptor.idempotency, .idempotencyKeyRequired)

    let status = registry.invoke(AgentIOSSelfEvolutionNativeToolCatalog.status, input: [:], context: readContext)
    let list = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksList,
      input: ["limit": .int(2)],
      context: readContext
    )
    let create = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate,
      input: [
        "problem": .string("Mirror Android self-evolution tools on iOS"),
        "scope": .array([.string("apps/ios")]),
        "acceptance": .array([.string("Tool ids match Android")])
      ],
      context: readContext
    )
    let deniedPrepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ]
      )
    )
    let missingPatchKey = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ],
        grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
      )
    )
    let prepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let patch = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/apps/ios/a b/apps/ios/a")
      ],
      context: candidateContext
    )
    let rollback = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidateRollback,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let unavailableProvider = FakeSelfEvolutionProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed self-evolution runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: candidateContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["protocol"], .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId))
    XCTAssertEqual(status.output["runtime_ready"], .bool(true))
    XCTAssertTrue(list.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["limit"], .int(2))
    XCTAssertTrue(create.isSuccess)
    XCTAssertEqual(create.output["status"], .string("proposed"))
    XCTAssertEqual(deniedPrepare.status, .rejected)
    XCTAssertEqual(deniedPrepare.error?.code, "missing_consents")
    XCTAssertEqual(missingPatchKey.status, .rejected)
    XCTAssertEqual(missingPatchKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(prepare.isSuccess)
    XCTAssertEqual(prepare.output["candidate_source_root"], .string("source"))
    XCTAssertTrue(patch.isSuccess)
    XCTAssertEqual(patch.output["status"], .string("waiting_approval"))
    XCTAssertNil(patch.output["unified_diff"])
    XCTAssertNil(patch.metadata["unified_diff"])
    XCTAssertEqual(patch.metadata["patch_content_retained"], .bool(false))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["status"], .string("rolled_back"))
    XCTAssertEqual(provider.invokedOperations, [.status, .tasksList, .tasksCreate, .candidatePrepare, .candidatePatch, .candidateRollback])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSDesktopRemoteNativeToolCatalogAndExecutorForwardsVerifiedDesktopCalls() throws {
    final class FakeDesktopRemoteProvider: AgentIOSDesktopRemoteToolProviding {
      var implementationId = "fake.ios.desktop_remote"
      var transportId = "signalasi-link-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var verificationStatus = "passed"
      var invokedKinds: [AgentIOSDesktopRemoteToolKind] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        kind: AgentIOSDesktopRemoteToolKind,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedKinds.append(kind)
        capturedInputs.append(input)
        return AgentNativeToolExecutionResult.success(
          output: output(kind: kind, input: input),
          message: "Desktop \(kind.rawValue) completed",
          metadata: [
            "desktop_id": .string(input["desktop_id"]?.stringValue ?? "desktop-1"),
            "remote_verification_status": .string(verificationStatus),
            "remote_verification_evidence": .object([
              "tool_id": .string(invocation.descriptor.id),
              "observed": .bool(true)
            ])
          ]
        )
      }

      private func output(kind: AgentIOSDesktopRemoteToolKind, input: AgentMcpJSONObject) -> AgentMcpJSONObject {
        switch kind {
        case .systemStatus:
          return ["os": .string("Windows"), "memory_used_bytes": .int(1_024)]
        case .processList:
          return ["processes": .array([.object(["pid": .int(7), "name": .string("SignalASI.exe")])])]
        case .fileReadText:
          return [
            "path": input["path"] ?? .string("notes/readme.txt"),
            "text": .string("desktop text"),
            "size_bytes": .int(12)
          ]
        case .terminalRun:
          return [
            "argv": input["argv"] ?? .array([]),
            "exit_code": .int(0),
            "stdout": .string("ok"),
            "stderr": .string("")
          ]
        case .fileList, .fileWriteText, .fileSha256, .archiveCreate, .officeInspect, .officeConvert:
          return ["kind": .string(kind.rawValue)]
        }
      }
    }

    let provider = FakeDesktopRemoteProvider()
    let definitions = AgentIOSDesktopRemoteNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: provider)
    )
    let linkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSDesktopRemoteNativeToolCatalog.linkPermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "desktop-terminal-1",
      idempotencyKey: "desktop-key-1",
      grantedPermissions: [
        AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
        AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
      ],
      grantedConsents: [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent],
      attributes: ["workspace_id": "desktop-workspace-1"]
    )

    XCTAssertEqual(Set(AgentIOSDesktopRemoteNativeToolCatalog.orderedToolIds), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map { $0.descriptor.version }), [AgentIOSDesktopRemoteNativeToolCatalog.version])
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSDesktopRemoteNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .desktop)
      XCTAssertFalse(definition.descriptor.capabilities.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["transport"], "signalasi-link-v1")
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentDesktopRemoteNativeTools")
    }
    let terminalDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.terminalRun })
    let writeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText })
    let readDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileReadText })
    XCTAssertEqual(terminalDescriptor.descriptor.risk, .high)
    XCTAssertEqual(terminalDescriptor.descriptor.timeoutMillis, 185_000)
    XCTAssertEqual(terminalDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent])
    XCTAssertEqual(terminalDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(writeDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(readDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertTrue(AgentIOSDesktopRemoteNativeToolCatalog.alwaysConfirmToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.terminalRun))

    let missingWorkspace = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ]
      )
    )
    let read = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: workspaceContext
    )
    let deniedTerminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "desktop-key-2",
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let missingWriteKey = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText,
      input: [
        "path": .string("notes/readme.txt"),
        "content": .string("updated"),
        "mode": .string("overwrite")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let terminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: workspaceContext
    )
    provider.verificationStatus = "failed"
    let verificationFailed = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.processList,
      input: ["query": .string("SignalASI")],
      context: linkContext
    )
    let unavailableProvider = FakeDesktopRemoteProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Waiting for Desktop manifest"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.systemStatus,
      input: [:],
      context: linkContext
    )

    XCTAssertEqual(missingWorkspace.status, .failed)
    XCTAssertEqual(missingWorkspace.error?.code, "desktop_workspace_unavailable")
    XCTAssertTrue(read.isSuccess)
    XCTAssertEqual(read.output["desktop_id"], .string("desktop-1"))
    XCTAssertEqual(read.output["workspace_id"], .string("desktop-workspace-1"))
    XCTAssertEqual(read.output["remote_artifacts"], .array([]))
    XCTAssertEqual(read.verification?.status, .passed)
    XCTAssertEqual(deniedTerminal.status, .rejected)
    XCTAssertEqual(deniedTerminal.error?.code, "missing_consents")
    XCTAssertEqual(missingWriteKey.status, .rejected)
    XCTAssertEqual(missingWriteKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(terminal.isSuccess)
    XCTAssertEqual(terminal.output["remote_forwarded"], .bool(true))
    XCTAssertEqual(terminal.metadata["transport"], .string("signalasi-link-v1"))
    XCTAssertEqual(verificationFailed.status, .verificationFailed)
    XCTAssertEqual(verificationFailed.error?.code, "verification_failed")
    XCTAssertEqual(provider.invokedKinds, [.fileReadText, .terminalRun, .processList])
    XCTAssertEqual(provider.capturedInputs.first?["path"], .string("notes/readme.txt"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedKinds.isEmpty)
  }

  func testAgentMcpNativeToolsExposeAndroidWireIdsAndProviderBackedExecution() throws {
    final class FakeMcpNativeProvider: AgentIOSMcpNativeToolProviding {
      var implementationId = "fake.ios.mcp"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSMcpNativeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSMcpNativeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .listConnections:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connections": .array([
                .object([
                  "id": .string("github"),
                  "name": .string("GitHub"),
                  "state": .string("connected"),
                  "auth_state": .string("authenticated"),
                  "enabled": .bool(true),
                  "permission_mode": .string("ask_for_changes"),
                  "tools": .array([.string("github.repositories")])
                ])
              ])
            ],
            message: "MCP connections listed"
          )
        case .listTools:
          return AgentNativeToolExecutionResult.success(
            output: [
              "connection_id": input["connection_id"] ?? .string("github"),
              "tools": .array([
                .object([
                  "name": .string("github.repositories"),
                  "title": .string("List repositories"),
                  "description": .string("Lists repositories"),
                  "security": .object(["risk": .string("low")])
                ])
              ])
            ],
            message: "MCP tools discovered"
          )
        case .callTool:
          return AgentNativeToolExecutionResult.success(
            output: [
              "content": .array([.object(["type": .string("text"), "text": .string("ok")])]),
              "structured_content": .object(["ok": .bool(true)])
            ],
            message: "MCP tool called",
            metadata: ["mcp_audit_id": .string("audit-1")]
          )
        }
      }
    }

    let provider = FakeMcpNativeProvider()
    let definitions = AgentMcpNativeTools.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider)
    )
    let context = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentMcpNativeTools.toolIds)
    XCTAssertEqual(registry.ids(), AgentMcpNativeTools.toolIds)
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.connections.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tools.list"))
    XCTAssertTrue(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.tool.call"))
    XCTAssertFalse(AgentMcpNativeTools.toolIds.contains("signalasi.mcp.call_tool"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentMcpNativeTools.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("mcp"))
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentMcpNativeTools.mcpHostPermission])
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], "mcp")
      XCTAssertEqual(definition.provenanceMetadata["host"], "ios")
    }
    let callDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentMcpNativeTools.callTool })
    XCTAssertEqual(callDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(callDescriptor.descriptor.timeoutMillis, 60_000)
    XCTAssertEqual(callDescriptor.descriptor.idempotency, .nonIdempotent)

    let connections = registry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)
    let tools = registry.invoke(
      AgentMcpNativeTools.listTools,
      input: ["connection_id": .string("github")],
      context: context
    )
    let denied = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object([:])
      ],
      context: AgentNativeToolInvocationContext()
    )
    let call = registry.invoke(
      AgentMcpNativeTools.callTool,
      input: [
        "connection_id": .string("github"),
        "tool_name": .string("github.repositories"),
        "arguments": .object(["limit": .int(1)])
      ],
      context: context
    )
    let unavailableProvider = FakeMcpNativeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "No authenticated MCP connection is ready"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(AgentMcpNativeTools.listConnections, input: [:], context: context)

    XCTAssertTrue(connections.isSuccess)
    if case .array(let listedConnections)? = connections.output["connections"] {
      XCTAssertEqual(listedConnections.count, 1)
    } else {
      XCTFail("Expected MCP connections array")
    }
    XCTAssertTrue(tools.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["connection_id"], .string("github"))
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_permissions")
    XCTAssertTrue(call.isSuccess)
    XCTAssertEqual(call.output["connection_id"], .string("github"))
    XCTAssertEqual(call.output["tool_name"], .string("github.repositories"))
    XCTAssertEqual(call.metadata["protocol"], .string("mcp"))
    XCTAssertEqual(call.metadata["mcp_audit_id"], .string("audit-1"))
    XCTAssertEqual(provider.invokedOperations, [.listConnections, .listTools, .callTool])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSOnDeviceRuntimeNativeToolCatalogAndExecutorMirrorsAndroidRuntimeTools() throws {
    final class FakeRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
      var implementationId = "fake.ios.runtime"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSOnDeviceRuntimeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "backend": .string("ios_local"),
              "backend_ready": .bool(true),
              "reason": .string("ready"),
              "packs": .array([packValue("linux-base", state: "ready")]),
              "languages": .array([
                .object(["id": .string("python"), "ready": .bool(true)])
              ])
            ],
            message: "On-device runtime inspected"
          )
        case .workspaceStatus:
          return AgentNativeToolExecutionResult.success(
            output: [
              "workspace_file_count": .int(3),
              "workspace_bytes": .int(1_024),
              "checkpoints": .array([.object(["checkpoint_id": .string("cp-1")])])
            ],
            message: "On-device project workspace inspected"
          )
        case .workspaceRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "checkpoint_id": input["checkpoint_id"] ?? .string("cp-1"),
              "workspace_file_count": .int(2),
              "workspace_bytes": .int(512),
              "workspace_disposition": .string("rolled_back")
            ],
            message: "On-device project checkpoint restored"
          )
        case .listPacks:
          return AgentNativeToolExecutionResult.success(
            output: ["packs": .array([packValue("linux-base", state: "ready"), packValue("python-uv", state: "ready")])],
            message: "On-device runtime packs listed"
          )
        case .installPack:
          return AgentNativeToolExecutionResult.success(
            output: [
              "requested_pack": input["pack_id"] ?? .string("python-uv"),
              "installed": .array([
                .object(["pack_id": .string("python-uv"), "version": .string("1.0.0"), "state": .string("ready")])
              ])
            ],
            message: "Trusted runtime pack is ready"
          )
        case .execute:
          return AgentNativeToolExecutionResult.success(
            output: [
              "exit_code": .int(0),
              "stdout": .string("ok"),
              "stderr": .string(""),
              "duration_ms": .int(25),
              "workspace_file_count": .int(4),
              "workspace_bytes": .int(2_048),
              "checkpoint_id": .string("cp-2"),
              "execution_receipt": .object(["request_id": .string(invocation.context.invocationId)])
            ],
            message: "On-device runtime completed"
          )
        }
      }

      private func packValue(_ id: String, state: String) -> AgentMcpJSONValue {
        .object([
          "id": .string(id),
          "state": .string(state),
          "reason": .string(""),
          "version": .string("1.0.0"),
          "architecture": .string("arm64"),
          "capabilities": .array([.string("shell.execute")]),
          "installed_size_bytes": .int(2_048),
          "license": .string("Apache-2.0")
        ])
      }
    }

    let provider = FakeRuntimeProvider()
    let definitions = AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: provider)
    )
    let runtimeContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "runtime-execute-1",
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission
      ],
      attributes: ["workspace_id": "runtime-workspace-1"]
    )
    let packContext = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.packInstallPermission
      ]
    )

    XCTAssertEqual(Set(AgentIOSOnDeviceRuntimeNativeToolCatalog.orderedToolIds), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds.contains("signalasi.runtime.workspace.status"))
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.requiredPacks.contains("python-uv"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("runtime.ios_local"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentOnDeviceRuntimeTools")
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios")
    }
    let installDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack })
    let executeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute })
    let statusDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.status })
    XCTAssertEqual(statusDescriptor.descriptor.risk, .low)
    XCTAssertEqual(installDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.packManagerExecutorId)
    XCTAssertEqual(installDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(executeDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    XCTAssertEqual(executeDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(executeDescriptor.descriptor.timeoutMillis, 30 * 60_000)

    let status = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], context: runtimeContext)
    let packs = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks, input: [:], context: runtimeContext)
    let workspace = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceStatus, input: [:], context: workspaceContext)
    let deniedInstall = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: runtimeContext
    )
    let install = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: packContext
    )
    let rollback = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback,
      input: ["checkpoint_id": .string("cp-1")],
      context: workspaceContext
    )
    let invalidExecute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("swift"),
        "source": .string("print(\"no\")")
      ],
      context: workspaceContext
    )
    let execute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')"),
        "timeout_ms": .int(1_000),
        "artifact_paths": .array([.string("out/result.txt")])
      ],
      context: workspaceContext
    )
    let unavailableProvider = FakeRuntimeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install runtime backend"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')")
      ],
      context: workspaceContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["backend"], .string("ios_local"))
    XCTAssertTrue(packs.isSuccess)
    if case .array(let packValues)? = packs.output["packs"] {
      XCTAssertEqual(packValues.count, 2)
    } else {
      XCTFail("Expected runtime packs array")
    }
    XCTAssertTrue(workspace.isSuccess)
    XCTAssertEqual(workspace.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(deniedInstall.status, .rejected)
    XCTAssertEqual(deniedInstall.error?.code, "missing_permissions")
    XCTAssertTrue(install.isSuccess)
    XCTAssertEqual(install.output["requested_pack"], .string("python-uv"))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["workspace_disposition"], .string("rolled_back"))
    XCTAssertEqual(invalidExecute.status, .rejected)
    XCTAssertEqual(invalidExecute.error?.code, "invalid_input")
    XCTAssertTrue(execute.isSuccess)
    XCTAssertEqual(execute.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(execute.output["workspace_disposition"], .string("preserved"))
    XCTAssertEqual(execute.output["artifacts"], .array([]))
    XCTAssertEqual(execute.metadata["network_default"], .string("disabled"))
    XCTAssertEqual(provider.invokedOperations, [.status, .listPacks, .workspaceStatus, .installPack, .workspaceRollback, .execute])
    XCTAssertEqual(provider.capturedInputs.last?["language"], .string("python"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentPhoneNativeToolCatalogRegistersStableDefaultIds() {
    var expected: Set<String> = [
      "signalasi.workspace.initialize",
      "signalasi.workspace.directory.create",
      "signalasi.workspace.directory.list",
      "signalasi.workspace.file.stat",
      "signalasi.workspace.file.read.text",
      "signalasi.workspace.file.read.bytes",
      "signalasi.workspace.file.write.text",
      "signalasi.workspace.file.create.text",
      "signalasi.workspace.file.append.text",
      "signalasi.workspace.file.write.bytes",
      "signalasi.workspace.file.create.bytes",
      "signalasi.workspace.file.append.bytes",
      "signalasi.workspace.entry.move",
      "signalasi.workspace.entry.copy",
      "signalasi.workspace.entry.delete",
      "signalasi.workspace.file.search.text",
      "signalasi.workspace.file.patch.exact",
      "signalasi.workspace.file.diff.summary",
      "signalasi.workspace.file.sha256",
      "signalasi.workspace.zip.create",
      "signalasi.workspace.zip.list",
      "signalasi.workspace.zip.extract",
      "signalasi.agent_action.read.screen",
      "signalasi.agent_action.tap",
      "signalasi.agent_action.type.text",
      "signalasi.agent_action.swipe",
      "signalasi.agent_action.long.press",
      "signalasi.agent_action.delete.text",
      "signalasi.agent_action.paste.text",
      "signalasi.agent_action.copy.screen.text",
      "signalasi.agent_action.back",
      "signalasi.agent_action.home",
      "signalasi.agent_action.recents",
      "signalasi.agent_action.lock.screen",
      "signalasi.agent_action.open.app",
      "signalasi.agent_action.open.url",
      "signalasi.agent_action.set.alarm",
      "signalasi.agent_action.reply.notification"
    ]
    expected.formUnion(AgentIOSSystemNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHardwareNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSNotificationNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSMediaNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    expected.formUnion(AgentMcpNativeTools.toolIds)
    expected.formUnion(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    let descriptors = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(expected, AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertEqual(expected, Set(descriptors.map(\.id)))
    XCTAssertEqual(expected.count, descriptors.count)
  }

  func testAgentPhoneNativeToolCatalogDescriptorsCarryPolicyAndProvenance() {
    let definitions = AgentPhoneNativeToolCatalog.definitions(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(definitions.count, AgentPhoneNativeToolCatalog.toolIds.count)
    definitions.forEach { definition in
      let descriptor = definition.descriptor
      XCTAssertFalse(descriptor.inputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.outputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.capabilities.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredPermissions.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredConsents.isEmpty, descriptor.id)
      XCTAssertTrue((Int64(1)...Int64(30 * 60_000)).contains(descriptor.timeoutMillis), descriptor.id)
      XCTAssertFalse(definition.executorId.isEmpty, descriptor.id)
      XCTAssertFalse(definition.provenanceMetadata.isEmpty, descriptor.id)
    }
  }

  func testAgentPhoneNativeToolCatalogMapsCapabilityAvailabilityToActions() throws {
    let declared = AgentPhoneNativeToolCatalog.descriptors()
    let readScreen = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.readScreen) }
    )
    let openURL = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let reply = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.replyNotification) }
    )

    XCTAssertEqual(readScreen.availability.status, .unavailable)
    XCTAssertTrue(readScreen.capabilities.contains("phone.accessibility.ui.tree"))
    XCTAssertEqual(openURL.availability.status, .available)
    XCTAssertEqual(reply.availability.status, .available)
    XCTAssertTrue(reply.availability.reason.contains("SignalASI-owned notification"))
  }

  func testAgentPhoneNativeToolCatalogDefaultIdsIncludeExpansionGroups() {
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.isSuperset(of: AgentPhoneNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.media.playback.handoff"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.web.intelligence.search"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.hardware.location.foreground.read"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.execute))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.listConnections))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.callTool))
    XCTAssertFalse(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.mcp.call_tool"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSystemNativeToolCatalog.smsSend))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHardwareNativeToolCatalog.storageStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHomeAssistantNativeToolCatalog.connectionStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSNotificationNativeToolCatalog.notificationsList))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebIntelligenceNativeToolCatalog.search))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSMediaNativeToolCatalog.mediaMetadata))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSelfEvolutionNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.systemStatus))
  }

  func testAgentPhoneNativeToolCatalogModelsUseAndroidWireNames() throws {
    let definition = try XCTUnwrap(
      AgentPhoneNativeToolCatalog.definitions().first { $0.id == AgentPhoneNativeToolCatalog.workspaceReadText }
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any]
    )
    let descriptor = try XCTUnwrap(object["descriptor"] as? [String: Any])

    XCTAssertEqual(object["executor_id"] as? String, AgentPhoneNativeToolCatalog.fileExecutorId)
    XCTAssertNotNil(object["provenance_metadata"])
    XCTAssertEqual(descriptor["id"] as? String, AgentPhoneNativeToolCatalog.workspaceReadText)
    XCTAssertNotNil(descriptor["input_schema"] as? [String: Any])
    XCTAssertNotNil(descriptor["output_schema"] as? [String: Any])
    XCTAssertNil(object["executorId"])
    XCTAssertNil(descriptor["inputSchema"])
  }

  func testAgentNativeToolRegistryRegistersStableIdsAndCatalogJson() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.echo",
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Contacts permission is disabled",
        checkedAtEpochMillis: 123
      ),
      capabilities: ["phone.local", "contacts.read"],
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.permission.contacts", title: "Contacts")
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "contacts.lookup", title: "Look up contact")
      ]
    )
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: "test.executor",
      provenanceMetadata: ["implementation": "fake"]
    )
    let registry = try AgentNativeToolRegistry(definitions: [definition])

    XCTAssertEqual(registry.ids(), Set(["signalasi.test.echo"]))
    XCTAssertEqual(registry.lookup("signalasi.test.echo"), definition)
    XCTAssertThrowsError(try registry.register(AgentPhoneNativeToolDefinition(
      descriptor: try nativeToolDescriptor("signalasi.test.echo"),
      executorId: "duplicate.executor"
    )))

    let json = registry.catalogJson()
    XCTAssertTrue(json.contains("\"contract_version\":\"signalasi.phone-native-tools/1.0\""))
    XCTAssertTrue(json.contains("\"id\":\"signalasi.test.echo\""))
    XCTAssertTrue(json.contains("\"input_schema\""))
    XCTAssertTrue(json.contains("\"output_schema\""))
    XCTAssertTrue(json.contains("\"required_permissions\""))
    XCTAssertTrue(json.contains("\"required_consents\""))
    XCTAssertTrue(json.contains("\"timeout_ms\""))
    XCTAssertTrue(json.contains("\"checked_at_epoch_ms\":123"))
    XCTAssertTrue((json.range(of: "contacts.read")?.lowerBound ?? json.endIndex) < (json.range(of: "phone.local")?.lowerBound ?? json.startIndex))
  }

  func testAgentNativeToolRegistryValidatesJsonSchemaTypesRequiredAndAdditionalProperties() throws {
    let schema: AgentMcpJSONObject = [
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string"), "minLength": .int(2)]),
        "count": .object(["type": .string("integer"), "minimum": .int(1)]),
        "mode": .object(["type": .string("string"), "enum": .array([.string("fast"), .string("safe")])]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "maxItems": .int(2)
        ])
      ]),
      "required": .array([.string("name"), .string("count")]),
      "additionalProperties": .bool(false)
    ]
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: try nativeToolDescriptor("signalasi.test.schema", inputSchema: schema),
        executorId: "test.executor"
      )
    ])

    let invalid = registry.validateInput("signalasi.test.schema", input: [
      "count": .string("one"),
      "mode": .string("slow"),
      "tags": .array([.string("a"), .string("b"), .string("c")]),
      "extra": .bool(true)
    ])
    let codes = Set(invalid.issues.map(\.code))

    XCTAssertFalse(invalid.isValid)
    XCTAssertTrue(codes.contains("required"))
    XCTAssertTrue(codes.contains("type_mismatch"))
    XCTAssertTrue(codes.contains("not_in_enum"))
    XCTAssertTrue(codes.contains("max_items"))
    XCTAssertTrue(codes.contains("additional_property"))
    XCTAssertTrue(registry.validateInput("signalasi.test.schema", input: [
      "name": .string("ok"),
      "count": .int(1),
      "mode": .string("safe")
    ]).isValid)
    XCTAssertEqual(registry.validateInput("signalasi.missing", input: [:]).issues.first?.code, "unknown_tool")
  }

  func testAgentNativeToolRegistryAuthorizesAvailabilityPermissionsAndConsents() throws {
    let permission = AgentNativePermissionRequirement(id: "ios.permission.camera", title: "Camera")
    let consent = AgentNativeConsentRequirement(id: "camera.capture", title: "Capture camera")
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.camera",
      requiredPermissions: [permission],
      requiredConsents: [consent],
      inputSchema: AgentNativeToolDescriptor.objectSchema()
    )
    let setup = try nativeToolDescriptor(
      "signalasi.test.setup",
      availability: AgentNativeToolAvailability(status: .requiresSetup, reason: "Needs configuration")
    )
    let blocked = try nativeToolDescriptor("signalasi.test.blocked", risk: .blocked)
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: setup, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: blocked, executorId: "test.executor")
    ])

    let missingPermission = registry.authorize("signalasi.test.camera", input: [:])
    let missingConsent = registry.authorize(
      "signalasi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(grantedPermissions: ["ios.permission.camera"])
    )
    let ready = registry.authorize(
      "signalasi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: ["ios.permission.camera"],
        grantedConsents: ["camera.capture"]
      )
    )

    XCTAssertEqual(missingPermission.code, "missing_permissions")
    XCTAssertEqual(missingPermission.missingPermissions.map(\.id), ["ios.permission.camera"])
    XCTAssertEqual(missingConsent.code, "missing_consents")
    XCTAssertEqual(missingConsent.missingConsents.map(\.id), ["camera.capture"])
    XCTAssertTrue(ready.allowed)
    XCTAssertEqual(ready.code, "ok")
    XCTAssertEqual(registry.authorize("signalasi.test.setup").code, "tool_unavailable")
    XCTAssertEqual(registry.authorize("signalasi.test.blocked").code, "tool_blocked")
    XCTAssertEqual(registry.authorize("signalasi.missing").code, "unknown_tool")
  }

  func testAgentNativeToolRegistryProtectsIdempotencyKeys() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.idempotent",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let missingKey = registry.authorize("signalasi.test.idempotent", input: ["value": .int(1)])
    let first = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.code, "missing_idempotency_key")
    XCTAssertEqual(first.code, .accepted)
    XCTAssertEqual(replay.code, .replay)
    XCTAssertTrue(replay.replayed)
    XCTAssertEqual(replay.originalInvocationId, "first")
    XCTAssertEqual(conflict.code, .conflict)
  }

  func testAgentNativeToolRegistryAcceptsPhoneCatalogDescriptors() throws {
    let registry = try AgentNativeToolRegistry(definitions: AgentPhoneNativeToolCatalog.definitions(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    ))
    let workspaceDecision = registry.authorize(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("default"),
        "path": .string("notes/today.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )
    let openURL = registry.validateInput(
      AgentNativeToolAgentActionAdapter.defaultToolId(.openURL),
      input: [
        "target": .string("Safari"),
        "url": .string("https://signalasi.com")
      ]
    )

    XCTAssertEqual(registry.ids(), AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertTrue(workspaceDecision.allowed)
    XCTAssertTrue(openURL.isValid)
  }

  func testAgentNativeToolRegistryModelsUseAndroidWireNames() throws {
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "key",
      grantedPermissions: ["permission.b", "permission.a"],
      grantedConsents: ["consent.a"]
    )
    let contextObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any]
    )
    let decision = AgentNativeToolAuthorizationDecision(
      toolId: "signalasi.test.tool",
      allowed: false,
      code: "missing_permissions",
      message: "Missing",
      availability: .available,
      risk: .medium,
      missingPermissions: [AgentNativePermissionRequirement(id: "permission.a")],
      missingConsents: [],
      validationIssues: []
    )
    let decisionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(decision)) as? [String: Any]
    )

    XCTAssertEqual(contextObject["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(contextObject["session_id"] as? String, "session")
    XCTAssertEqual(contextObject["idempotency_key"] as? String, "key")
    XCTAssertEqual(contextObject["granted_permissions"] as? [String], ["permission.a", "permission.b"])
    XCTAssertNil(contextObject["invocationId"])
    XCTAssertEqual(decisionObject["tool_id"] as? String, "signalasi.test.tool")
    XCTAssertNotNil(decisionObject["missing_permissions"])
    XCTAssertNotNil(decisionObject["validation_issues"])
    XCTAssertNil(decisionObject["missingPermissions"])
  }

  func testAgentNativeToolAgentActionAdapterCreatesNativeCallsWithLegacyContext() {
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"],
      requiresConfirmation: true
    )

    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)

    XCTAssertEqual(call.toolId, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertEqual(call.input["target"], .string("Wi-Fi"))
    XCTAssertEqual(call.input["description"], .string("Tap Wi-Fi"))
    XCTAssertEqual(call.input["requires_confirmation"], .bool(true))
    XCTAssertEqual(call.input["parameters"]?.objectValue?["bounds"], .string("[0,0][10,10]"))
    XCTAssertEqual(call.context.invocationId, "legacy-9")
    XCTAssertEqual(call.context.attributes[AgentNativeToolRegistry.legacyActionIdAttribute], "legacy-9")
  }

  func testAgentNativeToolAgentActionAdapterRehydratesLegacyActions() throws {
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium,
      requiredConsents: [
        AgentNativeConsentRequirement(id: "tap.once", title: "Tap once")
      ]
    )
    let call = AgentNativeToolCall(
      toolId: descriptor.id,
      input: [
        "target": .string("Wi-Fi"),
        "description": .string("Tap Wi-Fi"),
        "parameters": .object(["bounds": .string("[0,0][10,10]")])
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-9",
        attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-9"]
      )
    )

    let action = AgentNativeToolAgentActionAdapter.toAgentAction(
      call: call,
      descriptor: descriptor,
      kind: .tap
    )

    XCTAssertEqual(action.id, "legacy-9")
    XCTAssertEqual(action.kind, .tap)
    XCTAssertEqual(action.target, "Wi-Fi")
    XCTAssertEqual(action.risk, .medium)
    XCTAssertEqual(action.status, .running)
    XCTAssertEqual(action.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(action.requiresConfirmation)
  }

  func testAgentNativeToolAgentActionAdapterMapsResultsAndMetadata() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: "legacy.agent_action",
        provenanceMetadata: ["adapter": "AgentActionExecutor"]
      )
    ])
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)
    let nativeResult = registry.makeResult(
      call.toolId,
      input: call.input,
      context: call.context,
      status: .succeeded,
      output: ["action_id": .string(action.id), "success": .bool(true)],
      message: "Tapped",
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_007
    )
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: action.id)
    let failedExecution = AgentNativeToolAgentActionAdapter.fromAgentActionResult(AgentActionResult(
      actionId: action.id,
      success: false,
      message: "Missed target",
      metadata: ["screen": "Settings"]
    ))

    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.message, "Tapped")
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_tool_version"], "1.0.0")
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
    XCTAssertEqual(roundTripped.metadata["native_status"], "succeeded")
    XCTAssertFalse(failedExecution.isSuccess)
    XCTAssertEqual(failedExecution.error?.code, "agent_action_failed")
    XCTAssertEqual(failedExecution.output["metadata"]?.objectValue?["screen"], .string("Settings"))
  }

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.result",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      idempotencyKey: "key-1",
      attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-1"]
    )
    let result = registry.makeResult(
      descriptor.id,
      input: [:],
      context: context,
      status: .rejected,
      message: "Missing permission",
      error: AgentNativeToolError(code: "missing_permissions", message: "Missing permission"),
      verification: AgentNativeToolVerification(status: .skipped),
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_010
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    let callData = try JSONEncoder().encode(AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-1",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap"
    )))
    let callObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: callData) as? [String: Any]
    )

    XCTAssertEqual(receipt["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(receipt["idempotency_key"] as? String, "key-1")
    XCTAssertEqual(receipt["started_at_epoch_ms"] as? Int, 1_000)
    XCTAssertEqual(receipt["finished_at_epoch_ms"] as? Int, 1_010)
    XCTAssertEqual(receipt["duration_ms"] as? Int, 10)
    XCTAssertNotNil(receipt["input_sha256"])
    XCTAssertEqual(provenance["tool_id"] as? String, descriptor.id)
    XCTAssertEqual(provenance["executor_id"] as? String, "test.executor")
    XCTAssertEqual(provenance["legacy_agent_action_id"] as? String, "legacy-1")
    XCTAssertEqual(callObject["tool_id"] as? String, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertNil(receipt["startedAtEpochMillis"])
    XCTAssertNil(provenance["legacyAgentActionId"])
    XCTAssertNil(callObject["toolId"])
  }

  func testAgentNativeToolRegistryBuildsPreflightRejectionResults() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.preflight",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])

    let result = try XCTUnwrap(registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-preflight")
    ))
    let passed = registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-ready",
        grantedPermissions: ["ios.permission.camera"]
      )
    )

    XCTAssertEqual(result.status, .rejected)
    XCTAssertEqual(result.error?.code, "missing_permissions")
    XCTAssertEqual(result.receipt.invocationId, "invoke-preflight")
    XCTAssertEqual(result.provenance.toolId, descriptor.id)
    XCTAssertNil(passed)
  }

  func testAgentNativeToolRegistryInvokeReturnsReceiptProgressAndVerification() throws {
    var now: Int64 = 1_000
    var started = 0
    var progress: [AgentNativeToolProgressUpdate] = []
    var finished = 0
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.invoke",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.executor",
          provenanceMetadata: ["implementation": "fake"]
        ),
        executor: { invocation in
          try invocation.reportProgress(
            stage: "working",
            message: "Preparing output",
            percent: 40,
            sequence: 3
          )
          now += 7
          return .success(
            output: ["value": .string("done")],
            message: "Completed",
            metadata: ["native_call": .string("local")]
          )
        },
        verifier: { _, execution in
          AgentNativeToolVerification(
            status: .passed,
            evidence: ["observed": execution.output["value"] ?? .null]
          )
        }
      ))

    let result = registry.invoke(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-7", requestedAtEpochMillis: now),
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onStarted: { _ in started += 1 },
        onProgress: { _, update in progress.append(update) },
        onFinished: { _ in finished += 1 }
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.output["value"], .string("done"))
    XCTAssertEqual(result.message, "Completed")
    XCTAssertEqual(result.receipt.durationMillis, 7)
    XCTAssertEqual(result.receipt.inputSha256.count, 64)
    XCTAssertEqual(result.receipt.outputSha256.count, 64)
    XCTAssertEqual(result.verification?.status, .passed)
    XCTAssertEqual(result.provenance.executorId, "test.executor")
    XCTAssertEqual(result.provenance.toolVersion, "1.0.0")
    XCTAssertEqual(started, 1)
    XCTAssertEqual(progress.first?.stage, "working")
    XCTAssertEqual(progress.first?.percent, 40)
    XCTAssertEqual(progress.first?.sequence, 3)
    XCTAssertEqual(finished, 1)
    XCTAssertTrue(result.toJson().contains("\"invocation_id\":\"invoke-7\""))
  }

  func testAgentNativeToolRegistryInvokeRejectsInvalidOutputAndFailedVerification() throws {
    let invalidOutput = try nativeToolDescriptor(
      "signalasi.test.invalid-output",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let verificationFailed = try nativeToolDescriptor("signalasi.test.verification")
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: invalidOutput, executorId: "test.executor"),
        executor: { _ in .success(output: ["value": .int(1)], message: "Invalid") }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: verificationFailed, executorId: "test.executor"),
        executor: { _ in .success(message: "Executed") },
        verifier: { _, _ in AgentNativeToolVerification(status: .failed, message: "Screen did not change") }
      ))

    let invalid = registry.invoke(invalidOutput.id, input: [:])
    let failed = registry.invoke(verificationFailed.id, input: [:])

    XCTAssertEqual(invalid.status, .failed)
    XCTAssertEqual(invalid.error?.code, "invalid_output")
    XCTAssertEqual(failed.status, .verificationFailed)
    XCTAssertEqual(failed.error?.code, "verification_failed")
    XCTAssertEqual(failed.verification?.message, "Screen did not change")
  }

  func testAgentNativeToolRegistryInvokeHandlesCancellationTimeoutAndMissingExecutor() throws {
    var now: Int64 = 10
    var cancelledHooks = 0
    var timeoutHooks = 0
    var executions = 0
    let cancelledDescriptor = try nativeToolDescriptor("signalasi.test.cancelled")
    let timedDescriptor = try nativeToolDescriptor("signalasi.test.timeout", timeoutMillis: 5)
    let descriptorOnly = try nativeToolDescriptor("signalasi.test.descriptor-only")
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptorOnly, executorId: "test.executor")
    ])
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: cancelledDescriptor, executorId: "test.executor"),
        executor: { _ in
          executions += 1
          return .success()
        }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: timedDescriptor, executorId: "test.executor"),
        executor: { invocation in
          now += 5
          try invocation.checkpoint()
          return .success()
        }
      ))

    let cancelled = registry.invoke(
      cancelledDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        cancellationRequested: { true },
        onCancelled: { _ in cancelledHooks += 1 }
      )
    )
    let timedOut = registry.invoke(
      timedDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onTimeout: { _ in timeoutHooks += 1 }
      )
    )
    let missingExecutor = registry.invoke(descriptorOnly.id, input: [:])

    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.error?.code, "cancelled")
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(cancelledHooks, 1)
    XCTAssertEqual(timedOut.status, .timedOut)
    XCTAssertEqual(timedOut.error?.code, "timeout")
    XCTAssertEqual(timeoutHooks, 1)
    XCTAssertEqual(missingExecutor.status, .unavailable)
    XCTAssertEqual(missingExecutor.error?.code, "missing_executor")
  }

  func testAgentNativeToolRegistryInvokeReplaysSuccessfulKeyedResults() throws {
    var executions = 0
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.replay",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )

    func registry() throws -> AgentNativeToolRegistry {
      try AgentNativeToolRegistry(replayStore: replayStore)
        .registerExecutable(AgentNativeToolExecutableDefinition(
          definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
          executor: { _ in
            executions += 1
            return .success(output: ["execution": .int(Int64(executions))])
          }
        ))
    }

    let missingKey = try registry().invoke(descriptor.id, input: ["value": .int(1)])
    let first = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = try registry().invoke(
      descriptor.id,
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(first.output, replay.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "first")
    XCTAssertEqual(replay.receipt.invocationId, "second")
    XCTAssertEqual(conflict.status, .rejected)
    XCTAssertEqual(conflict.error?.code, "idempotency_key_conflict")
  }

  func testAgentActionNativeToolExecutorRunsLegacyExecutorThroughRegistry() throws {
    var capturedAction: AgentAction?
    var capturedScreen: AgentScreenContext?
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium
    )
    let delegate = TestAgentActionExecutor { action, screen in
      capturedAction = action
      capturedScreen = screen
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Tapped",
        metadata: ["screen": screen.pageTitle]
      )
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "legacy.agent_action",
          provenanceMetadata: ["adapter": "AgentActionExecutor"]
        ),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
      ))
    let legacy = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"]
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(legacy, toolId: descriptor.id)

    let nativeResult = registry.invoke(call.toolId, input: call.input, context: call.context)
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: legacy.id)

    XCTAssertTrue(nativeResult.toJson(), nativeResult.isSuccess)
    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(capturedAction?.id, "legacy-9")
    XCTAssertEqual(capturedAction?.kind, .tap)
    XCTAssertEqual(capturedAction?.target, "Wi-Fi")
    XCTAssertEqual(capturedAction?.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(capturedAction?.requiresConfirmation == true)
    XCTAssertEqual(capturedScreen?.pageTitle, "Settings")
    XCTAssertEqual(nativeResult.provenance.legacyAgentActionId, "legacy-9")
    XCTAssertEqual(nativeResult.provenance.executorId, "legacy.agent_action")
    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
  }

  func testAgentPhoneNativeToolCatalogBuildsExecutableActionDefinitions() throws {
    var captured: [AgentAction] = []
    let delegate = TestAgentActionExecutor { action, _ in
      captured.append(action)
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Executed \(action.kind.rawValue)"
      )
    }
    let executables = AgentPhoneNativeToolCatalog.actionExecutableDefinitions(
      delegate: delegate,
      screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Browser") },
      capabilityStatuses: readyPhoneCapabilityStatuses()
    )
    let openURL = try XCTUnwrap(
      executables.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(executables)
    let context = AgentNativeToolInvocationContext(
      invocationId: "open-url",
      grantedPermissions: Set(openURL.descriptor.requiredPermissions.filter { $0.required }.map(\.id)),
      grantedConsents: Set(openURL.descriptor.requiredConsents.filter { $0.required }.map(\.id))
    )

    let result = registry.invoke(
      openURL.id,
      input: [
        "target": .string("Safari"),
        "url": .string("https://signalasi.com"),
        "parameters": .object(["url": .string("https://signalasi.com")])
      ],
      context: context
    )

    XCTAssertEqual(Set(executables.map(\.id)), Set(AgentPhoneNativeToolCatalog.supportedActionKinds.map {
      AgentNativeToolAgentActionAdapter.defaultToolId($0)
    }))
    XCTAssertEqual(registry.ids(), Set(executables.map(\.id)))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(captured.first?.kind, .openURL)
    XCTAssertEqual(captured.first?.target, "Safari")
    XCTAssertEqual(captured.first?.parameters["url"], "https://signalasi.com")
    XCTAssertEqual(result.provenance.executorId, AgentPhoneNativeToolCatalog.actionExecutorId)
  }

  func testAgentActionNativeToolExecutorMapsLegacyFailuresToNativeFailures() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "Missed target")
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "legacy.agent_action"),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
      ))
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-failed",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    ))

    let result = registry.invoke(call.toolId, input: call.input, context: call.context)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "agent_action_failed")
    XCTAssertEqual(result.output["action_id"], .string("legacy-failed"))
  }

  func testAgentWorkspaceNativeToolExecutorRunsCoreFileWorkflowThroughRegistry() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 1_234 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "workspace-call",
      idempotencyKey: "workspace-key",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [
        AgentPhoneNativeToolCatalog.workspaceReadConsent,
        AgentPhoneNativeToolCatalog.workspaceWriteConsent
      ]
    )

    let initialized = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("alpha")],
      context: context
    )
    let created = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "text": .string("hello"),
        "create_parents": .bool(true)
      ],
      context: context
    )
    let appended = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceAppendText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "text": .string(" world")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "append",
        idempotencyKey: "append-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let read = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt")
      ],
      context: context
    )
    let listing = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceList,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs"),
        "recursive": .bool(true)
      ],
      context: context
    )
    let patched = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceApplyExactPatch,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "expected_text": .string("world"),
        "replacement_text": .string("iOS")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "patch",
        idempotencyKey: "patch-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let digest = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceSha256,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt")
      ],
      context: context
    )
    let search = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceSearchText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs"),
        "query": .string("ios")
      ],
      context: context
    )

    XCTAssertTrue(initialized.isSuccess)
    XCTAssertEqual(initialized.output["kind"], .string("initialize"))
    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(created.output["affected_entries"], .int(1))
    XCTAssertTrue(appended.isSuccess)
    XCTAssertEqual(read.output["text"], .string("hello world"))
    XCTAssertEqual(read.output["size_bytes"], .int(11))
    XCTAssertEqual((listing.output["entries"]?.arrayValue ?? []).count, 2)
    XCTAssertEqual(patched.output["replacements"], .int(1))
    XCTAssertEqual(digest.output["algorithm"], .string("SHA-256"))
    XCTAssertEqual(digest.output["hex"]?.stringValue?.count, 64)
    XCTAssertEqual((search.output["matches"]?.arrayValue ?? []).count, 1)
  }

  func testAgentWorkspaceNativeToolExecutorSupportsBytesMoveCopyDeleteAndErrors() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 2_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "bytes",
      idempotencyKey: "bytes-key",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [
        AgentPhoneNativeToolCatalog.workspaceReadConsent,
        AgentPhoneNativeToolCatalog.workspaceWriteConsent
      ]
    )
    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("binary")],
      context: context
    )
    let created = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("data/blob.bin"),
        "base64": .string(Data([1, 2, 3]).base64EncodedString()),
        "create_parents": .bool(true)
      ],
      context: context
    )
    let read = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadBytes,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("data/blob.bin")
      ],
      context: context
    )
    let copied = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCopy,
      input: [
        "workspace_id": .string("binary"),
        "source_path": .string("data/blob.bin"),
        "destination_path": .string("copy/blob.bin"),
        "create_parents": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "copy",
        idempotencyKey: "copy-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let moved = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceMove,
      input: [
        "workspace_id": .string("binary"),
        "source_path": .string("copy/blob.bin"),
        "destination_path": .string("moved/blob.bin"),
        "create_parents": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "move",
        idempotencyKey: "move-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let deleted = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceDelete,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("moved"),
        "recursive": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "delete",
        idempotencyKey: "delete-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let escaped = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("../escape.txt"),
        "text": .string("bad")
      ],
      context: context
    )

    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(read.output["base64"], .string(Data([1, 2, 3]).base64EncodedString()))
    XCTAssertEqual(copied.output["affected_entries"], .int(1))
    XCTAssertEqual(moved.output["affected_entries"], .int(1))
    XCTAssertEqual(deleted.output["affected_entries"], .int(2))
    XCTAssertEqual(escaped.status, .failed)
    XCTAssertEqual(escaped.error?.code, "workspace_file_error")
    XCTAssertEqual(escaped.error?.details["workspace_error"]?.objectValue?["code"], .string("PATH_ESCAPE"))
  }

  func testAgentWorkspaceNativeToolExecutorGatesConsentAndReportsInvalidZip() throws {
    let store = AgentWorkspaceNativeToolExecutor()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let missingConsent = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("note.txt"),
        "text": .string("hello")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission]
      )
    )
    let createdBadZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("bundle.zip"),
        "base64": .string(Data("not a zip".utf8).base64EncodedString())
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "bad-zip-create",
        idempotencyKey: "bad-zip-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let invalidZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("alpha"),
        "archive_path": .string("bundle.zip")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )

    XCTAssertEqual(Set(registry.ids()), Set(AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store).map(\.id)))
    XCTAssertEqual(missingConsent.status, .rejected)
    XCTAssertEqual(missingConsent.error?.code, "missing_consents")
    XCTAssertTrue(createdBadZip.isSuccess)
    XCTAssertEqual(invalidZip.status, .failed)
    XCTAssertEqual(invalidZip.error?.details["workspace_error"]?.objectValue?["code"], .string("INVALID_ARCHIVE"))
  }

  func testAgentWorkspaceNativeToolExecutorCreatesListsAndExtractsZipArchives() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 5_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    func writeContext(_ invocationId: String, _ idempotencyKey: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    }
    let readContext = AgentNativeToolInvocationContext(
      invocationId: "zip-read",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
    )

    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("zip")],
      context: writeContext("zip-init", "zip-init-key")
    )
    let firstFile = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("docs/a.txt"),
        "text": .string("alpha"),
        "create_parents": .bool(true)
      ],
      context: writeContext("zip-first-file", "zip-first-key")
    )
    let secondFile = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("docs/nested/b.txt"),
        "text": .string("beta"),
        "create_parents": .bool(true)
      ],
      context: writeContext("zip-second-file", "zip-second-key")
    )
    let createdZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipCreate,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip"),
        "source_paths": .array([.string("docs")])
      ],
      context: writeContext("zip-create", "zip-create-key")
    )
    let listedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip")
      ],
      context: readContext
    )
    let extractedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipExtract,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip"),
        "destination_path": .string("unpacked")
      ],
      context: writeContext("zip-extract", "zip-extract-key")
    )
    let unpackedFirst = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("unpacked/docs/a.txt")
      ],
      context: readContext
    )
    let unpackedSecond = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("unpacked/docs/nested/b.txt")
      ],
      context: readContext
    )

    let createdEntries = createdZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []
    let listedEntries = listedZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []

    XCTAssertTrue(firstFile.isSuccess)
    XCTAssertTrue(secondFile.isSuccess)
    XCTAssertTrue(createdZip.isSuccess)
    XCTAssertGreaterThan(createdZip.output["archive_bytes"]?.intValue ?? 0, 0)
    XCTAssertEqual(createdZip.output["total_compressed_bytes"], .int(9))
    XCTAssertEqual(createdZip.output["total_uncompressed_bytes"], .int(9))
    XCTAssertEqual(createdEntries.compactMap { $0["path"]?.stringValue }, [
      "docs",
      "docs/a.txt",
      "docs/nested",
      "docs/nested/b.txt"
    ])
    XCTAssertEqual(createdEntries.filter { $0["directory"]?.boolValue == false }.count, 2)
    XCTAssertTrue(createdEntries.allSatisfy { $0["last_modified_epoch_ms"] != nil })
    XCTAssertTrue(listedZip.isSuccess)
    XCTAssertEqual(listedZip.output["archive_bytes"], createdZip.output["archive_bytes"])
    XCTAssertEqual(listedEntries.compactMap { $0["path"]?.stringValue }, createdEntries.compactMap { $0["path"]?.stringValue })
    XCTAssertTrue(extractedZip.isSuccess)
    XCTAssertEqual(extractedZip.output["extracted_entries"], .int(4))
    XCTAssertEqual(extractedZip.output["extracted_bytes"], .int(9))
    XCTAssertEqual(unpackedFirst.output["text"], .string("alpha"))
    XCTAssertEqual(unpackedSecond.output["text"], .string("beta"))
  }

  func testAgentWorkspaceNativeToolExecutorExtractsDeflatedZipArchives() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 6_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    func writeContext(_ invocationId: String, _ idempotencyKey: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    }
    let readContext = AgentNativeToolInvocationContext(
      invocationId: "zip-deflate-read",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
    )

    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("zip-deflate")],
      context: writeContext("zip-deflate-init", "zip-deflate-init-key")
    )
    let createdZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("bundle.zip"),
        "base64": .string(deflatedZipArchive(
          ("docs/a.txt", "alpha"),
          ("docs/nested/b.txt", "beta")
        ).base64EncodedString())
      ],
      context: writeContext("zip-deflate-create", "zip-deflate-create-key")
    )
    let listedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("zip-deflate"),
        "archive_path": .string("bundle.zip")
      ],
      context: readContext
    )
    let extractedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipExtract,
      input: [
        "workspace_id": .string("zip-deflate"),
        "archive_path": .string("bundle.zip"),
        "destination_path": .string("unpacked")
      ],
      context: writeContext("zip-deflate-extract", "zip-deflate-extract-key")
    )
    let unpackedFirst = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("unpacked/docs/a.txt")
      ],
      context: readContext
    )
    let unpackedSecond = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("unpacked/docs/nested/b.txt")
      ],
      context: readContext
    )

    let listedEntries = listedZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []

    XCTAssertTrue(createdZip.isSuccess)
    XCTAssertTrue(listedZip.isSuccess)
    XCTAssertEqual(listedEntries.compactMap { $0["path"]?.stringValue }, ["docs/a.txt", "docs/nested/b.txt"])
    XCTAssertEqual(listedZip.output["total_uncompressed_bytes"], .int(9))
    XCTAssertTrue(extractedZip.isSuccess)
    XCTAssertEqual(extractedZip.output["extracted_entries"], .int(2))
    XCTAssertEqual(extractedZip.output["extracted_bytes"], .int(9))
    XCTAssertEqual(unpackedFirst.output["text"], .string("alpha"))
    XCTAssertEqual(unpackedSecond.output["text"], .string("beta"))
  }

  func testAgentPlanFactoryCollapsesDuplicateConnectorCallsAndRemapsDependencies() {
    let first = planConnectorAction(id: "codex-1", connectorId: "desktop:codex")
    let duplicate = planConnectorAction(id: "codex-2", connectorId: "desktop:codex")
    let dependent = AgentAction(
      id: "finish",
      kind: .createNotification,
      target: "phone",
      risk: .low,
      status: .pendingConfirmation,
      description: "Notify when complete",
      parameters: ["depends_on": duplicate.id]
    )

    let plan = AgentPlanFactory.actions(request: planFactoryRequest(), [first, duplicate, dependent])

    XCTAssertEqual(plan.actions.map(\.id), ["codex-1", "finish"])
    XCTAssertEqual(plan.actions.last?.parameters["depends_on"], "codex-1")
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryKeepsDifferentConnectorsIndependent() {
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(
        targets: [
          planFactoryTarget(id: "desktop:codex", title: "Codex"),
          planFactoryTarget(id: "desktop:hermes", title: "Hermes")
        ]
      ),
      [
        planConnectorAction(id: "codex", connectorId: "desktop:codex", target: "Codex"),
        planConnectorAction(id: "hermes", connectorId: "desktop:hermes", target: "Hermes")
      ]
    )

    XCTAssertEqual(plan.actions.map(\.id), ["codex", "hermes"])
    XCTAssertEqual(plan.selectedAgentOrModel, "Multiple Executors")
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryEmptyPlanFallsBackToAvailableReasoningConnector() {
    let plan = AgentPlanFactory.actions(request: planFactoryRequest(), [])
    let action = plan.actions.first

    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(action?.kind, .callConnector)
    XCTAssertEqual(action?.parameters["connector_id"], "desktop:codex")
    XCTAssertEqual(action?.parameters["planner_fallback"], "empty_action_plan")
    XCTAssertFalse(plan.actions.contains { $0.target == "local-agent-runtime" })
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryEmptyPlanWithoutProviderFailsExplicitly() {
    let plan = AgentPlanFactory.actions(request: planFactoryRequest(targets: []), [])
    let action = plan.actions.first

    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(action?.kind, .callConnector)
    XCTAssertEqual(action?.parameters["connector_id"], AgentPlanFactory.unavailableReasoningConnectorId)
    XCTAssertFalse(plan.actions.contains { $0.target == "local-agent-runtime" })
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryKeepsRecoveringConnectorAuthorizedDuringHeartbeat() {
    let recovering = planFactoryTarget(
      id: "desktop:codex",
      title: "Codex",
      status: .disconnected,
      capabilities: [.chat, .reasoning]
    )
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(targets: [recovering]),
      [planConnectorAction(id: "codex", connectorId: recovering.id, target: recovering.title)]
    )

    XCTAssertEqual(plan.requiredPermissions.single { $0.id == "paired_contact" }?.granted, true)
    XCTAssertEqual(plan.route.kind, .desktopAgent)
  }

  func testAgentPlanFactoryDoesNotAuthorizeConnectorThatNeedsSetup() {
    let unavailable = planFactoryTarget(
      id: "desktop:codex",
      title: "Codex",
      status: .needsSetup,
      capabilities: [.chat, .reasoning]
    )
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(targets: [unavailable]),
      [planConnectorAction(id: "codex", connectorId: unavailable.id, target: unavailable.title)]
    )

    XCTAssertEqual(plan.requiredPermissions.single { $0.id == "paired_contact" }?.granted, false)
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanRequestModelsUseAndroidWireNames() throws {
    let request = AgentPlanRequest(
      goal: "Convert the file",
      screen: AgentScreenContext(foregroundApp: "SignalASI"),
      targets: [planFactoryTarget()],
      nativeTools: [try nativeToolDescriptor("signalasi.test.native")],
      contextDigest: "digest"
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(object["context_digest"] as? String, "digest")
    XCTAssertNotNil(object["native_tools"])
    XCTAssertNil(object["contextDigest"])
    XCTAssertNil(object["nativeTools"])
  }

  func testAgentDynamicTeamCompilerBuildsVerifiedDagFromComplementaryAgents() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Research the latest API and implement a Python program with high quality",
        teamId: "dynamic-team"
      ),
      registrations: [
        networkRegistration(
          agentId: "hermes.office",
          displayName: "Hermes - Office PC",
          capabilities: [.chat, .reasoning, .research, .liveData, .toolUse],
          failureDomain: "desktop-office"
        ),
        networkRegistration(
          agentId: "codex.dev",
          displayName: "Codex - Development PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution, .toolUse],
          latency: .fast,
          failureDomain: "desktop-dev"
        ),
        networkRegistration(
          agentId: "claude-code.review",
          displayName: "Claude Code - Review PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution],
          failureDomain: "desktop-review"
        ),
        networkRegistration(
          agentId: "auditor.independent",
          displayName: "Independent Auditor",
          capabilities: [.chat, .reasoning, .research],
          failureDomain: "cloud-audit"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(result.outcome, .team)
    XCTAssertEqual(result.primaryAgentId, "codex.dev")
    XCTAssertEqual(
      Set(result.assignments.map { $0.registration.agentId }),
      Set(["codex.dev", "hermes.office", "claude-code.review", "auditor.independent"])
    )
    let definition = try XCTUnwrap(result.definition)
    XCTAssertEqual(definition.members.filter { $0.deliveryMode == .respond }.count, 1)
    XCTAssertEqual(definition.collectiveCapabilities, Set([AgentCapability.liveData, AgentCapability.code]))
    let verifier = try XCTUnwrap(definition.members.first { $0.role == "independent verifier" })
    XCTAssertEqual(verifier.dependsOnAgentIds, Set(["hermes.office", "claude-code.review"]))
    let lead = try XCTUnwrap(definition.members.first { $0.agentId == result.primaryAgentId })
    XCTAssertEqual(
      lead.dependsOnAgentIds,
      Set(definition.members.filter { $0.deliveryMode == .observe }.map { $0.agentId })
    )
  }

  func testAgentDynamicTeamCompilerKeepsSimpleConversationSingleAgentAndHonorsPinnedIdentity() {
    let simple = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Hello"),
      registrations: [
        networkRegistration(agentId: "hermes", displayName: "Hermes", capabilities: [.chat, .reasoning])
      ],
      nowMillis: 1_000_000
    )
    let pinned = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Discuss the architecture",
        policy: AgentDynamicTeamPolicy(pinnedAgentIds: ["hermes.home"])
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.office",
          displayName: "Codex - Office PC",
          capabilities: [.chat, .reasoning],
          latency: .instant
        ),
        networkRegistration(
          agentId: "hermes.home",
          displayName: "Hermes - Home PC",
          capabilities: [.chat, .reasoning],
          latency: .normal
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(simple.outcome, .singleAgent)
    XCTAssertEqual(simple.primaryAgentId, "hermes")
    XCTAssertNil(simple.definition)
    XCTAssertEqual(pinned.primaryAgentId, "hermes.home")
    XCTAssertEqual(pinned.assignments.first?.registration.displayName, "Hermes - Home PC")
  }

  func testAgentDynamicTeamCompilerAppliesPrivacyVerifierAndRuntimeIdentityBoundaries() {
    let privateResult = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Handle my private key locally only"),
      registrations: [
        networkRegistration(
          agentId: "phone.agent",
          displayName: "Phone Agent",
          location: .phone,
          trust: .phoneSystem,
          capabilities: [.chat, .reasoning],
          failureDomain: "phone"
        ),
        networkRegistration(
          agentId: "cloud.agent",
          displayName: "Cloud Agent",
          location: .cloud,
          trust: .cloudConfigured,
          capabilities: [.chat, .reasoning],
          failureDomain: "cloud"
        )
      ],
      nowMillis: 1_000_000
    )
    let sameDomain = [
      networkRegistration(
        agentId: "codex",
        displayName: "Codex",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      ),
      networkRegistration(
        agentId: "claude-code",
        displayName: "Claude Code",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      )
    ]
    let requiredVerifierRequest = AgentDynamicTeamRequest(
      goal: "Implement and verify a Python program",
      policy: AgentDynamicTeamPolicy(verificationMode: .required)
    )
    let blocked = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain,
      nowMillis: 1_000_000
    )
    let verified = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain + [
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let aliasBlocked = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        policy: AgentDynamicTeamPolicy(forceTeam: true)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.alias-one",
          displayName: "Codex",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        ),
        networkRegistration(
          agentId: "codex.alias-two",
          displayName: "Codex Alias",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(privateResult.primaryAgentId, "phone.agent")
    XCTAssertFalse(privateResult.assignments.contains { $0.registration.location == .cloud })
    XCTAssertEqual(blocked.outcome, .blocked)
    XCTAssertTrue(blocked.unfilledRoles.contains(.verifier))
    XCTAssertEqual(verified.outcome, .team)
    XCTAssertEqual(verified.assignments.first { $0.role == .verifier }?.failureDomain, "desktop-two")
    XCTAssertEqual(aliasBlocked.outcome, .blocked)
    XCTAssertEqual(aliasBlocked.assignments.count, 1)
  }

  func testAgentDynamicTeamCompilerModelsUseAndroidWireNames() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        teamId: "wire-team",
        policy: AgentDynamicTeamPolicy(verificationMode: .required)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex",
          displayName: "Codex",
          capabilities: [.chat, .code, .reasoning],
          failureDomain: "desktop-one"
        ),
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let definition = try XCTUnwrap(object["definition"] as? [String: Any])
    let members = try XCTUnwrap(definition["members"] as? [[String: Any]])

    XCTAssertEqual(object["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(object["estimated_cost_units"] as? Int, 0)
    XCTAssertNotNil(object["unfilled_roles"])
    XCTAssertEqual(definition["team_id"] as? String, "wire-team")
    XCTAssertEqual(definition["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(definition["visibility_mode"] as? String, "BACKGROUND")
    XCTAssertEqual(members.first?["delivery_mode"] as? String, "RESPOND")
    XCTAssertNotNil(members.first?["depends_on_agent_ids"])
    XCTAssertNil(object["primaryAgentId"])
    XCTAssertNil(definition["primaryAgentId"])
  }

  func testAgentTeamPlanBridgeCompilesBranchedGraphIntoOneSupervisedTeamAction() throws {
    let research = teamActionWithAgentKnowledge(
      teamAgentAction("research", "researcher"),
      "research-only"
    )
    let review = teamAgentAction("review", "reviewer")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research", "review"],
      outputSources: ["research", "review"]
    )
    let synthesisWithKnowledge = teamActionWithAgentKnowledge(synthesis, "lead-only")

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, review, synthesisWithKnowledge),
      targets: teamTargets(),
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 1)
    let action = try XCTUnwrap(compiled.actions.first)
    XCTAssertTrue(action.id.hasPrefix("agent-team-"))
    XCTAssertTrue(Int64(action.parameters[agentTeamSourceParameter] ?? "0") ?? 0 > 0)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "lead")
    XCTAssertEqual(spec.definition.members.count, 3)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.deliveryMode, .respond)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.dependsOnAgentIds, Set(["researcher", "reviewer"]))
    XCTAssertTrue(spec.definition.members.filter { $0.agentId != "lead" }.allSatisfy { $0.deliveryMode == .observe })
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "researcher" }?.context["_signalasi_agent_knowledge_context"],
      "research-only"
    )
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "lead" }?.context["_signalasi_agent_knowledge_context"],
      "lead-only"
    )
    XCTAssertTrue(compiled.validation.valid)
  }

  func testAgentTeamPlanBridgeRemapsDownstreamDependenciesAndRejectsUnsafeGraphs() {
    let research = teamAgentAction("research", "researcher")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research"],
      outputSources: ["research"]
    )
    let downstream = teamConnectorAction(
      "publish",
      "cloud",
      kind: .model,
      dependsOn: ["synthesis"],
      outputSources: ["synthesis"]
    )
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, synthesis, downstream),
      targets: teamTargets() + [teamTarget("cloud", kind: .model)],
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 2)
    let teamId = compiled.actions[0].id
    XCTAssertEqual(compiled.actions[1].parameters["depends_on"], teamId)
    XCTAssertEqual(compiled.actions[1].parameters["use_outputs_from"], teamId)
    XCTAssertTrue(compiled.validation.valid)

    let independent = teamBridgePlan(teamAgentAction("first", "researcher"), teamAgentAction("second", "lead"))
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: independent, targets: teamTargets(), enabled: true).actions,
      independent.actions
    )

    let external = teamBridgePlan(
      AgentAction(
        id: "phone-step",
        kind: .draftPlan,
        target: "phone",
        risk: .low,
        status: .pendingConfirmation,
        description: "Prepare phone evidence"
      ),
      teamAgentAction("research", "researcher", dependsOn: ["phone-step"]),
      teamAgentAction("synthesis", "lead", dependsOn: ["research"])
    )
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: external, targets: teamTargets(), enabled: true).actions,
      external.actions
    )
  }

  func testAgentTeamPlanBridgeCompilesComplexSingleAgentPlanIntoDynamicTeam() throws {
    let original = teamBridgePlan(
      goal: "Implement and verify a Python API using current documentation",
      teamAgentAction("implement", "codex")
    )
    let targets = [
      AgentCallableTarget(
        id: "codex",
        title: "Codex - Development PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .code, .taskExecution],
        failureDomain: "desktop-development",
        adapterType: "codex-app-server"
      ),
      AgentCallableTarget(
        id: "hermes",
        title: "Hermes - Research PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .research, .liveData, .knowledgeSearch],
        failureDomain: "desktop-research",
        adapterType: "hermes-cli"
      )
    ]
    let registrations = targets.map(teamRegistration)

    let compiled = AgentTeamPlanCompiler.compile(
      plan: original,
      targets: targets,
      enabled: true,
      registrations: registrations
    )

    let action = try XCTUnwrap(compiled.actions.first)
    let rawSpecObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data((action.parameters[agentTeamSpecParameter] ?? "").utf8)) as? [String: Any]
    )
    let rawMembers = try XCTUnwrap(rawSpecObject["members"] as? [[String: Any]])
    let codexContext = try XCTUnwrap(
      rawMembers.first { $0["agent_id"] as? String == "codex" }?["context"] as? [String: Any]
    )
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "codex")
    XCTAssertEqual(Set(spec.definition.members.map(\.agentId)), Set(["codex", "hermes"]))
    XCTAssertEqual(spec.definition.collectiveCapabilities, Set([AgentCapability.code, AgentCapability.liveData, AgentCapability.knowledgeSearch]))
    XCTAssertEqual(codexContext["compiled_role"] as? String, "lead")
    XCTAssertTrue(compiled.validation.valid)

    let simple = teamBridgePlan(goal: "Hello", teamAgentAction("chat", "codex"))
    XCTAssertNil(AgentTeamPlanCompiler.compile(
      plan: simple,
      targets: targets,
      enabled: true,
      registrations: registrations
    ).actions.first?.parameters[agentTeamSpecParameter])
  }

  func testAgentTeamDispatchSpecRejectsMalformedAndRetryRekeysAttempt() throws {
    let valid = AgentTeamDispatchSpec(
      definition: AgentTeamDefinition(
        teamId: "team",
        primaryAgentId: "lead",
        members: [
          AgentTeamMember(
            agentId: "researcher",
            deliveryMode: .observe,
            requiredCapabilities: [],
            role: "research specialist",
            objective: "",
            dependsOnAgentIds: [],
            context: [:]
          ),
          AgentTeamMember(
            agentId: "lead",
            deliveryMode: .respond,
            requiredCapabilities: [],
            role: "lead synthesizer",
            objective: "",
            dependsOnAgentIds: ["researcher"],
            context: [:]
          )
        ],
        visibilityMode: .background,
        collectiveCapabilities: []
      ),
      supervisorRunId: "run"
    )
    let encoded = AgentTeamDispatchSpecCodec.encode(valid)
      .replacingOccurrences(of: "\"delivery_mode\":\"OBSERVE\"", with: "\"delivery_mode\":\"RESPOND\"")

    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(encoded))
    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(#"{"version":1}"#))

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let original = try XCTUnwrap(compiled.actions.first)
    let retry = AgentTeamPlanCompiler.rekeyAgentTeamForRetry(original)
    let originalSpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(original.parameters[agentTeamSpecParameter] ?? ""))
    let retrySpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(retry.parameters[agentTeamSpecParameter] ?? ""))

    XCTAssertNotEqual(originalSpec.definition.teamId, retrySpec.definition.teamId)
    XCTAssertNotEqual(originalSpec.supervisorRunId, retrySpec.supervisorRunId)
    XCTAssertNotEqual(originalSpec.sourceMessageId, retrySpec.sourceMessageId)
    XCTAssertEqual(retry.parameters[agentTeamRunParameter], retrySpec.supervisorRunId)
    XCTAssertEqual(retry.parameters[agentTeamSourceParameter], String(retrySpec.sourceMessageId))
  }

  func testAgentTeamPlanBridgeModelsUseAndroidWireNames() throws {
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let action = try XCTUnwrap(compiled.actions.first)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    let specObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(AgentTeamDispatchSpecCodec.encode(spec).utf8)) as? [String: Any]
    )

    XCTAssertEqual(specObject["supervisor_run_id"] as? String, spec.supervisorRunId)
    XCTAssertEqual(specObject["team_id"] as? String, spec.definition.teamId)
    XCTAssertEqual(specObject["primary_agent_id"] as? String, "lead")
    XCTAssertEqual(specObject["visibility"] as? String, "BACKGROUND")
    XCTAssertNotNil(specObject["collective_capabilities"])
    XCTAssertEqual(action.parameters[agentTeamRunParameter], spec.supervisorRunId)
    XCTAssertEqual(action.parameters[agentTeamSourceParameter], String(spec.sourceMessageId))
    XCTAssertEqual(spec.responseContactId, "agent-team:\(spec.definition.teamId)")
    XCTAssertGreaterThanOrEqual(spec.sourceMessageId, Int64(1) << 62)
    XCTAssertNil(specObject["supervisorRunId"])
    XCTAssertNil(specObject["primaryAgentId"])
  }

  func testAgentTeamCompletionSinkPublishesOneDurableConnectorResponse() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let deliveryLedger = AgentTeamCompletionDeliveryLedger()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: deliveryLedger,
      nowMillis: { 20_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "completion-supervisor",
      teamId: "completion-team",
      conversationId: "completion-conversation",
      taskId: "completion-turn",
      primaryAgentId: "lead",
      goal: "Produce one answer",
      state: .succeeded,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          role: "lead synthesizer",
          deliveryMode: .respond,
          status: .succeeded,
          output: "single final answer"
        )
      ],
      finalOutput: "single final answer",
      updatedAtMillis: 10_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertFalse(sink.publish(snapshot))
    let pending = responseStore.pending()

    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].content, "single final answer")
    XCTAssertEqual(pending[0].turnId, "completion-turn")
    XCTAssertEqual(pending[0].taskId, "completion-turn")
    XCTAssertEqual(pending[0].conversationId, "completion-conversation")
    XCTAssertEqual(pending[0].contactId, AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId))
    XCTAssertEqual(pending[0].sourceMessageId, AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId))
    XCTAssertTrue(pending[0].success)
    XCTAssertEqual(pending[0].receivedAtMillis, 20_000)
    XCTAssertEqual(deliveryLedger.snapshot(), ["completion-supervisor"])

    sink.remove(supervisorRunId: "completion-supervisor")
    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertEqual(responseStore.pending().count, 2)
  }

  func testAgentTeamCompletionSinkPublishesFailureResponseWithReason() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: AgentTeamCompletionDeliveryLedger(),
      nowMillis: { 3_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "failed-supervisor",
      teamId: "failed-team",
      taskId: "failed-turn",
      primaryAgentId: "lead",
      state: .failed,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          deliveryMode: .respond,
          status: .failed,
          errorMessage: "primary Agent timed out"
        )
      ],
      updatedAtMillis: 2_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    let response = responseStore.pending().first

    XCTAssertEqual(response?.success, false)
    XCTAssertEqual(response?.content, "Agent team failed: primary Agent timed out")
    XCTAssertEqual(response?.contactId, "agent-team:failed-team")
    XCTAssertEqual(response?.receivedAtMillis, 3_000)
  }

  func testAgentManagedResponseLedgerCompletesAcknowledgesAndPublishesLateResponses() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    AgentLateManagedResponseBus.shared.clear()
    var lateResponses: [AgentManagedResponseRecord] = []
    let token = AgentLateManagedResponseBus.shared.addListener { lateResponses.append($0) }
    defer {
      AgentLateManagedResponseBus.shared.removeListener(token)
    }

    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-old",
      supervisorRunId: "supervisor",
      agentId: "observer",
      deliveryMode: .observe,
      sourceMessageId: 41,
      contactId: "observer",
      createdAtMillis: 1_000
    ))
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 42,
      contactId: "primary",
      createdAtMillis: 2_000
    ))

    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old", "child-primary"])
    XCTAssertNil(ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "other", content: "wrong")))

    let response = AgentConnectorResponse(
      sourceMessageId: 42,
      contactId: "",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )
    let completed = try XCTUnwrap(ledger.complete(response))

    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(completed.completedAtMillis, 9_000)
    XCTAssertEqual(lateResponses.map(\.ownerRunId), ["child-primary"])
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    _ = ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "primary", content: "duplicate"))
    XCTAssertEqual(lateResponses.count, 1)

    let acknowledged = try XCTUnwrap(ledger.acknowledge(response))
    XCTAssertEqual(acknowledged.state, .applied)
    XCTAssertTrue(ledger.completedUnapplied().isEmpty)
    ledger.removeOwner("child-primary")
    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old"])
  }

  func testAgentManagedResponseCodecUsesAndroidWireNamesAndBoundsPayloads() throws {
    let content = String(repeating: "a", count: AgentConnectorResponse.maxContentCharacters + 50)
    let rich = String(repeating: "b", count: AgentConnectorResponse.maxRichOutputCharacters + 50)
    let record = AgentManagedResponseRecord(
      ownerRunId: "child",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 77,
      contactId: "primary",
      state: .completed,
      response: AgentConnectorResponse(
        sourceMessageId: 77,
        contactId: "primary",
        content: content,
        conversationId: "conversation",
        turnId: "turn",
        taskId: "task",
        inputTokens: 11,
        outputTokens: 22,
        costMicros: 33,
        richOutputJson: rich,
        receivedAtMillis: 4_000
      ),
      createdAtMillis: 1_000,
      completedAtMillis: 4_000
    )

    let encoded = AgentManagedResponseCodec.encode([record])
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.first)
    let response = try XCTUnwrap(object["response"] as? [String: Any])
    let decoded = AgentManagedResponseCodec.decode(encoded)

    XCTAssertEqual(object["owner_run_id"] as? String, "child")
    XCTAssertEqual(object["supervisor_run_id"] as? String, "supervisor")
    XCTAssertEqual(object["delivery_mode"] as? String, "RESPOND")
    XCTAssertEqual(object["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["conversation_id"] as? String, "conversation")
    XCTAssertEqual(response["turn_id"] as? String, "turn")
    XCTAssertEqual(response["input_tokens"] as? Int, 11)
    XCTAssertEqual((response["content"] as? String)?.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual((response["rich_output"] as? String)?.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertNil(object["ownerRunId"])
    XCTAssertEqual(decoded.first?.response?.content.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual(decoded.first?.response?.richOutputJson.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertTrue(AgentManagedResponseCodec.decode(#"[{"owner_run_id":"","source_message_id":0}]"#).isEmpty)
  }

  func testAgentCrossTeamDelegationLaunchRequestUsesIsolatedContext() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam()
    let input = crossTeamInput(
      constraints: ["Use public evidence only"],
      expectedOutput: "A concise verified answer",
      evidence: [
        AgentDelegationEvidence(
          evidenceId: "evidence-one",
          summary: "The API changed in the latest release.",
          sourceAgentId: "hermes-source",
          contentHash: "ABC123"
        )
      ]
    )

    let prepared = try fixture.coordinator.prepare(
      input: input,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let admission = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let request = try XCTUnwrap(admission.launchSpec?.request)

    XCTAssertEqual(admission.record.state, .authorized)
    XCTAssertEqual(request.conversationId, "delegation:\(input.delegationId)")
    XCTAssertEqual(request.parentRunId, input.sourceRunId)
    XCTAssertEqual(request.requiredCapabilities, Set([AgentCapability.chat]))
    XCTAssertTrue(request.goal.contains("Use public evidence only"))
    XCTAssertTrue(request.goal.contains("The API changed in the latest release."))
    XCTAssertNil(request.context["conversation_history"])
    XCTAssertNil(request.context["internal_memory"])
    XCTAssertNil(request.context["system_prompt"])
    XCTAssertNil(request.context["checkpoint"])
    XCTAssertEqual(request.context["cross_team_delegation"]?.boolValue, true)
  }

  func testAgentCrossTeamDelegationArtifactManifestWaitsForGrantAndOmitsUris() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam()
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(artifacts: [
        AgentDelegationArtifactManifest(
          artifactId: "artifact-one",
          name: "report.pdf",
          mimeType: "APPLICATION/PDF",
          contentHash: "DEADBEEF",
          sizeBytes: 1_024
        )
      ]),
      destination: destination,
      registrations: crossTeamRegistrations()
    )

    XCTAssertEqual(prepared.state, .waitingConfirmation)
    _ = try fixture.grants.grant(crossTeamGrant(subjectId: "codex-destination", lifetime: .permanent))
    let admitted = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let encoded = AgentCrossTeamDelegationCodec.encodeEnvelope(admitted.record.envelope)

    XCTAssertEqual(admitted.record.state, .authorized)
    XCTAssertNotNil(admitted.launchSpec)
    XCTAssertTrue(encoded.contains("artifact-one"))
    XCTAssertTrue(encoded.contains("application/pdf"))
    XCTAssertFalse(encoded.contains("content://"))
    XCTAssertFalse(encoded.contains("file://"))
    XCTAssertFalse(encoded.contains("\"uri\""))
  }

  func testAgentCrossTeamDelegationResumesDispatchesAndReturnsPrimaryOutputOnly() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam(includeObserver: true)
    let registrations = crossTeamRegistrations(includeObserver: true)
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(),
      destination: destination,
      registrations: registrations
    )
    let firstAdmission = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: registrations
    )
    let resumed = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: registrations
    )
    let request = try XCTUnwrap(resumed.launchSpec?.request)

    XCTAssertEqual(firstAdmission.record.state, .authorized)
    XCTAssertEqual(firstAdmission.launchSpec?.request.runId, request.runId)
    let dispatched = try fixture.coordinator.markDispatched(
      delegationId: prepared.envelope.delegationId,
      destinationRunId: request.runId
    )
    let finished = try fixture.coordinator.finish(
      delegationId: prepared.envelope.delegationId,
      snapshot: AgentTeamExecutionSnapshot(
        supervisorRunId: dispatched.destinationRunId,
        teamId: destination.teamId,
        taskId: "delegated-task",
        primaryAgentId: destination.primaryAgentId,
        state: .succeeded,
        members: [
          AgentTeamMemberSnapshot(
            agentId: destination.primaryAgentId,
            deliveryMode: .respond,
            status: .succeeded,
            output: "Final delegated result"
          ),
          AgentTeamMemberSnapshot(
            agentId: "hermes-observer",
            deliveryMode: .observe,
            status: .succeeded,
            output: "Private observer evidence"
          )
        ],
        finalOutput: "Final delegated result",
        updatedAtMillis: crossTeamNow + 1_000
      )
    )

    XCTAssertEqual(dispatched.state, .dispatched)
    XCTAssertEqual(finished.state, .returned)
    XCTAssertEqual(finished.resultSummary, "Final delegated result")
    XCTAssertFalse(finished.resultSummary.contains("Private observer evidence"))
  }

  func testAgentCrossTeamDelegationCodecAndDenialsUseAndroidContract() throws {
    let fixture = crossTeamFixture()
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(
        constraints: ["No network writes"],
        evidence: [AgentDelegationEvidence(evidenceId: "evidence-one", summary: "A bounded summary", sourceAgentId: "source-agent")]
      ),
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    let encodedEnvelope = AgentCrossTeamDelegationCodec.encodeEnvelope(prepared.envelope)
    let encodedRecords = AgentCrossTeamDelegationCodec.encodeRecords([prepared])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encodedEnvelope.utf8)) as? [String: Any])
    let returnContract = try XCTUnwrap(object["return_contract"] as? [String: Any])

    XCTAssertEqual(object["delegation_id"] as? String, "delegation-one")
    XCTAssertEqual(object["source_team_id"] as? String, "team-source")
    XCTAssertEqual(returnContract["maximum_characters"] as? Int, 16_000)
    XCTAssertNil(object["delegationId"])
    XCTAssertEqual(AgentCrossTeamDelegationCodec.decodeEnvelope(encodedEnvelope), prepared.envelope)
    XCTAssertEqual(AgentCrossTeamDelegationCodec.decodeRecords(encodedRecords), [prepared])
    XCTAssertFalse(encodedEnvelope.contains("conversation_history"))
    XCTAssertFalse(encodedEnvelope.contains("internal_memory"))
    XCTAssertFalse(encodedEnvelope.contains("system_prompt"))

    let denied = try fixture.coordinator.prepare(
      input: crossTeamInput(delegationId: "delegation-denied", nonce: "delegation-nonce-0002", delegationDepth: 4),
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    let deniedAdmission = try fixture.coordinator.admit(
      delegationId: denied.envelope.delegationId,
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    XCTAssertEqual(denied.state, .denied)
    XCTAssertTrue(denied.policyReasonCodes.contains("delegation_depth_exceeded"))
    XCTAssertNil(deniedAdmission.launchSpec)

    let changed = AgentTeamDefinition(
      teamId: crossTeamDestinationTeam().teamId,
      primaryAgentId: "codex-destination",
      members: crossTeamDestinationTeam().members + [
        AgentTeamMember(
          agentId: "unreviewed-agent",
          deliveryMode: .observe,
          requiredCapabilities: [.chat],
          role: "observer",
          objective: "",
          dependsOnAgentIds: [],
          context: [:]
        )
      ],
      visibilityMode: .background,
      collectiveCapabilities: [.chat]
    )
    XCTAssertThrowsError(try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: changed,
      registrations: crossTeamRegistrations()
    )) { error in
      XCTAssertTrue("\(error)".contains("members changed"))
    }
  }

  func testAgentConnectorResponseBusInterceptsManagedResponsesOnce() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(registry: registry, store: store, nowMillis: { 10_000 })
    var intercepted: [AgentConnectorResponse] = []
    try registry.register(
      sourceMessageId: 73,
      contactId: "codex",
      ownerId: "managed-run"
    ) { response in
      intercepted.append(response)
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "Reviewed result",
      inputTokens: 10,
      outputTokens: 4
    )

    XCTAssertTrue(bus.publish(response))
    XCTAssertFalse(registry.consume(response))
    XCTAssertEqual(intercepted.map(\.content), ["Reviewed result"])
    XCTAssertTrue(store.pending().isEmpty)

    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(store.pending().map(\.content), ["Reviewed result"])
  }

  func testAgentConnectorResponseBusCompletesManagedLedgerBeforeStore() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 9001,
      contactId: "primary",
      createdAtMillis: 1_000
    ))
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: ledger,
      store: store,
      nowMillis: { 10_000 }
    )

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )))
    XCTAssertTrue(store.pending().isEmpty)
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "duplicate",
      receivedAtMillis: 9_500
    )))
    XCTAssertTrue(store.pending().isEmpty)
  }

  func testAgentConnectorResponseBusFallbacksRichOutputAndNotifiesListeners() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      store: store,
      nowMillis: { 10_000 }
    )
    let rich = #"{"version":1,"blocks":[{"type":"text","text":"Rendered rich answer","title":"","fallback_text":"","uri":""}]}"#
    var notified: [AgentConnectorResponse] = []
    let token = bus.addListener { notified.append($0) }
    defer { bus.removeListener(token) }

    XCTAssertFalse(bus.publish(AgentConnectorResponse(
      sourceMessageId: 501,
      contactId: "codex",
      content: "",
      richOutputJson: rich
    )))

    XCTAssertEqual(store.pending().map(\.content), ["Rendered rich answer"])
    XCTAssertEqual(notified.map(\.content), ["Rendered rich answer"])
    XCTAssertFalse(store.pending().first?.richOutputJson.isEmpty ?? true)
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 0, content: "invalid")))
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 502, content: "", richOutputJson: "{}")))
  }

  func testAgentConnectorResponseStoreBoundsDedupeExpiryAndAndroidWireNames() throws {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    for index in 0..<35 {
      store.append(AgentConnectorResponse(
        sourceMessageId: Int64(index + 1),
        contactId: "codex",
        content: "answer-\(index)",
        receivedAtMillis: Int64(index + 1)
      ))
    }
    XCTAssertEqual(store.pending().count, AgentConnectorResponseStore.maxResponses)
    XCTAssertEqual(store.pending().first?.sourceMessageId, 6)

    store.append(AgentConnectorResponse(
      sourceMessageId: 35,
      contactId: "codex",
      content: "replacement",
      receivedAtMillis: 101_000
    ))
    XCTAssertEqual(store.pending().filter { $0.sourceMessageId == 35 && $0.contactId == "codex" }.count, 1)
    XCTAssertEqual(store.pending().last?.content, "replacement")

    let encoded = store.serializedSnapshot()
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.last)
    XCTAssertEqual(object["source_message_id"] as? Int, 35)
    XCTAssertEqual(object["received_at"] as? Int, 101_000)
    XCTAssertNil(object["received_at_millis"])
    XCTAssertNil(object["sourceMessageId"])

    let stale = AgentConnectorResponseStoreCodec.encode([
      AgentConnectorResponse(
        sourceMessageId: 900,
        contactId: "codex",
        content: "old",
        receivedAtMillis: 100_000 - AgentConnectorResponseStore.maxResponseAgeMillis - 1
      )
    ])
    XCTAssertTrue(AgentConnectorResponseStore(serialized: stale, nowMillis: { 100_000 }).pending().isEmpty)

    store.remove(AgentConnectorResponse(sourceMessageId: 35, contactId: "codex", content: ""))
    XCTAssertFalse(store.pending().contains { $0.sourceMessageId == 35 && $0.contactId == "codex" })
  }

  func testAgentPermissionGrantLedgerConsumesSingleUseGrantExactlyOnce() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { now })
    _ = try store.grant(permissionGrant(lifetime: .singleUse))

    XCTAssertTrue(try store.authorize(permissionRequest(), consume: true).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(), consume: true).granted)
    XCTAssertEqual(store.list().first?.status, .consumed)
    XCTAssertEqual(store.list(includeInactive: false).count, 0)
    now = 1_100
    XCTAssertFalse(try store.authorize(permissionRequest(), consume: false).granted)
  }

  func testAgentPermissionGrantLedgerExpiresTemporaryGrantAtBoundary() throws {
    var now: Int64 = 1_000
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { now })
    _ = try store.grant(permissionGrant(
      lifetime: .temporary,
      expiresAtMillis: 2_000,
      maxUses: 0
    ))

    XCTAssertTrue(try store.authorize(permissionRequest()).granted)
    now = 2_000
    XCTAssertFalse(try store.authorize(permissionRequest()).granted)
    XCTAssertEqual(store.list().first?.status, .expired)
  }

  func testAgentPermissionGrantLedgerEnforcesResourceAndTargetConstraints() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    _ = try store.grant(permissionGrant(
      lifetime: .permanent,
      resource: "content://documents/report.pdf",
      target: "local-runtime",
      maxUses: 0
    ))

    XCTAssertTrue(try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "local-runtime"
    )).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(
      resource: "content://documents/private.pdf",
      target: "local-runtime"
    )).granted)
    XCTAssertFalse(try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "cloud-runtime"
    )).granted)
  }

  func testAgentPermissionGrantLedgerRevocationAndSerializationSurviveRecreation() throws {
    let first = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    let issued = try first.grant(permissionGrant(lifetime: .permanent, maxUses: 0))
    let recreated = InMemoryAgentPermissionGrantStore(
      serialized: first.serializedSnapshot(),
      nowMillis: { 1_500 }
    )
    let duplicate = try recreated.grant(permissionGrant(lifetime: .permanent, maxUses: 0))

    XCTAssertEqual(duplicate.grantId, issued.grantId)
    XCTAssertTrue(try recreated.authorize(permissionRequest()).granted)
    let revocation = recreated.revokeGrant(grantId: issued.grantId, reason: " user_revoked ")
    let afterRestart = InMemoryAgentPermissionGrantStore(
      serialized: recreated.serializedSnapshot(),
      nowMillis: { 2_000 }
    )

    XCTAssertEqual(revocation.revokedGrantIds, Set([issued.grantId]))
    XCTAssertEqual(revocation.scopes, Set(["location.foreground"]))
    XCTAssertEqual(revocation.reason, "user_revoked")
    XCTAssertFalse(try afterRestart.authorize(permissionRequest()).granted)
    XCTAssertEqual(afterRestart.list().first?.revocationReason, "user_revoked")
  }

  func testAgentPermissionGrantLedgerRejectsMalformedOrContradictoryGrants() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })

    XCTAssertThrowsError(try store.grant(permissionGrant(
      lifetime: .temporary,
      expiresAtMillis: 999,
      maxUses: 0
    ))) { error in
      XCTAssertTrue(error is AgentPermissionGrantLedgerError)
    }
    XCTAssertThrowsError(try store.grant(permissionGrant(
      lifetime: .permanent,
      constraintsJson: "[]",
      maxUses: 0
    ))) { error in
      XCTAssertTrue(error is AgentPermissionGrantLedgerError)
    }
  }

  func testAgentPermissionGrantLedgerUsesMostSpecificActiveGrant() throws {
    let store = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    _ = try store.grant(permissionGrant(
      grantId: "wildcard",
      lifetime: .permanent,
      subjectId: "*",
      scope: "*",
      action: "",
      maxUses: 0,
      createdAtMillis: 900
    ))
    _ = try store.grant(permissionGrant(
      grantId: "specific",
      lifetime: .permanent,
      resource: "content://documents/report.pdf",
      target: "local-runtime",
      maxUses: 0,
      createdAtMillis: 1_000
    ))

    let decision = try store.authorize(permissionRequest(
      resource: "content://documents/report.pdf",
      target: "local-runtime"
    ))

    XCTAssertTrue(decision.granted)
    XCTAssertEqual(decision.grant?.grantId, "specific")
    XCTAssertEqual(decision.reason, "host_grant_active")
  }

  func testAgentPermissionGrantLedgerModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.signalASI.decode(
      AgentPermissionGrant.self,
      from: Data(
        #"""
        {
          "grant_id": "grant-1",
          "subject_type": "TOOL",
          "subject_id": "android.location",
          "scope": "location.foreground",
          "action": "read",
          "resource": "content://documents/report.pdf",
          "target": "local-runtime",
          "constraints_json": "{\"allow\":\"once\"}",
          "issuer": "USER",
          "evidence": "approval-dialog:turn-1",
          "lifetime": "SINGLE_USE",
          "status": "ACTIVE",
          "max_uses": 1,
          "uses": 0,
          "created_at_millis": 1000,
          "expires_at_millis": 0,
          "consumed_at_millis": 0,
          "revoked_at_millis": 0,
          "revocation_reason": ""
        }
        """#.utf8
      )
    )
    let encoded = try JSONEncoder.signalASI.encode(decoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let serialized = AgentPermissionGrantJsonCodec.encode([decoded])
    let roundTripped = AgentPermissionGrantJsonCodec.decode(serialized)
    let fallbackSubject = try JSONDecoder.signalASI.decode(
      AgentPermissionSubjectType.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(decoded.grantId, "grant-1")
    XCTAssertEqual(decoded.subjectType, .tool)
    XCTAssertEqual(decoded.lifetime, .singleUse)
    XCTAssertEqual(object["grant_id"] as? String, "grant-1")
    XCTAssertEqual(object["subject_type"] as? String, "TOOL")
    XCTAssertEqual(object["constraints_json"] as? String, #"{"allow":"once"}"#)
    XCTAssertEqual(roundTripped.first?.grantId, "grant-1")
    XCTAssertEqual(fallbackSubject, .tool)
  }

  func testAgentActionRecoveryModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.signalASI.decode(
      AgentActionResult.self,
      from: Data(#"{"action_id":"home-1","success":false,"message":"Timed out","metadata":{"code":"timeout"}}"#.utf8)
    )
    XCTAssertEqual(decoded.actionId, "home-1")
    XCTAssertFalse(decoded.success)
    XCTAssertEqual(decoded.metadata["code"], "timeout")

    let observation = agentObservation(.changedAndStable, sampleCount: 2, durationMillis: 500, changed: true, stable: true)
    let encoded = try JSONEncoder.signalASI.encode(observation)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let screen = try XCTUnwrap(object["screen"] as? [String: Any])

    XCTAssertEqual(object["decision"] as? String, "CHANGED_AND_STABLE")
    XCTAssertEqual(object["sample_count"] as? Int, 2)
    XCTAssertEqual(object["duration_millis"] as? Int, 500)
    XCTAssertEqual(object["screen_changed"] as? Bool, true)
    XCTAssertEqual(object["screen_stable"] as? Bool, true)
    XCTAssertEqual(screen["foreground_app"] as? String, "SpringBoard")
    XCTAssertEqual(screen["visible_text_count"] as? Int, 3)
  }

  func testAgentContinuousObservationControllerReturnsFailureAndNoChangeOutcomes() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let after = agentObservationScreen(pageTitle: "After", visibleTextCount: 2)
    let controller = AgentContinuousObservationController(maxSamples: 3, stableSampleCount: 2, sampleIntervalMillis: 10)

    let failed = controller.observe(
      beforeAction: before,
      actionSucceeded: false,
      changeExpected: true,
      capture: { after },
      sleep: { _ in XCTFail("Failure observation should not sleep") },
      nowMillis: { 1_000 }
    )
    let noChange = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: false,
      capture: { before },
      sleep: { _ in XCTFail("No-change observation should not sleep") },
      nowMillis: { 2_000 }
    )

    XCTAssertEqual(failed.decision, .actionFailed)
    XCTAssertEqual(failed.sampleCount, 1)
    XCTAssertEqual(failed.durationMillis, 0)
    XCTAssertTrue(failed.screenChanged)
    XCTAssertFalse(failed.screenStable)
    XCTAssertTrue(failed.evidence.contains("decision=ACTION_FAILED"))

    XCTAssertEqual(noChange.decision, .noChangeRequired)
    XCTAssertEqual(noChange.sampleCount, 1)
    XCTAssertFalse(noChange.screenChanged)
    XCTAssertTrue(noChange.screenStable)
    XCTAssertTrue(noChange.evidence.contains("stable=true"))
  }

  func testAgentContinuousObservationControllerWaitsForChangedStableScreen() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let changed = agentObservationScreen(pageTitle: "After", visibleTextCount: 2, selectedText: " Done\nnow ")
    var now: Int64 = 1_000
    var captures = 0
    var sleepIntervals: [Int64] = []
    let controller = AgentContinuousObservationController(maxSamples: 4, stableSampleCount: 2, sampleIntervalMillis: 10)

    let outcome = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: {
        captures += 1
        return changed
      },
      sleep: { millis in
        sleepIntervals.append(millis)
        now += millis
      },
      nowMillis: { now }
    )

    XCTAssertEqual(outcome.decision, .changedAndStable)
    XCTAssertEqual(outcome.sampleCount, 2)
    XCTAssertEqual(outcome.durationMillis, 10)
    XCTAssertTrue(outcome.screenChanged)
    XCTAssertTrue(outcome.screenStable)
    XCTAssertEqual(captures, 2)
    XCTAssertEqual(sleepIntervals, [10])
    XCTAssertTrue(outcome.evidence.contains("samples=2"))
  }

  func testAgentContinuousObservationControllerReportsTimeoutAndUnstableChanges() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let first = agentObservationScreen(pageTitle: "First", visibleTextCount: 2)
    let second = agentObservationScreen(pageTitle: "Second", visibleTextCount: 3)
    let controller = AgentContinuousObservationController(maxSamples: 3, stableSampleCount: 2, sampleIntervalMillis: 5)

    let timeout = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: { before },
      sleep: { _ in },
      nowMillis: { 5_000 }
    )
    var unstableIndex = 0
    let unstableScreens = [first, second, first]
    let unstable = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: {
        defer { unstableIndex += 1 }
        return unstableScreens[min(unstableIndex, unstableScreens.count - 1)]
      },
      sleep: { _ in },
      nowMillis: { 6_000 }
    )

    XCTAssertEqual(timeout.decision, .timedOut)
    XCTAssertEqual(timeout.sampleCount, 3)
    XCTAssertFalse(timeout.screenChanged)
    XCTAssertFalse(timeout.screenStable)
    XCTAssertTrue(timeout.evidence.contains("decision=TIMED_OUT"))

    XCTAssertEqual(unstable.decision, .changedButUnstable)
    XCTAssertEqual(unstable.sampleCount, 3)
    XCTAssertTrue(unstable.screenChanged)
    XCTAssertFalse(unstable.screenStable)
    XCTAssertTrue(unstable.evidence.contains("decision=CHANGED_BUT_UNSTABLE"))
  }

  func testAgentObservationContextStoreObservesDedupesAndFiltersConversationScope() throws {
    var now: Int64 = 1_000
    var nextId = 0
    let store = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { nextId += 1 }
        return "observation-\(nextId)"
      }
    )

    let first = try XCTUnwrap(store.observe(
      targetId: " codex ",
      text: " Needs review ",
      conversationId: " conversation-a ",
      taskId: " task-a "
    ))
    now = 2_000
    let duplicate = try XCTUnwrap(store.observe(
      targetId: "codex",
      text: "Needs review",
      conversationId: "conversation-a",
      taskId: "task-a"
    ))
    _ = store.observe(targetId: "codex", text: "Global hint")
    _ = store.observe(targetId: "codex", text: "Other conversation", conversationId: "conversation-b")

    let scoped = store.peek(targetId: " codex ", conversationId: "conversation-a")
    let unscoped = store.peek(targetId: "codex")

    XCTAssertEqual(first.id, "observation-0")
    XCTAssertEqual(duplicate.id, "observation-1")
    XCTAssertEqual(duplicate.targetId, "codex")
    XCTAssertEqual(duplicate.text, "Needs review")
    XCTAssertEqual(duplicate.conversationId, "conversation-a")
    XCTAssertEqual(duplicate.taskId, "task-a")
    XCTAssertEqual(duplicate.createdAtMillis, 2_000)
    XCTAssertEqual(duplicate.expiresAtMillis, 2_000 + AgentObservedContext.defaultTTLMillis)
    XCTAssertEqual(scoped.map(\.id), ["observation-1", "observation-2"])
    XCTAssertEqual(unscoped.map(\.id), ["observation-1", "observation-2", "observation-3"])
    XCTAssertNil(store.observe(targetId: " ", text: "ignored"))
    XCTAssertNil(store.observe(targetId: "codex", text: " "))
  }

  func testAgentObservationContextStoreExpiresAcknowledgesClearsAndBoundsEntries() throws {
    var now: Int64 = 10_000
    let valid = AgentObservedContext(
      id: "valid",
      targetId: "codex",
      text: "Fresh context",
      conversationId: "conversation",
      taskId: "task",
      createdAtMillis: 9_000,
      expiresAtMillis: 20_000
    )
    let expired = AgentObservedContext(
      id: "expired",
      targetId: "codex",
      text: "Old context",
      createdAtMillis: 1_000,
      expiresAtMillis: 9_999
    )
    let invalid = AgentObservedContext(
      id: "invalid",
      targetId: "",
      text: "Missing target",
      createdAtMillis: 9_000,
      expiresAtMillis: 20_000
    )
    let store = InMemoryAgentObservationContextStore(
      serialized: AgentObservationContextJsonCodec.encode([expired, invalid, valid]),
      clock: { now },
      idFactory: { "new" }
    )

    XCTAssertEqual(store.peek(targetId: "codex").map(\.id), ["valid"])
    XCTAssertEqual(store.acknowledge(entryIds: ["missing"]), 0)
    XCTAssertEqual(store.acknowledge(entryIds: ["valid"]), 1)
    XCTAssertTrue(store.peek(targetId: "codex").isEmpty)

    _ = store.observe(targetId: "codex", text: "A")
    _ = store.observe(targetId: "other", text: "B")
    XCTAssertEqual(store.clearTarget(" codex "), 1)
    XCTAssertEqual(store.peek(targetId: "other").map(\.text), ["B"])
    store.clear()
    XCTAssertEqual(AgentObservationContextJsonCodec.decode(store.serializedSnapshot(), nowMillis: now), [])

    now = 1_000
    var boundedSeed = 0
    let bounded = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { boundedSeed += 1 }
        return "bounded-\(boundedSeed)"
      }
    )
    for index in 0..<18 {
      now = Int64(1_000 + index)
      _ = bounded.observe(targetId: "codex", text: "target-entry-\(index)")
    }
    XCTAssertEqual(bounded.peek(targetId: "codex").count, 16)
    XCTAssertEqual(bounded.peek(targetId: "codex").first?.text, "target-entry-2")

    var totalSeed = 0
    let total = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { totalSeed += 1 }
        return "total-\(totalSeed)"
      }
    )
    for index in 0..<130 {
      now = Int64(2_000 + index)
      _ = total.observe(targetId: "target-\(index)", text: "total-entry-\(index)")
    }
    let decoded = AgentObservationContextJsonCodec.decode(total.serializedSnapshot(), nowMillis: now)
    XCTAssertEqual(decoded.count, 128)
    XCTAssertFalse(decoded.contains { $0.targetId == "target-0" })
    XCTAssertEqual(decoded.first?.targetId, "target-2")
    XCTAssertEqual(decoded.last?.targetId, "target-129")
  }

  func testAgentObservationContextCodecUsesAndroidWireNamesAndBoundsPayloads() throws {
    let longText = String(repeating: "x", count: 8_050)
    let context = AgentObservedContext(
      id: "context",
      targetId: String(repeating: "t", count: 200),
      text: longText,
      conversationId: String(repeating: "c", count: 200),
      taskId: "task",
      createdAtMillis: 1_000,
      expiresAtMillis: 2_000
    )
    let encoded = AgentObservationContextJsonCodec.encode([context])
    let object = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])?.first
    )
    let decoded = AgentObservationContextJsonCodec.decode(
      """
      [
        "ignored",
        {"id":"blank","target_id":"","text":"ignored","created_at_millis":1,"expires_at_millis":9999},
        {"id":"expired","target_id":"codex","text":"old","created_at_millis":1,"expires_at_millis":999},
        \(encoded.dropFirst().dropLast())
      ]
      """,
      nowMillis: 1_500
    )

    XCTAssertEqual(object["id"] as? String, "context")
    XCTAssertEqual((object["target_id"] as? String)?.count, 160)
    XCTAssertEqual((object["text"] as? String)?.count, 8_000)
    XCTAssertEqual((object["conversation_id"] as? String)?.count, 160)
    XCTAssertEqual(object["task_id"] as? String, "task")
    XCTAssertEqual((object["created_at_millis"] as? NSNumber)?.int64Value, Int64(1_000))
    XCTAssertEqual((object["expires_at_millis"] as? NSNumber)?.int64Value, Int64(2_000))
    XCTAssertEqual(decoded, [context])
    XCTAssertTrue(context.isExpired(nowMillis: 2_000))
    XCTAssertFalse(context.isExpired(nowMillis: 1_999))
    XCTAssertEqual(AgentObservationContextJsonCodec.decode("not-json", nowMillis: 1_500), [])
  }

  func testPhoneExecutionAuthorityAnnotatesConcurrentReadsWithoutSerialization() {
    let action = phoneAuthorityAction(
      id: "read-1",
      kind: .readScreen,
      taskId: "task-read"
    )
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "screen read",
        metadata: ["delegate": "called"]
      )
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["delegate"], "called")
    XCTAssertEqual(result.metadata["execution_location"], "phone")
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
    XCTAssertEqual(result.metadata["task_id"], "task-read")
    XCTAssertEqual(result.metadata["serialized_side_effect"], "false")
  }

  func testPhoneExecutionAuthoritySerializesSideEffectsAndReportsActiveTask() {
    let taskId = "task-side-effect-\(UUID().uuidString)"
    let action = phoneAuthorityAction(
      id: "open-1",
      kind: .openApp,
      taskId: taskId
    )
    var observedSnapshot = PhoneExecutionAuthoritySnapshot()
    let delegate = TestAgentActionExecutor { action, _ in
      observedSnapshot = PhoneExecutionAuthority.snapshot()
      return AgentActionResult(actionId: action.id, success: true, message: "opened")
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(observedSnapshot.activeSideEffectTaskId, taskId)
    XCTAssertEqual(result.metadata["serialized_side_effect"], "true")
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
    XCTAssertEqual(PhoneExecutionAuthority.snapshot().activeSideEffectTaskId, "")
  }

  func testPhoneExecutionAuthorityCancellationReturnsAndroidMetadataWithoutDelegate() {
    let taskId = "task-cancel-\(UUID().uuidString)"
    PhoneExecutionAuthority.requestCancellation(taskId: taskId)
    defer { PhoneExecutionAuthority.clearCancellation(taskId: taskId) }
    let action = phoneAuthorityAction(
      id: "tap-1",
      kind: .tap,
      taskId: taskId
    )
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "unexpected")
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 0)
    XCTAssertFalse(result.success)
    XCTAssertEqual(result.message, "Phone tool execution was cancelled")
    XCTAssertEqual(result.metadata["execution_location"], "phone")
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
    XCTAssertEqual(result.metadata["task_id"], taskId)
    XCTAssertEqual(result.metadata["cancelled"], "true")
    XCTAssertTrue(PhoneExecutionAuthority.isCancelled(taskId: taskId))
    XCTAssertGreaterThanOrEqual(PhoneExecutionAuthority.snapshot().cancelledTaskCount, 1)
  }

  func testPhoneExecutionAuthoritySnapshotUsesAndroidWireNames() throws {
    let snapshot = PhoneExecutionAuthoritySnapshot(
      activeSideEffectTaskId: "task-1",
      queuedSideEffectTasks: 2,
      cancelledTaskCount: 3
    )
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(snapshot), as: UTF8.self)
    let decoded = try JSONDecoder.signalASI.decode(
      PhoneExecutionAuthoritySnapshot.self,
      from: Data(
        #"{"active_side_effect_task_id":"task-2","queued_side_effect_tasks":4,"cancelled_task_count":5}"#.utf8
      )
    )

    XCTAssertTrue(encoded.contains(#""active_side_effect_task_id":"task-1""#))
    XCTAssertTrue(encoded.contains(#""queued_side_effect_tasks":2"#))
    XCTAssertTrue(encoded.contains(#""cancelled_task_count":3"#))
    XCTAssertEqual(decoded.activeSideEffectTaskId, "task-2")
    XCTAssertEqual(decoded.queuedSideEffectTasks, 4)
    XCTAssertEqual(decoded.cancelledTaskCount, 5)
  }

  func testAgentActionRecoveryRetriesLowRiskNavigationTimeoutOnce() {
    var retryCount = 0
    let failed = AgentActionResult(actionId: "home-1", success: false, message: "Timed out")
    let outcome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-1", kind: .home, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(
        result: AgentActionResult(actionId: "home-1", success: true, message: "Home opened"),
        observation: agentObservation(.changedAndStable, sampleCount: 2, durationMillis: 250, changed: true, stable: true)
      )
    }

    XCTAssertEqual(retryCount, 1)
    XCTAssertEqual(outcome.decision, .retrySucceeded)
    XCTAssertEqual(outcome.attemptCount, 1)
    XCTAssertEqual(outcome.result?.success, true)
    XCTAssertEqual(outcome.observation.decision, .changedAndStable)
  }

  func testAgentActionRecoveryRequiresManualForUnsafeOrNonTimeoutFailures() {
    let failed = AgentActionResult(actionId: "tap-1", success: false, message: "Timed out")
    var retryCount = 0

    let unsafeTap = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "tap-1", kind: .tap, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let highRiskHome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-1", kind: .home, risk: .high),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let nonTimeoutHome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-2", kind: .home, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.actionFailed, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }

    XCTAssertEqual(unsafeTap.decision, .manualRequired)
    XCTAssertEqual(highRiskHome.decision, .manualRequired)
    XCTAssertEqual(nonTimeoutHome.decision, .manualRequired)
    XCTAssertEqual(retryCount, 0)
  }

  func testAgentActionRecoverySkipsRetryWhenFailureIsAbsent() {
    var retryCount = 0
    let successful = AgentActionResult(actionId: "open-1", success: true, message: "Opened")
    let controller = AgentActionRecoveryController()

    let nilResult = controller.recover(
      action: agentRecoveryAction(id: "open-1", kind: .openApp, risk: .low),
      failedResult: nil,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let successResult = controller.recover(
      action: agentRecoveryAction(id: "open-1", kind: .openApp, risk: .low),
      failedResult: successful,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }

    XCTAssertEqual(nilResult.decision, .notNeeded)
    XCTAssertEqual(successResult.decision, .notNeeded)
    XCTAssertEqual(retryCount, 0)
  }

  func testAgentExecutionPresentationPolicyMatchesAndroidLocalAndRemoteLocations() {
    let desktop = AgentExecutionPresentationPolicy.local(
      routeKind: .desktopAgent,
      targetTitle: "Codex \u{00b7} WORKSTATION",
      selectedAgentOrModel: "",
      phase: .executing,
      currentStep: "Reading files",
      startedAtMillis: 1_000
    )

    XCTAssertEqual(desktop.executorLabel, "Codex")
    XCTAssertEqual(desktop.locationLabelHint, "WORKSTATION")
    XCTAssertEqual(desktop.locationKind, .desktop)
    XCTAssertTrue(desktop.cancellable)

    let phone = AgentExecutionPresentationPolicy.local(
      routeKind: .localSystem,
      targetTitle: "",
      selectedAgentOrModel: "",
      phase: .executing,
      currentStep: "Reading battery",
      startedAtMillis: 1_000
    )
    let cloud = AgentExecutionPresentationPolicy.local(
      routeKind: .cloudModel,
      targetTitle: "DeepSeek",
      selectedAgentOrModel: "",
      phase: .waitingResponse,
      currentStep: "Waiting for model",
      startedAtMillis: 1_000
    )

    XCTAssertEqual(phone.locationKind, .phone)
    XCTAssertEqual(phone.executorLabel, "SignalASI")
    XCTAssertEqual(cloud.locationKind, .cloud)
    XCTAssertEqual(cloud.executorLabel, "DeepSeek")

    let completed = AgentExecutionPresentationPolicy.remote(
      executorId: "codex",
      executorLabel: "Codex",
      locationKind: "desktop",
      locationName: "WORKSTATION",
      status: "completed",
      currentStep: "",
      startedAtMillis: 1_000,
      completedAtMillis: 2_000,
      advertisedCancellable: true
    )

    XCTAssertFalse(completed.cancellable)
    XCTAssertEqual(completed.phase, .completed)
    XCTAssertEqual(completed.locationKind, .desktop)
  }

  func testAgentExecutionPresentationPolicyDecodesAndroidWireNames() throws {
    let phase = try JSONDecoder.signalASI.decode(AgentPhase.self, from: Data(#""WAITING_RESPONSE""#.utf8))
    let route = try JSONDecoder.signalASI.decode(AgentRouteKind.self, from: Data(#""DESKTOP_AGENT""#.utf8))
    let fallbackPhase = try JSONDecoder.signalASI.decode(AgentPhase.self, from: Data(#""not-supported""#.utf8))
    let fallbackRoute = try JSONDecoder.signalASI.decode(AgentRouteKind.self, from: Data(#""not-supported""#.utf8))

    XCTAssertEqual(phase, .waitingResponse)
    XCTAssertEqual(route, .desktopAgent)
    XCTAssertEqual(fallbackPhase, .executing)
    XCTAssertEqual(fallbackRoute, .unknown)
    XCTAssertFalse(AgentExecutionPresentationPolicy.isCancellable(.blocked))
    XCTAssertEqual(AgentExecutionPresentationPolicy.phaseForRemoteStatus("timed_out"), .failed)
    XCTAssertEqual(AgentExecutionPresentationPolicy.phaseForRemoteStatus("waiting_approval"), .paused)
  }

  func testAgentPlanLifecyclePolicyRestoresConnectorResultAndCompletesSession() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "The worksheet has been corrected."
    )
    let draft = lifecycleAction(
      id: "draft-plan",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    let session = lifecycleSession(
      phase: .planning,
      plan: lifecyclePlan(connector, draft),
      result: AgentActionResult(actionId: draft.id, success: true, message: "")
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(session)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.session.currentPlan?.actions, [connector])
    XCTAssertEqual(normalized.session.phase, .completed)
    XCTAssertEqual(normalized.session.lastActionResult?.actionId, connector.id)
    XCTAssertEqual(normalized.session.lastActionResult?.message, connector.result)
  }

  func testAgentPlanLifecyclePolicyRemovesPendingTrailingDraftBeforeItRuns() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "Done"
    )
    let draft = lifecycleAction(
      id: "draft-plan",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .pendingConfirmation
    )
    let plan = lifecyclePlan(connector, draft)

    let normalized = AgentPlanLifecyclePolicy.normalize(plan)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.plan.actions, [connector])
  }

  func testAgentPlanLifecyclePolicyRetiresStandaloneLegacyRuntimeDraft() {
    let standalone = lifecyclePlan(
      lifecycleAction(
        id: "draft-plan",
        kind: .draftPlan,
        target: "local-agent-runtime",
        status: .completed
      )
    )
    let taskComplete = lifecyclePlan(
      lifecycleAction(id: "connector", kind: .callConnector, target: "Codex", status: .completed),
      lifecycleAction(id: "done", kind: .draftPlan, target: "task-complete", status: .completed)
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(standalone)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.plan.actions.first?.target, "task-complete")
    XCTAssertEqual(normalized.plan.actions.first?.status, .failed)
    XCTAssertTrue(normalized.plan.actions.first?.result.contains("Send it again") == true)
    XCTAssertTrue(normalized.plan.validation.valid)
    XCTAssertFalse(AgentPlanLifecyclePolicy.normalize(taskComplete).changed)
  }

  func testAgentPlanLifecyclePolicyRecoversCompletedConnectorFromHistory() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "Recovered Codex reply"
    )
    let draft = lifecycleAction(
      id: "replanned-draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    var sourcePlan = lifecyclePlan(draft)
    sourcePlan.actionHistory = [connector]
    let sourceSession = lifecycleSession(
      phase: .planning,
      plan: sourcePlan,
      result: AgentActionResult(actionId: draft.id, success: true, message: "")
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(sourceSession)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.session.currentPlan?.actions, [connector])
    XCTAssertTrue(normalized.session.currentPlan?.actionHistory.isEmpty == true)
    XCTAssertEqual(normalized.session.phase, .completed)
    XCTAssertEqual(normalized.session.lastActionResult?.message, "Recovered Codex reply")
  }

  func testAgentPlanLifecyclePolicyRecoversReceivedConnectorWithoutLocalRuntimeDraft() {
    let draft = lifecycleAction(
      id: "replanned-draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    var sourcePlan = lifecyclePlan(draft)
    sourcePlan.route = AgentRoute(kind: .desktopAgent, targetTitle: "Codex")
    let sourceSession = lifecycleSession(
      phase: .planning,
      plan: sourcePlan,
      result: AgentActionResult(actionId: draft.id, success: true, message: "Created a local task plan"),
      auditTrail: [
        AgentAuditEntry(
          event: .connectorResponseReceived,
          detail: "source_message_id=1",
          timestampMillis: 2
        )
      ]
    )
    let durableTask = agentTaskRecord(
      taskId: sourcePlan.planId,
      sessionId: "session",
      goal: sourcePlan.goal,
      phase: .completed,
      routeKind: .desktopAgent,
      targetTitle: "Codex",
      risk: .low,
      result: "Durable Codex result"
    )

    let recovered = AgentPlanLifecyclePolicy.recoverCompletedConnector(
      session: sourceSession,
      persistedTask: durableTask,
      missingResult: "No final result"
    )

    XCTAssertEqual(recovered.phase, .completed)
    XCTAssertEqual(recovered.currentPlan?.actions.first?.kind, .callConnector)
    XCTAssertEqual(recovered.currentPlan?.actions.first?.target, "Codex")
    XCTAssertEqual(recovered.lastActionResult?.message, "Durable Codex result")
    XCTAssertFalse(recovered.currentPlan?.actions.contains { $0.target == "local-agent-runtime" } == true)
  }

  func testAgentPlanLifecyclePolicyDoesNotRewriteWithoutConnectorReceipt() {
    let draft = lifecycleAction(
      id: "draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .pendingConfirmation
    )
    let source = lifecycleSession(phase: .planning, plan: lifecyclePlan(draft), result: nil)

    let recovered = AgentPlanLifecyclePolicy.recoverCompletedConnector(
      session: source,
      persistedTask: nil,
      missingResult: "No final result"
    )

    XCTAssertEqual(source, recovered)
  }

  func testAgentPlanLifecycleModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentSessionSnapshot.self,
      from: Data(
        #"""
        {
          "session_id": "session",
          "phase": "PLANNING",
          "current_goal": "Correct the worksheet",
          "current_screen": {
            "foreground_app": "SignalASI",
            "page_title": "Agent"
          },
          "current_plan": {
            "goal": "Correct the worksheet",
            "screen": {
              "foreground_app": "SignalASI",
              "page_title": "Agent"
            },
            "steps": [
              {"order": 1, "kind": "BUILD_PLAN", "status": "CURRENT"}
            ],
            "actions": [
              {
                "id": "connector",
                "kind": "CALL_CONNECTOR",
                "target": "Codex",
                "risk": "LOW",
                "status": "COMPLETED",
                "description": "Run Codex",
                "result": "Done"
              }
            ],
            "execution_mode": "AUTO_COMPLETE",
            "plan_id": "plan",
            "route": {
              "kind": "DESKTOP_AGENT",
              "target_title": "Codex"
            },
            "verification_results": [
              {"action_id": "connector", "success": true, "evidence": "ok", "timestamp_millis": 12}
            ],
            "checkpoints": [
              {"action_id": "connector", "summary": "checkpoint", "timestamp_millis": 13}
            ]
          },
          "audit_trail": [
            {"event": "CONNECTOR_RESPONSE_RECEIVED", "detail": "ok", "timestamp_millis": 14}
          ],
          "last_action_result": {
            "action_id": "connector",
            "success": true,
            "message": "Done"
          },
          "task_execution_mode": "AUTO_COMPLETE",
          "updated_at_millis": 15
        }
        """#.utf8
      )
    )
    let fallbackAudit = try JSONDecoder().decode(
      AgentAuditEvent.self,
      from: Data(#""FUTURE""#.utf8)
    )
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

    XCTAssertEqual(decoded.phase, .planning)
    XCTAssertEqual(decoded.currentPlan?.route.kind, .desktopAgent)
    XCTAssertEqual(decoded.currentPlan?.steps.first?.kind, .buildPlan)
    XCTAssertEqual(decoded.auditTrail.first?.event, .connectorResponseReceived)
    XCTAssertEqual(fallbackAudit, .invocationAudit)
    XCTAssertTrue(encoded.contains(#""current_plan":"#) || encoded.contains(#""current_plan":{"#))
    XCTAssertTrue(encoded.contains(#""task_execution_mode":"AUTO_COMPLETE""#))
    XCTAssertTrue(encoded.contains(#""timestamp_millis":14"#))
  }

  func testAgentExecutionContinuityCreatesRollbackCheckpointAndAndroidDigest() throws {
    let screen = AgentScreenContext(
      foregroundApp: "SignalASI",
      activityName: "MainActivity",
      pageTitle: "Agent",
      visibleTextCount: 2,
      clickableNodeCount: 4,
      inputFieldCount: 1,
      visibleTexts: ["Inbox", "Compose"]
    )
    let changedScreen = AgentScreenContext(
      foregroundApp: "SignalASI",
      activityName: "MainActivity",
      pageTitle: "Agent",
      visibleTextCount: 2,
      clickableNodeCount: 4,
      inputFieldCount: 1,
      visibleTexts: ["Inbox", "Changed"]
    )
    let action = AgentAction(
      id: "open",
      kind: .openURL,
      target: "https://example.com",
      risk: .medium,
      status: .running,
      description: "Open docs"
    )

    let checkpoint = AgentExecutionContinuity.checkpointBefore(
      action: action,
      screen: screen,
      planRevision: 7,
      id: "checkpoint-1",
      nowMillis: 1_234
    )

    XCTAssertEqual(AgentExecutionContinuity.screenDigest(screen), "806208482")
    XCTAssertEqual(AgentExecutionContinuity.screenDigest(changedScreen), "-1027068")
    XCTAssertEqual(checkpoint.id, "checkpoint-1")
    XCTAssertEqual(checkpoint.actionId, "open")
    XCTAssertEqual(checkpoint.planRevision, 7)
    XCTAssertEqual(checkpoint.foregroundApp, "SignalASI")
    XCTAssertEqual(checkpoint.activityName, "MainActivity")
    XCTAssertEqual(checkpoint.pageTitle, "Agent")
    XCTAssertEqual(checkpoint.screenDigest, "806208482")
    XCTAssertEqual(checkpoint.status, .active)
    XCTAssertEqual(checkpoint.createdAtMillis, 1_234)
    XCTAssertEqual(checkpoint.rollbackAction?.id, "rollback-open")
    XCTAssertEqual(checkpoint.rollbackAction?.kind, .back)
    XCTAssertEqual(checkpoint.rollbackAction?.status, .pendingConfirmation)
    XCTAssertTrue(checkpoint.rollbackAction?.requiresConfirmation == true)

    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(checkpoint)) as? [String: Any]
    )
    XCTAssertEqual(object["plan_revision"] as? Int, 7)
    XCTAssertEqual(object["foreground_app"] as? String, "SignalASI")
    XCTAssertEqual(object["screen_digest"] as? String, "806208482")
    XCTAssertEqual((object["created_at_millis"] as? NSNumber)?.int64Value, Int64(1_234))
    XCTAssertNotNil(object["rollback_action"])
  }

  func testAgentExecutionContinuityReversesSwipeAndRestoresInterruptedActions() {
    let running = AgentAction(
      id: "swipe",
      kind: .swipe,
      target: "screen",
      risk: .low,
      status: .running,
      description: "Swipe up",
      parameters: [
        "from_x": "10",
        "from_y": "90",
        "to_x": "10",
        "to_y": "10"
      ]
    )
    let pending = AgentAction(
      id: "pending",
      kind: .tap,
      target: "button",
      risk: .low,
      status: .pendingConfirmation,
      description: "Tap"
    )
    let plan = lifecyclePlan(running, pending)
    let checkpoint = AgentExecutionContinuity.checkpointBefore(
      action: running,
      screen: plan.screen,
      planRevision: plan.revision,
      id: "checkpoint-swipe",
      nowMillis: 2_000
    )
    let rollback = checkpoint.rollbackAction
    let recovered = plan.addCheckpoint(checkpoint).recoverInterruptedExecution()

    XCTAssertEqual(rollback?.kind, .swipe)
    XCTAssertEqual(rollback?.description, "Reverse the previous swipe")
    XCTAssertEqual(rollback?.parameters["from_x"], "10")
    XCTAssertEqual(rollback?.parameters["from_y"], "10")
    XCTAssertEqual(rollback?.parameters["to_x"], "10")
    XCTAssertEqual(rollback?.parameters["to_y"], "90")
    XCTAssertEqual(recovered.checkpoints.count, 1)
    XCTAssertEqual(recovered.checkpoints.first?.id, "checkpoint-swipe")
    XCTAssertEqual(recovered.actions[0].status, .pendingConfirmation)
    XCTAssertEqual(recovered.actions[0].result, "Execution was interrupted before verification")
    XCTAssertEqual(recovered.actions[0].evidence, "interrupted")
    XCTAssertEqual(recovered.actions[1].status, .pendingConfirmation)
    let marked = recovered.markCheckpoint("checkpoint-swipe", status: .restored)
    XCTAssertEqual(marked.checkpoints.first?.status, .restored)
  }

  func testAgentExecutionContinuityHistoryAndCheckpointCodecStayBackwardCompatible() throws {
    let history = (0..<45).map { index in
      AgentAction(
        id: "history-\(index)",
        kind: .callConnector,
        target: "Codex",
        risk: .low,
        status: .completed,
        description: "Historical action"
      )
    }
    let blocked = AgentAction(
      id: "blocked",
      kind: .callNativeTool,
      target: "tool",
      risk: .medium,
      status: .blocked,
      description: "Blocked"
    )
    let running = AgentAction(
      id: "running",
      kind: .callNativeTool,
      target: "tool",
      risk: .medium,
      status: .running,
      description: "Running"
    )
    var plan = lifecyclePlan(blocked, running)
    plan.actionHistory = history

    let retained = plan.historyForReplan()
    let legacy = try JSONDecoder().decode(
      AgentExecutionCheckpoint.self,
      from: Data(#"{"action_id":"connector","summary":"checkpoint","timestamp_millis":13}"#.utf8)
    )
    let fallback = try JSONDecoder().decode(
      AgentCheckpointStatus.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(retained.count, 40)
    XCTAssertEqual(retained.first?.id, "history-6")
    XCTAssertEqual(retained.last?.id, "blocked")
    XCTAssertFalse(retained.contains { $0.id == "running" })
    XCTAssertEqual(legacy.id, "checkpoint-connector-13")
    XCTAssertEqual(legacy.actionId, "connector")
    XCTAssertEqual(legacy.summary, "checkpoint")
    XCTAssertEqual(legacy.createdAtMillis, 13)
    XCTAssertEqual(legacy.timestampMillis, 13)
    XCTAssertEqual(legacy.status, .active)
    XCTAssertEqual(fallback, .active)
  }

  func testAgentExecutionLoopTimelinePolicyProjectsCanonicalPhases() {
    let plan = AgentExecutionLoopTimelinePolicy.project(loopEvent(.plan))
    let act = AgentExecutionLoopTimelinePolicy.project(
      loopEvent(
        .act,
        actionId: "tool-1",
        toolCall: true,
        usage: AgentExecutionLoopUsage(iterations: 1, actions: 1, toolCalls: 1)
      )
    )
    let observe = AgentExecutionLoopTimelinePolicy.project(loopEvent(.observe, actionId: "tool-1"))
    let replan = AgentExecutionLoopTimelinePolicy.project(loopEvent(.replan, actionId: "tool-1"))

    XCTAssertEqual(plan.controlEventType, .planning)
    XCTAssertEqual(act.controlEventType, .toolStarted)
    XCTAssertEqual(act.toolCallId, "tool-1")
    XCTAssertEqual(observe.controlEventType, .toolProgress)
    XCTAssertEqual(replan.controlEventType, .retrying)
    XCTAssertEqual(plan.payload["timeline_kind"]?.stringValue, "plan")
    XCTAssertEqual(act.payload["timeline_kind"]?.stringValue, "tool")
    XCTAssertEqual(replan.payload["timeline_kind"]?.stringValue, "retry")
  }

  func testAgentExecutionLoopTimelinePolicyProjectsRecoveryCompletionAndRevision() {
    let recovered = AgentExecutionLoopTimelinePolicy.project(
      loopEvent(.act, previousPhase: .failed, actionId: "retry", retry: true)
    )
    let completed = AgentExecutionLoopTimelinePolicy.project(loopEvent(.completed))
    let event = loopEvent(
      .act,
      actionId: "action",
      toolCall: true,
      revision: 7,
      usage: AgentExecutionLoopUsage(iterations: 1, actions: 1, toolCalls: 1)
    )
    let projection = AgentExecutionLoopTimelinePolicy.project(event)
    let runEvent = runControlEvent(type: projection.controlEventType, payload: projection.payload)

    XCTAssertEqual(recovered.controlEventType, .runRecovered)
    XCTAssertEqual(recovered.payload["loop_retry"]?.boolValue, true)
    XCTAssertEqual(completed.controlEventType, .runCompleted)
    XCTAssertNil(completed.label)
    XCTAssertEqual(projection.payload["loop_revision"]?.intValue, 7)
    XCTAssertEqual(projection.payload["loop_actions"]?.intValue, 1)
    XCTAssertEqual(projection.payload["loop_tool_calls"]?.intValue, 1)
    XCTAssertEqual(projection.payload["loop_action_id"]?.stringValue, "action")
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.isSameRevision(event: runEvent, revision: 7))
    XCTAssertFalse(AgentExecutionLoopTimelinePolicy.isSameRevision(event: runEvent, revision: 8))
  }

  func testAgentExecutionLoopTimelinePolicyKeysActionsAndPlaceholderSuppression() {
    let event = loopEvent(.plan, revision: 3)
    let key = AgentExecutionLoopTimelinePolicy.transcriptDedupeKey(turnId: "turn", event: event)
    let genericAct = transcriptEntry("generic-act", text: "Executing task step", dedupeKey: "agent-loop:turn:ACT:2")
    let genericObserve = transcriptEntry("generic-observe", text: "Inspecting result", dedupeKey: "agent-loop:turn:OBSERVE:3")
    let detailedStart = transcriptEntry("tool-start", text: "Phone Linux: python app.py", dedupeKey: "audit:4:TOOL_STARTED:1")
    let detailedComplete = transcriptEntry("tool-complete", text: "Phone Linux completed", dedupeKey: "audit:5:TOOL_COMPLETED:1")

    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey(key), .plan)
    XCTAssertNil(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey("audit:1"))
    XCTAssertNil(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey("agent-loop:turn:FUTURE:1"))
    XCTAssertEqual(
      AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders([
        genericAct,
        genericObserve,
        detailedStart,
        detailedComplete
      ]),
      [detailedStart, detailedComplete]
    )
    XCTAssertEqual(
      AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders([genericAct, genericObserve]),
      [genericAct, genericObserve]
    )

    for phase in [AgentPhase.planning, .waitingConfirmation, .executing, .verifying] {
      XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(phase), [.pause, .cancel])
    }
    for phase in [AgentPhase.observing, .waitingResponse] {
      XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(phase), [.cancel])
    }
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.paused), [.resume, .cancel])
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.blocked), [.replan, .cancel])
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.failed), [.retry, .replan])
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.actionsForPhase(.completed).isEmpty)
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.actionsForPhase(.cancelled).isEmpty)
  }

  func testAgentRunTimelineContractCoverageMatchesAndroidKinds() {
    let events = [
      runControlEvent(type: .planning),
      runControlEvent(type: .toolStarted, toolCallId: "tool-1"),
      runControlEvent(type: .toolCompleted, toolCallId: "tool-1"),
      runControlEvent(type: .retrying),
      runControlEvent(type: .runCompleted)
    ]
    let coverage = AgentRunTimelineContract.coverage(events)
    let failed = AgentRunTimelineContract.coverage([runControlEvent(type: .runFailed)])
    let declared = runControlEvent(type: .stepStarted, payload: ["timeline_kind": .string("verify")])

    XCTAssertTrue(coverage.hasPlan)
    XCTAssertEqual(coverage.toolEventCount, 2)
    XCTAssertEqual(coverage.retryEventCount, 1)
    XCTAssertTrue(coverage.hasResult)
    XCTAssertTrue(coverage.complete)
    XCTAssertTrue(failed.hasFailure)
    XCTAssertTrue(failed.terminal)
    XCTAssertFalse(failed.complete)
    XCTAssertEqual(AgentRunTimelineContract.kind(declared), .verify)
  }

  func testAgentExecutionLoopTimelineModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentRunControlEvent.self,
      from: Data(
        #"""
        {
          "event_id": "event",
          "conversation_id": "conversation",
          "message_id": "turn",
          "task_id": "task",
          "run_id": "run",
          "step_id": "step",
          "tool_call_id": "tool",
          "agent_id": "signalasi-mobile",
          "device_id": "phone",
          "type": "TOOL_STARTED",
          "sequence": 4,
          "timestamp_millis": 1234,
          "payload": {
            "timeline_kind": "tool",
            "loop_revision": 7,
            "loop_retry": true
          }
        }
        """#.utf8
      )
    )
    let fallbackPhase = try JSONDecoder().decode(
      AgentExecutionLoopPhase.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackType = try JSONDecoder().decode(
      AgentRunControlEventType.self,
      from: Data(#""future""#.utf8)
    )
    let encodedEvent = String(decoding: try JSONEncoder().encode(loopEvent(.act, previousPhase: .failed)), as: UTF8.self)
    let encodedProjection = String(
      decoding: try JSONEncoder().encode(AgentExecutionLoopTimelinePolicy.project(loopEvent(.act, actionId: "tool"))),
      as: UTF8.self
    )

    XCTAssertEqual(decoded.type, .toolStarted)
    XCTAssertEqual(decoded.toolCallId, "tool")
    XCTAssertEqual(decoded.payload["loop_revision"]?.intValue, 7)
    XCTAssertEqual(decoded.payload["loop_retry"]?.boolValue, true)
    XCTAssertEqual(fallbackPhase, .plan)
    XCTAssertEqual(fallbackType, .runFailed)
    XCTAssertTrue(AgentExecutionLoopPhase.completed.isTerminal)
    XCTAssertTrue(AgentExecutionLoopUsage(activeDurationMillis: 20, activeSinceMillis: 100).elapsedActiveMillis(nowMillis: 150, phase: .act) == 70)
    XCTAssertTrue(encodedEvent.contains(#""previous_phase":"FAILED""#))
    XCTAssertTrue(encodedProjection.contains(#""control_event_type":"STEP_STARTED""#))
    XCTAssertTrue(encodedProjection.contains(#""timeline_contract":"signalasi.run-timeline/1.0""#))
  }

  func testAgentRunEventStoreReducerPreservesTerminalStateUntilExplicitRecovery() {
    let completed = AgentRunEventStore.reduce(current: .running, event: .runCompleted)
    let ignoredLateProgress = AgentRunEventStore.reduce(current: completed, event: .toolProgress)
    let recovered = AgentRunEventStore.reduce(current: completed, event: .runRecovered)
    let waiting = AgentRunEventStore.reduce(current: .running, event: .toolPermissionRequired)
    let paused = AgentRunEventStore.reduce(current: .running, event: .permissionRevoked)

    XCTAssertEqual(completed, .completed)
    XCTAssertEqual(ignoredLateProgress, .completed)
    XCTAssertEqual(recovered, .running)
    XCTAssertEqual(waiting, .waitingForUser)
    XCTAssertEqual(paused, .paused)
  }

  func testAgentRunRecoveryPolicyMatchesAndroidDurableDesktopRules() {
    let snapshot = runControlSnapshot(state: .waitingForDevice)
    let recorded = AgentRecordedRun(
      runId: "run",
      conversationId: "conversation",
      taskThreadId: "task",
      originalRequest: "Continue the task"
    )
    let paused = runControlSnapshot(state: .paused)
    let completed = runControlSnapshot(state: .completed)

    let durable = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: recorded,
      registration: runRecoveryRegistration()
    )
    let cloud = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: recorded,
      registration: runRecoveryRegistration(location: .cloud, connectionKind: .http)
    )
    let localWait = AgentRunRecoveryPolicy.decide(
      snapshot: paused,
      recordedRun: recorded,
      registration: nil
    )
    let terminal = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: AgentRecordedRun(
        runId: "run",
        conversationId: "conversation",
        taskThreadId: "task",
        originalRequest: "Done",
        status: .completed
      ),
      registration: runRecoveryRegistration()
    )
    let recoverable = AgentRunEventStore.recoverableRuns([snapshot, paused, completed])

    XCTAssertEqual(durable.disposition, .reconnectDurableRemote)
    XCTAssertEqual(durable.reason, "durable_remote_run_can_reconnect")
    XCTAssertEqual(cloud.disposition, .failNonReplayable)
    XCTAssertEqual(cloud.reason, "interrupted_run_cannot_be_replayed_safely")
    XCTAssertEqual(localWait.disposition, .restoreLocalWait)
    XCTAssertEqual(localWait.reason, "user_resumable_checkpoint")
    XCTAssertEqual(terminal.disposition, .ignoreTerminal)
    XCTAssertEqual(recoverable.map(\.state), [.waitingForDevice, .paused])
  }

  func testAgentRunRecoveryModelsUseAndroidWireNames() throws {
    let decodedSnapshot = try JSONDecoder().decode(
      AgentRunControlSnapshot.self,
      from: Data(
        #"""
        {
          "run_id": "run",
          "task_id": "task",
          "state": "WAITING_FOR_DEVICE",
          "agent_id": "codex",
          "device_id": "desktop",
          "last_sequence": 4,
          "last_event": {
            "event_id": "event",
            "conversation_id": "conversation",
            "message_id": "message",
            "task_id": "task",
            "run_id": "run",
            "agent_id": "codex",
            "device_id": "desktop",
            "type": "WAITING_FOR_DEVICE",
            "sequence": 4,
            "timestamp_millis": 1000
          }
        }
        """#.utf8
      )
    )
    let decodedRegistration = try JSONDecoder().decode(
      AgentRunRecoveryRegistration.self,
      from: Data(#"{"agent_id":"codex","location":"TRUSTED_DESKTOP","connection_kind":"SIGNALASI_LINK"}"#.utf8)
    )
    let fallbackRegistration = try JSONDecoder().decode(
      AgentRunRecoveryRegistration.self,
      from: Data(#"{"agent_id":"future","location":"FUTURE","connection_kind":"FUTURE"}"#.utf8)
    )
    let missingStatus = try JSONDecoder().decode(
      AgentRecordedRun.self,
      from: Data(#"{"run_id":"run","conversation_id":"conversation","task_thread_id":"task","original_request":"Continue"}"#.utf8)
    )
    let futureStatus = try JSONDecoder().decode(
      AgentRecordedRunStatus.self,
      from: Data(#""FUTURE""#.utf8)
    )
    let encodedSnapshot = String(decoding: try JSONEncoder().encode(decodedSnapshot), as: UTF8.self)
    let encodedRegistration = String(decoding: try JSONEncoder().encode(decodedRegistration), as: UTF8.self)
    let encodedRun = String(decoding: try JSONEncoder().encode(missingStatus), as: UTF8.self)

    XCTAssertEqual(decodedSnapshot.state, .waitingForDevice)
    XCTAssertEqual(decodedSnapshot.lastEvent.type, .waitingForDevice)
    XCTAssertEqual(decodedRegistration.location, .trustedDesktop)
    XCTAssertEqual(decodedRegistration.connectionKind, .signalasiLink)
    XCTAssertEqual(fallbackRegistration.location, .cloud)
    XCTAssertEqual(fallbackRegistration.connectionKind, .http)
    XCTAssertEqual(missingStatus.status, .running)
    XCTAssertEqual(futureStatus, .failed)
    XCTAssertTrue(encodedSnapshot.contains(#""last_sequence":4"#))
    XCTAssertTrue(encodedRegistration.contains(#""connection_kind":"SIGNALASI_LINK""#))
    XCTAssertTrue(encodedRun.contains(#""task_thread_id":"task""#))
  }

  func testAgentRunStartReceiptStoreReservesAndReplaysIdempotentRequests() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    let request = runStartRequest(requiredCapabilities: [.code, .chat])

    let reserved = try store.reserve(registration: registration, request: request)
    now = 2_000
    let replay = try store.reserve(
      registration: registration,
      request: runStartRequest(runId: "run-replayed", requiredCapabilities: [.chat, .code])
    )

    XCTAssertEqual(reserved, replay)
    XCTAssertEqual(reserved.status, .reserved)
    XCTAssertEqual(reserved.createdAtMillis, 1_000)
    XCTAssertEqual(reserved.updatedAtMillis, 1_000)
    XCTAssertEqual(reserved.runId, "run")
    XCTAssertEqual(reserved.taskId, "task")
    XCTAssertEqual(
      reserved.requestDigest,
      "2c83a56ff6e923a40ce01a63d26f37f6bc2e7b78ff367da21217b92ef586b719"
    )
    XCTAssertEqual(store.find(agentId: " codex ", idempotencyKey: " key ")?.idempotencyKey, "key")

    XCTAssertThrowsError(
      try store.reserve(
        registration: registration,
        request: runStartRequest(goal: "different request content", requiredCapabilities: [.chat, .code])
      )
    ) { error in
      XCTAssertTrue((error as? AgentRunStartReceiptError)?.message.contains("different request content") == true)
    }
  }

  func testAgentRunStartReceiptStoreAcceptsPersistsAndRejectsMismatchedHandles() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    let request = runStartRequest()
    _ = try store.reserve(registration: registration, request: request)
    now = 2_000

    XCTAssertThrowsError(
      try store.accept(
        agentId: "codex",
        idempotencyKey: "key",
        handle: AgentRunHandle(runId: "wrong", taskId: "task", agentId: "codex", remoteRunId: "remote")
      )
    ) { error in
      XCTAssertTrue((error as? AgentRunStartReceiptError)?.message.contains("different Run") == true)
    }

    let handle = AgentRunHandle(
      runId: "run",
      taskId: "task",
      agentId: "codex",
      remoteRunId: "remote-1",
      acceptedAtMillis: 1_950
    )
    let accepted = try store.accept(agentId: "codex", idempotencyKey: "key", handle: handle)
    let recreated = InMemoryAgentRunStartReceiptStore(serialized: store.serializedSnapshot(), clock: { 3_000 })

    XCTAssertEqual(accepted.status, .accepted)
    XCTAssertEqual(accepted.handle, handle)
    XCTAssertEqual(accepted.error, "")
    XCTAssertEqual(accepted.updatedAtMillis, 2_000)
    XCTAssertEqual(recreated.list().count, 1)
    XCTAssertEqual(recreated.list().first?.handle?.remoteRunId, "remote-1")
    XCTAssertEqual(recreated.list().first?.status, .accepted)

    let ignored = recreated.markOutcomeUnknown(agentId: "codex", idempotencyKey: "key", error: "connection_lost")
    XCTAssertEqual(ignored?.status, .accepted)
    XCTAssertEqual(recreated.markCancelledByRun(agentId: "codex", runId: "run"), 1)
    XCTAssertEqual(recreated.list().first?.status, .cancelled)
  }

  func testAgentRunStartReceiptStoreTracksUnknownOutcomeAndBoundsSerializedReceipts() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    _ = try store.reserve(registration: registration, request: runStartRequest(runId: "run-a", idempotencyKey: "key-a"))
    now = 2_000
    let unknown = store.markOutcomeUnknown(
      agentId: "codex",
      idempotencyKey: "key-a",
      error: " connection_lost "
    )
    now = 3_000
    let accepted = try store.accept(
      agentId: "codex",
      idempotencyKey: "key-a",
      handle: AgentRunHandle(runId: "run-a", taskId: "task", agentId: "codex", remoteRunId: "remote-a")
    )

    XCTAssertEqual(unknown?.status, .outcomeUnknown)
    XCTAssertEqual(unknown?.error, "connection_lost")
    XCTAssertEqual(unknown?.updatedAtMillis, 2_000)
    XCTAssertEqual(accepted.status, .accepted)
    XCTAssertEqual(accepted.updatedAtMillis, 3_000)

    let bulk = (0..<4_005).map { index in
      AgentRunStartReceipt(
        agentId: "codex",
        installationId: "installation-codex",
        idempotencyKey: "bulk-key-\(index)",
        requestDigest: String(repeating: "b", count: 64),
        runId: "bulk-\(index)",
        taskId: "task-\(index)",
        status: .reserved,
        createdAtMillis: Int64(index),
        updatedAtMillis: Int64(index)
      )
    }
    let bulkStore = InMemoryAgentRunStartReceiptStore(
      serialized: AgentRunStartReceiptJsonCodec.encode(bulk),
      clock: { 9_000 }
    )
    XCTAssertEqual(bulkStore.markCancelledByRun(agentId: "codex", runId: "bulk-4004"), 1)
    let receipts = bulkStore.list()
    XCTAssertEqual(receipts.count, 4_000)
    XCTAssertFalse(receipts.contains { $0.idempotencyKey == "bulk-key-0" })
    XCTAssertEqual(receipts.first?.idempotencyKey, "bulk-key-4004")
    XCTAssertEqual(receipts.last?.idempotencyKey, "bulk-key-5")
  }

  func testAgentRunStartReceiptCodecUsesAndroidWireNamesAndSkipsInvalidRecords() throws {
    let valid = AgentRunStartReceipt(
      agentId: "codex",
      installationId: "installation-codex",
      idempotencyKey: "key",
      requestDigest: String(repeating: "a", count: 64),
      runId: "run",
      taskId: "task",
      status: .accepted,
      handle: AgentRunHandle(runId: "run", taskId: "task", agentId: "codex", remoteRunId: "remote", acceptedAtMillis: 123),
      createdAtMillis: 1,
      updatedAtMillis: 2
    )
    let encoded = AgentRunStartReceiptJsonCodec.encode([valid])
    let object = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])?.first
    )
    let decoded = AgentRunStartReceiptJsonCodec.decode(
      """
      [
        {"agent_id":"bad","idempotency_key":"bad","status":"FUTURE"},
        \(encoded.dropFirst().dropLast())
      ]
      """
    )

    XCTAssertEqual(object["agent_id"] as? String, "codex")
    XCTAssertEqual(object["installation_id"] as? String, "installation-codex")
    XCTAssertEqual(object["idempotency_key"] as? String, "key")
    XCTAssertEqual(object["request_digest"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(object["run_id"] as? String, "run")
    XCTAssertEqual(object["task_id"] as? String, "task")
    XCTAssertEqual(object["status"] as? String, "ACCEPTED")
    XCTAssertEqual((object["handle"] as? [String: Any])?["remote_run_id"] as? String, "remote")
    XCTAssertEqual(decoded, [valid])
    XCTAssertEqual(AgentRunStartReceiptJsonCodec.decode("not-json"), [])
  }

  func testAgentExplicitToolHandleIsOpaqueScopedAndDoesNotExposeResource() throws {
    var now: Int64 = 1_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now })
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "internal-browser-resource",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      capabilities: ["browser.navigate"],
      resource: AgentExplicitToolHandleResource(
        resourceId: "internal-browser-resource",
        payload: ["url": .string("")]
      ),
      metadata: ["mode": .string(" isolated ")]
    )

    let handleId = opened.handleId
    let publicJSON = String(decoding: try JSONEncoder.signalASI.encode(opened), as: UTF8.self)
    now = 1_250
    let resolved = try registry.resolve(
      handleId: handleId,
      kind: "browser_session",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      requiredCapability: "browser.navigate"
    )

    XCTAssertTrue(handleId.hasPrefix("sth_browsers_"))
    XCTAssertFalse(publicJSON.contains("resource_id"))
    XCTAssertFalse(publicJSON.contains("internal-browser-resource"))
    XCTAssertEqual(opened.contract, AgentExplicitToolHandleContract.version)
    XCTAssertEqual(opened.metadata["mode"]?.stringValue, "isolated")
    XCTAssertEqual(resolved.resourceId, "internal-browser-resource")
    XCTAssertEqual(resolved.resource.payload["url"]?.stringValue, "")
    XCTAssertEqual(resolved.useCount, 1)
    XCTAssertEqual(registry.status().activeCount, 1)

    assertToolHandleError("tool_handle_context_mismatch") {
      _ = try registry.resolve(
        handleId: handleId,
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-2"),
        requiredCapability: "browser.navigate"
      )
    }
  }

  func testAgentExplicitToolHandleEnforcesOwnerKindAndCapabilities() throws {
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { 2_000 })
    let opened = try registry.create(
      kind: "browser",
      resourceId: "browser-resource",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )

    assertToolHandleError("tool_handle_owner_mismatch") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-b", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
    assertToolHandleError("tool_handle_kind_mismatch") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "desktop_session",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
    assertToolHandleError("tool_handle_capability_denied") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.download"
      )
    }
  }

  func testAgentExplicitToolHandleExpiresReleasesAndRevokesResources() throws {
    var now: Int64 = 2_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now })
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "browser-1",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"],
      ttlMillis: 100,
      idleTimeoutMillis: 0
    )
    now = 2_100

    assertToolHandleError("tool_handle_expired", retryable: true) {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner"),
        requiredCapability: "browser.close"
      )
    }

    let first = try registry.create(
      kind: "browser_session",
      resourceId: "browser-2",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"]
    )
    let second = try registry.create(
      kind: "browser_session",
      resourceId: "browser-3",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"]
    )

    XCTAssertTrue(try registry.release(handleId: first.handleId, scope: AgentExplicitToolHandleScope(ownerId: "owner")))
    XCTAssertFalse(try registry.release(handleId: first.handleId, scope: AgentExplicitToolHandleScope(ownerId: "owner")))
    XCTAssertEqual(try registry.revokeResource(kind: "browser_session", resourceId: "browser-3"), 1)
    XCTAssertEqual(second.kind, "browser_session")
    XCTAssertEqual(registry.status().activeCount, 0)
  }

  func testAgentExplicitToolHandleCapacityEvictsLeastRecentlyUsed() throws {
    var now: Int64 = 3_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now }, maxHandles: 2)
    let first = try registry.create(
      kind: "browser",
      resourceId: "resource-1",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )
    now += 1
    let second = try registry.create(
      kind: "browser",
      resourceId: "resource-2",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )
    now += 1
    _ = try registry.resolve(
      handleId: first.handleId,
      kind: "browser",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      requiredCapability: "browser.navigate"
    )
    now += 1
    let third = try registry.create(
      kind: "browser",
      resourceId: "resource-3",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )

    XCTAssertEqual(registry.status().activeCount, 2)
    XCTAssertEqual(registry.status().byKind["browser"], 2)
    XCTAssertEqual(third.kind, "browser")
    XCTAssertEqual(
      try registry.resolve(
        handleId: first.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      ).resourceId,
      "resource-1"
    )
    assertToolHandleError("tool_handle_not_found", retryable: true) {
      _ = try registry.resolve(
        handleId: second.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
  }

  func testAgentExplicitToolHandleModelsUseAndroidWireNames() throws {
    let scope = try JSONDecoder.signalASI.decode(
      AgentExplicitToolHandleScope.self,
      from: Data(#"{"owner_id":"owner","context_id":"conversation"}"#.utf8)
    )
    let record = AgentExplicitToolHandlePublicRecord(
      contract: AgentExplicitToolHandleContract.version,
      handleId: "sth_browser_abc",
      kind: "browser",
      capabilities: ["browser.navigate"],
      ownerId: "owner",
      contextId: "conversation",
      metadata: ["reuse": .bool(false), "ttl": .int(60)],
      createdAtEpochMillis: 1,
      lastUsedAtEpochMillis: 2,
      expiresAtEpochMillis: 3,
      useCount: 4
    )
    let status = AgentExplicitToolHandleStatus(
      contract: AgentExplicitToolHandleContract.version,
      activeCount: 1,
      byKind: ["browser": 1]
    )
    let recordJSON = String(decoding: try JSONEncoder.signalASI.encode(record), as: UTF8.self)
    let statusJSON = String(decoding: try JSONEncoder.signalASI.encode(status), as: UTF8.self)

    XCTAssertEqual(scope.ownerId, "owner")
    XCTAssertEqual(scope.contextId, "conversation")
    XCTAssertTrue(recordJSON.contains(#""handle_id":"sth_browser_abc""#))
    XCTAssertTrue(recordJSON.contains(#""created_at_epoch_ms":1"#))
    XCTAssertTrue(recordJSON.contains(#""expires_at_epoch_ms":3"#))
    XCTAssertTrue(recordJSON.contains(#""use_count":4"#))
    XCTAssertFalse(recordJSON.contains("resource_id"))
    XCTAssertTrue(statusJSON.contains(#""active_count":1"#))
    XCTAssertTrue(statusJSON.contains(#""by_kind":{"browser":1}"#))
  }

  func testAgentPrivateDataInventoryAuditCoversExportAndEraseDecisions() {
    let audit = AgentPrivateDataInventory.audit()
    let ids = AgentPrivateDataInventory.descriptors.map(\.id)

    XCTAssertTrue(audit.complete)
    XCTAssertTrue(audit.duplicateIds.isEmpty)
    XCTAssertTrue(audit.descriptorsWithoutStorage.isEmpty)
    XCTAssertTrue(audit.exportedDescriptorsWithoutPath.isEmpty)
    XCTAssertTrue(audit.nonExportedDescriptorsWithPath.isEmpty)
    XCTAssertEqual(audit.identityRotationCount, 1)
    XCTAssertEqual(ids.count, Set(ids).count)
  }

  func testAgentPrivateDataInventoryMinimalManifestExcludesOptionalAndLocalOnlyStores() {
    let manifest = AgentPrivateDataInventory.backupManifest(
      includeContacts: false,
      includeSessionHistory: false
    )
    let included = Set(manifest.includedStoreIds)
    let excluded = Set(manifest.excludedStoreIds)

    XCTAssertEqual(manifest.policyVersion, AgentPrivateDataInventory.policyVersion)
    XCTAssertTrue(manifest.encryptedContainerRequired)
    XCTAssertFalse(manifest.privateModeExported)
    XCTAssertFalse(manifest.pausedTrackingExported)
    XCTAssertTrue(manifest.identityRotatedOnReset)
    XCTAssertTrue(included.contains("identity"))
    XCTAssertTrue(included.contains("memory"))
    XCTAssertTrue(included.contains("personal_asi"))
    XCTAssertTrue(excluded.contains("contacts"))
    XCTAssertTrue(excluded.contains("chat_history"))
    XCTAssertTrue(excluded.contains("transcript"))
    XCTAssertTrue(excluded.contains("permission_grants"))
    XCTAssertTrue(excluded.contains("run_start_receipts"))
    XCTAssertTrue(excluded.contains("runtime_files"))
    XCTAssertEqual(Set(manifest.eraseStoreIds), Set(AgentPrivateDataInventory.descriptors.map(\.id)))
  }

  func testAgentPrivateDataInventoryFullManifestIncludesChosenDataButNeverLiveAuthority() {
    let manifest = AgentPrivateDataInventory.backupManifest(
      includeContacts: true,
      includeSessionHistory: true
    )
    let included = Set(manifest.includedStoreIds)
    let excluded = Set(manifest.excludedStoreIds)
    let all = Set(AgentPrivateDataInventory.descriptors.map(\.id))

    XCTAssertTrue(included.contains("contacts"))
    XCTAssertTrue(included.contains("chat_history"))
    XCTAssertTrue(included.contains("transcript"))
    XCTAssertTrue(included.contains("home_assistant"))
    XCTAssertTrue(Set(manifest.secretStoreIds).contains("identity"))
    XCTAssertTrue(Set(manifest.secretStoreIds).contains("home_assistant"))
    XCTAssertTrue(excluded.contains("permission_grants"))
    XCTAssertTrue(excluded.contains("run_start_receipts"))
    XCTAssertTrue(excluded.contains("mcp_credentials"))
    XCTAssertEqual(included.union(excluded), all)
    XCTAssertTrue(included.intersection(excluded).isEmpty)
  }

  func testAgentPrivateDataInventoryExportedBackupPathsMatchAndroidSchema() {
    let paths = Set(
      AgentPrivateDataInventory.descriptors
        .filter { $0.exportPolicy != .neverExport }
        .map(\.backupPath)
    )

    XCTAssertEqual(
      paths,
      Set([
        "root.identity",
        "root.profile",
        "root.contacts",
        "root.friend_requests",
        "root.messages",
        "agent.memory",
        "agent.knowledge",
        "agent.tasks",
        "agent.transcript",
        "agent.agent_conversations",
        "agent.active_agent_conversation",
        "agent.workflows",
        "agent.workflow_schedules",
        "agent.workflow_triggers",
        "agent.workflow_execution_history",
        "agent.safety",
        "agent.custom_device_connectors",
        "agent.global_super_agent",
        "agent.agent_self_model",
        "agent.model_planner",
        "agent.voice_assistant",
        "agent.home_assistant"
      ])
    )
  }

  func testAgentPrivateDataInventoryModelsUseAndroidWireNames() throws {
    let descriptor = try JSONDecoder.signalASI.decode(
      AgentPrivateDataDescriptor.self,
      from: Data(
        """
        {
          "id": "identity",
          "category": "Identity",
          "storage_ids": ["keychain:identity"],
          "backup_path": "root.identity",
          "export_policy": "ALWAYS_ENCRYPTED",
          "sensitivity": "SECRET",
          "erase_policy": "DELETE_AND_ROTATE_IDENTITY"
        }
        """.utf8
      )
    )
    let fallbackPolicy = try JSONDecoder.signalASI.decode(
      AgentPrivateDataExportPolicy.self,
      from: Data(#""future""#.utf8)
    )
    let encoded = String(
      decoding: try JSONEncoder.signalASI.encode(
        AgentPrivateDataInventory.backupManifest(includeContacts: true, includeSessionHistory: false)
      ),
      as: UTF8.self
    )

    XCTAssertEqual(descriptor.exportPolicy, .alwaysEncrypted)
    XCTAssertEqual(descriptor.sensitivity, .secret)
    XCTAssertEqual(descriptor.erasePolicy, .deleteAndRotateIdentity)
    XCTAssertEqual(fallbackPolicy, .neverExport)
    XCTAssertTrue(encoded.contains(#""policy_version":1"#))
    XCTAssertTrue(encoded.contains(#""encrypted_container_required":true"#))
    XCTAssertTrue(encoded.contains(#""identity_rotated_on_reset":true"#))
    XCTAssertTrue(encoded.contains(#""erase_store_ids""#))
  }

  func testAgentFailoverPolicyMatchesAndroidDesktopFallbackAndTimeoutStages() {
    let primary = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-a")
    let cloud = AgentFailoverResource(location: .cloud, failureDomain: "cloud-openai")
    let phone = AgentFailoverResource(location: .phone, failureDomain: "phone")
    let otherDesktop = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-b")
    let sameDesktop = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-a")

    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: cloud), 0)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: phone), 0)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: otherDesktop), 1)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: sameDesktop), 2)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: phone, candidate: sameDesktop), 0)

    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .notAccepted, status: "", liveReadOnly: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .notAccepted, status: "accepted", liveReadOnly: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .notRunning, status: "queued", liveReadOnly: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .notRunning, status: "running", liveReadOnly: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .readOnlyStale, status: "running", liveReadOnly: true)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .readOnlyStale, status: "running", liveReadOnly: false)
    )
  }

  func testAgentFailoverPolicyMatchesAndroidOnlyResourceAndCooldownBehavior() {
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "accepted", hasFallback: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "queued", hasFallback: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "accepted", hasFallback: true)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notAccepted, status: "", hasFallback: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .readOnlyStale, status: "running", hasFallback: false)
    )

    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 0), 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 1), 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 2), 5 * 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 3), 15 * 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 8), 60 * 60_000)
  }

  func testAgentConnectorTimingPolicyMatchesAndroidAttachmentDeadlinesAndWireNames() throws {
    let regular = AgentConnectorTimingPolicy.deadlines(hasAttachments: false)
    let attachment = AgentConnectorTimingPolicy.deadlines(hasAttachments: true)

    XCTAssertEqual(regular.acceptedMs, 5_000)
    XCTAssertEqual(regular.runningMs, 8_000)
    XCTAssertEqual(regular.liveStaleMs, 15_000)
    XCTAssertEqual(attachment.acceptedMs, 60_000)
    XCTAssertEqual(attachment.runningMs, 90_000)
    XCTAssertGreaterThan(attachment.liveStaleMs, regular.liveStaleMs)

    let encoded = try JSONEncoder.signalASI.encode(attachment)
    let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(encodedObject["accepted_ms"] as? Int, 60_000)
    XCTAssertEqual(encodedObject["running_ms"] as? Int, 90_000)
    XCTAssertEqual(encodedObject["live_stale_ms"] as? Int, 180_000)

    let stage = try JSONDecoder.signalASI.decode(
      AgentConnectorTimeoutStage.self,
      from: Data(#""READ_ONLY_STALE""#.utf8)
    )
    let resource = try JSONDecoder.signalASI.decode(
      AgentFailoverResource.self,
      from: Data(#"{"location":"TRUSTED_DESKTOP","failure_domain":"desktop-a"}"#.utf8)
    )

    XCTAssertEqual(stage, .readOnlyStale)
    XCTAssertEqual(resource.location, .trustedDesktop)
    XCTAssertEqual(resource.failureDomain, "desktop-a")
  }

  func testAgentCronExpressionMatchesAndroidTimeZoneAndWeekdayBehavior() throws {
    func millis(
      year: Int,
      month: Int,
      day: Int,
      hour: Int,
      minute: Int,
      timeZone: TimeZone
    ) -> Int64 {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      var components = DateComponents()
      components.calendar = calendar
      components.timeZone = timeZone
      components.year = year
      components.month = month
      components.day = day
      components.hour = hour
      components.minute = minute
      return Int64(((calendar.date(from: components)?.timeIntervalSince1970 ?? 0) * 1_000).rounded())
    }

    let weekdayCron = try AgentCronExpression.parse("30 9 * * mon-fri")
    let shanghai = try AgentCronExpression.parseZone("Asia/Shanghai")
    let friday = millis(year: 2026, month: 7, day: 24, hour: 9, minute: 31, timeZone: shanghai)
    let nextMonday = millis(year: 2026, month: 7, day: 27, hour: 9, minute: 30, timeZone: shanghai)

    XCTAssertEqual(
      try weekdayCron.nextAfter(timestampMillis: friday, timeZoneIdentifier: shanghai.identifier),
      nextMonday
    )

    let dayOrWeekday = try AgentCronExpression.parse("0 12 1 * mon")
    let utc = try AgentCronExpression.parseZone("UTC")
    let monday = Date(timeIntervalSince1970: Double(millis(year: 2026, month: 7, day: 6, hour: 12, minute: 0, timeZone: utc)) / 1_000)
    let firstOfMonth = Date(timeIntervalSince1970: Double(millis(year: 2026, month: 8, day: 1, hour: 12, minute: 0, timeZone: utc)) / 1_000)

    XCTAssertTrue(dayOrWeekday.matches(date: monday, timeZone: utc))
    XCTAssertTrue(dayOrWeekday.matches(date: firstOfMonth, timeZone: utc))
  }

  func testAgentCronExpressionSupportsAliasesListsStepsAndPreviousMatches() throws {
    func date(
      year: Int,
      month: Int,
      day: Int,
      hour: Int,
      minute: Int,
      timeZone: TimeZone
    ) -> Date {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      var components = DateComponents()
      components.calendar = calendar
      components.timeZone = timeZone
      components.year = year
      components.month = month
      components.day = day
      components.hour = hour
      components.minute = minute
      return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    let cron = try AgentCronExpression.parse("*/15 8,12 * jan,mar 0,7")
    let utc = try AgentCronExpression.parseZone("UTC")
    let sunday = date(year: 2026, month: 3, day: 1, hour: 12, minute: 45, timeZone: utc)
    let monday = date(year: 2026, month: 3, day: 2, hour: 12, minute: 45, timeZone: utc)
    let daily = try AgentCronExpression.parse("0 9 * * *")
    let after = Int64((date(year: 2026, month: 3, day: 2, hour: 9, minute: 30, timeZone: utc).timeIntervalSince1970 * 1_000).rounded())
    let expectedPrevious = Int64((date(year: 2026, month: 3, day: 2, hour: 9, minute: 0, timeZone: utc).timeIntervalSince1970 * 1_000).rounded())

    XCTAssertTrue(cron.matches(date: sunday, timeZone: utc))
    XCTAssertFalse(cron.matches(date: monday, timeZone: utc))
    XCTAssertEqual(
      try daily.previousAtOrBefore(timestampMillis: after, timeZoneIdentifier: "UTC"),
      expectedPrevious
    )
    XCTAssertThrowsError(try AgentCronExpression.parse("60 * * * *"))
    XCTAssertThrowsError(try AgentCronExpression.parseZone("Not/AZone"))
  }

  func testAgentProactiveTaskSchedulerIntervalCatchUpIsBounded() throws {
    let now: Int64 = 1_800_000_000_000
    let task = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(
        misfire: .catchUp,
        catchUpLimit: 3
      ),
      nextRunAtMillis: now - 20 * 60 * 1_000
    )

    let result = try AgentProactiveTaskScheduler.dueOccurrences(task: task, nowMillis: now)

    XCTAssertEqual(result.occurrences.count, 3)
    XCTAssertTrue(result.occurrences.allSatisfy { $0.status == .queued })
    XCTAssertTrue(result.nextRunAtMillis > now)
  }

  func testAgentProactiveTaskSchedulerFireOnceAndSkipCollapseMissedIntervals() throws {
    let now: Int64 = 1_800_000_000_000
    let fireOnceTask = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(misfire: .fireOnce),
      nextRunAtMillis: now - 10 * 60 * 1_000
    )
    let skipTask = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(
        misfire: .skip,
        catchUpLimit: 2
      ),
      nextRunAtMillis: now - 10 * 60 * 1_000
    )

    let fireOnce = try AgentProactiveTaskScheduler.dueOccurrences(task: fireOnceTask, nowMillis: now)
    let skipped = try AgentProactiveTaskScheduler.dueOccurrences(task: skipTask, nowMillis: now)

    XCTAssertEqual(fireOnce.occurrences.map(\.status), [.queued])
    XCTAssertTrue(fireOnce.nextRunAtMillis > now)
    XCTAssertEqual(skipped.occurrences.count, 2)
    XCTAssertTrue(skipped.occurrences.allSatisfy { $0.status == .skipped })
    XCTAssertTrue(skipped.nextRunAtMillis > now)
  }

  func testAgentProactiveTaskPolicyValidatesTeamLeadAndGoalCheckpoint() throws {
    XCTAssertThrowsError(
      try AgentProactiveAction(
        kind: .subagentTeam,
        team: [
          try AgentProactiveTeamMember(agentId: "codex", role: .observer),
          try AgentProactiveTeamMember(agentId: "hermes", role: .verifier)
        ]
      )
    )
    XCTAssertThrowsError(
      try AgentProactiveTrigger(
        kind: .goalCheckpoint,
        intervalSeconds: 300,
        goalId: ""
      )
    )
  }

  func testAgentProactiveTaskSchedulerInitialRunJitterAndOutcomeDisableRules() throws {
    let now: Int64 = 1_800_000_000_000
    let jitterTask = try proactiveIntervalTask(
      taskId: "jitter-task",
      policy: try AgentProactivePolicy(jitterSeconds: 30),
      nextRunAtMillis: 0
    )

    let next = try AgentProactiveTaskScheduler.initialNextRun(task: jitterTask, nowMillis: now)

    XCTAssertGreaterThanOrEqual(next, now + 60_000)
    XCTAssertLessThanOrEqual(next, now + 90_000)
    XCTAssertEqual(next, try AgentProactiveTaskScheduler.initialNextRun(task: jitterTask, nowMillis: now))

    let limited = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(maxRuns: 1),
      nextRunAtMillis: now + 60_000
    )
    let completed = try AgentProactiveTaskScheduler.recordOutcome(
      task: limited,
      status: .completed,
      completedAtMillis: now
    )

    XCTAssertFalse(completed.enabled)
    XCTAssertEqual(completed.nextRunAtMillis, 0)
    XCTAssertEqual(completed.lastStatus, .completed)
    XCTAssertEqual(completed.runCount, 1)
    XCTAssertEqual(completed.consecutiveFailures, 0)

    let failing = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(maxConsecutiveFailures: 2),
      nextRunAtMillis: now + 60_000,
      consecutiveFailures: 1
    )
    let failed = try AgentProactiveTaskScheduler.recordOutcome(
      task: failing,
      status: .failed,
      completedAtMillis: now
    )

    XCTAssertFalse(failed.enabled)
    XCTAssertEqual(failed.consecutiveFailures, 2)
    XCTAssertTrue(
      AgentProactiveTaskScheduler.shouldDisable(
        task: try proactiveIntervalTask(
          policy: try AgentProactivePolicy(deadlineAtMillis: now - 1),
          nextRunAtMillis: now + 60_000
        ),
        nowMillis: now
      )
    )
  }

  func testAgentProactiveTaskModelsUseAndroidWireNames() throws {
    let task = try AgentProactiveTask(
      taskId: "wire-task",
      name: "Wire task",
      trigger: try AgentProactiveTrigger(
        kind: .interval,
        intervalSeconds: 300,
        eventFilter: ["source.type": "desktop"]
      ),
      action: try AgentProactiveAction(
        kind: .nativeTool,
        targetId: "open_url",
        prompt: "Open the latest report",
        argumentsJson: #"{"path":"/tmp/report.txt","limit":2}"#,
        deliveryMode: "mobile",
        clientRouteId: "route-1",
        grantedPermissions: ["native.open_url"],
        grantedConsents: ["user-approved"]
      ),
      policy: try AgentProactivePolicy(
        misfire: .catchUp,
        catchUpLimit: 4,
        maxConcurrency: 2,
        network: "unmetered",
        requiresCharging: true
      ),
      nextRunAtMillis: 1_800_000_060_000
    )
    let run = try AgentProactiveRun(
      runId: "run-1",
      taskId: task.taskId,
      scheduledForMillis: 1_800_000_060_000,
      status: .waiting,
      attempt: 2,
      causeJson: #"{"type":"manual"}"#,
      linkedExecutionId: "execution-1",
      teamRunId: "team-1"
    )

    let taskObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
    let triggerObject = try XCTUnwrap(taskObject["trigger"] as? [String: Any])
    let actionObject = try XCTUnwrap(taskObject["action"] as? [String: Any])
    let policyObject = try XCTUnwrap(taskObject["policy"] as? [String: Any])
    let runObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])

    XCTAssertEqual(taskObject["protocol"] as? String, AgentProactiveTaskScheduler.protocolVersion)
    XCTAssertEqual(taskObject["task_id"] as? String, "wire-task")
    XCTAssertNotNil(taskObject["next_run_at_millis"])
    XCTAssertEqual(triggerObject["interval_seconds"] as? Int, 300)
    XCTAssertEqual(triggerObject["event_filter"] as? [String: String], ["source.type": "desktop"])
    XCTAssertEqual(actionObject["target_id"] as? String, "open_url")
    XCTAssertNotNil(actionObject["arguments"] as? [String: Any])
    XCTAssertNil(actionObject["arguments_json"])
    XCTAssertEqual(actionObject["delivery_mode"] as? String, "mobile")
    XCTAssertEqual(actionObject["client_route_id"] as? String, "route-1")
    XCTAssertEqual(policyObject["catch_up_limit"] as? Int, 4)
    XCTAssertEqual(policyObject["max_concurrency"] as? Int, 2)
    XCTAssertEqual(policyObject["requires_charging"] as? Bool, true)
    XCTAssertNotNil(runObject["cause"] as? [String: Any])
    XCTAssertNil(runObject["cause_json"])
    XCTAssertEqual(runObject["linked_execution_id"] as? String, "execution-1")

    let decoded = try JSONDecoder().decode(AgentProactiveTask.self, from: JSONEncoder().encode(task))
    let fallback = try JSONDecoder().decode(
      AgentProactiveMisfirePolicy.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(decoded.action.argumentsJson, #"{"limit":2,"path":"/tmp/report.txt"}"#)
    XCTAssertEqual(decoded.policy.misfire, .catchUp)
    XCTAssertEqual(fallback, .fireOnce)
  }

  func testGlobalProactiveInboxProjectsDeliveredFindingsAndDigests() {
    let items = GlobalProactiveInboxPolicy.project(
      messages: [
        globalProactiveMessage("current"),
        globalProactiveMessage("topic", target: .newConversation)
      ],
      feedback: []
    )
    let digest = GlobalProactiveInboxPolicy.project(
      messages: [
        globalProactiveMessage("digest-a", target: .globalDigest, deliveryGroupId: "daily"),
        globalProactiveMessage(
          "digest-b",
          target: .globalDigest,
          content: "A second material change is ready.",
          topic: "Release risk",
          deliveryGroupId: "daily"
        )
      ],
      feedback: []
    )

    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(GlobalProactiveInboxPolicy.newCount(items), 2)
    XCTAssertTrue(items.allSatisfy(\.isNew))
    XCTAssertEqual(Set(items.map(\.destinationConversationId)), Set(["destination"]))
    XCTAssertEqual(digest.count, 1)
    XCTAssertEqual(digest.first?.key, "global-agent-digest:daily")
    XCTAssertEqual(digest.first?.messageIds, Set(["digest-a", "digest-b"]))
    XCTAssertTrue(digest.first?.content.contains("Release risk") == true)
  }

  func testGlobalProactiveInboxFiltersStatusesAndFeedback() {
    let pending = globalProactiveMessage("pending", status: .pending)
    let dismissed = globalProactiveMessage("dismissed", status: .dismissed)
    let helpful = globalProactiveMessage("helpful")
    let irrelevant = globalProactiveMessage("irrelevant")
    let frequent = globalProactiveMessage("frequent")

    let statusItems = GlobalProactiveInboxPolicy.project(messages: [pending, dismissed], feedback: [])
    let helpfulItem = GlobalProactiveInboxPolicy.project(
      messages: [helpful],
      feedback: [globalAgentFeedback(messageId: helpful.id, kind: .helpful)]
    ).first
    let negativeItems = GlobalProactiveInboxPolicy.project(
      messages: [irrelevant, frequent],
      feedback: [
        globalAgentFeedback(messageId: irrelevant.id, kind: .notRelevant),
        globalAgentFeedback(messageId: frequent.id, kind: .tooFrequent)
      ]
    )

    XCTAssertTrue(statusItems.isEmpty)
    XCTAssertFalse(helpfulItem?.isNew ?? true)
    XCTAssertEqual(helpfulItem?.feedbackKind, .helpful)
    XCTAssertTrue(negativeItems.isEmpty)
  }

  func testGlobalProactiveInboxMarksOnlySelectedDeliveredMessagesViewed() {
    let delivered = globalProactiveMessage("delivered")
    let untouched = globalProactiveMessage("untouched")
    let pending = globalProactiveMessage("pending", status: .pending)

    let updated = Dictionary(
      uniqueKeysWithValues: GlobalProactiveInboxPolicy.markViewed(
        messages: [delivered, untouched, pending],
        messageIds: Set(["delivered", "pending"]),
        nowMillis: 9_000
      ).map { ($0.id, $0) }
    )

    XCTAssertEqual(updated["delivered"]?.viewedAtMillis, 9_000)
    XCTAssertEqual(updated["untouched"]?.viewedAtMillis, 0)
    XCTAssertEqual(updated["pending"]?.viewedAtMillis, 0)
  }

  func testGlobalProactiveInboxModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      GlobalProactiveMessage.self,
      from: Data(
        #"""
        {
          "id": "wire",
          "source_event_id": "event-wire",
          "source_conversation_id": "source",
          "target": "global-digest",
          "title": "Signal digest",
          "content": "Digest ready",
          "topic": "Release risk",
          "urgent": true,
          "causal_event_ids": ["event-a", "event-b"],
          "status": "delivered",
          "delivered_at_millis": 5,
          "delivered_conversation_id": "destination",
          "delivery_group_id": "daily"
        }
        """#.utf8
      )
    )
    let feedback = try JSONDecoder().decode(
      GlobalAgentFeedback.self,
      from: Data(
        #"""
        {
          "proactive_message_id": "wire",
          "delivery_group_id": "daily",
          "conversation_id": "destination",
          "topic": "Release risk",
          "target": "CURRENT_CONVERSATION",
          "kind": "too-frequent",
          "created_at_millis": 6
        }
        """#.utf8
      )
    )
    let fallbackTarget = try JSONDecoder().decode(
      GlobalProactiveTarget.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackStatus = try JSONDecoder().decode(
      GlobalProactiveMessageStatus.self,
      from: Data(#""future""#.utf8)
    )
    let legacy = GlobalProactiveInboxPolicy.project(
      messages: [globalProactiveMessage("legacy", title: "Signal \u{5efa}\u{8bae}")],
      feedback: []
    ).first
    let projected = try XCTUnwrap(GlobalProactiveInboxPolicy.project(messages: [decoded], feedback: []).first)
    let encoded = String(decoding: try JSONEncoder().encode(projected), as: UTF8.self)

    XCTAssertEqual(decoded.target, .globalDigest)
    XCTAssertEqual(decoded.status, .delivered)
    XCTAssertEqual(decoded.causalEventIds, Set(["event-a", "event-b"]))
    XCTAssertEqual(feedback.kind, .tooFrequent)
    XCTAssertEqual(fallbackTarget, .currentConversation)
    XCTAssertEqual(fallbackStatus, .pending)
    XCTAssertEqual(legacy?.title, "SignalASI \u{5efa}\u{8bae}")
    XCTAssertEqual(GlobalAgentText.productTitle("Signal Protocol"), "Signal Protocol")
    XCTAssertTrue(encoded.contains(#""message_ids""#))
    XCTAssertTrue(encoded.contains(#""destination_conversation_id":"destination""#))
  }

  func testAgentTranscriptScrollPolicyMatchesAndroidAutoFollowAndPagination() {
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: true,
        userScrollActive: false,
        itemCount: 3,
        lastVisiblePosition: 2,
        remainingPx: 600,
        thresholdPx: 56
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: true,
        userScrollActive: true,
        itemCount: 3,
        lastVisiblePosition: 1,
        remainingPx: Int.max,
        thresholdPx: 56
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: false,
        userScrollActive: true,
        itemCount: 3,
        lastVisiblePosition: 2,
        remainingPx: 20,
        thresholdPx: 56
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: -8,
        firstVisiblePosition: 1,
        hydrationPending: false
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: false,
        hydrationPending: false,
        thresholdPx: 24
      )
    )
  }

  func testAgentTranscriptScrollPolicyBlocksOrdinaryScrollAndHydration() {
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: 12,
        firstVisiblePosition: 0,
        hydrationPending: false
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: true,
        hydrationPending: false,
        thresholdPx: 24
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: -8,
        firstVisiblePosition: 0,
        hydrationPending: true
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: false,
        hydrationPending: true,
        thresholdPx: 24
      )
    )
  }

  func testAgentFinalResponseIdentityMatchesAndroidPriorityAndResolution() {
    let local = AgentFinalResponseIdentity.dedupeKey(
      turnId: "turn-1",
      sourceMessageId: 101,
      taskId: "mobile-session"
    )
    let remote = AgentFinalResponseIdentity.dedupeKey(
      turnId: "turn-1",
      sourceMessageId: 101,
      taskId: "desktop-task"
    )

    XCTAssertEqual(local, remote)
    XCTAssertEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "", sourceMessageId: 202, taskId: "mobile-session"),
      AgentFinalResponseIdentity.dedupeKey(turnId: "", sourceMessageId: 202, taskId: "desktop-task")
    )
    XCTAssertNotEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "turn-1", sourceMessageId: 101, taskId: "task"),
      AgentFinalResponseIdentity.dedupeKey(turnId: "turn-2", sourceMessageId: 101, taskId: "task")
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "", taskId: " task-1 "),
      "assistant-final:task:task-1"
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId: "",
        taskId: "task-1"
      ) { taskId in
        taskId == "task-1" ? "turn-1" : nil
      },
      "turn-1"
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId: " turn-2 ",
        taskId: "task-1"
      ) { _ in "turn-1" },
      "turn-2"
    )
  }

  func testAgentTranscriptEntryDecodesAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentTranscriptEntry.self,
      from: Data(
        #"""
        {
          "id": "entry-1",
          "role": "ASSISTANT",
          "text": "CODEX_OK",
          "timestamp_millis": 42,
          "dedupe_key": "assistant-final:turn:turn-1",
          "conversation_id": "conversation",
          "turn_id": "turn-1",
          "task_id": "task-1",
          "rich_output_json": "{\"type\":\"markdown\"}",
          "source_conversation_id": "source-conversation",
          "source_conversation_title": "Source",
          "source_entry_id": "source-entry"
        }
        """#.utf8
      )
    )

    XCTAssertEqual(decoded.role, .assistant)
    XCTAssertEqual(decoded.timestampMillis, 42)
    XCTAssertEqual(decoded.dedupeKey, "assistant-final:turn:turn-1")
    XCTAssertEqual(decoded.richOutputJson, #"{"type":"markdown"}"#)
    XCTAssertEqual(decoded.sourceConversationTitle, "Source")

    let fallback = try JSONDecoder().decode(
      AgentTranscriptEntry.self,
      from: Data(#"{"id":"entry-2","role":"FUTURE","text":"Running"}"#.utf8)
    )
    XCTAssertEqual(fallback.role, .process)

    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
    XCTAssertTrue(encoded.contains(#""timestamp_millis":42"#))
    XCTAssertTrue(encoded.contains(#""dedupe_key":"assistant-final:turn:turn-1""#))
    XCTAssertTrue(encoded.contains(#""rich_output_json":"#))
  }

  func testAgentTranscriptLifecyclePolicyRemovesOnlyLegacyPlannerProcessRows() {
    XCTAssertTrue(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .process,
        dedupeKey: "pending:plan:ask-codex:1"
      )
    )
    XCTAssertFalse(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .user,
        dedupeKey: "pending:plan:user-text:1"
      )
    )
    XCTAssertFalse(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .process,
        dedupeKey: "connector-task:task-id"
      )
    )
  }

  func testAgentTranscriptLifecyclePolicyRecoversStaleConnectorTurnWithoutAssistantReply() {
    let entries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry("remote", timestampMillis: 2, dedupeKey: "connector-task:task")
    ]
    let task = agentTaskRecord(
      phase: .completed,
      result: " Recovered result\n",
      updatedAtMillis: 2
    )

    let recovered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: entries,
      tasks: [task],
      activeTaskIds: [],
      nowMillis: AgentTranscriptLifecyclePolicy.staleConnectorMillis + 3
    )

    XCTAssertEqual(recovered.count, 1)
    XCTAssertEqual(recovered.first?.conversationId, "conversation")
    XCTAssertEqual(recovered.first?.turnId, "turn")
    XCTAssertEqual(recovered.first?.taskId, "task")
    XCTAssertEqual(recovered.first?.result, "Recovered result")
  }

  func testAgentTranscriptLifecyclePolicySkipsActiveAnsweredFreshAndInternalPlannerResults() {
    let user = transcriptEntry("user", role: .user, timestampMillis: 1)
    let process = transcriptEntry("remote", timestampMillis: 2, dedupeKey: "connector-task:task")
    let approval = transcriptEntry(
      "approval",
      role: .assistant,
      timestampMillis: 3,
      dedupeKey: "remote-approval:task"
    )
    let assistant = transcriptEntry(
      "assistant",
      role: .assistant,
      timestampMillis: 4,
      dedupeKey: "assistant-final:turn:turn"
    )
    let task = agentTaskRecord(result: "Recovered result", updatedAtMillis: 2)

    let answered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process, assistant],
      tasks: [task],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let active = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process],
      tasks: [task],
      activeTaskIds: ["task"],
      nowMillis: 10 * 60 * 1_000
    )
    let fresh = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process],
      tasks: [agentTaskRecord(result: "Recovered result", updatedAtMillis: 9 * 60 * 1_000)],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let approvalOnly = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process, approval],
      tasks: [task],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let internalPlanner = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [
        transcriptEntry("user-2", role: .user, turnId: "turn-2", timestampMillis: 1, taskId: "internal-task"),
        transcriptEntry(
          "remote-2",
          turnId: "turn-2",
          timestampMillis: 2,
          dedupeKey: "connector-task:internal-task",
          taskId: "internal-task"
        )
      ],
      tasks: [
        agentTaskRecord(
          taskId: "internal-task",
          result: "Create a safe local task plan for local-agent-runtime",
          updatedAtMillis: 2
        )
      ],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )

    XCTAssertTrue(answered.isEmpty)
    XCTAssertTrue(active.isEmpty)
    XCTAssertTrue(fresh.isEmpty)
    XCTAssertEqual(approvalOnly.count, 1)
    XCTAssertEqual(internalPlanner.count, 1)
    XCTAssertEqual(internalPlanner.first?.result, "")
  }

  func testAgentTranscriptLifecycleModelsUseAndroidWireNames() throws {
    let decodedTask = try JSONDecoder().decode(
      AgentTaskRecord.self,
      from: Data(
        #"""
        {
          "task_id": "task",
          "session_id": "conversation",
          "goal": "goal",
          "phase": "COMPLETED",
          "route_kind": "DESKTOP_AGENT",
          "target_title": "Codex",
          "risk": "LOW",
          "blocked": false,
          "result": "Recovered",
          "verification": "Verified",
          "output_files": ["report.md"],
          "execution_log": ["step"],
          "created_at_millis": 1,
          "updated_at_millis": 2
        }
        """#.utf8
      )
    )
    let fallbackTask = try JSONDecoder().decode(
      AgentTaskRecord.self,
      from: Data(#"{"task_id":"future","session_id":"conversation","goal":"goal","phase":"FUTURE","route_kind":"FUTURE","risk":"FUTURE"}"#.utf8)
    )
    let recovery = AgentStaleConnectorRecovery(
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      result: "Recovered"
    )
    let encodedTask = String(decoding: try JSONEncoder().encode(decodedTask), as: UTF8.self)
    let encodedRecovery = String(decoding: try JSONEncoder().encode(recovery), as: UTF8.self)

    XCTAssertEqual(decodedTask.phase, .completed)
    XCTAssertEqual(decodedTask.routeKind, .desktopAgent)
    XCTAssertEqual(decodedTask.risk, .low)
    XCTAssertEqual(decodedTask.outputFiles, ["report.md"])
    XCTAssertEqual(decodedTask.executionLog, ["step"])
    XCTAssertEqual(fallbackTask.phase, .executing)
    XCTAssertEqual(fallbackTask.routeKind, .unknown)
    XCTAssertEqual(fallbackTask.risk, .medium)
    XCTAssertTrue(encodedTask.contains(#""updated_at_millis":2"#))
    XCTAssertTrue(encodedTask.contains(#""route_kind":"DESKTOP_AGENT""#))
    XCTAssertTrue(encodedRecovery.contains(#""conversation_id":"conversation""#))
    XCTAssertTrue(encodedRecovery.contains(#""turn_id":"turn""#))
  }

  func testAgentTranscriptPresentationPolicyCollapsesProcessGroupsBetweenUserAndAssistant() {
    let entries = [
      transcriptEntry("process-before-user", timestampMillis: 1),
      transcriptEntry("user", role: .user, timestampMillis: 2),
      transcriptEntry("process-running", timestampMillis: 3),
      transcriptEntry("process-linux", timestampMillis: 4),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 5)
    ]

    let visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

    XCTAssertEqual(visible.map(\.role), [.user, .process, .assistant])
    XCTAssertEqual(visible[1].text, "process-linux")
    XCTAssertTrue(visible[1].id.hasPrefix("process-group:"))
  }

  func testAgentTranscriptPresentationPolicyFoldsRemoteCompletionAndKeepsStableRenderId() {
    let user = transcriptEntry("user", role: .user, timestampMillis: 10)
    let accepted = transcriptEntry("accepted", timestampMillis: 20)
    let running = transcriptEntry("running", timestampMillis: 30)
    let assistant = transcriptEntry("assistant", role: .assistant, timestampMillis: 40)
    let completed = transcriptEntry(
      "completed",
      turnId: "remote-codex-turn",
      timestampMillis: 50
    )

    let completedVisible = AgentTranscriptPresentationPolicy.collapseProcessGroups([
      user,
      running,
      assistant,
      completed
    ])
    let initial = AgentTranscriptPresentationPolicy.collapseProcessGroups([user, accepted])
    let updated = AgentTranscriptPresentationPolicy.collapseProcessGroups([user, running])
    let diff = AgentTranscriptRenderPolicy.diff(
      renderedIds: initial.map(\.id),
      renderedSignatures: Dictionary(uniqueKeysWithValues: initial.map {
        ($0.id, AgentTranscriptRenderPolicy.signature($0))
      }),
      incoming: updated
    )

    XCTAssertEqual(completedVisible.map(\.role), [.user, .process, .assistant])
    XCTAssertEqual(completedVisible[1].text, "completed")
    XCTAssertEqual(completedVisible[1].turnId, "turn")
    XCTAssertEqual(initial[1].id, updated[1].id)
    XCTAssertFalse(diff.reset)
    XCTAssertEqual(diff.replacementIndices, [1])
  }

  func testAgentTranscriptPresentationPolicyClassifiesExpansionCompletionAndDurations() {
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{5df2}\u{5206}\u{6790}\u{8bf7}\u{6c42}"),
      .analysis
    )
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{6b63}\u{5728}\u{8fd0}\u{884c}\u{624b}\u{673a}\u{672c}\u{5730} Linux"),
      .command
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.processVisualKind("Edited 2 files"), .file)
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{5df2}\u{67e5}\u{770b} 1 \u{5f20}\u{56fe}\u{7247}"),
      .image
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.processVisualKind("Web search complete"), .network)

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processExpanded(
      completed: false,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: false
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processExpanded(
      completed: false,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: true
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processExpanded(
      completed: true,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: false
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processExpanded(
      completed: true,
      manuallyExpanded: true,
      manuallyCollapsedWhileActive: false
    ))

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processClockStopsFor(.waitingConfirmation))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processClockStopsFor(.completed))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processClockStopsFor(.executing))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processClockStopsFor(.waitingResponse))

    XCTAssertFalse(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: true
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: nil
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: false
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: false,
      awaitingResponse: true
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callNativeTool,
      succeeded: true,
      awaitingResponse: false
    ))

    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(0), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(999), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(1_999), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(2_000), "2s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(59_999), "59s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(60_000), "1m")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(77_000), "1m 17s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(3_600_000), "1h")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(4_646_000), "1h 17m 26s")
  }

  func testAgentTranscriptPresentationPolicySegmentsVisibleProcessRows() {
    let entries = [
      transcriptEntry(
        "generic-analysis",
        text: "Analyzed the request - Codex",
        dedupeKey: "audit:1:REASONING_SUMMARY:fallback"
      ),
      transcriptEntry("tool-start", timestampMillis: 2, dedupeKey: "audit:2:TOOL_STARTED:x"),
      transcriptEntry("tool-complete", timestampMillis: 3, dedupeKey: "audit:3:TOOL_COMPLETED:x"),
      transcriptEntry(
        "plan",
        timestampMillis: 4,
        text: "Implement a small Python program",
        dedupeKey: "pending:plan:action"
      ),
      transcriptEntry("phone-linux", timestampMillis: 5, dedupeKey: "audit:5:TOOL_STARTED:y"),
      transcriptEntry("phone-linux-complete", timestampMillis: 6, dedupeKey: "audit:6:TOOL_COMPLETED:y")
    ]
    let connectorEntries = [
      transcriptEntry(
        "fallback-analysis",
        text: "Analyzed the request",
        dedupeKey: "audit:1:REASONING_SUMMARY:fallback"
      ),
      transcriptEntry("running-codex", text: "Running Codex", dedupeKey: "audit:2:TOOL_STARTED:codex"),
      transcriptEntry(
        "commentary",
        timestampMillis: 3,
        text: "I will inspect the provided input before acting.",
        dedupeKey: "connector-event:task:REASONING_SUMMARY:codex:commentary:1"
      ),
      transcriptEntry(
        "image-view",
        timestampMillis: 4,
        text: "Viewed 1 image",
        dedupeKey: "connector-event:task:TOOL_EVENT:codex:image_view:1"
      )
    ]

    let segments = AgentTranscriptPresentationPolicy.processSegments(entries)
    let connectorSegments = AgentTranscriptPresentationPolicy.processSegments(connectorEntries)

    XCTAssertEqual(segments.map(\.kind), [.toolActivity, .narration, .toolActivity])
    XCTAssertEqual(segments.map { $0.entries.count }, [3, 1, 2])
    XCTAssertEqual(
      connectorSegments.flatMap { $0.entries }.map(\.text),
      ["I will inspect the provided input before acting.", "Viewed 1 image"]
    )
    XCTAssertEqual(connectorSegments.map(\.kind), [.narration, .toolActivity])
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.narrationSegments(connectorEntries).flatMap { $0.entries }.map(\.text),
      ["I will inspect the provided input before acting."]
    )
  }

  func testAgentTranscriptPresentationPolicyFiltersInternalProcessNoise() {
    let loopEntries = [
      transcriptEntry("planning", text: "Planning", dedupeKey: "agent-loop:turn:PLAN:1"),
      transcriptEntry("observe", timestampMillis: 2, text: "Checking the result", dedupeKey: "agent-loop:turn:OBSERVE:2"),
      transcriptEntry(
        "waiting",
        timestampMillis: 3,
        text: "Waiting for a resource",
        dedupeKey: "agent-loop:turn:WAITING_RESPONSE:3"
      ),
      transcriptEntry(
        "heartbeat",
        timestampMillis: 4,
        text: "Working",
        dedupeKey: "connector-event:task:TOOL_EVENT:codex:heartbeat:1"
      ),
      transcriptEntry("watchdog", timestampMillis: 5, text: "No progress reported", dedupeKey: "task-watchdog:turn"),
      transcriptEntry("finalize", timestampMillis: 6, text: "Finalizing", dedupeKey: "agent-loop:turn:FINALIZE:4")
    ]
    let legacyEntries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry(
        "legacy-zh",
        timestampMillis: 2,
        text: "\u{8fd0}\u{884c}\u{4e86} 3 \u{4e2a}\u{5de5}\u{5177}\u{6b65}\u{9aa4}",
        dedupeKey: "pending:legacy:tool-summary"
      ),
      transcriptEntry("legacy-en", timestampMillis: 3, text: "Ran 2 tool steps.", dedupeKey: "pending:legacy:tool-summary-en"),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 4)
    ]
    let runtimeEntries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry(
        "runtime",
        timestampMillis: 2,
        text: "Execute in the on-device Linux sandbox",
        dedupeKey: "pending:plan:runtime"
      ),
      transcriptEntry(
        "implementation",
        timestampMillis: 3,
        text: "Implement a small Python program",
        dedupeKey: "pending:plan:summary"
      ),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 4)
    ]

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processSegments(loopEntries).isEmpty())
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.collapseProcessGroups(legacyEntries).map(\.text),
      ["user", "assistant"]
    )
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processSegments(legacyEntries).isEmpty())
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.collapseProcessGroups(runtimeEntries).map(\.text),
      ["user", "Implement a small Python program", "assistant"]
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.controlMessageKind("Task cancelled"), .cancelled)
    XCTAssertEqual(AgentTranscriptPresentationPolicy.controlMessageKind(" task CANCELED "), .cancelled)
    XCTAssertNil(AgentTranscriptPresentationPolicy.controlMessageKind("The user discussed a cancelled task"))
  }

  func testAgentTranscriptRenderPolicyMatchesAndroidDiffRules() {
    let previous = transcriptEntry("process-1", text: "Accepted")
    let current = transcriptEntry("process-1", text: "Running")
    let first = transcriptEntry("user-1", role: .user, text: "Run this")
    let second = transcriptEntry("process-2", text: "Processing")
    let assistantPrevious = transcriptEntry("assistant-1", role: .assistant, text: "Done", richOutputJson: #"{"type":"text"}"#)
    let assistantCurrent = transcriptEntry("assistant-1", role: .assistant, text: "Done", richOutputJson: #"{"type":"table"}"#)

    let changed = AgentTranscriptRenderPolicy.diff(
      renderedIds: [previous.id],
      renderedSignatures: [previous.id: AgentTranscriptRenderPolicy.signature(previous)],
      incoming: [current]
    )
    let appended = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id],
      renderedSignatures: [first.id: AgentTranscriptRenderPolicy.signature(first)],
      incoming: [first, second]
    )
    let reset = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id, second.id],
      renderedSignatures: [
        first.id: AgentTranscriptRenderPolicy.signature(first),
        second.id: AgentTranscriptRenderPolicy.signature(second)
      ],
      incoming: [second]
    )
    let richChanged = AgentTranscriptRenderPolicy.diff(
      renderedIds: [assistantPrevious.id],
      renderedSignatures: [assistantPrevious.id: AgentTranscriptRenderPolicy.signature(assistantPrevious)],
      incoming: [assistantCurrent]
    )
    let assistantAppended = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id, second.id],
      renderedSignatures: [
        first.id: AgentTranscriptRenderPolicy.signature(first),
        second.id: AgentTranscriptRenderPolicy.signature(second)
      ],
      incoming: [first, second, transcriptEntry("assistant-2", role: .assistant, text: "Done")]
    )

    XCTAssertFalse(changed.reset)
    XCTAssertEqual(changed.replacementIndices, [0])
    XCTAssertEqual(changed.appendFromIndex, 1)
    XCTAssertFalse(appended.reset)
    XCTAssertTrue(appended.replacementIndices.isEmpty)
    XCTAssertEqual(appended.appendFromIndex, 1)
    XCTAssertTrue(reset.reset)
    XCTAssertTrue(reset.replacementIndices.isEmpty)
    XCTAssertEqual(reset.appendFromIndex, 0)
    XCTAssertEqual(richChanged.replacementIndices, [0])
    XCTAssertFalse(assistantAppended.reset)
    XCTAssertEqual(assistantAppended.replacementIndices, [1])
    XCTAssertEqual(assistantAppended.appendFromIndex, 2)
  }

  func testAgentTaskLivenessPolicyWarnsBeforeHardTimeout() {
    let policy = agentLivenessPolicy()
    let workspace = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000)]
    )

    XCTAssertEqual(policy.evaluate(workspace: workspace, nowMillis: 1_099).state, .healthy)

    let stalled = policy.evaluate(workspace: workspace, nowMillis: 1_100)
    XCTAssertEqual(stalled.state, .stalled)
    XCTAssertEqual(stalled.reason, "running_progress_stalled")
    XCTAssertEqual(stalled.idleMillis, 100)

    let timedOut = policy.evaluate(workspace: workspace, nowMillis: 1_200)
    XCTAssertEqual(timedOut.state, .timedOut)
    XCTAssertEqual(timedOut.reason, "running_progress_timeout")
    XCTAssertEqual(timedOut.lifetimeMillis, 200)
  }

  func testAgentTaskLivenessPolicyClearsUnresolvedWarningAfterProgress() {
    let policy = agentLivenessPolicy()
    let stalled = agentWorkspace(
      status: .running,
      events: [
        agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000),
        agentWorkspaceEvent(2, AgentTaskEventKinds.stalled, 1_100)
      ]
    )
    let recovered = agentWorkspace(
      status: .running,
      events: stalled.eventJournal + [agentWorkspaceEvent(3, AgentTaskEventKinds.progress, 1_110)]
    )

    XCTAssertTrue(policy.hasUnresolvedStall(workspace: stalled))
    XCTAssertFalse(policy.hasUnresolvedStall(workspace: recovered))
    XCTAssertEqual(policy.evaluate(workspace: recovered, nowMillis: 1_150).state, .healthy)
    XCTAssertEqual(policy.meaningfulActivityAt(recovered), 1_110)
  }

  func testAgentTaskLivenessPolicyIgnoresUserControlledAndCancelledTasks() {
    let policy = agentLivenessPolicy()

    for status in [AgentWorkspaceStatus.waitingConfirmation, .paused, .blocked] {
      XCTAssertEqual(
        policy.evaluate(workspace: agentWorkspace(status: status), nowMillis: 10_000).state,
        .healthy,
        status.rawValue
      )
    }
    XCTAssertEqual(
      policy.evaluate(workspace: agentWorkspace(status: .running, cancellationRequested: true), nowMillis: 10_000).state,
      .healthy
    )
    XCTAssertEqual(
      policy.evaluate(workspace: agentWorkspace(status: .completed), nowMillis: 10_000).state,
      .healthy
    )
  }

  func testAgentTaskLivenessPolicyAppliesAbsoluteDeadlineAndVolatileActivity() {
    let policy = agentLivenessPolicy()
    let workspace = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.progress, 1_950)]
    )
    let active = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000)]
    )
    let longRunning = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.progress, 12 * 60 * 60_000 - 1_000)]
    )

    let decision = policy.evaluate(workspace: workspace, nowMillis: 2_000)
    let volatile = policy.evaluate(
      workspace: active,
      nowMillis: 1_150,
      volatileActivityAtMillis: 1_090
    )
    let defaultDecision = AgentTaskLivenessPolicy().evaluate(
      workspace: longRunning,
      nowMillis: 12 * 60 * 60_000
    )

    XCTAssertEqual(decision.state, .timedOut)
    XCTAssertEqual(decision.reason, "absolute_deadline_exceeded")
    XCTAssertEqual(volatile.state, .healthy)
    XCTAssertEqual(volatile.idleMillis, 60)
    XCTAssertEqual(defaultDecision.state, .healthy)
    XCTAssertGreaterThan(defaultDecision.lifetimeMillis, 2 * 60 * 60_000)
  }

  func testAgentTaskTerminalReplyPolicyMatchesAndroidDedupePrefixes() {
    let entries = [
      terminalReplyTranscript(role: .user, dedupeKey: "", turnId: "turn"),
      terminalReplyTranscript(role: .process, dedupeKey: "task-watchdog:turn", turnId: "turn"),
      terminalReplyTranscript(role: .assistant, dedupeKey: "result:plan:action:hash", turnId: "turn"),
      terminalReplyTranscript(
        role: .assistant,
        dedupeKey: "assistant-final:turn:other-turn",
        turnId: "other-turn",
        taskId: "turn"
      )
    ]
    let nonTerminal = [
      terminalReplyTranscript(role: .assistant, dedupeKey: "approval:plan:action", turnId: "turn"),
      terminalReplyTranscript(role: .assistant, dedupeKey: "task-watchdog-timeout:turn", turnId: "turn")
    ]

    XCTAssertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "turn"))
    XCTAssertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "other-turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "unrelated-turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: nonTerminal, turnId: "turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: " "))
  }

  func testAgentWorkspaceLivenessModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(
        #"""
        {
          "workspace_id": "workspace",
          "session_id": "session",
          "conversation_id": "conversation",
          "task_id": "task",
          "goal": "Run task",
          "status": "WAITING_RESPONSE",
          "event_sequence": 2,
          "event_journal": [
            {
              "sequence": 2,
              "kind": "task.progress",
              "message": "still running",
              "payload_json": "{\"step\":1}",
              "timestamp_millis": 1234
            }
          ],
          "cancellation_requested": true,
          "created_at_millis": 1000,
          "updated_at_millis": 1234,
          "revision": 5
        }
        """#.utf8
      )
    )
    let fallback = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(#"{"workspace_id":"w","session_id":"s","conversation_id":"c","task_id":"t","status":"FUTURE"}"#.utf8)
    )
    let encodedSignal = String(
      decoding: try JSONEncoder().encode(
        AgentTaskLivenessSignal(
          kind: .timedOut,
          workspace: decoded,
          reason: "running_progress_timeout",
          observedAtMillis: 2_000
        )
      ),
      as: UTF8.self
    )
    let encodedPolicy = String(decoding: try JSONEncoder().encode(AgentTaskLivenessPolicy()), as: UTF8.self)

    XCTAssertEqual(decoded.status, .waitingResponse)
    XCTAssertEqual(decoded.key, AgentWorkspaceKey(workspaceId: "workspace", sessionId: "session", conversationId: "conversation", taskId: "task"))
    XCTAssertEqual(decoded.eventJournal.first?.payloadJson, #"{"step":1}"#)
    XCTAssertTrue(decoded.cancellationRequested)
    XCTAssertEqual(fallback.status, .created)
    XCTAssertTrue(AgentWorkspaceStatus.completed.isTerminal)
    XCTAssertFalse(AgentWorkspaceStatus.running.isTerminal)
    XCTAssertTrue(encodedSignal.contains(#""observed_at_millis":2000"#))
    XCTAssertTrue(encodedSignal.contains(#""event_journal":["#))
    XCTAssertTrue(encodedPolicy.contains(#""queued_warning_millis":15000"#))
    XCTAssertTrue(encodedPolicy.contains(#""heartbeat_write_throttle_millis":2000"#))
  }

  func testAgentWorkspaceFileModelsUseAndroidWireNames() throws {
    let policy = AgentWorkspaceFilePolicy(maxTextReadBytes: -1, maxZipCompressionRatio: 0)
    let encodedPolicy = String(decoding: try JSONEncoder().encode(policy), as: UTF8.self)
    let decodedMutation = try JSONDecoder().decode(
      AgentWorkspaceMutation.self,
      from: Data(
        #"""
        {
          "kind": "MOVE",
          "path": "docs/new.txt",
          "source_path": "docs/old.txt",
          "affected_entries": 1,
          "affected_bytes": 12,
          "metadata": {
            "path": "docs/new.txt",
            "type": "FILE",
            "size_bytes": 12,
            "last_modified_millis": 123
          }
        }
        """#.utf8
      )
    )
    let zipEntry = AgentWorkspaceZipEntryMetadata(
      path: "docs/a.txt",
      directory: false,
      compressedBytes: 3,
      uncompressedBytes: 9,
      compressionRatio: 3,
      crc32: 42,
      lastModifiedMillis: 100
    )
    let encodedZip = String(
      decoding: try JSONEncoder().encode(
        AgentWorkspaceZipListing(
          archivePath: "bundle.zip",
          archiveBytes: 100,
          totalCompressedBytes: 3,
          totalUncompressedBytes: 9,
          entries: [zipEntry]
        )
      ),
      as: UTF8.self
    )

    XCTAssertEqual(policy.maxTextReadBytes, 1)
    XCTAssertEqual(policy.maxZipCompressionRatio, 1)
    XCTAssertTrue(encodedPolicy.contains(#""max_text_read_bytes":1"#))
    XCTAssertTrue(encodedPolicy.contains(#""max_zip_entry_name_characters":512"#))
    XCTAssertEqual(decodedMutation.kind, .move)
    XCTAssertEqual(decodedMutation.sourcePath, "docs/old.txt")
    XCTAssertEqual(decodedMutation.metadata?.type, .file)
    XCTAssertEqual(AgentWorkspaceFileErrorCode.fromWireValue("path_escape"), .pathEscape)
    XCTAssertEqual(AgentWorkspaceMutationKind.fromWireValue("mkdir"), .mkdir)
    XCTAssertEqual(AgentWorkspaceEntryType.fromWireValue("directory"), .directory)
    XCTAssertTrue(encodedZip.contains(#""archive_path":"bundle.zip""#))
    XCTAssertTrue(encodedZip.contains(#""total_uncompressed_bytes":9"#))
    XCTAssertTrue(encodedZip.contains(#""compression_ratio":3"#))
  }

  func testAgentWorkspaceFilePathPolicyRejectsEscapesAndNormalizesPortablePaths() {
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.workspaceDirectoryName("alpha_1.2-3").value, "alpha_1.2-3")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.workspaceDirectoryName("../alpha").error?.code, .invalidWorkspace)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs/./nested//note.txt").value, ["docs", "nested", "note.txt"])
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs\\note.txt").value, ["docs", "note.txt"])
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("../escape.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("docs/../escape.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("/absolute.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("C:\\absolute.txt").error?.code, .pathEscape)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("contains\u{0000}null").error?.code, .invalidPath)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeRelativePath("", allowRoot: false).error?.code, .invalidPath)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.displayPath("docs\\note.txt"), "docs/note.txt")
  }

  func testAgentWorkspaceFileArchivePolicyRejectsZipSlipAndAbsoluteEntries() {
    let policy = AgentWorkspaceFilePolicy(maxZipEntryNameCharacters: 12)

    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("docs\\a.txt").value, "docs/a.txt")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("docs/a.txt/").value, "docs/a.txt")
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("../escaped.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("/absolute.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("C:\\absolute.txt").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("/").error?.code, .invalidArchive)
    XCTAssertEqual(AgentWorkspaceFilePathPolicy.normalizeArchiveEntry("very-long-entry-name.txt", policy: policy).error?.code, .invalidArchive)
  }

  func testAgentWorkspacePatchPolicyMatchesAndroidDiffAndReplacementRules() {
    let before = "one\ntwo\nthree\n"
    let after = AgentWorkspacePatchPolicy.replaceOccurrences(text: before, expected: "two", replacement: "TWO")
    let diff = AgentWorkspacePatchPolicy.summarizeDiff(before: before, after: after)
    let unchanged = AgentWorkspacePatchPolicy.summarizeDiff(before: after, after: after)
    let inserted = AgentWorkspacePatchPolicy.summarizeDiff(before: "one\nthree", after: "one\ntwo\nthree")

    XCTAssertEqual(AgentWorkspacePatchPolicy.countOccurrences(text: before, expected: "two"), 1)
    XCTAssertEqual(AgentWorkspacePatchPolicy.countOccurrences(text: "aaaa", expected: "aa"), 2)
    XCTAssertEqual(after, "one\nTWO\nthree\n")
    XCTAssertEqual(diff.beforeSha256, agentReputationSha256(Data(before.utf8)))
    XCTAssertEqual(diff.afterSha256, agentReputationSha256(Data(after.utf8)))
    XCTAssertEqual(diff.firstChangedLine, 2)
    XCTAssertEqual(diff.changedLinePairs, 1)
    XCTAssertEqual(diff.addedLines, 0)
    XCTAssertEqual(diff.deletedLines, 0)
    XCTAssertNil(unchanged.firstChangedLine)
    XCTAssertEqual(inserted.firstChangedLine, 2)
    XCTAssertEqual(inserted.addedLines, 1)
    XCTAssertEqual(inserted.deletedLines, 0)
  }

  func testAgentFastLocalResponseAnswersBoundedBinaryArithmeticLocally() {
    let context = AgentConversationContext(conversationId: "test", summary: "", turns: [], privateMode: false)

    XCTAssertEqual(
      AgentFastLocalResponse.reply(goal: "\u{53ea}\u{7ed9}\u{51fa} 37 + 58 \u{7684}\u{7ed3}\u{679c}\u{3002}", context: context),
      "95"
    )
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "12 / 2", context: context), "6")
    XCTAssertEqual(AgentFastLocalResponse.reply(goal: "Calculate 3 x -7", context: context), "-21")
    XCTAssertNil(
      AgentFastLocalResponse.reply(goal: "Explain why 37 + 58 is useful in this example", context: context)
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Calculate 1 / 0", context: context))
  }

  func testAgentFastLocalResponseAsksOneQuestionForObjectlessNewConversationRequest() {
    let goal = "\u{5e2e}\u{6211}\u{5904}\u{7406}\u{4e00}\u{4e0b}\u{3002}"
    let contextAfterUserAppend = AgentConversationContext(
      conversationId: "test",
      summary: "",
      turns: [AgentTranscriptEntry(id: "current", role: .user, text: goal, timestampMillis: 1)],
      privateMode: false
    )
    let response = AgentFastLocalResponse.reply(goal: goal, context: contextAfterUserAppend)

    XCTAssertEqual(
      response,
      "\u{4f60}\u{60f3}\u{8ba9}\u{6211}\u{5904}\u{7406}\u{4ec0}\u{4e48}\u{ff1f}\u{53ef}\u{4ee5}\u{53d1}\u{6587}\u{5b57}\u{3001}\u{6587}\u{4ef6}\u{6216}\u{56fe}\u{7247}\u{ff0c}\u{6216}\u{76f4}\u{63a5}\u{8bf4}\u{8981}\u{6211}\u{67e5}\u{770b}\u{3001}\u{4fee}\u{6539}\u{3001}\u{603b}\u{7ed3}\u{8fd8}\u{662f}\u{6267}\u{884c}\u{3002}"
    )
  }

  func testAgentFastLocalResponsePreservesContextualFollowUpForTheModel() {
    let context = AgentConversationContext(
      conversationId: "test",
      summary: "",
      turns: [AgentTranscriptEntry(id: "1", role: .user, text: "Prior task", timestampMillis: 1)],
      privateMode: false
    )
    let summarizedContext = AgentConversationContext(
      conversationId: "test",
      summary: "The user asked for a report review.",
      turns: [],
      privateMode: false
    )

    XCTAssertNil(
      AgentFastLocalResponse.reply(goal: "\u{5e2e}\u{6211}\u{5904}\u{7406}\u{4e00}\u{4e0b}\u{3002}", context: context)
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Handle this", context: summarizedContext))
  }

  func testAgentFastLocalResponseRequestsDocumentAuthorizationForRawSharedStoragePaths() {
    let context = AgentConversationContext(conversationId: "test", summary: "", turns: [], privateMode: false)
    let chinese = AgentFastLocalResponse.reply(
      goal: "\u{8bfb}\u{53d6} /storage/emulated/0/Download/report.txt \u{5e76}\u{544a}\u{8bc9}\u{6211}\u{7ed3}\u{679c}\u{3002}",
      context: context
    )

    XCTAssertTrue(chinese?.contains("Android \u{4e0d}\u{5141}\u{8bb8} App") == true)
    XCTAssertTrue(chinese?.contains("\u{91cd}\u{65b0}\u{9009}\u{62e9}\u{8be5}\u{6587}\u{4ef6}") == true)
    XCTAssertEqual(
      AgentFastLocalResponse.reply(goal: "Read /sdcard/Download/report.txt", context: context),
      "Android does not let apps read this raw shared-storage path directly. Select the file again with the input bar's file button; after you grant access, I will process it directly."
    )
    XCTAssertNil(AgentFastLocalResponse.reply(goal: "Save the result to /sdcard/Download/report.txt", context: context))
  }

  func testAgentConversationContextUsesAndroidWireNamesAndGlobalContextRules() throws {
    let context = AgentConversationContext(
      conversationId: "conversation-a",
      summary: "Earlier summary",
      turns: [AgentTranscriptEntry(id: "1", role: .assistant, text: "Done", timestampMillis: 2)],
      privateMode: true,
      globalContext: "Global note",
      trackingPaused: true
    )
    let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)

    XCTAssertFalse(context.allowsGlobalContext)
    XCTAssertTrue(encoded.contains(#""conversation_id":"conversation-a""#))
    XCTAssertTrue(encoded.contains(#""private_mode":true"#))
    XCTAssertTrue(encoded.contains(#""global_context":"Global note""#))
    XCTAssertTrue(encoded.contains(#""tracking_paused":true"#))
  }

  func testAgentConversationContextTransportKeepsAttachmentReferenceWithoutPrivateBytes() throws {
    let richOutput = """
    {"version":1,"blocks":[{"id":"image-1","type":"image","title":"homework.jpg","uri":"content://signalasi/private/homework.jpg","data_b64":"private-image-bytes","mime_type":"image/jpeg","metadata":{"size_bytes":"245760"}}]}
    """
    let context = AgentConversationContext(
      conversationId: "conversation-1",
      summary: "",
      turns: [
        AgentTranscriptEntry(
          id: "entry-1",
          role: .user,
          text: "Please review this",
          timestampMillis: 1,
          dedupeKey: "",
          conversationId: "conversation-1",
          turnId: "turn-1",
          taskId: "turn-1",
          richOutputJson: richOutput
        )
      ],
      privateMode: false
    )

    let transport = context.asTransportBlock()
    let json = transport
      .replacingOccurrences(of: "\(AgentConversationContext.transportHeader)\n", with: "")
      .replacingOccurrences(of: "\n\(AgentConversationContext.transportFooter)", with: "")
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let attachmentIndex = try XCTUnwrap(payload["attachment_index"] as? [[String: Any]])
    let turns = try XCTUnwrap(payload["turns"] as? [[String: Any]])
    let turnAttachments = try XCTUnwrap(turns.first?["attachments"] as? [[String: Any]])

    XCTAssertTrue(context.hasAttachments)
    XCTAssertTrue(context.asPromptBlock().contains("Attachments: homework.jpg (image/jpeg)"))
    XCTAssertEqual(attachmentIndex.first?["name"] as? String, "homework.jpg")
    XCTAssertEqual(attachmentIndex.first?["mime_type"] as? String, "image/jpeg")
    XCTAssertEqual((attachmentIndex.first?["size_bytes"] as? NSNumber)?.intValue, 245_760)
    XCTAssertEqual(attachmentIndex.first?["turn_id"] as? String, "turn-1")
    XCTAssertEqual(turnAttachments.first?["artifact_id"] as? String, "image-1")
    XCTAssertFalse(transport.contains("content://signalasi/private"))
    XCTAssertFalse(transport.contains("private-image-bytes"))
    XCTAssertFalse(transport.contains("data_b64"))
  }

  func testAgentConversationMergePolicyMergesDialogueOnceAndArchivesChild() {
    let parent = agentConversation(id: "parent", title: "Main topic", summary: "Parent summary")
    let child = agentConversation(
      id: "child",
      title: "Agent research",
      summary: "Runtime is ready",
      createdByAgent: true,
      parentConversationId: parent.id,
      inputTokens: 20,
      outputTokens: 30
    )
    let entries = [
      agentMergeEntry(id: "user", role: .user, conversationId: child.id, text: "Investigate the runtime"),
      agentMergeEntry(id: "process", role: .process, conversationId: child.id, text: "Ran a tool"),
      agentMergeEntry(
        id: "assistant",
        role: .assistant,
        conversationId: child.id,
        text: "The runtime is ready",
        richOutputJson: #"{"version":1,"blocks":[{"id":"result","type":"markdown","text":"ready"}]}"#
      )
    ]

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: entries,
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertTrue(mutation.result.merged)
    XCTAssertEqual(mutation.result.copiedEntryCount, 2)
    XCTAssertEqual(mutation.result.skippedEntryCount, 0)
    let copied = mutation.entries.filter { $0.conversationId == parent.id }
    XCTAssertEqual(copied.map(\.role), [.user, .assistant])
    XCTAssertTrue(copied.allSatisfy { $0.sourceConversationId == child.id })
    XCTAssertTrue(copied.allSatisfy { $0.sourceConversationTitle == child.title })
    XCTAssertEqual(copied.last?.richOutputJson, entries.last?.richOutputJson)
    XCTAssertTrue(copied.allSatisfy { $0.dedupeKey.hasPrefix("merged:child:") })

    let mergedChild = mutation.conversations.first { $0.id == child.id }
    XCTAssertEqual(mergedChild?.status, .archived)
    XCTAssertEqual(mergedChild?.trackingPaused, true)
    XCTAssertEqual(mergedChild?.mergedIntoConversationId, parent.id)
    XCTAssertEqual(mergedChild?.mergedAtMillis, 1_000)
    XCTAssertEqual(mutation.result.targetConversation?.status, .active)
    XCTAssertEqual(mutation.result.targetConversation?.inputTokens, 20)
    XCTAssertEqual(mutation.result.targetConversation?.outputTokens, 30)
    XCTAssertTrue(mutation.result.targetConversation?.summary.contains("Merged topic Agent research:") == true)

    let repeated = AgentConversationMergePolicy.mergeIntoParent(
      conversations: mutation.conversations,
      entries: mutation.entries,
      sourceConversationId: child.id,
      nowMillis: 2_000
    )
    XCTAssertFalse(repeated.result.merged)
    XCTAssertEqual(repeated.result.failure, .alreadyMerged)
  }

  func testAgentConversationMergePolicyRefusesPrivacyMismatch() {
    let parent = agentConversation(id: "parent", title: "Main topic")
    let child = agentConversation(
      id: "child",
      title: "Private research",
      createdByAgent: true,
      parentConversationId: parent.id,
      privateMode: true
    )

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: [],
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertFalse(mutation.result.merged)
    XCTAssertEqual(mutation.result.failure, .privacyMismatch)
    XCTAssertEqual(mutation.conversations, [parent, child])
  }

  func testAgentConversationMergePolicySkipsGlobalDeliveryDuplicates() {
    let parent = agentConversation(id: "parent", title: "Main topic")
    let child = agentConversation(
      id: "child",
      title: "Agent research",
      createdByAgent: true,
      parentConversationId: parent.id
    )
    let parentInsight = agentMergeEntry(
      id: "parent-insight",
      role: .assistant,
      conversationId: parent.id,
      text: "Shared result",
      dedupeKey: "global-agent:insight"
    )
    let childInsight = agentMergeEntry(
      id: "child-insight",
      role: .assistant,
      conversationId: child.id,
      text: "Shared result",
      dedupeKey: "global-agent:insight"
    )

    let mutation = AgentConversationMergePolicy.mergeIntoParent(
      conversations: [parent, child],
      entries: [parentInsight, childInsight],
      sourceConversationId: child.id,
      nowMillis: 1_000
    )

    XCTAssertTrue(mutation.result.merged)
    XCTAssertEqual(mutation.result.copiedEntryCount, 0)
    XCTAssertEqual(mutation.result.skippedEntryCount, 1)
    XCTAssertEqual(
      mutation.entries.filter { $0.conversationId == parent.id && $0.dedupeKey == "global-agent:insight" }.count,
      1
    )
  }

  func testAgentFinalResponseIdentityCoalescesCanonicalDuplicates() {
    let canonical = finalTranscriptEntry(
      id: "canonical",
      turnId: "turn-1",
      taskId: "task-1",
      dedupeKey: "assistant-final:turn:turn-1",
      timestampMillis: 1
    )
    let lateDuplicate = finalTranscriptEntry(
      id: "late",
      turnId: "",
      taskId: " task-1 ",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 2
    )
    let userEntry = finalTranscriptEntry(
      id: "user",
      role: .user,
      taskId: "task-1",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 3
    )
    let otherTask = finalTranscriptEntry(
      id: "other",
      taskId: "task-2",
      dedupeKey: "assistant-final:task:task-2",
      timestampMillis: 4
    )

    XCTAssertEqual(
      AgentFinalResponseIdentity.coalesce([canonical, lateDuplicate, userEntry, otherTask]),
      [canonical, userEntry, otherTask]
    )
  }

  func testAgentFinalResponseIdentityPrefersRichOutputThenLatestTimestamp() {
    let plain = finalTranscriptEntry(
      id: "plain",
      taskId: "task-1",
      dedupeKey: "assistant-final:source:101",
      timestampMillis: 3
    )
    let rich = finalTranscriptEntry(
      id: "rich",
      taskId: "task-1",
      dedupeKey: "assistant-final:task:task-1",
      timestampMillis: 1,
      richOutputJson: #"{"type":"markdown"}"#
    )
    let latest = finalTranscriptEntry(
      id: "latest",
      taskId: "task-2",
      dedupeKey: "assistant-final:source:202",
      timestampMillis: 4
    )
    let earlier = finalTranscriptEntry(
      id: "earlier",
      taskId: "task-2",
      dedupeKey: "assistant-final:task:task-2",
      timestampMillis: 2
    )

    XCTAssertEqual(
      AgentFinalResponseIdentity.coalesce([plain, rich, latest, earlier]),
      [rich, latest]
    )
  }

  func testAgentInlineMarkdownParsesBoldCodeAndLinksWithoutMarkers() {
    let segments = AgentInlineMarkdown.parse(
      "Today is **cloudy**. Run `status` and open [Shanghai Weather](https://sh.cma.gov.cn/)."
    )

    XCTAssertEqual(
      segments.map(\.text).joined(),
      "Today is cloudy. Run status and open Shanghai Weather."
    )
    XCTAssertEqual(segments.first { $0.text == "cloudy" }?.style, .bold)
    XCTAssertEqual(segments.first { $0.text == "status" }?.style, .code)
    XCTAssertEqual(
      segments.first { $0.text == "Shanghai Weather" }?.url,
      "https://sh.cma.gov.cn/"
    )
  }

  func testAgentInlineMarkdownParsesItalicAndStrikeWithoutAffectingBold() {
    let segments = AgentInlineMarkdown.parse("Use *care* and remove ~~noise~~ while **keeping this**.")

    XCTAssertEqual(segments.first { $0.text == "care" }?.style, .italic)
    XCTAssertEqual(segments.first { $0.text == "noise" }?.style, .strike)
    XCTAssertEqual(segments.first { $0.text == "keeping this" }?.style, .bold)
  }

  func testAgentTaskIdentityPolicyGeneratesStableAndroidIds() {
    let conversationId = AgentTaskIdentityPolicy.conversationId(contactId: "codex", requested: "")
    let turnId = AgentTaskIdentityPolicy.turnId(sourceMessageId: 42, requested: "")
    let first = AgentTaskIdentityPolicy.taskId(
      ownerId: "signalasi:phone",
      contactId: "codex",
      sourceMessageId: 42,
      conversationId: conversationId,
      turnId: turnId
    )
    let second = AgentTaskIdentityPolicy.taskId(
      ownerId: "signalasi:phone",
      contactId: "codex",
      sourceMessageId: 42,
      conversationId: conversationId,
      turnId: turnId
    )

    XCTAssertEqual(conversationId, "contact:codex")
    XCTAssertEqual(turnId, "message:42")
    XCTAssertEqual(first, second)
    XCTAssertEqual(first, "89d82315-14f3-3f6a-8e5f-4cb48680373d")
    XCTAssertEqual(
      AgentTaskIdentityPolicy.conversationId(contactId: "codex", requested: " conversation-a "),
      "conversation-a"
    )
    XCTAssertEqual(
      AgentTaskIdentityPolicy.turnId(sourceMessageId: nil, requested: "") {
        UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
      },
      "11111111-2222-3333-4444-555555555555"
    )
  }

  func testAgentTaskIdentityPolicyMatchesDesktopResponseIdentity() {
    let expected = [
      "resource_location": "desktop",
      "conversation_id": "conversation-a",
      "remote_task_id": "task-a",
      "turn_id": "turn-a"
    ]

    XCTAssertTrue(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "task-a",
        turnId: "turn-a"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-b",
        taskId: "task-a",
        turnId: "turn-a"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "task-a",
        turnId: "turn-b"
      )
    )
    XCTAssertFalse(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: expected,
        conversationId: "conversation-a",
        taskId: "",
        turnId: "turn-a"
      )
    )
    XCTAssertTrue(
      AgentTaskIdentityPolicy.matchesDesktopResponse(
        expected: ["resource_location": "cloud"],
        conversationId: "",
        taskId: "",
        turnId: ""
      )
    )
  }

  func testAgentTaskIdentityCompletenessAndWireNames() throws {
    let identity = AgentTaskIdentity(
      clientRouteId: "route-1",
      conversationId: "conversation-a",
      taskId: "task-a",
      turnId: "turn-a"
    )
    XCTAssertTrue(identity.isComplete)
    XCTAssertFalse(
      AgentTaskIdentity(
        clientRouteId: "route-1",
        conversationId: "conversation-a",
        taskId: "",
        turnId: "turn-a"
      ).isComplete
    )

    let encoded = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
    XCTAssertTrue(encoded.contains(#""client_route_id":"route-1""#))
    XCTAssertTrue(encoded.contains(#""conversation_id":"conversation-a""#))
    XCTAssertTrue(encoded.contains(#""task_id":"task-a""#))
    XCTAssertTrue(encoded.contains(#""turn_id":"turn-a""#))

    let decoded = try JSONDecoder().decode(
      AgentTaskIdentity.self,
      from: Data(
        #"""
        {
          "client_route_id": "route-2",
          "conversation_id": "conversation-b",
          "task_id": "task-b",
          "turn_id": "turn-b"
        }
        """#.utf8
      )
    )
    XCTAssertEqual(decoded.clientRouteId, "route-2")
    XCTAssertTrue(decoded.isComplete)
  }

  func testAgentTaskIntentClassifierMatchesAndroidCanonicalIntents() {
    let cases: [(String, AgentTaskIntent)] = [
      ("Hello, how are you?", .chat),
      ("Build an Android app and run unit tests", .code),
      ("Turn on the flashlight on my phone", .phoneControl),
      ("Open the browser on my computer", .desktopControl),
      ("Research today's AI news and cite sources", .research),
      ("Extract text from this PDF", .file),
      ("Remember that I prefer concise replies", .memory),
      ("Run this health check every hour", .automation)
    ]

    for (goal, expected) in cases {
      let result = AgentTaskIntentClassifier.classify(goal: goal)

      XCTAssertEqual(result.intent, expected, goal)
      XCTAssertGreaterThanOrEqual(result.confidence, 55, goal)
    }
  }

  func testAgentTaskIntentClassifierHandlesAttachmentsAndChineseSignals() {
    let attachment = AgentTaskIntentClassifier.classify(goal: "", hasAttachments: true)
    XCTAssertEqual(attachment.intent, .file)
    XCTAssertTrue(attachment.matchedSignals.contains("attachment"))

    let cases: [(String, AgentTaskIntent)] = [
      ("\u{4f60}\u{597d}", .chat),
      ("\u{7f16}\u{8bd1}\u{8fd9}\u{4e2a}\u{9879}\u{76ee}", .code),
      ("\u{6253}\u{5f00}\u{624b}\u{673a}\u{624b}\u{7535}\u{7b52}", .phoneControl),
      ("\u{63a7}\u{5236}\u{7535}\u{8111}\u{6253}\u{5f00}\u{6d4f}\u{89c8}\u{5668}", .desktopControl),
      ("\u{641c}\u{7d22}\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}", .research),
      ("\u{63d0}\u{53d6}\u{8fd9}\u{4e2a} PDF \u{6587}\u{4ef6}\u{7684}\u{6587}\u{5b57}", .file),
      ("\u{8bb0}\u{4f4f}\u{6211}\u{7684}\u{504f}\u{597d}", .memory),
      ("\u{6bcf}\u{5929}\u{76d1}\u{63a7}\u{8fd9}\u{4e2a}\u{670d}\u{52a1}", .automation)
    ]

    for (goal, expected) in cases {
      XCTAssertEqual(AgentTaskIntentClassifier.classify(goal: goal).intent, expected, goal)
    }
  }

  func testAgentTaskIntentClassifierPrioritizesAutomationAndAvoidsGenericPhoneControl() {
    let automation = AgentTaskIntentClassifier.classify(
      goal: "Turn on the phone flashlight every day at 8"
    )
    let generic = AgentTaskIntentClassifier.classify(
      goal: "Open the app and show me its status"
    )

    XCTAssertEqual(automation.intent, .automation)
    XCTAssertEqual(generic.intent, .chat)
  }

  func testAgentExecutionProfileMatchesAndroidTaskKindsAndTimeouts() {
    let chat = AgentExecutionProfile.forGoal("Hello there")
    let device = AgentExecutionProfile.forGoal("Turn on the flashlight")
    let research = AgentExecutionProfile.forGoal("Research today's AI news")
    let artifact = AgentExecutionProfile.forGoal("Summarize this PDF", hasAttachments: true)
    let build = AgentExecutionProfile.forGoal("Build an Android app and run tests")
    let install = AgentExecutionProfile.forGoal("Install APK on the phone")

    XCTAssertEqual(chat.taskKind, .chat)
    XCTAssertEqual(chat.reasoningEffort, .low)
    XCTAssertEqual(chat.noProgressTimeoutMillis, 180_000)
    XCTAssertFalse(chat.requiresArtifact)

    XCTAssertEqual(device.taskKind, .device)
    XCTAssertEqual(device.reasoningEffort, .low)
    XCTAssertEqual(device.noProgressTimeoutMillis, 120_000)

    XCTAssertEqual(research.taskKind, .research)
    XCTAssertEqual(research.reasoningEffort, .medium)
    XCTAssertEqual(research.noProgressTimeoutMillis, 300_000)

    XCTAssertEqual(artifact.taskKind, .artifact)
    XCTAssertEqual(artifact.noProgressTimeoutMillis, 360_000)
    XCTAssertTrue(artifact.requiresArtifact)
    XCTAssertEqual(artifact.taskIntent, .file)
    XCTAssertTrue(artifact.taskIntentSignals.contains("attachment"))

    XCTAssertEqual(build.taskKind, .build)
    XCTAssertEqual(build.noProgressTimeoutMillis, 420_000)
    XCTAssertTrue(build.requiresArtifact)
    XCTAssertEqual(build.targetPlatform, "android")
    XCTAssertEqual(build.taskIntent, .code)

    XCTAssertEqual(install.taskKind, .install)
    XCTAssertEqual(install.reasoningEffort, .medium)
    XCTAssertEqual(install.noProgressTimeoutMillis, 420_000)
    XCTAssertTrue(install.requiresArtifact)
    XCTAssertTrue(install.verifyInstallation)
    XCTAssertEqual(install.targetPlatform, "android")
  }

  func testAgentExecutionProfileContractAndWireNamesMatchAndroid() throws {
    let profile = AgentExecutionProfile.forGoal("Install APK on the phone")

    XCTAssertTrue(profile.contract.contains("task=install"))
    XCTAssertTrue(profile.contract.contains("reasoning_effort=medium"))
    XCTAssertTrue(profile.contract.contains("A single deliverable remains in its native format"))
    XCTAssertTrue(profile.contract.contains("Android returns a verified execution receipt"))
    XCTAssertTrue(profile.contract.contains("Do not report success without verification evidence."))

    let encoded = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(object["task_kind"] as? String, "INSTALL")
    XCTAssertEqual(object["reasoning_effort"] as? String, "MEDIUM")
    XCTAssertEqual(object["no_progress_timeout_millis"] as? Int, 420_000)
    XCTAssertEqual(object["max_same_failure_attempts"] as? Int, 2)
    XCTAssertEqual(object["requires_artifact"] as? Bool, true)
    XCTAssertEqual(object["target_platform"] as? String, "android")
    XCTAssertEqual(object["verify_installation"] as? Bool, true)
    XCTAssertEqual(object["task_intent"] as? String, "CODE")
    XCTAssertGreaterThanOrEqual(object["task_intent_confidence"] as? Int ?? 0, 55)
  }

  func testAgentRuntimePackCatalogSigningPayloadCodecAndWireNamesMatchAndroid() throws {
    let now: Int64 = 1_750_000_000_000
    let first = runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    let second = runtimeCatalogEntry(
      packId: "python-uv",
      architecture: "arm64-v8a",
      dependencies: ["linux-base"]
    )
    let forward = runtimeCatalog(now: now, entries: [first, second])
    let reversed = runtimeCatalog(now: now, entries: [second, first])

    XCTAssertEqual(forward.signingPayload(), reversed.signingPayload())
    XCTAssertFalse(first.canonicalValue().contains("|"))

    let encoded = try JSONEncoder().encode(forward)
    let decoded = try JSONDecoder().decode(AgentRuntimePackCatalog.self, from: encoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])

    XCTAssertEqual(decoded, forward)
    XCTAssertEqual(object["format_version"] as? Int, 1)
    XCTAssertEqual(object["catalog_version"] as? String, "1.0.0")
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(entries.first?["pack_id"] as? String, "linux-base")
    XCTAssertEqual(entries.first?["archive_sha256"] as? String, String(repeating: "b", count: 64))
    XCTAssertEqual((entries.first?["archive_size_bytes"] as? NSNumber)?.int64Value, Int64(1_024))

    let manifest = AgentRuntimePackManifest(
      id: "python-uv",
      version: "1.0.0",
      architecture: "arm64-v8a",
      imageFile: "python.img",
      imageSha256: String(repeating: "c", count: 64),
      capabilities: ["uv.sync", "python.execute"],
      dependencies: ["linux-base"],
      installedSizeBytes: 2_048,
      license: "Apache-2.0",
      signatureKeyId: String(repeating: "d", count: 64),
      signature: "signed",
      archiveSizeBytes: 1_024
    )
    let status = AgentRuntimePackStatus(id: "python-uv", state: .ready, manifest: manifest)
    let install = AgentRuntimePackInstallResult(
      packId: "python-uv",
      version: "1.0.0",
      state: .ready,
      installedBytes: 2_048,
      replacedExisting: true
    )
    let progress = AgentRuntimePackInstallProgress(stage: .verifying, processedBytes: 128, totalBytes: 256)
    let installObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(install)) as? [String: Any]
    )

    XCTAssertFalse(manifest.signingPayload().isEmpty)
    XCTAssertEqual(status.manifest, Optional(manifest))
    XCTAssertEqual(installObject["pack_id"] as? String, "python-uv")
    XCTAssertEqual((installObject["installed_bytes"] as? NSNumber)?.int64Value, Int64(2_048))
    XCTAssertEqual(installObject["replaced_existing"] as? Bool, true)
    XCTAssertEqual(installObject["state"] as? String, "ready")
    XCTAssertEqual(progress.stage.rawValue, "VERIFYING")
    XCTAssertEqual(AgentRuntimePackState.fromWireValue("NOT-INSTALLED"), .notInstalled)
    XCTAssertEqual(AgentRuntimeLanguage.typescript.requiredPack, "node-js")
    XCTAssertTrue(AgentRuntimePackCatalogPolicy.requiredPacks.contains("browser-automation"))
    XCTAssertEqual(
      AgentRuntimePackCatalogPolicy.requiredPackCapabilities["ffmpeg"] ?? [],
      Set(["ffmpeg.execute", "ffprobe.inspect"])
    )
  }

  func testAgentRuntimePackCatalogPolicyRejectsDuplicateInsecureExpiredAndUntrustedCatalogs() throws {
    let now: Int64 = 1_750_000_000_000
    let valid = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    ])
    let trusted: (AgentRuntimePackCatalog) -> Bool = { _ in true }

    XCTAssertEqual(try AgentRuntimePackCatalogPolicy.validate(valid, nowMillis: now, verifier: trusted), valid)

    var duplicate = valid
    duplicate.entries = [
      valid.entries[0],
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a").with(version: "1.0.1")
    ]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(duplicate, nowMillis: now, verifier: trusted))

    var insecure = valid
    insecure.entries = [valid.entries[0].with(downloadUrl: "http://example.com/runtime.sarpack")]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(insecure, nowMillis: now, verifier: trusted))

    var expired = valid
    expired.expiresAtMillis = now - 1
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(expired, nowMillis: now, verifier: trusted))

    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(valid, nowMillis: now, verifier: { _ in false }))

    let missingDependency = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "python-uv", architecture: "arm64-v8a", dependencies: ["linux-base"])
    ])
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(missingDependency, nowMillis: now, verifier: trusted))

    let dependencyCycle = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a", dependencies: ["python-uv"]),
      runtimeCatalogEntry(packId: "python-uv", architecture: "arm64-v8a", dependencies: ["linux-base"])
    ])
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validate(dependencyCycle, nowMillis: now, verifier: trusted))
  }

  func testAgentRuntimePackCatalogPolicyChecksReplacementAndCompatibility() throws {
    let now: Int64 = 1_750_000_000_000
    let previous = runtimeCatalog(now: now, entries: [
      runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    ])

    var rollback = previous
    rollback.generatedAtMillis = previous.generatedAtMillis - 1
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: rollback))

    var reusedGeneration = previous
    reusedGeneration.entries = [previous.entries[0].with(version: "1.0.1")]
    XCTAssertThrowsError(try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: reusedGeneration))

    try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: previous)
    var newer = previous
    newer.generatedAtMillis = previous.generatedAtMillis + 1
    try AgentRuntimePackCatalogPolicy.validateReplacement(previous: previous, candidate: newer)

    let compatible = runtimeCatalogEntry(packId: "linux-base", architecture: "arm64-v8a")
    let wrongArchitecture = runtimeCatalogEntry(packId: "python-uv", architecture: "x86_64")
    let futureHost = runtimeCatalogEntry(packId: "node-js", architecture: "arm64-v8a")
      .with(minimumHostVersionCode: 99)
    let wrongGuest = runtimeCatalogEntry(packId: "go", architecture: "arm64-v8a")
      .with(guestApiVersion: AgentRuntimeGuestProtocol.version + 1)
    let catalog = runtimeCatalog(now: now, entries: [compatible, wrongArchitecture, futureHost, wrongGuest])

    XCTAssertEqual(
      AgentRuntimePackCatalogPolicy.compatibleEntries(
        in: catalog,
        supportedArchitectures: ["arm64-v8a"],
        hostVersionCode: 1
      ),
      [compatible]
    )
  }

  func testAgentRuntimeDistributionSourcesMatchAndroidAcceleratorPolicy() {
    let official = AgentRuntimeDistributionSources.githubCatalogURL

    XCTAssertEqual(AgentRuntimeDistributionSources.catalogCandidates(languageTag: "en-US"), [official])

    let chinese = AgentRuntimeDistributionSources.catalogCandidates(languageTag: "zh-CN")
    XCTAssertEqual(chinese.count, 4)
    XCTAssertEqual(chinese.last ?? "", official)
    XCTAssertTrue(chinese.prefix(3).allSatisfy { $0.hasSuffix(official) })
    XCTAssertEqual(
      AgentRuntimeDistributionSources.downloadCandidates(
        url: "https://downloads.example.com/tool.sarpack",
        languageTag: "zh-CN"
      ),
      ["https://downloads.example.com/tool.sarpack"]
    )
  }

  func testAgentEmbeddedRuntimeBundleCodecRequiresDefaultBootstrapEnvironment() throws {
    let bundle = try AgentEmbeddedRuntimeBundleCodec.decode(embeddedRuntimeIndexJson())
    let encoded = try JSONEncoder().encode(bundle)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let packs = try XCTUnwrap(object["packs"] as? [[String: Any]])

    XCTAssertEqual(bundle.architecture, "arm64-v8a")
    XCTAssertEqual(bundle.formatVersion, 1)
    XCTAssertEqual(bundle.packs.map(\.packId), ["linux-base", "python-uv"])
    XCTAssertEqual(bundle.packs.last?.dependencies, ["linux-base"])
    XCTAssertEqual(bundle.packs.first?.archiveSha256, String(repeating: "a", count: 64))
    XCTAssertEqual(object["format_version"] as? Int, 1)
    XCTAssertEqual(packs.first?["pack_id"] as? String, "linux-base")
    XCTAssertEqual(packs.last?["asset_path"] as? String, "runtime/bootstrap/python-uv.sarpack")
  }

  func testAgentEmbeddedRuntimeBundleCodecRejectsIncompleteDefaultEnvironment() {
    let invalid = """
      {"format_version":1,"architecture":"arm64-v8a","packs":[
        {"pack_id":"linux-base","version":"1.0.0","architecture":"arm64-v8a","asset_path":"runtime/bootstrap/linux-base.sarpack","archive_sha256":"\(String(repeating: "a", count: 64))","archive_size_bytes":1024,"installed_size_bytes":2048,"dependencies":[]}
      ]}
      """

    XCTAssertThrowsError(try AgentEmbeddedRuntimeBundleCodec.decode(invalid))
  }

  func testAgentEmbeddedRuntimeBootstrapVersionComparisonAvoidsDowngrades() {
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.1.9"), 1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.2.0"), 0)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.1.9", "1.2.0"), -1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0", "1.2.0-rc.1"), 1)
    XCTAssertEqual(AgentEmbeddedRuntimeBootstrap.compareVersions("1.2.0+build.2", "1.2.0+build.1"), 0)
  }

  func testAgentMcpToolSecurityPolicyMatchesAndroidRiskAndPermissions() {
    let read = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("get_weather", readOnly: true),
      arguments: ["city": .string("Shanghai")],
      transport: .streamableHTTP
    )
    let destructive = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_project", destructive: true),
      arguments: [
        "project_path": .string("/work"),
        "api_token": .string("secret-value")
      ],
      transport: .localStdio
    )

    XCTAssertEqual(read.risk, .low)
    XCTAssertTrue(read.permissions.contains("mcp.network.connect"))
    XCTAssertEqual(read.publicValue()["risk"], .string("low"))

    XCTAssertEqual(destructive.risk, .high)
    XCTAssertTrue(destructive.permissions.contains("mcp.destructive"))
    XCTAssertTrue(destructive.permissions.contains("mcp.files.access"))
    XCTAssertTrue(destructive.permissions.contains("mcp.secrets.use"))
    XCTAssertTrue(destructive.permissions.contains("mcp.process.execute"))
    XCTAssertEqual(destructive.parameterPreview["api_token"], .string("[REDACTED]"))
    XCTAssertEqual(destructive.inputSha256.count, 64)
  }

  func testAgentMcpToolSecurityPolicyPermissionMatrixMatchesAndroid() {
    let high = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_account", destructive: true),
      arguments: [:],
      transport: .streamableHTTP
    )
    let medium = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("update_document", readOnly: false),
      arguments: ["content": .string("updated")],
      transport: .streamableHTTP
    )

    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: high, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: high, explicitlyApproved: true).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: high, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: high, explicitlyApproved: true).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: medium, explicitlyApproved: false).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .askForChanges, assessment: medium, explicitlyApproved: true).allowed)
    XCTAssertTrue(AgentMcpToolSecurityPolicy.decide(mode: .trusted, assessment: medium, explicitlyApproved: false).allowed)
    XCTAssertFalse(AgentMcpToolSecurityPolicy.decide(mode: .readOnly, assessment: medium, explicitlyApproved: true).allowed)
    XCTAssertEqual(
      AgentMcpToolSecurityPolicy.decide(mode: .disabled, assessment: medium, explicitlyApproved: true).requiredUserAction,
      "enable_connection"
    )
  }

  func testAgentMcpParameterRedactorDropsNestedInlineAndURLSecrets() {
    let sanitized = AgentMcpParameterRedactor.sanitize([
      "password": .string("secret-value"),
      "nested": .object([
        "authorization": .string("Bearer abcdefghijklmnop"),
        "url": .string("https://example.test/action?token=secret#fragment"),
        "note": .string("token=inline-secret")
      ])
    ])
    let serialized = AgentMcpJSONCodec.stringify(sanitized)
    let error = AgentMcpParameterRedactor.sanitizeText(
      "token=inline-secret at https://example.test/mcp?api_key=secret"
    )

    XCTAssertFalse(serialized.contains("secret-value"))
    XCTAssertFalse(serialized.contains("abcdefghijklmnop"))
    XCTAssertFalse(serialized.contains("inline-secret"))
    XCTAssertFalse(serialized.contains("fragment"))
    XCTAssertFalse(error.contains("inline-secret"))
    XCTAssertFalse(error.contains("api_key=secret"))
  }

  func testAgentMcpSecurityModelsUseAndroidWireNamesAndStableJson() throws {
    let mode = try JSONDecoder().decode(AgentMcpPermissionMode.self, from: Data(#""trusted""#.utf8))
    let fallbackMode = try JSONDecoder().decode(AgentMcpPermissionMode.self, from: Data(#""future""#.utf8))
    let tool = try JSONDecoder().decode(
      AgentMcpTool.self,
      from: Data(
        #"""
        {
          "name": "get_status",
          "input_schema": {},
          "annotations": {
            "read_only_hint": true,
            "open_world_hint": true
          },
          "raw": {"name": "get_status"}
        }
        """#.utf8
      )
    )
    let assessment = AgentMcpToolSecurityPolicy.assess(
      tool: tool,
      arguments: ["path": .string("/tmp/report.txt")],
      transport: .streamableHTTP
    )
    let encodedAssessment = String(decoding: try JSONEncoder().encode(assessment), as: UTF8.self)
    let stableJson = AgentMcpJSONCodec.stringify(["b": .int(2), "a": .string("x")])

    XCTAssertEqual(mode, .trusted)
    XCTAssertEqual(fallbackMode, .askForChanges)
    XCTAssertEqual(tool.annotations?["read_only_hint"]?.boolValue, true)
    XCTAssertEqual(assessment.risk, .low)
    XCTAssertTrue(assessment.permissions.contains("mcp.files.access"))
    XCTAssertTrue(assessment.permissions.contains("mcp.network.open_world"))
    XCTAssertTrue(encodedAssessment.contains(#""parameter_preview":"#))
    XCTAssertEqual(stableJson, #"{"a":"x","b":2}"#)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "get_status"), .low)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "control_relay"), .medium)
    XCTAssertEqual(AgentMcpToolSecurityPolicy.provisionalRisk(toolName: "delete_device"), .high)
  }

  func testAgentMcpAuditStoreAppendsListsBoundsAndClears() {
    let store = InMemoryAgentMcpAuditStore()
    store.append(mcpAuditRecord("audit-1", connectionId: "conn-a", timestampMillis: 1))
    store.append(mcpAuditRecord("audit-2", connectionId: "conn-b", timestampMillis: 2))
    store.append(mcpAuditRecord("audit-3", connectionId: "conn-a", timestampMillis: 3))

    XCTAssertEqual(store.list(limit: 2).map(\.auditId), ["audit-3", "audit-2"])
    XCTAssertEqual(store.list(connectionId: "conn-a", limit: 10).map(\.auditId), ["audit-3", "audit-1"])
    XCTAssertEqual(store.clear(connectionId: "conn-a"), 2)
    XCTAssertEqual(store.list(limit: 10).map(\.auditId), ["audit-2"])

    let bounded = InMemoryAgentMcpAuditStore()
    for index in 0..<1_005 {
      bounded.append(mcpAuditRecord("bulk-\(index)", connectionId: "bulk", timestampMillis: Int64(index)))
    }
    XCTAssertEqual(bounded.list(limit: 1).first?.auditId, "bulk-1004")
    XCTAssertEqual(bounded.list(limit: 1_000).count, 500)
    XCTAssertEqual(bounded.clear(connectionId: ""), 1_000)
  }

  func testFileAgentMcpAuditStorePersistsAndRecoversRecords() throws {
    let root = try temporaryDirectory("mcp-audit-store")
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("audit/records.json", isDirectory: false)
    let store = FileAgentMcpAuditStore(fileURL: fileURL)

    store.append(mcpAuditRecord("audit-1", connectionId: "conn-a", timestampMillis: 1))
    store.append(mcpAuditRecord("audit-2", connectionId: "conn-b", timestampMillis: 2))
    let restored = FileAgentMcpAuditStore(fileURL: fileURL)

    XCTAssertEqual(restored.list(limit: 10).map(\.auditId), ["audit-2", "audit-1"])
    XCTAssertEqual(restored.clear(connectionId: "conn-a"), 1)
    XCTAssertEqual(FileAgentMcpAuditStore(fileURL: fileURL).list(limit: 10).map(\.auditId), ["audit-2"])

    try "not-json".write(to: fileURL, atomically: true, encoding: .utf8)
    XCTAssertEqual(FileAgentMcpAuditStore(fileURL: fileURL).list(limit: 10), [])
  }

  func testAgentMcpAuditRecordFactoryAndCodecUseAndroidWireNames() throws {
    let connection = AgentMcpConnection(
      id: "conn-a",
      displayName: "Relay",
      endpoint: "https://relay.example/mcp",
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired,
      permissionMode: .askForChanges
    )
    let assessment = AgentMcpToolSecurityPolicy.assess(
      tool: mcpTool("delete_project", destructive: true),
      arguments: [
        "api_token": .string("secret-value"),
        "url": .string("https://example.test/mcp?api_key=secret")
      ],
      transport: .streamableHTTP
    )
    let decision = AgentMcpToolSecurityPolicy.decide(
      mode: .askForChanges,
      assessment: assessment,
      explicitlyApproved: false
    )
    let context = AgentNativeToolInvocationContext(
      conversationId: "chat-1",
      callerId: "planner",
      attributes: ["task_id": "task-1"]
    )

    let record = AgentMcpAuditRecord.toolCall(
      connection: connection,
      toolName: "delete_project",
      assessment: assessment,
      decision: decision,
      context: context,
      status: "failed",
      durationMillis: -5,
      outputSha256: String(repeating: "b", count: 64),
      errorCode: "mcp_call_failed",
      errorMessage: "token=inline-secret at https://example.test/mcp?api_key=secret",
      auditId: "audit-fixed",
      timestampMillis: 12_345
    )
    let encoded = AgentMcpAuditCodec.encode([record])
    let decoded = try XCTUnwrap(AgentMcpAuditCodec.decode(encoded).first)

    XCTAssertEqual(record.source, "ios-mcp:conn-a")
    XCTAssertEqual(record.durationMillis, 0)
    XCTAssertEqual(record.permissions, assessment.permissions.sorted())
    XCTAssertEqual(record.parameterPreview["api_token"], .string("[REDACTED]"))
    XCTAssertTrue(encoded.contains(#""audit_id":"audit-fixed""#))
    XCTAssertTrue(encoded.contains(#""timestamp_ms":12345"#))
    XCTAssertTrue(encoded.contains(#""permission_decision":"mcp_high_risk_approval_required""#))
    XCTAssertFalse(encoded.contains("secret-value"))
    XCTAssertFalse(encoded.contains("inline-secret"))
    XCTAssertFalse(encoded.contains("api_key=secret"))
    XCTAssertEqual(decoded.auditId, "audit-fixed")
    XCTAssertEqual(decoded.connectionId, "conn-a")
    XCTAssertEqual(decoded.taskId, "task-1")
    XCTAssertEqual(decoded.conversationId, "chat-1")
    XCTAssertEqual(decoded.risk, "high")
    XCTAssertEqual(decoded.errorCode, "mcp_call_failed")
  }

  func testUnifiedCommandProtocolRequestPayloadUsesAndroidDesktopMqttContract() throws {
    let payload = try UnifiedCommandProtocol.requestPayload(
      commandId: "commands.list",
      args: ["dry_run": .bool(true)],
      messageId: "message-1"
    )

    XCTAssertEqual(payload["type"]?.stringValue, UnifiedCommandProtocol.requestType)
    XCTAssertEqual(payload["message_id"]?.stringValue, "message-1")
    XCTAssertEqual(payload["source_message_id"]?.stringValue, "message-1")
    XCTAssertEqual(payload["contact_id"]?.stringValue, "system")
    XCTAssertEqual(payload["command_id"]?.stringValue, "commands.list")
    XCTAssertEqual(payload["args"]?.objectValue?["dry_run"]?.boolValue, true)
    XCTAssertEqual(payload["requested_by"]?.stringValue, "paired_phone")
    XCTAssertEqual(payload["approve"]?.boolValue, false)
  }

  func testUnifiedCommandProtocolSlashPayloadCanOmitCommandIdAndRejectsBlankRequests() throws {
    let payload = try UnifiedCommandProtocol.requestPayload(
      commandId: "",
      slash: "/commands",
      messageId: "message-2"
    )

    XCTAssertEqual(payload["command_id"]?.stringValue, "")
    XCTAssertEqual(payload["slash"]?.stringValue, "/commands")
    XCTAssertThrowsError(
      try UnifiedCommandProtocol.requestPayload(commandId: "", raw: "  ", slash: "")
    ) { error in
      XCTAssertEqual(error as? UnifiedCommandProtocolError, .missingCommand)
    }
  }

  func testUnifiedCommandProtocolDecodesStructuredCommandResult() throws {
    let payload: AgentMcpJSONObject = [
      "type": .string("unified_command_result"),
      "command_id": .string("commands.list"),
      "command_status": .string("completed"),
      "source_message_id": .string("message-1"),
      "result": .object([
        "status": .string("completed"),
        "command_id": .string("commands.list"),
        "run_id": .string("run-1"),
        "data": .object(["catalog_size": .int(753)]),
        "display": .object(["type": .string("command_list")])
      ])
    ]

    let result = try XCTUnwrap(UnifiedCommandProtocol.decodeResult(payload))

    XCTAssertEqual(result.commandId, "commands.list")
    XCTAssertEqual(result.status, "completed")
    XCTAssertEqual(result.runId, "run-1")
    XCTAssertEqual(result.sourceMessageId, "message-1")
    XCTAssertEqual(result.data["catalog_size"]?.intValue, 753)
    XCTAssertEqual(result.display["type"]?.stringValue, "command_list")
  }

  func testUnifiedCommandProtocolIgnoresOtherPayloadTypesAndUsesResultFallbacks() throws {
    XCTAssertNil(UnifiedCommandProtocol.decodeResult(["type": .string("text")]))

    let result = try XCTUnwrap(
      UnifiedCommandProtocol.decodeResult([
        "type": .string("unified_command_result"),
        "source_message_id": .string("message-fallback"),
        "result": .object([
          "status": .string("failed"),
          "command_id": .string("commands.run"),
          "error_code": .string("command_failed"),
          "message": .string("Command failed")
        ])
      ])
    )

    XCTAssertEqual(result.commandId, "commands.run")
    XCTAssertEqual(result.status, "failed")
    XCTAssertEqual(result.errorCode, "command_failed")
    XCTAssertEqual(result.message, "Command failed")
  }

  func testUnifiedCommandResultUsesAndroidWireNames() throws {
    let result = UnifiedCommandResult(
      commandId: "commands.list",
      status: "completed",
      runId: "run-1",
      sourceMessageId: "message-1",
      data: ["catalog_size": .int(753)],
      display: ["type": .string("command_list")]
    )
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(result), as: UTF8.self)

    XCTAssertTrue(encoded.contains(#""command_id":"commands.list""#))
    XCTAssertTrue(encoded.contains(#""run_id":"run-1""#))
    XCTAssertTrue(encoded.contains(#""source_message_id":"message-1""#))
    XCTAssertTrue(encoded.contains(#""catalog_size":753"#))
  }

  func testAgentFailureRecoveryPayloadRoundTripsAndroidWireNames() throws {
    let payload = AgentFailureRecoveryPayload(
      action: .switchAgent,
      taskId: "task-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      agentId: "codex",
      originalGoal: "Build the project",
      failure: "Codex is unavailable"
    )

    let decoded = try XCTUnwrap(AgentFailureRecoveryPayload.decode(payload.encode()))
    let encodedObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(payload.encode().utf8)) as? [String: Any]
    )

    XCTAssertEqual(decoded, payload)
    XCTAssertNil(AgentFailureRecoveryPayload.decode("{}"))
    XCTAssertEqual(encodedObject["version"] as? Int, 1)
    XCTAssertEqual(encodedObject["action"] as? String, "switch_agent")
    XCTAssertEqual(encodedObject["task_id"] as? String, "task-1")
    XCTAssertEqual(AgentFailureRecoveryAction.fromWireValue(" SWITCH_AGENT "), .switchAgent)
  }

  func testAgentFailureRecoveryPayloadBoundsRecoveryContext() throws {
    let payload = AgentFailureRecoveryPayload(
      action: .retry,
      taskId: String(repeating: "t", count: 200),
      conversationId: String(repeating: "c", count: 200),
      turnId: String(repeating: "u", count: 200),
      agentId: String(repeating: "a", count: 200),
      originalGoal: String(repeating: "g", count: 17_000),
      failure: String(repeating: "f", count: 2_500)
    )
    let decoded = try XCTUnwrap(AgentFailureRecoveryPayload.decode(payload.encode()))

    XCTAssertEqual(decoded.taskId.count, 160)
    XCTAssertEqual(decoded.conversationId.count, 160)
    XCTAssertEqual(decoded.turnId.count, 160)
    XCTAssertEqual(decoded.agentId.count, 160)
    XCTAssertEqual(decoded.originalGoal.count, 16_000)
    XCTAssertEqual(decoded.failure.count, 2_000)
  }

  func testAgentFailureRecoveryPolicyRecommendsAndroidRecoveryPaths() {
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "timed_out", failure: "Execution timed out"),
      .retry
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Agent unavailable"),
      .switchAgent
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Verification failed"),
      .degrade
    )
    XCTAssertEqual(
      AgentFailureRecoveryPolicy.recommended(status: "failed", failure: "Permanent failure"),
      .diagnostics
    )
    XCTAssertEqual(AgentFailureRecoveryPolicy.executionMode(for: .degrade), .planOnly)
    XCTAssertEqual(AgentFailureRecoveryPolicy.executionMode(for: .diagnostics), .planOnly)
    XCTAssertNil(AgentFailureRecoveryPolicy.executionMode(for: .retry))
  }

  func testAgentFailureRecoveryInstructionPreservesGoalFailureAndLanguageHint() {
    let instruction = AgentFailureRecoveryPolicy.instruction(
      payload: AgentFailureRecoveryPayload(
        action: .retry,
        taskId: "task-1",
        conversationId: "conversation-1",
        turnId: "turn-1",
        agentId: "codex",
        originalGoal: "Build the app",
        failure: "Network unavailable"
      ),
      chinese: true
    )

    XCTAssertTrue(instruction.contains("latest safe checkpoint"))
    XCTAssertTrue(instruction.contains("Respond in Simplified Chinese."))
    XCTAssertTrue(instruction.contains("Build the app"))
    XCTAssertTrue(instruction.contains("Network unavailable"))
  }

  func testAgentClarificationPolicyAsksTargetedQuestionsForMissingDetails() {
    let cases: [(String, AgentClarificationQuestion)] = [
      ("Help me", .taskGoal),
      ("Write a program", .codeOutcome),
      ("Control my computer", .controlAction),
      ("Research", .researchTopic),
      ("Process the file", .fileAction),
      ("Remember this", .memoryContent),
      ("Create an automation", .automationDetails),
      ("\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}", .taskGoal),
      ("\u{5199}\u{4e2a}\u{7a0b}\u{5e8f}", .codeOutcome),
      ("\u{63a7}\u{5236}\u{624b}\u{673a}", .controlAction),
      ("\u{641c}\u{7d22}", .researchTopic),
      ("\u{8bb0}\u{4f4f}\u{8fd9}\u{4e2a}", .memoryContent),
      ("\u{521b}\u{5efa}\u{81ea}\u{52a8}\u{5316}", .automationDetails)
    ]

    for (goal, expectedQuestion) in cases {
      let decision = AgentClarificationPolicy.decide(goal: goal)

      XCTAssertEqual(decision.mode, .askLocally, goal)
      XCTAssertEqual(decision.question, expectedQuestion, goal)
      XCTAssertTrue(decision.shouldAsk, goal)
    }
  }

  func testAgentClarificationPolicyExecutesClearAndContextualRequests() {
    let clearRequests = [
      "Hello",
      "What is the battery level?",
      "Turn on the flashlight",
      "Set a one minute timer",
      "Research today's AI news",
      "Remember that I prefer concise replies",
      "Build an Android calculator app",
      "\u{4f60}\u{597d}",
      "\u{6253}\u{5f00}\u{624b}\u{7535}\u{7b52}",
      "\u{67e5}\u{4e00}\u{4e0b}\u{4eca}\u{5929}\u{4e0a}\u{6d77}\u{7684}\u{5929}\u{6c14}",
      "\u{8bb0}\u{4f4f}\u{6211}\u{559c}\u{6b22}\u{7b80}\u{6d01}\u{56de}\u{590d}"
    ]
    for goal in clearRequests {
      XCTAssertEqual(AgentClarificationPolicy.decide(goal: goal).mode, .execute, goal)
    }

    let contextualRequests = [
      "Continue",
      "Try again",
      "Handle this",
      "Make it better",
      "\u{7ee7}\u{7eed}",
      "\u{518d}\u{8bd5}\u{8bd5}",
      "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
      "\u{6309}\u{4e0a}\u{9762}\u{7684}\u{505a}"
    ]
    for goal in contextualRequests {
      let decision = AgentClarificationPolicy.decide(
        goal: goal,
        hasConversationContext: true
      )

      XCTAssertEqual(decision.mode, .execute, goal)
      XCTAssertFalse(decision.shouldAsk, goal)
    }
  }

  func testAgentClarificationPolicyUsesModelForVagueAttachmentTasks() {
    for goal in ["", "Take a look", "\u{5904}\u{7406}\u{4e00}\u{4e0b}"] {
      let decision = AgentClarificationPolicy.decide(
        goal: goal,
        hasAttachments: true
      )

      XCTAssertEqual(decision.mode, .askWithModel, goal)
      XCTAssertEqual(decision.question, .fileAction, goal)
    }

    XCTAssertEqual(
      AgentClarificationPolicy.decide(
        goal: "Summarize this PDF and list the action items",
        hasAttachments: true
      ).mode,
      .execute
    )
  }

  func testAgentSkillCommandParserMatchesAndroidSaveAndUpgradeCommands() {
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("Search today's news"))
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("Remember this preference"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand("Save this as a Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand("\u{4fdd}\u{5b58}\u{6210} Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand(
      "\u{4fdd}\u{5b58}\u{6210}skill,\u{4ee5}\u{540e}\u{6211}\u{8bf4}\u{67e5}\u{4ec0}\u{4e48}\u{5b57}\u{7b14}\u{987a}\u{7b14}\u{753b}\u{5c31}\u{8c03}\u{7528}\u{8fd9}\u{4e2a}skill"
    ))
    XCTAssertTrue(AgentSkillCommandParser.isSaveCommand(
      "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a} Skill\u{ff0c}\u{4ee5}\u{540e}\u{7ee7}\u{7eed}\u{4f7f}\u{7528}"
    ))
    XCTAssertFalse(AgentSkillCommandParser.isSaveCommand("\u{4e0d}\u{8981}\u{4fdd}\u{5b58}\u{6210} Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isUpgradeCommand("Upgrade this Skill"))
    XCTAssertTrue(AgentSkillCommandParser.isUpgradeCommand("\u{5347}\u{7ea7}\u{8fd9}\u{4e2a} Skill"))
  }

  func testAgentResponseSelfCheckMatchesAndroidRepairAndPassCases() {
    let substantive = AgentResponseSelfCheck.evaluate(
      latestRequest: "Summarize the report",
      response: "The report identifies three launch risks and recommends a one-day delay."
    )
    XCTAssertTrue(substantive.accepted)
    XCTAssertEqual(substantive.status, .passed)
    XCTAssertEqual(substantive.requestDigest.count, 16)
    XCTAssertTrue(substantive.diagnostic.contains("addresses the latest user request"))

    let acknowledgement = AgentResponseSelfCheck.evaluate(
      latestRequest: "Build and verify the Android app",
      response: "Got it. I will handle this now."
    )
    XCTAssertFalse(acknowledgement.accepted)
    XCTAssertEqual(acknowledgement.reasons, ["acknowledgement_only"])

    let missingAttachment = AgentResponseSelfCheck.evaluate(
      latestRequest: "Review this worksheet",
      response: "I cannot see any attachment. Please upload the file.",
      hasAttachments: true
    )
    XCTAssertEqual(missingAttachment.status, .repair)
    XCTAssertTrue(missingAttachment.reasons.contains("available_attachment_ignored"))
    XCTAssertTrue(missingAttachment.actionableRequest)

    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "Create a ZIP archive",
      response: "Done.",
      hasOutputArtifacts: true
    ).accepted)
    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "Create and return the annotated image",
      response: "",
      hasOutputArtifacts: true
    ).accepted)
  }

  func testAgentResponseSelfCheckMatchesAndroidChineseAndIdentityCases() {
    let chineseAcknowledgement = AgentResponseSelfCheck.evaluate(
      latestRequest: "\u{5206}\u{6790}\u{8fd9}\u{4efd}\u{62a5}\u{544a}",
      response: "\u{6536}\u{5230}\u{ff0c}\u{6211}\u{4f1a}\u{9a6c}\u{4e0a}\u{5904}\u{7406}\u{3002}"
    )
    XCTAssertFalse(chineseAcknowledgement.accepted)
    XCTAssertEqual(chineseAcknowledgement.reasons, ["acknowledgement_only"])

    let greeting = AgentResponseSelfCheck.evaluate(
      latestRequest: "hello",
      response: "Got it. I will handle this now."
    )
    XCTAssertFalse(greeting.accepted)
    XCTAssertEqual(greeting.reasons, ["acknowledgement_only"])

    XCTAssertTrue(AgentResponseSelfCheck.evaluate(
      latestRequest: "thank you",
      response: "Okay"
    ).accepted)

    let identityMismatch = AgentResponseSelfCheck.evaluate(
      latestRequest: "Explain the error",
      response: "The token expired.",
      expectedIdentity: ["task_id": "task-1", "turn_id": "turn-2"],
      responseIdentity: ["task_id": "task-1", "turn_id": "turn-1"]
    )
    XCTAssertEqual(identityMismatch.status, .rejected)
    XCTAssertEqual(identityMismatch.reasons, ["identity_mismatch"])
  }

  func testCodexStyleResponsePolicyCoversLanguageActionClarificationAndFailures() {
    let policy = CodexStyleResponsePolicy.promptText
    let preferred = CodexStyleResponsePolicy.preferredPrompt(languageTag: "zh-Hans-CN", languageName: "Simplified Chinese")
    let clarification = CodexStyleResponsePolicy.attachmentClarification(names: ["report.pdf", "report.pdf", "chart.png"])

    XCTAssertTrue(policy.contains("Simplified Chinese"))
    XCTAssertTrue(policy.contains("execute it"))
    XCTAssertTrue(policy.contains("ask only the most important question"))
    XCTAssertTrue(policy.contains("Never return a raw exception or stack trace"))
    XCTAssertTrue(policy.contains("never reproduce the input files as assistant artifacts"))
    XCTAssertTrue(preferred.contains("Preferred response language: Simplified Chinese (zh-Hans-CN)"))
    XCTAssertTrue(clarification.contains("report.pdf, chart.png"))
  }

  func testCodexStyleResponsePolicyDropsInputArtifactsButKeepsGeneratedFiles() throws {
    let raw = richDocument([
      [
        "id": "input",
        "type": "file",
        "title": "test.xlsx",
        "uri": "signalasi-artifact://task/downloads/input/01-test.xlsx"
      ],
      [
        "id": "output",
        "type": "file",
        "title": "summary.csv",
        "uri": "signalasi-artifact://task/outputs/summary.csv"
      ]
    ])

    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(raw))

    XCTAssertEqual(blocks.count, 1)
    XCTAssertEqual(blocks.first?["title"] as? String, "summary.csv")
  }

  func testCodexStyleResponsePolicyKeepsHostOwnedConversationActions() throws {
    let raw = richDocument([
      [
        "id": "notice",
        "type": "notice",
        "text": "A focused topic workspace is ready."
      ],
      [
        "id": "actions",
        "type": "actions",
        "actions": [
          [
            "id": "open",
            "label": "Open topic",
            "verb": "open_conversation",
            "value": "conversation-id"
          ]
        ]
      ]
    ])

    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(raw))
    let actions = try XCTUnwrap(blocks.last?["actions"] as? [[String: Any]])

    XCTAssertEqual(blocks.compactMap { $0["id"] as? String }, ["notice", "actions"])
    XCTAssertEqual(actions.first?["verb"] as? String, "open_conversation")
  }

  func testCodexStyleResponsePolicySanitizesToolChatterAndStackFrames() {
    let raw = """
    preparing mcp_fetch
    Useful result
    at com.signalasi.Internal.run(Internal.kt:10)
    """

    XCTAssertEqual(CodexStyleResponsePolicy.sanitizeAssistantText(raw), "Useful result")
  }

  func testCodexStyleResponsePolicyDropsDuplicatePhoneRuntimeVerification() throws {
    let text = [
      "\u{5df2}\u{5199}\u{597d}\u{5e76}\u{5728}\u{624b}\u{673a}\u{672c}\u{673a} Linux \u{4e2d}\u{9a8c}\u{8bc1}\u{901a}\u{8fc7}\u{3002}",
      "",
      "\u{8fd0}\u{884c}\u{7ed3}\u{679c}\u{ff1a}",
      "",
      "```text",
      "5050",
      "```",
      "",
      "\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}\u{ff1a}",
      "",
      "```text",
      "\u{901a}\u{8fc7}\u{ff08}\u{9000}\u{51fa}\u{7801} 0\u{ff09}",
      "```"
    ].joined(separator: "\n")
    let clean = CodexStyleResponsePolicy.sanitizeAssistantText(text)
    XCTAssertTrue(clean.contains("5050"))
    XCTAssertFalse(clean.contains("\u{5df2}\u{5199}\u{597d}"))
    XCTAssertFalse(clean.contains("\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}"))
    XCTAssertFalse(clean.contains("\u{9000}\u{51fa}\u{7801}"))

    let rich = richDocument([
      [
        "id": "heading",
        "type": "text",
        "text": "\u{5df2}\u{5199}\u{597d}\u{5e76}\u{5728}\u{624b}\u{673a}\u{672c}\u{673a} Linux \u{4e2d}\u{9a8c}\u{8bc1}\u{901a}\u{8fc7}\u{3002}"
      ],
      [
        "id": "run-heading",
        "type": "text",
        "text": "\u{8fd0}\u{884c}\u{7ed3}\u{679c}\u{ff1a}"
      ],
      [
        "id": "run",
        "type": "code",
        "text": "5050",
        "language": "text"
      ],
      [
        "id": "verify-heading",
        "type": "text",
        "text": "\u{9a8c}\u{8bc1}\u{7ed3}\u{679c}\u{ff1a}"
      ],
      [
        "id": "verify",
        "type": "code",
        "text": "\u{901a}\u{8fc7}\u{ff08}\u{9000}\u{51fa}\u{7801} 0\u{ff09}",
        "language": "text"
      ]
    ])
    let blocks = try richBlocks(CodexStyleResponsePolicy.filterAssistantRichOutput(rich))

    XCTAssertEqual(blocks.compactMap { $0["id"] as? String }, ["run-heading", "run"])
  }

  func testDeliveryTraceStageLabelsMatchAndroidActions() {
    XCTAssertEqual(DeliveryTraceEvent(stage: "mqtt_published").displayTitle, "Published to MQTT")
    XCTAssertEqual(DeliveryTraceEvent(stage: "desktop_decrypted").displayTitle, "Desktop decrypted")
    XCTAssertEqual(DeliveryTraceEvent(stage: "cloud_request").displayTitle, "Model request")
    XCTAssertEqual(DeliveryTraceEvent(stage: "unknown_stage").displayTitle, "unknown_stage")
  }

  func testMessageStatusUpdatesExposeReadableDeliveryTrace() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    store.markMessage(message.id, contactId: "hermes", status: .sent, detail: "QoS accepted")

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryTrace.map(\.displayTitle), ["Queued", "Sent"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "QoS accepted")
  }

  func testAppendDeliveryTraceUpdatesStatusAndKeepsPriorStages() {
    let store = makeStore()
    let message = store.appendOutgoing("hello", to: "hermes")

    XCTAssertTrue(store.appendDeliveryTrace(
      message.id,
      contactId: "hermes",
      stage: "mqtt_published",
      detail: "signalasi/topic",
      status: .sent
    ))

    let updated = store.messages(for: "hermes").first { $0.id == message.id }
    XCTAssertEqual(updated?.deliveryStatus, .sent)
    XCTAssertEqual(updated?.deliveryTrace.map(\.stage), ["queued", "mqtt_published"])
    XCTAssertEqual(updated?.deliveryTrace.last?.detail, "signalasi/topic")
  }

  func testDeletingHermesClearsServerLinks() throws {
    let store = makeStore()
    _ = try store.addServerLink(from: makePairingQRCode())

    XCTAssertEqual(store.serverLinks.count, 1)
    XCTAssertTrue(store.deleteContact(id: "hermes"))

    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.contact(id: "hermes")?.trustState, .deleted)
  }

  func testDestroyAllPrivateDataRegeneratesIdentityAndClearsSecrets() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let originalSignalASIId = store.profile.signalASIId
    let originalIdentitySecret = secrets.string(account: "identity.p256.private")
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "secret-key",
      apiStyle: .openAICompatible
    )
    let keychainAccount = contact.cloudModels[0].keychainAccount
    _ = try store.addServerLink(from: makePairingQRCode())
    store.appendOutgoing("private note", to: "hermes")
    store.updateVoiceSettings { settings in
      settings.wakeListeningEnabled = true
    }
    store.updateDisplaySettings {
      $0.textScale = .extraLarge
    }
    store.updateAgentSafetySettings {
      $0.taskExecutionMode = .planOnly
      $0.permissionMode = .observeOnly
      $0.executionPaused = true
    }
    store.selectAgentTaskBudgetProfile(.privateMode)
    store.upsertCustomDeviceConnector(
      CustomDeviceConnector(
        id: "custom-device-office",
        name: "Office Light",
        transport: .mqtt,
        endpoint: "mqtt://broker.local",
        authToken: "token"
      )
    )
    store.updateHomeAssistantSettings {
      $0.enabled = true
      $0.baseUrl = "http://homeassistant.local:8123"
      $0.accessToken = "ha-token"
      $0.defaultEntityId = "light.office"
    }
    store.updateModelPlannerSettings {
      $0.enabled = true
      $0.maxActions = 12
    }

    store.destroyAllPrivateData()

    XCTAssertNotEqual(store.profile.signalASIId, originalSignalASIId)
    XCTAssertNotEqual(secrets.string(account: "identity.p256.private"), originalIdentitySecret)
    XCTAssertNil(secrets.string(account: keychainAccount))
    XCTAssertNotNil(store.contact(id: "hermes"))
    XCTAssertNil(store.contact(id: "cloud:openai"))
    XCTAssertTrue(store.friendRequests.isEmpty)
    XCTAssertTrue(store.serverLinks.isEmpty)
    XCTAssertEqual(store.messages(for: "hermes").count, 1)
    XCTAssertEqual(store.voiceSettings, .default)
    XCTAssertEqual(store.displaySettings, .default)
    XCTAssertEqual(store.agentSafetySettings, .default)
    XCTAssertEqual(store.agentTaskBudget, .default)
    XCTAssertTrue(store.customDeviceConnectors.isEmpty)
    XCTAssertNil(secrets.string(account: "custom_device_connector.custom-device-office.auth_token"))
    XCTAssertEqual(store.homeAssistantSettings, .default)
    XCTAssertNil(secrets.string(account: "home_assistant.access_token"))
    XCTAssertEqual(store.modelPlannerSettings, .default)
  }

  func testSelectingCloudModelChangesProviderActiveModel() throws {
    let store = makeStore()

    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertEqual(contact?.selectedCloudModelId, "model-b")
    XCTAssertEqual(contact?.selectedCloudModel?.displayName, "Model B")
  }

  func testDeletingSelectedCloudModelRemovesSecretAndFallsBack() throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.example.com/v1/chat/completions",
      apiKey: "key-b",
      apiStyle: .openAICompatible
    )
    XCTAssertTrue(store.setSelectedCloudModel(contactId: "cloud:openai", modelId: "model-b"))
    let removedAccount = store.contact(id: "cloud:openai")!.cloudModels[1].keychainAccount

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-b"))

    let contact = store.contact(id: "cloud:openai")
    XCTAssertNil(secrets.string(account: removedAccount))
    XCTAssertEqual(contact?.cloudModels.map(\.modelId), ["model-a"])
    XCTAssertEqual(contact?.selectedCloudModelId, "model-a")
    XCTAssertEqual(contact?.deleted, false)
  }
  func testDeletingLastCloudModelHidesProviderContact() throws {
    let store = makeStore()
    _ = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "key-a",
      apiStyle: .openAICompatible
    )

    XCTAssertTrue(store.deleteCloudModel(contactId: "cloud:openai", modelId: "model-a"))

    XCTAssertEqual(store.contact(id: "cloud:openai")?.deleted, true)
    XCTAssertTrue(store.cloudModelContacts.isEmpty)
  }

  func testCloudModelCredentialPolicyRejectsPlaceholders() {
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential(""))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("****-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isStoredCredential("your-api-key"))
    XCTAssertFalse(CloudModelCredentialPolicy.isAutoRoutableCredential("sk-signalasi-smoke-key"))
    XCTAssertTrue(CloudModelCredentialPolicy.isStoredCredential("sk-live-key"))
  }

  func testAgentConnectorAvailabilityMatchesAndroidDesktopStatusRules() {
    let now: Int64 = 1_000_000

    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "ready", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "busy", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "degraded", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "needs_setup", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "unavailable", setupUpdatedAtMillis: now, nowMillis: now)
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now - 600_001,
        nowMillis: now
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(setupStatus: "ready", setupUpdatedAtMillis: 0, nowMillis: now)
    )
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now + 60_000,
        nowMillis: now
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.desktopAgentReady(
        setupStatus: "ready",
        setupUpdatedAtMillis: now + 60_001,
        nowMillis: now
      )
    )

    var contact = SignalASIContact.hermes()
    contact.setupStatus = "busy"
    contact.updatedAt = Date(timeIntervalSince1970: Double(now) / 1_000)
    XCTAssertTrue(
      AgentConnectorAvailability.desktopAgentReady(
        contact: contact,
        now: Date(timeIntervalSince1970: Double(now) / 1_000)
      )
    )
  }

  func testAgentConnectorAvailabilityMatchesAndroidCloudModelReadiness() {
    let complete = CloudModelConfig(
      id: "deepseek-v4",
      displayName: "DeepSeek V4",
      provider: "deepseek",
      modelId: "deepseek-v4",
      endpoint: "https://api.example.test/v1/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "cloud.deepseek.deepseek-v4",
      updatedAt: Date()
    )

    XCTAssertTrue(
      AgentConnectorAvailability.cloudModelReady(
        model: complete,
        apiKey: "secret",
        provider: "deepseek",
        setupStatus: "ready"
      )
    )
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "", provider: "deepseek"))
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "****-key", provider: "deepseek"))
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(model: complete, apiKey: "sk-signalasi-smoke-key", provider: "deepseek")
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: CloudModelConfig(
          id: "blank-model",
          displayName: "Blank",
          provider: "deepseek",
          modelId: "",
          endpoint: complete.endpoint,
          apiStyle: .openAICompatible,
          keychainAccount: "blank",
          updatedAt: Date()
        ),
        apiKey: "secret",
        provider: "deepseek"
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: CloudModelConfig(
          id: "example-endpoint",
          displayName: "Example",
          provider: "deepseek",
          modelId: "deepseek-v4",
          endpoint: "https://api.example.com/v1/chat/completions",
          apiStyle: .openAICompatible,
          keychainAccount: "example",
          updatedAt: Date()
        ),
        apiKey: "secret",
        provider: "deepseek"
      )
    )
    XCTAssertFalse(
      AgentConnectorAvailability.cloudModelReady(
        model: complete,
        apiKey: "secret",
        provider: "deepseek",
        setupStatus: "needs_setup"
      )
    )

    var contact = SignalASIContact.system()
    contact.deliveryMode = .cloudAPI
    contact.setupStatus = "ready"
    contact.cloudProvider = "deepseek"
    contact.cloudModels = [complete]
    contact.selectedCloudModelId = "deepseek-v4"
    XCTAssertTrue(AgentConnectorAvailability.cloudModelReady(contact: contact, apiKey: "secret"))
    contact.cloudModels = []
    XCTAssertFalse(AgentConnectorAvailability.cloudModelReady(contact: contact, apiKey: "secret"))
  }

  func testCloudClientRejectsPlaceholderCredentialBeforeNetwork() async throws {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-key",
      apiStyle: .openAICompatible
    )
    let model = contact.cloudModels[0]
    try secrets.setString("your-api-key", account: model.keychainAccount)

    do {
      _ = try await CloudModelClient().send(
        contact: store.contact(id: "cloud:openai")!,
        store: store,
        turns: [ChatMessage(contactId: "cloud:openai", content: "hello", isMine: true)]
      )
      XCTFail("Expected placeholder credentials to fail before a network request.")
    } catch SignalASIError.missingAPIKey {
      XCTAssertTrue(true)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeStore() -> SignalASIStore {
    makeStore(secrets: InMemorySecretStore())
  }

  private func makeStore(secrets: SignalASISecretStore) -> SignalASIStore {
    let suite = "SignalASIStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: secrets)
  }

  private func providerCloudModel(
    provider: String,
    modelId: String,
    endpoint: String,
    apiStyle: SignalASICloudAPIStyle = .openAICompatible
  ) -> CloudModelConfig {
    CloudModelConfig(
      id: "\(provider)-\(modelId)",
      displayName: modelId,
      provider: provider,
      modelId: modelId,
      endpoint: endpoint,
      apiStyle: apiStyle,
      keychainAccount: "cloud.\(provider).\(modelId)",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func routeTarget(
    _ id: String,
    kind: AgentConnectorKind,
    status: AgentConnectorStatus = .available,
    capabilities: [AgentCapability] = [.chat, .reasoning, .research]
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: id,
      kind: kind,
      status: status,
      capabilities: capabilities
    )
  }

  private func planFactoryTarget(
    id: String = "desktop:codex",
    title: String = "Codex",
    kind: AgentConnectorKind = .agent,
    status: AgentConnectorStatus = .available,
    capabilities: [AgentCapability] = [.chat, .reasoning]
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: kind,
      status: status,
      capabilities: capabilities,
      failureDomain: "desktop",
      desktopAccessProfile: SignalASILinkProtocol.accessDesktopExecutor
    )
  }

  private func planFactoryRequest(
    targets: [AgentCallableTarget]? = nil,
    nativeTools: [AgentNativeToolDescriptor] = []
  ) -> AgentPlanRequest {
    let resolvedTargets = targets ?? [planFactoryTarget()]
    return AgentPlanRequest(
      goal: "Convert the file",
      screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
      targets: resolvedTargets,
      nativeTools: nativeTools,
      contextDigest: "context"
    )
  }

  private func planConnectorAction(
    id: String,
    connectorId: String,
    target: String = "Codex"
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .callConnector,
      target: target,
      risk: .low,
      status: .pendingConfirmation,
      description: "Run the task",
      parameters: [
        "connector_id": connectorId,
        "prompt": "Convert the file"
      ]
    )
  }

  private func routingResource(
    targetId: String,
    type: AgentResourceType,
    location: AgentResourceLocation
  ) -> AgentResourceDescriptor {
    AgentResourceDescriptor(
      id: "resource:\(targetId)",
      title: targetId,
      type: type,
      location: location,
      status: .available,
      capabilities: [.research],
      cost: .free,
      latency: .fast,
      quality: .strong,
      supportsTools: type == .localTool,
      targetId: targetId
    )
  }

  private func resourceCandidate(
    _ resource: AgentResourceDescriptor,
    score: Int
  ) -> AgentResourceCandidate {
    AgentResourceCandidate(resource: resource, score: score)
  }

  private func routingDecision(
    primary: AgentResourceCandidate,
    fallbacks: [AgentResourceCandidate],
    catalog: [AgentResourceDescriptor]
  ) -> AgentRoutingDecision {
    AgentRoutingDecision(
      requirements: AgentTaskRequirements(
        capabilities: [.research],
        mode: .balanced,
        liveDataRequired: true,
        estimatedInputTokens: 200
      ),
      primary: primary,
      fallbacks: fallbacks,
      catalog: catalog
    )
  }

  private func permissionGrant(
    grantId: String = "grant-location",
    lifetime: AgentPermissionGrantLifetime,
    subjectId: String = "android.location",
    scope: String = "location.foreground",
    action: String = "read",
    resource: String = "",
    target: String = "",
    constraintsJson: String = "{}",
    expiresAtMillis: Int64 = 0,
    maxUses: Int? = nil,
    createdAtMillis: Int64 = 1_000
  ) -> AgentPermissionGrant {
    AgentPermissionGrant(
      grantId: grantId,
      subjectType: .tool,
      subjectId: subjectId,
      scope: scope,
      action: action,
      resource: resource,
      target: target,
      constraintsJson: constraintsJson,
      issuer: .user,
      evidence: "approval-dialog:turn-1",
      lifetime: lifetime,
      maxUses: maxUses,
      createdAtMillis: createdAtMillis,
      expiresAtMillis: expiresAtMillis
    )
  }

  private func permissionRequest(
    subjectId: String = "android.location",
    scope: String = "location.foreground",
    action: String = "read",
    resource: String = "",
    target: String = ""
  ) -> AgentPermissionRequest {
    AgentPermissionRequest(
      subjectType: .tool,
      subjectId: subjectId,
      scope: scope,
      action: action,
      resource: resource,
      target: target
    )
  }

  private func remoteApprovalTaskEvent(
    sourceMessageId: Int64 = 42,
    actionHash: String = String(repeating: "a", count: 64),
    taskStatus: String = "waiting_approval",
    expiresAtMillis: Int64 = 2_000_000
  ) -> String {
    let payload: [String: Any] = [
      "type": "agent_task_event",
      "task_status": taskStatus,
      "task_id": "task-approval",
      "client_route_id": "client-route",
      "conversation_id": "conversation-approval",
      "turn_id": "turn-approval",
      "contact_id": "codex-contact",
      "source_message_id": sourceMessageId,
      "approval_request": [
        "approval_id": "approval-12345678",
        "action_hash": actionHash,
        "kind": "command",
        "title": "Run a command",
        "detail": "python verify.py",
        "target": "python verify.py",
        "reason": "Verify the result",
        "requested_at_ms": expiresAtMillis - 300_000,
        "expires_at_ms": expiresAtMillis,
        "parameters": [
          "command": "python verify.py",
          "cwd": "C:/workspace"
        ]
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }

  private var remoteReputationDesktopId: String { "desktop_0123456789abcdef" }
  private var remoteReputationTaskId: String { "task-123" }
  private var remoteReputationContactId: String { "\(remoteReputationDesktopId):codex" }

  private func remoteReputationReceiptObject() -> AgentMcpJSONObject {
    [
      "version": .int(1),
      "receipt_id": .string("receipt-1"),
      "run_id": .string("run-1"),
      "task_id_hash": .string(agentReputationSha256(Data(remoteReputationTaskId.utf8))),
      "agent_id": .string(remoteReputationContactId),
      "installation_id": .string(remoteReputationDesktopId),
      "executor_failure_domain": .string(remoteReputationDesktopId),
      "capabilities": .array([.string("CHAT"), .string("CODE")]),
      "outcome": .string("SUCCEEDED"),
      "provenance": .string("HOST_OBSERVED"),
      "started_at_millis": .int(1_000),
      "completed_at_millis": .int(2_000),
      "deadline_at_millis": .int(0),
      "estimated_cost_units": .int(0),
      "actual_cost_units": .int(0),
      "output_hash": .string(String(repeating: "b", count: 64)),
      "evidence_hash": .string(String(repeating: "c", count: 64)),
      "signer_id": .string(remoteReputationDesktopId),
      "signature_key_id": .string(String(repeating: "a", count: 64)),
      "signature": .string("signature")
    ]
  }

  private func remoteReputationEnvelope(
    desktopId: String? = nil,
    taskId: String? = nil,
    agentId: String = "codex",
    contactId: String? = nil
  ) -> AgentMcpJSONObject {
    let resolvedDesktopId = desktopId ?? remoteReputationDesktopId
    let resolvedTaskId = taskId ?? remoteReputationTaskId
    let resolvedContactId = contactId ?? "\(resolvedDesktopId):\(agentId)"
    return [
      "desktop_id": .string(resolvedDesktopId),
      "task_id": .string(resolvedTaskId),
      "agent_id": .string(agentId),
      "contact_id": .string(resolvedContactId),
      "execution_receipt": .object(remoteReputationReceiptObject())
    ]
  }

  private func remoteReputationAttestationObject(
    for receipt: AgentSignedExecutionReceipt
  ) -> AgentMcpJSONObject {
    [
      "version": .int(1),
      "attestation_id": .string(agentReputationSha256(Data("\(receipt.receiptId):PASSED".utf8))),
      "receipt_id": .string(receipt.receiptId),
      "receipt_payload_hash": .string(agentReputationSha256(receipt.canonicalPayload())),
      "verifier_agent_id": .string("independent-verifier"),
      "verifier_installation_id": .string("verifier-host"),
      "verifier_failure_domain": .string("phone-b"),
      "verdict": .string("PASSED"),
      "evidence_hash": .string(agentReputationSha256(Data("evidence-\(receipt.receiptId)".utf8))),
      "created_at_millis": .int(receipt.completedAtMillis + 100),
      "signer_id": .string("verifier-host"),
      "signature_key_id": .string(String(repeating: "d", count: 64)),
      "signature": .string("attestation-signature")
    ]
  }

  private var reputationNow: Int64 { 10_000_000 }

  private func reputationReceipt(
    _ runId: String,
    outcome: AgentReputationOutcome,
    agentId: String = "codex-agent",
    capabilities: Set<AgentCapability> = [.chat, .reasoning],
    completedAtMillis: Int64? = nil,
    deadlineAtMillis: Int64 = 0,
    estimatedCostUnits: Int = 0,
    actualCostUnits: Int = 0
  ) -> AgentSignedExecutionReceipt {
    let completedAt = completedAtMillis ?? reputationNow
    return AgentSignedExecutionReceipt(
      receiptId: agentReputationSha256(Data("\(agentId):\(runId):\(outcome.rawValue):\(completedAt)".utf8)),
      runId: runId,
      taskIdHash: agentReputationSha256(Data("task-\(runId)".utf8)),
      agentId: agentId,
      installationId: "executor-host",
      executorFailureDomain: "executor-host",
      capabilities: capabilities,
      outcome: outcome,
      provenance: .executorSigned,
      startedAtMillis: completedAt - 1_000,
      completedAtMillis: completedAt,
      deadlineAtMillis: deadlineAtMillis,
      estimatedCostUnits: estimatedCostUnits,
      actualCostUnits: actualCostUnits,
      outputHash: outcome == .succeeded ? agentReputationSha256(Data("output-\(runId)".utf8)) : "",
      evidenceHash: "",
      signerId: "executor-host",
      signatureKeyId: String(repeating: "a", count: 64),
      signature: "receipt-signature"
    )
  }

  private func reputationAttestation(
    for receipt: AgentSignedExecutionReceipt,
    verdict: AgentReputationVerificationVerdict
  ) -> AgentSignedReputationAttestation {
    AgentSignedReputationAttestation(
      attestationId: agentReputationSha256(Data("\(receipt.receiptId):\(verdict.rawValue)".utf8)),
      receiptId: receipt.receiptId,
      receiptPayloadHash: agentReputationSha256(receipt.canonicalPayload()),
      verifierAgentId: "independent-verifier",
      verifierInstallationId: "verifier-host",
      verifierFailureDomain: "phone-b",
      verdict: verdict,
      evidenceHash: agentReputationSha256(Data("evidence-\(receipt.receiptId)".utf8)),
      createdAtMillis: receipt.completedAtMillis + 100,
      signerId: "verifier-host",
      signatureKeyId: String(repeating: "d", count: 64),
      signature: "attestation-signature"
    )
  }

  private func networkRegistration(
    agentId: String,
    displayName: String,
    providerId: String = "desktop-provider",
    deviceId: String = "desktop-device",
    location: AgentResourceLocation = .trustedDesktop,
    status: AgentEndpointStatus = .online,
    capabilities: Set<AgentCapability> = [.chat],
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    trust: AgentResourceTrust = .verifiedPaired,
    activeRuns: Int = 0,
    maxParallelRuns: Int = 4,
    failureDomain: String = "",
    runtimeFailureDomain: String = "",
    adapterType: String = "",
    lastHeartbeatMillis: Int64 = 0
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: agentId,
      installationId: "installation-\(agentId)",
      deviceId: deviceId,
      providerId: providerId,
      displayName: displayName,
      kind: .agent,
      location: location,
      status: status,
      capabilities: capabilities,
      protocol: AgentProtocolRange(
        preferred: "1.1",
        minimum: "1.0",
        maximum: "1.1",
        features: ["run.cancel", "run.recover"]
      ),
      connectionKind: .signalasiLink,
      cost: cost,
      latency: latency,
      trust: trust,
      activeRuns: activeRuns,
      maxParallelRuns: maxParallelRuns,
      failureDomain: failureDomain,
      runtimeFailureDomain: runtimeFailureDomain,
      adapterType: adapterType,
      lastHeartbeatMillis: lastHeartbeatMillis
    )
  }

  private func assertGlobalCapabilityEventDoesNotExpose(
    _ event: GlobalConversationEvent,
    secrets: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let metadata = event.metadata
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: "\n")
    let publicText = [
      event.id,
      event.messageId,
      event.content,
      event.contentRef,
      event.conversationTitle,
      event.topicHints.sorted().joined(separator: "\n"),
      metadata
    ].joined(separator: "\n")

    for secret in secrets where !secret.isEmpty {
      XCTAssertFalse(
        publicText.contains(secret),
        "Capability observation exposed secret: \(secret)",
        file: file,
        line: line
      )
    }
  }

  private func runStartRequest(
    conversationId: String = "conversation",
    messageId: String = "message",
    taskId: String = "task",
    runId: String = "run",
    parentRunId: String = "",
    goal: String = "execute once",
    deliveryMode: AgentDeliveryMode = .respond,
    requiredCapabilities: Set<AgentCapability> = [.chat, .code],
    context: AgentMcpJSONObject = ["z": .int(2), "a": .string("x")],
    idempotencyKey: String = "key",
    createdAtMillis: Int64 = 0
  ) -> AgentRunRequest {
    AgentRunRequest(
      conversationId: conversationId,
      messageId: messageId,
      taskId: taskId,
      runId: runId,
      parentRunId: parentRunId,
      goal: goal,
      deliveryMode: deliveryMode,
      requiredCapabilities: requiredCapabilities,
      context: context,
      idempotencyKey: idempotencyKey,
      createdAtMillis: createdAtMillis
    )
  }

  private func teamBridgePlan(_ actions: AgentAction...) -> AgentPlan {
    teamBridgePlan(goal: "Research and synthesize a verified answer", actions)
  }

  private func teamBridgePlan(goal: String, _ actions: AgentAction...) -> AgentPlan {
    teamBridgePlan(goal: goal, actions)
  }

  private func teamBridgePlan(goal: String, _ actions: [AgentAction]) -> AgentPlan {
    var plan = AgentPlan(
      goal: goal,
      screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: AgentRoute(kind: .desktopAgent)
    )
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  private func teamAgentAction(
    _ id: String,
    _ connectorId: String,
    dependsOn: [String] = [],
    outputSources: [String] = []
  ) -> AgentAction {
    teamConnectorAction(id, connectorId, kind: .agent, dependsOn: dependsOn, outputSources: outputSources)
  }

  private func teamConnectorAction(
    _ id: String,
    _ connectorId: String,
    kind: AgentConnectorKind = .agent,
    dependsOn: [String] = [],
    outputSources: [String] = []
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .callConnector,
      target: connectorId,
      risk: .medium,
      status: .pendingConfirmation,
      description: "Run \(id)",
      parameters: [
        "connector_id": connectorId,
        "prompt": "Complete \(id)",
        "node_ref": id,
        "depends_on": dependsOn.joined(separator: ","),
        "use_outputs_from": outputSources.joined(separator: ","),
        "_signalasi_conversation_id": "conversation",
        "_signalasi_turn_id": "turn",
        "connector_kind": kind.rawValue
      ]
    )
  }

  private func teamActionWithAgentKnowledge(_ action: AgentAction, _ value: String) -> AgentAction {
    var copy = action
    copy.parameters["_signalasi_agent_knowledge_context"] = value
    return copy
  }

  private func teamTargets() -> [AgentCallableTarget] {
    [
      teamTarget("researcher", kind: .agent, capability: .research),
      teamTarget("reviewer", kind: .agent, capability: .research),
      teamTarget("lead", kind: .agent, capability: .reasoning)
    ]
  }

  private func teamTarget(
    _ id: String,
    kind: AgentConnectorKind,
    capability: AgentCapability = .chat
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: id,
      kind: kind,
      status: .available,
      capabilities: [capability]
    )
  }

  private func teamRegistration(_ target: AgentCallableTarget) -> AgentRegistration {
    networkRegistration(
      agentId: target.id,
      displayName: target.title,
      capabilities: Set(target.capabilities),
      failureDomain: target.failureDomain,
      adapterType: target.adapterType
    )
  }

  private var crossTeamNow: Int64 { 2_000_000 }
  private var crossTeamSourceTeam: String { "team-source" }
  private var crossTeamDestinationTeamId: String { "team-destination" }

  private func crossTeamFixture() -> CrossTeamFixture {
    let grants = InMemoryAgentPermissionGrantStore(nowMillis: { self.crossTeamNow })
    let firewall = AgentPersonalPolicyFirewall(
      grantStore: grants,
      replayStore: InMemoryAgentPolicyReplayStore(),
      auditStore: InMemoryAgentPolicyFirewallAuditStore(),
      clock: { self.crossTeamNow }
    )
    return CrossTeamFixture(
      grants: grants,
      coordinator: AgentCrossTeamDelegationCoordinator(
        firewall: firewall,
        store: InMemoryAgentCrossTeamDelegationStore(),
        clock: { self.crossTeamNow }
      )
    )
  }

  private func crossTeamInput(
    delegationId: String = "delegation-one",
    nonce: String = "delegation-nonce-0001",
    goal: String = "Complete the delegated analysis",
    constraints: [String] = [],
    expectedOutput: String = "",
    evidence: [AgentDelegationEvidence] = [],
    artifacts: [AgentDelegationArtifactManifest] = [],
    delegationDepth: Int = 1,
    secureTransport: Bool = true
  ) -> AgentCrossTeamDelegationInput {
    AgentCrossTeamDelegationInput(
      delegationId: delegationId,
      nonce: nonce,
      sourceTeamId: crossTeamSourceTeam,
      sourceRunId: "source-run",
      requesterAgentId: "signalasi-mobile",
      goal: goal,
      constraints: constraints,
      expectedOutput: expectedOutput,
      requiredCapabilities: [.chat],
      evidence: evidence,
      artifacts: artifacts,
      delegationDepth: delegationDepth,
      secureTransport: secureTransport,
      identityProofVerified: true,
      createdAtMillis: crossTeamNow,
      expiresAtMillis: crossTeamNow + 60_000
    )
  }

  private func crossTeamDestinationTeam(includeObserver: Bool = false) -> AgentTeamDefinition {
    var members = [
      AgentTeamMember(
        agentId: "codex-destination",
        deliveryMode: .respond,
        requiredCapabilities: [.chat],
        role: "lead synthesizer",
        objective: "",
        dependsOnAgentIds: [],
        context: [:]
      )
    ]
    if includeObserver {
      members.append(AgentTeamMember(
        agentId: "hermes-observer",
        deliveryMode: .observe,
        requiredCapabilities: [],
        role: "research specialist",
        objective: "",
        dependsOnAgentIds: [],
        context: [:]
      ))
    }
    return AgentTeamDefinition(
      teamId: crossTeamDestinationTeamId,
      primaryAgentId: "codex-destination",
      members: members,
      visibilityMode: .background,
      collectiveCapabilities: [.chat]
    )
  }

  private func crossTeamRegistrations(includeObserver: Bool = false) -> [AgentRegistration] {
    var registrations = [
      networkRegistration(
        agentId: "codex-destination",
        displayName: "codex-destination",
        providerId: "codex",
        deviceId: "device-codex-destination",
        capabilities: [.chat],
        trust: .verifiedPaired
      )
    ]
    if includeObserver {
      registrations.append(networkRegistration(
        agentId: "hermes-observer",
        displayName: "hermes-observer",
        providerId: "hermes",
        deviceId: "device-hermes-observer",
        capabilities: [.chat],
        trust: .verifiedPaired
      ))
    }
    return registrations
  }

  private func crossTeamGrant(
    subjectId: String,
    lifetime: AgentPermissionGrantLifetime
  ) -> AgentPermissionGrant {
    AgentPermissionGrant(
      grantId: "grant-\(subjectId)",
      subjectType: .agent,
      subjectId: subjectId,
      scope: AgentPersonalPolicyFirewall.DELEGATION_SCOPE,
      action: "outbound",
      resource: crossTeamSourceTeam,
      target: crossTeamDestinationTeamId,
      issuer: .user,
      evidence: "user-confirmed",
      lifetime: lifetime,
      maxUses: lifetime == .singleUse ? 1 : 0,
      createdAtMillis: crossTeamNow,
      expiresAtMillis: lifetime == .temporary ? crossTeamNow + 60_000 : 0
    )
  }

  private struct CrossTeamFixture {
    var grants: InMemoryAgentPermissionGrantStore
    var coordinator: AgentCrossTeamDelegationCoordinator
  }

  private func riskHardenerAction(
    id: String,
    kind: AgentActionKind,
    risk: AgentRisk = .low,
    target: String = "iOS",
    description: String? = nil,
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: risk,
      status: .pendingConfirmation,
      description: description ?? "Harden \(id)",
      parameters: parameters
    )
  }

  private func riskHardenerPlan(_ actions: [AgentAction]) -> AgentPlan {
    var plan = AgentPlan(
      goal: "Harden action risks",
      screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: AgentRoute(kind: .deviceConnector)
    )
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  private func agentScreenElement(
    label: String,
    viewId: String,
    className: String,
    bounds: String,
    origin: AgentElementOrigin = .accessibility,
    confidence: Double = 1,
    visualRole: AgentVisualRole = .unknown,
    actionable: Bool = true
  ) -> AgentScreenElement {
    AgentScreenElement(
      label: label,
      viewId: viewId,
      className: className,
      bounds: bounds,
      origin: origin,
      confidence: confidence,
      visualRole: visualRole,
      actionable: actionable
    )
  }

  private var globalBudgetNow: Int64 { 1_000_000 }
  private var globalBudgetLeaseMillis: Int64 { 60_000 }

  private func acquireModelCall(
    _ state: GlobalModelCallBudgetState,
    _ ownerKey: String,
    kind: GlobalModelCallKind = .cognition,
    dailyLimit: Int = 48,
    concurrencyLimit: Int = 3,
    nowMillis: Int64? = nil,
    resourceId: String = "",
    estimatedInputTokens: Int64 = 0,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) -> GlobalModelCallBudgetDecision {
    GlobalModelCallBudgetPolicy.acquire(
      state: state,
      leaseId: GlobalModelCallBudgetPolicy.leaseId(kind: kind, ownerKey: ownerKey),
      kind: kind,
      ownerKey: ownerKey,
      leaseMillis: globalBudgetLeaseMillis,
      dailyLimit: dailyLimit,
      concurrencyLimit: concurrencyLimit,
      nowMillis: nowMillis ?? globalBudgetNow,
      resourceId: resourceId,
      estimatedInputTokens: estimatedInputTokens,
      dailyTokenLimit: dailyTokenLimit,
      dailyReportedCostLimitMicros: dailyReportedCostLimitMicros
    )
  }

  private func assertToolHandleError(
    _ code: String,
    retryable: Bool = false,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Void
  ) {
    do {
      try body()
      XCTFail("Expected AgentExplicitToolHandleError.", file: file, line: line)
    } catch let error as AgentExplicitToolHandleError {
      XCTAssertEqual(error.code, code, file: file, line: line)
      XCTAssertEqual(error.retryable, retryable, file: file, line: line)
    } catch {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }

  private func agentRecoveryAction(
    id: String,
    kind: AgentActionKind,
    risk: AgentRisk
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "iOS",
      risk: risk,
      status: .failed,
      description: "Recover \(kind.rawValue)"
    )
  }

  private func phoneAuthorityAction(
    id: String,
    kind: AgentActionKind,
    taskId: String
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: "SignalASI",
      risk: .low,
      status: .pendingConfirmation,
      description: id,
      parameters: ["_signalasi_task_id": taskId]
    )
  }

  private func phoneAuthorityScreen() -> AgentScreenContext {
    AgentScreenContext(
      foregroundApp: "SignalASI",
      pageTitle: "Agent",
      visibleTextCount: 3,
      clickableNodeCount: 2,
      isAccessibilityEnabled: true
    )
  }

  private func agentAutonomyAction(
    id: String,
    kind: AgentActionKind = .openApp,
    status: AgentActionStatus,
    package: String = "com.signalasi.chat",
    connectorId: String = "",
    url: String = "",
    prompt: String = ""
  ) -> AgentAction {
    var parameters: [String: String] = [:]
    if !package.isEmpty { parameters["package"] = package }
    if !connectorId.isEmpty { parameters["connector_id"] = connectorId }
    if !url.isEmpty { parameters["url"] = url }
    if !prompt.isEmpty { parameters["prompt"] = prompt }
    return AgentAction(
      id: id,
      kind: kind,
      target: "SignalASI",
      risk: .low,
      status: status,
      description: id,
      parameters: parameters
    )
  }

  private func agentAutonomyPlan(
    actions: [AgentAction],
    actionHistory: [AgentAction] = []
  ) -> AgentPlan {
    AgentPlan(
      goal: "Review autonomy guard",
      screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      actionHistory: actionHistory
    )
  }

  private func nativeToolDescriptor(
    _ id: String,
    risk: AgentNativeToolRisk = .low,
    availability: AgentNativeToolAvailability = .available,
    capabilities: Set<String> = ["test.execute"],
    requiredPermissions: [AgentNativePermissionRequirement] = [],
    requiredConsents: [AgentNativeConsentRequirement] = [],
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    outputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    timeoutMillis: Int64 = AgentNativeToolDescriptor.defaultTimeoutMillis,
    idempotency: AgentNativeToolIdempotency = .nonIdempotent
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Test capability",
      location: .application,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      risk: risk,
      capabilities: capabilities,
      requiredPermissions: requiredPermissions,
      requiredConsents: requiredConsents,
      timeoutMillis: timeoutMillis,
      idempotency: idempotency,
      availability: availability
    )
  }

  private func readyPhoneCapabilityStatuses() -> [AgentPhoneCapabilityStatus] {
    AgentPhoneCapabilityCatalog.capabilities.map { boundary in
      AgentPhoneCapabilityStatus(
        boundary: boundary,
        availability: .ready,
        evidence: "Ready for test"
      )
    }
  }

  private func nativeToolResult(
    status: AgentNativeToolResultStatus = .succeeded,
    invocationId: String,
    idempotencyKey: String?,
    replayed: Bool = false,
    verification: AgentNativeToolVerification? = nil
  ) -> AgentNativeToolResult {
    AgentNativeToolResult(
      status: status,
      output: [
        "ok": .bool(status == .succeeded),
        "invocation_id": .string(invocationId)
      ],
      message: status == .succeeded ? "Done" : "Failed",
      metadata: ["platform": .string("ios")],
      error: status == .succeeded ? nil : AgentNativeToolError(
        code: "test_failure",
        message: "Failed",
        retryable: false
      ),
      verification: verification,
      receipt: AgentNativeToolReceipt(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        startedAtEpochMillis: 1_000,
        finishedAtEpochMillis: 1_050,
        durationMillis: 50,
        status: status,
        inputSha256: String(repeating: "a", count: 64),
        outputSha256: String(repeating: "b", count: 64),
        replayed: replayed
      ),
      provenance: AgentNativeToolProvenance(
        toolId: "signalasi.test.native",
        toolVersion: "1.0.0",
        location: .application,
        executorId: "ios-native",
        contractVersion: "signalasi.native-tool/1.0",
        metadata: ["platform": "ios"]
      )
    )
  }

  private func agentObservation(
    _ decision: AgentObservationDecision,
    sampleCount: Int = 1,
    durationMillis: Int64 = 0,
    changed: Bool = false,
    stable: Bool = false
  ) -> AgentObservationOutcome {
    AgentObservationOutcome(
      screen: AgentScreenContext(
        foregroundApp: "SpringBoard",
        pageTitle: "Home",
        visibleTextCount: 3,
        clickableNodeCount: 2,
        isAccessibilityEnabled: true
      ),
      decision: decision,
      sampleCount: sampleCount,
      durationMillis: durationMillis,
      screenChanged: changed,
      screenStable: stable,
      evidence: "decision=\(decision.rawValue); samples=\(sampleCount)"
    )
  }

  private func agentObservationScreen(
    pageTitle: String,
    visibleTextCount: Int,
    selectedText: String = "",
    clickableNodeCount: Int = 2,
    inputFieldCount: Int = 0,
    scrollableRegionCount: Int = 0
  ) -> AgentScreenContext {
    AgentScreenContext(
      foregroundApp: "SpringBoard",
      activityName: "MainActivity",
      pageTitle: pageTitle,
      visibleTextCount: visibleTextCount,
      clickableNodeCount: clickableNodeCount,
      inputFieldCount: inputFieldCount,
      scrollableRegionCount: scrollableRegionCount,
      selectedText: selectedText,
      isAccessibilityEnabled: true
    )
  }

  private func agentLivenessPolicy() -> AgentTaskLivenessPolicy {
    AgentTaskLivenessPolicy(
      queuedWarningMillis: 10,
      queuedTimeoutMillis: 20,
      runningWarningMillis: 100,
      runningTimeoutMillis: 200,
      waitingResponseWarningMillis: 300,
      waitingResponseTimeoutMillis: 400,
      absoluteTimeoutMillis: 1_000,
      watchdogIntervalMillis: 60_000,
      heartbeatWriteThrottleMillis: 0
    )
  }

  private func runtimeCatalog(
    now: Int64,
    entries: [AgentRuntimePackCatalogEntry]
  ) -> AgentRuntimePackCatalog {
    AgentRuntimePackCatalog(
      catalogVersion: "1.0.0",
      generatedAtMillis: now - 1_000,
      expiresAtMillis: now + 60_000,
      entries: entries,
      signatureKeyId: String(repeating: "a", count: 64),
      signature: "signed"
    )
  }

  private func runtimeCatalogEntry(
    packId: String,
    architecture: String,
    dependencies: [String] = []
  ) -> AgentRuntimePackCatalogEntry {
    AgentRuntimePackCatalogEntry(
      packId: packId,
      version: "1.0.0",
      architecture: architecture,
      downloadUrl: "https://downloads.example.com/\(packId).sarpack",
      archiveSha256: String(repeating: "b", count: 64),
      archiveSizeBytes: 1_024,
      installedSizeBytes: 2_048,
      dependencies: dependencies,
      license: "Apache-2.0",
      minimumHostVersionCode: 1,
      guestApiVersion: AgentRuntimeGuestProtocol.version
    )
  }

  private func embeddedRuntimeIndexJson() -> String {
    """
    {"format_version":1,"architecture":"arm64-v8a","packs":[
      {"pack_id":"linux-base","version":"1.0.0","architecture":"arm64-v8a","asset_path":"runtime/bootstrap/linux-base.sarpack","archive_sha256":"\(String(repeating: "A", count: 64))","archive_size_bytes":1024,"installed_size_bytes":2048,"dependencies":[]},
      {"pack_id":"python-uv","version":"1.0.0","architecture":"arm64-v8a","asset_path":"runtime/bootstrap/python-uv.sarpack","archive_sha256":"\(String(repeating: "b", count: 64))","archive_size_bytes":2048,"installed_size_bytes":4096,"dependencies":["linux-base"]}
    ]}
    """
  }

  private func agentWorkspace(
    status: AgentWorkspaceStatus,
    events: [AgentWorkspaceEvent] = [],
    cancellationRequested: Bool = false
  ) -> AgentWorkspace {
    AgentWorkspace(
      workspaceId: "workspace",
      sessionId: "session",
      conversationId: "conversation",
      taskId: "task",
      status: status,
      eventSequence: events.map(\.sequence).max() ?? 0,
      eventJournal: events,
      cancellationRequested: cancellationRequested,
      createdAtMillis: 1_000,
      updatedAtMillis: events.map(\.timestampMillis).max() ?? 1_000
    )
  }

  private func agentWorkspaceEvent(
    _ sequence: Int64,
    _ kind: String,
    _ timestampMillis: Int64
  ) -> AgentWorkspaceEvent {
    AgentWorkspaceEvent(
      sequence: sequence,
      kind: kind,
      timestampMillis: timestampMillis
    )
  }

  private func lifecycleAction(
    id: String,
    kind: AgentActionKind,
    target: String,
    status: AgentActionStatus,
    result: String = ""
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: .low,
      status: status,
      description: id,
      result: result
    )
  }

  private func lifecyclePlan(_ actions: AgentAction...) -> AgentPlan {
    let needsRoute = actions.contains {
      $0.kind == .callConnector || $0.kind == .controlDevice
    }
    return AgentPlan(
      goal: "Correct the worksheet",
      screen: AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent"),
      steps: [],
      actions: actions,
      route: needsRoute ? AgentRoute(kind: .desktopAgent, targetTitle: "Codex") : AgentRoute()
    )
  }

  private func lifecycleSession(
    phase: AgentPhase,
    plan: AgentPlan,
    result: AgentActionResult?,
    auditTrail: [AgentAuditEntry] = []
  ) -> AgentSessionSnapshot {
    AgentSessionSnapshot(
      sessionId: "session",
      phase: phase,
      currentGoal: plan.goal,
      currentScreen: plan.screen,
      currentPlan: plan,
      auditTrail: auditTrail,
      lastActionResult: result,
      updatedAtMillis: 1
    )
  }

  private func agentTaskRecord(
    taskId: String = "task",
    sessionId: String = "conversation",
    goal: String = "goal",
    phase: AgentPhase = .executing,
    routeKind: AgentRouteKind = .desktopAgent,
    targetTitle: String = "Codex",
    risk: AgentRisk = .low,
    blocked: Bool = false,
    result: String = "",
    verification: String = "",
    outputFiles: [String] = [],
    executionLog: [String] = [],
    createdAtMillis: Int64 = 1,
    updatedAtMillis: Int64 = 1
  ) -> AgentTaskRecord {
    AgentTaskRecord(
      taskId: taskId,
      sessionId: sessionId,
      goal: goal,
      phase: phase,
      routeKind: routeKind,
      targetTitle: targetTitle,
      risk: risk,
      blocked: blocked,
      result: result,
      verification: verification,
      outputFiles: outputFiles,
      executionLog: executionLog,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis
    )
  }

  private func terminalReplyTranscript(
    role: AgentTranscriptRole,
    dedupeKey: String,
    turnId: String,
    taskId: String? = nil
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: "\(role.rawValue)-\(dedupeKey)",
      role: role,
      text: "message",
      timestampMillis: 1_000,
      dedupeKey: dedupeKey,
      conversationId: "conversation",
      turnId: turnId,
      taskId: taskId ?? turnId
    )
  }

  private func agentConversation(
    id: String,
    title: String,
    summary: String = "",
    status: AgentConversationStatus = .active,
    createdByAgent: Bool = false,
    parentConversationId: String = "",
    privateMode: Bool = false,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0
  ) -> AgentConversation {
    AgentConversation(
      id: id,
      title: title,
      createdAt: 1,
      updatedAt: 1,
      summary: summary,
      status: status,
      privateMode: privateMode,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      costMicros: costMicros,
      createdByAgent: createdByAgent,
      parentConversationId: parentConversationId
    )
  }

  private func agentMergeEntry(
    id: String,
    role: AgentTranscriptRole,
    conversationId: String,
    text: String,
    dedupeKey: String = "",
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text,
      timestampMillis: Int64(id.count),
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      turnId: "turn",
      taskId: "task",
      richOutputJson: richOutputJson
    )
  }

  private func loopEvent(
    _ phase: AgentExecutionLoopPhase,
    previousPhase: AgentExecutionLoopPhase? = nil,
    actionId: String = "",
    toolCall: Bool = false,
    retry: Bool = false,
    revision: Int64 = 1,
    usage: AgentExecutionLoopUsage = AgentExecutionLoopUsage(),
    reason: String = ""
  ) -> AgentExecutionLoopEvent {
    AgentExecutionLoopEvent(
      previousPhase: previousPhase,
      phase: phase,
      reason: reason,
      snapshot: AgentExecutionLoopSnapshot(
        taskId: "task",
        phase: phase,
        usage: usage,
        lastActionId: actionId,
        startedAtMillis: 1_000,
        updatedAtMillis: 1_000,
        revision: revision
      ),
      toolCall: toolCall,
      retry: retry
    )
  }

  private func runControlEvent(
    type: AgentRunControlEventType,
    toolCallId: String = "",
    sequence: Int64 = 1,
    payload: AgentRunControlPayload = [:]
  ) -> AgentRunControlEvent {
    AgentRunControlEvent(
      eventId: "event",
      conversationId: "conversation",
      messageId: "turn",
      taskId: "task",
      runId: "run",
      toolCallId: toolCallId,
      agentId: "signalasi-mobile",
      deviceId: "phone",
      type: type,
      sequence: sequence,
      payload: payload
    )
  }

  private func runControlSnapshot(
    state: AgentRunControlState,
    sequence: Int64 = 4
  ) -> AgentRunControlSnapshot {
    AgentRunControlSnapshot(
      runId: "run",
      taskId: "task",
      state: state,
      agentId: "codex",
      deviceId: "desktop",
      lastSequence: sequence,
      lastEvent: runControlEvent(type: .waitingForDevice, sequence: sequence)
    )
  }

  private func runRecoveryRegistration(
    agentId: String = "codex",
    location: AgentResourceLocation = .trustedDesktop,
    connectionKind: AgentConnectionKind = .signalasiLink
  ) -> AgentRunRecoveryRegistration {
    AgentRunRecoveryRegistration(
      agentId: agentId,
      location: location,
      connectionKind: connectionKind
    )
  }

  private func proactiveIntervalTask(
    taskId: String = "test-task",
    policy: AgentProactivePolicy,
    nextRunAtMillis: Int64,
    runCount: Int = 0,
    consecutiveFailures: Int = 0
  ) throws -> AgentProactiveTask {
    try AgentProactiveTask(
      taskId: taskId,
      name: "Test task",
      trigger: try AgentProactiveTrigger(
        kind: .interval,
        intervalSeconds: 60
      ),
      action: try AgentProactiveAction(
        kind: .agent,
        targetId: "codex",
        prompt: "Check status"
      ),
      policy: policy,
      nextRunAtMillis: nextRunAtMillis,
      runCount: runCount,
      consecutiveFailures: consecutiveFailures
    )
  }

  private func globalProactiveMessage(
    _ id: String,
    target: GlobalProactiveTarget = .currentConversation,
    status: GlobalProactiveMessageStatus = .delivered,
    title: String = "SignalASI insight",
    content: String = "A material result is ready.",
    topic: String = "SignalASI autonomy",
    urgent: Bool = false,
    deliveredAtMillis: Int64 = 2_000,
    deliveredConversationId: String = "destination",
    deliveryGroupId: String? = nil,
    viewedAtMillis: Int64 = 0
  ) -> GlobalProactiveMessage {
    GlobalProactiveMessage(
      id: id,
      sourceEventId: "event-\(id)",
      sourceConversationId: "source",
      target: target,
      title: title,
      content: content,
      topic: topic,
      urgent: urgent,
      status: status,
      createdAtMillis: 1_000,
      deliveredAtMillis: deliveredAtMillis,
      deliveredConversationId: deliveredConversationId,
      deliveryGroupId: deliveryGroupId ?? id,
      viewedAtMillis: viewedAtMillis
    )
  }

  private func globalAgentFeedback(
    messageId: String,
    kind: GlobalAgentFeedbackKind,
    createdAtMillis: Int64 = 3_000
  ) -> GlobalAgentFeedback {
    GlobalAgentFeedback(
      proactiveMessageId: messageId,
      deliveryGroupId: messageId,
      conversationId: "destination",
      topic: "SignalASI autonomy",
      target: .currentConversation,
      kind: kind,
      createdAtMillis: createdAtMillis
    )
  }

  private func mcpAuditRecord(
    _ auditId: String,
    connectionId: String,
    timestampMillis: Int64
  ) -> AgentMcpAuditRecord {
    AgentMcpAuditRecord(
      auditId: auditId,
      timestampMillis: timestampMillis,
      connectionId: connectionId,
      connectionName: "Relay",
      toolName: "relay.switch",
      transport: "streamable_http",
      source: "ios-mcp:\(connectionId)",
      callerId: "planner",
      taskId: "task-\(auditId)",
      conversationId: "chat",
      risk: "medium",
      permissions: ["mcp.network.connect", "mcp.data.write"],
      permissionMode: "ask_for_changes",
      permissionDecision: "allowed_explicit_change",
      parameterPreview: ["enabled": .bool(true)],
      inputSha256: String(repeating: "a", count: 64),
      status: "succeeded",
      durationMillis: 10
    )
  }

  private func mcpTool(
    _ name: String,
    readOnly: Bool? = nil,
    destructive: Bool? = nil
  ) -> AgentMcpTool {
    var annotations: AgentMcpJSONObject = [:]
    if let readOnly {
      annotations["readOnlyHint"] = .bool(readOnly)
    }
    if let destructive {
      annotations["destructiveHint"] = .bool(destructive)
    }
    return AgentMcpTool(
      name: name,
      inputSchema: [:],
      annotations: annotations,
      raw: ["name": .string(name)]
    )
  }

  private func mcpDeclarativePackageManifest() -> String {
    #"""
    {
      "format_version": 1,
      "id": "example.relay",
      "version": "1.0.0",
      "name": "Relay Controller",
      "description": "Authenticated relay control",
      "catalog_id": "signalasi.mcp.relay",
      "author": "SignalASI",
      "website": "https://relay.example",
      "transport": {
        "type": "declarative_http",
        "endpoint": "https://relay.example/api/"
      },
      "authentication": [
        {
          "method": "dynamic",
          "access_token_ttl_seconds": 86400,
          "steps": [
            {
              "id": "login",
              "title": "Sign in",
              "fields": [
                {"id": "username", "label": "Username", "type": "text"},
                {"id": "password", "label": "Password", "type": "password"}
              ],
              "exchange": {
                "method": "POST",
                "path": "/api/login",
                "body_template": "{\"username\":{{field.username}},\"password\":{{field.password}}}",
                "response_mappings": {
                  "access_token": "$.session.access_token"
                },
                "accepted_status_codes": [200, 201]
              }
            }
          ]
        }
      ],
      "tools": [
        {
          "name": "relay.switch",
          "title": "Switch relay",
          "description": "Turns a relay on or off",
          "input_schema": {
            "type": "object",
            "properties": {
              "device_id": {"type": "string"},
              "enabled": {"type": "boolean"}
            },
            "required": ["device_id", "enabled"]
          },
          "request": {
            "method": "POST",
            "path": "/api/relay/{{args.device_id}}",
            "headers": {
              "Authorization": "Bearer {{auth.access_token}}"
            },
            "body_template": "{\"enabled\":{{args.enabled}}}"
          },
          "result_json_path": "$.relay",
          "mutating": true
        }
      ]
    }
    """#
  }

  private func mcpLocalStdioPackageManifest(
    entrypoint: String = "runtime/server.py",
    authentication: String = #"[{"method":"bearer_token"}]"#,
    allowedNetworkDomains: String = ""
  ) -> String {
    let domains = allowedNetworkDomains.isEmpty ? "[]" : "[\(allowedNetworkDomains)]"
    return #"""
    {
      "format_version": 1,
      "id": "example.local_mcp",
      "version": "1.0.0",
      "name": "Local MCP",
      "description": "Runs inside the on-device Linux sandbox",
      "transport": {
        "type": "local_stdio",
        "runtime": "python",
        "entrypoint": "\#(entrypoint)",
        "arguments": ["--stdio"],
        "environment": {
          "ACCESS_TOKEN": "{{auth.access_token}}"
        },
        "allowed_network_domains": \#(domains),
        "timeout_ms": 45000
      },
      "authentication": \#(authentication),
      "tools": []
    }
    """#
  }

  private func mcpPackageIntegrity(for manifest: String) -> String {
    let digest = AgentMcpPackageInstaller.sha256(Data(manifest.utf8))
    return #"{"manifest_sha256":"\#(digest)"}"#
  }

  private func temporaryDirectory(_ label: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("signalasi-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func relativeFile(_ relative: String, under root: URL) -> URL {
    relative
      .split(separator: "/")
      .map(String.init)
      .reduce(root) { partial, segment in
        partial.appendingPathComponent(segment)
      }
  }

  private func storedMcpPackage(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, data: Data, crc32: UInt32, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let crc = mcpPackageCRC32(body)
      let size = UInt32(body.count)
      let localOffset = output.count
      appendMcpZipUInt32LE(0x04034b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(crc, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(body)
      centralRecords.append((file.0, body, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      let size = UInt32(record.data.count)
      appendMcpZipUInt32LE(0x02014b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(record.crc32, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt32LE(size, to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(0, to: &output)
      appendMcpZipUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendMcpZipUInt32LE(0x06054b50, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt32LE(UInt32(centralSize), to: &output)
    appendMcpZipUInt32LE(UInt32(centralStart), to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    return output
  }

  private func deflatedZipArchive(_ files: (String, String)...) -> Data {
    var output = Data()
    var centralRecords: [(name: String, body: Data, compressed: Data, crc32: UInt32, localOffset: Int)] = []
    for file in files {
      let nameBytes = Data(file.0.utf8)
      let body = Data(file.1.utf8)
      let compressed = rawDeflateStoredBlocks(body)
      let crc = mcpPackageCRC32(body)
      let localOffset = output.count
      appendMcpZipUInt32LE(0x04034b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(8, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(crc, to: &output)
      appendMcpZipUInt32LE(UInt32(compressed.count), to: &output)
      appendMcpZipUInt32LE(UInt32(body.count), to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      output.append(nameBytes)
      output.append(compressed)
      centralRecords.append((file.0, body, compressed, crc, localOffset))
    }
    let centralStart = output.count
    for record in centralRecords {
      let nameBytes = Data(record.name.utf8)
      appendMcpZipUInt32LE(0x02014b50, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(20, to: &output)
      appendMcpZipUInt16LE(0x0800, to: &output)
      appendMcpZipUInt16LE(8, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(record.crc32, to: &output)
      appendMcpZipUInt32LE(UInt32(record.compressed.count), to: &output)
      appendMcpZipUInt32LE(UInt32(record.body.count), to: &output)
      appendMcpZipUInt16LE(UInt16(nameBytes.count), to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt16LE(0, to: &output)
      appendMcpZipUInt32LE(0, to: &output)
      appendMcpZipUInt32LE(UInt32(record.localOffset), to: &output)
      output.append(nameBytes)
    }
    let centralSize = output.count - centralStart
    appendMcpZipUInt32LE(0x06054b50, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt16LE(UInt16(centralRecords.count), to: &output)
    appendMcpZipUInt32LE(UInt32(centralSize), to: &output)
    appendMcpZipUInt32LE(UInt32(centralStart), to: &output)
    appendMcpZipUInt16LE(0, to: &output)
    return output
  }

  private func rawDeflateStoredBlocks(_ data: Data) -> Data {
    var output = Data()
    var offset = 0
    repeat {
      let count = min(data.count - offset, 0xffff)
      let finalBlock = offset + count == data.count
      output.append(finalBlock ? 0x01 : 0x00)
      appendMcpZipUInt16LE(UInt16(count), to: &output)
      appendMcpZipUInt16LE(~UInt16(count), to: &output)
      output.append(data.subdata(in: offset..<(offset + count)))
      offset += count
    } while offset < data.count
    return output
  }

  private func appendMcpZipUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00ff))
    data.append(UInt8((value >> 8) & 0x00ff))
  }

  private func appendMcpZipUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000ff))
    data.append(UInt8((value >> 8) & 0x000000ff))
    data.append(UInt8((value >> 16) & 0x000000ff))
    data.append(UInt8((value >> 24) & 0x000000ff))
  }

  private func mcpPackageCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.mcpPackageCRC32Table[index]
    }
    return crc ^ 0xffffffff
  }

  private static let mcpPackageCRC32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()

  private func transcriptEntry(
    _ id: String,
    role: AgentTranscriptRole = .process,
    conversationId: String = "conversation",
    turnId: String = "turn",
    timestampMillis: Int64 = 1,
    text: String? = nil,
    dedupeKey: String = "",
    taskId: String = "task",
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text ?? id,
      timestampMillis: timestampMillis,
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      turnId: turnId,
      taskId: taskId,
      richOutputJson: richOutputJson
    )
  }

  private func richDocument(_ blocks: [[String: Any]]) -> String {
    let data = try! JSONSerialization.data(
      withJSONObject: ["version": 1, "blocks": blocks],
      options: [.sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
  }

  private func richBlocks(_ raw: String) throws -> [[String: Any]] {
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    return try XCTUnwrap(payload["blocks"] as? [[String: Any]])
  }

  private func finalTranscriptEntry(
    id: String,
    role: AgentTranscriptRole = .assistant,
    text: String = "CODEX_OK",
    turnId: String = "",
    taskId: String,
    dedupeKey: String,
    timestampMillis: Int64,
    richOutputJson: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: role,
      text: text,
      timestampMillis: timestampMillis,
      dedupeKey: dedupeKey,
      conversationId: "conversation",
      turnId: turnId,
      taskId: taskId,
      richOutputJson: richOutputJson
    )
  }

  private func makeFriendRequest(signalASIId: String, name: String) -> SignalASIFriendRequest {
    SignalASIFriendRequest(
      id: "req-\(signalASIId)",
      signalASIId: signalASIId,
      name: name,
      type: "person",
      identityPublicKey: "public-key-\(signalASIId)",
      identityFingerprint: String(repeating: "a", count: 64),
      mqttTopic: "signalasi/contact/\(signalASIId)",
      mqttInboxTopic: "signalasi/contact/\(signalASIId)/inbox"
    )
  }

  private func makePairingQRCode() -> PairingQRCode {
    PairingQRCode(
      desktopId: "desktop-1",
      desktopName: "SignalASI Desktop",
      desktopFingerprint: String(repeating: "f", count: 64),
      serverRouteId: "abcdefghijklmnopqrstuv",
      pairingTopic: "signalasi/pair",
      pairingToken: "pairing-token",
      pairingSecret: Data(repeating: 1, count: 32),
      access: PairingAccess(
        profile: SignalASILinkProtocol.accessDesktopExecutor,
        scopes: [SignalASILinkProtocol.scopeDesktopExecutor]
      ),
      controlAuthorizationToken: "control-token",
      raw: [:]
    )
  }
}

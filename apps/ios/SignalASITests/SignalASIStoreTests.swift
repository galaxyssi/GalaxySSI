import XCTest
@testable import SignalASI

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

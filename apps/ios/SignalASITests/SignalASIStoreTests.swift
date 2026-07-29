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

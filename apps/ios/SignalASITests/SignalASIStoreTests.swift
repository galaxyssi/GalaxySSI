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

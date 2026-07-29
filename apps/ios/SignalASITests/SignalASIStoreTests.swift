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

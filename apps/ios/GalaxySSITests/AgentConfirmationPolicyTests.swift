import XCTest
@testable import GalaxySSI

final class AgentConfirmationPolicyTests: XCTestCase {
  func testAgentConfirmationPolicyKeepsAndroidWireNames() throws {
    let decoded = try JSONDecoder.galaxySSI.decode(
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
          "tool_id": "galaxyssi.notifications.reply",
          "input_json": "{}"
        },
        "requires_confirmation": true
      }
      """.utf8)
    )
    let encoded = try JSONEncoder.galaxySSI.encode(decoded)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    XCTAssertEqual(decoded.kind, .callNativeTool)
    XCTAssertEqual(decoded.risk, .medium)
    XCTAssertEqual(decoded.status, .pendingConfirmation)
    XCTAssertEqual(object["kind"] as? String, "CALL_NATIVE_TOOL")
    XCTAssertEqual(object["requires_confirmation"] as? Bool, true)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: decoded), .confirmAlways)
  }

  func testAgentConfirmationPolicyDirectPhoneUtilitiesDoNotRequireConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "set-timer", kind: .setAlarm, description: "Set timer for 60 seconds")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "open-camera", kind: .openApp, description: "Open camera and take photo")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.android.audio.volume.set", "Set Android stream volume")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.android.wifi.hotspot.panel.open", "Open hotspot settings")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.hardware.bluetooth.pairing.handoff", "Open Bluetooth pairing settings")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.camera.capture.visible", "Capture a photo")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.media.ffmpeg.transcode", "Convert media locally")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.desktop.workspace.file.read.text", "Read an authorized Desktop file")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.desktop.workspace.file.write.text", "Write a bounded task workspace file")), .direct)
  }

  func testAgentConfirmationPolicySensitiveCapabilitiesRequireOneRememberedConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "location", kind: .callNativeTool, description: "Read location")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "download", kind: .callNativeTool, description: "Download file")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "contact-upsert", kind: .callNativeTool, description: "Create contact")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.hardware.bluetooth.discovery.foreground", "Discover nearby Bluetooth devices once")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.hardware.apps.installed.list", "List query-visible installed apps")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.microphone.record.visible", "Record audio")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.notifications.list", "Read notifications")), .confirmOnce)
  }

  func testAgentConfirmationPolicyConsequentialActionsRequireEveryConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "sms-send", kind: .callNativeTool, description: "Send SMS message")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "delete-file", kind: .callNativeTool, description: "Delete file")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "lock", kind: .lockScreen, description: "Lock device")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.notifications.reply", "Reply to a notification")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("galaxyssi.desktop.terminal.run", "Run a Desktop workspace command")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "submit-code", kind: .callConnector, description: "Git commit and push the code")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "system-settings", kind: .callConnector, description: "Change a system setting")), .confirmAlways)
  }

  func testAgentConfirmationPolicyRememberedNativeConsentKeysAreStable() {
    let firstBluetooth = nativeConfirmationAction(
      "galaxyssi.hardware.bluetooth.discovery.foreground",
      "Discover nearby Bluetooth devices once",
      id: "native-first"
    )
    let secondBluetooth = nativeConfirmationAction(
      "galaxyssi.hardware.bluetooth.discovery.foreground",
      "Scan for nearby Bluetooth devices",
      id: "native-second"
    )

    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), "bluetooth_discovery")
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), AgentConfirmationPolicy.consentKey(for: secondBluetooth))
  }

  func testAgentConfirmationPolicyHomeAssistantUsesAndroidConsentScope() {
    let homeAssistantInput = #"{"entity_id":"lock.front_door","service_domain":"lock","service":"unlock"}"#
    let homeAssistantAction = nativeConfirmationAction(
      "galaxyssi.home_assistant.service.call",
      "Unlock front door",
      inputJson: homeAssistantInput
    )

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: homeAssistantAction), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: homeAssistantAction), "home_assistant_control:lock.front_door")
  }

  func testAgentConfirmationPolicyIgnoresInternalContextForRisk() {
    let connectorAction = AgentAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      risk: .low,
      status: .pendingConfirmation,
      description: "Ask Codex",
      parameters: [
        "prompt": "Show an animated letter",
        "_galaxyssi_conversation_context": "Earlier the user asked to send a message"
      ]
    )

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: connectorAction), .direct)
  }

  func testAgentConfirmationConsentStoreUsesGrantLedgerScopes() throws {
    let grantStore = InMemoryAgentPermissionGrantStore(nowMillis: { 1_000 })
    let store = AgentGrantBackedConfirmationConsentStore(grantStore: grantStore)
    let unrelated = try grantStore.grant(AgentPermissionGrant(
      subjectType: .tool,
      subjectId: "tool-host",
      scope: "bluetooth_discovery",
      action: "bluetooth_discovery",
      issuer: .user,
      evidence: "tool_grant",
      lifetime: .permanent
    ))

    XCTAssertFalse(store.isRemembered(consentKey: " "))
    store.remember(consentKey: " bluetooth_discovery ")
    store.remember(consentKey: "bluetooth_discovery")

    XCTAssertTrue(store.isRemembered(consentKey: "bluetooth_discovery"))
    XCTAssertEqual(store.rememberedKeys(), Set(["bluetooth_discovery"]))
    let remembered = grantStore.list(includeInactive: false).filter { $0.subjectType == .consequentialAction }
    XCTAssertEqual(remembered.count, 1)
    XCTAssertEqual(remembered.first?.subjectId, "galaxyssi-host")
    XCTAssertEqual(remembered.first?.issuer, .user)
    XCTAssertEqual(remembered.first?.evidence, "user_confirmed_once")
    XCTAssertEqual(remembered.first?.lifetime, .permanent)

    XCTAssertTrue(store.forget(consentKey: "bluetooth_discovery"))
    XCTAssertFalse(store.isRemembered(consentKey: "bluetooth_discovery"))
    XCTAssertFalse(store.forget(consentKey: "bluetooth_discovery"))
    XCTAssertTrue(try grantStore.authorize(AgentPermissionRequest(
      subjectType: .tool,
      subjectId: "tool-host",
      scope: "bluetooth_discovery",
      action: "bluetooth_discovery"
    )).granted)
    XCTAssertEqual(grantStore.list(includeInactive: false).first { $0.grantId == unrelated.grantId }?.status, .active)
  }

  func testUserDefaultsAgentConfirmationConsentStorePersistsRememberedKeys() throws {
    let suite = "AgentConfirmationConsentStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = UserDefaultsAgentConfirmationConsentStore(defaults: defaults, nowMillis: { 1_000 })

    first.remember(consentKey: "home_assistant_control:light.office")

    let restored = UserDefaultsAgentConfirmationConsentStore(defaults: defaults, nowMillis: { 2_000 })
    XCTAssertTrue(restored.isRemembered(consentKey: "home_assistant_control:light.office"))
    XCTAssertEqual(restored.rememberedKeys(), Set(["home_assistant_control:light.office"]))
    XCTAssertTrue(restored.forget(consentKey: "home_assistant_control:light.office"))
    XCTAssertFalse(restored.isRemembered(consentKey: "home_assistant_control:light.office"))

    restored.remember(consentKey: "downloads")
    restored.remember(consentKey: "microphone")
    restored.clear()

    let afterClear = UserDefaultsAgentConfirmationConsentStore(defaults: defaults, nowMillis: { 3_000 })
    XCTAssertTrue(afterClear.rememberedKeys().isEmpty)
    XCTAssertFalse(afterClear.isRemembered(consentKey: "downloads"))
    XCTAssertFalse(afterClear.isRemembered(consentKey: "microphone"))
  }

  func testAgentConfirmationDecisionPolicyUsesRememberedConfirmOnceConsent() {
    let store = AgentGrantBackedConfirmationConsentStore()
    let bluetooth = nativeConfirmationAction(
      "galaxyssi.hardware.bluetooth.discovery.foreground",
      "Discover nearby Bluetooth devices once",
      id: "bluetooth"
    )
    let sms = nativeConfirmationAction("galaxyssi.notifications.reply", "Reply to notification", id: "reply")

    let first = AgentConfirmationDecisionPolicy.decision(
      actions: [bluetooth],
      permissionMode: .autoLowRisk,
      consentStore: store
    )
    AgentConfirmationDecisionPolicy.recordApproval(action: bluetooth, consentStore: store)
    let remembered = AgentConfirmationDecisionPolicy.decision(
      actions: [bluetooth],
      permissionMode: .autoLowRisk,
      consentStore: store
    )
    let always = AgentConfirmationDecisionPolicy.decision(
      actions: [sms],
      permissionMode: .autoLowRisk,
      consentStore: store
    )

    XCTAssertTrue(first.requiresConfirmation)
    XCTAssertFalse(remembered.requiresConfirmation)
    XCTAssertEqual(remembered.rememberedConsentKeys, ["bluetooth_discovery"])
    XCTAssertTrue(always.requiresConfirmation)
    XCTAssertEqual(always.alwaysConfirmActionIds, ["reply"])
  }

  func testAgentConfirmationDecisionPolicyMatchesAndroidPermissionModes() {
    let store = AgentGrantBackedConfirmationConsentStore()
    let direct = confirmationAction(id: "open-camera", kind: .openApp, description: "Open camera")
    let connector = confirmationAction(id: "connector", kind: .callConnector, description: "Ask paired Agent")
    let download = confirmationAction(id: "download", kind: .callNativeTool, description: "Download file")

    XCTAssertFalse(AgentConfirmationDecisionPolicy.decision(
      actions: [download],
      permissionMode: .observeOnly,
      consentStore: store
    ).requiresConfirmation)
    XCTAssertFalse(AgentConfirmationDecisionPolicy.decision(
      actions: [download],
      permissionMode: .suggestOnly,
      consentStore: store
    ).requiresConfirmation)
    XCTAssertFalse(AgentConfirmationDecisionPolicy.decision(
      actions: [direct, connector],
      permissionMode: .askBeforeAction,
      consentStore: store
    ).requiresConfirmation)
    XCTAssertTrue(AgentConfirmationDecisionPolicy.decision(
      actions: [download],
      permissionMode: .askBeforeAction,
      consentStore: store
    ).requiresConfirmation)
    XCTAssertEqual(AgentConfirmationDecisionPolicy.decision(
      actions: [download],
      permissionMode: .askBeforeAction,
      consentStore: store
    ).pendingActionIds, ["download"])
  }

  func testAgentConfirmationDecisionPolicyRecordsOnlyConfirmOnceApprovals() {
    let store = AgentGrantBackedConfirmationConsentStore()
    let direct = confirmationAction(id: "open-camera", kind: .openApp, description: "Open camera")
    let always = nativeConfirmationAction("galaxyssi.notifications.reply", "Reply to notification", id: "reply")
    let once = confirmationAction(id: "location", kind: .callNativeTool, description: "Read location")

    AgentConfirmationDecisionPolicy.recordApproval(action: direct, consentStore: store)
    AgentConfirmationDecisionPolicy.recordApproval(action: always, consentStore: store)
    AgentConfirmationDecisionPolicy.recordApproval(action: once, consentStore: store)

    XCTAssertEqual(store.rememberedKeys(), Set(["location"]))
  }

  private func confirmationAction(
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

  private func nativeConfirmationAction(
    _ toolId: String,
    _ description: String,
    id: String = "native-tool",
    inputJson: String = "{}"
  ) -> AgentAction {
    confirmationAction(
      id: id,
      kind: .callNativeTool,
      description: description,
      parameters: ["tool_id": toolId, "input_json": inputJson]
    )
  }
}

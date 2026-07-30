import XCTest
@testable import SignalASI

final class AgentConfirmationPolicyTests: XCTestCase {
  func testAgentConfirmationPolicyKeepsAndroidWireNames() throws {
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
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: decoded), .confirmAlways)
  }

  func testAgentConfirmationPolicyDirectPhoneUtilitiesDoNotRequireConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "set-timer", kind: .setAlarm, description: "Set timer for 60 seconds")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "open-camera", kind: .openApp, description: "Open camera and take photo")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.android.audio.volume.set", "Set Android stream volume")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.android.wifi.hotspot.panel.open", "Open hotspot settings")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.hardware.bluetooth.pairing.handoff", "Open Bluetooth pairing settings")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.camera.capture.visible", "Capture a photo")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.media.ffmpeg.transcode", "Convert media locally")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.desktop.workspace.file.read.text", "Read an authorized Desktop file")), .direct)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.desktop.workspace.file.write.text", "Write a bounded task workspace file")), .direct)
  }

  func testAgentConfirmationPolicySensitiveCapabilitiesRequireOneRememberedConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "location", kind: .callNativeTool, description: "Read location")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "download", kind: .callNativeTool, description: "Download file")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "contact-upsert", kind: .callNativeTool, description: "Create contact")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.hardware.bluetooth.discovery.foreground", "Discover nearby Bluetooth devices once")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.hardware.apps.installed.list", "List query-visible installed apps")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.microphone.record.visible", "Record audio")), .confirmOnce)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.notifications.list", "Read notifications")), .confirmOnce)
  }

  func testAgentConfirmationPolicyConsequentialActionsRequireEveryConfirmation() {
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "sms-send", kind: .callNativeTool, description: "Send SMS message")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "delete-file", kind: .callNativeTool, description: "Delete file")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "lock", kind: .lockScreen, description: "Lock device")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.notifications.reply", "Reply to a notification")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: nativeConfirmationAction("signalasi.desktop.terminal.run", "Run a Desktop workspace command")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "submit-code", kind: .callConnector, description: "Git commit and push the code")), .confirmAlways)
    XCTAssertEqual(AgentConfirmationPolicy.tier(for: confirmationAction(id: "system-settings", kind: .callConnector, description: "Change a system setting")), .confirmAlways)
  }

  func testAgentConfirmationPolicyRememberedNativeConsentKeysAreStable() {
    let firstBluetooth = nativeConfirmationAction(
      "signalasi.hardware.bluetooth.discovery.foreground",
      "Discover nearby Bluetooth devices once",
      id: "native-first"
    )
    let secondBluetooth = nativeConfirmationAction(
      "signalasi.hardware.bluetooth.discovery.foreground",
      "Scan for nearby Bluetooth devices",
      id: "native-second"
    )

    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), "bluetooth_discovery")
    XCTAssertEqual(AgentConfirmationPolicy.consentKey(for: firstBluetooth), AgentConfirmationPolicy.consentKey(for: secondBluetooth))
  }

  func testAgentConfirmationPolicyHomeAssistantUsesAndroidConsentScope() {
    let homeAssistantInput = #"{"entity_id":"lock.front_door","service_domain":"lock","service":"unlock"}"#
    let homeAssistantAction = nativeConfirmationAction(
      "signalasi.home_assistant.service.call",
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
        "_signalasi_conversation_context": "Earlier the user asked to send a message"
      ]
    )

    XCTAssertEqual(AgentConfirmationPolicy.tier(for: connectorAction), .direct)
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

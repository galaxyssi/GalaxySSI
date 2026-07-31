import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentDirectNativeToolPlannerRoutesCommonPhoneOperations() throws {
    let requestTools = AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    )
    let screen = AgentScreenContext(foregroundApp: "com.signalasi.chat", pageTitle: "SignalASI")

    func action(_ goal: String) -> AgentAction? {
      AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
        goal: goal,
        screen: screen,
        nativeTools: requestTools
      ))
    }

    XCTAssertEqual(
      action("Read the current battery level on this phone.")?.parameters["tool_id"],
      AgentIOSHardwareNativeToolCatalog.batteryStatus
    )
    XCTAssertEqual(
      action("\u{67e5}\u{770b}\u{624b}\u{673a}\u{7535}\u{91cf}")?.parameters["tool_id"],
      AgentIOSHardwareNativeToolCatalog.batteryStatus
    )
    XCTAssertEqual(action("Check battery saver status")?.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.powerStatus)
    XCTAssertEqual(action("Check phone storage")?.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.storageStatus)
    XCTAssertEqual(action("Check phone network status")?.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.networkStatus)
    XCTAssertEqual(action("Check Wi-Fi status")?.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.wifiStatus)
    XCTAssertEqual(action("Open Wi-Fi settings")?.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.wifiPanelOpen)

    let volume = try XCTUnwrap(action("Set media volume 30"))
    let volumeInput = try inputObject(volume)
    XCTAssertEqual(volume.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.audioVolumeSet)
    XCTAssertEqual(volumeInput["stream"] as? String, "music")
    XCTAssertEqual(volumeInput["percent"] as? Int, 30)
    XCTAssertEqual(volume.parameters["response_language"], "en")
    XCTAssertFalse(volume.requiresConfirmation)

    let chineseVolume = try XCTUnwrap(action("\u{628a}\u{97f3}\u{91cf}\u{8bbe}\u{7f6e}\u{4e3a}50"))
    XCTAssertEqual(chineseVolume.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.audioVolumeSet)
    XCTAssertEqual(chineseVolume.parameters["response_language"], "zh")
    XCTAssertEqual(try inputObject(chineseVolume)["percent"] as? Int, 50)

    let mute = try XCTUnwrap(action("Mute media audio"))
    XCTAssertEqual(mute.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.audioMuteSet)
    XCTAssertEqual(try inputObject(mute)["muted"] as? Bool, true)

    let unmute = try XCTUnwrap(action("Unmute media audio"))
    XCTAssertEqual(unmute.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.audioMuteSet)
    XCTAssertEqual(try inputObject(unmute)["muted"] as? Bool, false)

    let dial = try XCTUnwrap(action("Dial 12345"))
    XCTAssertEqual(dial.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.telephonyDialHandoff)
    XCTAssertEqual(try inputObject(dial)["phone_number"] as? String, "12345")
    XCTAssertTrue(dial.requiresConfirmation)

    let sms = try XCTUnwrap(action("Send SMS to 12345: hello"))
    XCTAssertEqual(sms.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.smsSend)
    XCTAssertEqual(try inputObject(sms)["phone_number"] as? String, "12345")
    XCTAssertEqual(try inputObject(sms)["message"] as? String, "hello")
    XCTAssertTrue(sms.requiresConfirmation)

    let plan = try XCTUnwrap(AgentDirectNativeToolPlanner.plan(request: AgentPlanRequest(
      goal: "Set media volume 30",
      screen: screen,
      nativeTools: requestTools
    )))
    XCTAssertEqual(plan.plannerProfile, "rule-based-direct-native-tool")
    XCTAssertEqual(plan.actions.first?.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.audioVolumeSet)
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentDirectNativeToolPlannerSkipsMissingOrUnavailableNativeTools() throws {
    let requestTools = AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    )
    let screen = AgentScreenContext(foregroundApp: "com.signalasi.chat")

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Turn on the flashlight",
      screen: screen,
      nativeTools: requestTools
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Set media volume 30",
      screen: screen,
      nativeTools: requestTools.filter { $0.id == AgentIOSHardwareNativeToolCatalog.batteryStatus }
    )))
  }

  private func inputObject(_ action: AgentAction) throws -> [String: Any] {
    let inputJson = try XCTUnwrap(action.parameters["input_json"])
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJson.utf8)) as? [String: Any])
  }
}

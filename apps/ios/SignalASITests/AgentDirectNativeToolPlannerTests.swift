import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentDirectNativeToolPlannerRoutesCommonPhoneOperations() throws {
    let requestTools = AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    ) + AgentIOSVisibleCaptureNativeToolCatalog.definitions(
      provider: DirectPlannerVisibleCaptureProvider()
    ).map(\.descriptor)
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
    XCTAssertEqual(action("Check available RAM on this phone")?.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.memoryStatus)
    XCTAssertEqual(action("\u{67e5}\u{770b}\u{624b}\u{673a}\u{5185}\u{5b58}")?.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.memoryStatus)
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

    let blockedInstall = try XCTUnwrap(action("Install APK from Downloads"))
    XCTAssertEqual(blockedInstall.id, "blocked-app-installation")
    XCTAssertEqual(blockedInstall.kind, .draftPlan)
    XCTAssertEqual(blockedInstall.risk, .blocked)
    XCTAssertEqual(blockedInstall.status, .blocked)
    XCTAssertFalse(blockedInstall.requiresConfirmation)
    XCTAssertTrue(blockedInstall.parameters["blocked_reason"]?.contains("installation") == true)

    let blockedMessage = try XCTUnwrap(action("Send message to Alice on WeChat"))
    XCTAssertEqual(blockedMessage.id, "blocked-third-party-send")
    XCTAssertEqual(blockedMessage.risk, .blocked)

    let blockedPayment = try XCTUnwrap(action("Make payment for this order"))
    XCTAssertEqual(blockedPayment.id, "blocked-payment-order")
    XCTAssertEqual(blockedPayment.risk, .blocked)

    let blockedCredential = try XCTUnwrap(action("Export private key"))
    XCTAssertEqual(blockedCredential.id, "blocked-credential-permission")
    XCTAssertEqual(blockedCredential.risk, .blocked)

    let blockedPlan = try XCTUnwrap(AgentDirectNativeToolPlanner.plan(request: AgentPlanRequest(
      goal: "Export private key",
      screen: screen,
      nativeTools: requestTools
    )))
    XCTAssertEqual(blockedPlan.actions.first?.status, .blocked)
    XCTAssertEqual(blockedPlan.routeRationale, "A deterministic iOS safety block matched this protected operation.")
    XCTAssertTrue(blockedPlan.validation.valid)

    let website = try XCTUnwrap(action("Open website example.com/docs"))
    XCTAssertEqual(website.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openURL))
    XCTAssertEqual(website.target, "https://example.com/docs")
    XCTAssertEqual(try inputObject(website)["url"] as? String, "https://example.com/docs")
    XCTAssertEqual(try inputParameters(website)["url"] as? String, "https://example.com/docs")

    let webSearch = try XCTUnwrap(action("Search web SignalASI iOS"))
    XCTAssertEqual(webSearch.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openURL))
    XCTAssertEqual(webSearch.target, "Web Search")
    XCTAssertEqual(try inputParameters(webSearch)["url"] as? String, "https://www.google.com/search?q=SignalASI%20iOS")

    let map = try XCTUnwrap(action("Navigate to Shenzhen Bay"))
    XCTAssertEqual(map.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openURL))
    XCTAssertEqual(map.target, "Maps")
    XCTAssertEqual(try inputParameters(map)["url"] as? String, "https://maps.apple.com/?q=Shenzhen%20Bay")
    XCTAssertNil(action("Open website ftp://example.com"))

    let photos = try XCTUnwrap(action("Open photos"))
    XCTAssertEqual(photos.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openApp))
    XCTAssertEqual(photos.target, "Photos")
    XCTAssertEqual(try inputObject(photos)["target"] as? String, "Photos")
    XCTAssertEqual(try inputParameters(photos)["package"] as? String, "com.apple.mobileslideshow")
    XCTAssertFalse(photos.requiresConfirmation)
    XCTAssertNil(action("Open Photos on desktop"))
    XCTAssertNil(action("Open Safari on my desktop"))

    let safari = try XCTUnwrap(action("Open browser"))
    XCTAssertEqual(safari.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openApp))
    XCTAssertEqual(safari.target, "Safari")
    XCTAssertEqual(try inputParameters(safari)["package"] as? String, "com.apple.mobilesafari")

    let files = try XCTUnwrap(action("Open files"))
    XCTAssertEqual(files.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openApp))
    XCTAssertEqual(files.target, "Files")
    XCTAssertEqual(try inputParameters(files)["package"] as? String, "com.apple.DocumentsApp")

    let messages = try XCTUnwrap(action("Open messages"))
    XCTAssertEqual(messages.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openApp))
    XCTAssertEqual(messages.target, "Messages")
    XCTAssertEqual(try inputParameters(messages)["package"] as? String, "com.apple.MobileSMS")
    XCTAssertNil(action("Pick image"))

    let calendar = try XCTUnwrap(action("Open calendar"))
    XCTAssertEqual(calendar.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openApp))
    XCTAssertEqual(calendar.target, "Calendar")
    XCTAssertEqual(try inputParameters(calendar)["package"] as? String, "com.apple.mobilecal")

    let contact = try XCTUnwrap(action("Create contact Alice Example +1 555 123 4567"))
    XCTAssertEqual(contact.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.contactsUpsert)
    XCTAssertEqual(contact.target, "Contacts")
    XCTAssertEqual(try inputObject(contact)["display_name"] as? String, "Alice Example")
    XCTAssertEqual(try inputObject(contact)["phone_number"] as? String, "+15551234567")
    XCTAssertTrue(contact.requiresConfirmation)
    XCTAssertTrue(contact.parameters["idempotency_key"]?.hasPrefix("create-contact-") == true)

    let camera = try XCTUnwrap(action("Open camera and take a photo"))
    XCTAssertEqual(camera.parameters["tool_id"], AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture)
    XCTAssertEqual(try inputObject(camera)["facing"] as? String, "back")
    XCTAssertFalse(camera.requiresConfirmation)

    let chineseCamera = try XCTUnwrap(action("\u{6253}\u{5f00}\u{624b}\u{673a}\u{6444}\u{50cf}\u{5934}\u{62cd}\u{7167}"))
    XCTAssertEqual(chineseCamera.parameters["tool_id"], AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture)
    XCTAssertNil(action("Explain how camera sensors work"))

    let microphone = try XCTUnwrap(action("Record audio for five seconds"))
    XCTAssertEqual(microphone.parameters["tool_id"], AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord)
    XCTAssertEqual(try inputObject(microphone)["max_duration_seconds"] as? Int, 5)
    XCTAssertTrue(microphone.requiresConfirmation)

    let chineseMicrophone = try XCTUnwrap(action("\u{5f55}\u{97f3} 8 \u{79d2}"))
    XCTAssertEqual(chineseMicrophone.parameters["tool_id"], AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord)
    XCTAssertEqual(try inputObject(chineseMicrophone)["max_duration_seconds"] as? Int, 8)

    let clampedMicrophone = try XCTUnwrap(action("Record audio for one minute"))
    XCTAssertEqual(clampedMicrophone.parameters["tool_id"], AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord)
    XCTAssertEqual(try inputObject(clampedMicrophone)["max_duration_seconds"] as? Int, 30)
    XCTAssertNil(action("Explain how microphones work"))

    let timer = try XCTUnwrap(action("Set a fifteen second timer"))
    XCTAssertEqual(timer.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm))
    XCTAssertEqual(timer.target, "iOS Timer")
    XCTAssertEqual(try inputObject(timer)["target"] as? String, "iOS Timer")
    XCTAssertEqual(try inputParameters(timer)["timer_seconds"] as? String, "15")
    XCTAssertEqual(try inputParameters(timer)["label"] as? String, "Set a fifteen second timer")
    XCTAssertFalse(timer.requiresConfirmation)

    let chineseTimer = try XCTUnwrap(action("\u{8bbe}\u{7f6e}3\u{5206}\u{949f}\u{5012}\u{8ba1}\u{65f6}"))
    XCTAssertEqual(chineseTimer.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm))
    XCTAssertEqual(try inputParameters(chineseTimer)["timer_seconds"] as? String, "180")
    XCTAssertEqual(chineseTimer.parameters["response_language"], "zh")

    let alarm = try XCTUnwrap(action("Set alarm 07:30"))
    XCTAssertEqual(alarm.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm))
    XCTAssertEqual(alarm.target, "iOS Alarm")
    XCTAssertEqual(try inputParameters(alarm)["hour"] as? String, "7")
    XCTAssertEqual(try inputParameters(alarm)["minute"] as? String, "30")
    XCTAssertEqual(try inputParameters(alarm)["message"] as? String, "Set alarm 07:30")
    XCTAssertFalse(alarm.requiresConfirmation)
    XCTAssertNil(action("Explain what a timer is"))
    XCTAssertNil(action("Open timer"))

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
      goal: "Open camera and take a photo",
      screen: screen,
      nativeTools: requestTools
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "\u{5f55}\u{97f3} 8 \u{79d2}",
      screen: screen,
      nativeTools: requestTools
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Set media volume 30",
      screen: screen,
      nativeTools: requestTools.filter { $0.id == AgentIOSHardwareNativeToolCatalog.batteryStatus }
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Set a fifteen second timer",
      screen: screen,
      nativeTools: requestTools.filter { $0.id != AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm) }
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Open photos",
      screen: screen,
      nativeTools: requestTools.filter { $0.id != AgentNativeToolAgentActionAdapter.defaultToolId(.openApp) }
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Open website example.com",
      screen: screen,
      nativeTools: requestTools.filter { $0.id != AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )))

    XCTAssertNil(AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(
      goal: "Create contact Alice Example +1 555 123 4567",
      screen: screen,
      nativeTools: requestTools.filter { $0.id != AgentIOSSystemNativeToolCatalog.contactsUpsert }
    )))
  }

  private func inputObject(_ action: AgentAction) throws -> [String: Any] {
    let inputJson = try XCTUnwrap(action.parameters["input_json"])
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJson.utf8)) as? [String: Any])
  }

  private func inputParameters(_ action: AgentAction) throws -> [String: Any] {
    try XCTUnwrap(inputObject(action)["parameters"] as? [String: Any])
  }
}

private struct DirectPlannerVisibleCaptureProvider: AgentIOSVisibleCaptureToolProviding {
  let implementationId = "fake.ios.visible_capture.direct_planner"

  func availability(kind: AgentIOSVisibleCaptureKind) -> AgentNativeToolAvailability {
    .available
  }

  func capturePhoto(
    facing: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    AgentIOSVisibleCaptureOutcome(status: .cancelled)
  }

  func recordAudio(
    maxDurationSeconds: Int,
    invocation: AgentNativeToolInvocation
  ) -> AgentIOSVisibleCaptureOutcome {
    AgentIOSVisibleCaptureOutcome(status: .cancelled)
  }
}

import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testDeviceMutationShortcutMustCoverTheWholeCommand() throws {
    let tools = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses()) +
      AgentIOSHardwareNativeToolCatalog.descriptors().filter { $0.id == AgentIOSHardwareNativeToolCatalog.flashlightSet } +
      AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: DirectPlannerVisibleCaptureProvider()).map(\.descriptor)
    func request(_ goal: String) -> AgentPlanRequest {
      AgentPlanRequest(goal: goal, screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat"), nativeTools: tools)
    }
    for goal in [
      "Do not turn on the flashlight", "Why does turn on the flashlight fail?",
      "If it is dark, turn on the flashlight", "Turn on the flashlight for 10 seconds",
      "Set volume from 20 to 50", "Set volume to 150", "Set volume to -20", "Set volume to 0.5",
      "Set media volume 30 and then open Wi-Fi settings", "Set volume 20 and notification volume 50",
      "Set volume to 30?", "Mute media audio?", "Open camera", "Open camera and take three photos",
      "Take a photo and then open Photos", "Record audio", "Record audio for zero seconds",
      "Record audio for 31 seconds", "Record audio for 5 seconds at 16 kHz",
      "Record audio for 5 seconds after the signal", "Record audio for 5 seconds and then open Photos",
      "Open Calculatr on my phone", "Launch Calculator app on this device",
      "Open Photos and select a PDF", "\u{4e0d}\u{8981}\u{5f55}\u{97f3}"
    ] {
      XCTAssertTrue(AgentDeviceMutationShortcutCoverage.requiresReasoning(goal), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.action(for: request(goal)), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.plan(request: request(goal)), goal)
    }
    let ring = try XCTUnwrap(AgentDirectNativeToolPlanner.action(for: request("Change ring volume to 50%")))
    XCTAssertEqual(try inputObject(ring)["stream"] as? String, "ring")
    XCTAssertEqual(try inputObject(ring)["percent"] as? Int, 50)
    let flashlight = try XCTUnwrap(AgentDirectNativeToolPlanner.action(for: request("\u{8acb}\u{95dc}\u{9589}\u{624b}\u{96fb}\u{7b52}")))
    XCTAssertEqual(try inputObject(flashlight)["enabled"] as? Bool, false)
    for (command, duration) in [
      ("Record audio for five seconds", 5), ("Record audio for 20 seconds and 5 seconds", 25),
      ("\u{9304}\u{97f3}\u{534a}\u{5206}\u{9418}", 30)
    ] {
      let action = try XCTUnwrap(AgentDirectNativeToolPlanner.action(for: request(command)))
      XCTAssertEqual(try inputObject(action)["max_duration_seconds"] as? Int, duration, command)
    }
    let handoff = try XCTUnwrap(AgentDirectNativeToolPlanner.action(for: request("Launch Safari app on this device")))
    XCTAssertEqual(try inputParameters(handoff)["package"] as? String, "com.apple.mobilesafari")
    let settings = AgentModelPlannerSettings()
    for (goal, toolId, arguments, code) in [
      ("Open Calculatr on my phone", AgentNativeToolAgentActionAdapter.defaultToolId(.openApp),
        #"{"parameters":{"package":"com.apple.mobilesafari"}}"#, "unavailable_app_handoff"),
      ("Record audio", AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord, "{}", "invalid_audio_duration"),
      ("Open camera", AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture, "{}", "photo_not_requested")
    ] {
      let raw = """
      {"actions":[{"kind":"CALL_NATIVE_TOOL","parameters":{"tool_id":"\(toolId)","arguments":\(arguments)}}]}
      """
      guard case .failure(let rejection) = AgentModelPlanParser.parseWithDiagnostics(
        request: request(goal), raw: raw, settings: settings) else { return XCTFail(goal) }
      XCTAssertEqual(rejection.code, code, goal)
    }
    XCTAssertTrue(AgentPhoneShortcutRouting.requiresPhoneReasoning("Open Calculatr on my phone"))
    XCTAssertFalse(AgentPhoneShortcutRouting.requiresPhoneReasoning("Open Photos on my desktop"))
    XCTAssertTrue(AgentDeviceMutationShortcutCoverage.prohibitsMutation("Do not turn on the flashlight"))
    XCTAssertTrue(AgentDeviceMutationShortcutCoverage.prohibitsMutation("Explain how to set volume to 50"))
    for goal in ["Explain camera sensors", "What is audio?", "How do microphones work?", "Open website https://example.com"] {
      XCTAssertFalse(AgentDeviceMutationShortcutCoverage.requiresReasoning(goal), goal)
    }
  }

  func testCompositeDeviceGoalsRequireWholeGoalPhonePlanning() {
    let tools = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses())
    func request(_ goal: String) -> AgentPlanRequest {
      AgentPlanRequest(goal: goal, screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat"), nativeTools: tools)
    }
    for goal in [
      "Check battery status and remaining storage", "Read battery status, free RAM, network status",
      "Read battery percentage and temperature", "Don't read battery status; read storage only",
      "Read battery level if charging", "Read battery status and save it to battery.txt",
      "Read Wi-Fi status and Bluetooth status", "Read battery status and then turn on the flashlight",
      "\u{7535}\u{91cf}\u{3001}\u{5185}\u{5b58}", "\u{96fb}\u{91cf}\u{8207}\u{5132}\u{5b58}"
    ] {
      XCTAssertTrue(AgentDeviceStatusShortcutCoverage.requiresPhoneReasoning(goal), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.action(for: request(goal)), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.plan(request: request(goal)), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.shortcutPlan(request: request(goal)), goal)
    }
    for goal in [
      "Read the current battery level on this phone.",
      "\u{8bfb}\u{53d6}\u{8fd9}\u{53f0}\u{624b}\u{673a}\u{7684}\u{5f53}\u{524d}\u{7535}\u{91cf}\u{ff0c}\u{7b80}\u{77ed}\u{56de}\u{7b54}\u{3002}"
    ] {
      XCTAssertFalse(AgentDeviceStatusShortcutCoverage.requiresReasoning(goal), goal)
      XCTAssertEqual(AgentDirectNativeToolPlanner.shortcutPlan(request: request(goal))?.actions.first?.parameters["tool_id"],
        AgentIOSHardwareNativeToolCatalog.batteryStatus, goal)
    }
    XCTAssertNotNil(AgentDirectNativeToolPlanner.action(for: request(
      "\u{9019}\u{53f0}\u{624b}\u{6a5f}\u{9084}\u{6709}\u{591a}\u{5c11}\u{904b}\u{884c}\u{5167}\u{5b58}"
    )))
    for goal in [
      "Explain battery level and network status", "What is cloud storage?",
      "Compare battery chemistry and memory technology", "Check this program for errors",
      "Set media volume 30", "Turn on the flashlight", "Open Wi-Fi settings"
    ] {
      XCTAssertFalse(AgentDeviceStatusShortcutCoverage.requiresReasoning(goal), goal)
    }
    for goal in [
      "Read battery status and available storage on my computer",
      "Audit this repository, inspect available memory, Git, builds, tests, and replan from the evidence."
    ] {
      XCTAssertTrue(AgentDeviceStatusShortcutCoverage.requiresReasoning(goal), goal)
      XCTAssertFalse(AgentDeviceStatusShortcutCoverage.requiresPhoneReasoning(goal), goal)
      XCTAssertNil(AgentDirectNativeToolPlanner.plan(request: request(goal)), goal)
    }
  }

  func testNativeShortcutsRequireCompleteCommandsAndTypedArguments() throws {
    let tools = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses()) +
      AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: DirectPlannerVisibleCaptureProvider()).map(\.descriptor)
    func action(_ goal: String) -> AgentAction? {
      AgentDirectNativeToolPlanner.action(for: AgentPlanRequest(goal: goal,
        screen: AgentScreenContext(foregroundApp: "com.galaxyssi.chat"), nativeTools: tools))
    }
    for goal in [
      "Don't open Wi-Fi settings; explain what it would do.",
      "Open Wi-Fi settings if the phone is offline.",
      "Open Photos and select a PDF.",
      "Explain battery level and network status.",
      "Read battery and network status.",
      "Read battery level if charging.",
      "Check VPN status, then open Settings.",
      "Set media volume -30",
      "Set media volume 130",
      "Set media volume to 30 or 40",
      "Do not mute media audio.",
      "Dial 12345 after checking the contact.",
      "Dial 12",
      "Send SMS to 12345 if I approve: hello",
      "Set alarm 07:30 on Monday",
      "Set alarm 24:00",
      "Set alarm 07:30 and 09:00",
      "Set timer for 0 seconds",
      "Set timer for 999999999999999999 hours",
      "Record audio for five seconds and save it.",
      "Take a photo after opening Settings.",
      "Read sensor",
      "Read sensor thermocouple",
      "Read accelerometer and gyroscope",
      "Open website https://example.com then copy the page.",
      "Open website https://user:pass@example.com",
      "Download https://example.com/file and open it",
      "Download http://example.com/file",
      "Delete contact 17 if it is a duplicate",
      "Create contact Alice Example +1234567890123456789",
      "Remove download 12 and 13",
      "Package info com.example.app or com.example.other",
      "Navigate to Shenzhen Bay. Open Photos.",
      "\u{4e0d}\u{8981}\u{6253}\u{5f00}\u{76f8}\u{518c}",
      "\u{5982}\u{679c}\u{6709}\u{7f51}\u{5c31}\u{6253}\u{5f00}\u{65e0}\u{7ebf}\u{7f51}\u{7edc}\u{8bbe}\u{7f6e}"
    ] {
      XCTAssertNil(action(goal), goal)
    }
    let battery = try XCTUnwrap(action("Please read the current battery level on this phone, reply briefly."))
    XCTAssertEqual(battery.parameters["tool_id"], AgentIOSHardwareNativeToolCatalog.batteryStatus)
    let settings = try XCTUnwrap(action("Please open Wi-Fi settings."))
    XCTAssertEqual(settings.parameters["tool_id"], AgentIOSSystemNativeToolCatalog.wifiPanelOpen)
    let call = try XCTUnwrap(action("Please dial +1 (555) 123-4567."))
    XCTAssertEqual(try inputObject(call)["phone_number"] as? String, "+15551234567")
    XCTAssertTrue(call.requiresConfirmation)
    let sensor = try XCTUnwrap(action("Sample gyroscope sensor."))
    XCTAssertEqual(try inputObject(sensor)["type"] as? String, "gyroscope")
    XCTAssertNil(AgentScreenSearchCommand.query("Find on screen PDF, then tap it"))
    XCTAssertNil(AgentNotificationCommand.parse("Search notifications Alice and reply to her"))
  }

  func testAgentDirectNativeToolPlannerRoutesCommonPhoneOperations() throws {
    let requestTools = AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    ) + AgentIOSVisibleCaptureNativeToolCatalog.definitions(
      provider: DirectPlannerVisibleCaptureProvider()
    ).map(\.descriptor)
    let screen = AgentScreenContext(foregroundApp: "com.galaxyssi.chat", pageTitle: "GalaxySSI")

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

    let webSearch = try XCTUnwrap(action("Search web GalaxySSI iOS"))
    XCTAssertEqual(webSearch.parameters["tool_id"], AgentNativeToolAgentActionAdapter.defaultToolId(.openURL))
    XCTAssertEqual(webSearch.target, "Web Search")
    XCTAssertEqual(try inputParameters(webSearch)["url"] as? String, "https://www.google.com/search?q=GalaxySSI%20iOS")

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
    let screen = AgentScreenContext(foregroundApp: "com.galaxyssi.chat")

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

import Foundation

enum AgentDirectNativeToolPlanner {
  static func plan(request: AgentPlanRequest) -> AgentPlan? {
    guard let action = action(for: request) else {
      return nil
    }
    var plan = AgentPlanFactory.singleAction(request: request, action: action)
    plan.plannerProfile = "rule-based-direct-native-tool"
    plan.routeRationale = action.risk == .blocked
      ? "A deterministic iOS safety block matched this protected operation."
      : "A deterministic iOS native-tool route matched this phone operation."
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  static func action(for request: AgentPlanRequest) -> AgentAction? {
    let goal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty else { return nil }
    let lower = goal.lowercased()
    let responseLanguage = responseLanguageCode(for: request)
    guard AgentTaskIntentClassifier.classify(goal: goal).intent != .desktopControl else {
      return nil
    }

    if isNotificationReadGoal(lower),
       let descriptor = descriptor(AgentIOSNotificationNativeToolCatalog.notificationsList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "list-notifications",
        target: "Notifications",
        description: "Read current notifications",
        input: ["limit": .int(Int64(AgentIOSNotificationNativeToolCatalog.defaultLimit))],
        responseLanguage: responseLanguage
      )
    }

    if isHomeAssistantStatusGoal(lower),
       let descriptor = descriptorAllowingSetup(AgentIOSHomeAssistantNativeToolCatalog.connectionStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "home-assistant-status",
        target: "Home Assistant",
        description: "Check Home Assistant connection status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if let collection = homeAssistantCollection(in: lower),
       let descriptor = descriptorAllowingSetup(AgentIOSHomeAssistantNativeToolCatalog.entitiesList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "home-assistant-\(collection.domain)",
        target: "Home Assistant \(collection.label)",
        description: "List Home Assistant \(collection.label)",
        input: [
          "domains": .array([.string(collection.domain)]),
          "limit": .int(40)
        ],
        responseLanguage: responseLanguage
      )
    }

    if let query = homeAssistantEntitySearchQuery(in: goal, lower: lower),
       let descriptor = descriptorAllowingSetup(AgentIOSHomeAssistantNativeToolCatalog.entitiesList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "home-assistant-search",
        target: "Home Assistant",
        description: "Search Home Assistant entities",
        input: [
          "query": .string(query),
          "limit": .int(40)
        ],
        responseLanguage: responseLanguage
      )
    }

    if isHomeAssistantEntitiesGoal(lower),
       let descriptor = descriptorAllowingSetup(AgentIOSHomeAssistantNativeToolCatalog.entitiesList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "home-assistant-entities",
        target: "Home Assistant",
        description: "List Home Assistant entities",
        input: ["limit": .int(40)],
        responseLanguage: responseLanguage
      )
    }

    if let entityID = homeAssistantEntityReadID(in: goal, lower: lower),
       let descriptor = descriptorAllowingSetup(AgentIOSHomeAssistantNativeToolCatalog.entityRead, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "home-assistant-entity",
        target: entityID,
        description: "Read Home Assistant entity state",
        input: ["entity_id": .string(entityID)],
        responseLanguage: responseLanguage
      )
    }

    if let url = downloadURL(in: goal, lower: lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.downloadEnqueue, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "enqueue-download",
        target: url,
        description: "Enqueue HTTPS download",
        input: [
          "url": .string(url),
          "title": .string(downloadTitle(for: url)),
          "description": .string(goal.prefixString(500))
        ],
        responseLanguage: responseLanguage
      )
    }

    if isDownloadQueryGoal(lower),
       let downloadID = downloadID(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.downloadQuery, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "query-download",
        target: "Download #\(downloadID)",
        description: "Read download status",
        input: ["download_id": .int(Int64(downloadID))],
        responseLanguage: responseLanguage
      )
    }

    if isDownloadRemoveGoal(lower),
       let downloadID = downloadID(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.downloadRemove, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "remove-download",
        target: "Download #\(downloadID)",
        description: "Remove managed download",
        input: ["download_id": .int(Int64(downloadID))],
        responseLanguage: responseLanguage
      )
    }

    if isSMSComposeGoal(lower),
       let phoneNumber = phoneNumber(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.smsComposeHandoff, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "compose-sms",
        target: phoneNumber,
        description: "Open SMS composer",
        input: [
          "phone_number": .string(phoneNumber),
          "message": .string(smsMessage(in: goal))
        ],
        responseLanguage: responseLanguage
      )
    }

    if isWifiHotspotSettingsGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.wifiHotspotPanelOpen, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-hotspot-settings",
        target: "Personal Hotspot",
        description: "Open Personal Hotspot settings",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isBiometricEnrollmentGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.biometricEnrollmentOpen, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-biometric-settings",
        target: "Biometrics",
        description: "Open biometric enrollment settings",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isVPNConsentGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.vpnConsentOpen, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-vpn-settings",
        target: "VPN",
        description: "Open VPN settings",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isTelephonyCallStateObserveGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.telephonyCallStateObserve, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "observe-call-state",
        target: "Phone",
        description: "Observe one call state transition",
        input: ["timeout_ms": .int(10_000)],
        responseLanguage: responseLanguage
      )
    }

    if isTelephonyCallStateGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.telephonyCallState, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "call-state",
        target: "Phone",
        description: "Read current call state",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isTelephonyStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.telephonyStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "telephony-status",
        target: "Phone",
        description: "Read phone service status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isSMSListGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.smsList, in: request) {
      var input: AgentMcpJSONObject = ["limit": .int(20)]
      if let address = phoneNumber(in: goal) {
        input["address"] = .string(address)
      }
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "list-sms",
        target: "SMS",
        description: "Read recent SMS messages",
        input: input,
        responseLanguage: responseLanguage
      )
    }

    if let query = contactSearchQuery(in: goal, lower: lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.contactsSearch, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "search-contacts",
        target: "Contacts",
        description: "Search contacts",
        input: [
          "query": .string(query),
          "limit": .int(30)
        ],
        responseLanguage: responseLanguage
      )
    }

    if isContactDeleteGoal(lower),
       let contactID = contactID(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.contactsDelete, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "delete-contact",
        target: "Contact #\(contactID)",
        description: "Delete contact",
        input: ["contact_id": .int(Int64(contactID))],
        responseLanguage: responseLanguage
      )
    }

    if isCalendarsListGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.calendarsList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "list-calendars",
        target: "Calendar",
        description: "List calendars",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isCalendarEventsQueryGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.calendarEventsQuery, in: request) {
      let window = calendarEventWindow(for: lower)
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "query-calendar-events",
        target: "Calendar",
        description: "Query calendar events",
        input: [
          "start_epoch_ms": .int(window.start),
          "end_epoch_ms": .int(window.end),
          "limit": .int(50)
        ],
        responseLanguage: responseLanguage
      )
    }

    if isCalendarEventDeleteGoal(lower),
       let eventID = calendarEventID(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.calendarEventDelete, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "delete-calendar-event",
        target: "Calendar event #\(eventID)",
        description: "Delete calendar event",
        input: ["event_id": .int(Int64(eventID))],
        responseLanguage: responseLanguage
      )
    }

    if isWifiScanStartGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.wifiScanStart, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "start-wifi-scan",
        target: "Wi-Fi",
        description: "Start Wi-Fi scan",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isWifiScanResultsGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.wifiScanResults, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "wifi-scan-results",
        target: "Wi-Fi",
        description: "Read Wi-Fi scan results",
        input: ["limit": .int(32)],
        responseLanguage: responseLanguage
      )
    }

    if isAudioStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.audioStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "audio-status",
        target: "Audio",
        description: "Read audio status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isBiometricStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.biometricStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "biometric-status",
        target: "Biometrics",
        description: "Read biometric capability",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isVPNStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.vpnStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "vpn-status",
        target: "VPN",
        description: "Read VPN status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isDevicePolicyStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.devicePolicyStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "device-policy-status",
        target: "Device Policy",
        description: "Read device policy status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isSMSGoal(lower),
       let phoneNumber = phoneNumber(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.smsSend, in: request) {
      let message = smsMessage(in: goal)
      guard !message.isEmpty else { return nil }
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "send-sms",
        target: phoneNumber,
        description: "Send SMS message",
        input: ["phone_number": .string(phoneNumber), "message": .string(message)],
        responseLanguage: responseLanguage
      )
    }

    if isDialGoal(lower),
       let phoneNumber = phoneNumber(in: goal),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.telephonyDialHandoff, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "dial-phone",
        target: phoneNumber,
        description: "Open phone dialer",
        input: ["phone_number": .string(phoneNumber)],
        responseLanguage: responseLanguage
      )
    }

    if let blocked = blockedSensitiveAction(goal: goal, lower: lower) {
      return blocked
    }

    if let handoff = urlHandoff(goal: goal, lower: lower),
       let descriptor = descriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.openURL), in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: handoff.idPrefix,
        target: handoff.target,
        description: handoff.description,
        input: actionAdapterInput(
          target: handoff.target,
          parameters: ["url": handoff.url],
          topLevel: ["url": .string(handoff.url)]
        ),
        responseLanguage: responseLanguage
      )
    }

    if let handoff = systemAppHandoff(for: lower),
       let descriptor = descriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.openApp), in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: handoff.idPrefix,
        target: handoff.target,
        description: "Open app \(handoff.target)",
        input: actionAdapterInput(
          target: handoff.target,
          parameters: ["package": handoff.bundleId]
        ),
        responseLanguage: responseLanguage
      )
    }

    if let contact = contactUpsertDraft(goal: goal, lower: lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.contactsUpsert, in: request) {
      var input: AgentMcpJSONObject = ["display_name": .string(contact.displayName)]
      if !contact.phoneNumber.isEmpty {
        input["phone_number"] = .string(contact.phoneNumber)
      }
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "create-contact",
        target: "Contacts",
        description: "Create contact",
        input: input,
        responseLanguage: responseLanguage
      )
    }

    if isCameraCaptureGoal(lower),
       let descriptor = descriptor(AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-camera",
        target: "Camera",
        description: "Take one user-visible photo",
        input: ["facing": .string("back")],
        responseLanguage: responseLanguage
      )
    }

    if isMicrophoneCaptureGoal(lower),
       let descriptor = descriptor(AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "record-audio",
        target: "Microphone",
        description: "Record user-visible audio",
        input: ["max_duration_seconds": .int(Int64(audioDurationSeconds(for: lower)))],
        responseLanguage: responseLanguage
      )
    }

    if isTimerGoal(lower),
       let seconds = timerDurationSeconds(for: lower),
       let descriptor = descriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm), in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "set-timer",
        target: "iOS Timer",
        description: "Set timer for \(seconds) seconds",
        input: actionAdapterInput(
          target: "iOS Timer",
          parameters: [
            "label": goal.prefixString(200),
            "timer_seconds": String(seconds)
          ]
        ),
        responseLanguage: responseLanguage
      )
    }

    if isAlarmGoal(lower),
       let time = alarmClockTime(in: lower),
       let descriptor = descriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm), in: request) {
      let hour = String(format: "%02d", time.hour)
      let minute = String(format: "%02d", time.minute)
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "set-alarm",
        target: "iOS Alarm",
        description: "Set alarm for \(hour):\(minute)",
        input: actionAdapterInput(
          target: "iOS Alarm",
          parameters: [
            "hour": String(time.hour),
            "minute": String(time.minute),
            "message": goal.prefixString(200)
          ]
        ),
        responseLanguage: responseLanguage
      )
    }

    if isVolumeSetGoal(lower),
       let percent = firstPercent(in: lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.audioVolumeSet, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "set-volume",
        target: "Audio",
        description: "Set media volume",
        input: ["stream": .string("music"), "percent": .int(Int64(percent))],
        responseLanguage: responseLanguage
      )
    }

    if isMuteGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.audioMuteSet, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "set-mute",
        target: "Audio",
        description: "Set audio mute",
        input: ["stream": .string("music"), "muted": .bool(!isUnmuteGoal(lower))],
        responseLanguage: responseLanguage
      )
    }

    if isWifiSettingsGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.wifiPanelOpen, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-wifi-settings",
        target: "Wi-Fi Settings",
        description: "Open Wi-Fi settings",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isWifiStatusGoal(lower),
       let descriptor = descriptor(AgentIOSSystemNativeToolCatalog.wifiStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "wifi-status",
        target: "Wi-Fi",
        description: "Read Wi-Fi status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isDeviceStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.deviceStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "device-status",
        target: "Device Status",
        description: "Read current device status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isBatteryStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.batteryStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "battery-status",
        target: "Battery",
        description: "Read battery status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isPowerStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.powerStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "power-status",
        target: "Power",
        description: "Read power status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isMemoryStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.memoryStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "memory-status",
        target: "Memory",
        description: "Read phone memory status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isStorageStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.storageStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "storage-status",
        target: "Storage",
        description: "Read storage status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isNetworkStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.networkStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "network-status",
        target: "Network",
        description: "Read network status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isLocationReadGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.locationForegroundRead, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "location-status",
        target: "Location",
        description: "Read foreground location",
        input: ["timeout_ms": .int(10_000)],
        responseLanguage: responseLanguage
      )
    }

    if isSensorListGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.sensorsList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "list-sensors",
        target: "Sensors",
        description: "List device sensors",
        input: ["limit": .int(64)],
        responseLanguage: responseLanguage
      )
    }

    if isSensorSampleGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.sensorSample, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "sample-sensor",
        target: "Sensors",
        description: "Read one foreground sensor sample",
        input: [
          "type": .string(sensorType(in: lower)),
          "timeout_ms": .int(5_000)
        ],
        responseLanguage: responseLanguage
      )
    }

    if isBluetoothStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.bluetoothStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "bluetooth-status",
        target: "Bluetooth",
        description: "Read Bluetooth status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isBluetoothDiscoveryGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.bluetoothDiscoveryForeground, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "discover-bluetooth",
        target: "Bluetooth",
        description: "Discover nearby Bluetooth devices",
        input: [
          "timeout_ms": .int(10_000),
          "limit": .int(16)
        ],
        responseLanguage: responseLanguage
      )
    }

    if isBluetoothPairingGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.bluetoothPairingHandoff, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "open-bluetooth-pairing",
        target: "Bluetooth Settings",
        description: "Open Bluetooth pairing settings",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if isNFCStatusGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.nfcStatus, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "nfc-status",
        target: "NFC",
        description: "Read NFC status",
        input: [:],
        responseLanguage: responseLanguage
      )
    }

    if let query = installedAppsQuery(goal: goal, lower: lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.installedAppsList, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "list-installed-apps",
        target: "Installed Apps",
        description: "List visible installed apps",
        input: [
          "query": .string(query),
          "limit": .int(100)
        ],
        responseLanguage: responseLanguage
      )
    }

    if let package = packageName(in: goal, lower: lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.packageDetail, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "app-package-detail",
        target: package,
        description: "Read visible app detail",
        input: ["package_name": .string(package)],
        responseLanguage: responseLanguage
      )
    }

    if isFlashlightGoal(lower),
       let descriptor = descriptor(AgentIOSHardwareNativeToolCatalog.flashlightSet, in: request) {
      return nativeAction(
        descriptor: descriptor,
        idPrefix: "set-flashlight",
        target: "Flashlight",
        description: "Set flashlight",
        input: ["enabled": .bool(!isTurnOffGoal(lower))],
        responseLanguage: responseLanguage
      )
    }

    return nil
  }

  private static func nativeAction(
    descriptor: AgentNativeToolDescriptor,
    idPrefix: String,
    target: String,
    description: String,
    input: AgentMcpJSONObject,
    responseLanguage: String
  ) -> AgentAction {
    var parameters = [
      "tool_id": descriptor.id,
      "input_json": AgentMcpJSONCodec.stringify(input),
      "native_tool_risk": descriptor.risk.rawValue,
      "response_language": responseLanguage
    ]
    if descriptor.idempotency == .idempotencyKeyRequired {
      parameters["idempotency_key"] = "\(idPrefix)-\(AgentMcpJSONCodec.sha256(input).prefix(16))"
    }
    return AgentAction(
      id: "\(idPrefix)-\(AgentMcpJSONCodec.sha256(input).prefix(16))",
      kind: .callNativeTool,
      target: target,
      risk: agentRisk(descriptor.risk),
      status: .pendingConfirmation,
      description: description,
      parameters: parameters,
      requiresConfirmation: AgentConfirmationPolicy.tier(for: AgentAction(
        id: idPrefix,
        kind: .callNativeTool,
        target: target,
        risk: agentRisk(descriptor.risk),
        status: .pendingConfirmation,
        description: description,
        parameters: ["tool_id": descriptor.id]
      )) != .direct
    )
  }

  private static func descriptor(
    _ id: String,
    in request: AgentPlanRequest
  ) -> AgentNativeToolDescriptor? {
    request.nativeTools.first {
      $0.id == id && $0.availability.status == .available && $0.risk != .blocked
    }
  }

  private static func descriptorAllowingSetup(
    _ id: String,
    in request: AgentPlanRequest
  ) -> AgentNativeToolDescriptor? {
    request.nativeTools.first {
      $0.id == id && $0.risk != .blocked
    }
  }

  private static func isNotificationReadGoal(_ lower: String) -> Bool {
    let normalized = lower.trimmingCharacters(in: .whitespacesAndNewlines)
    return [
      "notifications",
      "notification inbox",
      "read notifications",
      "list notifications",
      "show notifications",
      "show notification inbox",
      "\u{8bfb}\u{53d6}\u{901a}\u{77e5}",
      "\u{67e5}\u{770b}\u{901a}\u{77e5}",
      "\u{663e}\u{793a}\u{901a}\u{77e5}",
      "\u{901a}\u{77e5}\u{5217}\u{8868}",
      "\u{901a}\u{77e5}\u{6536}\u{4ef6}\u{7bb1}"
    ].contains(normalized)
  }

  private static func isHomeAssistantStatusGoal(_ lower: String) -> Bool {
    [
      "home assistant status",
      "check home assistant",
      "test home assistant",
      "test home assistant connection",
      "\u{68c0}\u{67e5} home assistant",
      "home assistant \u{72b6}\u{6001}",
      "\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{72b6}\u{6001}",
      "\u{667a}\u{80fd}\u{7a7a}\u{95f4}\u{72b6}\u{6001}",
      "\u{5bb6}\u{5c45}\u{52a9}\u{624b}\u{72b6}\u{6001}"
    ].contains(lower.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func isHomeAssistantEntitiesGoal(_ lower: String) -> Bool {
    [
      "home assistant entities",
      "list home assistant entities",
      "show home assistant entities",
      "list smart devices",
      "show smart devices",
      "\u{5217}\u{51fa} home assistant \u{5b9e}\u{4f53}",
      "\u{663e}\u{793a}\u{667a}\u{80fd}\u{8bbe}\u{5907}",
      "\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{8bbe}\u{5907}",
      "\u{5217}\u{51fa}\u{667a}\u{80fd}\u{8bbe}\u{5907}",
      "\u{67e5}\u{770b}\u{667a}\u{80fd}\u{8bbe}\u{5907}"
    ].contains(lower.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func homeAssistantCollection(
    in lower: String
  ) -> (label: String, domain: String)? {
    switch lower.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "home assistant scenes", "list home assistant scenes", "show home assistant scenes",
         "list scenes", "show scenes", "\u{5217}\u{51fa}\u{573a}\u{666f}",
         "\u{663e}\u{793a}\u{573a}\u{666f}", "\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{573a}\u{666f}":
      return ("scenes", "scene")
    case "home assistant automations", "list home assistant automations", "show home assistant automations",
         "list automations", "show automations", "\u{5217}\u{51fa}\u{81ea}\u{52a8}\u{5316}",
         "\u{663e}\u{793a}\u{81ea}\u{52a8}\u{5316}", "\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{81ea}\u{52a8}\u{5316}":
      return ("automations", "automation")
    case "home assistant scripts", "list home assistant scripts", "show home assistant scripts",
         "list scripts", "show scripts", "\u{5217}\u{51fa}\u{811a}\u{672c}",
         "\u{663e}\u{793a}\u{811a}\u{672c}", "\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{811a}\u{672c}":
      return ("scripts", "script")
    default:
      return nil
    }
  }

  private static func homeAssistantEntitySearchQuery(
    in goal: String,
    lower: String
  ) -> String? {
    let prefixes = [
      "search home assistant entities ",
      "find home assistant entity ",
      "search smart devices ",
      "find smart device ",
      "\u{641c}\u{7d22} home assistant \u{5b9e}\u{4f53} ",
      "\u{641c}\u{7d22}\u{667a}\u{80fd}\u{8bbe}\u{5907} ",
      "\u{641c}\u{7d22}\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{8bbe}\u{5907} ",
      "\u{67e5}\u{627e}\u{667a}\u{5bb6}\u{5c45}\u{8bbe}\u{5907} "
    ]
    guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else {
      return nil
    }
    let value = String(goal.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value.prefix(200))
  }

  private static func homeAssistantEntityReadID(
    in goal: String,
    lower: String
  ) -> String? {
    let prefixes = [
      "read home assistant entity ",
      "get home assistant entity ",
      "read sensor ",
      "get sensor ",
      "\u{8bfb}\u{53d6} home assistant \u{5b9e}\u{4f53} ",
      "\u{8bfb}\u{53d6}\u{4f20}\u{611f}\u{5668} ",
      "\u{8bfb}\u{53d6}\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{8bbe}\u{5907} ",
      "\u{67e5}\u{770b}\u{667a}\u{80fd}\u{5bb6}\u{5c45}\u{8bbe}\u{5907} "
    ]
    guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else {
      return nil
    }
    let value = String(goal.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : String(value.prefix(160))
  }

  private static func firstPercent(in value: String) -> Int? {
    value
      .components(separatedBy: CharacterSet.decimalDigits.inverted)
      .compactMap(Int.init)
      .first { (0...100).contains($0) }
  }

  private static func phoneNumber(in value: String) -> String? {
    guard let range = value.range(
      of: #"\+?[0-9][0-9\s().-]{2,}[0-9]"#,
      options: .regularExpression
    ) else {
      return nil
    }
    let raw = String(value[range])
    var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" ", "-", "(", ")", "."] {
      normalized = normalized.replacingOccurrences(of: removable, with: "")
    }
    return normalized.isEmpty ? nil : String(normalized.prefix(64))
  }

  private static func smsMessage(in goal: String) -> String {
    if let separator = goal.firstIndex(of: ":") {
      return String(goal[goal.index(after: separator)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefixString(2_000)
    }
    return ""
  }

  private static func responseLanguageCode(for request: AgentPlanRequest) -> String {
    let resolved = LanguagePolicySettings.resolve(request.responseLanguage)
    let languageCode = resolved
      .split(separator: "-", maxSplits: 1)
      .first
      .map { String($0).lowercased() } ?? ""
    switch languageCode {
    case "zh", "en":
      return languageCode
    default:
      return responseLanguageCode(fromGoal: request.goal)
    }
  }

  private static func responseLanguageCode(fromGoal goal: String) -> String {
    goal.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(Int(scalar.value))
    } ? "zh" : "en"
  }

  private static func agentRisk(_ risk: AgentNativeToolRisk) -> AgentRisk {
    switch risk {
    case .low:
      return .low
    case .medium:
      return .medium
    case .high:
      return .high
    case .blocked:
      return .blocked
    }
  }

  private static func isBatteryStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["battery level", "battery status", "read battery", "\u{7535}\u{91cf}"])
  }

  private static func isDeviceStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "device status", "phone status", "device health", "phone health",
      "\u{8BBE}\u{5907}\u{72B6}\u{6001}", "\u{624B}\u{673A}\u{72B6}\u{6001}",
      "\u{8BBE}\u{5907}\u{5065}\u{5EB7}", "\u{624B}\u{673A}\u{5065}\u{5EB7}"
    ])
  }

  private static func isSMSComposeGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "compose sms", "draft sms", "write sms", "compose text", "draft text",
      "\u{7f16}\u{8f91}\u{77ed}\u{4fe1}", "\u{8d77}\u{8349}\u{77ed}\u{4fe1}", "\u{7f16}\u{5199}\u{77ed}\u{4fe1}"
    ])
  }

  private static func isWifiHotspotSettingsGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "open hotspot settings", "open personal hotspot", "hotspot settings", "personal hotspot",
      "\u{6253}\u{5f00}\u{70ed}\u{70b9}\u{8bbe}\u{7f6e}", "\u{4e2a}\u{4eba}\u{70ed}\u{70b9}\u{8bbe}\u{7f6e}"
    ])
  }

  private static func isBiometricEnrollmentGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "open face id settings", "face id settings", "touch id settings", "biometric settings",
      "set up face id", "set up touch id", "\u{6253}\u{5f00}\u{9762}\u{5bb9}id\u{8bbe}\u{7f6e}",
      "\u{9762}\u{5bb9}id\u{8bbe}\u{7f6e}", "\u{89e6}\u{63a7}id\u{8bbe}\u{7f6e}", "\u{751f}\u{7269}\u{8bc6}\u{522b}\u{8bbe}\u{7f6e}"
    ])
  }

  private static func isVPNConsentGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "set up vpn", "configure vpn", "vpn consent", "vpn settings", "open vpn settings",
      "\u{914d}\u{7f6e}vpn", "vpn\u{8bbe}\u{7f6e}", "\u{6253}\u{5f00}vpn\u{8bbe}\u{7f6e}"
    ])
  }

  private static func isTelephonyStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "phone service status", "telephony status", "carrier status", "\u{624b}\u{673a}\u{670d}\u{52a1}\u{72b6}\u{6001}", "\u{7535}\u{8bdd}\u{670d}\u{52a1}\u{72b6}\u{6001}"
    ])
  }

  private static func downloadURL(in goal: String, lower: String) -> String? {
    let prefixes = ["download file ", "download ", "save file ", "\u{4e0b}\u{8f7d}\u{6587}\u{4ef6} ", "\u{4e0b}\u{8f7d}"]
    for prefix in prefixes where lower.hasPrefix(prefix) {
      let raw = String(goal.dropFirst(prefix.count))
      return normalizedHTTPURL(raw)
    }
    return nil
  }

  private static func downloadTitle(for urlString: String) -> String {
    guard let url = URL(string: urlString),
          !url.lastPathComponent.isEmpty,
          url.lastPathComponent != "/" else {
      return "SignalASI download"
    }
    return String(
      (url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent).prefix(240)
    )
  }

  private static func isDownloadQueryGoal(_ lower: String) -> Bool {
    containsAny(lower, ["query download", "download status", "check download", "\u{67e5}\u{770b}\u{4e0b}\u{8f7d}", "\u{4e0b}\u{8f7d}\u{72b6}\u{6001}", "\u{67e5}\u{8be2}\u{4e0b}\u{8f7d}"])
  }

  private static func isDownloadRemoveGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "remove download", "delete download", "cancel download", "\u{5220}\u{9664}\u{4e0b}\u{8f7d}", "\u{53d6}\u{6d88}\u{4e0b}\u{8f7d}"
    ])
  }

  private static func downloadID(in goal: String) -> Int? {
    let pattern = "(?:download|file|\u{4e0b}\u{8f7d})[^0-9]{0,24}([0-9]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let value = goal as NSString
    let range = NSRange(location: 0, length: value.length)
    guard let match = regex.firstMatch(in: goal, range: range),
          match.numberOfRanges > 1,
          let id = Int(value.substring(with: match.range(at: 1))),
          id > 0 else {
      return nil
    }
    return id
  }

  private static func isTelephonyCallStateGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "call state", "current call", "incoming call", "\u{901a}\u{8bdd}\u{72b6}\u{6001}", "\u{5f53}\u{524d}\u{901a}\u{8bdd}", "\u{6765}\u{7535}\u{72b6}\u{6001}"
    ])
  }

  private static func isTelephonyCallStateObserveGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "observe call", "wait for call", "watch call", "\u{76d1}\u{542c}\u{901a}\u{8bdd}", "\u{7b49}\u{5f85}\u{6765}\u{7535}", "\u{89c2}\u{5bdf}\u{901a}\u{8bdd}"
    ])
  }

  private static func isSMSListGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "read sms", "list sms", "sms inbox", "recent sms", "read text messages", "\u{8bfb}\u{53d6}\u{77ed}\u{4fe1}", "\u{77ed}\u{4fe1}\u{5217}\u{8868}", "\u{77ed}\u{4fe1}\u{6536}\u{4ef6}\u{7bb1}"
    ])
  }

  private static func contactSearchQuery(in goal: String, lower: String) -> String? {
    let prefixes = [
      "search contacts ", "find contacts ", "search contact ", "find contact ",
      "\u{641c}\u{7d22}\u{8054}\u{7cfb}\u{4eba}", "\u{67e5}\u{627e}\u{8054}\u{7cfb}\u{4eba}"
    ]
    for prefix in prefixes where lower.hasPrefix(prefix) {
      return String(goal.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).prefixString(160)
    }
    return [
      "search contacts", "find contacts", "search contact", "find contact",
      "contacts", "contact list", "\u{8054}\u{7cfb}\u{4eba}", "\u{8054}\u{7cfb}\u{4eba}\u{5217}\u{8868}"
    ].contains(lower) ? "" : nil
  }

  private static func isContactDeleteGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "delete contact", "remove contact", "erase contact",
      "\u{5220}\u{9664}\u{8054}\u{7cfb}\u{4eba}", "\u{79fb}\u{9664}\u{8054}\u{7cfb}\u{4eba}"
    ])
  }

  private static func contactID(in goal: String) -> Int? {
    numericIdentifier(in: goal, pattern: "(?:contact|contact id|\u{8054}\u{7cfb}\u{4eba})[^0-9]{0,24}([0-9]+)")
  }

  private static func isCalendarsListGoal(_ lower: String) -> Bool {
    containsAny(lower, ["list calendars", "calendar list", "show calendars", "\u{65e5}\u{5386}\u{5217}\u{8868}", "\u{67e5}\u{770b}\u{65e5}\u{5386}"])
  }

  private static func isCalendarEventsQueryGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "calendar events", "upcoming events", "today's events", "today events", "my schedule",
      "\u{65e5}\u{5386}\u{4e8b}\u{4ef6}", "\u{65e5}\u{7a0b}", "\u{4eca}\u{5929}\u{7684}\u{65e5}\u{7a0b}", "\u{8fd1}\u{671f}\u{65e5}\u{7a0b}"
    ])
  }

  private static func isCalendarEventDeleteGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "delete calendar event", "remove calendar event", "delete event", "remove event",
      "\u{5220}\u{9664}\u{65e5}\u{5386}\u{4e8b}\u{4ef6}", "\u{5220}\u{9664}\u{65e5}\u{7a0b}"
    ])
  }

  private static func calendarEventID(in goal: String) -> Int? {
    numericIdentifier(
      in: goal,
      pattern: "(?:calendar event|event|\u{65e5}\u{5386}\u{4e8b}\u{4ef6}|\u{65e5}\u{7a0b})[^0-9]{0,24}([0-9]+)"
    )
  }

  private static func numericIdentifier(in goal: String, pattern: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let value = goal as NSString
    let range = NSRange(location: 0, length: value.length)
    guard let match = regex.firstMatch(in: goal, range: range),
          match.numberOfRanges > 1,
          let identifier = Int(value.substring(with: match.range(at: 1))),
          identifier > 0 else {
      return nil
    }
    return identifier
  }

  private static func calendarEventWindow(for lower: String) -> (start: Int64, end: Int64) {
    let now = Date()
    let calendar = Calendar.current
    let start = lower.contains("today") || lower.contains("\u{4eca}\u{5929}") ? calendar.startOfDay(for: now) : now
    let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
    return (
      Int64(start.timeIntervalSince1970 * 1_000),
      Int64(end.timeIntervalSince1970 * 1_000)
    )
  }

  private static func isWifiScanResultsGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "scan wifi", "scan wi-fi", "wifi networks", "nearby wifi",
      "\u{626b}\u{63cf}wifi", "\u{626b}\u{63cf} wi-fi", "\u{9644}\u{8fd1}wifi", "wifi\u{7f51}\u{7edc}",
      "\u{626b}\u{63cf}\u{65e0}\u{7ebf}\u{7f51}\u{7edc}", "\u{9644}\u{8fd1}\u{65e0}\u{7ebf}\u{7f51}\u{7edc}", "\u{65e0}\u{7ebf}\u{7f51}\u{7edc}\u{5217}\u{8868}"
    ])
  }

  private static func isWifiScanStartGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "start wifi scan", "start wi-fi scan", "begin wifi scan",
      "\u{5f00}\u{59cb}\u{626b}\u{63cf}wifi", "\u{5f00}\u{59cb}\u{626b}\u{63cf} wi-fi", "\u{5f00}\u{59cb}\u{626b}\u{63cf}\u{65e0}\u{7ebf}\u{7f51}\u{7edc}"
    ])
  }

  private static func isAudioStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["audio status", "sound status", "volume status", "\u{97f3}\u{9891}\u{72b6}\u{6001}", "\u{58f0}\u{97f3}\u{72b6}\u{6001}", "\u{97f3}\u{91cf}\u{72b6}\u{6001}"])
  }

  private static func isBiometricStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "biometric status", "face id status", "touch id status", "biometric capability", "\u{751f}\u{7269}\u{8bc6}\u{522b}\u{72b6}\u{6001}", "\u{9762}\u{5bb9}id", "\u{89e6}\u{63a7}id"
    ])
  }

  private static func isVPNStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "vpn status", "is vpn on", "vpn connection status", "vpn\u{72b6}\u{6001}", "vpn\u{662f}\u{5426}\u{5f00}\u{542f}",
      "\u{865a}\u{62df}\u{4e13}\u{7528}\u{7f51}\u{7edc}\u{72b6}\u{6001}", "\u{865a}\u{62df}\u{4e13}\u{7f51}\u{72b6}\u{6001}"
    ])
  }

  private static func isDevicePolicyStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "device policy status", "device owner status", "management status", "\u{8bbe}\u{5907}\u{7b56}\u{7565}\u{72b6}\u{6001}", "\u{8bbe}\u{5907}\u{7ba1}\u{7406}\u{5458}\u{72b6}\u{6001}",
      "\u{8bbe}\u{5907}\u{7ba1}\u{7406}\u{72b6}\u{6001}", "\u{8bbe}\u{5907}\u{7ba1}\u{7406}\u{6743}\u{9650}"
    ])
  }

  private static func isPowerStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "battery saver", "low power", "power status", "\u{7701}\u{7535}\u{6a21}\u{5f0f}",
      "\u{4f4e}\u{7535}\u{91cf}\u{6a21}\u{5f0f}", "\u{7535}\u{6e90}\u{72b6}\u{6001}"
    ])
  }

  private static func isMemoryStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "phone memory", "phone ram", "device memory", "device ram", "available ram", "free ram", "ram status",
      "\u{624b}\u{673a}\u{5185}\u{5b58}", "\u{8bbe}\u{5907}\u{5185}\u{5b58}", "\u{8fd0}\u{884c}\u{5185}\u{5b58}",
      "\u{53ef}\u{7528}\u{5185}\u{5b58}", "\u{5269}\u{4f59}\u{5185}\u{5b58}", "\u{5185}\u{5b58}\u{5360}\u{7528}",
      "\u{5185}\u{5b58}\u{4f7f}\u{7528}", "\u{67e5}\u{5185}\u{5b58}", "\u{67e5}\u{770b}\u{5185}\u{5b58}", "\u{67e5}\u{8be2}\u{5185}\u{5b58}"
    ])
  }

  private static func isStorageStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["storage status", "phone storage", "device storage", "\u{5b58}\u{50a8}"])
  }

  private static func isNetworkStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["network status", "phone network", "device network", "\u{7f51}\u{7edc}\u{72b6}\u{6001}"])
  }

  private static func isLocationReadGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "current location",
      "phone location",
      "where am i",
      "location now",
      "\u{83b7}\u{53d6}\u{4f4d}\u{7f6e}",
      "\u{5f53}\u{524d}\u{4f4d}\u{7f6e}",
      "\u{624b}\u{673a}\u{4f4d}\u{7f6e}",
      "\u{6211}\u{5728}\u{54ea}\u{91cc}"
    ])
  }

  private static func isSensorListGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "list sensors",
      "device sensors",
      "sensor list",
      "\u{5217}\u{51fa}\u{4f20}\u{611f}\u{5668}",
      "\u{624b}\u{673a}\u{4f20}\u{611f}\u{5668}",
      "\u{4f20}\u{611f}\u{5668}\u{5217}\u{8868}"
    ])
  }

  private static func isSensorSampleGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "sample sensor",
      "read sensor",
      "sensor sample",
      "sensor data",
      "\u{8bfb}\u{53d6}\u{4f20}\u{611f}\u{5668}",
      "\u{4f20}\u{611f}\u{5668}\u{6570}\u{636e}",
      "\u{91c7}\u{6837}\u{4f20}\u{611f}\u{5668}"
    ])
  }

  private static func sensorType(in lower: String) -> String {
    if containsAny(lower, ["gyroscope", "gyro", "\u{9640}\u{87ba}\u{4eea}"]) { return "gyroscope" }
    if containsAny(lower, ["magnetic", "magnetometer", "\u{78c1}\u{529b}\u{8ba1}", "\u{78c1}\u{573a}"]) {
      return "magnetic_field"
    }
    if containsAny(lower, ["gravity", "\u{91cd}\u{529b}"]) { return "gravity" }
    if containsAny(lower, ["linear acceleration", "\u{7ebf}\u{6027}\u{52a0}\u{901f}\u{5ea6}"]) {
      return "linear_acceleration"
    }
    if containsAny(lower, ["rotation", "\u{65cb}\u{8f6c}"]) { return "rotation_vector" }
    return "accelerometer"
  }

  private static func isBluetoothStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "bluetooth status",
      "is bluetooth on",
      "\u{84dd}\u{7259}\u{72b6}\u{6001}",
      "\u{84dd}\u{7259}\u{662f}\u{5426}\u{6253}\u{5f00}"
    ])
  }

  private static func isBluetoothDiscoveryGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "discover bluetooth",
      "scan bluetooth",
      "nearby bluetooth",
      "\u{626b}\u{63cf}\u{84dd}\u{7259}",
      "\u{9644}\u{8fd1}\u{84dd}\u{7259}",
      "\u{53d1}\u{73b0}\u{84dd}\u{7259}\u{8bbe}\u{5907}"
    ])
  }

  private static func isBluetoothPairingGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "open bluetooth pairing",
      "pair bluetooth",
      "\u{6253}\u{5f00}\u{84dd}\u{7259}\u{914d}\u{5bf9}",
      "\u{84dd}\u{7259}\u{914d}\u{5bf9}",
      "\u{914d}\u{5bf9}\u{84dd}\u{7259}"
    ])
  }

  private static func isNFCStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "nfc status",
      "is nfc on",
      "check nfc",
      "nfc\u{72b6}\u{6001}",
      "nfc\u{662f}\u{5426}\u{6253}\u{5f00}",
      "\u{8fd1}\u{573a}\u{901a}\u{4fe1}\u{72b6}\u{6001}", "\u{8fd1}\u{573a}\u{901a}\u{4fe1}\u{662f}\u{5426}\u{5f00}\u{542f}"
    ])
  }

  private static func installedAppsQuery(goal: String, lower: String) -> String? {
    let searchPrefixes = [
      "search installed apps",
      "find installed apps",
      "\u{641c}\u{7d22}\u{5df2}\u{5b89}\u{88c5}\u{5e94}\u{7528}",
      "\u{67e5}\u{627e}\u{5df2}\u{5b89}\u{88c5}\u{5e94}\u{7528}"
    ]
    if let prefix = searchPrefixes.first(where: { lower.hasPrefix($0) }) {
      return String(goal.dropFirst(prefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefixString(160)
    }
    guard containsAny(lower, [
      "list installed apps",
      "installed applications",
      "installed app list",
      "\u{5df2}\u{5b89}\u{88c5}\u{5e94}\u{7528}",
      "\u{5e94}\u{7528}\u{5217}\u{8868}",
      "\u{5217}\u{51fa}\u{5df2}\u{5b89}\u{88c5}app"
    ]) else {
      return nil
    }
    return ""
  }

  private static func packageName(in goal: String, lower: String) -> String? {
    guard containsAny(lower, [
      "package detail",
      "package info",
      "app package",
      "\u{5e94}\u{7528}\u{5305}\u{540d}",
      "\u{5e94}\u{7528}\u{8be6}\u{60c5}"
    ]),
    let regex = try? NSRegularExpression(
      pattern: #"\b[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+\b"#
    ) else {
      return nil
    }
    let nsGoal = goal as NSString
    let range = NSRange(location: 0, length: nsGoal.length)
    guard let match = regex.firstMatch(in: goal, range: range) else { return nil }
    return nsGoal.substring(with: match.range).prefixString(255)
  }

  private static func isWifiStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["wifi status", "wi-fi status", "wireless status", "\u{65e0}\u{7ebf}\u{7f51}\u{7edc}\u{72b6}\u{6001}", "\u{65e0}\u{7ebf}\u{7f51}\u{72b6}\u{6001}"]) ||
      (containsAny(lower, ["wifi", "wi-fi"]) && lower.contains("status"))
  }

  private static func isWifiSettingsGoal(_ lower: String) -> Bool {
    containsAny(lower, [
      "open wifi settings", "open wi-fi settings", "wifi settings", "wi-fi settings",
      "\u{6253}\u{5f00}\u{65e0}\u{7ebf}\u{7f51}\u{7edc}\u{8bbe}\u{7f6e}", "\u{65e0}\u{7ebf}\u{7f51}\u{7edc}\u{8bbe}\u{7f6e}"
    ])
  }

  private static func isVolumeSetGoal(_ lower: String) -> Bool {
    containsAny(lower, ["set volume", "media volume", "\u{97f3}\u{91cf}"]) && firstPercent(in: lower) != nil
  }

  private static func isMuteGoal(_ lower: String) -> Bool {
    containsAny(lower, ["mute", "unmute", "\u{9759}\u{97f3}", "\u{53d6}\u{6d88}\u{9759}\u{97f3}"])
  }

  private static func isUnmuteGoal(_ lower: String) -> Bool {
    containsAny(lower, ["unmute", "turn sound on", "\u{53d6}\u{6d88}\u{9759}\u{97f3}", "\u{89e3}\u{9664}\u{9759}\u{97f3}"])
  }

  private static func isDialGoal(_ lower: String) -> Bool {
    containsAny(lower, ["dial ", "call ", "phone call", "\u{62e8}\u{53f7}", "\u{6253}\u{7535}\u{8bdd}"])
  }

  private static func isSMSGoal(_ lower: String) -> Bool {
    containsAny(lower, ["send sms", "text ", "send message", "\u{53d1}\u{9001}\u{77ed}\u{4fe1}", "\u{53d1}\u{6d88}\u{606f}"])
  }

  private static func isCameraCaptureGoal(_ lower: String) -> Bool {
    guard !isExplanationOnlyGoal(lower) else { return false }
    let hasCamera = containsAny(lower, ["camera", "\u{76f8}\u{673a}", "\u{6444}\u{50cf}\u{5934}"])
    let hasCapture = containsAny(lower, ["take photo", "take a photo", "capture photo", "snap photo", "\u{62cd}\u{7167}"])
    let hasOpenAction = containsAny(
      lower,
      ["open", "launch", "use", "\u{6253}\u{5f00}", "\u{542f}\u{52a8}", "\u{8c03}\u{7528}", "\u{4f7f}\u{7528}"]
    )
    return hasCapture || (hasCamera && hasOpenAction)
  }

  private static func isMicrophoneCaptureGoal(_ lower: String) -> Bool {
    guard !isExplanationOnlyGoal(lower) else { return false }
    let hasMicrophone = containsAny(lower, ["microphone", "mic", "\u{9ea6}\u{514b}\u{98ce}"])
    let hasRecording = containsAny(
      lower,
      ["record audio", "record voice", "record sound", "start recording", "\u{5f55}\u{97f3}", "\u{5f55}\u{5236}"]
    )
    let hasUseAction = containsAny(
      lower,
      ["open", "start", "use", "\u{6253}\u{5f00}", "\u{5f00}\u{59cb}", "\u{8c03}\u{7528}", "\u{4f7f}\u{7528}"]
    )
    return hasRecording || (hasMicrophone && hasUseAction)
  }

  private static func audioDurationSeconds(for lower: String) -> Int {
    clampAudioDuration(durationSecondsFromDigitUnit(in: lower) ?? durationSecondsFromSpokenUnit(in: lower) ??
      AgentIOSVisibleCaptureNativeToolCatalog.defaultAudioDurationSeconds)
  }

  private static func timerDurationSeconds(for lower: String) -> Int? {
    guard let seconds = durationSecondsFromDigitUnit(in: lower) ?? durationSecondsFromSpokenUnit(in: lower) else {
      return nil
    }
    return max(1, min(seconds, maximumTimerDurationSeconds))
  }

  private static func durationSecondsFromDigitUnit(in value: String) -> Int? {
    let pattern = "([0-9]+)\\s*" +
      "(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|\u{79d2}\u{949f}?|\u{5206}\u{949f}?|\u{5c0f}\u{65f6})"
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let nsValue = value as NSString
    let range = NSRange(location: 0, length: nsValue.length)
    guard let match = regex.firstMatch(in: value, range: range),
          match.numberOfRanges >= 3,
          let amount = Int(nsValue.substring(with: match.range(at: 1))) else {
      return nil
    }
    return amount * durationMultiplier(for: nsValue.substring(with: match.range(at: 2)))
  }

  private static func durationSecondsFromSpokenUnit(in value: String) -> Int? {
    for (phrase, amount) in spokenDurations {
      if containsDurationPhrase(value, phrase: phrase, unitTerms: ["second", "seconds", "sec", "secs"]) {
        return amount
      }
      if containsDurationPhrase(value, phrase: phrase, unitTerms: ["minute", "minutes", "min", "mins"]) {
        return amount * 60
      }
      if containsDurationPhrase(value, phrase: phrase, unitTerms: ["hour", "hours", "hr", "hrs"]) {
        return amount * 3_600
      }
    }
    return nil
  }

  private static func containsDurationPhrase(_ value: String, phrase: String, unitTerms: [String]) -> Bool {
    unitTerms.contains { value.contains("\(phrase) \($0)") }
  }

  private static func durationMultiplier(for unit: String) -> Int {
    if unit.hasPrefix("h") || unit == "\u{5c0f}\u{65f6}" {
      return 3_600
    }
    if unit.hasPrefix("m") || unit.hasPrefix("\u{5206}") {
      return 60
    }
    return 1
  }

  private static func clampAudioDuration(_ seconds: Int) -> Int {
    max(1, min(seconds, AgentIOSVisibleCaptureNativeToolCatalog.maxAudioDurationSeconds))
  }

  private static let spokenDurations: [(String, Int)] = [
    ("forty five", 45), ("forty-five", 45), ("thirty", 30), ("twenty", 20),
    ("fifteen", 15), ("fourteen", 14), ("thirteen", 13), ("twelve", 12),
    ("eleven", 11), ("ten", 10), ("nine", 9), ("eight", 8), ("seven", 7),
    ("six", 6), ("five", 5), ("four", 4), ("three", 3), ("two", 2),
    ("one", 1), ("an", 1), ("a", 1)
  ]

  private static func isExplanationOnlyGoal(_ lower: String) -> Bool {
    containsAny(
      lower,
      ["explain", "what is", "what are", "how does", "how do", "\u{89e3}\u{91ca}", "\u{4ecb}\u{7ecd}", "\u{8bf4}\u{660e}"]
    )
  }

  private static func contactUpsertDraft(goal: String, lower: String) -> ContactUpsertDraft? {
    let raw: Substring
    if lower.hasPrefix("add contact ") {
      raw = goal.dropFirst("add contact ".count)
    } else if lower.hasPrefix("create contact ") {
      raw = goal.dropFirst("create contact ".count)
    } else {
      return nil
    }
    var nameSource = String(raw)
    let parsed = contactPhone(in: nameSource)
    if let rawPhone = parsed.rawPhone {
      nameSource = nameSource.replacingOccurrences(of: rawPhone, with: " ")
    }
    let displayName = cleanContactName(nameSource)
    guard !displayName.isEmpty else { return nil }
    return ContactUpsertDraft(
      displayName: displayName.prefixString(160),
      phoneNumber: (parsed.number ?? "").prefixString(64)
    )
  }

  private static func contactPhone(in value: String) -> (number: String?, rawPhone: String?) {
    guard let range = value.range(
      of: #"\+?[0-9][0-9\s().-]{2,}[0-9]"#,
      options: .regularExpression
    ) else {
      return (nil, nil)
    }
    let rawPhone = String(value[range])
    var normalized = rawPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" ", "-", "(", ")", "."] {
      normalized = normalized.replacingOccurrences(of: removable, with: "")
    }
    return (normalized.isEmpty ? nil : normalized, rawPhone)
  }

  private static func cleanContactName(_ value: String) -> String {
    var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" with number ", " phone ", " number ", " tel ", ":", ","] {
      clean = clean.replacingOccurrences(of: removable, with: " ", options: .caseInsensitive)
    }
    return clean
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private struct ContactUpsertDraft {
    var displayName: String
    var phoneNumber: String
  }

  private static func urlHandoff(goal: String, lower: String) -> URLHandoff? {
    let openURLPrefixes = [
      "open url ", "open website ",
      "\u{6253}\u{5f00}\u{7f51}\u{5740} ", "\u{6253}\u{5f00}\u{7f51}\u{7ad9} ",
      "\u{8bbf}\u{95ee}\u{7f51}\u{5740} ", "\u{8bbf}\u{95ee}\u{7f51}\u{7ad9} "
    ]
    if let prefix = openURLPrefixes.first(where: { lower.hasPrefix($0) }) {
      let raw = goal.dropFirst(prefix.count)
      guard let url = normalizedHTTPURL(String(raw)) else { return nil }
      return URLHandoff(
        idPrefix: "open-url",
        target: url,
        url: url,
        description: "Open URL"
      )
    }
    let webSearchPrefixes = [
      "search web ", "google ",
      "\u{641c}\u{7d22}\u{7f51}\u{9875} ", "\u{7f51}\u{9875}\u{641c}\u{7d22} ", "\u{641c}\u{7d22}\u{4e92}\u{8054}\u{7f51} "
    ]
    if let prefix = webSearchPrefixes.first(where: { lower.hasPrefix($0) }) {
      let raw = goal.dropFirst(prefix.count)
      guard let query = encodedURLQuery(String(raw)) else { return nil }
      return URLHandoff(
        idPrefix: "search-web",
        target: "Web Search",
        url: "https://www.google.com/search?q=\(query)",
        description: "Search the web"
      )
    }
    let mapPrefixes = [
      "open map ", "map ", "navigate to ",
      "\u{6253}\u{5f00}\u{5730}\u{56fe} ", "\u{5730}\u{56fe} ", "\u{5bfc}\u{822a}\u{5230} ", "\u{524d}\u{5f80} "
    ]
    if let prefix = mapPrefixes.first(where: { lower.hasPrefix($0) }) {
      let raw = goal.dropFirst(prefix.count)
      guard let query = encodedURLQuery(String(raw)) else { return nil }
      return URLHandoff(
        idPrefix: "open-map",
        target: "Maps",
        url: "https://maps.apple.com/?q=\(query)",
        description: "Open map location"
      )
    }
    return nil
  }

  private static func normalizedHTTPURL(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    if lower.contains("://") && !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
      return nil
    }
    let candidate = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
    guard let components = URLComponents(string: candidate),
          ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
          !(components.host ?? "").isEmpty else {
      return nil
    }
    return candidate.prefixString(2_048)
  }

  private static func encodedURLQuery(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=?+")
    return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)?.prefixString(2_048)
  }

  private struct URLHandoff {
    var idPrefix: String
    var target: String
    var url: String
    var description: String
  }

  private static func systemAppHandoff(for lower: String) -> SystemAppHandoff? {
    if containsAny(
      lower,
      [
        "open gallery", "open photos", "open photo library",
        "\u{6253}\u{5f00}\u{76f8}\u{518c}", "\u{6253}\u{5f00}\u{7167}\u{7247}"
      ]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-photos",
        target: "Photos",
        bundleId: "com.apple.mobileslideshow"
      )
    }
    if containsAny(
      lower,
      ["open browser", "open safari", "launch safari", "\u{6253}\u{5f00}\u{6d4f}\u{89c8}\u{5668}", "\u{6253}\u{5f00}safari"]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-safari",
        target: "Safari",
        bundleId: "com.apple.mobilesafari"
      )
    }
    if containsAny(
      lower,
      [
        "open contacts", "open address book",
        "\u{6253}\u{5f00}\u{901a}\u{8baf}\u{5f55}", "\u{6253}\u{5f00}\u{8054}\u{7cfb}\u{4eba}"
      ]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-contacts",
        target: "Contacts",
        bundleId: "com.apple.MobileAddressBook"
      )
    }
    if containsAny(lower, ["open calendar", "\u{6253}\u{5f00}\u{65e5}\u{5386}"]) {
      return SystemAppHandoff(
        idPrefix: "open-calendar",
        target: "Calendar",
        bundleId: "com.apple.mobilecal"
      )
    }
    if containsAny(
      lower,
      ["open files", "open file manager", "open documents", "\u{6253}\u{5f00}\u{6587}\u{4ef6}"]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-files",
        target: "Files",
        bundleId: "com.apple.DocumentsApp"
      )
    }
    if containsAny(
      lower,
      ["open messages", "open sms", "\u{6253}\u{5f00}\u{4fe1}\u{606f}", "\u{6253}\u{5f00}\u{77ed}\u{4fe1}"]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-messages",
        target: "Messages",
        bundleId: "com.apple.MobileSMS"
      )
    }
    if containsAny(
      lower,
      ["open phone", "open dialer", "\u{6253}\u{5f00}\u{7535}\u{8bdd}", "\u{6253}\u{5f00}\u{62e8}\u{53f7}\u{76d8}"]
    ) {
      return SystemAppHandoff(
        idPrefix: "open-phone",
        target: "Phone",
        bundleId: "com.apple.mobilephone"
      )
    }
    return nil
  }

  private struct SystemAppHandoff {
    var idPrefix: String
    var target: String
    var bundleId: String
  }

  private static func blockedSensitiveAction(goal: String, lower: String) -> AgentAction? {
    if containsAny(
      lower,
      ["install apk", "install app", "unknown app sources", "install unknown apps", "apk install permission"]
    ) {
      return blockedAction(
        id: "blocked-app-installation",
        target: "Package Manager",
        description: "App installation or installation-source changes require explicit owner control.",
        goal: goal
      )
    }
    if containsAny(
      lower,
      [
        "uninstall app", "delete app", "factory reset", "erase phone", "clear all data",
        "\u{5378}\u{8f7d}", "\u{6062}\u{590d}\u{51fa}\u{5382}"
      ]
    ) {
      return blockedAction(
        id: "blocked-device-wipe-or-removal",
        target: "Device Administration",
        description: "App removal or device wipe requests are blocked by phone safety policy.",
        goal: goal
      )
    }
    if containsAny(lower, ["unlock phone", "disable lock", "change screen lock"]) {
      return blockedAction(
        id: "blocked-lock-control",
        target: "Screen Lock",
        description: "Unlocking or weakening the screen lock is blocked by phone safety policy.",
        goal: goal
      )
    }
    if containsAny(lower, ["answer call", "listen call", "record call"]) {
      return blockedAction(
        id: "blocked-call-control",
        target: "Phone Call",
        description: "Phone call handling or call recording requires explicit owner control.",
        goal: goal
      )
    }
    if containsAny(lower, ["send wechat", "reply wechat", "send message to"]) {
      return blockedAction(
        id: "blocked-third-party-send",
        target: "Third-party messaging",
        description: "Sending third-party messages is blocked unless routed through an explicit supported tool.",
        goal: goal
      )
    }
    if containsAny(
      lower,
      [
        "make payment", "transfer money", "purchase", "checkout", "place order",
        "\u{652f}\u{4ed8}", "\u{8f6c}\u{8d26}", "\u{8d2d}\u{4e70}"
      ]
    ) ||
      lower.hasPrefix("pay ") {
      return blockedAction(
        id: "blocked-payment-order",
        target: "Payment or Order",
        description: "Payment, transfer, purchase, and order submission are blocked by phone safety policy.",
        goal: goal
      )
    }
    if containsAny(
      lower,
      [
        "authorize login", "approve login", "grant permission", "share password", "share private key",
        "export private key", "export api key", "seed phrase", "\u{6388}\u{6743}\u{767b}\u{5f55}",
        "\u{5206}\u{4eab}\u{5bc6}\u{7801}", "\u{5bfc}\u{51fa}\u{79c1}\u{94a5}"
      ]
    ) {
      return blockedAction(
        id: "blocked-credential-permission",
        target: "Credentials and Permissions",
        description: "Credentials, login approvals, and permission grants are blocked by phone safety policy.",
        goal: goal
      )
    }
    return nil
  }

  private static func blockedAction(id: String, target: String, description: String, goal: String) -> AgentAction {
    AgentAction(
      id: id,
      kind: .draftPlan,
      target: target,
      risk: .blocked,
      status: .blocked,
      description: description,
      parameters: [
        "blocked_reason": description,
        "original_goal": goal.prefixString(500)
      ],
      requiresConfirmation: false
    )
  }

  private static func isTimerGoal(_ lower: String) -> Bool {
    guard timerDurationSeconds(for: lower) != nil else { return false }
    let hasTimerTerm = containsAny(lower, ["timer", "countdown", "\u{8ba1}\u{65f6}\u{5668}", "\u{5012}\u{8ba1}\u{65f6}"])
    let hasStartAction = containsAny(
      lower,
      ["set", "start", "create", "begin", "run", "\u{8bbe}\u{7f6e}", "\u{5f00}\u{59cb}"]
    )
    return hasTimerTerm && hasStartAction
  }

  private static func isAlarmGoal(_ lower: String) -> Bool {
    alarmClockTime(in: lower) != nil &&
      containsAny(lower, ["set alarm", "alarm at", "alarm for", "\u{95f9}\u{949f}"])
  }

  private static func alarmClockTime(in value: String) -> (hour: Int, minute: Int)? {
    guard let regex = try? NSRegularExpression(pattern: "\\b([0-9]{1,2}):([0-9]{2})\\b") else {
      return nil
    }
    let nsValue = value as NSString
    let range = NSRange(location: 0, length: nsValue.length)
    guard let match = regex.firstMatch(in: value, range: range),
          match.numberOfRanges >= 3,
          let hour = Int(nsValue.substring(with: match.range(at: 1))),
          let minute = Int(nsValue.substring(with: match.range(at: 2))),
          (0...23).contains(hour),
          (0...59).contains(minute) else {
      return nil
    }
    return (hour, minute)
  }

  private static func actionAdapterInput(
    target: String,
    parameters: [String: String],
    topLevel: AgentMcpJSONObject = [:]
  ) -> AgentMcpJSONObject {
    var input = topLevel
    input["target"] = .string(target)
    input["parameters"] = .object(parameters.reduce(into: AgentMcpJSONObject()) { result, entry in
      result[entry.key] = .string(entry.value)
    })
    return input
  }

  private static let maximumTimerDurationSeconds = 24 * 60 * 60

  private static func isFlashlightGoal(_ lower: String) -> Bool {
    containsAny(lower, ["flashlight", "torch", "\u{624b}\u{7535}\u{7b52}"])
  }

  private static func isTurnOffGoal(_ lower: String) -> Bool {
    containsAny(lower, ["turn off", "switch off", "disable", "\u{5173}\u{95ed}", "\u{5173}\u{6389}"])
  }

  private static func containsAny(_ value: String, _ terms: [String]) -> Bool {
    terms.contains { value.contains($0) }
  }
}

enum AgentScreenOverviewCommand {
  static func matches(_ goal: String) -> Bool {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "screen status", "inspect screen", "read current screen", "screen elements",
         "show screen elements", "screen structure", "show screen structure",
         "\u{8bfb}\u{53d6}\u{5f53}\u{524d}\u{5c4f}\u{5e55}", "\u{67e5}\u{770b}\u{5f53}\u{524d}\u{5c4f}\u{5e55}", "\u{8bfb}\u{53d6}\u{5c4f}\u{5e55}", "\u{67e5}\u{770b}\u{5c4f}\u{5e55}", "\u{5c4f}\u{5e55}\u{72b6}\u{6001}", "\u{5c4f}\u{5e55}\u{5143}\u{7d20}":
      return true
    default:
      return false
    }
  }
}

enum AgentTaskHistoryCommand: Equatable {
  case recent
  case search(String)

  static func parse(_ goal: String) -> AgentTaskHistoryCommand? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = clean.lowercased()
    guard !clean.isEmpty else { return nil }

    switch normalized {
    case "recent tasks", "show recent tasks", "task history", "show task history",
         "last tasks", "show last tasks",
         "\u{6700}\u{8fd1}\u{4efb}\u{52a1}", "\u{67e5}\u{770b}\u{6700}\u{8fd1}\u{4efb}\u{52a1}",
         "\u{4efb}\u{52a1}\u{5386}\u{53f2}", "\u{67e5}\u{770b}\u{4efb}\u{52a1}\u{5386}\u{53f2}":
      return .recent
    default:
      break
    }

    let prefixes = [
      "search tasks ", "find tasks ", "search task ", "find task ",
      "\u{641c}\u{7d22}\u{4efb}\u{52a1} ", "\u{67e5}\u{627e}\u{4efb}\u{52a1} ",
      "\u{641c}\u{7d22}\u{4efb}\u{52a1}\u{5386}\u{53f2} ", "\u{67e5}\u{627e}\u{4efb}\u{52a1}\u{5386}\u{53f2} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    let query = String(clean.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? nil : .search(query)
  }
}

enum AgentTaskControlCommand {
  case approve
  case retry
  case pause
  case resume
  case replan
  case rollback
  case cancel

  static func parse(_ goal: String) -> AgentTaskControlCommand? {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "approve", "confirm", "approve next", "confirm next", "run next", "execute next",
         "\u{6279}\u{51c6}", "\u{786e}\u{8ba4}", "\u{6279}\u{51c6}\u{4e0b}\u{4e00}\u{6b65}", "\u{6267}\u{884c}\u{4e0b}\u{4e00}\u{6b65}":
      return .approve
    case "retry", "retry task", "retry action", "retry failed action", "try again",
         "\u{91cd}\u{8bd5}", "\u{91cd}\u{8bd5}\u{4efb}\u{52a1}", "\u{518d}\u{8bd5}\u{4e00}\u{6b21}":
      return .retry
    case "pause", "pause task", "pause execution", "\u{6682}\u{505c}", "\u{6682}\u{505c}\u{4efb}\u{52a1}":
      return .pause
    case "resume", "resume task", "resume execution", "continue task",
         "\u{7ee7}\u{7eed}", "\u{7ee7}\u{7eed}\u{4efb}\u{52a1}":
      return .resume
    case "replan", "replan task", "update plan", "plan again",
         "\u{91cd}\u{65b0}\u{89c4}\u{5212}", "\u{66f4}\u{65b0}\u{8ba1}\u{5212}":
      return .replan
    case "rollback", "rollback task", "undo last action", "restore checkpoint",
         "\u{56de}\u{6eda}", "\u{64a4}\u{9500}\u{6700}\u{540e}\u{4e00}\u{6b21}\u{64cd}\u{4f5c}":
      return .rollback
    case "cancel", "cancel task", "stop task", "abort task",
         "\u{53d6}\u{6d88}", "\u{53d6}\u{6d88}\u{4efb}\u{52a1}", "\u{505c}\u{6b62}\u{4efb}\u{52a1}":
      return .cancel
    default:
      return nil
    }
  }
}

enum AgentClearTaskHistoryCommand {
  static func matches(_ goal: String) -> Bool {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "clear task history", "clear recent tasks", "delete task history", "delete recent tasks",
         "\u{6e05}\u{9664}\u{4efb}\u{52a1}\u{5386}\u{53f2}", "\u{6e05}\u{7a7a}\u{6700}\u{8fd1}\u{4efb}\u{52a1}",
         "\u{5220}\u{9664}\u{4efb}\u{52a1}\u{5386}\u{53f2}", "\u{5220}\u{9664}\u{6700}\u{8fd1}\u{4efb}\u{52a1}":
      return true
    default:
      return false
    }
  }
}

enum AgentScreenSearchCommand {
  static func query(_ goal: String) -> String? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = clean.lowercased()
    let prefixes = [
      "search screen elements ", "find screen element ",
      "search screen ", "find on screen ",
      "\u{641c}\u{7d22}\u{5c4f}\u{5e55}\u{5143}\u{7d20} ", "\u{67e5}\u{627e}\u{5c4f}\u{5e55}\u{5143}\u{7d20} ", "\u{641c}\u{7d22}\u{5c4f}\u{5e55} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    let value = String(clean.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

enum AgentSecurityStatusCommand {
  static func matches(_ goal: String) -> Bool {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "security status", "permission status", "agent security status",
         "agent permission status", "safety status", "privacy status",
         "\u{5b89}\u{5168}\u{72b6}\u{6001}", "\u{6743}\u{9650}\u{72b6}\u{6001}",
         "agent \u{5b89}\u{5168}\u{72b6}\u{6001}", "agent \u{6743}\u{9650}\u{72b6}\u{6001}",
         "\u{5b89}\u{5168}\u{8bbe}\u{7f6e}", "\u{9690}\u{79c1}\u{72b6}\u{6001}":
      return true
    default:
      return false
    }
  }
}

enum AgentAuditTrailCommand {
  static func matches(_ goal: String) -> Bool {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "audit trail", "show audit trail", "audit log", "show audit log",
         "execution log", "show execution log",
         "\u{5ba1}\u{8ba1}\u{65e5}\u{5fd7}", "\u{663e}\u{793a}\u{5ba1}\u{8ba1}\u{65e5}\u{5fd7}",
         "\u{6267}\u{884c}\u{65e5}\u{5fd7}", "\u{663e}\u{793a}\u{6267}\u{884c}\u{65e5}\u{5fd7}":
      return true
    default:
      return false
    }
  }
}

enum AgentNotificationCommand: Equatable {
  case inbox
  case search(String)

  static func parse(_ goal: String) -> AgentNotificationCommand? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = clean.lowercased()
    switch normalized {
    case "notifications", "read notifications", "list notifications", "show notifications",
         "notification inbox", "show notification inbox",
         "\u{901a}\u{77e5}", "\u{663e}\u{793a}\u{901a}\u{77e5}", "\u{901a}\u{77e5}\u{6536}\u{4ef6}\u{7bb1}":
      return .inbox
    default:
      break
    }
    let prefixes = [
      "search notifications ", "find notifications ",
      "search notification ", "find notification ",
      "\u{641c}\u{7d22}\u{901a}\u{77e5} ", "\u{67e5}\u{627e}\u{901a}\u{77e5} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    let query = String(clean.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? nil : .search(query)
  }
}

enum AgentPermissionModeCommand {
  static func mode(_ goal: String) -> AgentPermissionMode? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = clean.lowercased()
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
    let prefixes = [
      "set permission mode ", "permission mode ",
      "set agent mode ", "agent mode ",
      "\u{8bbe}\u{7f6e}\u{6743}\u{9650}\u{6a21}\u{5f0f} ",
      "\u{6743}\u{9650}\u{6a21}\u{5f0f} ",
      "\u{8bbe}\u{7f6e} agent \u{6a21}\u{5f0f} ",
      "agent \u{6a21}\u{5f0f} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    let value = String(normalized.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    switch value {
    case "observe", "observe only", "read only", "readonly", "\u{4ec5}\u{89c2}\u{5bdf}", "\u{53ea}\u{8bfb}":
      return .observeOnly
    case "suggest", "suggest only", "assist", "assisted", "\u{5efa}\u{8bae}", "\u{4ec5}\u{5efa}\u{8bae}":
      return .suggestOnly
    case "confirm", "ask", "ask first", "ask before action", "\u{786e}\u{8ba4}", "\u{64cd}\u{4f5c}\u{524d}\u{786e}\u{8ba4}":
      return .askBeforeAction
    case "auto", "automatic", "auto low risk", "low risk auto", "\u{81ea}\u{52a8}", "\u{4f4e}\u{98ce}\u{9669}\u{81ea}\u{52a8}":
      return .autoLowRisk
    default:
      return nil
    }
  }
}

enum AgentHighRiskGuardCommand {
  static func enabled(_ goal: String) -> Bool? {
    let normalized = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
    let prefixes = [
      "set high risk guard ", "high risk guard ",
      "\u{8bbe}\u{7f6e}\u{9ad8}\u{98ce}\u{9669}\u{4fdd}\u{62a4} ",
      "\u{9ad8}\u{98ce}\u{9669}\u{4fdd}\u{62a4} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    switch String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) {
    case "on", "enable", "enabled", "\u{5f00}\u{542f}", "\u{542f}\u{7528}":
      return true
    case "off", "disable", "disabled", "\u{5173}\u{95ed}", "\u{7981}\u{7528}":
      return false
    default:
      return nil
    }
  }
}

enum AgentPermissionChecklistCommand {
  static func matches(_ goal: String) -> Bool {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "permission checklist", "show permission checklist", "check permissions",
         "agent permissions", "show agent permissions", "missing permissions",
         "\u{6743}\u{9650}\u{6e05}\u{5355}", "\u{663e}\u{793a}\u{6743}\u{9650}\u{6e05}\u{5355}",
         "\u{68c0}\u{67e5}\u{6743}\u{9650}", "agent \u{6743}\u{9650}",
         "\u{663e}\u{793a} agent \u{6743}\u{9650}", "\u{7f3a}\u{5c11}\u{6743}\u{9650}":
      return true
    default:
      return false
    }
  }
}

enum AgentCallableInventorySearchCommand {
  static func query(_ goal: String) -> String? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = clean.lowercased()
    let prefixes = [
      "search tools ", "find tools ", "search tool ", "find tool ",
      "search capabilities ", "find capabilities ", "search capability ", "find capability ",
      "search agents ", "find agents ", "search models ", "find models ",
      "\u{641c}\u{7d22}\u{5de5}\u{5177} ", "\u{67e5}\u{627e}\u{5de5}\u{5177} ", "\u{641c}\u{7d22}\u{80fd}\u{529b} ", "\u{67e5}\u{627e}\u{80fd}\u{529b} ",
      "\u{641c}\u{7d22} agent ", "\u{641c}\u{7d22}\u{667a}\u{80fd}\u{4f53} ", "\u{67e5}\u{627e}\u{667a}\u{80fd}\u{4f53} ", "\u{641c}\u{7d22}\u{4ee3}\u{7406} ", "\u{67e5}\u{627e}\u{4ee3}\u{7406} ", "\u{641c}\u{7d22}\u{6a21}\u{578b} "
    ]
    guard let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) else {
      return nil
    }
    let value = String(clean.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

enum AgentCallableInventoryFilter {
  case tools
  case agents
  case models
  case devices
  case capabilities
  case all
}

enum AgentCallableInventoryCommand {
  static func filter(_ goal: String) -> AgentCallableInventoryFilter? {
    switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "list tools", "show tools", "available tools", "list system tools", "show system tools",
         "\u{5217}\u{51fa}\u{5de5}\u{5177}", "\u{663e}\u{793a}\u{5de5}\u{5177}":
      return .tools
    case "list agents", "show agents", "available agents", "\u{5217}\u{51fa} agent", "\u{663e}\u{793a} agent",
         "\u{5217}\u{51fa}\u{667a}\u{80fd}\u{4f53}", "\u{663e}\u{793a}\u{667a}\u{80fd}\u{4f53}", "\u{5217}\u{51fa}\u{4ee3}\u{7406}", "\u{663e}\u{793a}\u{4ee3}\u{7406}":
      return .agents
    case "list models", "show models", "available models", "\u{5217}\u{51fa}\u{6a21}\u{578b}", "\u{663e}\u{793a}\u{6a21}\u{578b}":
      return .models
    case "list devices", "show devices", "available devices", "\u{5217}\u{51fa}\u{8bbe}\u{5907}", "\u{663e}\u{793a}\u{8bbe}\u{5907}":
      return .devices
    case "list capabilities", "show capabilities", "list callable targets", "show callable targets",
         "what can you do", "\u{5217}\u{51fa}\u{80fd}\u{529b}", "\u{663e}\u{793a}\u{80fd}\u{529b}", "\u{4f60}\u{80fd}\u{505a}\u{4ec0}\u{4e48}":
      return .all
    default:
      return nil
    }
  }
}

private extension String {
  func prefixString(_ limit: Int) -> String {
    String(prefix(max(0, limit)))
  }
}

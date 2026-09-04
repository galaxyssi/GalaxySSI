import Foundation

enum AgentIOSSystemNativeToolCatalog {
  static let telephonyStatus = "galaxyssi.android.telephony.status"
  static let telephonyCallState = "galaxyssi.android.telephony.call_state"
  static let telephonyCallStateObserve = "galaxyssi.android.telephony.call_state.observe"
  static let telephonyDialHandoff = "galaxyssi.android.telephony.dial.handoff"
  static let smsList = "galaxyssi.android.sms.list"
  static let smsSend = "galaxyssi.android.sms.send"
  static let smsComposeHandoff = "galaxyssi.android.sms.compose.handoff"
  static let contactsSearch = "galaxyssi.android.contacts.search"
  static let contactsUpsert = "galaxyssi.android.contacts.upsert"
  static let contactsDelete = "galaxyssi.android.contacts.delete"
  static let calendarsList = "galaxyssi.android.calendar.calendars.list"
  static let calendarEventsQuery = "galaxyssi.android.calendar.events.query"
  static let calendarEventUpsert = "galaxyssi.android.calendar.event.upsert"
  static let calendarEventDelete = "galaxyssi.android.calendar.event.delete"
  static let wifiStatus = "galaxyssi.android.wifi.status"
  static let wifiScanResults = "galaxyssi.android.wifi.scan_results"
  static let wifiScanStart = "galaxyssi.android.wifi.scan.start"
  static let wifiPanelOpen = "galaxyssi.android.wifi.panel.open"
  static let wifiHotspotPanelOpen = "galaxyssi.android.wifi.hotspot.panel.open"
  static let audioStatus = "galaxyssi.android.audio.status"
  static let audioVolumeSet = "galaxyssi.android.audio.volume.set"
  static let audioMuteSet = "galaxyssi.android.audio.mute.set"
  static let downloadEnqueue = "galaxyssi.android.download.enqueue"
  static let downloadQuery = "galaxyssi.android.download.query"
  static let downloadRemove = "galaxyssi.android.download.remove"
  static let biometricStatus = "galaxyssi.android.biometric.status"
  static let biometricEnrollmentOpen = "galaxyssi.android.biometric.enrollment.open"
  static let vpnStatus = "galaxyssi.android.vpn.status"
  static let vpnConsentOpen = "galaxyssi.android.vpn.consent.open"
  static let devicePolicyStatus = "galaxyssi.android.device_policy.status"
  static let devicePolicyLock = "galaxyssi.android.device_policy.lock"
  static let devicePolicyReboot = "galaxyssi.android.device_policy.reboot"

  static let androidSystemPermission = "galaxyssi.platform.android_system_api"
  static let compatibilityConsent = "galaxyssi.consent.android_system_compatibility"
  static let executorId = "galaxyssi.ios.system_native_catalog"

  static let telephonyReadToolIds: Set<String> = [
    telephonyStatus,
    telephonyCallState,
    telephonyCallStateObserve
  ]

  static let handoffToolIds: Set<String> = [
    telephonyDialHandoff,
    smsSend,
    smsComposeHandoff,
    wifiPanelOpen,
    wifiHotspotPanelOpen,
    biometricEnrollmentOpen,
    vpnConsentOpen
  ]

  static let smsHandoffToolIds: Set<String> = [
    smsSend,
    smsComposeHandoff
  ]

  static let smsInboxBoundaryToolIds: Set<String> = [
    smsList
  ]

  static let downloadToolIds: Set<String> = [
    downloadEnqueue,
    downloadQuery,
    downloadRemove
  ]

  static let contactsWriteToolIds: Set<String> = [
    contactsUpsert,
    contactsDelete
  ]

  static let calendarWriteToolIds: Set<String> = [
    calendarEventUpsert,
    calendarEventDelete
  ]

  static let wifiScanBoundaryToolIds: Set<String> = [
    wifiScanResults,
    wifiScanStart
  ]

  static let audioControlBoundaryToolIds: Set<String> = [
    audioVolumeSet,
    audioMuteSet
  ]

  static let devicePolicyActionBoundaryToolIds: Set<String> = [
    devicePolicyLock,
    devicePolicyReboot
  ]

  static let executableToolIds: Set<String> = handoffToolIds.union([
    telephonyStatus,
    telephonyCallState,
    telephonyCallStateObserve,
    smsList,
    calendarsList,
    calendarEventsQuery,
    contactsSearch,
    contactsUpsert,
    contactsDelete,
    calendarEventUpsert,
    calendarEventDelete,
    downloadEnqueue,
    downloadQuery,
    downloadRemove,
    devicePolicyStatus,
    devicePolicyLock,
    devicePolicyReboot,
    wifiStatus,
    wifiScanResults,
    wifiScanStart,
    audioStatus,
    audioVolumeSet,
    audioMuteSet,
    vpnStatus,
    biometricStatus
  ])

  static var orderedToolIds: [String] {
    specifications.map(\.id)
  }

  static var toolIds: Set<String> {
    Set(orderedToolIds)
  }

  static func definitions() -> [AgentPhoneNativeToolDefinition] {
    specifications.map(definition)
  }

  static func descriptors() -> [AgentNativeToolDescriptor] {
    definitions().map(\.descriptor)
  }

  private struct Specification {
    var id: String
    var title: String
    var description: String
    var risk: AgentNativeToolRisk
    var capabilities: Set<String>
    var permissions: [String]
    var consents: [String]
    var inputSchema: AgentMcpJSONObject
  }

  private static let specifications: [Specification] = [
    spec(
      telephonyStatus,
      "Read phone service status",
      "Reads app-visible iOS CoreTelephony carrier and CallKit call-state summary without exposing subscriber identifiers.",
      .low,
      ["telephony.status"],
      ["android.permission.READ_PHONE_STATE"]
    ),
    spec(
      telephonyCallState,
      "Read current call state",
      "Reads app-visible iOS CallKit current call-state summary without phone numbers or subscriber identifiers.",
      .low,
      ["telephony.call_state"],
      ["android.permission.READ_PHONE_STATE"]
    ),
    spec(
      telephonyCallStateObserve,
      "Observe call state transition",
      "Observes one bounded iOS CallKit call-state transition without registering an unbounded background listener.",
      .low,
      ["telephony.call_state.observe"],
      ["android.permission.READ_PHONE_STATE"],
      inputSchema: input(["timeout_ms": integerSchema(minimum: 1_000, maximum: 30_000)])
    ),
    spec(
      telephonyDialHandoff,
      "Open iOS dialer",
      "Prepares a user-visible iOS telephone handoff. The user reviews the number before placing a call.",
      .medium,
      ["telephony.dial_handoff"],
      inputSchema: input(["phone_number": stringSchema(maxLength: 64)], required: ["phone_number"])
    ),
    spec(
      smsList,
      "Read recent SMS messages",
      "Returns a structured iOS SMS inbox boundary result; iOS cannot read the user's SMS database for normal apps.",
      .low,
      ["sms.read"],
      ["android.permission.READ_SMS"],
      inputSchema: input(["limit": integerSchema(minimum: 1, maximum: 100), "address": stringSchema(maxLength: 128)])
    ),
    spec(
      smsSend,
      "Send SMS message",
      "Prepares a user-visible iOS Messages compose handoff. The user reviews and sends the message.",
      .high,
      ["sms.send"],
      ["android.permission.SEND_SMS"],
      [consentSmsSend],
      input(["phone_number": stringSchema(maxLength: 64), "message": stringSchema(maxLength: 2_000)], required: ["phone_number", "message"])
    ),
    spec(
      smsComposeHandoff,
      "Open SMS composer",
      "Prepares a user-visible iOS Messages compose handoff with a bounded recipient and optional body.",
      .medium,
      ["sms.compose_handoff"],
      inputSchema: input(["phone_number": stringSchema(maxLength: 64), "message": stringSchema(maxLength: 2_000)], required: ["phone_number"])
    ),
    spec(
      contactsSearch,
      "Search iOS contacts",
      "Searches iOS Contacts phone numbers after the app-visible Contacts permission gate.",
      .low,
      ["contacts.read"],
      ["android.permission.READ_CONTACTS"],
      inputSchema: input(["query": stringSchema(maxLength: 160), "limit": integerSchema(minimum: 1, maximum: 100)])
    ),
    spec(
      contactsUpsert,
      "Create or update iOS contact",
      "Creates or updates one iOS Contacts record after the Contacts permission and explicit consent gates.",
      .high,
      ["contacts.write"],
      ["android.permission.WRITE_CONTACTS"],
      [consentContactsWrite],
      input([
        "contact_id": integerSchema(minimum: 1),
        "display_name": stringSchema(maxLength: 160),
        "phone_number": stringSchema(maxLength: 64)
      ], required: ["display_name"])
    ),
    spec(
      contactsDelete,
      "Delete iOS contact",
      "Deletes one iOS Contacts record selected by its stable contact id.",
      .high,
      ["contacts.delete"],
      ["android.permission.WRITE_CONTACTS"],
      [consentContactsWrite],
      input(["contact_id": integerSchema(minimum: 1)], required: ["contact_id"])
    ),
    spec(
      calendarsList,
      "List iOS calendars",
      "Lists iOS EventKit calendars after the app-visible Calendar permission gate.",
      .low,
      ["calendar.read"],
      ["android.permission.READ_CALENDAR"]
    ),
    spec(
      calendarEventsQuery,
      "Query iOS calendar events",
      "Queries iOS EventKit calendar events in a bounded time range after the Calendar permission gate.",
      .low,
      ["calendar.read"],
      ["android.permission.READ_CALENDAR"],
      inputSchema: input([
        "start_epoch_ms": integerSchema(minimum: 0),
        "end_epoch_ms": integerSchema(minimum: 0),
        "limit": integerSchema(minimum: 1, maximum: 200)
      ], required: ["start_epoch_ms", "end_epoch_ms"])
    ),
    spec(
      calendarEventUpsert,
      "Create or update calendar event",
      "Creates or updates one iOS EventKit calendar event after permission, consent, and idempotency gates.",
      .high,
      ["calendar.write"],
      ["android.permission.WRITE_CALENDAR"],
      [consentCalendarWrite],
      input([
        "event_id": integerSchema(minimum: 1),
        "calendar_id": integerSchema(minimum: 1),
        "title": stringSchema(maxLength: 240),
        "description": stringSchema(maxLength: 2_000),
        "location": stringSchema(maxLength: 240),
        "start_epoch_ms": integerSchema(minimum: 0),
        "end_epoch_ms": integerSchema(minimum: 0),
        "timezone": stringSchema(maxLength: 80)
      ], required: ["calendar_id", "title", "start_epoch_ms", "end_epoch_ms"])
    ),
    spec(
      calendarEventDelete,
      "Delete calendar event",
      "Deletes one iOS EventKit calendar event selected by its stable event id.",
      .high,
      ["calendar.delete"],
      ["android.permission.WRITE_CALENDAR"],
      [consentCalendarWrite],
      input(["event_id": integerSchema(minimum: 1)], required: ["event_id"])
    ),
    spec(
      wifiStatus,
      "Read Wi-Fi status",
      "Reads iOS app-visible Wi-Fi transport status without SSID, BSSID, RSSI, or traffic capture.",
      .low,
      ["wifi.status"],
      ["android.permission.ACCESS_WIFI_STATE"]
    ),
    spec(
      wifiScanResults,
      "Read Wi-Fi scan results",
      "Returns a structured iOS Wi-Fi scan boundary result; iOS cannot enumerate nearby Wi-Fi networks for normal apps.",
      .low,
      ["wifi.scan_results"],
      ["android.permission.ACCESS_WIFI_STATE", "android.permission.ACCESS_FINE_LOCATION"],
      inputSchema: input(["limit": integerSchema(minimum: 1, maximum: 100)])
    ),
    spec(
      wifiScanStart,
      "Start Wi-Fi scan",
      "Returns a structured iOS Wi-Fi scan boundary result; iOS cannot trigger arbitrary nearby-network scans for normal apps.",
      .medium,
      ["wifi.scan.start"],
      ["android.permission.ACCESS_WIFI_STATE", "android.permission.CHANGE_WIFI_STATE", "android.permission.ACCESS_FINE_LOCATION"]
    ),
    spec(
      wifiPanelOpen,
      "Open Wi-Fi settings",
      "Prepares a user-visible iOS Settings handoff for Wi-Fi connectivity.",
      .medium,
      ["wifi.settings_handoff"]
    ),
    spec(
      wifiHotspotPanelOpen,
      "Open Personal Hotspot settings",
      "Prepares a user-visible iOS Settings handoff for Personal Hotspot settings.",
      .medium,
      ["wifi.hotspot.settings_handoff"]
    ),
    spec(
      audioStatus,
      "Read audio status",
      "Reads app-visible iOS audio session status without changing global volume, mute, route, or ringer settings.",
      .low,
      ["audio.status"]
    ),
    spec(
      audioVolumeSet,
      "Request audio volume change",
      "Returns a structured iOS audio-control boundary result; iOS cannot set global system stream volumes directly.",
      .medium,
      ["audio.volume"],
      [],
      [consentAudioChange],
      input(["stream": stringSchema(maxLength: 32), "percent": integerSchema(minimum: 0, maximum: 100)], required: ["stream", "percent"])
    ),
    spec(
      audioMuteSet,
      "Request audio mute change",
      "Returns a structured iOS audio-control boundary result; iOS cannot mute arbitrary global audio streams directly.",
      .medium,
      ["audio.mute"],
      [],
      [consentAudioChange],
      input(["stream": stringSchema(maxLength: 32), "muted": boolSchema()], required: ["stream", "muted"])
    ),
    spec(
      downloadEnqueue,
      "Enqueue app-managed download",
      "Enqueues one public HTTPS download through the iOS app-managed URLSession download store.",
      .medium,
      ["download.enqueue"],
      ["android.permission.INTERNET"],
      [consentDownload],
      input(["url": stringSchema(maxLength: 4_096), "title": stringSchema(maxLength: 240), "description": stringSchema(maxLength: 500)], required: ["url"])
    ),
    spec(
      downloadQuery,
      "Query app-managed download",
      "Queries one app-managed iOS URLSession download record using stable cross-platform fields.",
      .low,
      ["download.query"],
      inputSchema: input(["download_id": integerSchema(minimum: 1)], required: ["download_id"])
    ),
    spec(
      downloadRemove,
      "Remove app-managed download",
      "Cancels or removes one app-managed iOS download record and its cached file.",
      .high,
      ["download.remove"],
      [],
      [consentDownload],
      input(["download_id": integerSchema(minimum: 1)], required: ["download_id"])
    ),
    spec(
      biometricStatus,
      "Read biometric capability",
      "Reads iOS LocalAuthentication biometric capability without starting an authentication prompt.",
      .low,
      ["biometric.status"],
      ["android.permission.USE_BIOMETRIC"]
    ),
    spec(
      biometricEnrollmentOpen,
      "Open biometric enrollment",
      "Prepares a user-visible iOS Settings handoff for Face ID, Touch ID, or passcode enrollment.",
      .medium,
      ["biometric.enrollment_handoff"]
    ),
    spec(
      vpnStatus,
      "Read VPN status",
      "Reads app-managed iOS NetworkExtension VPN connection status without enumerating global VPN transports.",
      .low,
      ["vpn.status"]
    ),
    spec(
      vpnConsentOpen,
      "Open VPN settings",
      "Prepares a user-visible iOS Settings handoff for VPN configuration review.",
      .medium,
      ["vpn.consent_handoff"]
    ),
    spec(
      devicePolicyStatus,
      "Read device policy status",
      "Reads app-visible iOS device policy boundary status and reports that Android device-owner operations are unavailable.",
      .low,
      ["device_policy.status"]
    ),
    spec(
      devicePolicyLock,
      "Lock device through device policy",
      "Returns an iOS device-policy action boundary failure; iOS normal apps cannot lock the device.",
      .high,
      ["device_policy.lock"],
      [],
      [consentDevicePolicy]
    ),
    spec(
      devicePolicyReboot,
      "Reboot device through device policy",
      "Returns an iOS device-policy action boundary failure; iOS normal apps cannot reboot the device.",
      .high,
      ["device_policy.reboot"],
      [],
      [consentDevicePolicy]
    )
  ]

  private static func definition(_ specification: Specification) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: specification.id,
      version: AgentPhoneNativeToolCatalog.version,
      title: specification.title,
      description: specification.description,
      location: .androidSystem,
      inputSchema: specification.inputSchema,
      outputSchema: handoffToolIds.contains(specification.id)
        ? handoffOutputSchema()
        : AgentNativeToolDescriptor.objectSchema(),
      risk: specification.risk,
      capabilities: specification.capabilities,
      requiredPermissions: permissionRequirements(specification),
      requiredConsents: consentRequirements(specification),
      timeoutMillis: 30_000,
      idempotency: specification.risk == .high ? .idempotencyKeyRequired : .nonIdempotent,
      availability: availability(specification.id)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "platform": "ios",
        "compatibility_source": "AgentAndroidSystemNativeTools",
        "contract": "bounded-system-api-v1",
        "execution_policy": executionPolicy(specification.id)
      ]
    )
  }

  private static func spec(
    _ id: String,
    _ title: String,
    _ description: String,
    _ risk: AgentNativeToolRisk,
    _ capabilities: Set<String>,
    _ permissions: [String] = [],
    _ consents: [String] = [],
    inputSchema: AgentMcpJSONObject = input()
  ) -> Specification {
    Specification(
      id: id,
      title: title,
      description: description,
      risk: risk,
      capabilities: capabilities,
      permissions: permissions,
      consents: consents,
      inputSchema: inputSchema
    )
  }

  private static func spec(
    _ id: String,
    _ title: String,
    _ description: String,
    _ risk: AgentNativeToolRisk,
    _ capabilities: Set<String>,
    _ permissions: [String] = [],
    _ consents: [String] = [],
    _ inputSchema: AgentMcpJSONObject
  ) -> Specification {
    spec(
      id,
      title,
      description,
      risk,
      capabilities,
      permissions,
      consents,
      inputSchema: inputSchema
    )
  }

  private static func permissionRequirements(_ specification: Specification) -> [AgentNativePermissionRequirement] {
    if telephonyReadToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosTelephonyStatusPermission,
          title: "App-visible iOS telephony status",
          description: "Limits execution to CoreTelephony and CallKit status fields visible to the GalaxySSI app process."
        )
      ]
    }
    if smsHandoffToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosSMSComposePermission,
          title: "User-visible iOS SMS compose",
          description: "Limits SMS execution to an iOS Messages compose handoff that requires the user to review and send."
        )
      ]
    }
    if smsInboxBoundaryToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosSMSInboxBoundaryPermission,
          title: "iOS SMS inbox boundary",
          description: "Limits execution to a structured iOS platform-boundary result; SMS database reads are not exposed."
        )
      ]
    }
    if specification.id == audioStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosAudioStatusPermission,
          title: "App-visible iOS audio status",
          description: "Limits execution to AVAudioSession status fields visible to the GalaxySSI app process."
        )
      ]
    }
    if audioControlBoundaryToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosAudioControlBoundaryPermission,
          title: "iOS audio control boundary",
          description: "Limits execution to a structured iOS platform-boundary result; global audio controls are not exposed."
        )
      ]
    }
    if specification.id == wifiStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosWifiStatusPermission,
          title: "App-visible iOS Wi-Fi status",
          description: "Limits execution to identifier-free NWPath Wi-Fi transport status."
        )
      ]
    }
    if wifiScanBoundaryToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosWifiScanBoundaryPermission,
          title: "iOS Wi-Fi scan boundary",
          description: "Limits execution to a structured iOS platform-boundary result; nearby Wi-Fi scans are not exposed."
        )
      ]
    }
    if specification.id == contactsSearch {
      return [
        AgentNativePermissionRequirement(
          id: iosContactsReadPermission,
          title: "Read iOS Contacts",
          description: "Allows bounded Contacts framework search for display names and phone numbers."
        )
      ]
    }
    if contactsWriteToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosContactsWritePermission,
          title: "Write iOS Contacts",
          description: "Allows Contacts framework create, update, and delete operations after explicit consent."
        )
      ]
    }
    if specification.id == calendarsList || specification.id == calendarEventsQuery {
      return [
        AgentNativePermissionRequirement(
          id: iosCalendarReadPermission,
          title: "Read iOS Calendars",
          description: "Allows bounded EventKit calendar and event reads without writes."
        )
      ]
    }
    if calendarWriteToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosCalendarWritePermission,
          title: "Write iOS Calendars",
          description: "Allows EventKit event create, update, and delete operations after explicit consent."
        )
      ]
    }
    if specification.id == biometricStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosBiometricStatusPermission,
          title: "App-visible iOS biometric status",
          description: "Limits execution to LocalAuthentication capability checks without starting authentication."
        )
      ]
    }
    if specification.id == vpnStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosVPNStatusPermission,
          title: "App-managed iOS VPN status",
          description: "Limits execution to NetworkExtension connection status visible to the GalaxySSI app."
        )
      ]
    }
    if specification.id == devicePolicyStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosDevicePolicyStatusPermission,
          title: "App-visible iOS device policy status",
          description: "Limits execution to device policy boundaries visible from the GalaxySSI iOS app sandbox."
        )
      ]
    }
    if devicePolicyActionBoundaryToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosDevicePolicyActionBoundaryPermission,
          title: "iOS device policy action boundary",
          description: "Limits execution to a structured iOS platform-boundary failure for unsupported device policy actions."
        )
      ]
    }
    if downloadToolIds.contains(specification.id) {
      return [
        AgentNativePermissionRequirement(
          id: iosDownloadPermission,
          title: "iOS app-managed downloads",
          description: "Limits downloads to public HTTPS URLs and files cached inside the GalaxySSI iOS app sandbox."
        )
      ]
    }
    let platform = AgentNativePermissionRequirement(
      id: androidSystemPermission,
      title: "Cross-platform system compatibility",
      description: "This cross-platform wire tool is fulfilled by its bounded iOS executor or user-visible handoff when available."
    )
    let mirrored = specification.permissions.map { permission in
      AgentNativePermissionRequirement(
        id: permission,
        title: permission.replacingOccurrences(of: "android.permission.", with: ""),
        description: "Cross-platform permission metadata retained for policy decisions."
      )
    }
    return ([platform] + mirrored).sorted { $0.id < $1.id }
  }

  private static func consentRequirements(_ specification: Specification) -> [AgentNativeConsentRequirement] {
    let compatibility = AgentNativeConsentRequirement(
      id: compatibilityConsent,
      title: "Cross-platform compatibility adaptation",
      description: compatibilityConsentDescription(specification.id),
      required: false
    )
    let mirrored = specification.consents.map { consent in
      AgentNativeConsentRequirement(
        id: consent,
        title: consent.replacingOccurrences(of: "galaxyssi.consent.", with: "").replacingOccurrences(of: "_", with: " "),
        description: "Cross-platform consent metadata retained for policy decisions."
      )
    }
    return ([compatibility] + mirrored).sorted { $0.id < $1.id }
  }

  private static func compatibilityConsentDescription(_ id: String) -> String {
    if telephonyReadToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS CoreTelephony and CallKit status executor."
    }
    if smsHandoffToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a user-visible iOS Messages compose handoff."
    }
    if smsInboxBoundaryToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a structured iOS SMS inbox boundary executor."
    }
    if id == audioStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS audio status executor."
    }
    if audioControlBoundaryToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a structured iOS audio-control boundary executor."
    }
    if id == wifiStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Wi-Fi status executor."
    }
    if wifiScanBoundaryToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a structured iOS Wi-Fi scan boundary executor."
    }
    if id == contactsSearch {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Contacts search executor."
    }
    if contactsWriteToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Contacts write executor."
    }
    if id == calendarsList || id == calendarEventsQuery {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Calendar read executor."
    }
    if calendarWriteToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Calendar write executor."
    }
    if downloadToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS URLSession download executor."
    }
    if id == biometricStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS biometric status executor."
    }
    if id == vpnStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS NetworkExtension VPN status executor."
    }
    if id == devicePolicyStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS app-visible device policy status executor."
    }
    if devicePolicyActionBoundaryToolIds.contains(id) {
      return "Acknowledges that this Android wire tool is fulfilled by a structured iOS device policy action boundary executor."
    }
    return "Acknowledges that this Android wire tool is discoverable on iOS but has no iOS executor."
  }

  private static func availability(_ id: String) -> AgentNativeToolAvailability {
    if telephonyReadToolIds.contains(id) {
      return telephonyReadAvailability
    }
    if smsHandoffToolIds.contains(id) {
      return smsHandoffAvailability
    }
    if smsInboxBoundaryToolIds.contains(id) {
      return smsInboxBoundaryAvailability
    }
    if handoffToolIds.contains(id) {
      return handoffAvailability
    }
    if id == audioStatus {
      return audioStatusAvailability
    }
    if audioControlBoundaryToolIds.contains(id) {
      return audioControlBoundaryAvailability
    }
    if id == wifiStatus {
      return wifiStatusAvailability
    }
    if wifiScanBoundaryToolIds.contains(id) {
      return wifiScanBoundaryAvailability
    }
    if id == contactsSearch {
      return contactsSearchAvailability
    }
    if contactsWriteToolIds.contains(id) {
      return contactsWriteAvailability
    }
    if id == calendarsList || id == calendarEventsQuery {
      return calendarReadAvailability
    }
    if calendarWriteToolIds.contains(id) {
      return calendarWriteAvailability
    }
    if downloadToolIds.contains(id) {
      return downloadAvailability
    }
    if id == biometricStatus {
      return biometricStatusAvailability
    }
    if id == vpnStatus {
      return vpnStatusAvailability
    }
    if id == devicePolicyStatus {
      return devicePolicyStatusAvailability
    }
    if devicePolicyActionBoundaryToolIds.contains(id) {
      return devicePolicyActionBoundaryAvailability
    }
    return unavailableAvailability
  }

  private static func executionPolicy(_ id: String) -> String {
    if telephonyReadToolIds.contains(id) {
      return "core_telephony_callkit_status_on_ios15"
    }
    if smsHandoffToolIds.contains(id) {
      return "sms_compose_handoff_on_ios15"
    }
    if smsInboxBoundaryToolIds.contains(id) {
      return "ios_sms_inbox_boundary_on_ios15"
    }
    if handoffToolIds.contains(id) {
      return "handoff_request_on_ios15"
    }
    if id == audioStatus {
      return "av_audio_session_status_on_ios15"
    }
    if audioControlBoundaryToolIds.contains(id) {
      return "ios_audio_control_boundary_on_ios15"
    }
    if id == wifiStatus {
      return "nw_path_wifi_status_on_ios15"
    }
    if wifiScanBoundaryToolIds.contains(id) {
      return "ios_wifi_scan_boundary_on_ios15"
    }
    if id == contactsSearch {
      return "contacts_search_on_ios15"
    }
    if contactsWriteToolIds.contains(id) {
      return "contacts_write_on_ios15"
    }
    if id == calendarsList || id == calendarEventsQuery {
      return "eventkit_calendar_read_on_ios15"
    }
    if calendarWriteToolIds.contains(id) {
      return "eventkit_calendar_write_on_ios15"
    }
    if downloadToolIds.contains(id) {
      return "url_session_download_manager_on_ios15"
    }
    if id == biometricStatus {
      return "local_authentication_status_on_ios15"
    }
    if id == vpnStatus {
      return "network_extension_vpn_status_on_ios15"
    }
    if id == devicePolicyStatus {
      return "ios_app_visible_device_policy_status_on_ios15"
    }
    if devicePolicyActionBoundaryToolIds.contains(id) {
      return "ios_device_policy_action_boundary_on_ios15"
    }
    return "descriptor_only_unavailable_on_ios15"
  }

  private static var unavailableAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .unavailable,
      reason: "Android system framework APIs are not executable by the iOS 15+ app sandbox; use an iOS-specific native executor when one is available."
    )
  }

  private static var handoffAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a user-visible handoff request; the app UI must present the system URL or settings surface."
    )
  }

  private static var smsHandoffAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a user-visible Messages compose handoff; direct background SMS send is not available on iOS."
    )
  }

  private static var smsInboxBoundaryAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a structured SMS inbox boundary result because SMS database reads are not exposed to normal apps."
    )
  }

  private static var telephonyReadAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads app-visible CoreTelephony carrier fields and CallKit call-state summary without subscriber identifiers."
    )
  }

  private static var audioStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads bounded AVAudioSession status without changing audio settings."
    )
  }

  private static var audioControlBoundaryAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a structured audio-control boundary result because global stream volume and mute are not exposed to normal apps."
    )
  }

  private static var wifiStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads bounded NWPath Wi-Fi transport status without network identifiers."
    )
  }

  private static var wifiScanBoundaryAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a structured Wi-Fi scan boundary result because nearby-network scans are not exposed to normal apps."
    )
  }

  private static var contactsSearchAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor searches Contacts after the Contacts permission gate."
    )
  }

  private static var contactsWriteAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor writes Contacts through CNSaveRequest after permission, consent, and idempotency gates."
    )
  }

  private static var calendarReadAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads EventKit calendars and events after the Calendar permission gate."
    )
  }

  private static var calendarWriteAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor writes EventKit events after permission, consent, and idempotency gates."
    )
  }

  private static var downloadAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor uses URLSession to manage bounded public HTTPS downloads inside the Files-visible app Documents directory."
    )
  }

  private static var biometricStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor checks LocalAuthentication biometric capability without prompting."
    )
  }

  private static var vpnStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads app-managed NetworkExtension VPN status without enumerating global VPN transports."
    )
  }

  private static var devicePolicyStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reports app-visible device policy boundaries; lock and reboot remain unavailable to normal iOS apps."
    )
  }

  private static var devicePolicyActionBoundaryAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor returns a structured device-policy action boundary failure because lock and reboot are not exposed to normal apps."
    )
  }

  private static func handoffOutputSchema() -> AgentMcpJSONObject {
    input([
      "handoff_kind": stringSchema(maxLength: 64),
      "url": stringSchema(maxLength: 2_048),
      "requires_user_action": boolSchema(),
      "completion_untrusted": boolSchema(),
      "platform": stringSchema(maxLength: 16),
      "tool_id": stringSchema(maxLength: 160),
      "phone_number": stringSchema(maxLength: 64),
      "prefill_body": stringSchema(maxLength: 2_000),
      "body_in_url": boolSchema(),
      "settings_target": stringSchema(maxLength: 80),
      "requested_direct_send": boolSchema(),
      "direct_send_supported": boolSchema(),
      "submitted_to_system": boolSchema(),
      "can_send_text": boolSchema(),
      "handoff_transport": stringSchema(maxLength: 64),
      "observed_at_epoch_ms": integerSchema(minimum: 0)
    ], required: [
      "handoff_kind",
      "url",
      "requires_user_action",
      "completion_untrusted",
      "platform",
      "tool_id"
    ])
  }

  private static func input(
    _ properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = []
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(false)
    ]
  }

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
  }

  private static func integerSchema(minimum: Int64, maximum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("integer"),
      "minimum": .int(minimum)
    ]
    if let maximum {
      schema["maximum"] = .int(maximum)
    }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  static let iosAudioStatusPermission = "galaxyssi.scope.ios_app_visible_audio_status"
  static let iosAudioControlBoundaryPermission = "galaxyssi.scope.ios_audio_control_boundary"
  static let iosWifiStatusPermission = "galaxyssi.scope.ios_app_visible_wifi_status"
  static let iosWifiScanBoundaryPermission = "galaxyssi.scope.ios_wifi_scan_boundary"
  static let iosContactsReadPermission = "galaxyssi.scope.ios_contacts_read"
  static let iosContactsWritePermission = "galaxyssi.scope.ios_contacts_write"
  static let iosCalendarReadPermission = "galaxyssi.scope.ios_calendar_read"
  static let iosCalendarWritePermission = "galaxyssi.scope.ios_calendar_write"
  static let iosDownloadPermission = "galaxyssi.scope.ios_app_managed_downloads"
  static let iosBiometricStatusPermission = "galaxyssi.scope.ios_app_visible_biometric_status"
  static let iosSMSComposePermission = "galaxyssi.scope.ios_user_visible_sms_compose"
  static let iosSMSInboxBoundaryPermission = "galaxyssi.scope.ios_sms_inbox_boundary"
  static let iosTelephonyStatusPermission = "galaxyssi.scope.ios_app_visible_telephony_status"
  static let iosVPNStatusPermission = "galaxyssi.scope.ios_app_managed_vpn_status"
  static let iosDevicePolicyStatusPermission = "galaxyssi.scope.ios_app_visible_device_policy_status"
  static let iosDevicePolicyActionBoundaryPermission = "galaxyssi.scope.ios_device_policy_action_boundary"

  private static let consentSmsSend = "galaxyssi.consent.sms.send"
  private static let consentContactsWrite = "galaxyssi.consent.contacts.write"
  private static let consentCalendarWrite = "galaxyssi.consent.calendar.write"
  private static let consentAudioChange = "galaxyssi.consent.audio.change"
  private static let consentDownload = "galaxyssi.consent.download"
  private static let consentDevicePolicy = "galaxyssi.consent.device_policy"
}

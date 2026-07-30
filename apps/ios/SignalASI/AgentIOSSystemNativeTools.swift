import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
#if canImport(Contacts)
import Contacts
#endif

protocol AgentIOSAudioStatusProviding {
  func audioStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

protocol AgentIOSContactsSearchProviding {
  func searchContacts(query: String, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

protocol AgentIOSBiometricStatusProviding {
  func biometricStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

protocol AgentIOSWifiStatusProviding {
  func wifiStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

struct AgentIOSDefaultAudioStatusProvider: AgentIOSAudioStatusProviding {
  func audioStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(AVFoundation)
    let session = AVAudioSession.sharedInstance()
    let volumePercent = Int64(max(0, min(100, Int((session.outputVolume * 100).rounded()))))
    let routes = boundedRoutes(session.currentRoute.outputs.map { routeName($0.portType) })
    return [
      "ringer_mode": .string("not_exposed_ios"),
      "mode": .string(session.mode.rawValue),
      "category": .string(session.category.rawValue),
      "speakerphone_on": .bool(routes.contains("speaker")),
      "microphone_muted": .null,
      "streams": .object([
        "media": .object([
          "current": .int(volumePercent),
          "max": .int(100),
          "muted": .bool(volumePercent == 0),
          "scope": .string("app_visible_output_volume")
        ])
      ]),
      "routes": .array(routes.map(AgentMcpJSONValue.string)),
      "secondary_audio_silenced": .bool(session.secondaryAudioShouldBeSilencedHint),
      "output_volume_percent": .int(volumePercent),
      "scope": .string("app_visible_ios"),
      "identifiers_included": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #else
    return [
      "ringer_mode": .string("unknown"),
      "mode": .string("unknown"),
      "category": .string("unknown"),
      "speakerphone_on": .bool(false),
      "microphone_muted": .null,
      "streams": .object([:]),
      "routes": .array([]),
      "output_volume_percent": .null,
      "scope": .string("app_visible_ios_unavailable"),
      "identifiers_included": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #endif
  }

  private func boundedRoutes(_ routes: [String]) -> [String] {
    var seen: Set<String> = []
    return Array(routes.filter { route in
      guard !seen.contains(route) else {
        return false
      }
      seen.insert(route)
      return true
    }.prefix(8))
  }

  #if canImport(AVFoundation)
  private func routeName(_ port: AVAudioSession.Port) -> String {
    let raw = port.rawValue.lowercased()
    if raw.contains("speaker") {
      return "speaker"
    }
    if raw.contains("receiver") {
      return "receiver"
    }
    if raw.contains("headphone") || raw.contains("headset") {
      return "headphones"
    }
    if raw.contains("bluetooth") {
      return "bluetooth"
    }
    if raw.contains("airplay") {
      return "airplay"
    }
    if raw.contains("hdmi") {
      return "hdmi"
    }
    if raw.contains("car") {
      return "car_audio"
    }
    if raw.contains("usb") {
      return "usb"
    }
    return "other"
  }
  #endif
}

struct AgentIOSDefaultWifiStatusProvider: AgentIOSWifiStatusProviding {
  var networkProbeProvider: () -> AgentMediaNetworkProbe

  init(networkProbeProvider: @escaping () -> AgentMediaNetworkProbe = { AgentMediaNetworkDetector.shared.currentProbe }) {
    self.networkProbeProvider = networkProbeProvider
  }

  func wifiStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    let probe = networkProbeProvider()
    let activeWifi = probe.transports.contains("wifi")
    return [
      "wifi_enabled": activeWifi ? .bool(true) : .null,
      "ssid": .string(""),
      "bssid": .string(""),
      "rssi": .null,
      "link_speed_mbps": .null,
      "active_wifi_transport": .bool(activeWifi),
      "validated": .bool(activeWifi && probe.validated),
      "metered": .bool(probe.metered),
      "constrained": .bool(probe.restricted),
      "internet_capable": .bool(probe.internetCapable),
      "identifiers_included": .bool(false),
      "scope": .string("app_visible_ios_no_wifi_identifiers"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }
}

struct AgentIOSDefaultContactsSearchProvider: AgentIOSContactsSearchProviding {
  func searchContacts(query: String, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    #if canImport(Contacts)
    let authorization = CNContactStore.authorizationStatus(for: .contacts)
    guard authorization == .authorized else {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_permission_required",
        message: "iOS Contacts permission is required before contacts can be searched."
      )
    }
    let store = CNContactStore()
    let clampedLimit = max(1, min(100, limit))
    let normalizedQuery = bounded(query, 160)
    let keys = [
      CNContactIdentifierKey,
      CNContactGivenNameKey,
      CNContactMiddleNameKey,
      CNContactFamilyNameKey,
      CNContactOrganizationNameKey,
      CNContactPhoneNumbersKey
    ] as [CNKeyDescriptor]
    var rows: [AgentMcpJSONObject] = []
    var seen: Set<String> = []

    do {
      if normalizedQuery.isEmpty {
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        try store.enumerateContacts(with: request) { contact, stop in
          self.append(contact, rows: &rows, seen: &seen, limit: clampedLimit)
          if rows.count >= clampedLimit {
            stop.pointee = true
          }
        }
      } else {
        let contacts = try store.unifiedContacts(
          matching: CNContact.predicateForContacts(matchingName: normalizedQuery),
          keysToFetch: keys
        )
        for contact in contacts {
          self.append(contact, rows: &rows, seen: &seen, limit: clampedLimit)
          if rows.count >= clampedLimit {
            break
          }
        }
      }
      return AgentNativeToolExecutionResult.success(
        output: [
          "contacts": .array(rows.map(AgentMcpJSONValue.object)),
          "count": .int(Int64(rows.count)),
          "query": .string(normalizedQuery),
          "limit": .int(Int64(clampedLimit)),
          "authorization_status": .string(authorizationStatus(authorization)),
          "scope": .string("ios_contacts_read"),
          "observed_at_epoch_ms": .int(nowMillis)
        ],
        message: "Contacts search completed"
      )
    } catch {
      return AgentNativeToolExecutionResult.failure(
        code: "contacts_search_failed",
        message: "iOS Contacts search failed."
      )
    }
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "contacts_framework_unavailable",
      message: "Contacts framework is unavailable on this platform."
    )
    #endif
  }

  #if canImport(Contacts)
  private func append(
    _ contact: CNContact,
    rows: inout [AgentMcpJSONObject],
    seen: inout Set<String>,
    limit: Int
  ) {
    guard rows.count < limit else {
      return
    }
    let displayName = bounded(contactDisplayName(contact), 160)
    for phone in contact.phoneNumbers {
      let number = bounded(phone.value.stringValue, 64)
      guard !number.isEmpty else {
        continue
      }
      let dedupeKey = "\(contact.identifier)|\(number)"
      guard seen.insert(dedupeKey).inserted else {
        continue
      }
      rows.append([
        "contact_id": .int(syntheticContactId(contact.identifier)),
        "display_name": .string(displayName),
        "phone_number": .string(number),
        "platform": .string("ios")
      ])
      if rows.count >= limit {
        break
      }
    }
  }

  private func contactDisplayName(_ contact: CNContact) -> String {
    let name = [contact.givenName, contact.middleName, contact.familyName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    if !name.isEmpty {
      return name
    }
    let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    return organization.isEmpty ? "Contact" : organization
  }

  private func syntheticContactId(_ identifier: String) -> Int64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in identifier.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int64(hash & 0x7fff_ffff_ffff_ffff)
  }

  private func authorizationStatus(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "not_determined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown"
    }
  }
  #endif

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}

struct AgentIOSDefaultBiometricStatusProvider: AgentIOSBiometricStatusProviding {
  func biometricStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    #if canImport(LocalAuthentication)
    let biometricContext = LAContext()
    var biometricError: NSError?
    let canAuthenticate = biometricContext.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: &biometricError
    )
    let deviceContext = LAContext()
    var deviceError: NSError?
    let deviceSecure = deviceContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &deviceError)
    return [
      "device_secure": .bool(deviceSecure),
      "can_authenticate": .bool(canAuthenticate),
      "can_authenticate_code": .int(Int64(biometricError?.code ?? 0)),
      "biometry_type": .string(biometryType(biometricContext.biometryType)),
      "framework": .string("LocalAuthentication"),
      "authentication_prompted": .bool(false),
      "scope": .string("app_visible_ios"),
      "identifiers_included": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #else
    return [
      "device_secure": .bool(false),
      "can_authenticate": .bool(false),
      "can_authenticate_code": .int(-1),
      "biometry_type": .string("unknown"),
      "framework": .string("unavailable"),
      "authentication_prompted": .bool(false),
      "scope": .string("app_visible_ios_unavailable"),
      "identifiers_included": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #endif
  }

  #if canImport(LocalAuthentication)
  private func biometryType(_ type: LABiometryType) -> String {
    switch type {
    case .none:
      return "none"
    case .touchID:
      return "touch_id"
    case .faceID:
      return "face_id"
    @unknown default:
      return "unknown"
    }
  }
  #endif
}

enum AgentIOSSystemNativeToolCatalog {
  static let telephonyStatus = "signalasi.android.telephony.status"
  static let telephonyCallState = "signalasi.android.telephony.call_state"
  static let telephonyCallStateObserve = "signalasi.android.telephony.call_state.observe"
  static let telephonyDialHandoff = "signalasi.android.telephony.dial.handoff"
  static let smsList = "signalasi.android.sms.list"
  static let smsSend = "signalasi.android.sms.send"
  static let smsComposeHandoff = "signalasi.android.sms.compose.handoff"
  static let contactsSearch = "signalasi.android.contacts.search"
  static let contactsUpsert = "signalasi.android.contacts.upsert"
  static let contactsDelete = "signalasi.android.contacts.delete"
  static let calendarsList = "signalasi.android.calendar.calendars.list"
  static let calendarEventsQuery = "signalasi.android.calendar.events.query"
  static let calendarEventUpsert = "signalasi.android.calendar.event.upsert"
  static let calendarEventDelete = "signalasi.android.calendar.event.delete"
  static let wifiStatus = "signalasi.android.wifi.status"
  static let wifiScanResults = "signalasi.android.wifi.scan_results"
  static let wifiScanStart = "signalasi.android.wifi.scan.start"
  static let wifiPanelOpen = "signalasi.android.wifi.panel.open"
  static let wifiHotspotPanelOpen = "signalasi.android.wifi.hotspot.panel.open"
  static let audioStatus = "signalasi.android.audio.status"
  static let audioVolumeSet = "signalasi.android.audio.volume.set"
  static let audioMuteSet = "signalasi.android.audio.mute.set"
  static let downloadEnqueue = "signalasi.android.download.enqueue"
  static let downloadQuery = "signalasi.android.download.query"
  static let downloadRemove = "signalasi.android.download.remove"
  static let biometricStatus = "signalasi.android.biometric.status"
  static let biometricEnrollmentOpen = "signalasi.android.biometric.enrollment.open"
  static let vpnStatus = "signalasi.android.vpn.status"
  static let vpnConsentOpen = "signalasi.android.vpn.consent.open"
  static let devicePolicyStatus = "signalasi.android.device_policy.status"
  static let devicePolicyLock = "signalasi.android.device_policy.lock"
  static let devicePolicyReboot = "signalasi.android.device_policy.reboot"

  static let androidSystemPermission = "signalasi.platform.android_system_api"
  static let compatibilityConsent = "signalasi.consent.android_system_compatibility"
  static let executorId = "signalasi.ios.system_native_catalog"

  static let handoffToolIds: Set<String> = [
    telephonyDialHandoff,
    smsComposeHandoff,
    wifiPanelOpen,
    wifiHotspotPanelOpen,
    biometricEnrollmentOpen,
    vpnConsentOpen
  ]

  static let executableToolIds: Set<String> = handoffToolIds.union([
    contactsSearch,
    wifiStatus,
    audioStatus,
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
      "Android telephony status descriptor retained for cross-platform planning; iOS cannot read SIM and carrier telephony state through this Android API.",
      .low,
      ["telephony.status"],
      ["android.permission.READ_PHONE_STATE"]
    ),
    spec(
      telephonyCallState,
      "Read current call state",
      "Android call-state descriptor retained for cross-platform planning; iOS apps cannot read arbitrary cellular call state.",
      .low,
      ["telephony.call_state"],
      ["android.permission.READ_PHONE_STATE"]
    ),
    spec(
      telephonyCallStateObserve,
      "Observe call state transition",
      "Android bounded call-state observer descriptor retained for planning; iOS does not provide this app-sandboxed listener.",
      .low,
      ["telephony.call_state.observe"],
      ["android.permission.READ_PHONE_STATE"],
      inputSchema: input(["timeout_ms": integerSchema(minimum: 1_000, maximum: 30_000)])
    ),
    spec(
      telephonyDialHandoff,
      "Open Android dialer",
      "Android dialer handoff descriptor retained for planning; iOS needs a separate user-visible tel URL executor.",
      .medium,
      ["telephony.dial_handoff"],
      inputSchema: input(["phone_number": stringSchema(maxLength: 64)], required: ["phone_number"])
    ),
    spec(
      smsList,
      "Read recent SMS messages",
      "Android SMS inbox descriptor retained for planning; iOS cannot read the user's SMS database.",
      .low,
      ["sms.read"],
      ["android.permission.READ_SMS"],
      inputSchema: input(["limit": integerSchema(minimum: 1, maximum: 100), "address": stringSchema(maxLength: 128)])
    ),
    spec(
      smsSend,
      "Send SMS message",
      "Android direct SMS send descriptor retained for planning; iOS requires a user-visible Messages compose handoff.",
      .high,
      ["sms.send"],
      ["android.permission.SEND_SMS"],
      [consentSmsSend],
      input(["phone_number": stringSchema(maxLength: 64), "message": stringSchema(maxLength: 2_000)], required: ["phone_number", "message"])
    ),
    spec(
      smsComposeHandoff,
      "Open SMS composer",
      "Android SMS composer handoff descriptor retained for planning; iOS needs a dedicated user-visible compose executor.",
      .medium,
      ["sms.compose_handoff"],
      inputSchema: input(["phone_number": stringSchema(maxLength: 64), "message": stringSchema(maxLength: 2_000)], required: ["phone_number"])
    ),
    spec(
      contactsSearch,
      "Search Android contacts",
      "Searches iOS Contacts phone numbers after the app-visible Contacts permission gate.",
      .low,
      ["contacts.read"],
      ["android.permission.READ_CONTACTS"],
      inputSchema: input(["query": stringSchema(maxLength: 160), "limit": integerSchema(minimum: 1, maximum: 100)])
    ),
    spec(
      contactsUpsert,
      "Create or update Android contact",
      "Android contacts write descriptor retained for planning; iOS requires a Contacts framework executor and explicit confirmation.",
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
      "Delete Android contact",
      "Android contact delete descriptor retained for planning; iOS requires a Contacts framework executor and explicit confirmation.",
      .high,
      ["contacts.delete"],
      ["android.permission.WRITE_CONTACTS"],
      [consentContactsWrite],
      input(["contact_id": integerSchema(minimum: 1)], required: ["contact_id"])
    ),
    spec(
      calendarsList,
      "List Android calendars",
      "Android calendar list descriptor retained for planning; iOS requires an EventKit executor and permission gate.",
      .low,
      ["calendar.read"],
      ["android.permission.READ_CALENDAR"]
    ),
    spec(
      calendarEventsQuery,
      "Query Android calendar events",
      "Android calendar query descriptor retained for planning; iOS requires an EventKit executor and permission gate.",
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
      "Android calendar event write descriptor retained for planning; iOS requires an EventKit executor and explicit confirmation.",
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
      "Android calendar event delete descriptor retained for planning; iOS requires an EventKit executor and explicit confirmation.",
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
      "Android Wi-Fi scan results descriptor retained for planning; iOS cannot enumerate nearby Wi-Fi scan results.",
      .low,
      ["wifi.scan_results"],
      ["android.permission.ACCESS_WIFI_STATE", "android.permission.ACCESS_FINE_LOCATION"],
      inputSchema: input(["limit": integerSchema(minimum: 1, maximum: 100)])
    ),
    spec(
      wifiScanStart,
      "Start Wi-Fi scan",
      "Android Wi-Fi scan request descriptor retained for planning; iOS cannot trigger arbitrary Wi-Fi scans.",
      .medium,
      ["wifi.scan.start"],
      ["android.permission.ACCESS_WIFI_STATE", "android.permission.CHANGE_WIFI_STATE", "android.permission.ACCESS_FINE_LOCATION"]
    ),
    spec(
      wifiPanelOpen,
      "Open Internet panel",
      "Android Internet panel descriptor retained for planning; iOS requires a separate Settings handoff executor.",
      .medium,
      ["wifi.settings_handoff"]
    ),
    spec(
      wifiHotspotPanelOpen,
      "Open hotspot settings",
      "Android hotspot settings descriptor retained for planning; iOS personal hotspot settings are not exposed as the same Android panel.",
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
      "Set Android stream volume",
      "Android stream-volume descriptor retained for planning; iOS apps cannot set global system stream volumes directly.",
      .medium,
      ["audio.volume"],
      [],
      [consentAudioChange],
      input(["stream": stringSchema(maxLength: 32), "percent": integerSchema(minimum: 0, maximum: 100)], required: ["stream", "percent"])
    ),
    spec(
      audioMuteSet,
      "Set Android stream mute",
      "Android stream-mute descriptor retained for planning; iOS apps cannot mute arbitrary system audio streams directly.",
      .medium,
      ["audio.mute"],
      [],
      [consentAudioChange],
      input(["stream": stringSchema(maxLength: 32), "muted": boolSchema()], required: ["stream", "muted"])
    ),
    spec(
      downloadEnqueue,
      "Enqueue Android download",
      "Android DownloadManager enqueue descriptor retained for planning; iOS requires a separate URLSession-backed download executor.",
      .medium,
      ["download.enqueue"],
      ["android.permission.INTERNET"],
      [consentDownload],
      input(["url": stringSchema(maxLength: 4_096), "title": stringSchema(maxLength: 240), "description": stringSchema(maxLength: 500)], required: ["url"])
    ),
    spec(
      downloadQuery,
      "Query Android download",
      "Android DownloadManager query descriptor retained for planning; iOS cannot query Android-managed downloads.",
      .low,
      ["download.query"],
      inputSchema: input(["download_id": integerSchema(minimum: 1)], required: ["download_id"])
    ),
    spec(
      downloadRemove,
      "Remove Android download",
      "Android DownloadManager remove descriptor retained for planning; iOS requires a separate scoped download executor.",
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
      "Android biometric enrollment descriptor retained for planning; iOS can only hand off to allowed Settings surfaces through a separate executor.",
      .medium,
      ["biometric.enrollment_handoff"]
    ),
    spec(
      vpnStatus,
      "Read VPN status",
      "Android VPN transport descriptor retained for planning; iOS VPN state is not exposed through this Android API.",
      .low,
      ["vpn.status"]
    ),
    spec(
      vpnConsentOpen,
      "Request Android VPN consent",
      "Android VPN consent descriptor retained for planning; iOS requires Network Extension entitlements and a separate setup flow.",
      .medium,
      ["vpn.consent_handoff"]
    ),
    spec(
      devicePolicyStatus,
      "Read device policy status",
      "Android device-policy descriptor retained for planning; iOS supervised MDM state is not available to normal apps.",
      .low,
      ["device_policy.status"]
    ),
    spec(
      devicePolicyLock,
      "Lock device through device policy",
      "Android device-policy lock descriptor retained for planning; iOS normal apps cannot lock the device.",
      .high,
      ["device_policy.lock"],
      [],
      [consentDevicePolicy]
    ),
    spec(
      devicePolicyReboot,
      "Reboot device through device policy",
      "Android device-policy reboot descriptor retained for planning; iOS normal apps cannot reboot the device.",
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
    if specification.id == audioStatus {
      return [
        AgentNativePermissionRequirement(
          id: iosAudioStatusPermission,
          title: "App-visible iOS audio status",
          description: "Limits execution to AVAudioSession status fields visible to the SignalASI app process."
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
    if specification.id == contactsSearch {
      return [
        AgentNativePermissionRequirement(
          id: iosContactsReadPermission,
          title: "Read iOS Contacts",
          description: "Allows bounded Contacts framework search for display names and phone numbers."
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
    let platform = AgentNativePermissionRequirement(
      id: androidSystemPermission,
      title: "Android system API",
      description: "This Android framework tool is cataloged for planning but is unavailable inside the iOS 15+ app sandbox."
    )
    let mirrored = specification.permissions.map { permission in
      AgentNativePermissionRequirement(
        id: permission,
        title: permission.replacingOccurrences(of: "android.permission.", with: ""),
        description: "Android permission mirrored from AgentAndroidSystemNativeTools for cross-platform policy decisions."
      )
    }
    return ([platform] + mirrored).sorted { $0.id < $1.id }
  }

  private static func consentRequirements(_ specification: Specification) -> [AgentNativeConsentRequirement] {
    let compatibility = AgentNativeConsentRequirement(
      id: compatibilityConsent,
      title: "Android compatibility boundary",
      description: compatibilityConsentDescription(specification.id),
      required: false
    )
    let mirrored = specification.consents.map { consent in
      AgentNativeConsentRequirement(
        id: consent,
        title: consent.replacingOccurrences(of: "signalasi.consent.", with: "").replacingOccurrences(of: "_", with: " "),
        description: "Android consent requirement mirrored for cross-platform policy decisions."
      )
    }
    return ([compatibility] + mirrored).sorted { $0.id < $1.id }
  }

  private static func compatibilityConsentDescription(_ id: String) -> String {
    if id == audioStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS audio status executor."
    }
    if id == wifiStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Wi-Fi status executor."
    }
    if id == contactsSearch {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS Contacts search executor."
    }
    if id == biometricStatus {
      return "Acknowledges that this Android wire tool is fulfilled by a bounded iOS biometric status executor."
    }
    return "Acknowledges that this Android wire tool is discoverable on iOS but has no iOS executor."
  }

  private static func availability(_ id: String) -> AgentNativeToolAvailability {
    if handoffToolIds.contains(id) {
      return handoffAvailability
    }
    if id == audioStatus {
      return audioStatusAvailability
    }
    if id == wifiStatus {
      return wifiStatusAvailability
    }
    if id == contactsSearch {
      return contactsSearchAvailability
    }
    if id == biometricStatus {
      return biometricStatusAvailability
    }
    return unavailableAvailability
  }

  private static func executionPolicy(_ id: String) -> String {
    if handoffToolIds.contains(id) {
      return "handoff_request_on_ios15"
    }
    if id == audioStatus {
      return "av_audio_session_status_on_ios15"
    }
    if id == wifiStatus {
      return "nw_path_wifi_status_on_ios15"
    }
    if id == contactsSearch {
      return "contacts_search_on_ios15"
    }
    if id == biometricStatus {
      return "local_authentication_status_on_ios15"
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

  private static var audioStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads bounded AVAudioSession status without changing audio settings."
    )
  }

  private static var wifiStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor reads bounded NWPath Wi-Fi transport status without network identifiers."
    )
  }

  private static var contactsSearchAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor searches Contacts after the Contacts permission gate."
    )
  }

  private static var biometricStatusAvailability: AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS executor checks LocalAuthentication biometric capability without prompting."
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
      "settings_target": stringSchema(maxLength: 80)
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

  static let iosAudioStatusPermission = "signalasi.scope.ios_app_visible_audio_status"
  static let iosWifiStatusPermission = "signalasi.scope.ios_app_visible_wifi_status"
  static let iosContactsReadPermission = "signalasi.scope.ios_contacts_read"
  static let iosBiometricStatusPermission = "signalasi.scope.ios_app_visible_biometric_status"

  private static let consentSmsSend = "signalasi.consent.sms.send"
  private static let consentContactsWrite = "signalasi.consent.contacts.write"
  private static let consentCalendarWrite = "signalasi.consent.calendar.write"
  private static let consentAudioChange = "signalasi.consent.audio.change"
  private static let consentDownload = "signalasi.consent.download"
  private static let consentDevicePolicy = "signalasi.consent.device_policy"
}

struct AgentIOSSystemNativeToolExecutor {
  var audioProvider: AgentIOSAudioStatusProviding
  var contactsProvider: AgentIOSContactsSearchProviding
  var wifiProvider: AgentIOSWifiStatusProviding
  var biometricProvider: AgentIOSBiometricStatusProviding
  var nowMillis: () -> Int64

  init(
    audioProvider: AgentIOSAudioStatusProviding = AgentIOSDefaultAudioStatusProvider(),
    contactsProvider: AgentIOSContactsSearchProviding = AgentIOSDefaultContactsSearchProvider(),
    wifiProvider: AgentIOSWifiStatusProviding = AgentIOSDefaultWifiStatusProvider(),
    biometricProvider: AgentIOSBiometricStatusProviding = AgentIOSDefaultBiometricStatusProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.audioProvider = audioProvider
    self.contactsProvider = contactsProvider
    self.wifiProvider = wifiProvider
    self.biometricProvider = biometricProvider
    self.nowMillis = nowMillis
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    switch invocation.descriptor.id {
    case AgentIOSSystemNativeToolCatalog.contactsSearch:
      return contactsSearch(invocation)
    case AgentIOSSystemNativeToolCatalog.wifiStatus:
      return wifiStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.audioStatus:
      return audioStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.biometricStatus:
      return biometricStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.telephonyDialHandoff:
      return dialHandoff(invocation)
    case AgentIOSSystemNativeToolCatalog.smsComposeHandoff:
      return smsComposeHandoff(invocation)
    case AgentIOSSystemNativeToolCatalog.wifiPanelOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "wifi",
        message: "Open iOS Settings so the user can review Wi-Fi connectivity."
      )
    case AgentIOSSystemNativeToolCatalog.wifiHotspotPanelOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "personal_hotspot",
        message: "Open iOS Settings so the user can review Personal Hotspot settings."
      )
    case AgentIOSSystemNativeToolCatalog.biometricEnrollmentOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "biometric_enrollment",
        message: "Open iOS Settings so the user can review Face ID, Touch ID, or passcode enrollment."
      )
    case AgentIOSSystemNativeToolCatalog.vpnConsentOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "vpn",
        message: "Open iOS Settings so the user can review VPN configuration."
      )
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "ios_system_tool_unavailable",
        message: "This Android system native tool has no iOS handoff executor."
      )
    }
  }

  private func audioStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: audioProvider.audioStatus(nowMillis: max(0, nowMillis())),
      message: "Audio status read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "identifiers_included": .bool(false),
        "settings_changed": .bool(false)
      ]
    )
  }

  private func contactsSearch(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let query = String((invocation.input["query"]?.stringValue ?? "").prefix(160))
    let limit = Int(invocation.input["limit"]?.intValue ?? 30)
    return contactsProvider.searchContacts(
      query: query,
      limit: max(1, min(100, limit)),
      nowMillis: max(0, nowMillis())
    )
  }

  private func wifiStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: wifiProvider.wifiStatus(nowMillis: max(0, nowMillis())),
      message: "Wi-Fi status read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "identifiers_included": .bool(false),
        "settings_changed": .bool(false)
      ]
    )
  }

  private func biometricStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: biometricProvider.biometricStatus(nowMillis: max(0, nowMillis())),
      message: "Biometric capability read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "authentication_prompted": .bool(false),
        "identifiers_included": .bool(false)
      ]
    )
  }

  private func dialHandoff(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    guard let phoneNumber = normalizedPhoneNumber(invocation.input["phone_number"]?.stringValue) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_phone_number",
        message: "Phone number must contain only bounded dialable characters."
      )
    }
    return handoffResult(
      invocation,
      kind: "dial",
      url: "tel:\(phoneNumber)",
      message: "Dialer handoff prepared for user confirmation.",
      extra: ["phone_number": .string(phoneNumber)]
    )
  }

  private func smsComposeHandoff(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    guard let phoneNumber = normalizedPhoneNumber(invocation.input["phone_number"]?.stringValue) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_phone_number",
        message: "Phone number must contain only bounded dialable characters."
      )
    }
    let body = String((invocation.input["message"]?.stringValue ?? "").prefix(2_000))
    return handoffResult(
      invocation,
      kind: "sms_compose",
      url: "sms:\(phoneNumber)",
      message: "SMS compose handoff prepared; iOS requires the user to review and send.",
      extra: [
        "phone_number": .string(phoneNumber),
        "prefill_body": .string(body),
        "body_in_url": .bool(false)
      ]
    )
  }

  private func settingsHandoff(
    _ invocation: AgentNativeToolInvocation,
    settingsTarget: String,
    message: String
  ) -> AgentNativeToolExecutionResult {
    handoffResult(
      invocation,
      kind: "settings",
      url: "app-settings:",
      message: message,
      extra: ["settings_target": .string(settingsTarget)]
    )
  }

  private func handoffResult(
    _ invocation: AgentNativeToolInvocation,
    kind: String,
    url: String,
    message: String,
    extra: AgentMcpJSONObject
  ) -> AgentNativeToolExecutionResult {
    var output: AgentMcpJSONObject = [
      "handoff_kind": .string(kind),
      "url": .string(url),
      "requires_user_action": .bool(true),
      "completion_untrusted": .bool(true),
      "platform": .string("ios"),
      "tool_id": .string(invocation.descriptor.id)
    ]
    for (key, value) in extra {
      output[key] = value
    }
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: message,
      metadata: [
        "handoff_required": .bool(true),
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId)
      ]
    )
  }

  private func normalizedPhoneNumber(_ value: String?) -> String? {
    var normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" ", "-", "(", ")", "."] {
      normalized = normalized.replacingOccurrences(of: removable, with: "")
    }
    guard !normalized.isEmpty,
          normalized.count <= 64,
          normalized.range(of: #"^[+0-9*#,;]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return normalized
  }
}

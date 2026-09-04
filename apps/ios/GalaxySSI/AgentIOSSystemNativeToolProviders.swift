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
#if canImport(EventKit)
import EventKit
#endif

protocol AgentIOSAudioStatusProviding {
  func audioStatus(nowMillis: Int64) -> AgentMcpJSONObject
}

protocol AgentIOSCalendarReadProviding {
  func listCalendars(nowMillis: Int64) -> AgentNativeToolExecutionResult
  func queryEvents(startEpochMillis: Int64, endEpochMillis: Int64, limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
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
        let nameMatches = try store.unifiedContacts(
          matching: CNContact.predicateForContacts(matchingName: normalizedQuery),
          keysToFetch: keys
        )
        for contact in nameMatches {
          self.append(contact, rows: &rows, seen: &seen, limit: clampedLimit)
          if rows.count >= clampedLimit {
            break
          }
        }
        if rows.count < clampedLimit {
          let request = CNContactFetchRequest(keysToFetch: keys)
          request.sortOrder = .userDefault
          try store.enumerateContacts(with: request) { contact, stop in
            guard self.matches(contact, query: normalizedQuery) else {
              return
            }
            self.append(contact, rows: &rows, seen: &seen, limit: clampedLimit)
            if rows.count >= clampedLimit {
              stop.pointee = true
            }
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

  private func matches(_ contact: CNContact, query: String) -> Bool {
    let normalizedQuery = query.localizedLowercase
    let name = contactDisplayName(contact).localizedLowercase
    let organization = contact.organizationName.localizedLowercase
    if name.contains(normalizedQuery) || organization.contains(normalizedQuery) {
      return true
    }
    let queryDigits = query.filter { $0.isNumber }
    guard !queryDigits.isEmpty else {
      return false
    }
    return contact.phoneNumbers.contains { phone in
      phone.value.stringValue.filter { $0.isNumber }.contains(queryDigits)
    }
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

struct AgentIOSDefaultCalendarReadProvider: AgentIOSCalendarReadProviding {
  func listCalendars(nowMillis: Int64) -> AgentNativeToolExecutionResult {
    #if canImport(EventKit)
    let authorization = EKEventStore.authorizationStatus(for: .event)
    guard isCalendarReadable(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_permission_required",
        message: "iOS Calendar permission is required before calendars can be listed."
      )
    }
    let store = EKEventStore()
    let calendars = store.calendars(for: .event)
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
      .prefix(100)
      .map { calendar in
        AgentMcpJSONValue.object([
          "calendar_id": .int(syntheticCalendarId(calendar.calendarIdentifier)),
          "display_name": .string(bounded(calendar.title, 160)),
          "account_name": .string(bounded(calendar.source.title, 160)),
          "visible": .bool(true),
          "platform": .string("ios")
        ])
      }
    return AgentNativeToolExecutionResult.success(
      output: [
        "calendars": .array(Array(calendars)),
        "count": .int(Int64(calendars.count)),
        "authorization_status": .string(authorizationStatus(authorization)),
        "scope": .string("ios_calendar_read"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "Calendars listed"
    )
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "eventkit_unavailable",
      message: "EventKit is unavailable on this platform."
    )
    #endif
  }

  func queryEvents(
    startEpochMillis: Int64,
    endEpochMillis: Int64,
    limit: Int,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    guard startEpochMillis > 0, endEpochMillis > startEpochMillis else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_time_range",
        message: "Calendar time range is invalid."
      )
    }
    #if canImport(EventKit)
    let authorization = EKEventStore.authorizationStatus(for: .event)
    guard isCalendarReadable(authorization) else {
      return AgentNativeToolExecutionResult.failure(
        code: "calendar_permission_required",
        message: "iOS Calendar permission is required before events can be queried."
      )
    }
    let store = EKEventStore()
    let start = Date(timeIntervalSince1970: TimeInterval(startEpochMillis) / 1_000)
    let end = Date(timeIntervalSince1970: TimeInterval(endEpochMillis) / 1_000)
    let clampedLimit = max(1, min(200, limit))
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = store.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .prefix(clampedLimit)
      .map { event in
        AgentMcpJSONValue.object([
          "event_id": .int(syntheticCalendarId(event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)|\(event.title ?? "")")),
          "title": .string(bounded(event.title ?? "", 240)),
          "start_epoch_ms": .int(epochMillis(event.startDate)),
          "end_epoch_ms": .int(epochMillis(event.endDate)),
          "location": .string(bounded(event.location ?? "", 240)),
          "calendar_id": .int(syntheticCalendarId(event.calendar.calendarIdentifier)),
          "platform": .string("ios")
        ])
      }
    return AgentNativeToolExecutionResult.success(
      output: [
        "events": .array(Array(events)),
        "count": .int(Int64(events.count)),
        "start_epoch_ms": .int(startEpochMillis),
        "end_epoch_ms": .int(endEpochMillis),
        "limit": .int(Int64(clampedLimit)),
        "authorization_status": .string(authorizationStatus(authorization)),
        "scope": .string("ios_calendar_read"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "Calendar events queried"
    )
    #else
    return AgentNativeToolExecutionResult.failure(
      code: "eventkit_unavailable",
      message: "EventKit is unavailable on this platform."
    )
    #endif
  }

  #if canImport(EventKit)
  private func isCalendarReadable(_ status: EKAuthorizationStatus) -> Bool {
    status == .authorized || String(describing: status).lowercased().contains("full")
  }

  private func authorizationStatus(_ status: EKAuthorizationStatus) -> String {
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
      return String(describing: status)
        .replacingOccurrences(of: " ", with: "_")
        .lowercased()
    }
  }

  private func epochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }
  #endif

  private func syntheticCalendarId(_ identifier: String) -> Int64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in identifier.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int64(hash & 0x7fff_ffff_ffff_ffff)
  }

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

import Foundation

struct AgentIOSSystemNativeToolExecutor {
  var audioProvider: AgentIOSAudioStatusProviding
  var audioControlProvider: AgentIOSAudioControlProviding
  var calendarProvider: AgentIOSCalendarReadProviding
  var calendarWriteProvider: AgentIOSCalendarWriteProviding
  var contactsProvider: AgentIOSContactsSearchProviding
  var contactsWriteProvider: AgentIOSContactsWriteProviding
  var communicationHandoffProvider: AgentIOSCommunicationHandoffProviding
  var devicePolicyProvider: AgentIOSDevicePolicyStatusProviding
  var downloadProvider: AgentIOSDownloadManaging
  var telephonyProvider: AgentIOSTelephonyStatusProviding
  var vpnProvider: AgentIOSVPNStatusProviding
  var wifiScanProvider: AgentIOSWifiScanProviding
  var wifiProvider: AgentIOSWifiStatusProviding
  var biometricProvider: AgentIOSBiometricStatusProviding
  var nowMillis: () -> Int64

  init(
    audioProvider: AgentIOSAudioStatusProviding = AgentIOSDefaultAudioStatusProvider(),
    audioControlProvider: AgentIOSAudioControlProviding = AgentIOSDefaultAudioControlProvider(),
    calendarProvider: AgentIOSCalendarReadProviding = AgentIOSDefaultCalendarReadProvider(),
    calendarWriteProvider: AgentIOSCalendarWriteProviding = AgentIOSDefaultCalendarWriteProvider(),
    contactsProvider: AgentIOSContactsSearchProviding = AgentIOSDefaultContactsSearchProvider(),
    contactsWriteProvider: AgentIOSContactsWriteProviding = AgentIOSDefaultContactsWriteProvider(),
    communicationHandoffProvider: AgentIOSCommunicationHandoffProviding = AgentIOSDefaultCommunicationHandoffProvider(),
    devicePolicyProvider: AgentIOSDevicePolicyStatusProviding = AgentIOSDefaultDevicePolicyStatusProvider(),
    downloadProvider: AgentIOSDownloadManaging = AgentIOSDefaultDownloadProvider.shared,
    telephonyProvider: AgentIOSTelephonyStatusProviding = AgentIOSDefaultTelephonyStatusProvider(),
    vpnProvider: AgentIOSVPNStatusProviding = AgentIOSDefaultVPNStatusProvider(),
    wifiScanProvider: AgentIOSWifiScanProviding = AgentIOSDefaultWifiScanProvider(),
    wifiProvider: AgentIOSWifiStatusProviding = AgentIOSDefaultWifiStatusProvider(),
    biometricProvider: AgentIOSBiometricStatusProviding = AgentIOSDefaultBiometricStatusProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.audioProvider = audioProvider
    self.audioControlProvider = audioControlProvider
    self.calendarProvider = calendarProvider
    self.calendarWriteProvider = calendarWriteProvider
    self.contactsProvider = contactsProvider
    self.contactsWriteProvider = contactsWriteProvider
    self.communicationHandoffProvider = communicationHandoffProvider
    self.devicePolicyProvider = devicePolicyProvider
    self.downloadProvider = downloadProvider
    self.telephonyProvider = telephonyProvider
    self.vpnProvider = vpnProvider
    self.wifiScanProvider = wifiScanProvider
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
    case AgentIOSSystemNativeToolCatalog.telephonyStatus:
      return telephonyStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.telephonyCallState:
      return telephonyCallState(invocation)
    case AgentIOSSystemNativeToolCatalog.telephonyCallStateObserve:
      return telephonyCallStateObserve(invocation)
    case AgentIOSSystemNativeToolCatalog.calendarsList:
      return calendarProvider.listCalendars(nowMillis: max(0, nowMillis()))
    case AgentIOSSystemNativeToolCatalog.calendarEventsQuery:
      return calendarEventsQuery(invocation)
    case AgentIOSSystemNativeToolCatalog.calendarEventUpsert:
      return calendarEventUpsert(invocation)
    case AgentIOSSystemNativeToolCatalog.calendarEventDelete:
      return calendarEventDelete(invocation)
    case AgentIOSSystemNativeToolCatalog.contactsSearch:
      return contactsSearch(invocation)
    case AgentIOSSystemNativeToolCatalog.contactsUpsert:
      return contactsUpsert(invocation)
    case AgentIOSSystemNativeToolCatalog.contactsDelete:
      return contactsDelete(invocation)
    case AgentIOSSystemNativeToolCatalog.downloadEnqueue:
      return downloadEnqueue(invocation)
    case AgentIOSSystemNativeToolCatalog.downloadQuery:
      return downloadQuery(invocation)
    case AgentIOSSystemNativeToolCatalog.downloadRemove:
      return downloadRemove(invocation)
    case AgentIOSSystemNativeToolCatalog.devicePolicyStatus:
      return devicePolicyStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.wifiStatus:
      return wifiStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.wifiScanResults:
      return wifiScanResults(invocation)
    case AgentIOSSystemNativeToolCatalog.wifiScanStart:
      return wifiScanStart(invocation)
    case AgentIOSSystemNativeToolCatalog.audioStatus:
      return audioStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.audioVolumeSet:
      return audioVolumeSet(invocation)
    case AgentIOSSystemNativeToolCatalog.audioMuteSet:
      return audioMuteSet(invocation)
    case AgentIOSSystemNativeToolCatalog.biometricStatus:
      return biometricStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.vpnStatus:
      return vpnStatus(invocation)
    case AgentIOSSystemNativeToolCatalog.telephonyDialHandoff:
      return dialHandoff(invocation)
    case AgentIOSSystemNativeToolCatalog.smsSend:
      return smsSendHandoff(invocation)
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

  private func audioVolumeSet(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = audioControlProvider.setVolume(
      stream: boundedString(invocation.input["stream"]?.stringValue, limit: 32),
      percent: Int(invocation.input["percent"]?.intValue ?? 50),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func audioMuteSet(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = audioControlProvider.setMute(
      stream: boundedString(invocation.input["stream"]?.stringValue, limit: 32),
      muted: invocation.input["muted"]?.boolValue ?? false,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func telephonyStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: telephonyProvider.telephonyStatus(nowMillis: max(0, nowMillis())),
      message: "Phone service status read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "identifiers_included": .bool(false)
      ]
    )
  }

  private func telephonyCallState(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: telephonyProvider.callState(nowMillis: max(0, nowMillis())),
      message: "Current call state read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "identifiers_included": .bool(false)
      ]
    )
  }

  private func telephonyCallStateObserve(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let timeout = invocation.input["timeout_ms"]?.intValue ?? 10_000
    let result = telephonyProvider.observeCallState(
      timeoutMillis: max(1_000, min(30_000, timeout)),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func calendarEventsQuery(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let start = invocation.input["start_epoch_ms"]?.intValue ?? 0
    let end = invocation.input["end_epoch_ms"]?.intValue ?? 0
    let limit = Int(invocation.input["limit"]?.intValue ?? 50)
    return calendarProvider.queryEvents(
      startEpochMillis: start,
      endEpochMillis: end,
      limit: max(1, min(200, limit)),
      nowMillis: max(0, nowMillis())
    )
  }

  private func calendarEventUpsert(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = calendarWriteProvider.upsertEvent(
      eventId: invocation.input["event_id"]?.intValue ?? 0,
      calendarId: invocation.input["calendar_id"]?.intValue ?? 0,
      title: boundedString(invocation.input["title"]?.stringValue, limit: 240),
      description: boundedString(invocation.input["description"]?.stringValue, limit: 2_000),
      location: boundedString(invocation.input["location"]?.stringValue, limit: 240),
      startEpochMillis: invocation.input["start_epoch_ms"]?.intValue ?? 0,
      endEpochMillis: invocation.input["end_epoch_ms"]?.intValue ?? 0,
      timezone: boundedString(invocation.input["timezone"]?.stringValue, limit: 80),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func calendarEventDelete(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = calendarWriteProvider.deleteEvent(
      eventId: invocation.input["event_id"]?.intValue ?? 0,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
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

  private func contactsUpsert(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = contactsWriteProvider.upsertContact(
      contactId: invocation.input["contact_id"]?.intValue ?? 0,
      displayName: boundedString(invocation.input["display_name"]?.stringValue, limit: 160),
      phoneNumber: boundedString(invocation.input["phone_number"]?.stringValue, limit: 64),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func contactsDelete(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = contactsWriteProvider.deleteContact(
      contactId: invocation.input["contact_id"]?.intValue ?? 0,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func downloadEnqueue(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let url = boundedString(invocation.input["url"]?.stringValue, limit: 4_096)
    guard isHTTPSURL(url) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_download_url",
        message: "Only HTTPS downloads are allowed"
      )
    }
    let result = downloadProvider.enqueueDownload(
      url: url,
      title: boundedString(invocation.input["title"]?.stringValue, limit: 240),
      description: boundedString(invocation.input["description"]?.stringValue, limit: 500),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func downloadQuery(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let id = invocation.input["download_id"]?.intValue ?? 0
    let result = downloadProvider.queryDownload(
      id: id,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func downloadRemove(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let id = invocation.input["download_id"]?.intValue ?? 0
    let result = downloadProvider.removeDownload(
      id: id,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func devicePolicyStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: devicePolicyProvider.devicePolicyStatus(nowMillis: max(0, nowMillis())),
      message: "Device policy status read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "settings_changed": .bool(false)
      ]
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

  private func wifiScanResults(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let limit = Int(invocation.input["limit"]?.intValue ?? 30)
    let result = wifiScanProvider.wifiScanResults(
      limit: max(1, min(100, limit)),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func wifiScanStart(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = wifiScanProvider.startWifiScan(nowMillis: max(0, nowMillis()))
    return annotatedSystemResult(result, invocation: invocation)
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

  private func vpnStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: vpnProvider.vpnStatus(nowMillis: max(0, nowMillis())),
      message: "VPN status read",
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "identifiers_included": .bool(false)
      ]
    )
  }

  private func annotatedSystemResult(
    _ result: AgentNativeToolExecutionResult,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    var result = result
    result.metadata["executor_id"] = .string(AgentIOSSystemNativeToolCatalog.executorId)
    result.metadata["tool_id"] = .string(invocation.descriptor.id)
    result.metadata["platform"] = result.metadata["platform"] ?? .string("ios")
    return result
  }

  private func dialHandoff(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    communicationHandoffProvider.dialHandoff(
      phoneNumber: boundedString(invocation.input["phone_number"]?.stringValue, limit: 64),
      toolId: invocation.descriptor.id,
      nowMillis: max(0, nowMillis())
    )
  }

  private func smsSendHandoff(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let body = boundedString(invocation.input["message"]?.stringValue, limit: 2_000)
    guard !body.isEmpty else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_message",
        message: "SMS message is empty."
      )
    }
    return communicationHandoffProvider.smsComposeHandoff(
      phoneNumber: boundedString(invocation.input["phone_number"]?.stringValue, limit: 64),
      message: body,
      toolId: invocation.descriptor.id,
      requestedDirectSend: true,
      nowMillis: max(0, nowMillis())
    )
  }

  private func smsComposeHandoff(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    communicationHandoffProvider.smsComposeHandoff(
      phoneNumber: boundedString(invocation.input["phone_number"]?.stringValue, limit: 64),
      message: boundedString(invocation.input["message"]?.stringValue, limit: 2_000),
      toolId: invocation.descriptor.id,
      requestedDirectSend: false,
      nowMillis: max(0, nowMillis())
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

  private func isHTTPSURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.scheme?.lowercased() == "https",
          let host = components.host,
          !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    return true
  }

  private func boundedString(_ value: String?, limit: Int) -> String {
    String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}

import Foundation

struct AgentIOSSystemNativeToolExecutor {
  var audioProvider: AgentIOSAudioStatusProviding
  var calendarProvider: AgentIOSCalendarReadProviding
  var contactsProvider: AgentIOSContactsSearchProviding
  var wifiProvider: AgentIOSWifiStatusProviding
  var biometricProvider: AgentIOSBiometricStatusProviding
  var nowMillis: () -> Int64

  init(
    audioProvider: AgentIOSAudioStatusProviding = AgentIOSDefaultAudioStatusProvider(),
    calendarProvider: AgentIOSCalendarReadProviding = AgentIOSDefaultCalendarReadProvider(),
    contactsProvider: AgentIOSContactsSearchProviding = AgentIOSDefaultContactsSearchProvider(),
    wifiProvider: AgentIOSWifiStatusProviding = AgentIOSDefaultWifiStatusProvider(),
    biometricProvider: AgentIOSBiometricStatusProviding = AgentIOSDefaultBiometricStatusProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.audioProvider = audioProvider
    self.calendarProvider = calendarProvider
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
    case AgentIOSSystemNativeToolCatalog.calendarsList:
      return calendarProvider.listCalendars(nowMillis: max(0, nowMillis()))
    case AgentIOSSystemNativeToolCatalog.calendarEventsQuery:
      return calendarEventsQuery(invocation)
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

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
  var smsInboxProvider: AgentIOSSMSInboxProviding
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
    smsInboxProvider: AgentIOSSMSInboxProviding = AgentIOSDefaultSMSInboxProvider(),
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
    self.smsInboxProvider = smsInboxProvider
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
    case AgentIOSSystemNativeToolCatalog.smsList:
      return smsList(invocation)
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
    case AgentIOSSystemNativeToolCatalog.devicePolicyLock:
      return devicePolicyLock(invocation)
    case AgentIOSSystemNativeToolCatalog.devicePolicyReboot:
      return devicePolicyReboot(invocation)
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
        english: "Open iOS Settings so the user can review Wi-Fi connectivity.",
        chinese: "\u{8BF7}\u{6253}\u{5F00} iOS \u{8BBE}\u{7F6E}\u{4EE5}\u{67E5}\u{770B} Wi-Fi \u{8FDE}\u{63A5}\u{72B6}\u{6001}\u{3002}"
      )
    case AgentIOSSystemNativeToolCatalog.wifiHotspotPanelOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "personal_hotspot",
        english: "Open iOS Settings so the user can review Personal Hotspot settings.",
        chinese: "\u{8BF7}\u{6253}\u{5F00} iOS \u{8BBE}\u{7F6E}\u{4EE5}\u{67E5}\u{770B}\u{4E2A}\u{4EBA}\u{70ED}\u{70B9}\u{8BBE}\u{7F6E}\u{3002}"
      )
    case AgentIOSSystemNativeToolCatalog.biometricEnrollmentOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "biometric_enrollment",
        english: "Open iOS Settings so the user can review Face ID, Touch ID, or passcode enrollment.",
        chinese: "\u{8BF7}\u{6253}\u{5F00} iOS \u{8BBE}\u{7F6E}\u{4EE5}\u{67E5}\u{770B} Face ID\u{3001}Touch ID \u{6216}\u{5BC6}\u{7801}\u{8BBE}\u{7F6E}\u{3002}"
      )
    case AgentIOSSystemNativeToolCatalog.vpnConsentOpen:
      return settingsHandoff(
        invocation,
        settingsTarget: "vpn",
        english: "Open iOS Settings so the user can review VPN configuration.",
        chinese: "\u{8BF7}\u{6253}\u{5F00} iOS \u{8BBE}\u{7F6E}\u{4EE5}\u{67E5}\u{770B} VPN \u{914D}\u{7F6E}\u{3002}"
      )
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "ios_system_tool_unavailable",
        message: localizedMessage(
          invocation,
          english: "This system native tool has no iOS executor.",
          chinese: "\u{8BE5}\u{7CFB}\u{7EDF}\u{539F}\u{751F}\u{5DE5}\u{5177}\u{6CA1}\u{6709}\u{53EF}\u{7528}\u{7684} iOS \u{6267}\u{884C}\u{5668}\u{3002}"
        )
      )
    }
  }

  private func audioStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: audioProvider.audioStatus(nowMillis: max(0, nowMillis())),
      message: localizedMessage(invocation, english: "Audio status read", chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{97F3}\u{9891}\u{72B6}\u{6001}"),
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
      message: localizedMessage(invocation, english: "Phone service status read", chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{7535}\u{8BDD}\u{670D}\u{52A1}\u{72B6}\u{6001}"),
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
      message: localizedMessage(invocation, english: "Current call state read", chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{5F53}\u{524D}\u{901A}\u{8BDD}\u{72B6}\u{6001}"),
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

  private func smsList(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let limit = Int(invocation.input["limit"]?.intValue ?? 20)
    let result = smsInboxProvider.listMessages(
      limit: max(1, min(100, limit)),
      address: boundedString(invocation.input["address"]?.stringValue, limit: 128),
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
    let suppliedURL = boundedString(invocation.input["url"]?.stringValue, limit: 4_096)
    guard let normalizedURL = AgentIOSPublicDownloadPolicy.normalizeHTTPSURL(suppliedURL) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_download_url",
        message: "A valid public HTTPS download URL is required"
      )
    }
    let result = downloadProvider.enqueueDownload(
      url: normalizedURL.absoluteString,
      title: boundedString(invocation.input["title"]?.stringValue, limit: 240),
      description: boundedString(invocation.input["description"]?.stringValue, limit: 500),
      context: AgentIOSDownloadContext(
        contactId: invocation.context.attributes["contact_id"] ?? "",
        conversationId: invocation.context.conversationId,
        turnId: invocation.context.turnId,
        languageTag: invocation.context.attributes["response_language"] ?? ""
      ),
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(
      localizedDownloadResult(
        result,
        toolId: AgentIOSSystemNativeToolCatalog.downloadEnqueue,
        invocation: invocation
      ),
      invocation: invocation
    )
  }

  private func downloadQuery(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let id = invocation.input["download_id"]?.intValue ?? 0
    let result = downloadProvider.queryDownload(
      id: id,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(
      localizedDownloadResult(
        result,
        toolId: AgentIOSSystemNativeToolCatalog.downloadQuery,
        invocation: invocation
      ),
      invocation: invocation
    )
  }

  private func downloadRemove(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let id = invocation.input["download_id"]?.intValue ?? 0
    let result = downloadProvider.removeDownload(
      id: id,
      nowMillis: max(0, nowMillis())
    )
    return annotatedSystemResult(
      localizedDownloadResult(
        result,
        toolId: AgentIOSSystemNativeToolCatalog.downloadRemove,
        invocation: invocation
      ),
      invocation: invocation
    )
  }

  private func devicePolicyStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: devicePolicyProvider.devicePolicyStatus(nowMillis: max(0, nowMillis())),
      message: localizedMessage(invocation, english: "Device policy status read", chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{8BBE}\u{5907}\u{7BA1}\u{7406}\u{7B56}\u{7565}\u{72B6}\u{6001}"),
      metadata: [
        "executor_id": .string(AgentIOSSystemNativeToolCatalog.executorId),
        "tool_id": .string(invocation.descriptor.id),
        "settings_changed": .bool(false)
      ]
    )
  }

  private func devicePolicyLock(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = devicePolicyProvider.lockDevice(nowMillis: max(0, nowMillis()))
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func devicePolicyReboot(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let result = devicePolicyProvider.rebootDevice(nowMillis: max(0, nowMillis()))
    return annotatedSystemResult(result, invocation: invocation)
  }

  private func wifiStatus(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.success(
      output: wifiProvider.wifiStatus(nowMillis: max(0, nowMillis())),
      message: localizedMessage(invocation, english: "Wi-Fi status read", chinese: "\u{5DF2}\u{8BFB}\u{53D6} Wi-Fi \u{72B6}\u{6001}"),
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
      message: localizedMessage(invocation, english: "Biometric capability read", chinese: "\u{5DF2}\u{8BFB}\u{53D6}\u{751F}\u{7269}\u{8BC6}\u{522B}\u{80FD}\u{529B}"),
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
      message: localizedMessage(invocation, english: "VPN status read", chinese: "\u{5DF2}\u{8BFB}\u{53D6} VPN \u{72B6}\u{6001}"),
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

  private func localizedDownloadResult(
    _ result: AgentNativeToolExecutionResult,
    toolId: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    guard result.isSuccess else { return result }
    var localized = result
    let chinese = LanguagePolicySettings.resolve(
      invocation.context.attributes["response_language"] ?? ""
    ).hasPrefix("zh")
    switch toolId {
    case AgentIOSSystemNativeToolCatalog.downloadEnqueue:
      localized.message = chinese
        ? "\u{5DF2}\u{5F00}\u{59CB}\u{4E0B}\u{8F7D}\u{3002}\u{5B8C}\u{6210}\u{540E}\u{6587}\u{4EF6}\u{4F1A}\u{4FDD}\u{5B58}\u{5230} Download/GalaxySSI\u{FF0C}\u{5E76}\u{663E}\u{793A}\u{5728}\u{5F53}\u{524D}\u{4F1A}\u{8BDD}\u{4E2D}\u{3002}"
        : "Download started. When it finishes, the file will be saved in Download/GalaxySSI and shown in this conversation."
    case AgentIOSSystemNativeToolCatalog.downloadQuery:
      let status = downloadStatusLabel(
        result.output["status"]?.intValue ?? 0,
        chinese: chinese
      )
      let downloaded = result.output["bytes_downloaded"]?.intValue ?? 0
      let total = result.output["total_bytes"]?.intValue ?? 0
      let progress = total > 0
        ? " (\(min(100, max(0, downloaded * 100 / total)))%)"
        : ""
      localized.message = chinese
        ? "\u{4E0B}\u{8F7D}\u{72B6}\u{6001}\u{FF1A}\(status)\(progress)\u{3002}"
        : "Download status: \(status)\(progress)."
    case AgentIOSSystemNativeToolCatalog.downloadRemove:
      let removed = result.output["removed"]?.intValue ?? 0
      localized.message = chinese
        ? (removed > 0
          ? "\u{5DF2}\u{5220}\u{9664}\u{4E0B}\u{8F7D}\u{8BB0}\u{5F55}\u{548C}\u{6587}\u{4EF6}\u{3002}"
          : "\u{6CA1}\u{6709}\u{627E}\u{5230}\u{53EF}\u{5220}\u{9664}\u{7684}\u{4E0B}\u{8F7D}\u{3002}")
        : (removed > 0 ? "Download record and file removed." : "No removable download was found.")
    default:
      break
    }
    return localized
  }

  private func downloadStatusLabel(_ status: Int64, chinese: Bool) -> String {
    switch status {
    case 1: return chinese ? "\u{7B49}\u{5F85}\u{4E2D}" : "pending"
    case 2: return chinese ? "\u{4E0B}\u{8F7D}\u{4E2D}" : "downloading"
    case 4: return chinese ? "\u{5DF2}\u{6682}\u{505C}" : "paused"
    case 8: return chinese ? "\u{5DF2}\u{5B8C}\u{6210}" : "complete"
    case 16: return chinese ? "\u{5DF2}\u{5931}\u{8D25}" : "failed"
    default: return chinese ? "\u{72B6}\u{6001}\u{672A}\u{77E5}" : "unknown"
    }
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
        message: localizedMessage(invocation, english: "SMS message is empty.", chinese: "\u{77ED}\u{4FE1}\u{5185}\u{5BB9}\u{4E3A}\u{7A7A}\u{3002}")
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
    english: String,
    chinese: String
  ) -> AgentNativeToolExecutionResult {
    handoffResult(
      invocation,
      kind: "settings",
      url: "app-settings:",
      message: localizedMessage(invocation, english: english, chinese: chinese),
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

  private func boundedString(_ value: String?, limit: Int) -> String {
    String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func localizedMessage(
    _ invocation: AgentNativeToolInvocation,
    english: String,
    chinese: String
  ) -> String {
    LanguagePolicySettings.resolve(invocation.context.attributes["response_language"] ?? "").hasPrefix("zh")
      ? chinese
      : english
  }
}

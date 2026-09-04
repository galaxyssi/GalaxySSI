import Foundation

enum AgentConfirmationTier: String, Codable, CaseIterable, Identifiable {
  case direct = "DIRECT"
  case confirmOnce = "CONFIRM_ONCE"
  case confirmAlways = "CONFIRM_ALWAYS"

  var id: String { rawValue }
}

enum AgentConfirmationPolicy {
  static func tier(for action: AgentAction) -> AgentConfirmationTier {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if toolId == homeAssistantServiceCall && requiresAlwaysHomeAssistantConfirmation(action.parameters["input_json"] ?? "") {
      return .confirmAlways
    }
    if alwaysConfirmNativeToolIds.contains(toolId) {
      return .confirmAlways
    }
    if confirmOnceNativeToolIds.contains(toolId) {
      return .confirmOnce
    }
    if desktopRemoteNativeToolIds.contains(toolId) {
      return .direct
    }
    if toolId == webSearch || webIntelligenceToolIds.contains(toolId) {
      return .direct
    }
    if alwaysConfirmKinds.contains(action.kind) || alwaysConfirmTerms.contains(where: value.contains) {
      return .confirmAlways
    }
    if action.kind == .callConnector {
      return .direct
    }
    if confirmOnceTerms.contains(where: value.contains) || action.kind == .controlDevice {
      return .confirmOnce
    }
    if action.kind == .setAlarm ||
      action.kind == .openApp ||
      directActionIds.contains(action.id) ||
      directNativeToolIds.contains(toolId) ||
      directTerms.contains(where: value.contains) {
      return .direct
    }
    switch action.risk {
    case .low:
      return .direct
    case .medium:
      return .confirmOnce
    case .high, .blocked:
      return .confirmAlways
    }
  }

  static func consentKey(for action: AgentAction) -> String {
    let value = searchableValue(action)
    let toolId = nativeToolId(action)
    if locationTerms.contains(where: value.contains) {
      return "location"
    }
    if microphoneTerms.contains(where: value.contains) {
      return "microphone"
    }
    if downloadTerms.contains(where: value.contains) {
      return "downloads"
    }
    if contactWriteTerms.contains(where: value.contains) {
      return "contacts_write"
    }
    if calendarWriteTerms.contains(where: value.contains) {
      return "calendar_write"
    }
    if toolId == bluetoothDiscoveryForeground {
      return "bluetooth_discovery"
    }
    if toolId == wifiScanStart {
      return "wifi_scan"
    }
    if toolId == installedAppsList || toolId == packageDetail {
      return "installed_apps_read"
    }
    if toolId == homeAssistantEntitiesList || toolId == homeAssistantEntityRead {
      return "home_assistant_read"
    }
    if toolId == homeAssistantServiceCall {
      return homeAssistantConsentScope(action.parameters["input_json"] ?? "")
    }
    if action.kind == .controlDevice {
      return "device_control:\(action.target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    return "action:\(action.kind.rawValue.lowercased()):\(action.id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private static func nativeToolId(_ action: AgentAction) -> String {
    action.parameters["tool_id"] ?? ""
  }

  private static func searchableValue(_ action: AgentAction) -> String {
    var parts = [action.id, action.kind.rawValue, action.target, action.description]
    for (key, value) in action.parameters where !key.hasPrefix(internalParameterPrefix) {
      parts.append(key)
      parts.append(value)
    }
    return parts.joined(separator: " ").lowercased()
  }

  private static func requiresAlwaysHomeAssistantConfirmation(_ inputJson: String) -> Bool {
    let input = homeAssistantInput(inputJson)
    let cleanEntity = input.entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let entityDomain = cleanEntity.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    let identity = "\(cleanEntity) \(input.serviceDomain.lowercased()) \(input.service.lowercased())"
    return homeAssistantAlwaysConfirmDomains.contains(entityDomain) ||
      homeAssistantAlwaysConfirmServices.contains(input.service.lowercased()) ||
      homeAssistantAlwaysConfirmIdentityTerms.contains(where: identity.contains)
  }

  private static func homeAssistantConsentScope(_ inputJson: String) -> String {
    let entityId = homeAssistantInput(inputJson).entityId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if entityId.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil {
      return "home_assistant_control:\(entityId)"
    }
    return "home_assistant_control"
  }

  private static func homeAssistantInput(_ inputJson: String) -> (entityId: String, serviceDomain: String, service: String) {
    guard let data = inputJson.data(using: .utf8),
          let rawObject = try? JSONSerialization.jsonObject(with: data),
          let object = rawObject as? [String: Any] else {
      return ("", "", "")
    }
    return (
      object["entity_id"] as? String ?? "",
      object["service_domain"] as? String ?? "",
      object["service"] as? String ?? ""
    )
  }

  private static let internalParameterPrefix = "_galaxyssi_"
  private static let homeAssistantServiceCall = "galaxyssi.home_assistant.service.call"
  private static let homeAssistantEntitiesList = "galaxyssi.home_assistant.entities.list"
  private static let homeAssistantEntityRead = "galaxyssi.home_assistant.entity.read"
  private static let bluetoothDiscoveryForeground = "galaxyssi.hardware.bluetooth.discovery.foreground"
  private static let installedAppsList = "galaxyssi.hardware.apps.installed.list"
  private static let packageDetail = "galaxyssi.hardware.apps.package.detail"
  private static let wifiScanStart = "galaxyssi.android.wifi.scan.start"
  private static let webSearch = "web.search"

  private static let alwaysConfirmKinds: Set<AgentActionKind> = [.replyNotification, .deleteText, .lockScreen]
  private static let directActionIds: Set<String> = [
    "set-timer", "open-timer", "set-alarm", "open-camera", "open-flashlight",
    "battery-status", "device-status"
  ]
  private static let desktopRemoteNativeToolIds: Set<String> = [
    "galaxyssi.desktop.windows.system.status",
    "galaxyssi.desktop.windows.process.list",
    "galaxyssi.desktop.workspace.file.list",
    "galaxyssi.desktop.workspace.file.read.text",
    "galaxyssi.desktop.workspace.file.write.text",
    "galaxyssi.desktop.workspace.file.sha256",
    "galaxyssi.desktop.workspace.archive.create",
    "galaxyssi.desktop.terminal.run",
    "galaxyssi.desktop.office.document.inspect",
    "galaxyssi.desktop.office.document.convert"
  ]
  private static let webIntelligenceToolIds: Set<String> = [
    "galaxyssi.web.intelligence.search",
    "galaxyssi.web.intelligence.fetch",
    "galaxyssi.web.intelligence.crawl",
    "galaxyssi.web.intelligence.extract",
    "galaxyssi.web.intelligence.cache",
    "galaxyssi.web.intelligence.find_similar",
    "galaxyssi.web.intelligence.research",
    "galaxyssi.web.intelligence.agent",
    "galaxyssi.web.intelligence.diff",
    "galaxyssi.web.intelligence.watch"
  ]
  private static let directNativeToolIds = Set([
    "galaxyssi.hardware.device.status",
    "galaxyssi.hardware.battery.status",
    "galaxyssi.hardware.power.status",
    "galaxyssi.hardware.memory.status",
    "galaxyssi.hardware.storage.status",
    "galaxyssi.hardware.network.status",
    "galaxyssi.hardware.sensors.list",
    "galaxyssi.hardware.sensor.sample",
    "galaxyssi.hardware.bluetooth.status",
    "galaxyssi.hardware.nfc.status",
    "galaxyssi.hardware.flashlight.set",
    "galaxyssi.camera.capture.visible",
    "web.search",
    "galaxyssi.media.ffmpeg.transcode",
    "galaxyssi.runtime.execute",
    "galaxyssi.hardware.bluetooth.pairing.handoff",
    "galaxyssi.android.audio.status",
    "galaxyssi.android.audio.volume.set",
    "galaxyssi.android.audio.mute.set",
    "galaxyssi.android.wifi.panel.open",
    "galaxyssi.android.wifi.hotspot.panel.open",
    "galaxyssi.android.biometric.enrollment.open"
  ])
    .union(webIntelligenceToolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.directToolIds)
  private static let confirmOnceNativeToolIds: Set<String> = Set([
    "galaxyssi.microphone.record.visible",
    "galaxyssi.notifications.list",
    bluetoothDiscoveryForeground,
    installedAppsList,
    packageDetail,
    wifiScanStart,
    "galaxyssi.runtime.packs.install",
    homeAssistantEntitiesList,
    homeAssistantEntityRead,
    homeAssistantServiceCall
  ]).union(AgentIOSWebMediaNativeToolCatalog.confirmOnceToolIds)
  private static let alwaysConfirmNativeToolIds: Set<String> = [
    "galaxyssi.notifications.reply",
    "galaxyssi.desktop.terminal.run"
  ]

  private static let alwaysConfirmTerms = [
    "send sms", "sms.send", "reply sms", "send message", "reply message", "reply notification",
    "send email", "reply email", "phone call", "dial", "telephony.dial", "delete", "remove",
    "install", "uninstall", "payment", "purchase", "checkout", "transfer", "grant permission",
    "authorize", "security setting", "system setting", "registry edit", "screen lock", "lock device",
    "device_policy.lock", "reboot", "git commit", "git push", "submit code", "commit code",
    "door lock", "smart lock", "garage door", "alarm panel", "private key", "password",
    "\u{53D1}\u{9001}\u{77ED}\u{4FE1}", "\u{56DE}\u{590D}\u{77ED}\u{4FE1}",
    "\u{53D1}\u{6D88}\u{606F}", "\u{56DE}\u{590D}\u{6D88}\u{606F}",
    "\u{6253}\u{7535}\u{8BDD}", "\u{62E8}\u{53F7}", "\u{5220}\u{9664}",
    "\u{5B89}\u{88C5}", "\u{5378}\u{8F7D}", "\u{652F}\u{4ED8}",
    "\u{8F6C}\u{8D26}", "\u{6388}\u{6743}", "\u{6743}\u{9650}",
    "\u{5B89}\u{5168}\u{8BBE}\u{7F6E}", "\u{7CFB}\u{7EDF}\u{8BBE}\u{7F6E}",
    "\u{63D0}\u{4EA4}\u{4EE3}\u{7801}", "\u{63A8}\u{9001}\u{4EE3}\u{7801}",
    "\u{9501}\u{5C4F}", "\u{91CD}\u{542F}", "\u{95E8}\u{9501}", "\u{8F66}\u{5E93}\u{95E8}"
  ]
  private static let directTerms = [
    "timer", "alarm clock", "set alarm", "camera capture", "take photo", "flashlight", "torch",
    "audio volume", "set volume", "audio mute", "open app", "launch app", "battery status",
    "device status", "read battery", "read device", "\u{8BA1}\u{65F6}\u{5668}",
    "\u{95F9}\u{949F}", "\u{62CD}\u{7167}", "\u{624B}\u{7535}\u{7B52}",
    "\u{97F3}\u{91CF}", "\u{6253}\u{5F00}app", "\u{6253}\u{5F00} app",
    "\u{7535}\u{91CF}", "\u{8BBE}\u{5907}\u{72B6}\u{6001}"
  ]
  private static let locationTerms = ["location", "gps", "\u{5B9A}\u{4F4D}", "\u{4F4D}\u{7F6E}"]
  private static let microphoneTerms = ["microphone", "record audio", "\u{9EA6}\u{514B}\u{98CE}", "\u{5F55}\u{97F3}"]
  private static let downloadTerms = ["download", "\u{4E0B}\u{8F7D}"]
  private static let contactWriteTerms = [
    "contacts.write", "contact upsert", "create contact", "update contact",
    "\u{65B0}\u{5EFA}\u{8054}\u{7CFB}\u{4EBA}", "\u{4FEE}\u{6539}\u{8054}\u{7CFB}\u{4EBA}",
    "\u{66F4}\u{65B0}\u{8054}\u{7CFB}\u{4EBA}"
  ]
  private static let calendarWriteTerms = [
    "calendar.write", "calendar event upsert", "create calendar event", "update calendar event",
    "\u{65B0}\u{5EFA}\u{65E5}\u{7A0B}", "\u{4FEE}\u{6539}\u{65E5}\u{7A0B}",
    "\u{66F4}\u{65B0}\u{65E5}\u{7A0B}"
  ]
  private static let confirmOnceTerms = locationTerms + microphoneTerms + downloadTerms + contactWriteTerms + calendarWriteTerms
  private static let homeAssistantAlwaysConfirmDomains: Set<String> = [
    "alarm_control_panel", "automation", "camera", "lock", "script", "siren", "valve"
  ]
  private static let homeAssistantAlwaysConfirmServices: Set<String> = [
    "alarm_arm_away", "alarm_arm_home", "alarm_arm_night", "alarm_disarm", "alarm_trigger", "unlock"
  ]
  private static let homeAssistantAlwaysConfirmIdentityTerms = [
    "alarm", "door", "gate", "garage", "lock", "security", "siren"
  ]
}

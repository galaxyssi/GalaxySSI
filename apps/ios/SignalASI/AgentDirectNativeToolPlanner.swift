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

  private static func isPowerStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["battery saver", "low power", "power status", "\u{7701}\u{7535}\u{6a21}\u{5f0f}"])
  }

  private static func isStorageStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["storage status", "phone storage", "device storage", "\u{5b58}\u{50a8}"])
  }

  private static func isNetworkStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["network status", "phone network", "device network", "\u{7f51}\u{7edc}\u{72b6}\u{6001}"])
  }

  private static func isWifiStatusGoal(_ lower: String) -> Bool {
    containsAny(lower, ["wifi status", "wi-fi status", "wireless status"]) ||
      (containsAny(lower, ["wifi", "wi-fi"]) && lower.contains("status"))
  }

  private static func isWifiSettingsGoal(_ lower: String) -> Bool {
    containsAny(lower, ["open wifi settings", "open wi-fi settings", "wifi settings", "wi-fi settings"])
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
    if lower.hasPrefix("open url ") || lower.hasPrefix("open website ") {
      let raw = lower.hasPrefix("open url ")
        ? goal.dropFirst("open url ".count)
        : goal.dropFirst("open website ".count)
      guard let url = normalizedHTTPURL(String(raw)) else { return nil }
      return URLHandoff(
        idPrefix: "open-url",
        target: url,
        url: url,
        description: "Open URL"
      )
    }
    if lower.hasPrefix("search web ") || lower.hasPrefix("google ") {
      let raw = lower.hasPrefix("search web ")
        ? goal.dropFirst("search web ".count)
        : goal.dropFirst("google ".count)
      guard let query = encodedURLQuery(String(raw)) else { return nil }
      return URLHandoff(
        idPrefix: "search-web",
        target: "Web Search",
        url: "https://www.google.com/search?q=\(query)",
        description: "Search the web"
      )
    }
    if lower.hasPrefix("open map ") || lower.hasPrefix("map ") || lower.hasPrefix("navigate to ") {
      let raw: Substring
      if lower.hasPrefix("open map ") {
        raw = goal.dropFirst("open map ".count)
      } else if lower.hasPrefix("map ") {
        raw = goal.dropFirst("map ".count)
      } else {
        raw = goal.dropFirst("navigate to ".count)
      }
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
    if containsAny(lower, ["open browser", "open safari", "launch safari"]) {
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
    if containsAny(lower, ["open messages", "open sms"]) {
      return SystemAppHandoff(
        idPrefix: "open-messages",
        target: "Messages",
        bundleId: "com.apple.MobileSMS"
      )
    }
    if containsAny(lower, ["open phone", "open dialer"]) {
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

private extension String {
  func prefixString(_ limit: Int) -> String {
    String(prefix(max(0, limit)))
  }
}

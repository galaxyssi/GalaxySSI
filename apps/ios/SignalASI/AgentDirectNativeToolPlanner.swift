import Foundation

enum AgentDirectNativeToolPlanner {
  static func plan(request: AgentPlanRequest) -> AgentPlan? {
    guard let action = action(for: request) else {
      return nil
    }
    var plan = AgentPlanFactory.singleAction(request: request, action: action)
    plan.plannerProfile = "rule-based-direct-native-tool"
    plan.routeRationale = "A deterministic iOS native-tool route matched this phone operation."
    plan.validation = AgentPlanValidator.validate(plan)
    return plan
  }

  static func action(for request: AgentPlanRequest) -> AgentAction? {
    let goal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty else { return nil }
    let lower = goal.lowercased()

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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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
        responseLanguage: responseLanguage(for: goal)
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

  private static func responseLanguage(for goal: String) -> String {
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

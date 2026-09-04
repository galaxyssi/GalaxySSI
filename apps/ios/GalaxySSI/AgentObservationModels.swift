import CryptoKit
import Foundation

enum AgentObservationDecision: String, Codable, CaseIterable, Identifiable {
  case actionFailed = "ACTION_FAILED"
  case noChangeRequired = "NO_CHANGE_REQUIRED"
  case changedAndStable = "CHANGED_AND_STABLE"
  case changedButUnstable = "CHANGED_BUT_UNSTABLE"
  case timedOut = "TIMED_OUT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentObservationDecision {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .actionFailed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRecoveryDecision: String, Codable, CaseIterable, Identifiable {
  case notNeeded = "NOT_NEEDED"
  case retrySucceeded = "RETRY_SUCCEEDED"
  case retryFailed = "RETRY_FAILED"
  case manualRequired = "MANUAL_REQUIRED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRecoveryDecision {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .manualRequired
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentNotificationItem: Codable, Equatable {
  var key: String
  var packageName: String
  var title: String
  var textPreview: String
  var category: String
  var postedAtMillis: Int64
  var canReply: Bool
  var sensitiveFlags: [String]

  init(
    key: String = "",
    packageName: String = "",
    title: String = "",
    textPreview: String = "",
    category: String = "app",
    postedAtMillis: Int64 = 0,
    canReply: Bool = false,
    sensitiveFlags: [String] = []
  ) {
    self.key = String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255))
    self.packageName = String(packageName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255))
    self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.textPreview = String(textPreview.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320))
    self.category = String(category.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
    self.postedAtMillis = max(0, postedAtMillis)
    self.canReply = canReply
    self.sensitiveFlags = Array(
      sensitiveFlags
        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
        .filter { !$0.isEmpty }
        .prefix(8)
    )
  }

  enum CodingKeys: String, CodingKey {
    case key
    case packageName = "package_name"
    case title
    case textPreview = "text_preview"
    case category
    case postedAtMillis = "posted_at_millis"
    case canReply = "can_reply"
    case sensitiveFlags = "sensitive_flags"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      key: try container.decodeIfPresent(String.self, forKey: .key) ?? "",
      packageName: try container.decodeIfPresent(String.self, forKey: .packageName) ?? "",
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      textPreview: try container.decodeIfPresent(String.self, forKey: .textPreview) ?? "",
      category: try container.decodeIfPresent(String.self, forKey: .category) ?? "app",
      postedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .postedAtMillis) ?? 0,
      canReply: try container.decodeIfPresent(Bool.self, forKey: .canReply) ?? false,
      sensitiveFlags: try container.decodeIfPresent([String].self, forKey: .sensitiveFlags) ?? []
    )
  }
}

struct AgentNotificationContext: Codable, Equatable {
  var hasAccess: Bool
  var items: [AgentNotificationItem]
  var sensitiveFlags: [String]
  var totalCount: Int

  init(
    hasAccess: Bool = false,
    items: [AgentNotificationItem] = [],
    sensitiveFlags: [String] = [],
    totalCount: Int? = nil
  ) {
    self.hasAccess = hasAccess
    self.items = Array(items.prefix(6))
    self.sensitiveFlags = Array(
      sensitiveFlags
        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
        .filter { !$0.isEmpty }
        .prefix(8)
    )
    self.totalCount = max(0, totalCount ?? items.count)
  }

  enum CodingKeys: String, CodingKey {
    case hasAccess = "has_access"
    case items
    case sensitiveFlags = "sensitive_flags"
    case totalCount = "total_count"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      hasAccess: try container.decodeIfPresent(Bool.self, forKey: .hasAccess) ?? false,
      items: try container.decodeIfPresent([AgentNotificationItem].self, forKey: .items) ?? [],
      sensitiveFlags: try container.decodeIfPresent([String].self, forKey: .sensitiveFlags) ?? [],
      totalCount: try container.decodeIfPresent(Int.self, forKey: .totalCount)
    )
  }
}

struct AgentClipboardContext: Codable, Equatable {
  var hasText: Bool
  var textLength: Int
  var textHash: String
  var preview: String
  var sensitiveFlags: [String]

  init(
    hasText: Bool = false,
    textLength: Int = 0,
    textHash: String = "",
    preview: String = "",
    sensitiveFlags: [String] = []
  ) {
    self.hasText = hasText
    self.textLength = max(textLength, 0)
    self.textHash = String(textHash.prefix(128))
    self.preview = String(preview.prefix(96))
    self.sensitiveFlags = Array(
      sensitiveFlags
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .prefix(8)
    )
  }

  static func fromText(_ rawText: String) -> AgentClipboardContext {
    guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return AgentClipboardContext()
    }
    let normalized = rawText.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let flags = sensitiveFlags(for: rawText)
    return AgentClipboardContext(
      hasText: true,
      textLength: rawText.count,
      textHash: SHA256.hash(data: Data(rawText.utf8))
        .map { String(format: "%02x", $0) }
        .joined(),
      preview: flags.isEmpty ? normalized : "",
      sensitiveFlags: flags
    )
  }

  private static func sensitiveFlags(for text: String) -> [String] {
    let normalized = text.lowercased()
    var flags: [String] = []
    let terms = [
      ("password", "password"),
      ("passcode", "passcode"),
      ("verification code", "verification_code"),
      ("one-time code", "one_time_code"),
      ("otp", "otp"),
      ("api key", "api_key"),
      ("secret key", "secret_key"),
      ("private key", "private_key"),
      ("seed phrase", "seed_phrase"),
      ("credit card", "financial")
    ]
    for (term, flag) in terms where normalized.contains(term) {
      flags.append(flag)
    }
    if normalized.range(of: #"\b(?:\d[ -]?){13,19}\b"#, options: .regularExpression) != nil {
      flags.append("financial")
    }
    return Array(Set(flags)).sorted()
  }
}

struct AgentDeviceStatusContext: Codable, Equatable {
  var batteryPercent: Int
  var charging: Bool
  var powerSaveMode: Bool
  var network: String
  var freeStorageMb: Int64
  var totalStorageMb: Int64
  var thermalState: String

  init(
    batteryPercent: Int = -1,
    charging: Bool = false,
    powerSaveMode: Bool = false,
    network: String = "unknown",
    freeStorageMb: Int64 = 0,
    totalStorageMb: Int64 = 0,
    thermalState: String = "unknown"
  ) {
    self.batteryPercent = batteryPercent < 0 ? -1 : min(batteryPercent, 100)
    self.charging = charging
    self.powerSaveMode = powerSaveMode
    let cleanNetwork = network.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.network = String((cleanNetwork.isEmpty ? "unknown" : cleanNetwork).prefix(32))
    self.freeStorageMb = max(0, freeStorageMb)
    self.totalStorageMb = max(0, totalStorageMb)
    let cleanThermalState = thermalState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.thermalState = String((cleanThermalState.isEmpty ? "unknown" : cleanThermalState).prefix(32))
  }

  enum CodingKeys: String, CodingKey {
    case batteryPercent = "battery_percent"
    case charging
    case powerSaveMode = "power_save_mode"
    case network
    case freeStorageMb = "free_storage_mb"
    case totalStorageMb = "total_storage_mb"
    case thermalState = "thermal_state"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      batteryPercent: try container.decodeIfPresent(Int.self, forKey: .batteryPercent) ?? -1,
      charging: try container.decodeIfPresent(Bool.self, forKey: .charging) ?? false,
      powerSaveMode: try container.decodeIfPresent(Bool.self, forKey: .powerSaveMode) ?? false,
      network: try container.decodeIfPresent(String.self, forKey: .network) ?? "unknown",
      freeStorageMb: try container.decodeIfPresent(Int64.self, forKey: .freeStorageMb) ?? 0,
      totalStorageMb: try container.decodeIfPresent(Int64.self, forKey: .totalStorageMb) ?? 0,
      thermalState: try container.decodeIfPresent(String.self, forKey: .thermalState) ?? "unknown"
    )
  }
}

struct AgentScreenContext: Codable, Equatable {
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var visibleTextCount: Int
  var clickableNodeCount: Int
  var inputFieldCount: Int
  var scrollableRegionCount: Int
  var sensitiveFlagCount: Int
  var visibleTexts: [String]
  var selectedText: String
  var notifications: AgentNotificationContext
  var clipboard: AgentClipboardContext
  var focusedInputField: AgentScreenElement?
  var clickableElements: [AgentScreenElement]
  var inputFields: [AgentScreenElement]
  var scrollableRegions: [AgentScreenElement]
  var sensitiveFlags: [String]
  var deviceStatus: AgentDeviceStatusContext
  var isAccessibilityEnabled: Bool
  var snapshotAgeMillis: Int64

  init(
    foregroundApp: String,
    activityName: String = "",
    pageTitle: String = "",
    visibleTextCount: Int = 0,
    clickableNodeCount: Int = 0,
    inputFieldCount: Int = 0,
    scrollableRegionCount: Int = 0,
    sensitiveFlagCount: Int = 0,
    visibleTexts: [String] = [],
    selectedText: String = "",
    notifications: AgentNotificationContext = AgentNotificationContext(),
    clipboard: AgentClipboardContext = AgentClipboardContext(),
    focusedInputField: AgentScreenElement? = nil,
    clickableElements: [AgentScreenElement] = [],
    inputFields: [AgentScreenElement] = [],
    scrollableRegions: [AgentScreenElement] = [],
    sensitiveFlags: [String] = [],
    deviceStatus: AgentDeviceStatusContext = AgentDeviceStatusContext(),
    isAccessibilityEnabled: Bool = false,
    snapshotAgeMillis: Int64 = 0
  ) {
    self.foregroundApp = foregroundApp
    self.activityName = activityName
    self.pageTitle = pageTitle
    self.visibleTextCount = max(visibleTextCount, 0)
    self.clickableNodeCount = max(clickableNodeCount, 0)
    self.inputFieldCount = max(inputFieldCount, 0)
    self.scrollableRegionCount = max(scrollableRegionCount, 0)
    self.sensitiveFlagCount = max(sensitiveFlagCount, 0)
    self.visibleTexts = visibleTexts
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumVisibleTextLength)) }
      .filter { !$0.isEmpty }
      .prefix(Self.maximumVisibleTextItems)
      .map { $0 }
    self.selectedText = String(selectedText.prefix(Self.maximumSelectedTextLength))
    self.notifications = notifications
    self.clipboard = clipboard
    self.focusedInputField = focusedInputField
    self.clickableElements = Array(clickableElements.prefix(Self.maximumScreenElements))
    self.inputFields = Array(inputFields.prefix(Self.maximumScreenElements))
    self.scrollableRegions = Array(scrollableRegions.prefix(Self.maximumScreenElements))
    self.sensitiveFlags = Array(
      sensitiveFlags
        .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
        .filter { !$0.isEmpty }
        .prefix(Self.maximumSensitiveFlags)
    )
    self.deviceStatus = deviceStatus
    self.isAccessibilityEnabled = isAccessibilityEnabled
    self.snapshotAgeMillis = max(snapshotAgeMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case foregroundApp = "foreground_app"
    case activityName = "activity_name"
    case pageTitle = "page_title"
    case visibleTextCount = "visible_text_count"
    case clickableNodeCount = "clickable_node_count"
    case inputFieldCount = "input_field_count"
    case scrollableRegionCount = "scrollable_region_count"
    case sensitiveFlagCount = "sensitive_flag_count"
    case visibleTexts = "visible_texts"
    case selectedText = "selected_text"
    case notifications
    case clipboard
    case focusedInputField = "focused_input_field"
    case clickableElements = "clickable_elements"
    case inputFields = "input_fields"
    case scrollableRegions = "scrollable_regions"
    case sensitiveFlags = "sensitive_flags"
    case deviceStatus = "device_status"
    case isAccessibilityEnabled = "is_accessibility_enabled"
    case snapshotAgeMillis = "snapshot_age_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      foregroundApp: try container.decodeIfPresent(String.self, forKey: .foregroundApp) ?? "",
      activityName: try container.decodeIfPresent(String.self, forKey: .activityName) ?? "",
      pageTitle: try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "",
      visibleTextCount: try container.decodeIfPresent(Int.self, forKey: .visibleTextCount) ?? 0,
      clickableNodeCount: try container.decodeIfPresent(Int.self, forKey: .clickableNodeCount) ?? 0,
      inputFieldCount: try container.decodeIfPresent(Int.self, forKey: .inputFieldCount) ?? 0,
      scrollableRegionCount: try container.decodeIfPresent(Int.self, forKey: .scrollableRegionCount) ?? 0,
      sensitiveFlagCount: try container.decodeIfPresent(Int.self, forKey: .sensitiveFlagCount) ?? 0,
      visibleTexts: try container.decodeIfPresent([String].self, forKey: .visibleTexts) ?? [],
      selectedText: try container.decodeIfPresent(String.self, forKey: .selectedText) ?? "",
      notifications: try container.decodeIfPresent(AgentNotificationContext.self, forKey: .notifications) ?? AgentNotificationContext(),
      clipboard: try container.decodeIfPresent(AgentClipboardContext.self, forKey: .clipboard) ?? AgentClipboardContext(),
      focusedInputField: try container.decodeIfPresent(AgentScreenElement.self, forKey: .focusedInputField),
      clickableElements: try container.decodeIfPresent([AgentScreenElement].self, forKey: .clickableElements) ?? [],
      inputFields: try container.decodeIfPresent([AgentScreenElement].self, forKey: .inputFields) ?? [],
      scrollableRegions: try container.decodeIfPresent([AgentScreenElement].self, forKey: .scrollableRegions) ?? [],
      sensitiveFlags: try container.decodeIfPresent([String].self, forKey: .sensitiveFlags) ?? [],
      deviceStatus: try container.decodeIfPresent(AgentDeviceStatusContext.self, forKey: .deviceStatus) ?? AgentDeviceStatusContext(),
      isAccessibilityEnabled: try container.decodeIfPresent(Bool.self, forKey: .isAccessibilityEnabled) ?? false,
      snapshotAgeMillis: try container.decodeIfPresent(Int64.self, forKey: .snapshotAgeMillis) ?? 0
    )
  }

  private static let maximumVisibleTextItems = 80
  private static let maximumVisibleTextLength = 300
  private static let maximumSelectedTextLength = 1_000
  private static let maximumScreenElements = 80
  private static let maximumSensitiveFlags = 12
}

struct AgentObservationOutcome: Codable, Equatable {
  var screen: AgentScreenContext
  var decision: AgentObservationDecision
  var sampleCount: Int
  var durationMillis: Int64
  var screenChanged: Bool
  var screenStable: Bool
  var evidence: String

  init(
    screen: AgentScreenContext,
    decision: AgentObservationDecision,
    sampleCount: Int,
    durationMillis: Int64,
    screenChanged: Bool,
    screenStable: Bool,
    evidence: String = ""
  ) {
    self.screen = screen
    self.decision = decision
    self.sampleCount = max(sampleCount, 0)
    self.durationMillis = max(durationMillis, 0)
    self.screenChanged = screenChanged
    self.screenStable = screenStable
    self.evidence = String(evidence.prefix(Self.maximumEvidenceLength))
  }

  enum CodingKeys: String, CodingKey {
    case screen
    case decision
    case sampleCount = "sample_count"
    case durationMillis = "duration_millis"
    case screenChanged = "screen_changed"
    case screenStable = "screen_stable"
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      screen: try container.decodeIfPresent(AgentScreenContext.self, forKey: .screen) ?? AgentScreenContext(foregroundApp: ""),
      decision: try container.decodeIfPresent(AgentObservationDecision.self, forKey: .decision) ?? .actionFailed,
      sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0,
      durationMillis: try container.decodeIfPresent(Int64.self, forKey: .durationMillis) ?? 0,
      screenChanged: try container.decodeIfPresent(Bool.self, forKey: .screenChanged) ?? false,
      screenStable: try container.decodeIfPresent(Bool.self, forKey: .screenStable) ?? false,
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    )
  }

  private static let maximumEvidenceLength = 2_000
}

struct AgentObservedContext: Codable, Equatable, Identifiable {
  static let defaultTTLMillis: Int64 = 24 * 60 * 60 * 1_000

  var id: String
  var targetId: String
  var text: String
  var conversationId: String
  var taskId: String
  var createdAtMillis: Int64
  var expiresAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    targetId: String,
    text: String,
    conversationId: String = "",
    taskId: String = "",
    createdAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    expiresAtMillis: Int64? = nil
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
    self.targetId = String(targetId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTargetCharacters))
    self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxEntryCharacters))
    self.conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    self.taskId = String(taskId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.expiresAtMillis = max(expiresAtMillis ?? (self.createdAtMillis + Self.defaultTTLMillis), 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case targetId = "target_id"
    case text
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case createdAtMillis = "created_at_millis"
    case expiresAtMillis = "expires_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let createdAtMillis = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      createdAtMillis: createdAtMillis,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis)
    )
  }

  func isExpired(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> Bool {
    expiresAtMillis > 0 && nowMillis >= expiresAtMillis
  }

  var isUsable: Bool {
    !targetId.isEmpty && !text.isEmpty
  }

  static let maxTotalEntries = 128
  static let maxEntriesPerTarget = 16
  static let maxTargetCharacters = 160
  static let maxIdCharacters = 160
  static let maxEntryCharacters = 8_000
}

enum AgentObservationContextJsonCodec {
  static func encode(_ items: [AgentObservedContext]) -> String {
    guard let data = try? JSONEncoder().encode(items) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(
    _ raw: String,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [AgentObservedContext] {
    guard let data = raw.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
      return []
    }
    let decoded = array.compactMap { value -> AgentObservedContext? in
      guard let object = value as? [String: Any],
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let item = try? JSONDecoder().decode(AgentObservedContext.self, from: data) else {
        return nil
      }
      return item
    }
    return decoded.filter { $0.isUsable && !$0.isExpired(nowMillis: nowMillis) }
  }
}

protocol AgentObservationContextStore: AnyObject {
  func observe(
    targetId: String,
    text: String,
    conversationId: String,
    taskId: String
  ) -> AgentObservedContext?
  func peek(targetId: String, conversationId: String) -> [AgentObservedContext]
  func acknowledge(entryIds: Set<String>) -> Int
  func clearTarget(_ targetId: String) -> Int
  func clear()
}

final class InMemoryAgentObservationContextStore: AgentObservationContextStore {
  private let lock = NSRecursiveLock()
  private let clock: () -> Int64
  private let idFactory: () -> String
  private var document: String

  init(
    serialized: String = "[]",
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    idFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.document = serialized
    self.clock = clock
    self.idFactory = idFactory
  }

  func observe(
    targetId: String,
    text: String,
    conversationId: String = "",
    taskId: String = ""
  ) -> AgentObservedContext? {
    lock.lock()
    defer { lock.unlock() }
    let now = max(clock(), 0)
    let entry = AgentObservedContext(
      id: idFactory(),
      targetId: targetId,
      text: text,
      conversationId: conversationId,
      taskId: taskId,
      createdAtMillis: now,
      expiresAtMillis: now + AgentObservedContext.defaultTTLMillis
    )
    guard entry.isUsable else {
      return nil
    }
    let current = load(nowMillis: now).filter { existing in
      !(existing.targetId == entry.targetId &&
        existing.text == entry.text &&
        existing.conversationId == entry.conversationId)
    }
    let otherTargets = current.filter { $0.targetId != entry.targetId }
    let targetEntries = Array((current.filter { $0.targetId == entry.targetId } + [entry]).suffix(AgentObservedContext.maxEntriesPerTarget))
    let bounded = Array((otherTargets + targetEntries)
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
      .suffix(AgentObservedContext.maxTotalEntries))
    save(bounded)
    return entry
  }

  func peek(targetId: String, conversationId: String = "") -> [AgentObservedContext] {
    lock.lock()
    defer { lock.unlock() }
    let targetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return Array(load(nowMillis: max(clock(), 0)).filter { entry in
      entry.targetId == targetId &&
        (conversationId.isEmpty || entry.conversationId.isEmpty || entry.conversationId == conversationId)
    }.suffix(AgentObservedContext.maxEntriesPerTarget))
  }

  func acknowledge(entryIds: Set<String>) -> Int {
    lock.lock()
    defer { lock.unlock() }
    guard !entryIds.isEmpty else {
      return 0
    }
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { !entryIds.contains($0.id) }
    if remaining.count != current.count {
      save(remaining)
    }
    return current.count - remaining.count
  }

  func clearTarget(_ targetId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let targetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { $0.targetId != targetId }
    if remaining.count != current.count {
      save(remaining)
    }
    return current.count - remaining.count
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    document = "[]"
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    return document
  }

  private func load(nowMillis: Int64) -> [AgentObservedContext] {
    AgentObservationContextJsonCodec.decode(document, nowMillis: nowMillis)
  }

  private func save(_ items: [AgentObservedContext]) {
    document = AgentObservationContextJsonCodec.encode(items)
  }
}

struct AgentContinuousObservationController {
  let maxSamples: Int
  let stableSampleCount: Int
  let sampleIntervalMillis: Int64

  init(
    maxSamples: Int = 10,
    stableSampleCount: Int = 2,
    sampleIntervalMillis: Int64 = 250
  ) {
    precondition((1...Self.maxAllowedSamples).contains(maxSamples))
    precondition((1...maxSamples).contains(stableSampleCount))
    precondition((0...Self.maxSampleIntervalMillis).contains(sampleIntervalMillis))
    self.maxSamples = maxSamples
    self.stableSampleCount = stableSampleCount
    self.sampleIntervalMillis = sampleIntervalMillis
  }

  func observe(
    beforeAction: AgentScreenContext,
    actionSucceeded: Bool,
    changeExpected: Bool,
    capture: () -> AgentScreenContext,
    sleep: (Int64) -> Void = { millis in
      guard millis > 0 else { return }
      Thread.sleep(forTimeInterval: Double(millis) / 1_000)
    },
    nowMillis: () -> Int64 = {
      Int64(Date().timeIntervalSince1970 * 1_000)
    }
  ) -> AgentObservationOutcome {
    let startedAt = nowMillis()
    var latest = capture()
    if !actionSucceeded {
      return outcome(
        screen: latest,
        decision: .actionFailed,
        sampleCount: 1,
        startedAt: startedAt,
        changed: latest.fingerprint() != beforeAction.fingerprint(),
        stable: false,
        nowMillis: nowMillis
      )
    }
    if !changeExpected {
      return outcome(
        screen: latest,
        decision: .noChangeRequired,
        sampleCount: 1,
        startedAt: startedAt,
        changed: latest.fingerprint() != beforeAction.fingerprint(),
        stable: true,
        nowMillis: nowMillis
      )
    }

    let beforeFingerprint = beforeAction.fingerprint()
    var previousFingerprint: AgentScreenFingerprint?
    var changed = false
    var stableSamples = 0
    var samples = 0
    for index in 0..<maxSamples {
      if index > 0 {
        sleep(sampleIntervalMillis)
        latest = capture()
      }
      samples += 1
      let fingerprint = latest.fingerprint()
      let differsFromBefore = fingerprint != beforeFingerprint
      changed = changed || differsFromBefore
      if !differsFromBefore {
        stableSamples = 0
      } else if previousFingerprint == fingerprint {
        stableSamples += 1
      } else {
        stableSamples = 1
      }
      previousFingerprint = fingerprint
      if changed && stableSamples >= stableSampleCount {
        return outcome(
          screen: latest,
          decision: .changedAndStable,
          sampleCount: samples,
          startedAt: startedAt,
          changed: true,
          stable: true,
          nowMillis: nowMillis
        )
      }
    }
    return outcome(
      screen: latest,
      decision: changed ? .changedButUnstable : .timedOut,
      sampleCount: samples,
      startedAt: startedAt,
      changed: changed,
      stable: false,
      nowMillis: nowMillis
    )
  }

  private func outcome(
    screen: AgentScreenContext,
    decision: AgentObservationDecision,
    sampleCount: Int,
    startedAt: Int64,
    changed: Bool,
    stable: Bool,
    nowMillis: () -> Int64
  ) -> AgentObservationOutcome {
    let duration = max(nowMillis() - startedAt, 0)
    return AgentObservationOutcome(
      screen: screen,
      decision: decision,
      sampleCount: sampleCount,
      durationMillis: duration,
      screenChanged: changed,
      screenStable: stable,
      evidence: "decision=\(decision.rawValue); samples=\(sampleCount); duration_ms=\(duration); changed=\(changed); stable=\(stable)"
    )
  }

  private static let maxAllowedSamples = 30
  private static let maxSampleIntervalMillis: Int64 = 2_000
}

private struct AgentScreenFingerprint: Equatable {
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var visibleTextCount: Int
  var clickableNodeCount: Int
  var inputFieldCount: Int
  var scrollableRegionCount: Int
  var sensitiveFlagCount: Int
  var selectedText: String
  var isAccessibilityEnabled: Bool
}

private extension AgentScreenContext {
  func fingerprint() -> AgentScreenFingerprint {
    AgentScreenFingerprint(
      foregroundApp: foregroundApp,
      activityName: activityName,
      pageTitle: pageTitle,
      visibleTextCount: visibleTextCount,
      clickableNodeCount: clickableNodeCount,
      inputFieldCount: inputFieldCount,
      scrollableRegionCount: scrollableRegionCount,
      sensitiveFlagCount: sensitiveFlagCount,
      selectedText: Self.normalizedFingerprintText(selectedText),
      isAccessibilityEnabled: isAccessibilityEnabled
    )
  }

  private static func normalizedFingerprintText(_ value: String) -> String {
    value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

struct AgentActionResult: Codable, Equatable {
  var actionId: String
  var success: Bool
  var message: String
  var metadata: [String: String]

  init(
    actionId: String,
    success: Bool,
    message: String,
    metadata: [String: String] = [:]
  ) {
    self.actionId = actionId
    self.success = success
    self.message = String(message.prefix(Self.maximumMessageLength))
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case actionId = "action_id"
    case success
    case message
    case metadata
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      actionId: try container.decodeIfPresent(String.self, forKey: .actionId) ?? "",
      success: try container.decodeIfPresent(Bool.self, forKey: .success) ?? false,
      message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }

  private static let maximumMessageLength = 2_000
}

struct AgentRecoveryAttempt: Equatable {
  var result: AgentActionResult?
  var observation: AgentObservationOutcome
}

struct AgentRecoveryOutcome: Equatable {
  var result: AgentActionResult?
  var observation: AgentObservationOutcome
  var decision: AgentRecoveryDecision
  var attemptCount: Int
}

enum AgentPhase: String, Codable, CaseIterable, Identifiable {
  case observing = "OBSERVING"
  case planning = "PLANNING"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case executing = "EXECUTING"
  case verifying = "VERIFYING"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case cancelled = "CANCELLED"
  case blocked = "BLOCKED"
  case completed = "COMPLETED"
  case failed = "FAILED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPhase {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .executing
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentExecutionLoopPhase: String, Codable, CaseIterable, Identifiable {
  case plan = "PLAN"
  case act = "ACT"
  case observe = "OBSERVE"
  case replan = "REPLAN"
  case verify = "VERIFY"
  case finalize = "FINALIZE"
  case learn = "LEARN"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case blocked = "BLOCKED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case completed = "COMPLETED"

  var id: String { rawValue }

  var isActive: Bool {
    [.plan, .act, .observe, .replan, .verify, .finalize, .learn].contains(self)
  }

  var isTerminal: Bool {
    [.blocked, .failed, .cancelled, .completed].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentExecutionLoopPhase {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .plan
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentExecutionLoopUsage: Codable, Equatable {
  var iterations: Int
  var actions: Int
  var replans: Int
  var toolCalls: Int
  var retries: Int
  var activeDurationMillis: Int64
  var activeSinceMillis: Int64

  init(
    iterations: Int = 0,
    actions: Int = 0,
    replans: Int = 0,
    toolCalls: Int = 0,
    retries: Int = 0,
    activeDurationMillis: Int64 = 0,
    activeSinceMillis: Int64 = 0
  ) {
    self.iterations = iterations
    self.actions = actions
    self.replans = replans
    self.toolCalls = toolCalls
    self.retries = retries
    self.activeDurationMillis = activeDurationMillis
    self.activeSinceMillis = activeSinceMillis
  }

  enum CodingKeys: String, CodingKey {
    case iterations
    case actions
    case replans
    case toolCalls = "tool_calls"
    case retries
    case activeDurationMillis = "active_duration_millis"
    case activeSinceMillis = "active_since_millis"
  }

  func elapsedActiveMillis(nowMillis: Int64, phase: AgentExecutionLoopPhase) -> Int64 {
    activeDurationMillis + (phase.isActive && activeSinceMillis > 0 ? max(nowMillis - activeSinceMillis, 0) : 0)
  }
}

struct AgentExecutionLoopSnapshot: Codable, Equatable {
  var taskId: String
  var phase: AgentExecutionLoopPhase
  var usage: AgentExecutionLoopUsage
  var resumePhase: AgentExecutionLoopPhase
  var lastActionId: String
  var lastReason: String
  var budgetFailure: String
  var startedAtMillis: Int64
  var updatedAtMillis: Int64
  var revision: Int64

  init(
    taskId: String,
    phase: AgentExecutionLoopPhase,
    usage: AgentExecutionLoopUsage = AgentExecutionLoopUsage(),
    resumePhase: AgentExecutionLoopPhase = .plan,
    lastActionId: String = "",
    lastReason: String = "",
    budgetFailure: String = "",
    startedAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    revision: Int64 = 1
  ) {
    self.taskId = taskId
    self.phase = phase
    self.usage = usage
    self.resumePhase = resumePhase
    self.lastActionId = lastActionId
    self.lastReason = lastReason
    self.budgetFailure = budgetFailure
    self.startedAtMillis = startedAtMillis
    self.updatedAtMillis = updatedAtMillis
    self.revision = revision
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case phase
    case usage
    case resumePhase = "resume_phase"
    case lastActionId = "last_action_id"
    case lastReason = "last_reason"
    case budgetFailure = "budget_failure"
    case startedAtMillis = "started_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case revision
  }
}

struct AgentExecutionLoopEvent: Codable, Equatable {
  var previousPhase: AgentExecutionLoopPhase?
  var phase: AgentExecutionLoopPhase
  var reason: String
  var snapshot: AgentExecutionLoopSnapshot
  var toolCall: Bool
  var retry: Bool

  init(
    previousPhase: AgentExecutionLoopPhase? = nil,
    phase: AgentExecutionLoopPhase,
    reason: String = "",
    snapshot: AgentExecutionLoopSnapshot,
    toolCall: Bool = false,
    retry: Bool = false
  ) {
    self.previousPhase = previousPhase
    self.phase = phase
    self.reason = reason
    self.snapshot = snapshot
    self.toolCall = toolCall
    self.retry = retry
  }

  enum CodingKeys: String, CodingKey {
    case previousPhase = "previous_phase"
    case phase
    case reason
    case snapshot
    case toolCall = "tool_call"
    case retry
  }
}

enum AgentRunControlEventType: String, Codable, CaseIterable, Identifiable {
  case runCreated = "RUN_CREATED"
  case runQueued = "RUN_QUEUED"
  case runStarted = "RUN_STARTED"
  case planning = "PLANNING"
  case thinking = "THINKING"
  case agentConnected = "AGENT_CONNECTED"
  case stepStarted = "STEP_STARTED"
  case toolPermissionRequired = "TOOL_PERMISSION_REQUIRED"
  case permissionRevoked = "PERMISSION_REVOKED"
  case toolStarted = "TOOL_STARTED"
  case toolProgress = "TOOL_PROGRESS"
  case toolCompleted = "TOOL_COMPLETED"
  case waitingForUser = "WAITING_FOR_USER"
  case waitingForDevice = "WAITING_FOR_DEVICE"
  case paused = "PAUSED"
  case retrying = "RETRYING"
  case handoff = "HANDOFF"
  case stepCompleted = "STEP_COMPLETED"
  case runCompleted = "RUN_COMPLETED"
  case runFailed = "RUN_FAILED"
  case runCancelled = "RUN_CANCELLED"
  case runRecovered = "RUN_RECOVERED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRunControlEventType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .runFailed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRunControlPayloadValue: Codable, Equatable {
  case string(String)
  case int(Int64)
  case bool(Bool)

  var stringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .int(let value):
      return String(value)
    case .bool(let value):
      return value ? "true" : "false"
    }
  }

  var intValue: Int64? {
    switch self {
    case .int(let value):
      return value
    case .string(let value):
      return Int64(value)
    case .bool:
      return nil
    }
  }

  var boolValue: Bool? {
    switch self {
    case .bool(let value):
      return value
    case .string(let value):
      return Bool(value)
    case .int:
      return nil
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .int(value)
    } else {
      self = .string((try? container.decode(String.self)) ?? "")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    }
  }
}

typealias AgentRunControlPayload = [String: AgentRunControlPayloadValue]

struct AgentRunControlEvent: Codable, Equatable {
  var eventId: String
  var conversationId: String
  var messageId: String
  var taskId: String
  var runId: String
  var stepId: String
  var toolCallId: String
  var agentId: String
  var deviceId: String
  var type: AgentRunControlEventType
  var sequence: Int64
  var timestampMillis: Int64
  var payload: AgentRunControlPayload

  init(
    eventId: String = UUID().uuidString,
    conversationId: String,
    messageId: String,
    taskId: String,
    runId: String,
    stepId: String = "",
    toolCallId: String = "",
    agentId: String,
    deviceId: String,
    type: AgentRunControlEventType,
    sequence: Int64,
    timestampMillis: Int64 = 0,
    payload: AgentRunControlPayload = [:]
  ) {
    self.eventId = eventId
    self.conversationId = conversationId
    self.messageId = messageId
    self.taskId = taskId
    self.runId = runId
    self.stepId = stepId
    self.toolCallId = toolCallId
    self.agentId = agentId
    self.deviceId = deviceId
    self.type = type
    self.sequence = sequence
    self.timestampMillis = timestampMillis
    self.payload = payload
  }

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case taskId = "task_id"
    case runId = "run_id"
    case stepId = "step_id"
    case toolCallId = "tool_call_id"
    case agentId = "agent_id"
    case deviceId = "device_id"
    case type
    case sequence
    case timestampMillis = "timestamp_millis"
    case payload
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    eventId = try container.decodeIfPresent(String.self, forKey: .eventId) ?? UUID().uuidString
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
    messageId = try container.decodeIfPresent(String.self, forKey: .messageId) ?? ""
    taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
    runId = try container.decodeIfPresent(String.self, forKey: .runId) ?? ""
    stepId = try container.decodeIfPresent(String.self, forKey: .stepId) ?? ""
    toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId) ?? ""
    agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
    type = try container.decodeIfPresent(AgentRunControlEventType.self, forKey: .type) ?? .runFailed
    sequence = try container.decodeIfPresent(Int64.self, forKey: .sequence) ?? 0
    timestampMillis = try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0
    payload = try container.decodeIfPresent(AgentRunControlPayload.self, forKey: .payload) ?? [:]
  }
}

enum AgentRunControlState: String, Codable, CaseIterable, Identifiable {
  case created = "CREATED"
  case queued = "QUEUED"
  case running = "RUNNING"
  case waitingForUser = "WAITING_FOR_USER"
  case waitingForDevice = "WAITING_FOR_DEVICE"
  case paused = "PAUSED"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.completed, .failed, .cancelled].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentRunControlState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .failed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentRunControlSnapshot: Codable, Equatable {
  var runId: String
  var taskId: String
  var state: AgentRunControlState
  var agentId: String
  var deviceId: String
  var lastSequence: Int64
  var lastEvent: AgentRunControlEvent

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case taskId = "task_id"
    case state
    case agentId = "agent_id"
    case deviceId = "device_id"
    case lastSequence = "last_sequence"
    case lastEvent = "last_event"
  }
}

enum AgentConnectionKind: String, Codable, CaseIterable, Identifiable {
  case inProcess = "IN_PROCESS"
  case binder = "BINDER"
  case galaxyssiLink = "GALAXYSSI_LINK"
  case cliJson = "CLI_JSON"
  case stdio = "STDIO"
  case http = "HTTP"
  case websocket = "WEBSOCKET"
  case mcp = "MCP"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentConnectionKind {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .http
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentResourceLocation: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case trustedDesktop = "TRUSTED_DESKTOP"
  case privateNetwork = "PRIVATE_NETWORK"
  case cloud = "CLOUD"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentResourceLocation {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cloud
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRecordedRunStatus: String, Codable, CaseIterable, Identifiable {
  case running = "RUNNING"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRecordedRunStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .failed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentRecordedRun: Codable, Equatable, Identifiable {
  var runId: String
  var conversationId: String
  var taskThreadId: String
  var originalRequest: String
  var normalizedIntent: String
  var extractedInputs: AgentMcpJSONObject
  var agentPlan: [AgentMcpJSONValue]
  var toolCalls: [AgentToolCallRecord]
  var sources: [AgentMcpJSONValue]
  var transformations: [AgentMcpJSONValue]
  var finalOutput: AgentMcpJSONObject
  var renderSpec: AgentMcpJSONObject
  var artifacts: [AgentArtifactReference]
  var userFeedback: [String]
  var activeSkillId: String
  var executionResourceId: String
  var parentRunId: String
  var revisionNumber: Int
  var status: AgentRecordedRunStatus
  var createdAtMillis: Int64
  var completedAtMillis: Int64

  var id: String { runId }

  init(
    runId: String,
    conversationId: String,
    taskThreadId: String,
    originalRequest: String,
    normalizedIntent: String = "",
    extractedInputs: AgentMcpJSONObject = [:],
    agentPlan: [AgentMcpJSONValue] = [],
    toolCalls: [AgentToolCallRecord] = [],
    sources: [AgentMcpJSONValue] = [],
    transformations: [AgentMcpJSONValue] = [],
    finalOutput: AgentMcpJSONObject = [:],
    renderSpec: AgentMcpJSONObject = [:],
    artifacts: [AgentArtifactReference] = [],
    userFeedback: [String] = [],
    activeSkillId: String = "",
    executionResourceId: String = "",
    parentRunId: String = "",
    revisionNumber: Int = 1,
    status: AgentRecordedRunStatus = .running,
    createdAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0
  ) {
    self.runId = runId
    self.conversationId = conversationId
    self.taskThreadId = taskThreadId
    self.originalRequest = originalRequest
    self.normalizedIntent = normalizedIntent
    self.extractedInputs = extractedInputs
    self.agentPlan = agentPlan
    self.toolCalls = Array(toolCalls.prefix(AgentSkillLimits.maxToolCalls))
    self.sources = sources
    self.transformations = transformations
    self.finalOutput = finalOutput
    self.renderSpec = renderSpec
    self.artifacts = Array(artifacts.prefix(AgentSkillLimits.maxArtifacts))
    self.userFeedback = userFeedback.prefix(32).map { String($0.prefix(AgentSkillLimits.maxFeedbackCharacters)) }
    self.activeSkillId = String(activeSkillId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.executionResourceId = String(executionResourceId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.parentRunId = String(parentRunId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.revisionNumber = max(revisionNumber, 1)
    self.status = status
    self.createdAtMillis = createdAtMillis
    self.completedAtMillis = completedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case conversationId = "conversation_id"
    case taskThreadId = "task_thread_id"
    case originalRequest = "original_request"
    case normalizedIntent = "normalized_intent"
    case extractedInputs = "extracted_inputs"
    case agentPlan = "agent_plan"
    case toolCalls = "tool_calls"
    case sources
    case transformations
    case finalOutput = "final_output"
    case renderSpec = "render_spec"
    case artifacts
    case userFeedback = "user_feedback"
    case activeSkillId = "active_skill_id"
    case executionResourceId = "execution_resource_id"
    case parentRunId = "parent_run_id"
    case revisionNumber = "revision_number"
    case status
    case createdAtMillis = "created_at_millis"
    case completedAtMillis = "completed_at_millis"
    case createdAtAndroid = "created_at"
    case completedAtAndroid = "completed_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .createdAtAndroid)) ?? 0
    let completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .completedAtAndroid)) ?? 0
    self.init(
      runId: try container.decodeIfPresent(String.self, forKey: .runId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskThreadId: try container.decodeIfPresent(String.self, forKey: .taskThreadId) ?? "",
      originalRequest: try container.decodeIfPresent(String.self, forKey: .originalRequest) ?? "",
      normalizedIntent: try container.decodeIfPresent(String.self, forKey: .normalizedIntent) ?? "",
      extractedInputs: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .extractedInputs) ?? [:],
      agentPlan: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .agentPlan) ?? [],
      toolCalls: try container.decodeIfPresent([AgentToolCallRecord].self, forKey: .toolCalls) ?? [],
      sources: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .sources) ?? [],
      transformations: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .transformations) ?? [],
      finalOutput: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .finalOutput) ?? [:],
      renderSpec: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .renderSpec) ?? [:],
      artifacts: try container.decodeIfPresent([AgentArtifactReference].self, forKey: .artifacts) ?? [],
      userFeedback: try container.decodeIfPresent([String].self, forKey: .userFeedback) ?? [],
      activeSkillId: try container.decodeIfPresent(String.self, forKey: .activeSkillId) ?? "",
      executionResourceId: try container.decodeIfPresent(String.self, forKey: .executionResourceId) ?? "",
      parentRunId: try container.decodeIfPresent(String.self, forKey: .parentRunId) ?? "",
      revisionNumber: try container.decodeIfPresent(Int.self, forKey: .revisionNumber) ?? 1,
      status: try container.decodeIfPresent(AgentRecordedRunStatus.self, forKey: .status) ?? .running,
      createdAtMillis: createdAt,
      completedAtMillis: completedAt
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(runId, forKey: .runId)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(taskThreadId, forKey: .taskThreadId)
    try container.encode(originalRequest, forKey: .originalRequest)
    try container.encode(normalizedIntent, forKey: .normalizedIntent)
    try container.encode(extractedInputs, forKey: .extractedInputs)
    try container.encode(agentPlan, forKey: .agentPlan)
    try container.encode(toolCalls, forKey: .toolCalls)
    try container.encode(sources, forKey: .sources)
    try container.encode(transformations, forKey: .transformations)
    try container.encode(finalOutput, forKey: .finalOutput)
    try container.encode(renderSpec, forKey: .renderSpec)
    try container.encode(artifacts, forKey: .artifacts)
    try container.encode(userFeedback, forKey: .userFeedback)
    try container.encode(activeSkillId, forKey: .activeSkillId)
    try container.encode(executionResourceId, forKey: .executionResourceId)
    try container.encode(parentRunId, forKey: .parentRunId)
    try container.encode(revisionNumber, forKey: .revisionNumber)
    try container.encode(status, forKey: .status)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
    try container.encode(completedAtMillis, forKey: .completedAtMillis)
  }
}

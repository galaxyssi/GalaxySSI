import CryptoKit
import Foundation

enum AgentLongTaskPersistenceLimits {
  static let maximumActions = 1_024
  static let maximumCheckpoints = 128
  static let maximumPageItems = 32
  static let maximumPageJSONCharacters = 64 * 1_024
  static let rootPlanActions = 64
  static let rootActionHistoryItems = 40
  static let rootCheckpoints = 16
}

struct AgentSessionHistoryManifest: Codable, Equatable {
  var version: Int
  var sessionId: String
  var actionPageIds: [String]
  var actionPageItemCounts: [Int]
  var checkpointPageIds: [String]
  var checkpointPageItemCounts: [Int]

  init(
    sessionId: String,
    actionPageIds: [String],
    actionPageItemCounts: [Int],
    checkpointPageIds: [String],
    checkpointPageItemCounts: [Int]
  ) {
    version = 1
    self.sessionId = sessionId
    self.actionPageIds = actionPageIds
    self.actionPageItemCounts = actionPageItemCounts
    self.checkpointPageIds = checkpointPageIds
    self.checkpointPageItemCounts = checkpointPageItemCounts
  }

  var actionCount: Int { actionPageItemCounts.reduce(0, +) }
  var checkpointCount: Int { checkpointPageItemCounts.reduce(0, +) }

  var isValid: Bool {
    version == 1 &&
      actionPageIds.count == actionPageItemCounts.count &&
      checkpointPageIds.count == checkpointPageItemCounts.count &&
      actionPageItemCounts.allSatisfy { $0 > 0 } &&
      checkpointPageItemCounts.allSatisfy { $0 > 0 } &&
      actionPageIds.allSatisfy { !$0.isEmpty } &&
      checkpointPageIds.allSatisfy { !$0.isEmpty }
  }

  enum CodingKeys: String, CodingKey {
    case version
    case sessionId = "session_id"
    case actionPageIds = "action_pages"
    case actionPageItemCounts = "action_page_counts"
    case checkpointPageIds = "checkpoint_pages"
    case checkpointPageItemCounts = "checkpoint_page_counts"
  }
}

struct AgentSessionHistoryPage<Item> {
  var items: [Item]
  var pageIndex: Int
  var pageCount: Int
  var totalItems: Int
  var available: Bool

  var hasOlderPage: Bool { pageIndex > 0 }
  var hasNewerPage: Bool { pageIndex + 1 < pageCount }
}

final class AgentTaskHistoryPersistence {
  struct Transaction {
    var rootRecords: [AgentTaskRecord]
    fileprivate var prepared: [PreparedHistory]
    fileprivate var createdKeys: [String]
    fileprivate var sourceRecords: [String: AgentTaskRecord]
  }

  fileprivate struct PreparedHistory {
    var taskId: String
    var manifest: AgentSessionHistoryManifest
    var actions: [AgentAction]
    var checkpoints: [AgentExecutionCheckpoint]
    var previousManifest: AgentSessionHistoryManifest?
  }

  private struct EncodedPage {
    var kind: String
    var id: String
    var itemCount: Int
    var data: Data
  }

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private var manifests: [String: AgentSessionHistoryManifest] = [:]
  private var cachedActions: [String: [AgentAction]] = [:]
  private var cachedCheckpoints: [String: [AgentExecutionCheckpoint]] = [:]
  private var cachedSourceRecords: [String: AgentTaskRecord] = [:]
  private var cachedRootRecords: [String: AgentTaskRecord] = [:]

  init(defaults: UserDefaults, secrets: GalaxySSISecretStore) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func restore(_ records: [AgentTaskRecord]) -> [AgentTaskRecord] {
    records.map { record in
      guard let manifest = record.historyManifest, manifest.isValid else { return record }
      manifests[record.taskId] = manifest
      let actions: [AgentAction] = readAll(
        taskId: record.taskId,
        kind: Self.actionKind,
        pageIds: manifest.actionPageIds
      )
      let checkpoints: [AgentExecutionCheckpoint] = readAll(
        taskId: record.taskId,
        kind: Self.checkpointKind,
        pageIds: manifest.checkpointPageIds
      )
      guard var plan = record.activePlan else { return record }
      var restored = record
      let activeIds = Set(plan.actions.map(\.id))
      if !actions.isEmpty {
        plan.actionHistory = actions.filter { $0.id.isEmpty || !activeIds.contains($0.id) }
        cachedActions[record.taskId] = actions
      }
      if !checkpoints.isEmpty {
        plan.checkpoints = checkpoints
        cachedCheckpoints[record.taskId] = checkpoints
      }
      restored.activePlan = plan
      cachedSourceRecords[record.taskId] = restored
      cachedRootRecords[record.taskId] = record
      return restored
    }
  }

  func prepare(records: [AgentTaskRecord]) throws -> Transaction {
    var rootRecords: [AgentTaskRecord] = []
    var prepared: [PreparedHistory] = []
    var createdKeys: [String] = []
    let sourceRecords = Dictionary(records.map { ($0.taskId, $0) }) { _, latest in latest }
    do {
      for record in records {
        if cachedSourceRecords[record.taskId] == record,
           let cachedRoot = cachedRootRecords[record.taskId] {
          rootRecords.append(cachedRoot)
          continue
        }
        guard let plan = record.activePlan else {
          rootRecords.append(record)
          if let manifest = record.historyManifest, manifest.isValid {
            manifests[record.taskId] = manifest
          }
          continue
        }
        let previousManifest = manifests[record.taskId] ?? record.historyManifest
        let previousActions = cachedActions[record.taskId] ?? readActions(
          taskId: record.taskId,
          manifest: previousManifest
        )
        let previousCheckpoints = cachedCheckpoints[record.taskId] ?? readCheckpoints(
          taskId: record.taskId,
          manifest: previousManifest
        )
        let actions = Array(
          Self.latestActions(previousActions + plan.actionHistory + plan.actions)
            .suffix(AgentLongTaskPersistenceLimits.maximumActions)
        )
        let checkpoints = Array(
          Self.latestCheckpoints(previousCheckpoints + plan.checkpoints)
            .suffix(AgentLongTaskPersistenceLimits.maximumCheckpoints)
        )
        let actionPages = try encodePages(kind: Self.actionKind, items: actions)
        let checkpointPages = try encodePages(kind: Self.checkpointKind, items: checkpoints)
        let manifest = AgentSessionHistoryManifest(
          sessionId: record.sessionId,
          actionPageIds: actionPages.map(\.id),
          actionPageItemCounts: actionPages.map(\.itemCount),
          checkpointPageIds: checkpointPages.map(\.id),
          checkpointPageItemCounts: checkpointPages.map(\.itemCount)
        )
        for page in actionPages + checkpointPages {
          let key = pageKey(taskId: record.taskId, kind: page.kind, pageId: page.id)
          if GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets) == nil {
            guard GalaxySSIEncryptedUserDefaultsStore.write(
              page.data,
              defaults: defaults,
              key: key,
              secrets: secrets
            ) else {
              throw AgentHistoryPersistenceError.writeFailed
            }
            createdKeys.append(key)
          }
        }
        var root = record
        root.historyManifest = manifest
        var compactPlan = plan
        compactPlan.actions = Array(plan.actions.prefix(AgentLongTaskPersistenceLimits.rootPlanActions))
        compactPlan.actionHistory = Array(plan.actionHistory.suffix(AgentLongTaskPersistenceLimits.rootActionHistoryItems))
        compactPlan.checkpoints = Array(plan.checkpoints.suffix(AgentLongTaskPersistenceLimits.rootCheckpoints))
        root.activePlan = compactPlan
        rootRecords.append(root)
        prepared.append(
          PreparedHistory(
            taskId: record.taskId,
            manifest: manifest,
            actions: actions,
            checkpoints: checkpoints,
            previousManifest: previousManifest
          )
        )
      }
      return Transaction(
        rootRecords: rootRecords,
        prepared: prepared,
        createdKeys: createdKeys,
        sourceRecords: sourceRecords
      )
    } catch {
      destroy(keys: createdKeys)
      throw error
    }
  }

  func commit(_ transaction: Transaction) {
    let retainedTaskIds = Set(transaction.rootRecords.map(\.taskId))
    cachedSourceRecords = transaction.sourceRecords
    cachedRootRecords = Dictionary(transaction.rootRecords.map { ($0.taskId, $0) }) { _, latest in latest }
    for item in transaction.prepared {
      manifests[item.taskId] = item.manifest
      cachedActions[item.taskId] = item.actions
      cachedCheckpoints[item.taskId] = item.checkpoints
      removeUnreferencedPages(
        taskId: item.taskId,
        previous: item.previousManifest,
        retained: item.manifest
      )
    }
    for taskId in Set(manifests.keys).subtracting(retainedTaskIds) {
      clear(taskId: taskId)
    }
  }

  func rollback(_ transaction: Transaction) {
    destroy(keys: transaction.createdKeys)
  }

  func actionPage(taskId: String, pageIndex: Int) -> AgentSessionHistoryPage<AgentAction> {
    guard let manifest = manifests[taskId], manifest.isValid else {
      return unavailablePage(pageIndex)
    }
    return readPage(
      taskId: taskId,
      kind: Self.actionKind,
      pageIndex: pageIndex,
      pageIds: manifest.actionPageIds,
      pageItemCounts: manifest.actionPageItemCounts
    )
  }

  func checkpointPage(taskId: String, pageIndex: Int) -> AgentSessionHistoryPage<AgentExecutionCheckpoint> {
    guard let manifest = manifests[taskId], manifest.isValid else {
      return unavailablePage(pageIndex)
    }
    return readPage(
      taskId: taskId,
      kind: Self.checkpointKind,
      pageIndex: pageIndex,
      pageIds: manifest.checkpointPageIds,
      pageItemCounts: manifest.checkpointPageItemCounts
    )
  }

  func manifest(taskId: String) -> AgentSessionHistoryManifest? {
    manifests[taskId]
  }

  func clear(taskId: String) {
    if let manifest = manifests.removeValue(forKey: taskId) {
      destroy(keys: pageKeys(taskId: taskId, manifest: manifest))
    }
    cachedActions.removeValue(forKey: taskId)
    cachedCheckpoints.removeValue(forKey: taskId)
    cachedSourceRecords.removeValue(forKey: taskId)
    cachedRootRecords.removeValue(forKey: taskId)
  }

  func clear() {
    for (taskId, manifest) in manifests {
      destroy(keys: pageKeys(taskId: taskId, manifest: manifest))
    }
    manifests.removeAll()
    cachedActions.removeAll()
    cachedCheckpoints.removeAll()
    cachedSourceRecords.removeAll()
    cachedRootRecords.removeAll()
  }

  private func readActions(
    taskId: String,
    manifest: AgentSessionHistoryManifest?
  ) -> [AgentAction] {
    guard let manifest, manifest.isValid else { return [] }
    return readAll(taskId: taskId, kind: Self.actionKind, pageIds: manifest.actionPageIds)
  }

  private func readCheckpoints(
    taskId: String,
    manifest: AgentSessionHistoryManifest?
  ) -> [AgentExecutionCheckpoint] {
    guard let manifest, manifest.isValid else { return [] }
    return readAll(taskId: taskId, kind: Self.checkpointKind, pageIds: manifest.checkpointPageIds)
  }

  private func encodePages<Item: Encodable>(kind: String, items: [Item]) throws -> [EncodedPage] {
    var pages: [EncodedPage] = []
    var current: [Any] = []
    func flush() throws {
      guard !current.isEmpty else { return }
      let data = try pageData(kind: kind, items: current)
      pages.append(
        EncodedPage(kind: kind, id: Self.sha256(data), itemCount: current.count, data: data)
      )
      current.removeAll(keepingCapacity: true)
    }
    for item in items {
      let object = try boundedJSONObject(item)
      let candidate = current + [object]
      let candidateData = try pageData(kind: kind, items: candidate)
      if !current.isEmpty && (
        current.count >= AgentLongTaskPersistenceLimits.maximumPageItems ||
          Self.characterCount(candidateData) > AgentLongTaskPersistenceLimits.maximumPageJSONCharacters
      ) {
        try flush()
      }
      current.append(object)
      let data = try pageData(kind: kind, items: current)
      guard Self.characterCount(data) <= AgentLongTaskPersistenceLimits.maximumPageJSONCharacters else {
        throw AgentHistoryPersistenceError.itemTooLarge
      }
    }
    try flush()
    return pages
  }

  private func boundedJSONObject<Item: Encodable>(_ item: Item) throws -> Any {
    let encoded = try Self.encoder().encode(item)
    let object = try JSONSerialization.jsonObject(with: encoded)
    if try Self.singleItemPageCharacters(object) <= AgentLongTaskPersistenceLimits.maximumPageJSONCharacters {
      return object
    }
    for limit in [1_024, 512, 256, 128, 64] {
      let compact = Self.compact(object, stringLimit: limit)
      if try Self.singleItemPageCharacters(compact) <= AgentLongTaskPersistenceLimits.maximumPageJSONCharacters {
        return compact
      }
    }
    throw AgentHistoryPersistenceError.itemTooLarge
  }

  private func pageData(kind: String, items: [Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: ["items": items, "kind": kind, "version": 1],
      options: [.sortedKeys]
    )
  }

  private func readPage<Item: Decodable>(
    taskId: String,
    kind: String,
    pageIndex: Int,
    pageIds: [String],
    pageItemCounts: [Int]
  ) -> AgentSessionHistoryPage<Item> {
    let pageCount = pageIds.count
    let totalItems = pageItemCounts.reduce(0, +)
    guard pageIds.indices.contains(pageIndex) else {
      return AgentSessionHistoryPage(
        items: [],
        pageIndex: pageIndex,
        pageCount: pageCount,
        totalItems: totalItems,
        available: false
      )
    }
    let items: [Item]? = decodePage(
      taskId: taskId,
      kind: kind,
      pageId: pageIds[pageIndex]
    )
    let available = items?.count == pageItemCounts[pageIndex]
    return AgentSessionHistoryPage(
      items: items ?? [],
      pageIndex: pageIndex,
      pageCount: pageCount,
      totalItems: totalItems,
      available: available
    )
  }

  private func readAll<Item: Decodable>(
    taskId: String,
    kind: String,
    pageIds: [String]
  ) -> [Item] {
    pageIds.flatMap { pageId -> [Item] in
      decodePage(taskId: taskId, kind: kind, pageId: pageId) ?? []
    }
  }

  private func decodePage<Item: Decodable>(
    taskId: String,
    kind: String,
    pageId: String
  ) -> [Item]? {
    let key = pageKey(taskId: taskId, kind: kind, pageId: pageId)
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: key,
      secrets: secrets
    ), Self.sha256(data) == pageId,
      let rawObject = try? JSONSerialization.jsonObject(with: data),
      let object = rawObject as? [String: Any],
      (object["version"] as? NSNumber)?.intValue == 1,
      object["kind"] as? String == kind,
      let items = object["items"] as? [Any] else {
      return nil
    }
    return items.compactMap { item in
      guard JSONSerialization.isValidJSONObject(item),
            let data = try? JSONSerialization.data(withJSONObject: item),
            let value = try? Self.decoder().decode(Item.self, from: data) else {
        return nil
      }
      return value
    }
  }

  private func removeUnreferencedPages(
    taskId: String,
    previous: AgentSessionHistoryManifest?,
    retained: AgentSessionHistoryManifest
  ) {
    guard let previous else { return }
    let retainedKeys = Set(pageKeys(taskId: taskId, manifest: retained))
    destroy(keys: pageKeys(taskId: taskId, manifest: previous).filter { !retainedKeys.contains($0) })
  }

  private func pageKeys(taskId: String, manifest: AgentSessionHistoryManifest) -> [String] {
    manifest.actionPageIds.map { pageKey(taskId: taskId, kind: Self.actionKind, pageId: $0) } +
      manifest.checkpointPageIds.map { pageKey(taskId: taskId, kind: Self.checkpointKind, pageId: $0) }
  }

  private func pageKey(taskId: String, kind: String, pageId: String) -> String {
    "galaxyssi.agent_task_history.\(Self.sha256(Data(taskId.utf8))).\(kind).\(pageId)"
  }

  private func destroy(keys: [String]) {
    for key in Set(keys) {
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    }
  }

  private func unavailablePage<Item>(_ pageIndex: Int) -> AgentSessionHistoryPage<Item> {
    AgentSessionHistoryPage(
      items: [],
      pageIndex: pageIndex,
      pageCount: 0,
      totalItems: 0,
      available: false
    )
  }

  private static func latestActions(_ actions: [AgentAction]) -> [AgentAction] {
    guard actions.count > 1 else { return actions }
    var seen: Set<String> = []
    var retained: [AgentAction] = []
    for action in actions.reversed() where action.id.isEmpty || seen.insert(action.id).inserted {
      retained.append(action)
    }
    return Array(retained.reversed())
  }

  private static func latestCheckpoints(_ checkpoints: [AgentExecutionCheckpoint]) -> [AgentExecutionCheckpoint] {
    guard checkpoints.count > 1 else { return checkpoints }
    var seen: Set<String> = []
    var retained: [AgentExecutionCheckpoint] = []
    for checkpoint in checkpoints.reversed() where checkpoint.id.isEmpty || seen.insert(checkpoint.id).inserted {
      retained.append(checkpoint)
    }
    return Array(retained.reversed())
  }

  private static func singleItemPageCharacters(_ item: Any) throws -> Int {
    let data = try JSONSerialization.data(
      withJSONObject: ["items": [item], "kind": "item", "version": 1],
      options: [.sortedKeys]
    )
    return characterCount(data)
  }

  private static func compact(_ value: Any, stringLimit: Int) -> Any {
    if let string = value as? String {
      return String(string.prefix(stringLimit))
    }
    if let values = value as? [Any] {
      return values.map { compact($0, stringLimit: stringLimit) }
    }
    if let values = value as? [String: Any] {
      return values.mapValues { compact($0, stringLimit: stringLimit) }
    }
    return value
  }

  private static func characterCount(_ data: Data) -> Int {
    String(data: data, encoding: .utf8)?.count ?? Int.max
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    JSONDecoder()
  }

  private static let actionKind = "actions"
  private static let checkpointKind = "checkpoints"
}

private enum AgentHistoryPersistenceError: Error {
  case itemTooLarge
  case writeFailed
}

enum AgentCheckpointStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case restored = "RESTORED"
  case invalidated = "INVALIDATED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentCheckpointStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .active
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

struct AgentExecutionCheckpoint: Codable, Equatable {
  var id: String
  var actionId: String
  var planRevision: Int
  var foregroundApp: String
  var activityName: String
  var pageTitle: String
  var screenDigest: String
  var rollbackAction: AgentAction?
  var status: AgentCheckpointStatus
  var createdAtMillis: Int64
  var summary: String
  var timestampMillis: Int64

  init(
    id: String = UUID().uuidString,
    actionId: String,
    planRevision: Int = 0,
    foregroundApp: String = "",
    activityName: String = "",
    pageTitle: String = "",
    screenDigest: String = "",
    rollbackAction: AgentAction? = nil,
    status: AgentCheckpointStatus = .active,
    createdAtMillis: Int64 = 0,
    summary: String = "",
    timestampMillis: Int64? = nil
  ) {
    self.id = id
    self.actionId = actionId
    self.planRevision = planRevision
    self.foregroundApp = foregroundApp
    self.activityName = activityName
    self.pageTitle = pageTitle
    self.screenDigest = screenDigest
    self.rollbackAction = rollbackAction
    self.status = status
    self.createdAtMillis = max(createdAtMillis, 0)
    self.summary = summary
    self.timestampMillis = max(timestampMillis ?? createdAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case actionId = "action_id"
    case planRevision = "plan_revision"
    case foregroundApp = "foreground_app"
    case activityName = "activity_name"
    case pageTitle = "page_title"
    case screenDigest = "screen_digest"
    case rollbackAction = "rollback_action"
    case status
    case createdAtMillis = "created_at_millis"
    case summary
    case timestampMillis = "timestamp_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let actionId = try container.decodeIfPresent(String.self, forKey: .actionId) ?? ""
    let createdAtMillis = try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ??
        Self.fallbackId(actionId: actionId, createdAtMillis: createdAtMillis),
      actionId: actionId,
      planRevision: try container.decodeIfPresent(Int.self, forKey: .planRevision) ?? 0,
      foregroundApp: try container.decodeIfPresent(String.self, forKey: .foregroundApp) ?? "",
      activityName: try container.decodeIfPresent(String.self, forKey: .activityName) ?? "",
      pageTitle: try container.decodeIfPresent(String.self, forKey: .pageTitle) ?? "",
      screenDigest: try container.decodeIfPresent(String.self, forKey: .screenDigest) ?? "",
      rollbackAction: try container.decodeIfPresent(AgentAction.self, forKey: .rollbackAction),
      status: try container.decodeIfPresent(AgentCheckpointStatus.self, forKey: .status) ?? .active,
      createdAtMillis: createdAtMillis,
      summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      timestampMillis: try container.decodeIfPresent(Int64.self, forKey: .timestampMillis)
    )
  }

  private static func fallbackId(actionId: String, createdAtMillis: Int64) -> String {
    let suffix = actionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : actionId
    return "checkpoint-\(suffix)-\(max(createdAtMillis, 0))"
  }
}

enum AgentExecutionContinuity {
  static func checkpointBefore(
    action: AgentAction,
    screen: AgentScreenContext,
    planRevision: Int,
    id: String = UUID().uuidString,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentExecutionCheckpoint {
    AgentExecutionCheckpoint(
      id: id,
      actionId: action.id,
      planRevision: planRevision,
      foregroundApp: screen.foregroundApp,
      activityName: screen.activityName,
      pageTitle: screen.pageTitle,
      screenDigest: screenDigest(screen),
      rollbackAction: rollbackAction(for: action),
      status: .active,
      createdAtMillis: nowMillis
    )
  }

  static func screenDigest(_ screen: AgentScreenContext) -> String {
    let notifications = screen.notifications.items.prefix(6).map { item in
      [item.key, item.packageName, item.title, String(item.postedAtMillis), item.sensitiveFlags.joined(separator: ",")]
        .joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let clickableElements = screen.clickableElements.prefix(12).map { item in
      [item.viewId, item.label].joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let inputFields = screen.inputFields.prefix(8).map { item in
      [item.viewId, item.label].joined(separator: "\u{001f}")
    }.joined(separator: "\u{001d}")
    let payload: [String] = [
      screen.foregroundApp,
      screen.activityName,
      screen.pageTitle,
      screen.visibleTexts.prefix(40).joined(separator: "\u{001f}"),
      String(screen.clickableNodeCount),
      String(screen.inputFieldCount),
      String(screen.notifications.totalCount),
      notifications,
      screen.clipboard.textHash,
      String(screen.clipboard.textLength),
      screen.clipboard.sensitiveFlags.joined(separator: ","),
      screen.sensitiveFlags.joined(separator: ","),
      clickableElements,
      inputFields,
      screen.scrollableRegions.prefix(6).map(\.viewId).joined(separator: "\u{001d}"),
      String(screen.deviceStatus.batteryPercent),
      String(screen.deviceStatus.charging),
      String(screen.deviceStatus.powerSaveMode),
      screen.deviceStatus.network,
      String(screen.deviceStatus.freeStorageMb),
      screen.deviceStatus.thermalState
    ]
    return String(javaStringHash(payload.joined(separator: "\u{001e}")))
  }

  private static func rollbackAction(for action: AgentAction) -> AgentAction? {
    switch action.kind {
    case .openApp, .openURL, .recents:
      return AgentAction(
        id: "rollback-\(action.id)",
        kind: .back,
        target: action.target,
        risk: .low,
        status: .pendingConfirmation,
        description: "Return to the screen before \(action.description)",
        requiresConfirmation: true
      )
    case .swipe:
      return reverseSwipe(action)
    default:
      return nil
    }
  }

  private static func reverseSwipe(_ action: AgentAction) -> AgentAction? {
    guard let fromX = action.parameters["from_x"],
          let fromY = action.parameters["from_y"],
          let toX = action.parameters["to_x"],
          let toY = action.parameters["to_y"] else {
      return nil
    }
    return AgentAction(
      id: "rollback-\(action.id)",
      kind: .swipe,
      target: action.target,
      risk: .low,
      status: .pendingConfirmation,
      description: "Reverse the previous swipe",
      parameters: [
        "from_x": toX,
        "from_y": toY,
        "to_x": fromX,
        "to_y": fromY
      ],
      requiresConfirmation: true
    )
  }

  private static func javaStringHash(_ value: String) -> Int32 {
    var hash: Int32 = 0
    for codeUnit in value.utf16 {
      hash = hash &* 31 &+ Int32(codeUnit)
    }
    return hash
  }
}

extension AgentPlan {
  func addCheckpoint(_ checkpoint: AgentExecutionCheckpoint) -> AgentPlan {
    var copy = self
    copy.checkpoints = Array(
      (copy.checkpoints + [checkpoint]).suffix(AgentLongTaskPersistenceLimits.maximumCheckpoints)
    )
    return copy
  }

  func markCheckpoint(_ checkpointId: String, status: AgentCheckpointStatus) -> AgentPlan {
    var copy = self
    copy.checkpoints = copy.checkpoints.map { checkpoint in
      guard checkpoint.id == checkpointId else {
        return checkpoint
      }
      var marked = checkpoint
      marked.status = status
      return marked
    }
    return copy
  }

  func recoverInterruptedExecution() -> AgentPlan {
    var copy = self
    copy.actions = copy.actions.map { action in
      guard action.status == .running else {
        return action
      }
      var interrupted = action
      interrupted.status = .pendingConfirmation
      interrupted.result = "Execution was interrupted before verification"
      interrupted.evidence = "interrupted"
      return interrupted
    }
    return copy
  }

  func historyForReplan() -> [AgentAction] {
    let terminalStatuses: [AgentActionStatus] = [.completed, .failed, .blocked, .rolledBack]
    return Array((actionHistory + actions.filter { terminalStatuses.contains($0.status) }).suffix(40))
  }
}

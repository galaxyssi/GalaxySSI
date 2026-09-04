import Foundation

struct GlobalMemoryEvolutionArchive: Codable, Equatable {
  var inbox: GlobalMemoryInbox
  var audit: GlobalMemoryAuditReport
  var records: [GlobalMemoryEvolutionRecord]

  enum CodingKeys: String, CodingKey {
    case inbox
    case audit
    case records
  }

  init(
    inbox: GlobalMemoryInbox = GlobalMemoryInbox(),
    audit: GlobalMemoryAuditReport = GlobalMemoryAuditReport(),
    records: [GlobalMemoryEvolutionRecord] = []
  ) {
    self.inbox = GlobalMemoryEvolutionCodec.bounded(inbox)
    self.audit = GlobalMemoryEvolutionCodec.bounded(audit)
    self.records = GlobalMemoryEvolutionCodec.bounded(records)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      inbox: try container.decodeIfPresent(GlobalMemoryInbox.self, forKey: .inbox) ?? GlobalMemoryInbox(),
      audit: try container.decodeIfPresent(GlobalMemoryAuditReport.self, forKey: .audit) ?? GlobalMemoryAuditReport(),
      records: try container.decodeIfPresent([GlobalMemoryEvolutionRecord].self, forKey: .records) ?? []
    )
  }
}

enum GlobalMemoryEvolutionCodec {
  static func encodeInbox(_ inbox: GlobalMemoryInbox) -> String {
    encode(bounded(inbox), fallback: #"{"candidates":[],"processed_event_ids":[],"updated_at_millis":0}"#)
  }

  static func decodeInbox(_ raw: String) -> GlobalMemoryInbox {
    guard let decoded = decode(GlobalMemoryInbox.self, raw: raw) else {
      return GlobalMemoryInbox()
    }
    return bounded(decoded)
  }

  static func encodeAudit(_ report: GlobalMemoryAuditReport) -> String {
    encode(bounded(report), fallback: #"{"findings":[],"themes":[],"audited_item_count":0,"created_at_millis":0}"#)
  }

  static func decodeAudit(_ raw: String) -> GlobalMemoryAuditReport {
    guard let decoded = decode(GlobalMemoryAuditReport.self, raw: raw) else {
      return GlobalMemoryAuditReport()
    }
    return bounded(decoded)
  }

  static func encodeRecords(_ records: [GlobalMemoryEvolutionRecord]) -> String {
    encode(bounded(records), fallback: "[]")
  }

  static func decodeRecords(_ raw: String) -> [GlobalMemoryEvolutionRecord] {
    guard let decoded = decode([GlobalMemoryEvolutionRecord].self, raw: raw) else {
      return []
    }
    return bounded(decoded)
  }

  static func encodeArchive(_ archive: GlobalMemoryEvolutionArchive) -> String {
    encode(GlobalMemoryEvolutionArchive(
      inbox: archive.inbox,
      audit: archive.audit,
      records: archive.records
    ), fallback: #"{"inbox":{"candidates":[]},"audit":{"findings":[]},"records":[]}"#)
  }

  static func decodeArchive(_ raw: String) -> GlobalMemoryEvolutionArchive {
    guard let decoded = decode(GlobalMemoryEvolutionArchive.self, raw: raw) else {
      return GlobalMemoryEvolutionArchive()
    }
    return GlobalMemoryEvolutionArchive(
      inbox: decoded.inbox,
      audit: decoded.audit,
      records: decoded.records
    )
  }

  static func bounded(_ inbox: GlobalMemoryInbox) -> GlobalMemoryInbox {
    GlobalMemoryInbox(
      candidates: Array(inbox.candidates.prefix(maxInboxCandidates)),
      processedEventIds: Array(GlobalMemoryEvolutionPolicy.uniqueStrings(inbox.processedEventIds).suffix(maxProcessedEventIds)),
      updatedAtMillis: inbox.updatedAtMillis
    )
  }

  static func bounded(_ report: GlobalMemoryAuditReport) -> GlobalMemoryAuditReport {
    GlobalMemoryAuditReport(
      findings: Array(report.findings.prefix(maxAuditFindings)),
      themes: Array(report.themes.prefix(maxAuditThemes)),
      auditedItemCount: report.auditedItemCount,
      createdAtMillis: report.createdAtMillis
    )
  }

  static func bounded(_ records: [GlobalMemoryEvolutionRecord]) -> [GlobalMemoryEvolutionRecord] {
    Array(records.suffix(maxEvolutionRecords))
  }

  private static func encode<T: Encodable>(_ value: T, fallback: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else {
      return fallback
    }
    return String(decoding: data, as: UTF8.self)
  }

  private static func decode<T: Decodable>(_ type: T.Type, raw: String) -> T? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return nil }
    return try? JSONDecoder().decode(type, from: Data(clean.utf8))
  }

  static let maxInboxCandidates = 1_000
  static let maxProcessedEventIds = 4_000
  static let maxEvolutionRecords = 2_000
  static let maxAuditFindings = 200
  static let maxAuditThemes = 80
}

final class GlobalMemoryEvolutionStore {
  private let defaults: UserDefaults
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func inbox() -> GlobalMemoryInbox {
    locked {
      GlobalMemoryEvolutionCodec.decodeInbox(defaults.string(forKey: Keys.inbox) ?? "")
    }
  }

  func saveInbox(_ inbox: GlobalMemoryInbox) {
    locked {
      defaults.set(GlobalMemoryEvolutionCodec.encodeInbox(inbox), forKey: Keys.inbox)
    }
  }

  func auditReport() -> GlobalMemoryAuditReport {
    locked {
      GlobalMemoryEvolutionCodec.decodeAudit(defaults.string(forKey: Keys.audit) ?? "")
    }
  }

  func saveAudit(_ report: GlobalMemoryAuditReport) {
    locked {
      defaults.set(GlobalMemoryEvolutionCodec.encodeAudit(report), forKey: Keys.audit)
    }
  }

  func evolutionRecords() -> [GlobalMemoryEvolutionRecord] {
    locked {
      GlobalMemoryEvolutionCodec.decodeRecords(defaults.string(forKey: Keys.records) ?? "")
    }
  }

  func appendEvolutionRecords(_ records: [GlobalMemoryEvolutionRecord]) {
    if records.isEmpty { return }
    locked {
      let incomingIds = Set(records.map(\.id))
      let merged = (GlobalMemoryEvolutionCodec.decodeRecords(defaults.string(forKey: Keys.records) ?? "")
        .filter { !incomingIds.contains($0.id) } + records)
        .sorted { $0.createdAtMillis < $1.createdAtMillis }
      defaults.set(GlobalMemoryEvolutionCodec.encodeRecords(merged), forKey: Keys.records)
    }
  }

  func exportArchive() -> GlobalMemoryEvolutionArchive {
    locked {
      GlobalMemoryEvolutionArchive(
        inbox: GlobalMemoryEvolutionCodec.decodeInbox(defaults.string(forKey: Keys.inbox) ?? ""),
        audit: GlobalMemoryEvolutionCodec.decodeAudit(defaults.string(forKey: Keys.audit) ?? ""),
        records: GlobalMemoryEvolutionCodec.decodeRecords(defaults.string(forKey: Keys.records) ?? "")
      )
    }
  }

  func export() -> String {
    GlobalMemoryEvolutionCodec.encodeArchive(exportArchive())
  }

  func restore(_ archive: GlobalMemoryEvolutionArchive) {
    locked {
      defaults.set(GlobalMemoryEvolutionCodec.encodeInbox(archive.inbox), forKey: Keys.inbox)
      defaults.set(GlobalMemoryEvolutionCodec.encodeAudit(archive.audit), forKey: Keys.audit)
      defaults.set(GlobalMemoryEvolutionCodec.encodeRecords(archive.records), forKey: Keys.records)
    }
  }

  func restore(_ rawArchive: String) {
    restore(GlobalMemoryEvolutionCodec.decodeArchive(rawArchive))
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: Keys.inbox)
      defaults.removeObject(forKey: Keys.audit)
      defaults.removeObject(forKey: Keys.records)
    }
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }

  private enum Keys {
    static let inbox = "memory_evolution_inbox"
    static let audit = "memory_evolution_audit"
    static let records = "memory_evolution_records"
  }
}

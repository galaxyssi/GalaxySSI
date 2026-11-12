import Foundation

enum GalaxySSIHealthCareAgenda {
  static let pageSize = 30
  static let version = 2

  enum Filter: String, CaseIterable { case today, later, review, recorded }
  enum Bucket: Int, Codable { case planned, review, recorded }

  struct Scope: Equatable {
    let concern: UUID
    let metric: GalaxySSIHealthMetric
  }

  struct Context: Codable, Equatable {
    let assessmentCurrent: Bool
    let profileCurrent: Bool
  }

  struct Key: Codable, Equatable, Comparable {
    let bucket: Bucket
    let due: Date?
    let concern: UUID
    let action: String

    private var order: (Int, Double, String, String) {
      (bucket.rawValue, due?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude, concern.uuidString, action)
    }

    static func < (lhs: Key, rhs: Key) -> Bool { lhs.order < rhs.order }
  }

  struct Row: Codable, Equatable {
    let key: Key
    let metric: GalaxySSIHealthMetric
    let revision: Int
    let reminderID: UUID?
    let submittedFor: Date?
    let canRecord: Bool
    var journalVisit: UUID? = nil

    func matches(_ filter: Filter, dayEnd: Date) -> Bool {
      switch filter {
      case .today: return key.bucket == .planned && key.due.map { $0 < dayEnd } == true
      case .later: return key.bucket == .planned && key.due.map { $0 >= dayEnd } != false
      case .review: return key.bucket == .review
      case .recorded: return key.bucket == .recorded
      }
    }
  }

  struct Projection: Codable, Equatable {
    let version: Int
    let carePermission: UUID?
    let onlinePermission: UUID?
    let context: [String: Context]
    let rows: [Row]
    private let byConcern: [String: [Row]]
    let generation: String

    init(carePermission: UUID?, onlinePermission: UUID?, context: [String: Context], rows: [Row]) {
      version = GalaxySSIHealthCareAgenda.version
      self.carePermission = carePermission
      self.onlinePermission = onlinePermission
      self.context = context
      let sorted = rows.sorted { $0.key < $1.key }
      self.rows = sorted
      byConcern = Dictionary(grouping: sorted) { $0.key.concern.uuidString }
      generation = AgentModelLoopRecoveryIdentity.sha256(Basis(care: carePermission, online: onlinePermission,
        context: context, rows: sorted))
    }

    private struct Basis: Encodable {
      let care: UUID?
      let online: UUID?
      let context: [String: Context]
      let rows: [Row]
    }

    func page(filter: Filter?, scope: Scope?, dayEnd: Date, after: Cursor?, limit: Int) throws -> [Row] {
      guard (1...GalaxySSIHealthCareAgenda.pageSize).contains(limit), filter != nil || scope != nil
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      let rows = scope.map { byConcern[$0.concern.uuidString] ?? [] } ?? self.rows
      let start: Int
      if let after {
        guard after.generation == generation, after.filter == filter, after.scope == scope, after.dayEnd == dayEnd
        else { throw GalaxySSIHealthRecords.Failure.stale }
        let position = lowerBound(rows) { $0.key >= after.key }
        guard position < rows.count, rows[position].key == after.key,
              filter.map({ rows[position].matches($0, dayEnd: dayEnd) }) != false,
              scope.map({ rows[position].key.concern == $0.concern && rows[position].metric == $0.metric }) != false
        else { throw GalaxySSIHealthRecords.Failure.stale }
        start = position + 1
      } else {
        switch filter {
        case .later:
          start = lowerBound(rows) { $0.key.bucket != .planned || $0.key.due.map { $0 >= dayEnd } != false }
        case .review:
          start = lowerBound(rows) { $0.key.bucket.rawValue >= Bucket.review.rawValue }
        case .recorded:
          start = lowerBound(rows) { $0.key.bucket == .recorded }
        case .today, nil: start = 0
        }
      }
      var result: [Row] = []
      for row in rows[start...] {
        if let filter, !row.matches(filter, dayEnd: dayEnd) { break }
        if let scope, row.metric != scope.metric { throw GalaxySSIHealthRecords.Failure.stale }
        result.append(row)
        if result.count > limit { break }
      }
      return result
    }

    private func lowerBound(_ rows: [Row], _ predicate: (Row) -> Bool) -> Int {
      var low = 0, high = rows.count
      while low < high {
        let midpoint = low + (high - low) / 2
        if predicate(rows[midpoint]) { high = midpoint } else { low = midpoint + 1 }
      }
      return low
    }
  }

  struct Cursor: Equatable {
    let generation: String
    let filter: Filter?
    let scope: Scope?
    let dayEnd: Date
    let key: Key
  }

  struct Item: Identifiable {
    let scope: Scope
    let revision: Int
    let action: GalaxySSIHealthCarePlan.AdoptedAction?
    let reminder: GalaxySSIHealthCareFollowUp.Reminder?
    let plannedAt: Date?
    let bucket: Bucket
    let canRecord: Bool

    var id: String { "\(scope.concern.uuidString):\(action?.id ?? reminder?.actionID ?? "")" }
  }

  struct Page {
    let items: [Item]
    let next: Cursor?
    let dayEnd: Date
    let remindersEnabled: Bool
  }
}

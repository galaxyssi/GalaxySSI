import EventKit
import Foundation

struct VoiceReminderSnapshot: Codable, Equatable, Sendable {
  struct TaskRow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let conversationID: String
    let title: String
    let phase: String
  }

  struct CalendarRow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
  }

  let tasks: [TaskRow]
  // A missing source is distinct from an available source with no entries.
  let calendar: [CalendarRow]?
  let unreadNewsCount: Int?

  static func taskRows(_ records: [AgentTaskRecord], limit: Int = 5) -> [TaskRow] {
    Array(records.lazy.filter {
      [.waitingConfirmation, .paused, .blocked].contains($0.phase) &&
        !$0.taskId.isEmpty && AgentTaskCenterPolicy.isReusableGoal($0.goal)
    }.prefix(max(0, limit)).map {
      TaskRow(id: $0.taskId, conversationID: $0.sessionId, title: String($0.goal.prefix(240)),
              phase: $0.phase.rawValue)
    })
  }

  static func calendarRows(now: Date = Date()) -> [CalendarRow]? {
    let authorization = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      guard authorization == .fullAccess else { return nil }
    } else {
      guard authorization == .authorized else { return nil }
    }
    let store = EKEventStore()
    guard let end = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return nil }
    let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
    return store.events(matching: predicate).compactMap { event -> CalendarRow? in
      guard let identifier = event.eventIdentifier, let start = event.startDate,
            start >= now, start < end else { return nil }
      return CalendarRow(id: identifier, title: String((event.title ?? "").prefix(240)), start: start)
    }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.prefix(5).map { $0 }
  }
}

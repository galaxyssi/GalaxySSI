import CryptoKit
import Foundation

enum GalaxySSIHealthRecordingReminders {
  static let changed = Notification.Name("galaxyssi.health.recordingRemindersChanged")
  static let prefix = "galaxyssi.health.recording."

  enum Category: String, Codable, CaseIterable, Identifiable {
    case bloodPressure, glucose, weight, sleep
    var id: String { rawValue }
    var metric: GalaxySSIHealthMetric {
      switch self {
      case .bloodPressure: return .bloodPressure
      case .glucose: return .glucose
      case .weight: return .weight
      case .sleep: return .sleepDuration
      }
    }
  }

  struct Settings: Codable, Equatable {
    var version = UUID()
    var enabled = false
    var effectiveAt: Date?
    var category = Category.bloodPressure
    var hour = 9
    var minute = 0
    var quietStart = 22
    var quietEnd = 8
    var notifications = false
    var pausedUntil: Date?

    var isValid: Bool {
      (0..<24).contains(hour) && (0..<60).contains(minute) &&
        (0..<24).contains(quietStart) && (0..<24).contains(quietEnd)
    }

    func quietEndAfter(_ date: Date, calendar: Calendar) -> Date {
      let hour = calendar.component(.hour, from: date)
      guard quietStart != quietEnd else { return date }
      let quiet = quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
      guard quiet else { return date }
      return calendar.nextDate(after: date, matching: DateComponents(hour: quietEnd, minute: 0),
                               matchingPolicy: .nextTime) ?? date
    }

    func nextDelivery(_ date: Date, calendar: Calendar) -> Date {
      quietEndAfter(max(date, pausedUntil ?? .distantPast), calendar: calendar)
    }
  }

  static func sharedDelivery(_ date: Date, settings: Settings?, calendar: Calendar,
                             local: (Date) -> Date) -> Date? {
    var next = date
    // A pair of quiet windows can cover the entire day.
    for _ in 0..<8 {
      let candidate = local(settings?.nextDelivery(next, calendar: calendar) ?? next)
      if candidate == next { return next }
      guard candidate > next else { return nil }
      next = candidate
    }
    return nil
  }

  static func calendarTriggerDate(_ due: Date) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var date = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due.roundedUpToSecond)
    date.calendar = calendar
    date.timeZone = calendar.timeZone
    return date
  }

  struct Occurrence: Codable, Equatable, Identifiable {
    var id: String { day }
    let day: String
    let scheduledAt: Date
    let zone: String
    let category: Category
    var version = UUID()
    var completedAt: Date?
    var snoozedUntil: Date?
    var disabled = false
  }

  struct Ledger: Codable, Equatable {
    var settings = Settings()
    var history: [Occurrence] = []

    mutating func reconcile(at now: Date, calendar: Calendar) {
      let day = calendar.startOfDay(for: now)
      guard settings.enabled, let effectiveAt = settings.effectiveAt,
            let due = Self.due(on: day, settings: settings, calendar: calendar),
            due >= effectiveAt, due <= now, due >= (settings.pausedUntil ?? .distantPast),
            !history.contains(where: { $0.day == Self.key(day, calendar: calendar) }) else { return }
      history.insert(.init(day: Self.key(day, calendar: calendar), scheduledAt: due,
                           zone: calendar.timeZone.identifier, category: settings.category), at: 0)
      history = Array(history.prefix(365))
    }

    func upcoming(at now: Date, calendar: Calendar) -> [(String, Date)] {
      guard settings.enabled, settings.notifications, let effectiveAt = settings.effectiveAt else { return [] }
      let today = calendar.startOfDay(for: now)
      return (0..<7).compactMap { offset in
        guard let day = calendar.date(byAdding: .day, value: offset, to: today),
              let due = Self.due(on: day, settings: settings, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let key = Self.key(day, calendar: calendar)
        let item = history.first { $0.day == key }
        if let item, item.completedAt != nil || item.disabled { return nil }
        let target = item?.snoozedUntil ?? item?.scheduledAt ?? due
        guard target >= effectiveAt, target >= (settings.pausedUntil ?? .distantPast) else { return nil }
        let allowed = settings.nextDelivery(target, calendar: calendar)
        guard allowed > now, allowed < end else { return nil }
        return (key, allowed)
      }
    }

    func keepsDelivered(at now: Date, calendar: Calendar) -> Set<String> {
      guard settings.enabled, settings.notifications, settings.nextDelivery(now, calendar: calendar) == now
      else { return [] }
      let today = Self.key(now, calendar: calendar)
      return Set(history.filter {
        $0.day == today && !$0.disabled && $0.completedAt == nil &&
          max($0.scheduledAt, $0.snoozedUntil ?? .distantPast) <= now
      }.map(\.day))
    }

    private static func due(on day: Date, settings: Settings, calendar: Calendar) -> Date? {
      calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    static func key(_ day: Date, calendar: Calendar) -> String {
      let value = calendar.dateComponents([.year, .month, .day], from: day)
      return String(format: "%04d-%02d-%02d", value.year ?? 0, value.month ?? 0, value.day ?? 0)
    }
  }

  static func notificationID(owner: String, day: String) -> String {
    prefix + SHA256.hash(data: Data((owner + ":" + day).utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
}

private extension Date {
  var roundedUpToSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.up)) }
}

import Foundation

enum GalaxySSIHealthMeasurementPeriodText {
  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.period." + key, fallback: fallback, language: language)
  }
  static func label(_ period: GalaxySSIHealthMeasurementPeriod, zone: TimeZone, locale: Locale) -> String {
    guard let start = try? period.firstDate(zone: zone), let interval = try? period.interval(zone: zone) else { return period.first }
    let formatter = DateFormatter()
    formatter.locale = locale; formatter.timeZone = zone; formatter.calendar = GalaxySSIHealthMeasurementPeriod.calendar(zone)
    if period.kind == .month {
      let parts = formatter.calendar.dateComponents([.year, .month], from: start)
      return String(format: "%04d/%02d", parts.year ?? 0, parts.month ?? 0)
    }
    formatter.dateStyle = .short
    let end = formatter.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    return formatter.string(from: start) + " \u{2013} " + formatter.string(from: end)
  }
  static func condition(_ condition: String, language: String) -> String {
    if GalaxySSIHealthReportBatch.conditions.contains(condition) {
      return GalaxySSIHealthReportBatch.conditionTitle(condition, language: language)
    }
    switch condition {
    case "", "unspecified": return text("condition_unknown", "Condition not specified", language)
    case "resting": return text("condition_resting", "Resting", language)
    case "after_exercise": return text("condition_after_exercise", "After exercise", language)
    default: return condition
    }
  }
  static func failure(_ failure: GalaxySSIHealthMeasurementQuery.Failure, language: String) -> String {
    switch failure {
    case .permission: return text("permission", "Enable local measurement summaries in Health Privacy.", language)
    case .changed: return text("changed", "Measurements changed. Reload to view current results.", language)
    case .unavailable: return text("unavailable", "Health measurements could not be accessed.", language)
    }
  }
}

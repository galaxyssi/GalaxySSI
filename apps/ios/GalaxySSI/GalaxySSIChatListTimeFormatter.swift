import Foundation

enum GalaxySSIChatListTimeFormatter {
  static func string(for date: Date, language: String, now: Date = Date()) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let formatter = DateFormatter()
    formatter.locale = GalaxySSILocalization.dateLocale(language: language)
    formatter.timeZone = calendar.timeZone
    if calendar.isDate(date, inSameDayAs: now) {
      formatter.dateStyle = .none
      formatter.timeStyle = .short
    } else {
      formatter.dateFormat = "MM/dd"
    }
    return formatter.string(from: date)
  }
}

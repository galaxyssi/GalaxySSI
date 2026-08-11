import Foundation
import SwiftUI

struct SignalASIConversationDateDivider: View {
  var date: Date
  var language: String

  var body: some View {
    Text(label)
      .font(.system(size: 11))
      .foregroundColor(.signalASITextSecondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
      .accessibilityLabel(Text(label))
  }

  static func shouldShow(for date: Date, previous: Date?) -> Bool {
    guard let previous = previous else { return true }
    return !Calendar.current.isDate(date, inSameDayAs: previous) ||
      date.timeIntervalSince(previous) >= 30 * 60
  }

  private var label: String {
    let locale = SignalASILocalization.interfaceLocale(language: language)
    var calendar = Calendar.current
    calendar.locale = locale
    let time = formatted(date, format: "HH:mm", locale: locale)
    if calendar.isDateInToday(date) {
      return time
    }
    if calendar.isDateInYesterday(date) {
      let yesterday = SignalASILocalization.string(
        "signalasi.message.yesterday",
        fallback: "Yesterday",
        language: language
      )
      return "\(yesterday) \(time)"
    }
    return formatted(date, format: "MM/dd HH:mm", locale: locale)
  }

  private func formatted(_ value: Date, format: String, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = format
    return formatter.string(from: value)
  }
}

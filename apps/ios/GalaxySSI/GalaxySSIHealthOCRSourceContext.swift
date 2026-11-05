import Foundation
import SwiftUI

struct GalaxySSIHealthOCRSourceContext: Equatable, Sendable {
  struct Sample: Equatable, Sendable {
    let date: Date
    let zone: String
  }

  var names: [String] = []
  var times: [String] = []
  var sample: Sample?

  var isEmpty: Bool { names.isEmpty && times.isEmpty }

  private static let nameLabel = try! NSRegularExpression(
    pattern: #"^(?:patient(?:['\u2019]s)?\s+name|(?:\u60A3\u8005|\u53D7\u68C0\u8005|\u75C5\u4EBA)?\u59D3\u540D)\s*[:\uFF1A]\s*(.+)$"#,
    options: .caseInsensitive
  )
  private static let timeLabel = try! NSRegularExpression(
    pattern: #"^(?:(?:(?:sample|specimen)\s+)?collect(?:ed(?:\s+at)?|ion\s+(?:date(?:\s*/\s*time)?|time))|measured\s+at|measurement\s+(?:date\s*/\s*time|time)|(?:\u91C7\u6837|\u91C7\u96C6|\u6D4B\u91CF)(?:\u65F6\u95F4|\u65E5\u671F))\s*[:\uFF1A]\s*(.+)$"#,
    options: .caseInsensitive
  )
  private static let timestamp = try! NSRegularExpression(
    pattern: #"^([0-9]{4})[-/.\u5E74]([0-9]{1,2})[-/.\u6708]([0-9]{1,2})\u65E5?[ Tt]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?\s*(Z|[+-][0-9]{2}:[0-9]{2})?$"#
  )

  static func inspect(_ regions: [String], timeZone: TimeZone) -> Self {
    let lines = regions.prefix(1_000).flatMap { $0.split(whereSeparator: \.isNewline) }
    let names = values(lines, matching: nameLabel)
    let times = values(lines, matching: timeLabel)
    let proposed = names.count <= 1 && times.count == 1 ? parseTime(times[0], in: timeZone) : nil
    return Self(names: names, times: times, sample: proposed)
  }

  private static func values(_ lines: [Substring], matching regex: NSRegularExpression) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for line in lines {
      let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard text.count <= 512,
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            let range = Range(match.range(at: 1), in: text) else { continue }
      let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty, value.count <= 200,
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            seen.insert(value).inserted else { continue }
      output.append(value)
      if output.count == 4 { break }
    }
    return output
  }

  private static func parseTime(_ text: String, in zone: TimeZone) -> Sample? {
    guard let match = timestamp.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    else { return nil }
    func field(_ index: Int) -> String? {
      Range(match.range(at: index), in: text).map { String(text[$0]) }
    }
    guard let year = field(1).flatMap(Int.init), (1900...2200).contains(year),
          let month = field(2).flatMap(Int.init), (1...12).contains(month),
          let day = field(3).flatMap(Int.init), (1...31).contains(day),
          let hour = field(4).flatMap(Int.init), (0...23).contains(hour),
          let minute = field(5).flatMap(Int.init), (0...59).contains(minute) else { return nil }
    let second = field(6).flatMap(Int.init) ?? 0
    guard (0...59).contains(second), let utc = TimeZone(secondsFromGMT: 0) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    func matches(_ date: Date, in calendar: Calendar) -> Bool {
      let actual = calendar.dateComponents(fields, from: date)
      return actual.year == year && actual.month == month && actual.day == day &&
        actual.hour == hour && actual.minute == minute && actual.second == second
    }
    guard let wallTime = calendar.date(from: parts), matches(wallTime, in: calendar) else {
      return nil
    }

    if let explicit = field(7) {
      if explicit == "Z" || explicit == "+00:00" || explicit == "-00:00" {
        return Sample(date: wallTime, zone: "UTC")
      }
      let digits = explicit.dropFirst().split(separator: ":")
      guard digits.count == 2, let hours = Int(digits[0]), let minutes = Int(digits[1]),
            (0...18).contains(hours), (0...59).contains(minutes), hours < 18 || minutes == 0 else { return nil }
      let offset = (hours * 3_600 + minutes * 60) * (explicit.first == "-" ? -1 : 1)
      return Sample(date: wallTime.addingTimeInterval(-Double(offset)), zone: "UTC" + explicit)
    }

    // Reconstruct every possible nearby offset; a DST gap has none and an overlap has two.
    calendar.timeZone = zone
    let offsets = Set(stride(from: -48, through: 48, by: 6).map {
      zone.secondsFromGMT(for: wallTime.addingTimeInterval(Double($0) * 3_600))
    })
    let matches = offsets.map { wallTime.addingTimeInterval(-Double($0)) }
      .filter { matches($0, in: calendar) }
    guard matches.count == 1, let date = matches.first else { return nil }
    return Sample(date: date, zone: zone.identifier)
  }
}

@MainActor
struct GalaxySSIHealthOCRSourceContextRows: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let context: GalaxySSIHealthOCRSourceContext
  var apply: (@MainActor (GalaxySSIHealthOCRSourceContext.Sample) -> Void)? = nil

  var body: some View {
    if !context.isEmpty {
      Section(t("source_context", "Labeled report context")) {
        if !context.names.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(t("source_name", "Name shown on report")).font(.caption).foregroundColor(.secondary)
            ForEach(context.names, id: \.self) { Text($0).textSelection(.enabled) }
          }
        }
        if !context.times.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(t("source_time", "Collection or measurement time on report"))
              .font(.caption).foregroundColor(.secondary)
            ForEach(context.times, id: \.self) { Text($0).textSelection(.enabled) }
          }
          if let sample = context.sample, sample.date <= Date() {
            Text(String(format: t("source_time_zone", "Time interpreted in %@"), sample.zone))
              .font(.caption).foregroundColor(.secondary)
            if let apply {
              Button(t("source_use_time", "Use this time")) { apply(sample) }
                .accessibilityIdentifier("ios.health.ocr.source-use-time")
            }
          } else {
            Text(t("source_time_unavailable", "No unambiguous time to apply. Verify it manually."))
              .font(.caption).foregroundColor(.secondary)
          }
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthReportReview.text(key, fallback, language: language)
  }
}

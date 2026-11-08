import Foundation
import SwiftUI

enum GalaxySSIHealthCarePriority {
  static let source = URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/when-to-call-911-for-high-blood-pressure")!

  struct Warning: Codable, Equatable {
    let record: GalaxySSIHealthCare.Record
    let measuredAt: Date
    let unit: String
    let systolic: Decimal
    let diastolic: Decimal

    var displayedValue: String {
      [systolic, diastolic].map { NSDecimalNumber(decimal: $0).stringValue }.joined(separator: " / ") + " " + unit
    }
  }

  static func evaluate(_ reading: GalaxySSIHealthReading?) -> Warning? {
    guard let reading, reading.metric == .bloodPressure, !reading.deleted, reading.isValid,
          let systolic = reading.value, let diastolic = reading.diastolic else { return nil }
    let scale: Decimal
    switch reading.unit {
    case "mmHg": scale = 1
    // NIST SP 811: conventional mmHg is 133.3224 Pa; compare before rounding.
    case "kPa": scale = Decimal(1_333_224) / Decimal(10_000_000)
    default: return nil
    }
    guard systolic > Decimal(180) * scale || diastolic > Decimal(120) * scale else { return nil }
    return .init(record: .init(reading), measuredAt: reading.measuredAt, unit: reading.unit,
      systolic: systolic, diastolic: diastolic)
  }
}

struct GalaxySSIHealthCarePriorityNotice: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let warning: GalaxySSIHealthCarePriority.Warning
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 8) {
      Label(t("title", "Review this recorded blood pressure first"), systemImage: "exclamationmark.triangle")
        .font(compact ? .footnote.weight(.semibold) : .headline)
      Text(warning.displayedValue).font(.subheadline.monospacedDigit())
      Text(warning.measuredAt, format: .dateTime.year().month().day().hour().minute())
        .font(.caption).foregroundColor(.secondary)
      if compact {
        Text(t("compact", "An old reading does not establish a current emergency. If this high now with new serious symptoms, seek emergency help."))
          .font(.caption).foregroundColor(.secondary)
      } else {
        Text(t("threshold", "The recorded systolic value is above 180 or the diastolic value is above 120 mmHg, or the equivalent."))
        Text(t("emergency", "For nonpregnant adults: if your pressure is this high now with chest pain, trouble breathing, back pain, numbness, weakness, vision changes, or difficulty speaking, seek local emergency help now. Do not wait for the app."))
          .font(.body.weight(.semibold))
        Text(t("recheck", "For a current reading without new concerning symptoms, wait at least one minute and measure again. If still this high, contact a health professional promptly. Do not change medication on your own."))
        Text(t("scope", "Children and pregnancy need different assessment. A past reading does not establish a current emergency. This warning is not a diagnosis or live monitoring."))
          .foregroundColor(.secondary)
        Link(t("source", "American Heart Association guidance"), destination: GalaxySSIHealthCarePriority.source)
      }
    }
    .foregroundColor(.primary)
    .accessibilityElement(children: .contain)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.priority." + key, fallback: fallback, language: language)
  }
}

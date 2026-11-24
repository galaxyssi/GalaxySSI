import Foundation

/// Frozen paired synthetic inputs, not population estimates or experimental validation.
struct GalaxySSIHealthAtlasModelComparison: Equatable, Sendable {
  enum Scenario: Int, CaseIterable, Sendable {
    case control, exchange, faster
    var distribution: GalaxySSIHealthAtlasDistribution {
      let rates: (Int, Int)
      switch self {
      case .control: rates = (0, 0)
      case .exchange: rates = (30, 15)
      case .faster: rates = (100, 40)
      }
      return GalaxySSIHealthAtlasDistribution(outward: rates.0, returning: rates.1, elimination: 10)!
    }
    var label: String {
      switch self {
      case .control: return "compare_control"
      case .exchange: return "compare_exchange"
      case .faster: return "compare_faster"
      }
    }
  }
  struct Point: Equatable, Sendable {
    let one: Double
    let two: GalaxySSIHealthAtlasDistribution.Amounts
    let low: Double
    let high: Double
    var centralGap: Double { two.central - one }
  }
  let scenario: Scenario
  let quarterHours: Int
  static let standard = Self()!
  init?(scenario: Scenario = .exchange, quarterHours: Int = 16) {
    guard (0...192).contains(quarterHours) else { return nil }
    self.scenario = scenario; self.quarterHours = quarterHours
  }
  var hours: Double { Double(quarterHours) / 4 }
  var point: Point { at(hours)! }
  func at(_ hours: Double) -> Point? {
    guard hours.isFinite, (0...48).contains(hours) else { return nil }
    let values = Scenario.allCases.map { $0.distribution.at(hours)! }
    return Point(one: 100 * exp(-scenario.distribution.k10 * hours), two: values[scenario.rawValue],
      low: values.map(\.central).min()!, high: values.map(\.central).max()!)
  }
  // Three immutable profiles keep moving the cursor from recalculating whole curves.
  private static let profiles: [[Point]] = Scenario.allCases.map { scenario in
    let model = Self(scenario: scenario)!
    return (0...192).map { model.at(Double($0) / 4)! }
  }
  var samples: [Point] { Self.profiles[scenario.rawValue] }
}

enum GalaxySSIHealthAtlasComparisonText {
  static let validationSource = URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6977398/")!
  private static func number(_ value: Double, _ locale: Locale) -> String {
    let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }
  static func time(_ model: GalaxySSIHealthAtlasModelComparison, locale: Locale, text t: (String) -> String) -> String {
    String(format: t("distribution_time"), number(model.hours, locale))
  }
  static func rates(_ model: GalaxySSIHealthAtlasModelComparison, locale: Locale, text t: (String) -> String) -> String {
    let values = model.scenario.distribution
    return String(format: t("distribution_rates"), number(values.k12, locale), number(values.k21, locale), number(values.k10, locale))
  }
  static func summary(_ point: GalaxySSIHealthAtlasModelComparison.Point, locale: Locale, text t: (String) -> String) -> String {
    String(format: t("compare_summary"), number(point.one, locale), number(point.two.central, locale), number(point.centralGap, locale))
  }
  static func range(_ point: GalaxySSIHealthAtlasModelComparison.Point, locale: Locale, text t: (String) -> String) -> String {
    String(format: t("compare_range"), number(point.low, locale), number(point.high, locale))
  }
  static func context(_ model: GalaxySSIHealthAtlasModelComparison, locale: Locale, text t: (String) -> String) -> String {
    [t("compare_title"), t("compare_scope"), t(model.scenario.label), rates(model, locale: locale, text: t),
      time(model, locale: locale, text: t), summary(model.point, locale: locale, text: t),
      range(model.point, locale: locale, text: t), t("compare_limit"),
      GalaxySSIHealthAtlasDistribution.source.absoluteString, validationSource.absoluteString].joined(separator: "\n")
  }
}

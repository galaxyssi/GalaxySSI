import Foundation

/// Linear two-compartment amounts after a normalized central bolus; no patient parameters.
struct GalaxySSIHealthAtlasDistribution: Equatable, Sendable {
  struct Amounts: Equatable, Sendable {
    let central: Double
    let peripheral: Double
    let eliminated: Double
    var values: [Double] { [central, peripheral, eliminated] }
  }
  let outward: Int
  let returning: Int
  let elimination: Int
  let quarterHours: Int
  static let standard = Self(outward: 30, returning: 15, elimination: 10, quarterHours: 16)!
  static let source = URL(string: "https://doi.org/10.12793/tcp.2019.27.2.43")!
  init?(outward: Int = 30, returning: Int = 15, elimination: Int = 10, quarterHours: Int = 16) {
    guard (0...300).contains(outward), (0...300).contains(returning), (0...300).contains(elimination),
      (0...192).contains(quarterHours) else { return nil }
    self.outward = outward; self.returning = returning; self.elimination = elimination; self.quarterHours = quarterHours
  }
  var k12: Double { Double(outward) / 100 }
  var k21: Double { Double(returning) / 100 }
  var k10: Double { Double(elimination) / 100 }
  var hours: Double { Double(quarterHours) / 4 }
  var amounts: Amounts { at(hours)! }
  func at(_ hours: Double) -> Amounts? {
    guard hours.isFinite, (0...48).contains(hours) else { return nil }
    if hours == 0 { return Amounts(central: 100, peripheral: 0, eliminated: 0) }
    if outward == 0 {
      let central = 100 * exp(-k10 * hours)
      return Amounts(central: central, peripheral: 0, eliminated: 100 - central)
    }
    let sum = k10 + k12 + k21
    let delta = sqrt(pow(k10 + k12 - k21, 2) + 4 * k12 * k21)
    let alpha = (sum + delta) / 2, beta = k10 * k21 / alpha
    let slow = exp(-beta * hours), fast = exp(-alpha * hours)
    let central = 100 * ((alpha - k21) * fast + (k21 - beta) * slow) / delta
    // expm1 preserves small-time precision; the repeated root with zero outward transfer is handled above.
    let peripheral = 100 * k12 * slow * -expm1(-delta * hours) / delta
    func bounded(_ value: Double) -> Double { min(100, max(0, value)) }
    return Amounts(central: bounded(central), peripheral: bounded(peripheral), eliminated: bounded(100 - central - peripheral))
  }
  func changing(_ index: Int, to value: Int) -> Self? {
    var values = [quarterHours, outward, returning, elimination]
    guard values.indices.contains(index) else { return nil }
    values[index] = value
    return Self(outward: values[1], returning: values[2], elimination: values[3], quarterHours: values[0])
  }
  func summary(locale: Locale, text t: (String) -> String) -> String {
    String(format: t("distribution_summary"), number(hours, locale: locale),
      number(amounts.central, locale: locale), number(amounts.peripheral, locale: locale), number(amounts.eliminated, locale: locale))
  }
  func context(locale: Locale, text t: (String) -> String) -> String {
    [t("drug_two"), t("distribution_scope"),
      String(format: t("distribution_rates"), number(k12, locale: locale), number(k21, locale: locale), number(k10, locale: locale)),
      summary(locale: locale, text: t), t("distribution_formula"), t("distribution_boundary"), Self.source.absoluteString]
      .joined(separator: "\n")
  }
  private func number(_ value: Double, locale: Locale) -> String {
    let formatter = NumberFormatter(); formatter.locale = locale
    formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }
}

struct GalaxySSIHealthAtlasDrugState: Equatable, Sendable {
  enum Mode: Int, CaseIterable, Sendable { case single, two }
  var mode = Mode.single
  var distribution = GalaxySSIHealthAtlasDistribution.standard
  var encoded: [Int] { [mode.rawValue, distribution.outward, distribution.returning, distribution.elimination, distribution.quarterHours] }
  static func restore(_ values: [Int]?) -> Self? {
    guard let values, values.count == 5, let mode = Mode(rawValue: values[0]),
      let distribution = GalaxySSIHealthAtlasDistribution(outward: values[1], returning: values[2],
        elimination: values[3], quarterHours: values[4]) else { return nil }
    return Self(mode: mode, distribution: distribution)
  }
}

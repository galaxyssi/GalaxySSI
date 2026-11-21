import Foundation

/// Fixed-exponent equilibrium teaching identity, not a measurement or a patient prediction.
enum GalaxySSIHealthAtlasOxygen {
  struct Amounts: Equatable, Sendable {
    let bound: Double
    let dissolved: Double
    var total: Double { bound + dissolved }
  }
  static let bindingSource = URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC2862600/")!
  static let contentSource = URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC3485568/")!
  static var sources: [URL] { [bindingSource, contentSource] }

  static func saturation(pressure: Double, p50: Double) -> Double? {
    guard pressure.isFinite, pressure >= 0, p50.isFinite, p50 > 0 else { return nil }
    // Reciprocal form avoids infinity/infinity at extreme ratios; zero pressure is exact.
    return pressure == 0 ? 0 : 1 / (1 + pow(p50 / pressure, 2.7))
  }
  static func amounts(pressure: Double, p50: Double, hemoglobinGramsPerLiter: Double) -> Amounts? {
    guard hemoglobinGramsPerLiter.isFinite, hemoglobinGramsPerLiter >= 0,
      let fraction = saturation(pressure: pressure, p50: p50) else { return nil }
    // Hb g/L -> g/dL. Both quantities are mL O2 per dL of whole blood, using a fraction, not a percentage.
    return Amounts(bound: 1.34 * (hemoglobinGramsPerLiter / 10) * fraction, dissolved: 0.0031 * pressure)
  }
}

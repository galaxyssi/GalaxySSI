import Foundation

/// Steady, fully developed flow in one ideal rigid circular tube; not a patient-vessel estimate.
struct GalaxySSIHealthAtlasVesselFlow: Equatable, Sendable {
  let pressureMmHg: Double
  let radiusMm: Double
  let lengthMm: Double
  let viscosityMilliPascalSeconds: Double
  static let pascalsPerMmHg = 133.3224
  static let sources = [
    URL(string: "https://openstax.org/books/college-physics-2e/pages/12-4-viscosity-and-laminar-flow-poiseuilles-law")!,
    URL(string: "https://ocw.mit.edu/courses/2-25-advanced-fluid-mechanics-fall-2013/1a114d602956fa0dd328155f9b45f93d_MIT2_25F13_Couet_and_Pois.pdf")!,
    URL(string: "https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9")!
  ]
  init?(pressureMmHg: Double = 10, radiusMm: Double = 0.1, lengthMm: Double = 50, viscosityMilliPascalSeconds: Double = 3.5) {
    guard pressureMmHg.isFinite, (0...20).contains(pressureMmHg), radiusMm.isFinite, (0.05...0.2).contains(radiusMm),
      lengthMm.isFinite, (20...100).contains(lengthMm), viscosityMilliPascalSeconds.isFinite,
      (2...6).contains(viscosityMilliPascalSeconds) else { return nil }
    self.pressureMmHg = pressureMmHg; self.radiusMm = radiusMm; self.lengthMm = lengthMm
    self.viscosityMilliPascalSeconds = viscosityMilliPascalSeconds
  }
  private var radiusMetres: Double { radiusMm / 1000 }
  private var lengthMetres: Double { lengthMm / 1000 }
  private var viscosityPascalSeconds: Double { viscosityMilliPascalSeconds / 1000 }
  private var resistanceSI: Double { 8 * viscosityPascalSeconds * lengthMetres / (.pi * pow(radiusMetres, 4)) }
  var flowCubicMetresPerSecond: Double { pressureMmHg * Self.pascalsPerMmHg / resistanceSI }
  var flowMlPerMinute: Double { flowCubicMetresPerSecond * 60_000_000 }
  // Resistance is calculated independently of Q, including at zero pressure.
  var resistanceMmHgMinutesPerMl: Double { resistanceSI / (Self.pascalsPerMmHg * 60_000_000) }
  var meanSpeedMmPerSecond: Double { flowCubicMetresPerSecond / (.pi * pow(radiusMetres, 2)) * 1000 }
  var centreSpeedMmPerSecond: Double { 2 * meanSpeedMmPerSecond }
  var wallShearPascals: Double { pressureMmHg * Self.pascalsPerMmHg * radiusMetres / (2 * lengthMetres) }
  func speedMmPerSecond(relativeRadius: Double) -> Double? {
    guard relativeRadius.isFinite, (-1...1).contains(relativeRadius) else { return nil }
    return centreSpeedMmPerSecond * (1 - relativeRadius * relativeRadius)
  }
}

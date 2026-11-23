import Foundation

/// Equivalent thin lens in air with a fixed teaching plane, not a prescription.
struct GalaxySSIHealthAtlasEyeOptics: Equatable, Sendable {
  let distanceMetres: Double
  let powerDiopters: Double
  static let retinalPlaneMm = 17.0
  static let source = URL(string: "https://openstax.org/books/university-physics-volume-3/pages/2-5-the-eye")!
  static let anatomySource = URL(string: "https://www.nei.nih.gov/eye-health-information/healthy-vision/nei-for-kids/about-eye")!
  enum FocusSide: String { case in_front, at_plane, behind }
  init?(distanceMetres: Double = 1, powerDiopters: Double = 59.82) {
    guard distanceMetres.isFinite, (0.25...6).contains(distanceMetres),
      powerDiopters.isFinite, (55...65).contains(powerDiopters) else { return nil }
    self.distanceMetres = distanceMetres; self.powerDiopters = powerDiopters
  }
  var imageDistanceMm: Double { 1000 / (powerDiopters - 1 / distanceMetres) }
  var offsetMm: Double { imageDistanceMm - Self.retinalPlaneMm }
  var targetPowerDiopters: Double { 1000 / Self.retinalPlaneMm + 1 / distanceMetres }
  var targetPowerSteps: Int { Int((targetPowerDiopters * 100).rounded()) }
  var focusSide: FocusSide { abs(offsetMm) < 0.005 ? .at_plane : offsetMm < 0 ? .in_front : .behind }
  func rayHeight(axialMm: Double, heightAtLensMm: Double) -> Double? {
    guard axialMm.isFinite, heightAtLensMm.isFinite else { return nil }
    let result = heightAtLensMm * (axialMm < 0 ? 1 + axialMm / (1000 * distanceMetres) : 1 - axialMm / imageDistanceMm)
    return result.isFinite ? result : nil
  }
  static let plate = GalaxySSIHealthAtlas.Plate(id: "eye", asset: "HealthAtlasEyeSection", owner: "eye",
    viewLabel: "health_atlas_view_eye_section", entryIDs: ["eye", "cornea", "lens", "retina"], aspectRatio: 400.0 / 280,
    markers: [.init(id: "cornea", x: 0.138, y: 0.39), .init(id: "lens", x: 0.30, y: 0.49),
      .init(id: "retina", x: 0.663, y: 0.669)], source: anatomySource)
}

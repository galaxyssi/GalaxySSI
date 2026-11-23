import Foundation

/// Qualitative playback fractions, not secretion rates or clinical timing.
struct GalaxySSIHealthAtlasSweat: Equatable {
  static let owner = "sweat-glands"
  let phase: Double
  init?(phase: Double) {
    guard phase.isFinite else { return nil }
    self.phase = min(1, max(0, phase))
  }
  var stage: Int { min(3, Int(phase * 4)) }
  var fraction: Double { min(1, max(0, phase * 4 - Double(stage))) }
  var transportFraction: Double? {
    stage == 0 ? 1 - 0.25 * fraction : stage == 1 ? 0.75 * (1 - fraction) : nil
  }
  var surfaceRadius: Double? { stage == 2 ? 5 + fraction * 3 : nil }
  var vaporOpacity: Double { Double(210 - Int(fraction * 135)) / 255 }
  static func context(_ id: String, text t: (String) -> String) -> String? {
    id == owner ? t("context_sweat_scope") : id == "hair-follicles" ? t("context_hair_scope") : nil
  }
}

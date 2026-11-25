import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricChiefLabels(_ step: Int) {
    switch step {
    case 0:
      gastricChiefCallout("gastric_chief_story_stomach", 67, 62, 106, 67, 70, 76, 119)
      gastricChiefCallout("gastric_chief_story_pit", 243, 50, 130, 243, 58, 252, 116)
      gastricChiefCallout("gastric_chief_story_chief_cells", 161, 318, 122, 173, 302, 204, 255)
      gastricChiefCallout("gastric_chief_story_gland_base", 303, 318, 104, 294, 302, 264, 291)
    case 1:
      gastricChiefCallout("gastric_chief_story_granule", 147, 63, 139, 153, 71, 183, 125)
      gastricChiefCallout("gastric_chief_story_gland_lumen", 281, 49, 120, 281, 57, 260, 99)
      gastricChiefCallout("gastric_chief_story_nucleus", 86, 307, 140, 84, 290, 91, 213)
    case 2:
      gastricChiefCallout("gastric_chief_story_chief_cell", 86, 56, 124, 86, 64, 95, 110)
      gastricChiefCallout("gastric_chief_story_pepsinogen", 282, 50, 124, 282, 58, 271, 94)
      gastricChiefCallout("gastric_chief_story_membrane", 150, 310, 159, 159, 293, 221, 231)
      gastricChiefCallout("gastric_chief_story_gland_lumen", 286, 310, 111, 286, 293, 268, 247)
    case 3:
      gastricChiefCallout("gastric_chief_story_parietal_cell", 76, 53, 126, 77, 61, 78, 111)
      gastricChiefCallout("gastric_chief_story_chief_cell", 287, 53, 120, 298, 61, 295, 147)
      gastricChiefCallout("gastric_chief_story_acidic_lumen", 97, 317, 126, 107, 300, 143, 240)
      gastricChiefCallout("gastric_chief_story_activation_site", 246, 317, 145, 237, 300, 202, 251)
    case 4:
      gastricChiefCallout("gastric_chief_story_protein", 77, 54, 131, 72, 63, 100, 156)
      gastricChiefCallout("gastric_chief_story_pepsin", 282, 55, 113, 283, 63, 288, 136)
    default: break
    }
  }
  private func gastricChiefCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ fromX: Double, _ fromY: Double, _ toX: Double, _ toY: Double) {
    line(fromX, fromY, toX, toY, 0x56696E, 1.1)
    disc(toX, toY, 1.7, 0x56696E)
    label(key, x, baseline, width)
  }
}

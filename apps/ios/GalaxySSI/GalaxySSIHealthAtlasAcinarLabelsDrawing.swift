import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func acinarLabels(_ step: Int) {
    switch step {
    case 0:
      acinarCallout("acinar_enzyme_story_lobule", 89, 65, 141, 89, 74, 72, 100)
      acinarCallout("acinar_enzyme_story_acinus", 254, 65, 112, 254, 74, 263, 122)
      acinarCallout("acinar_enzyme_story_lumen", 220, 301, 113, 223, 288, 260, 188)
      acinarCallout("acinar_enzyme_story_small_duct", 303, 274, 104, 318, 261, 327, 183)
    case 1:
      acinarCallout("acinar_enzyme_story_rough_er", 74, 61, 106, 74, 71, 83, 121)
      acinarCallout("acinar_enzyme_story_golgi", 102, 291, 135, 122, 279, 143, 192)
      acinarCallout("acinar_enzyme_story_granules", 251, 291, 137, 248, 279, 218, 194)
    case 2:
      acinarCallout("acinar_enzyme_story_granules", 142, 59, 136, 157, 68, 208, 151)
      acinarCallout("acinar_enzyme_story_lumen", 289, 60, 128, 286, 70, 261, 145)
      acinarCallout("acinar_enzyme_story_membrane", 158, 277, 151, 191, 264, 240, 202)
    case 3:
      acinarCallout("acinar_enzyme_story_acini", 57, 51, 95, 64, 59, 71, 83)
      acinarCallout("acinar_enzyme_story_ductal_cells", 235, 93, 126, 235, 102, 239, 153)
      acinarCallout("acinar_enzyme_story_duct_fluid", 247, 275, 176, 266, 262, 285, 186)
    case 4:
      acinarCallout("acinar_enzyme_story_pancreas", 102, 79, 126, 108, 88, 131, 138)
      acinarCallout("acinar_enzyme_story_main_duct", 96, 222, 154, 99, 209, 124, 159)
      acinarCallout("acinar_enzyme_story_duodenum", 265, 310, 137, 266, 297, 268, 248)
    default: break
    }
  }
  private func acinarCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ lx: Double, _ ly: Double, _ tx: Double, _ ty: Double) {
    line(lx, ly, tx, ty, 0x5A686D, 1.05)
    disc(tx, ty, 1.55, 0x5A686D)
    label(key, x, y, width)
  }
}

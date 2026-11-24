import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tonsilLabels(_ step: Int) {
    switch step {
    case 0:
      label("tonsil_story_pharyngeal", 278, 84, 144)
      label("tonsil_story_adenoids", 278, 100, 135)
      tonsilLeader(278, 107, 236, 117, 167, 125)
      label("tonsil_story_palatine", 278, 217, 146)
      tonsilLeader(278, 203, 230, 192, 150, 192)
    case 1:
      label("tonsil_story_crypt", 94, 78, 150)
      tonsilLeader(94, 85, 94, 111, 94, 138)
      label("tonsil_story_folds", 267, 78, 155)
      tonsilLeader(267, 85, 267, 103, 250, 130)
      label("tonsil_story_palatine", 94, 289, 155)
      label("tonsil_story_adenoids", 267, 289, 155)
    case 2:
      label("tonsil_story_lumen", 265, 80, 147)
      tonsilLeader(248, 87, 232, 94, 207, 111)
      label("tonsil_story_lymphoid", 258, 329, 153)
      tonsilLeader(258, 315, 258, 295, 258, 264)
    case 3, 4:
      if step == 4 {
        label("tonsil_story_t_cell", 241, 331, 104)
        tonsilLeader(241, 316, 241, 280, 227, 245)
      }
      label("tonsil_story_lining", 252, 95, 166)
      tonsilLeader(252, 103, 252, 121, 237, 143)
      label("tonsil_story_dendritic", 104, 331, 148)
      tonsilLeader(104, 315, 104, 273, 124, 242)
    default: break
    }
  }
  private func tonsilLeader(_ x: Double, _ y: Double, _ ex: Double, _ ey: Double, _ tx: Double, _ ty: Double) {
    line(x, y, ex, ey, 0x526C71, 1.05)
    line(ex, ey, tx, ty, 0x526C71, 1.05)
    disc(tx, ty, 1.8, 0x526C71, border: Self.cream)
  }
}

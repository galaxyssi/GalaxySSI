import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusLabels(_ step: Int) {
    switch step {
    case 0:
      sinusLeader("sinus_drainage_frontal", 81, 47, 142, 81, 55, 81, 88, 75, 111)
      sinusLeader("sinus_drainage_maxillary_pair", 90, 304, 150, 53, 290, 41, 256, 57, 200)
      sinusLeader("sinus_drainage_ethmoid", 230, 47, 102, 230, 55, 243, 93, 242, 145)
      sinusLeader("sinus_drainage_sphenoid", 269, 304, 150, 312, 291, 320, 180, 279, 149)
      label("sinus_drainage_front_view", 90, 335, 136)
      label("sinus_drainage_side_view", 269, 335, 136)
    case 1, 3, 4:
      label("sinus_drainage_maxillary", 125, 191, 108)
      sinusLeader("sinus_drainage_opening", 212, 42, 190, 212, 51, 211, 113, 205, 149)
      sinusLeader("sinus_drainage_floor", 105, 318, 160, 105, 302, 110, 290, 137, 266)
      sinusLeader("sinus_drainage_nasal_passage", 276, 318, 150, 283, 303, 298, 282, 292, 225)
      label("sinus_drainage_coronal_view", 180, 341, 210)
    case 2:
      sinusLeader("sinus_drainage_mucus_film", 259, 181, 144, 259, 185, 252, 192, 246, 204)
      sinusLeader("sinus_drainage_secretory_cell", 156, 325, 150, 156, 309, 158, 291, 162, 255)
      sinusLeader("sinus_drainage_cilia", 50, 325, 68, 39, 309, 23, 236, 43, 216)
    default: break
    }
  }
  private func sinusLeader(_ key: String, _ x: Double, _ baseline: Double, _ width: Double,
    _ startX: Double, _ startY: Double, _ bendX: Double, _ bendY: Double, _ targetX: Double, _ targetY: Double) {
    var path = Path()
    path.move(to: CGPoint(x: startX, y: startY)); path.addLine(to: CGPoint(x: bendX, y: bendY)); path.addLine(to: CGPoint(x: targetX, y: targetY))
    stroke(path, 0x576E71, 1.05)
    disc(targetX, targetY, 1.85, 0x576E71)
    label(key, x, baseline, width)
  }
}

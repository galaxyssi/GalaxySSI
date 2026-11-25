import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mesangialLabels() {
    mesangialLeader(155, 36, 120, 39)
    label("mesangial_story_label_glomerulus", 205, 40, 94)
    mesangialLeader(255, 111, 215, 110)
    label("mesangial_story_label_podocyte", 300, 115, 84)
    mesangialLeader(253, 164, 215, 164)
    label("mesangial_story_label_loop", 302, 168, 91)
    mesangialLeader(252, 198, 245, 201)
    label("mesangial_story_label_basement", 302, 197, 93)
    label("mesangial_story_label_membrane", 302, 211, 93)
    line(104, 309, 127, 269, 0x576D70, 1)
    mesangialLeader(127, 269, 133, 228)
    label("mesangial_story_label_cell", 86, 328, 146)
    line(180, 309, 153, 270, 0x576D70, 1)
    mesangialLeader(153, 270, 146, 258)
    label("mesangial_story_label_matrix", 203, 328, 143)
  }
  private func mesangialLeader(_ x: Double, _ y: Double, _ targetX: Double, _ targetY: Double) {
    line(x, y, targetX, targetY, 0x576D70, 1)
    disc(targetX, targetY, 1.8, 0x576D70, border: Self.cream)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferLabels(_ step: Int) {
    switch step {
    case 0:
      ductBufferCallout("duct_buffer_story_acinus", 58, 46, 88, 59, 54, 71, 76)
      ductBufferCallout("duct_buffer_story_acinar_lumen", 175, 325, 132, 155, 310, 93, 254)
      ductBufferCallout("duct_buffer_story_small_duct", 277, 96, 135, 269, 103, 223, 125)
    case 1:
      ductBufferCallout("duct_buffer_story_acidic_contents", 102, 79, 135, 105, 87, 116, 111)
      ductBufferCallout("duct_buffer_story_s_cell", 274, 103, 98, 267, 111, 220, 154)
      ductBufferCallout("duct_buffer_story_blood_signal", 252, 248, 166, 192, 238, 172, 225)
      ductBufferCallout("duct_buffer_story_duct_cells", 240, 305, 130, 205, 297, 145, 285)
    case 2:
      ductBufferCallout("duct_buffer_story_duct_cells", 111, 81, 124, 111, 90, 111, 123)
      ductBufferLeader(56, 274, 33, 248)
      ductBufferLeader(33, 248, 33, 177)
      ductBufferCallout("duct_buffer_story_duct_lumen", 85, 294, 126, 33, 177, 54, 177)
      ductBufferLeader(295, 275, 327, 246)
      ductBufferLeader(327, 246, 327, 181)
      ductBufferCallout("duct_buffer_story_rich_fluid", 252, 294, 176, 327, 181, 304, 181)
    case 3:
      ductBufferCallout("duct_buffer_story_pancreas", 89, 87, 132, 90, 95, 99, 130)
      ductBufferCallout("duct_buffer_story_main_duct", 103, 230, 160, 111, 216, 140, 159)
      ductBufferCallout("duct_buffer_story_duodenum", 266, 312, 127, 269, 299, 266, 254)
    case 4:
      ductBufferCallout("duct_buffer_story_acidic_contents", 91, 111, 138, 91, 120, 97, 174)
      ductBufferCallout("duct_buffer_story_rich_fluid", 250, 76, 174, 246, 86, 208, 122)
      ductBufferCallout("duct_buffer_story_duodenal_lumen", 242, 281, 165, 242, 266, 253, 200)
    default: break
    }
  }
  private func ductBufferLeader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double) {
    line(x, y, tx, ty, 0x526569, 1.05)
  }
  private func ductBufferCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ lx: Double, _ ly: Double, _ tx: Double, _ ty: Double) {
    ductBufferLeader(lx, ly, tx, ty)
    disc(tx, ty, 1.65, 0x526569)
    label(key, x, y, width)
  }
}

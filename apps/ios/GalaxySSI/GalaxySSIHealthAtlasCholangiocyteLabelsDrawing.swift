import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteLabels(_ step: Int) {
    switch step {
    case 0:
      cholangiocyteCallout("cholangiocyte_story_liver", 81, 56, 118, 81, 65, 65, 104)
      cholangiocyteCallout("cholangiocyte_story_small_duct", 264, 67, 130, 262, 76, 229, 134)
      cholangiocyteCallout("cholangiocyte_story_larger_duct", 218, 327, 139, 217, 313, 198, 252)
    case 1:
      line(84, 72, 34, 140, 0x405C67, 1)
      cholangiocyteCallout("cholangiocyte_story_lumen", 84, 65, 114, 34, 140, 49, 171)
      cholangiocyteCallout("cholangiocyte_story_apical", 101, 304, 123, 97, 289, 126, 210)
      cholangiocyteCallout("cholangiocyte_story_cell", 250, 310, 126, 249, 294, 238, 233)
    case 2:
      cholangiocyteCallout("cholangiocyte_story_bicarbonate", 80, 59, 98, 83, 68, 111, 103)
      cholangiocyteCallout("cholangiocyte_story_chloride", 275, 59, 83, 273, 69, 249, 103)
      cholangiocyteCallout("cholangiocyte_story_exchanger", 180, 80, 120, 180, 90, 179, 146)
    case 3:
      cholangiocyteCallout("cholangiocyte_story_lumen", 88, 67, 103, 88, 76, 86, 103)
      cholangiocyteCallout("cholangiocyte_story_water_channel", 221, 64, 124, 220, 75, 208, 148)
      cholangiocyteCallout("cholangiocyte_story_tissue_side", 105, 321, 107, 111, 307, 120, 272)
    case 4:
      cholangiocyteCallout("cholangiocyte_story_modified_bile", 122, 73, 143, 129, 83, 152, 140)
      cholangiocyteCallout("cholangiocyte_story_duodenum", 261, 319, 129, 264, 305, 253, 267)
    default: break
    }
  }
  private func cholangiocyteCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ lx: Double, _ ly: Double, _ tx: Double, _ ty: Double) {
    line(lx, ly, tx, ty, 0x405C67, 1)
    disc(tx, ty, 1.7, 0x405C67)
    label(key, x, y, width)
  }
}

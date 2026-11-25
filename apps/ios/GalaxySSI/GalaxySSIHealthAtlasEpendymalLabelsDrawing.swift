import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ependymalLabels(_ step: Int, _ top: Double, _ t: Double) {
    let rim = GalaxySSIHealthAtlasEpendymalMotion.rim, r = GalaxySSIHealthAtlasEpendymalRoutes.self
    switch step {
    case 0:
      ependymalLocator()
      ependymalCallout("ependymal_story_lumen", 254, 73, 172, 245, 105)
      ependymalCallout("ependymal_story_lining", 203, 330, 224, 182, 249)
    case 1:
      ependymalCallout("ependymal_story_cilia", 179, 104, 166, 180, rim(180,top)-2)
      ependymalCallout("ependymal_story_apical_surface", 244, 324, 211, 198, rim(198,top)+2)
    case 2:
      label("ependymal_story_wave_front", 180, 89, 264)
      line(180, 97, 180, 131, 0x647C9A, 1.15); line(60, 131, 300, 131, 0x647C9A, 1.15)
      line(60, 131, 60, 138, 0x647C9A, 1.15); line(300, 131, 300, 138, 0x647C9A, 1.15)
    case 3:
      ependymalStream(r.singleRoute, t, 1.4, 6)
      ependymalCallout("ependymal_story_near_wall", 167, 93, 230, 164, 147)
    case 4:
      ependymalStream(r.leftRoute, t, 1.25, 4)
      ependymalStream(r.rightRoute, t+0.23, 1.25, 4)
      ependymalCallout("ependymal_story_local_routes", 180, 88, 237, 250, 158)
      line(180, 94, 106, 140, 0x647C9A, 1.15); disc(106, 140, 2.3, 0xF3FBFF, border: 0x647C9A)
    default: break
    }
  }
  private func ependymalCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double) {
    let fromY = y+(ty > y ? 6 : -15)
    line(x, fromY, tx, ty, 0x647C9A, 1.15); disc(tx, ty, 2.3, 0xF3FBFF, border: 0x647C9A)
    label(key, x, y, width)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ganglionLabels(_ step: Int) {
    switch step {
    case 0:
      ganglionCallout("ganglion_relay_art_drg",83, 62, 142, 131, 96)
      ganglionCallout("ganglion_relay_art_soma",269, 91, 151, 194, 111)
      ganglionCallout("ganglion_relay_art_junction",193, 272, 110, 192, 183)
      ganglionCallout("ganglion_relay_art_central",78, 315, 142, 47, 224)
      ganglionCallout("ganglion_relay_art_peripheral",284, 315, 140, 322, 187)
    case 1:
      ganglionCallout("ganglion_relay_art_pre",88, 60, 149, 68, 150)
      ganglionCallout("ganglion_relay_art_synapse",189, 83, 120, 159, 160)
      ganglionCallout("ganglion_relay_art_dendrite",85, 277, 130, 177, 165)
      ganglionCallout("ganglion_relay_art_post_soma",229, 281, 152, 227, 198)
      ganglionCallout("ganglion_relay_art_post",277, 315, 152, 322, 191)
    case 2:
      ganglionCallout("ganglion_relay_art_sheath",91, 57, 150, 122, 111)
      ganglionCallout("ganglion_relay_art_soma",266, 66, 151, 203, 144)
      ganglionCallout("ganglion_relay_art_glial_nucleus",79, 277, 133, 99, 182)
      ganglionCallout("ganglion_relay_art_perisomatic",226, 309, 180, 198, 216)
      ganglionCallout("ganglion_relay_art_matrix",281, 258, 145, 249, 220)
    default: break
    }
  }
  private func ganglionCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double) {
    line(x,y+(ty > y ? 5 : -14),tx,ty,0x617473,1)
    disc(tx,ty,1.65,0x617473,border:Self.cream)
    label(key,x,y,width)
  }
}

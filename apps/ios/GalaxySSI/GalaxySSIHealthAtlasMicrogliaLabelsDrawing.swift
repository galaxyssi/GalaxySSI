import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func microgliaLabels(_ step: Int, _ scale: Double, _ offsetX: Double, _ offsetY: Double) {
    switch step {
    case 0:
      microgliaCallout("microglia_story_neuron", 68, 38, 108, 63, 91, 0x8E86AD)
      microgliaCallout("microglia_story_soma", 101, 298, 166, 142, 185, 0x36786C)
    case 1: microgliaCallout("microglia_story_process", 237, 45, 184, 183, 116, 0x36786C)
    case 2: microgliaCallout("microglia_story_debris", 270, 68, 154, 261, 146, 0x9B6458)
    case 3: microgliaCallout("microglia_story_pouch", 273, 68, 155, offsetX+247*scale, offsetY+151*scale, 0x36786C)
    case 4: microgliaCallout("microglia_story_pouch", 270, 37, 161, 270, 68, 0x36786C)
    default: break
    }
  }
  private func microgliaCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ tx: Double, _ ty: Double, _ color: UInt32) {
    let fromY = y+(ty > y ? 5 : -14)
    line(x, fromY, tx, ty, color, 1.15); disc(tx, ty, 2.4, 0xF7FBFA, border: color)
    label(key, x, y, width)
  }
}

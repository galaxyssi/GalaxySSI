import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sebaceousCell(_ x: Double, _ y: Double, _ radius: Double, _ stored: Double, _ intact: Double) {
    guard intact > 0 else { return }
    var local = context; local.opacity = Double(Int(255 * intact)) / 255
    let art = copy(local)
    art.oval(x - radius, y - radius * 0.92, x + radius, y + radius * 0.92, fill: 0xF6D6AD, border: 0x99696B)
    let nuclearRadius = radius * (0.31 - 0.16 * stored)
    art.disc(x - radius * 0.2, y + radius * 0.17, nuclearRadius, 0x9773A0)
    for (index, offset) in GalaxySSIHealthAtlasSebaceousGeometry.lipidLocations.enumerated() {
      let volume = GalaxySSIHealthAtlasSebaceousMotion.volume(stored, index)
      if volume > 0 {
        art.disc(x + radius * offset.x, y + radius * offset.y, radius * (0.05 + 0.16 * volume), 0xD69742, border: 0xC0843F)
      }
    }
  }
}

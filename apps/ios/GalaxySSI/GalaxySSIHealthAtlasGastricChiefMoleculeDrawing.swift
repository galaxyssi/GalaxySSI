import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricChiefMolecule(_ x: Double, _ y: Double, _ size: Double, cleavage: Double? = nil) {
    var local = context
    local.translateBy(x: x, y: y); local.scaleBy(x: size, y: size)
    let art = copy(local)
    art.fill(GalaxySSIHealthAtlasGastricChiefGeometry.pepsinGlyph, 0x426D94)
    if let cleavage {
      let dx = 1.20 * cleavage, dy = 0.62 * cleavage
      art.line(0.72 + dx, -0.42 + dy, 0.89 + dx, 0.16 + dy, 0x9B622F, 0.36)
    }
  }
  func gastricChiefGranule(_ x: Double, _ y: Double, _ radius: Double) {
    disc(x, y, radius, 0xFFE3B5, border: 0x9B622F)
    gastricChiefMolecule(x - radius * 0.12, y, radius * 0.47, cleavage: 0)
  }
  func gastricChiefTint(_ shape: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32) {
    gradient(shape, top, bottom, from, to)
  }
}

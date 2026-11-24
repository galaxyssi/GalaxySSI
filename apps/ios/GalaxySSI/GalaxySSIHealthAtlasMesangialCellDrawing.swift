import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mesangialCell(_ tension: Double) {
    typealias Geometry = GalaxySSIHealthAtlasMesangialGeometry
    var local = context
    local.translateBy(x: 138, y: 227); local.scaleBy(x: 1, y: 1 - 0.12 * tension); local.translateBy(x: -138, y: -227)
    let art = copy(local)
    art.gradient(Geometry.cell, 174, 251, 0xC7DFCA, 0x78AA96)
    art.stroke(Geometry.cell, 0x396D65, 1.6)
    art.oval(126, 217, 140, 237, fill: 0x75A592, border: 0x396D65)
    art.disc(133, 227, 2.1, 0x396D65)
    gradient(Geometry.podocyte, 103, 148, 0xE6D9ED, 0xAE94BD)
    stroke(Geometry.podocyte, 0x785E85, 1.5)
    oval(189, 105, 210, 117, fill: 0xB39BC2, border: 0x785E85)
  }
  func mesangialBoundary(_ f: Double) {
    mesangialSweep(GalaxySSIHealthAtlasMesangialRoutes.wall, f - 0.30, f + 0.05, 0x9E712F, 4.2)
    if f > 0.35 {
      let light = GalaxySSIHealthAtlasMesangialMotion.boundaryLight(f)
      var local = context; local.opacity *= Double(Int(light * 255)) / 255
      copy(local).stroke(GalaxySSIHealthAtlasMesangialGeometry.podocyte, 0x79528B, 2.5)
    }
  }
  func mesangialUptake(_ f: Double) {
    let frame = GalaxySSIHealthAtlasMesangialMotion.uptake(f)
    disc(146, 218, frame.radius, 0xCCE2CE, border: 0x396D65)
    at(GalaxySSIHealthAtlasMesangialRoutes.uptake.route, frame.travel) { x, y in mesangialDebris(x, y, frame.size) }
    mesangialDebris(251, 253, 1)
    label("mesangial_story_label_debris", 307, 257, 93)
  }
  private func mesangialDebris(_ x: Double, _ y: Double, _ size: Double) {
    disc(x - 2 * size, y, 2.2 * size, 0xB17C42, border: 0x927344)
    disc(x + 1.8 * size, y + 1.3 * size, 1.9 * size, 0xD6A361, border: 0x927344)
    disc(x + 0.4 * size, y - 2.4 * size, 1.8 * size, 0xEBC58B, border: 0x927344)
  }
}

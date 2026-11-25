import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusSectionArt() {
    typealias Geometry = GalaxySSIHealthAtlasSinusGeometry
    sinusShaded(Geometry.bone, 66, 290, 0xFFEAD5, 0xDDB59A)
    sinusArea(Geometry.orbitSection, 0xF7DDCF, 0x886762)
    oval(99, 84, 150, 116, fill: 0xF8EBE1, border: 0xBD9288)
    oval(118, 90, 142, 110, fill: 0xD9B7AC, border: 0xBD9288)
    sinusShaded(Geometry.nasalSection, 84, 266, 0xFFE9DA, 0xE8AD9C)
    sinusArea(Geometry.middleTurbinate, 0xDBA693, 0x9B655E)
    sinusArea(Geometry.lowerTurbinate, 0xDBA693, 0x9B655E)
    sinusShaded(Geometry.maxillarySection, 128, 266, 0xF3F6E8, 0xD6E9DA, border: 0x457970)
    stroke(Geometry.outlet, 0xFCDFC6, 10); stroke(Geometry.outletEdges, 0x9B655E, 1.15)
  }
  func sinusCrossSection(_ t: Double, step: Int) {
    sinusSectionArt()
    switch step {
    case 1: sinusHeightCue(t)
    case 3: sinusRise(t)
    case 4: sinusEnterNose(t)
    default: break
    }
  }
  private func sinusHeightCue(_ t: Double) {
    let top = 149.0, bottom = 266.0, x = 25.0
    let end = bottom - (bottom - top) * GalaxySSIHealthAtlasSinusMotion.heightReveal(t)
    line(x, top, x, bottom, 0xB5A394, 1)
    line(x - 5, top, x + 7, top, Self.sienna, 1.5)
    line(x - 5, bottom, x + 7, bottom, Self.sienna, 1.5)
    line(x, bottom, x, end, Self.sienna, 2.8)
    disc(x, end, 3.1, Self.sienna, border: Self.cream)
    if t > 0.21 {
      let radius = 8 + 3 * GalaxySSIHealthAtlasSinusMotion.heightReveal(t)
      stroke(Path(ellipseIn: CGRect(x: 205 - radius, y: 149 - radius, width: 2 * radius, height: 2 * radius)), Self.sienna, 1.4)
    }
  }
}

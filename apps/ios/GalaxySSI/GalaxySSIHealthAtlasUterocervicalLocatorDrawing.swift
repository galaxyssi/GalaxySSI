import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func uterocervicalLocator(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasUterocervicalLocatorGeometry.self
    uterocervicalSurface(g.locatorVagina, 148, 280, 0xEAD4DF, 0xB489A4, 0x765870)
    fill(g.locatorVaginalSpace, 0xFFF5E7); stroke(g.locatorVaginalSpace, 0x765870, 1)
    line(100, 269, 108, 269, 0xFFF5E7, 2.3)
    uterocervicalSurface(g.locatorCervix, 105, 263, 0xF6DBC0, 0xC8927D, 0x916652)
    uterocervicalSurface(g.locatorUterus, 64, 167, 0xF7C5AE, 0xCA8C8E, 0x89535D)
    fill(g.locatorCavity, 0xFFF5E7); stroke(g.locatorCavity, 0x89535D, 1)
    stroke(g.locatorWallTexture, 0xAA7482, 1)
    stroke(g.locatorCanal, 0x916652, 6); stroke(g.locatorCanal, 0xFFF5E7, 4.2); stroke(g.locatorOs, 0x916652, 1)
    stroke(step == 0 ? g.locatorUterus : step == 1 ? g.locatorCervix : g.locatorVagina, 0x24776D, 1.6)
    uterocervicalTrace(g.tracks[step], GalaxySSIHealthAtlasUterocervicalMotion.sweep(t))
    line(49, 304, 103, 304, 0x24776D, 1.1)
    let owners = ["uterus", "cervix", "vagina"]
    label("uterocervical_locator_" + owners[step], 76, 326, 108)
  }
}

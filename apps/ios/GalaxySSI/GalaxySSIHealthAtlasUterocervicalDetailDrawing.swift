import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func uterocervicalUterus(_ t: Double) {
    let g = GalaxySSIHealthAtlasUterocervicalWallGeometry.self
    uterocervicalSurface(g.wallSurface, 106, 275, 0xFFDCCB, 0xECAD9F, 0x89535D)
    uterocervicalSurface(g.wallMuscle, 111, 273, 0xE7A598, 0xC4808E, 0xA5636D)
    var local = context; local.clip(to: g.wallMuscle)
    copy(local).stroke(g.wallFibers, 0xCC8586, 1.2)
    uterocervicalSurface(g.wallLining, 106, 275, 0xFFDCCB, 0xECAD9F, 0x89535D)
    stroke(g.wallGlands, 0xAC6573, 1.3)
    for (index, rim) in g.wallRims.enumerated() {
      let emphasis = GalaxySSIHealthAtlasUterocervicalMotion.wallEmphasis(t, layer: index)
      if emphasis > 0 {
        var focus = context; focus.opacity = Double(Int(180 * emphasis)) / 255
        copy(focus).stroke(rim, 0x24776D, 1.2 + 4 * emphasis)
      }
    }
    uterocervicalCallout("endometrium", 293, 83, 103, 294, 92, 287, 132)
    uterocervicalCallout("perimetrium", 199, 313, 92, 197, 297, 188, 238)
    uterocervicalCallout("myometrium", 286, 328, 105, 272, 312, 242, 226)
  }
  func uterocervicalCervix(_ t: Double) {
    let g = GalaxySSIHealthAtlasUterocervicalCanalGeometry.self
    uterocervicalSurface(g.upperVagina, 104, 270, 0xF5DAE0, 0xD8A5BD, 0x765870)
    uterocervicalSurface(g.neck, 105, 263, 0xF6DBC0, 0xC8927D, 0x916652)
    stroke(g.neckCollagen, 0xC29387, 1.3); stroke(g.canalFolds, 0xB87D67, 1.4)
    fill(g.canalSpace, 0xFFF5E7); stroke(g.canalSpace, 0x916652, 1.2)
    line(245, 253, 252, 253, 0xFFF5E7, 2.6)
    uterocervicalTrace(g.track, GalaxySSIHealthAtlasUterocervicalMotion.sweep(t))
    uterocervicalCallout("internal_os", 207, 75, 100, 212, 83, 244, 122)
    uterocervicalCallout("canal", 293, 316, 86, 299, 299, 257, 194)
    uterocervicalCallout("external_os", 205, 316, 82, 207, 300, 248, 253)
  }
}

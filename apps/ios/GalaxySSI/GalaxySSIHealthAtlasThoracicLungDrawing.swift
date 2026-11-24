import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thoracicFrontLung(_ b: Double, heartSide: Bool) {
    let g = GalaxySSIHealthAtlasThoracicLungGeometry.self
    thoracicWashed(g.front(b, heartSide: heartSide), 75, 255, 0xE3EFF5, 0xADC9DB, 0x7F9FAE)
    stroke(g.frontDetail(b, heartSide: heartSide), 0x8CAEBA, 1.2)
    thoracicWashed(g.frontDiaphragm(b), 205, 261, 0xE6CACD, 0xB88395, 0x8B536B)
  }
  func thoracicProfileLung(_ b: Double) {
    let g = GalaxySSIHealthAtlasThoracicLungGeometry.self
    thoracicWashed(g.profile(b), 75, 255, 0xE3EFF5, 0xADC9DB, 0x7F9FAE)
    stroke(g.profileDetail(b), 0x8CAEBA, 1.2)
    thoracicWashed(g.profileDiaphragm(b), 205, 261, 0xE6CACD, 0xB88395, 0x8B536B)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ductBufferMixing(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasDuctBufferGeometry
    typealias Motion = GalaxySSIHealthAtlasDuctBufferMotion
    typealias Routes = GalaxySSIHealthAtlasDuctBufferRoutes
    ductBufferBowel(Geometry.bufferBowel, 68)
    for i in 0...5 {
      let x = 68 + Double(i) * 42, y = i < 3 ? 203.0 : 220.0
      line(x, y + 4, x + 4, y - 3, 0xB47C72, 1.3)
    }
    stroke(Geometry.bufferBowel, 0xF1CB96, 23)
    ductBufferTube(Geometry.bufferInlet, 22, 14)
    let mixed = Motion.buffering(t)
    if mixed > 0 {
      let front = Routes.mixingTrack.path.trimmedPath(from: 0, to: mixed)
      stroke(front, 0xDEC99E, 22); stroke(front, 0xC9D6BB, 14)
    }
    for i in 0...6 {
      let p = 0.05 + Double(i) * 0.129 + Motion.delivery(t) * 0.115
      at(Routes.acidStream.route, p) { x, y in
        let reached = x >= 196 && x <= 200 + 110 * mixed
        if !reached || i % 2 == 0 { ductBufferAcidMark(x, y + Double(i % 3 - 1) * 4, 0.63, muted: reached) }
      }
    }
    let inlet = Motion.bufferInflow(t)
    for i in 0...3 {
      let f = 0.17 + 0.82 * inlet - Double(i) * 0.19
      if f >= 0 { at(Routes.inflowTrack.route, f) { x, y in ductBufferFluidMark(x, y, scale: 0.84) } }
    }
    if mixed > 0 { at(Routes.mixingTrack.route, mixed * 0.77) { x, y in ductBufferFluidMark(x, y) } }
  }
}

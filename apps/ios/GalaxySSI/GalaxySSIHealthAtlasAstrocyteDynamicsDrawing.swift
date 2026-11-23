import SwiftUI

private typealias AstrocyteMotion = GalaxySSIHealthAtlasAstrocyteMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func astrocyteDynamics(step: Int, t: Double) {
    switch step {
    case 0:
      for i in 0...2 {
        let f = AstrocyteMotion.signal(t, index: i)
        if f > 0 { at(AstrocyteMotion.signalRoutes[i], f) { astrocyteGlutamate($0, $1) } }
      }
      let response = AstrocyteMotion.travel(t, start: 0.58, duration: 0.19)
      if response > 0 {
        let x = 134 - response * 16, y = 171 + response * 17, r = 5 + 9 * response
        oval(x - r, y - r * 0.63, x + r, y + r * 0.63, fill: 0xFAE0AB, border: 0xC0874E)
      }
    case 1:
      for i in 0...2 { at(AstrocyteMotion.uptakeRoutes[i], AstrocyteMotion.uptake(t, index: i)) { astrocyteGlutamate($0, $1) } }
    case 2:
      for i in 0...2 {
        let f = AstrocyteMotion.conversion(t, index: i)
        at(AstrocyteMotion.conversionRoutes[i], f) { x, y in
          if f < 0.58 { astrocyteGlutamate(x, y) } else { astrocyteGlutamine(x, y) }
        }
      }
    case 3:
      for i in 0...2 {
        let f = AstrocyteMotion.recycle(t, index: i)
        if f < 1 { at(AstrocyteMotion.returnRoutes[i], f) { astrocyteGlutamine($0, $1) } }
        else { disc(112 + Double(i) * 3, 91 + Double(i % 2) * 3, 1.9, Self.sienna) }
      }
    case 4:
      for i in 0...2 {
        let f = AstrocyteMotion.buffer(t, index: i)
        if f < 1 { at(AstrocyteMotion.bufferRoutes[i], f) { astrocytePotassium($0, $1) } }
      }
      astrocytePotassium(308, 229 + 2 * wave(t)); astrocytePotassium(168, 184 - 2 * wave(t))
    default: break
    }
  }
  func astrocyteGlutamate(_ x: Double, _ y: Double) { disc(x, y, 3.7, Self.sienna, border: Self.cream) }
  func astrocyteGlutamine(_ x: Double, _ y: Double) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local), diamond = GalaxySSIHealthAtlasAstrocyteShapes.diamond
    art.fill(diamond, Self.violet); art.stroke(diamond, Self.cream, 1.1)
  }
  func astrocytePotassium(_ x: Double, _ y: Double) {
    disc(x, y, 4.9, Self.blue, border: Self.cream)
    line(x - 2, y, x + 2, y, Self.cream, 1); line(x, y - 2, x, y + 2, Self.cream, 1)
  }
}

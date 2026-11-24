import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealOrient(_ t: Double) {
    let zoom = GalaxySSIHealthAtlasPinealMotion.zoom(t), size = 0.91+0.57*zoom
    let x = 242-32*zoom-249*size, y = 180-146*size
    var c = context; c.clip(to: Path(CGRect(x: 12, y: 45, width: 336, height: 248)))
    copy(c).pinealBrain(x, y, size)
    let pinealX = x+249*size
    stroke(Path(ellipseIn: CGRect(x: pinealX-20*size, y: 180-12*size, width: 40*size, height: 24*size)), 0xFCF7FF, 1.6)
  }
  func pinealRetinalInput(_ t: Double) {
    let g = GalaxySSIHealthAtlasPinealGeometry.self, r = GalaxySSIHealthAtlasPinealRoutes.self
    pinealBrain(159, 100, 0.53); pinealSun(41, 98, 9)
    gradient(g.opticWall, 126, 213, 0xFBFBFB, 0xC7DBE6); stroke(g.opticWall, 0x637E8B, 1.5)
    fill(g.vitreous, 0xE3F3F7)
    oval(47, 150, 61, 189, fill: 0xCEE8E9, border: 0x7B9CA9)
    line(42, 151, 42, 162, 0x55727D, 2.5); line(42, 176, 42, 187, 0x55727D, 2.5)
    stroke(g.retinaEdge, 0x9E747D, 4.3); stroke(g.retinaEdge, 0xF3C9C8, 1.45)
    let light = GalaxySSIHealthAtlasPinealMotion.zoom(min(1, t*2.55))
    for ray in [r.ray0, r.ray1, r.ray2] { pinealSegment(ray, light, 0xB98639, 1.55) }
    stroke(g.retinaFiber, 0xD5E7EB, 7); stroke(g.retinaFiber, 0x8CAEB0, 2.5)
    for i in 0...2 {
      let f = GalaxySSIHealthAtlasPinealMotion.retinalSignal(t, i)
      if f > 0 && f < 1 { at(r.retinaTrack.route, f) { x, y in disc(x, y, 3.7, 0x267D78, border: 0xFAFFFF) } }
    }
    let arrival = GalaxySSIHealthAtlasPinealMotion.retinalSignal(t, 0)
    disc(221, 184, 4.7+2.1*arrival, 0x267D78, border: 0xFAFFFF)
  }
}

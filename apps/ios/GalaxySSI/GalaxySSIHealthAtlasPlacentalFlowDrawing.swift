import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func placentalFlows(_ t: Double, _ routeChapter: Bool) {
    let g = GalaxySSIHealthAtlasPlacentalGeometry.self, r = GalaxySSIHealthAtlasPlacentalRoutes.self
    let maternal: UInt32 = routeChapter ? 0xA66070 : 0xBD8990, fetal: UInt32 = routeChapter ? 0x3E7582 : 0x6A949B
    context.stroke(g.maternalRoute,with:.color(Self.color(maternal)),
      style:StrokeStyle(lineWidth:1.35,lineCap:.round,lineJoin:.round,dash:[3,4],dashPhase:0))
    placentalRouteArrow(r.maternal,0.10,maternal); placentalRouteArrow(r.maternal,0.89,maternal)
    placentalRouteArrow(r.fetal,0.08,fetal); placentalRouteArrow(r.fetal,0.87,fetal)
    let count = routeChapter ? 3 : 2
    for i in 0..<count {
      let progress = GalaxySSIHealthAtlasPlacentalMotion.stream(t,i)
      let size = min(1,progress*12,(1-progress)*12)
      if size > 0 {
        at(r.maternal.route,progress) { x,y in oval(x-4.1*size,y-2.6*size,x+4.1*size,y+2.6*size,fill:0xE3A7A9,border:maternal) }
        at(r.fetal.route,progress) { x,y in oval(x-4.1*size,y-2.6*size,x+4.1*size,y+2.6*size,fill:0xD9E9E5,border:fetal) }
      }
    }
  }
  private func placentalRouteArrow(_ track: GalaxySSIHealthAtlasPlacentalRoutes.Track, _ fraction: Double, _ color: UInt32) {
    guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(track.route,position:fraction,width:360,height:360) else { return }
    let x = Double(sample.point.x), y = Double(sample.point.y), dx = Double(sample.direction.dx), dy = Double(sample.direction.dy)
    arrow(x-6*dx,y-6*dy,x+6*dx,y+6*dy,color)
  }
}

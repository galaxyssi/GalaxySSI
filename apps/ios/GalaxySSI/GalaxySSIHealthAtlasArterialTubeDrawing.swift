import SwiftUI

private typealias ArterialTube = GalaxySSIHealthAtlasArterialMotion
private typealias ArterialTubeInk = GalaxySSIHealthAtlasArterialShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func arterialTube(step: Int, t: Double) {
    let layers: [(Double, Double, Double, UInt32, UInt32)] = [
      (16,199,299,0xF4D4BF,0xDEA392), (11,205,292,0xECA8A0,0xCC7680),
      (3,216,285,0xF4C0A9,0xE09487), (0,223,279,0xFFE1CE,0xEFADA5)
    ]
    for (offset, top, bottom, from, to) in layers {
      let path = ArterialTubeInk.path(ArterialTube.layer(step: step,t: t,offset: offset),closed: true)
      gradient(path,top,bottom,from,to)
    }
    for side in [-1.0,1] {
      for offset in ArterialTube.layerLines {
        let path = ArterialTubeInk.path(ArterialTube.lamella(step: step,t: t,offset: offset,side: side))
        stroke(path,offset == 0 || offset == 16 ? ArterialTubeInk.outline : 0xF5C4B0,1.1)
      }
    }
    for f in [0.0,1] {
      let r = ArterialTube.radius(step: step,t: t,location: f), x = ArterialTube.xAt(f)
      for side in [-1.0,1] {
        line(x,ArterialTube.tubeY + side * r,x,ArterialTube.tubeY + side * (r + 16),ArterialTubeInk.outline,1.5)
      }
    }
  }
  func arterialPulse(step: Int, t: Double, fraction: Double) {
    let x = ArterialTube.xAt(fraction), y = ArterialTube.tubeY - ArterialTube.radius(step: step,t: t,location: fraction) - 16
    stroke(ArterialTubeInk.arc(x - 12,y - 11,x + 12,y + 5,start: 207,sweep: 126),ArterialTubeInk.pulse,2.1)
    disc(x,y,2.5,ArterialTubeInk.pulse,border: Self.cream)
  }
  func arterialFlow(_ distance: Double) {
    for index in 0...3 {
      let point = ArterialTube.flow(distance: distance,index: index)
      arrow(point.x - 5,point.y,point.x + 7,point.y,ArterialTubeInk.blood)
    }
  }
  func arterialLegend() {
    arrow(43,329,63,329,ArterialTubeInk.blood); label("arterial_flow",108,333,76)
    disc(200,329,3.5,ArterialTubeInk.pulse); label("arterial_wave",265,333,111)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func deltoidBands(_ frame: GalaxySSIHealthAtlasDeltoidPose, _ step: Int, _ t: Double) {
    let m = GalaxySSIHealthAtlasDeltoidMotion.self
    let shades: [(Double,Double,UInt32,UInt32)] = [
      (110,230,0xD5C6E4,0xAE97C5), (106,231,0xEDC6D7,0xC987A6), (114,224,0xF1D1C8,0xDBA099)
    ]
    for band in 0...2 {
      let l = band, r = band+1, pose = frame.amount
      let o = frame.origins, c = frame.controls, e = frame.ends, v = frame.tangents
      let cap = Path { p in
        p.move(to: o[l]); p.addCurve(to: e[l], control1: c[l], control2: v[l])
        p.addLine(to: e[r]); p.addCurve(to: o[r], control1: v[r], control2: c[r]); p.closeSubpath()
      }
      let shade = shades[band]
      deltoidTissue(cap, shade.0, shade.1, shade.2, shade.3, m.fiberInks[band])
      let reveal = step == 0 ? m.partFocus(band,t) : 0
      for row in 1...4 {
        let f = Double(row)/5
        let x = m.blend(e[l].x,e[r].x,f), y = m.blend(e[l].y,e[r].y,f)
        let fiber = Path { p in
          p.move(to: CGPoint(x: m.blend(o[l].x,o[r].x,f), y: m.blend(o[l].y,o[r].y,f)+4))
          p.addCurve(to: CGPoint(x: x-2*pose, y: y-4*(1-pose)),
            control1: CGPoint(x: m.blend(c[l].x,c[r].x,f), y: m.blend(c[l].y,c[r].y,f)),
            control2: CGPoint(x: m.blend(v[l].x,v[r].x,f), y: m.blend(v[l].y,v[r].y,f)))
        }
        stroke(fiber, row % 2 == 0 ? 0xAAFFF4F7 : m.fiberInks[band],
          0.85+0.85*reveal+(step == 1 && band == 1 ? 0.65*pose : 0))
      }
    }
  }
}

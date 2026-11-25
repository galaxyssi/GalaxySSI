import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func obliqueAnatomy(_ motion: GalaxySSIHealthAtlasObliqueMotion) {
    let g = GalaxySSIHealthAtlasObliqueGeometry.self
    obliqueTissue(g.pelvis,101,251,0xFCF6E7,0xD6C9B8,0x928572,evenOdd:true)
    stroke(g.hipContours,0xAE9B85,1.5)
    var c = context; c.translateBy(x:180,y:177); c.rotate(by:.degrees(motion.degrees)); c.translateBy(x:-180,y:-177)
    let art = copy(c)
    art.obliqueTissue(g.ribs,129,220,0xF9F5E9,0xDCE7E3,0x68878D)
    art.stroke(g.ribContours,0xC5BBA7,2.75); art.stroke(g.ribContours,0xF9F6EC,1.15)
    art.oval(169,199,191,212,fill:0xE7E0CF,border:0x928572)
    art.oval(176,127,184,150,fill:0xE3E9DD,border:0x68878D)
    art.line(180,148,180,194,0xA4B5B1,1.05)
  }
  func obliqueTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32, evenOdd: Bool = false) {
    context.fill(p,with:.linearGradient(Gradient(colors:[Self.color(from),Self.color(to)]),
      startPoint:CGPoint(x:0,y:top),endPoint:CGPoint(x:0,y:bottom)),style:FillStyle(eoFill:evenOdd))
    stroke(p,border,1.35)
  }
}

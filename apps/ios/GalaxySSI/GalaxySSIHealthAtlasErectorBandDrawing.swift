import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func erectorBands(_ motion: GalaxySSIHealthAtlasErectorMotion) {
    let g = GalaxySSIHealthAtlasErectorGeometry.self
    erectorBand(g.trace(motion.flexion,-23,77,258),0x896D91,0xD8C3D6,motion.emphasis)
    erectorBand(g.trace(motion.flexion,-16,71,258),0xA3667C,0xE9BBC2,motion.emphasis)
  }
  private func erectorBand(_ p: Path, _ edge: UInt32, _ fill: UInt32, _ emphasis: Double) {
    stroke(p,edge,7.3); stroke(p,fill,5)
    var c = context; c.opacity = Double(Int(25+155*emphasis))/255
    copy(c).stroke(p,edge,2.8)
  }
  func erectorExtension(_ ease: Double) {
    let g = GalaxySSIHealthAtlasErectorGeometry.self
    stroke(g.extensionArc,0x85A9B8,1.3)
    at(g.extensionRoute,ease) { x,y in disc(x,y,3.3,Self.blue,border:Self.cream) }
    arrow(151,44,139,50,Self.blue)
  }
}

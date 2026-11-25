import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func erectorTrunk(_ flexion: Double) {
    let g = GalaxySSIHealthAtlasErectorGeometry.self, m = GalaxySSIHealthAtlasErectorMotion.self
    erectorTissue(g.trunk(flexion),62,292,0xE8F3EF,0xCBDEE0,0x97B1B2)
    erectorTissue(g.pelvis,218,296,0xFBF3E3,0xBDCFC9,0x7E9898)
    erectorTissue(g.sacrum,218,296,0xFBF3E3,0xBDCFC9,0x7E9898)
    oval(177,255,204,282,fill:0xC9D9D5,border:0x7E9898)
    stroke(g.trace(flexion,0,72,252),0x7E9898,3)
    for y in stride(from:76.0,through:244,by:14) {
      let x = m.spineX(y,flexion), tilt = atan2(m.spineX(y+1,flexion)-x,1)*(-180 / .pi)
      var c = context; c.translateBy(x:x,y:y); c.rotate(by:.degrees(tilt))
      let art = copy(c)
      art.oval(-9,-5.6,11,5.6,fill:0xF6F0DF,border:0x7E9898)
      art.line(-9,0,-15,3,0x7E9898,1.4)
    }
  }
  func erectorSupport() {
    rounded(84,112,122,201,11,0x8AAEA9); rounded(88,116,115,197,8,0xC3DFD6)
    line(92,198,92,267,0x87A7A7,4)
    erectorKey("erector_support_story_contact",59,98,107,131,Self.teal,100)
  }
  func erectorLoad() {
    line(222,121,278,121,Self.blue,2)
    rounded(262,87,295,120,5,0x8EB2C3); rounded(266,91,291,105,3,0xC5DCE4)
    arrow(279,124,279,163,Self.blue)
    label("erector_support_story_external",279,69,118)
  }
  private func erectorTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,border,1.4)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func scapularFoundation(_ frame: GalaxySSIHealthAtlasScapularPose, _ step: Int) {
    let g = GalaxySSIHealthAtlasScapularGeometry.self
    scapularTissue(g.back, 51, 304, 0xE1EDED, 0xCCDCDE, 0xA4B7BD)
    for rib in g.ribs { stroke(rib,0xA4B8BD,8.5); stroke(rib,0xF3F4E8,6) }
    for i in 0...10 {
      let y = 77+Double(i)*18
      oval(106,y,119,y+16,fill:0xE9E9DC,border:0xACB4AA)
    }
    if step == 3 || step == 4 { stroke(g.blade,0x9BAAB1,1.1) }
  }
  func scapularBones(_ frame: GalaxySSIHealthAtlasScapularPose) {
    let g = GalaxySSIHealthAtlasScapularGeometry.self, x = frame.points[0].x, y = frame.points[0].y
    let clavicle = Path { p in
      p.move(to: CGPoint(x:x-31,y:y+6))
      p.addQuadCurve(to: CGPoint(x:x+7,y:y-5),control:CGPoint(x:x-15,y:y-7))
      p.addQuadCurve(to: CGPoint(x:x+8,y:y+5),control:CGPoint(x:x+15,y:y-1))
      p.addQuadCurve(to: CGPoint(x:x-31,y:y+11),control:CGPoint(x:x-8,y:y+4)); p.closeSubpath()
    }
    scapularTissue(clavicle,109,249,0xF8F6ED,0xBCCFD4,0x6E8C94)
    var arm = context; arm.concatenate(frame.arm)
    copy(arm).scapularTissue(g.arm,109,249,0xF8F6ED,0xBCCFD4,0x6E8C94)
    var blade = context; blade.concatenate(frame.turn)
    let art = copy(blade)
    art.scapularTissue(g.blade,109,249,0xF8F6ED,0xBCCFD4,0x6E8C94)
    art.stroke(g.ridge,0x829CA3,1.9); art.oval(247,135,254,151,fill:0xCADCDF,border:0x6E8C94)
  }
  func scapularTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,border,1.45)
  }
}

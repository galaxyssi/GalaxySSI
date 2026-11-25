import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func scapularLabels(_ frame: GalaxySSIHealthAtlasScapularPose, _ step: Int, _ t: Double) {
    let m = GalaxySSIHealthAtlasScapularMotion.self, pts = frame.points
    if step == 0 || step == 1 {
      scapularKey("scapular_rotation_story_upper",53,74,116,76,0x9C5F79,step == 0 ? m.regionFocus(0,t) : 0)
      scapularKey("scapular_rotation_story_middle",47,137,137,132,0x846280,step == 0 ? m.regionFocus(1,t) : 0)
    }
    if step <= 2 {
      scapularKey("scapular_rotation_story_lower",59,250,129,224,0x735D8C,step == 0 ? m.regionFocus(2,t) : 0)
      scapularKey("scapular_rotation_story_serratus",282,309,260,233,0x477E79,step == 0 ? m.regionFocus(3,t) : 0)
    }
    if step == 1 { scapularKey("scapular_rotation_story_clavicle_label",280,70,pts[0].x,pts[0].y,0x9C5F79) }
    if step >= 2 { scapularKey("scapular_rotation_story_inferior_angle",202,328,pts[4].x,pts[4].y,Self.blue) }
  }
  func scapularKey(_ key: String, _ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ color: UInt32, _ focus: Double = 0) {
    if focus > 0 {
      var c = context; c.opacity = Double(Int(180*focus))/255
      copy(c).stroke(Path(ellipseIn:CGRect(x:tx-5-5*focus,y:ty-5-5*focus,width:10+10*focus,height:10+10*focus)),color,1.5)
    }
    let edge = ty > y ? y+7 : y-17
    line(x,edge,tx,ty,color,1.1); disc(tx,ty,3,color,border:Self.cream)
    label(key,x,y,x < 80 ? 86 : 108)
  }
}

import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func obliqueLabels(_ motion: GalaxySSIHealthAtlasObliqueMotion) {
    label("oblique_rotation_story_anterior",180,47,90)
    label("oblique_rotation_story_body_left",58,70,101)
    label("oblique_rotation_story_body_right",302,70,101)
    obliqueLeader("oblique_rotation_story_left_external",65,109,105,motion.bands[0].focus,0x9B5B63)
    obliqueLeader("oblique_rotation_story_right_external",295,109,255,motion.bands[2].focus,0x9B5B63)
    obliqueLeader("oblique_rotation_story_left_internal",65,274,104,motion.bands[1].focus,0x665A88)
    obliqueLeader("oblique_rotation_story_right_internal",295,274,256,motion.bands[3].focus,0x665A88)
    obliqueLeader("oblique_rotation_story_pelvis",180,312,180,CGPoint(x:180,y:244),0x928572)
  }
  private func obliqueLeader(_ key: String, _ x: Double, _ y: Double, _ elbow: Double, _ target: CGPoint, _ color: UInt32) {
    let tx = Double(target.x), ty = Double(target.y), edge = ty > y ? y+6 : y-17
    line(x,edge,elbow,edge,color,1.05); line(elbow,edge,tx,ty,color,1.05)
    disc(tx,ty,2.75,color,border:Self.cream); label(key,x,y,110)
  }
}

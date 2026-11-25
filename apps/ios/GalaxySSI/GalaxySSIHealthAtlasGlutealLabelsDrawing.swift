import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glutealAttachmentLabels() {
    glutealKey("gluteal_extension_story_gluteus",64,208,CGPoint(x:132,y:178),0x9E617A,110)
    glutealKey("gluteal_extension_story_pelvis_label",284,103,CGPoint(x:220,y:125),0x779095,113)
    glutealKey("gluteal_extension_story_socket",287,170,CGPoint(x:190,y:173),Self.blue,107)
    glutealKey("gluteal_extension_story_femoral_attachment",266,254,CGPoint(x:164,y:219),0x9E617A,128)
    label("gluteal_extension_story_lateral",181,32,216)
  }
  func glutealCompareLabels() {
    label("gluteal_extension_story_hip_motion",94,71,142)
    label("gluteal_extension_story_spine_motion",275,71,142)
    label("gluteal_extension_story_hip_angle_changes",94,277,146)
    label("gluteal_extension_story_hip_angle_fixed",275,277,146)
  }
  func glutealKey(_ key: String, _ x: Double, _ y: Double, _ target: CGPoint, _ color: UInt32, _ width: Double) {
    let tx=Double(target.x), ty=Double(target.y)
    line(x,ty > y ? y+6 : y-15,tx,ty,color,1.1)
    disc(tx,ty,3,color,border:Self.cream); label(key,x,y,width)
  }
}

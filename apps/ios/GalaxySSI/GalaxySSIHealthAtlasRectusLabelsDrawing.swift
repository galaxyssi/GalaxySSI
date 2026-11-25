import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func rectusLabels(_ motion: GalaxySSIHealthAtlasRectusMotion) {
    rectusLeader("rectus_flexion_story_costal",295,92,282,216,132,0x998A77,116,motion)
    rectusLeader("rectus_flexion_story_lumbar",63,183,99,145,210,Self.blue,103,motion)
    rectusLeader("rectus_flexion_story_belly",299,222,272,219,209,0xA06269,112,motion)
    rectusLeader("rectus_flexion_story_pubis",276,303,242,209,260,0xA06269,118,motion)
    rectusLeader("rectus_flexion_story_pelvis",77,326,109,138,274,0x998A77,112,motion)
  }
  private func rectusLeader(_ key: String, _ x: Double, _ y: Double, _ elbow: Double,
    _ tx: Double, _ ty: Double, _ color: UInt32, _ width: Double, _ motion: GalaxySSIHealthAtlasRectusMotion) {
    let mapped = motion.point(tx,ty), edge = ty > y ? y+6 : y-17
    line(x,edge,elbow,edge,color,1.05); line(elbow,edge,mapped.x,mapped.y,color,1.05)
    disc(mapped.x,mapped.y,2.75,color,border:Self.cream); label(key,x,y,width)
  }
}

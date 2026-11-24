import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glutealScene(_ step: Int, _ t: Double) {
    let ease = GalaxySSIHealthAtlasGlutealPose.ease(t), g = GalaxySSIHealthAtlasGlutealGeometry.self
    switch step {
    case 0:
      glutealAnatomy(.init(0,0),0)
      let focus = (1+wave(t-0.25))/2, r = 6+3*focus
      var c = context; c.opacity = Double(Int(80+120*focus))/255
      copy(c).stroke(Path(ellipseIn:CGRect(x:164-r,y:219-r,width:2*r,height:2*r)),0x9E617A,1.4)
      glutealAttachmentLabels()
    case 1:
      glutealGhost(g.femur,-32)
      let frame = GalaxySSIHealthAtlasGlutealPose(0,-32+44*ease)
      glutealAnatomy(frame,0); glutealSweep(150,58,44,ease)
      glutealKey("gluteal_extension_story_pelvis_fixed",286,92,CGPoint(x:221,y:125),0x779095,110)
      glutealKey("gluteal_extension_story_femur_moves",76,246,CGPoint(x:162,y:262).applying(frame.femur),Self.blue,114)
    case 2:
      glutealGhost(g.ilium,29)
      let frame = GalaxySSIHealthAtlasGlutealPose(29-44*ease,0)
      glutealAnatomy(frame,0); glutealSweep(131,-61,-44,ease)
      glutealKey("gluteal_extension_story_pelvis_moves",293,218,CGPoint(x:218,y:139).applying(frame.pelvis),Self.blue,110)
      glutealKey("gluteal_extension_story_femur_fixed",248,307,CGPoint(x:164,y:269),0x779095,104)
    default: glutealCompare(ease)
    }
  }
  private func glutealCompare(_ ease: Double) {
    line(180,76,180,275,0xBBCECB,1.1)
    var left = context; left.translateBy(x:-8,y:70); left.scaleBy(x:0.54,y:0.54)
    let l = copy(left)
    l.glutealGhost(GalaxySSIHealthAtlasGlutealGeometry.femur,-32)
    l.glutealAnatomy(.init(0,-32+44*ease),0); l.glutealSweep(150,58,44,ease)
    var right = context; right.translateBy(x:173,y:70); right.scaleBy(x:0.54,y:0.54)
    let r = copy(right)
    r.glutealLumbar(1,ghost:true); r.glutealAnatomy(.init(0,0),1-ease)
    r.arrow(182,49,147,49,Self.teal)
    glutealCompareLabels()
  }
}

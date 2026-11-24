import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func erectorPosteriorLabels() {
    erectorKey("erector_spinae_plate_spinalis",61,89,168,80+42,0x896D91,88)
    erectorKey("erector_spinae_plate_longissimus",302,119,206,127+42,0xA3667C,94)
    erectorKey("erector_spinae_plate_iliocostalis",307,233,223,154+42,Self.coral,88)
    erectorKey("erector_spinae_plate_origin",169,328,171,218+42,0x7E9898,116)
  }
  func erectorSideLabels(_ step: Int, _ motion: GalaxySSIHealthAtlasErectorMotion) {
    let spineX = GalaxySSIHealthAtlasErectorMotion.spineX
    if step == 1 {
      erectorKey("erector_support_story_paired",61,194,spineX(185,motion.flexion)-19,185,0xA3667C,105)
      erectorKey("erector_support_story_fixed_pelvis",203,329,189,269,0x7E9898,112)
    } else {
      erectorKey("erector_support_story_neutral_curve",195,329,spineX(222,0),222,Self.blue,138,bendX:242)
    }
  }
  func erectorKey(_ key: String, _ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ color: UInt32, _ maxWidth: Double, bendX: Double? = nil) {
    let edge = ty > y ? y+6 : y-15, bend = bendX ?? x
    if bend != x { line(x,edge,bend,edge,color,1.1) }
    line(bend,edge,tx,ty,color,1.1); disc(tx,ty,3,color,border:Self.cream)
    label(key,x,y,maxWidth)
  }
}

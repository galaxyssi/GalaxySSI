import SwiftUI

private typealias EndometriumLabels = GalaxySSIHealthAtlasEndometriumGeometry

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endometriumLabels(_ step: Int) {
    endometriumCallout("endometrium_story_label_uterus",left: true,y: 49,anchorX: 153,anchorY: 52)
    endometriumCallout("endometrium_story_label_cavity",left: false,y: 132,anchorX: 244,anchorY: 132)
    endometriumCallout("endometrium_story_label_basal",left: true,y: 263,anchorX: 114,anchorY: 260)
    endometriumCallout("endometrium_story_label_muscle",left: true,y: 309,anchorX: 116,anchorY: 305)
    if step == 0 { endometriumCallout("endometrium_story_label_functional",left: true,y: 201,anchorX: 115,anchorY: 203) }
    if step == 1 || step == 2 { endometriumCallout("endometrium_story_label_stroma",left: false,y: 211,anchorX: 245,anchorY: step == 1 ? 250 : 216) }
    switch step {
    case 3: endometriumCallout("endometrium_story_label_gland_base",left: false,y: 263,anchorX: 230,anchorY: 268)
    case 4: endometriumCallout("endometrium_story_label_surface",left: false,y: 224,anchorX: 232,anchorY: 243)
    default: endometriumCallout("endometrium_story_label_gland",left: false,y: 263,anchorX: 234,anchorY: 262)
    }
  }
  private func endometriumCallout(_ key: String, left: Bool, y: Double, anchorX: Double, anchorY: Double) {
    let x = left ? 51.0 : 309.0, start = left ? 61.0 : 299.0, elbow = left ? 101.0 : 259.0
    line(start,y + 5,elbow,y + 5,EndometriumLabels.leader,1.05); line(elbow,y + 5,anchorX,anchorY,EndometriumLabels.leader,1.05)
    disc(anchorX,anchorY,1.9,EndometriumLabels.leader,border: Self.cream); label(key,x,y,89)
  }
}

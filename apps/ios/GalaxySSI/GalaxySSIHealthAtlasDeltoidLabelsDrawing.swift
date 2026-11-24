import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func deltoidLabels(_ frame: GalaxySSIHealthAtlasDeltoidPose, _ step: Int, _ t: Double) {
    if step == 0 {
      deltoidPart("deltoid_story_spinal", 71, 60, 98, 0, t, frame)
      deltoidPart("deltoid_story_acromial", 176, 47, 178, 1, t, frame)
      deltoidPart("deltoid_story_clavicular", 288, 68, 263, 2, t, frame)
    } else {
      if step >= 2 {
        deltoidCallout("deltoid_story_blade", 66, 215, 99, frame.bladeAnchor.x, frame.bladeAnchor.y, Self.blue)
      }
      deltoidSweep(frame, lowering: step == 3)
    }
    deltoidCallout("deltoid_story_tuberosity", 271, 325, 265, frame.ends[2].x, frame.ends[2].y, 0x9E607F)
  }
  private func deltoidPart(_ key: String, _ x: Double, _ y: Double, _ elbow: Double,
    _ band: Int, _ t: Double, _ frame: GalaxySSIHealthAtlasDeltoidPose) {
    let m = GalaxySSIHealthAtlasDeltoidMotion.self
    let tx = m.blend(frame.origins[band].x,frame.origins[band+1].x,0.53)
    let ty = m.blend(frame.origins[band].y,frame.origins[band+1].y,0.53)+3
    let focus = m.partFocus(band,t), color = m.fiberInks[band]
    if focus > 0 {
      var c = context; c.opacity = Double(Int(180*focus))/255
      copy(c).stroke(Path(ellipseIn: CGRect(x: tx-5-5*focus, y: ty-5-5*focus, width: 10+10*focus, height: 10+10*focus)), color, 1.5)
    }
    deltoidCallout(key,x,y,elbow,tx,ty,color)
  }
  private func deltoidCallout(_ key: String, _ x: Double, _ y: Double, _ elbow: Double,
    _ tx: Double, _ ty: Double, _ color: UInt32) {
    let edge = ty > y ? y+7 : y-17
    line(x,edge,elbow,edge,color,1.1); line(elbow,edge,tx,ty,color,1.1)
    disc(tx,ty,3,color,border: Self.cream); label(key,x,y,124)
  }
}

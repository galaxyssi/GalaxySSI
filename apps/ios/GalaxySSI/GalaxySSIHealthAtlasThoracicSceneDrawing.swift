import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thoracicScene(_ step: Int, _ b: Double) {
    let m = GalaxySSIHealthAtlasThoracicMotion.self
    switch step {
    case 0:
      thoracicFront(b)
      thoracicCallout("thoracic_frame_story_art_sternum", 180, 30, 110, 180, 70-6*b)
      thoracicCallout("thoracic_frame_story_art_ribs", 65, 57, 106,
        180-m.frontX(m.lateral[2],b), m.frontY(m.lateral[2],m.outerY(2),b))
      thoracicCallout("thoracic_frame_story_art_cartilage", 260, 302, 151,
        180+m.frontX(m.join[8],b), m.frontY(m.join[8],m.joinY(8),b), below: true)
      label("thoracic_frame_story_art_front", 180, 337, 144)
    case 1:
      thoracicProfile(b, cutaway: false)
      thoracicCallout("thoracic_frame_story_art_joint", 85, 29, 153, m.rearX(2), m.rearY(2))
      thoracicCallout("thoracic_frame_story_art_sternum", 265, 29, 115, m.sideSternumX(77,b), 77-9*b)
      let x = m.sideSternumX(116,b), y = 116-9*b
      arrow(x+13, y+14, x+33, y-6, 0x8B536B)
      label("thoracic_frame_story_art_side", 180, 284, 120)
      thoracicAxis(180, 306, 129, 57+58*b, 0x8B536B, "thoracic_frame_story_art_depth")
    case 2:
      thoracicFront(b, bucket: true)
      thoracicCallout("thoracic_frame_story_art_sternum", 180, 30, 110, 180, 70-6*b)
      let radius = m.frontX(m.lateral[7],b), y = m.frontY(m.lateral[7],m.outerY(7),b)
      for side in [-1.0,1.0] { arrow(180+side*(radius+4), y+10, 180+side*(radius+25), y-9, 0x2C766E) }
      thoracicCallout("thoracic_frame_story_art_side_ribs", 88, 278, 156, 180-radius, y, below: true)
      thoracicAxis(180, 306, 150, 70+64*b, 0x2C766E, "thoracic_frame_story_art_width")
    default: thoracicVolume(b, returning: step == 4)
    }
  }
  private func thoracicVolume(_ b: Double, returning: Bool) {
    let m = GalaxySSIHealthAtlasThoracicMotion.self
    if returning {
      thoracicProfile(b, cutaway: true)
      thoracicCallout("thoracic_frame_story_art_sternum", 265, 29, 115, m.sideSternumX(77,b), 77-9*b)
      let x = m.sideSternumX(128,b)
      arrow(x+36, 111-9*b, x+14, 130-9*b, 0x8B536B)
      arrow(210, 246+17*b, 210, 227+17*b, 0x466A9C)
    } else {
      thoracicFront(b, cutaway: true)
      thoracicCallout("thoracic_frame_story_art_chest_space", 80, 29, 153, 150-4*b, 115)
      thoracicCallout("thoracic_frame_story_art_sternum", 261, 29, 116, 180, 73-6*b)
      arrow(180, 253+13*b, 180, 270+13*b, 0x466A9C)
    }
    thoracicCallout("thoracic_frame_story_art_diaphragm", 279, 280, 139,
      returning ? 178 : 228+5*b, returning ? 210+17*b : 222+14*b, below: true)
    thoracicAxis(66, 306, 87, 39+35*b, 0x8B536B, "thoracic_frame_story_art_depth")
    thoracicAxis(180, 306, 87, 42+36*b, 0x2C766E, "thoracic_frame_story_art_width")
    thoracicAxis(294, 306, 87, 45+37*b, 0x466A9C, "thoracic_frame_story_art_height")
  }
}

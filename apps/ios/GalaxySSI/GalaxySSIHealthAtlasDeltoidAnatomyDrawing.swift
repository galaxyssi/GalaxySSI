import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func deltoidAnatomy(_ frame: GalaxySSIHealthAtlasDeltoidPose) {
    let g = GalaxySSIHealthAtlasDeltoidGeometry.self
    deltoidTissue(g.torso, 68, 315, 0xE5F0EE, 0xD3E3E1, 0xA5BCBC)
    var blade = context; blade.concatenate(frame.scapula)
    let art = copy(blade)
    art.deltoidTissue(g.blade, 113, 242, 0xDCECEF, 0xB5CFD4, 0x7D9699)
    art.stroke(g.ridge, 0x86A3AB, 2); art.stroke(g.bladeContour, 0xE6F1F1, 2)
    deltoidClavicle(frame)
    var arm = context; arm.concatenate(frame.arm)
    let limb = copy(arm)
    limb.deltoidTissue(g.arm, 68, 315, 0xE5F0EE, 0xD3E3E1, 0xA5BCBC)
    limb.deltoidTissue(g.humerus, 101, 277, 0xFFFBEF, 0xDFD7C3, 0x948777)
    limb.stroke(g.armContour, 0xB9AC94, 1.4)
  }
  func deltoidTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(p, top, bottom, from, to); stroke(p, border, 1.5)
  }
  private func deltoidClavicle(_ frame: GalaxySSIHealthAtlasDeltoidPose) {
    let x = frame.clavicleEnd.x, y = frame.clavicleEnd.y
    let p = Path { p in
      p.move(to: CGPoint(x: 102, y: 108))
      p.addCurve(to: CGPoint(x: x, y: y-4), control1: CGPoint(x: 144, y: 77), control2: CGPoint(x: x-43, y: y-33))
      p.addQuadCurve(to: CGPoint(x: x+1, y: y+7), control: CGPoint(x: x+8, y: y))
      p.addCurve(to: CGPoint(x: 106, y: 116), control1: CGPoint(x: x-41, y: y-18), control2: CGPoint(x: 148, y: 86))
      p.addQuadCurve(to: CGPoint(x: 102, y: 108), control: CGPoint(x: 99, y: 120)); p.closeSubpath()
    }
    deltoidTissue(p, 101, 277, 0xFFFBEF, 0xDFD7C3, 0x948777)
  }
}

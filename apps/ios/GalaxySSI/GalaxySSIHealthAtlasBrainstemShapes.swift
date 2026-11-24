import SwiftUI

enum GalaxySSIHealthAtlasBrainstemShapes {
  static let guide: UInt32 = 0x657482, neural: UInt32 = 0x69518E, quietNeural: UInt32 = 0xAD98BB
  static let movingAir: UInt32 = 0x356E8E, muscle: UInt32 = 0xAB5661
  static let body = Path { p in
    p.move(to: CGPoint(x: 151, y: 35))
    p.addCurve(to: CGPoint(x: 230, y: 56), control1: CGPoint(x: 172, y: 17), control2: CGPoint(x: 219, y: 22))
    p.addCurve(to: CGPoint(x: 224, y: 128), control1: CGPoint(x: 242, y: 89), control2: CGPoint(x: 218, y: 108))
    p.addQuadCurve(to: CGPoint(x: 245, y: 151), control: CGPoint(x: 226, y: 142))
    p.addCurve(to: CGPoint(x: 260, y: 248), control1: CGPoint(x: 268, y: 161), control2: CGPoint(x: 269, y: 208))
    p.addQuadCurve(to: CGPoint(x: 249, y: 307), control: CGPoint(x: 250, y: 277))
    p.addQuadCurve(to: CGPoint(x: 113, y: 307), control: CGPoint(x: 182, y: 324))
    p.addQuadCurve(to: CGPoint(x: 103, y: 248), control: CGPoint(x: 112, y: 278))
    p.addCurve(to: CGPoint(x: 127, y: 152), control1: CGPoint(x: 93, y: 205), control2: CGPoint(x: 97, y: 165))
    p.addQuadCurve(to: CGPoint(x: 153, y: 120), control: CGPoint(x: 151, y: 141))
    p.addQuadCurve(to: CGPoint(x: 147, y: 115), control: CGPoint(x: 154, y: 116))
    p.addQuadCurve(to: CGPoint(x: 138, y: 103), control: CGPoint(x: 137, y: 113))
    p.addLine(to: CGPoint(x: 135, y: 94))
    p.addQuadCurve(to: CGPoint(x: 128, y: 86), control: CGPoint(x: 125, y: 94))
    p.addLine(to: CGPoint(x: 137, y: 73))
    p.addQuadCurve(to: CGPoint(x: 151, y: 35), control: CGPoint(x: 138, y: 47))
    p.closeSubpath()
  }
  static let brain = Path { p in
    p.move(to: CGPoint(x: 149, y: 63))
    p.addCurve(to: CGPoint(x: 188, y: 37), control1: CGPoint(x: 151, y: 44), control2: CGPoint(x: 172, y: 34))
    p.addCurve(to: CGPoint(x: 222, y: 68), control1: CGPoint(x: 207, y: 35), control2: CGPoint(x: 223, y: 48))
    p.addCurve(to: CGPoint(x: 196, y: 86), control1: CGPoint(x: 223, y: 82), control2: CGPoint(x: 210, y: 88))
    p.addCurve(to: CGPoint(x: 150, y: 77), control1: CGPoint(x: 179, y: 92), control2: CGPoint(x: 158, y: 86))
    p.addQuadCurve(to: CGPoint(x: 149, y: 63), control: CGPoint(x: 145, y: 72))
    p.closeSubpath()
  }
  static let folds = Path { p in
    p.move(to: CGPoint(x: 157, y: 59))
    p.addCurve(to: CGPoint(x: 183, y: 51), control1: CGPoint(x: 165, y: 62), control2: CGPoint(x: 173, y: 49))
    p.move(to: CGPoint(x: 154, y: 72))
    p.addCurve(to: CGPoint(x: 182, y: 66), control1: CGPoint(x: 166, y: 75), control2: CGPoint(x: 170, y: 61))
    p.move(to: CGPoint(x: 174, y: 79))
    p.addCurve(to: CGPoint(x: 201, y: 69), control1: CGPoint(x: 181, y: 73), control2: CGPoint(x: 195, y: 79))
    p.move(to: CGPoint(x: 190, y: 45))
    p.addCurve(to: CGPoint(x: 213, y: 60), control1: CGPoint(x: 187, y: 54), control2: CGPoint(x: 207, y: 52))
    p.move(to: CGPoint(x: 190, y: 62))
    p.addQuadCurve(to: CGPoint(x: 201, y: 62), control: CGPoint(x: 197, y: 57))
    p.move(to: CGPoint(x: 204, y: 77))
    p.addQuadCurve(to: CGPoint(x: 215, y: 69), control: CGPoint(x: 212, y: 75))
  }
  static let stem = Path { p in
    p.move(to: CGPoint(x: 175, y: 80))
    p.addQuadCurve(to: CGPoint(x: 196, y: 81), control: CGPoint(x: 182, y: 79))
    p.addQuadCurve(to: CGPoint(x: 198, y: 95), control: CGPoint(x: 200, y: 87))
    p.addLine(to: CGPoint(x: 200, y: 119))
    p.addQuadCurve(to: CGPoint(x: 191, y: 119), control: CGPoint(x: 197, y: 122))
    p.addQuadCurve(to: CGPoint(x: 182, y: 98), control: CGPoint(x: 191, y: 104))
    p.addQuadCurve(to: CGPoint(x: 178, y: 88), control: CGPoint(x: 175, y: 94))
    p.closeSubpath()
  }
  static let cord = Path { p in
    p.move(to: CGPoint(x: 196, y: 116))
    p.addCurve(to: CGPoint(x: 198, y: 174), control1: CGPoint(x: 196, y: 131), control2: CGPoint(x: 198, y: 150))
  }
  static let bronchi = Path { p in
    p.move(to: CGPoint(x: 151, y: 213))
    p.addQuadCurve(to: CGPoint(x: 175, y: 190), control: CGPoint(x: 157, y: 200))
    p.addQuadCurve(to: CGPoint(x: 210, y: 211), control: CGPoint(x: 192, y: 196))
  }
  static func lung(_ expansion: Double, side: Int) -> Path {
    let outer = 56 + 5 * expansion, base = (side == 0 ? 265.0 : 271.0) + 16 * expansion, notch = side == 0 ? 0.0 : 9.0
    return Path { p in
      p.move(to: CGPoint(x: 25, y: 166))
      p.addCurve(to: CGPoint(x: outer, y: 232), control1: CGPoint(x: 40, y: 171), control2: CGPoint(x: outer, y: 199))
      p.addQuadCurve(to: CGPoint(x: 53, y: 284), control: CGPoint(x: outer + 2, y: 261))
      p.addCurve(to: CGPoint(x: 10, y: base + 7), control1: CGPoint(x: 39, y: base), control2: CGPoint(x: 24, y: base - 7))
      p.addCurve(to: CGPoint(x: 9 + notch, y: 218), control1: CGPoint(x: 3, y: base - 2), control2: CGPoint(x: 7 + notch, y: 235))
      p.addCurve(to: CGPoint(x: 25, y: 166), control1: CGPoint(x: 7, y: 197), control2: CGPoint(x: 10, y: 170)); p.closeSubpath()
    }
  }
  static func diaphragm(_ expansion: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 128, y: 288))
      p.addCurve(to: CGPoint(x: 181, y: GalaxySSIHealthAtlasBrainstemMotion.diaphragmCenter(expansion)), control1: CGPoint(x: 146, y: 256 + 22 * expansion), control2: CGPoint(x: 162, y: 252 + 27 * expansion))
      p.addCurve(to: CGPoint(x: 234, y: 288), control1: CGPoint(x: 201, y: 258 + 21 * expansion), control2: CGPoint(x: 218, y: 260 + 20 * expansion))
    }
  }
}

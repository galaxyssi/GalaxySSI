import SwiftUI

enum GalaxySSIHealthAtlasCoronaryGeometry {
  static let wall: UInt32 = 0x995F62, artery: UInt32 = 0xA1414F, arteryFill: UInt32 = 0xE69B86
  static let vein: UInt32 = 0x3E7188, veinFill: UInt32 = 0x95BDC9, leader: UInt32 = 0x786969, oxygen: UInt32 = 0xB67822
  static let arch = Path { p in
    p.move(to: CGPoint(x: 142, y: 108))
    p.addCurve(to: CGPoint(x: 146, y: 59), control1: CGPoint(x: 137, y: 94), control2: CGPoint(x: 147, y: 78))
    p.addCurve(to: CGPoint(x: 186, y: 18), control1: CGPoint(x: 145, y: 31), control2: CGPoint(x: 162, y: 18))
    p.addCurve(to: CGPoint(x: 231, y: 44), control1: CGPoint(x: 207, y: 17), control2: CGPoint(x: 223, y: 27))
    p.addQuadCurve(to: CGPoint(x: 212, y: 55), control: CGPoint(x: 225, y: 52))
    p.addCurve(to: CGPoint(x: 189, y: 45), control1: CGPoint(x: 207, y: 45), control2: CGPoint(x: 199, y: 43))
    p.addCurve(to: CGPoint(x: 177, y: 76), control1: CGPoint(x: 173, y: 46), control2: CGPoint(x: 176, y: 67))
    p.addQuadCurve(to: CGPoint(x: 180, y: 109), control: CGPoint(x: 185, y: 94))
    p.closeSubpath()
  }
  static let venaCava = Path { p in
    p.move(to: CGPoint(x: 113, y: 42))
    p.addQuadCurve(to: CGPoint(x: 133, y: 43), control: CGPoint(x: 123, y: 36))
    p.addCurve(to: CGPoint(x: 136, y: 91), control1: CGPoint(x: 128, y: 56), control2: CGPoint(x: 132, y: 73))
    p.addLine(to: CGPoint(x: 111, y: 95))
    p.addQuadCurve(to: CGPoint(x: 113, y: 42), control: CGPoint(x: 114, y: 68))
    p.closeSubpath()
  }
  static let pulmonaryTrunk = Path { p in
    p.move(to: CGPoint(x: 163, y: 121))
    p.addCurve(to: CGPoint(x: 195, y: 67), control1: CGPoint(x: 174, y: 99), control2: CGPoint(x: 180, y: 78))
    p.addCurve(to: CGPoint(x: 235, y: 57), control1: CGPoint(x: 205, y: 59), control2: CGPoint(x: 216, y: 56))
    p.addQuadCurve(to: CGPoint(x: 237, y: 77), control: CGPoint(x: 240, y: 64))
    p.addCurve(to: CGPoint(x: 207, y: 96), control1: CGPoint(x: 222, y: 76), control2: CGPoint(x: 211, y: 81))
    p.addLine(to: CGPoint(x: 201, y: 121))
    p.closeSubpath()
  }
  static let heart = Path { p in
    p.move(to: CGPoint(x: 154, y: 101))
    p.addCurve(to: CGPoint(x: 100, y: 104), control1: CGPoint(x: 141, y: 80), control2: CGPoint(x: 112, y: 83))
    p.addCurve(to: CGPoint(x: 128, y: 176), control1: CGPoint(x: 82, y: 134), control2: CGPoint(x: 105, y: 158))
    p.addCurve(to: CGPoint(x: 207, y: 213), control1: CGPoint(x: 150, y: 195), control2: CGPoint(x: 181, y: 207))
    p.addCurve(to: CGPoint(x: 253, y: 156), control1: CGPoint(x: 230, y: 218), control2: CGPoint(x: 249, y: 185))
    p.addCurve(to: CGPoint(x: 226, y: 96), control1: CGPoint(x: 260, y: 125), control2: CGPoint(x: 248, y: 99))
    p.addCurve(to: CGPoint(x: 183, y: 111), control1: CGPoint(x: 209, y: 91), control2: CGPoint(x: 195, y: 105))
    p.addQuadCurve(to: CGPoint(x: 154, y: 101), control: CGPoint(x: 168, y: 117))
    p.closeSubpath()
  }
  static let lvSurface = Path { p in
    p.move(to: CGPoint(x: 191, y: 121))
    p.addCurve(to: CGPoint(x: 229, y: 99), control1: CGPoint(x: 200, y: 105), control2: CGPoint(x: 215, y: 96))
    p.addCurve(to: CGPoint(x: 252, y: 157), control1: CGPoint(x: 253, y: 104), control2: CGPoint(x: 258, y: 130))
    p.addCurve(to: CGPoint(x: 207, y: 213), control1: CGPoint(x: 246, y: 186), control2: CGPoint(x: 230, y: 216))
    p.addCurve(to: CGPoint(x: 191, y: 121), control1: CGPoint(x: 190, y: 194), control2: CGPoint(x: 181, y: 148))
    p.closeSubpath()
  }
  static let atrialGroove = Path { p in
    p.move(to: CGPoint(x: 99, y: 123))
    p.addCurve(to: CGPoint(x: 153, y: 146), control1: CGPoint(x: 124, y: 116), control2: CGPoint(x: 145, y: 132))
    p.addQuadCurve(to: CGPoint(x: 196, y: 190), control: CGPoint(x: 171, y: 173))
  }
  static let rootCusp = Path { p in
    p.move(to: CGPoint(x: 144, y: 101))
    p.addQuadCurve(to: CGPoint(x: 163, y: 105), control: CGPoint(x: 152, y: 111))
    p.addQuadCurve(to: CGPoint(x: 181, y: 102), control: CGPoint(x: 173, y: 111))
  }
  static let rootSection = Path { p in
    p.move(to: CGPoint(x: 144, y: 248))
    p.addQuadCurve(to: CGPoint(x: 216, y: 248), control: CGPoint(x: 180, y: 237))
    p.addCurve(to: CGPoint(x: 232, y: 295), control1: CGPoint(x: 210, y: 269), control2: CGPoint(x: 233, y: 277))
    p.addQuadCurve(to: CGPoint(x: 205, y: 326), control: CGPoint(x: 233, y: 315))
    p.addQuadCurve(to: CGPoint(x: 155, y: 326), control: CGPoint(x: 180, y: 335))
    p.addQuadCurve(to: CGPoint(x: 128, y: 295), control: CGPoint(x: 127, y: 315))
    p.addCurve(to: CGPoint(x: 144, y: 248), control1: CGPoint(x: 127, y: 277), control2: CGPoint(x: 150, y: 269))
    p.closeSubpath()
  }
  static let rootValve = Path { p in
    p.move(to: CGPoint(x: 132, y: 310))
    p.addCurve(to: CGPoint(x: 180, y: 316), control1: CGPoint(x: 152, y: 303), control2: CGPoint(x: 160, y: 326))
    p.addCurve(to: CGPoint(x: 228, y: 310), control1: CGPoint(x: 199, y: 326), control2: CGPoint(x: 207, y: 303))
  }
  static let posteriorHeart = Path { p in
    p.move(to: CGPoint(x: 175, y: 265))
    p.addCurve(to: CGPoint(x: 99, y: 267), control1: CGPoint(x: 156, y: 245), control2: CGPoint(x: 114, y: 243))
    p.addCurve(to: CGPoint(x: 141, y: 329), control1: CGPoint(x: 84, y: 290), control2: CGPoint(x: 116, y: 321))
    p.addCurve(to: CGPoint(x: 220, y: 311), control1: CGPoint(x: 164, y: 335), control2: CGPoint(x: 196, y: 322))
    p.addCurve(to: CGPoint(x: 250, y: 251), control1: CGPoint(x: 247, y: 299), control2: CGPoint(x: 269, y: 270))
    p.addCurve(to: CGPoint(x: 192, y: 261), control1: CGPoint(x: 234, y: 238), control2: CGPoint(x: 202, y: 246))
    p.addQuadCurve(to: CGPoint(x: 175, y: 265), control: CGPoint(x: 184, y: 271))
    p.closeSubpath()
  }
  static let posteriorAtrium = Path { p in
    p.move(to: CGPoint(x: 208, y: 263))
    p.addCurve(to: CGPoint(x: 229, y: 236), control1: CGPoint(x: 215, y: 250), control2: CGPoint(x: 228, y: 249))
    p.addQuadCurve(to: CGPoint(x: 250, y: 238), control: CGPoint(x: 242, y: 233))
    p.addQuadCurve(to: CGPoint(x: 254, y: 258), control: CGPoint(x: 244, y: 250))
    p.addCurve(to: CGPoint(x: 231, y: 298), control1: CGPoint(x: 271, y: 277), control2: CGPoint(x: 250, y: 295))
    p.addQuadCurve(to: CGPoint(x: 208, y: 263), control: CGPoint(x: 205, y: 289))
    p.closeSubpath()
  }
  static let exposedRoot = Path { p in
    p.move(to: CGPoint(x: 146, y: 76))
    p.addCurve(to: CGPoint(x: 142, y: 99), control1: CGPoint(x: 150, y: 85), control2: CGPoint(x: 140, y: 88))
    p.addQuadCurve(to: CGPoint(x: 182, y: 101), control: CGPoint(x: 162, y: 118))
    p.addCurve(to: CGPoint(x: 177, y: 76), control1: CGPoint(x: 186, y: 91), control2: CGPoint(x: 176, y: 83))
    p.addQuadCurve(to: CGPoint(x: 146, y: 76), control: CGPoint(x: 160, y: 80))
    p.closeSubpath()
  }
  static let wallSlice = Path { p in
    p.move(to: CGPoint(x: 39, y: 273))
    p.addCurve(to: CGPoint(x: 313, y: 270), control1: CGPoint(x: 104, y: 244), control2: CGPoint(x: 228, y: 242))
    p.addQuadCurve(to: CGPoint(x: 320, y: 306), control: CGPoint(x: 331, y: 286))
    p.addCurve(to: CGPoint(x: 42, y: 308), control1: CGPoint(x: 255, y: 334), control2: CGPoint(x: 108, y: 334))
    p.addQuadCurve(to: CGPoint(x: 39, y: 273), control: CGPoint(x: 23, y: 292))
    p.closeSubpath()
  }
  static func wallFiber(squeeze: Double, side: Double, row: Int) -> Path {
    let edge = 290 + side * (15 + Double(row) * 6), inside = 290 + side * (21 - 11 * squeeze + Double(row) * 9)
    return Path { p in
      p.move(to: CGPoint(x: 54, y: edge))
      p.addCurve(to: CGPoint(x: 161, y: inside), control1: CGPoint(x: 101, y: edge + 4), control2: CGPoint(x: 122, y: inside))
      p.addCurve(to: CGPoint(x: 300, y: edge), control1: CGPoint(x: 207, y: inside), control2: CGPoint(x: 232, y: edge - 3))
    }
  }
}

import SwiftUI

enum GalaxySSIHealthAtlasThymusShapes {
  static let capsuleEdge: UInt32 = 0xA26476, medullaEdge: UInt32 = 0xB48171, early: UInt32 = 0x805E9A
  static let selected: UInt32 = 0x287C70, reactive: UInt32 = 0x986329, vesselBlue: UInt32 = 0x527F9B, guide: UInt32 = 0x687177
  static let tissue = Path { p in
    p.move(to: CGPoint(x: 99, y: 145))
    p.addCurve(to: CGPoint(x: 170, y: 83), control1: CGPoint(x: 105, y: 107), control2: CGPoint(x: 136, y: 84))
    p.addCurve(to: CGPoint(x: 225, y: 83), control1: CGPoint(x: 190, y: 74), control2: CGPoint(x: 207, y: 89))
    p.addCurve(to: CGPoint(x: 302, y: 129), control1: CGPoint(x: 263, y: 73), control2: CGPoint(x: 290, y: 98))
    p.addCurve(to: CGPoint(x: 308, y: 186), control1: CGPoint(x: 309, y: 146), control2: CGPoint(x: 299, y: 167))
    p.addCurve(to: CGPoint(x: 252, y: 282), control1: CGPoint(x: 326, y: 235), control2: CGPoint(x: 285, y: 271))
    p.addCurve(to: CGPoint(x: 183, y: 288), control1: CGPoint(x: 224, y: 296), control2: CGPoint(x: 208, y: 278))
    p.addCurve(to: CGPoint(x: 99, y: 251), control1: CGPoint(x: 146, y: 302), control2: CGPoint(x: 113, y: 277))
    p.addCurve(to: CGPoint(x: 99, y: 145), control1: CGPoint(x: 78, y: 217), control2: CGPoint(x: 88, y: 181))
    p.closeSubpath()
  }
  static let medulla = Path { p in
    p.move(to: CGPoint(x: 144, y: 175))
    p.addCurve(to: CGPoint(x: 200, y: 149), control1: CGPoint(x: 153, y: 149), control2: CGPoint(x: 179, y: 142))
    p.addCurve(to: CGPoint(x: 258, y: 167), control1: CGPoint(x: 223, y: 159), control2: CGPoint(x: 247, y: 142))
    p.addCurve(to: CGPoint(x: 260, y: 211), control1: CGPoint(x: 269, y: 187), control2: CGPoint(x: 251, y: 195))
    p.addCurve(to: CGPoint(x: 226, y: 255), control1: CGPoint(x: 269, y: 231), control2: CGPoint(x: 247, y: 254))
    p.addCurve(to: CGPoint(x: 180, y: 258), control1: CGPoint(x: 207, y: 257), control2: CGPoint(x: 197, y: 246))
    p.addCurve(to: CGPoint(x: 151, y: 228), control1: CGPoint(x: 161, y: 268), control2: CGPoint(x: 149, y: 244))
    p.addCurve(to: CGPoint(x: 144, y: 175), control1: CGPoint(x: 153, y: 205), control2: CGPoint(x: 132, y: 199))
    p.closeSubpath()
  }
  static let shoulders = Path { p in
    p.move(to: CGPoint(x: 42, y: 39))
    p.addCurve(to: CGPoint(x: 25, y: 54), control1: CGPoint(x: 44, y: 50), control2: CGPoint(x: 34, y: 50))
    p.addQuadCurve(to: CGPoint(x: 17, y: 83), control: CGPoint(x: 15, y: 58))
    p.addLine(to: CGPoint(x: 17, y: 102))
    p.addQuadCurve(to: CGPoint(x: 86, y: 102), control: CGPoint(x: 52, y: 108))
    p.addLine(to: CGPoint(x: 86, y: 83))
    p.addQuadCurve(to: CGPoint(x: 78, y: 54), control: CGPoint(x: 88, y: 58))
    p.addCurve(to: CGPoint(x: 61, y: 39), control1: CGPoint(x: 69, y: 50), control2: CGPoint(x: 59, y: 50))
  }
  static let lung = Path { p in
    p.move(to: CGPoint(x: 43, y: 58))
    p.addCurve(to: CGPoint(x: 25, y: 87), control1: CGPoint(x: 35, y: 55), control2: CGPoint(x: 25, y: 70))
    p.addCurve(to: CGPoint(x: 41, y: 92), control1: CGPoint(x: 25, y: 95), control2: CGPoint(x: 35, y: 97))
    p.addQuadCurve(to: CGPoint(x: 43, y: 58), control: CGPoint(x: 46, y: 87))
    p.closeSubpath()
  }
  static let thymicLobe = Path { p in
    p.move(to: CGPoint(x: 50, y: 54))
    p.addCurve(to: CGPoint(x: 44, y: 69), control1: CGPoint(x: 46, y: 52), control2: CGPoint(x: 46, y: 63))
    p.addCurve(to: CGPoint(x: 49, y: 87), control1: CGPoint(x: 39, y: 80), control2: CGPoint(x: 44, y: 88))
    p.addCurve(to: CGPoint(x: 50, y: 54), control1: CGPoint(x: 53, y: 84), control2: CGPoint(x: 54, y: 61))
    p.closeSubpath()
  }
  static let entryVessel = Path { p in
    p.move(to: CGPoint(x: 62, y: 285))
    p.addCurve(to: CGPoint(x: 136, y: 248), control1: CGPoint(x: 104, y: 284), control2: CGPoint(x: 107, y: 258))
    p.addQuadCurve(to: CGPoint(x: 156, y: 226), control: CGPoint(x: 150, y: 244))
  }
  static let exitVessel = Path { p in
    p.move(to: CGPoint(x: 228, y: 241))
    p.addCurve(to: CGPoint(x: 260, y: 283), control1: CGPoint(x: 224, y: 266), control2: CGPoint(x: 248, y: 273))
    p.addQuadCurve(to: CGPoint(x: 302, y: 291), control: CGPoint(x: 279, y: 293))
  }
}

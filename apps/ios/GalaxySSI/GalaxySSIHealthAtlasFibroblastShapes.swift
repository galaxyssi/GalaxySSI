import SwiftUI

enum GalaxySSIHealthAtlasFibroblastShapes {
  static let collagen: UInt32 = 0xAA757E, newFiber: UInt32 = 0x397F76, cue: UInt32 = 0x547F9E, leader: UInt32 = 0x665969
  static let dermis = Path { p in
    p.move(to: CGPoint(x: 33, y: 105))
    p.addLine(to: CGPoint(x: 305, y: 105))
    p.addQuadCurve(to: CGPoint(x: 310, y: 113), control: CGPoint(x: 310, y: 106))
    p.addLine(to: CGPoint(x: 310, y: 259))
    p.addQuadCurve(to: CGPoint(x: 297, y: 273), control: CGPoint(x: 310, y: 273))
    p.addLine(to: CGPoint(x: 47, y: 273))
    p.addQuadCurve(to: CGPoint(x: 33, y: 259), control: CGPoint(x: 33, y: 273))
    p.closeSubpath()
  }
  static let side = Path { p in
    p.move(to: CGPoint(x: 310, y: 105))
    p.addLine(to: CGPoint(x: 329, y: 88))
    p.addLine(to: CGPoint(x: 329, y: 244))
    p.addQuadCurve(to: CGPoint(x: 323, y: 256), control: CGPoint(x: 329, y: 251))
    p.addLine(to: CGPoint(x: 306, y: 269))
    p.addQuadCurve(to: CGPoint(x: 310, y: 258), control: CGPoint(x: 310, y: 264))
    p.closeSubpath()
  }
  static let epidermalBand = Path { p in
    p.move(to: CGPoint(x: 33, y: 105))
    p.addQuadCurve(to: CGPoint(x: 134, y: 105), control: CGPoint(x: 87, y: 100))
    p.addQuadCurve(to: CGPoint(x: 218, y: 104), control: CGPoint(x: 184, y: 110))
    p.addQuadCurve(to: CGPoint(x: 310, y: 105), control: CGPoint(x: 263, y: 99))
    p.addLine(to: CGPoint(x: 310, y: 133))
    p.addCurve(to: CGPoint(x: 250, y: 132), control1: CGPoint(x: 288, y: 138), control2: CGPoint(x: 276, y: 125))
    p.addCurve(to: CGPoint(x: 194, y: 134), control1: CGPoint(x: 230, y: 139), control2: CGPoint(x: 217, y: 127))
    p.addCurve(to: CGPoint(x: 133, y: 133), control1: CGPoint(x: 170, y: 141), control2: CGPoint(x: 154, y: 126))
    p.addCurve(to: CGPoint(x: 76, y: 132), control1: CGPoint(x: 112, y: 140), control2: CGPoint(x: 96, y: 127))
    p.addQuadCurve(to: CGPoint(x: 33, y: 133), control: CGPoint(x: 49, y: 140))
    p.closeSubpath()
  }
  static let epidermalTop = Path { p in
    p.move(to: CGPoint(x: 33, y: 105))
    p.addLine(to: CGPoint(x: 53, y: 88))
    p.addQuadCurve(to: CGPoint(x: 154, y: 88), control: CGPoint(x: 101, y: 82))
    p.addQuadCurve(to: CGPoint(x: 239, y: 87), control: CGPoint(x: 201, y: 93))
    p.addQuadCurve(to: CGPoint(x: 329, y: 88), control: CGPoint(x: 279, y: 82))
    p.addLine(to: CGPoint(x: 310, y: 105))
    p.addQuadCurve(to: CGPoint(x: 218, y: 104), control: CGPoint(x: 263, y: 99))
    p.addQuadCurve(to: CGPoint(x: 134, y: 105), control: CGPoint(x: 184, y: 110))
    p.addQuadCurve(to: CGPoint(x: 33, y: 105), control: CGPoint(x: 87, y: 100))
    p.closeSubpath()
  }
  static let epidermalEdge = Path { p in
    p.move(to: CGPoint(x: 310, y: 105))
    p.addLine(to: CGPoint(x: 329, y: 88))
    p.addLine(to: CGPoint(x: 329, y: 115))
    p.addLine(to: CGPoint(x: 310, y: 133))
    p.closeSubpath()
  }
  static let surfaceDetail = Path { p in
    p.move(to: CGPoint(x: 47, y: 102))
    p.addQuadCurve(to: CGPoint(x: 132, y: 101), control: CGPoint(x: 92, y: 96))
    p.move(to: CGPoint(x: 218, y: 100))
    p.addQuadCurve(to: CGPoint(x: 304, y: 100), control: CGPoint(x: 267, y: 94))
    p.move(to: CGPoint(x: 38, y: 120))
    p.addCurve(to: CGPoint(x: 225, y: 119), control1: CGPoint(x: 108, y: 113), control2: CGPoint(x: 158, y: 126))
    p.addQuadCurve(to: CGPoint(x: 305, y: 120), control: CGPoint(x: 270, y: 113))
  }
  static let cell = Path { p in
    p.move(to: CGPoint(x: 129, y: 229))
    p.addCurve(to: CGPoint(x: 173, y: 197), control1: CGPoint(x: 149, y: 214), control2: CGPoint(x: 150, y: 200))
    p.addCurve(to: CGPoint(x: 232, y: 186), control1: CGPoint(x: 195, y: 194), control2: CGPoint(x: 210, y: 201))
    p.addCurve(to: CGPoint(x: 187, y: 217), control1: CGPoint(x: 218, y: 208), control2: CGPoint(x: 199, y: 211))
    p.addCurve(to: CGPoint(x: 129, y: 229), control1: CGPoint(x: 165, y: 226), control2: CGPoint(x: 151, y: 217))
    p.closeSubpath()
  }
  static let cellDetail = Path { p in
    p.move(to: CGPoint(x: 146, y: 221))
    p.addQuadCurve(to: CGPoint(x: 161, y: 209), control: CGPoint(x: 158, y: 210))
    p.move(to: CGPoint(x: 195, y: 204))
    p.addQuadCurve(to: CGPoint(x: 222, y: 195), control: CGPoint(x: 213, y: 202))
  }
}

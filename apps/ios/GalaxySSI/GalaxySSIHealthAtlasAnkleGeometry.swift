import SwiftUI

// Original Android #4385 path coordinates; named by scene, with no simplified outlines.
enum GalaxySSIHealthAtlasAnkleGeometry {
  static let overviewTibia = Path { p in
    p.move(to: CGPoint(x: 118, y: 41))
    p.addCurve(to: CGPoint(x: 193, y: 45), control1: CGPoint(x: 144, y: 31), control2: CGPoint(x: 166, y: 34))
    p.addCurve(to: CGPoint(x: 184, y: 79), control1: CGPoint(x: 209, y: 51), control2: CGPoint(x: 199, y: 70))
    p.addCurve(to: CGPoint(x: 178, y: 203), control1: CGPoint(x: 174, y: 95), control2: CGPoint(x: 174, y: 163))
    p.addCurve(to: CGPoint(x: 182, y: 246), control1: CGPoint(x: 180, y: 222), control2: CGPoint(x: 190, y: 235))
    p.addQuadCurve(to: CGPoint(x: 142, y: 248), control: CGPoint(x: 165, y: 261))
    p.addCurve(to: CGPoint(x: 140, y: 207), control1: CGPoint(x: 133, y: 239), control2: CGPoint(x: 140, y: 224))
    p.addCurve(to: CGPoint(x: 132, y: 85), control1: CGPoint(x: 145, y: 166), control2: CGPoint(x: 142, y: 112))
    p.addCurve(to: CGPoint(x: 118, y: 41), control1: CGPoint(x: 114, y: 77), control2: CGPoint(x: 100, y: 55))
    p.closeSubpath()
  }
  static let overviewFibula = Path { p in
    p.move(to: CGPoint(x: 211, y: 66))
    p.addQuadCurve(to: CGPoint(x: 235, y: 76), control: CGPoint(x: 231, y: 57))
    p.addQuadCurve(to: CGPoint(x: 224, y: 95), control: CGPoint(x: 233, y: 87))
    p.addCurve(to: CGPoint(x: 213, y: 198), control1: CGPoint(x: 211, y: 121), control2: CGPoint(x: 213, y: 177))
    p.addCurve(to: CGPoint(x: 216, y: 252), control1: CGPoint(x: 213, y: 221), control2: CGPoint(x: 224, y: 231))
    p.addQuadCurve(to: CGPoint(x: 199, y: 252), control: CGPoint(x: 209, y: 269))
    p.addCurve(to: CGPoint(x: 195, y: 195), control1: CGPoint(x: 201, y: 236), control2: CGPoint(x: 192, y: 219))
    p.addCurve(to: CGPoint(x: 203, y: 94), control1: CGPoint(x: 198, y: 148), control2: CGPoint(x: 200, y: 119))
    p.addQuadCurve(to: CGPoint(x: 211, y: 66), control: CGPoint(x: 197, y: 76))
    p.closeSubpath()
  }
  static let tarsus = Path { p in
    p.move(to: CGPoint(x: 153, y: 260))
    p.addQuadCurve(to: CGPoint(x: 194, y: 258), control: CGPoint(x: 169, y: 245))
    p.addQuadCurve(to: CGPoint(x: 189, y: 279), control: CGPoint(x: 202, y: 269))
    p.addQuadCurve(to: CGPoint(x: 155, y: 274), control: CGPoint(x: 169, y: 282))
    p.closeSubpath()
  }
  static let cradleTibia = Path { p in
    p.move(to: CGPoint(x: 93, y: 57))
    p.addCurve(to: CGPoint(x: 176, y: 55), control1: CGPoint(x: 114, y: 45), control2: CGPoint(x: 144, y: 44))
    p.addCurve(to: CGPoint(x: 194, y: 92), control1: CGPoint(x: 193, y: 62), control2: CGPoint(x: 199, y: 74))
    p.addCurve(to: CGPoint(x: 189, y: 162), control1: CGPoint(x: 187, y: 113), control2: CGPoint(x: 188, y: 143))
    p.addQuadCurve(to: CGPoint(x: 172, y: 179), control: CGPoint(x: 190, y: 177))
    p.addQuadCurve(to: CGPoint(x: 141, y: 180), control: CGPoint(x: 157, y: 174))
    p.addQuadCurve(to: CGPoint(x: 121, y: 204), control: CGPoint(x: 124, y: 186))
    p.addQuadCurve(to: CGPoint(x: 102, y: 208), control: CGPoint(x: 114, y: 214))
    p.addQuadCurve(to: CGPoint(x: 94, y: 188), control: CGPoint(x: 92, y: 202))
    p.addCurve(to: CGPoint(x: 89, y: 99), control1: CGPoint(x: 99, y: 143), control2: CGPoint(x: 103, y: 122))
    p.addQuadCurve(to: CGPoint(x: 93, y: 57), control: CGPoint(x: 72, y: 69))
    p.closeSubpath()
  }
  static func cradleFibula(_ shift: Double) -> Path { Path { p in
    p.move(to: CGPoint(x: 208 + shift, y: 53))
    p.addQuadCurve(to: CGPoint(x: 231 + shift, y: 67), control: CGPoint(x: 226 + shift, y: 48))
    p.addCurve(to: CGPoint(x: 222 + shift, y: 145), control1: CGPoint(x: 229 + shift, y: 90), control2: CGPoint(x: 221 + shift, y: 113))
    p.addCurve(to: CGPoint(x: 225 + shift, y: 211), control1: CGPoint(x: 222 + shift, y: 168), control2: CGPoint(x: 232 + shift, y: 183))
    p.addQuadCurve(to: CGPoint(x: 209 + shift, y: 225), control: CGPoint(x: 221 + shift, y: 230))
    p.addQuadCurve(to: CGPoint(x: 201 + shift, y: 209), control: CGPoint(x: 198 + shift, y: 221))
    p.addCurve(to: CGPoint(x: 198 + shift, y: 146), control1: CGPoint(x: 209 + shift, y: 186), control2: CGPoint(x: 200 + shift, y: 168))
    p.addCurve(to: CGPoint(x: 203 + shift, y: 76), control1: CGPoint(x: 193 + shift, y: 115), control2: CGPoint(x: 206 + shift, y: 94))
    p.addQuadCurve(to: CGPoint(x: 208 + shift, y: 53), control: CGPoint(x: 197 + shift, y: 62))
    p.closeSubpath()
  } }
  static let talus = Path { p in
    p.move(to: CGPoint(x: 128, y: 193))
    p.addCurve(to: CGPoint(x: 194, y: 197), control1: CGPoint(x: 144, y: 181), control2: CGPoint(x: 177, y: 180))
    p.addQuadCurve(to: CGPoint(x: 201, y: 229), control: CGPoint(x: 207, y: 211))
    p.addQuadCurve(to: CGPoint(x: 172, y: 243), control: CGPoint(x: 193, y: 240))
    p.addQuadCurve(to: CGPoint(x: 132, y: 232), control: CGPoint(x: 150, y: 242))
    p.addQuadCurve(to: CGPoint(x: 128, y: 193), control: CGPoint(x: 116, y: 222))
    p.closeSubpath()
  }
  static let sideTibia = Path { p in
    p.move(to: CGPoint(x: 120, y: 65))
    p.addQuadCurve(to: CGPoint(x: 170, y: 59), control: CGPoint(x: 146, y: 49))
    p.addQuadCurve(to: CGPoint(x: 184, y: 90), control: CGPoint(x: 188, y: 67))
    p.addCurve(to: CGPoint(x: 179, y: 162), control1: CGPoint(x: 174, y: 119), control2: CGPoint(x: 176, y: 144))
    p.addQuadCurve(to: CGPoint(x: 164, y: 184), control: CGPoint(x: 181, y: 174))
    p.addQuadCurve(to: CGPoint(x: 127, y: 177), control: CGPoint(x: 143, y: 188))
    p.addQuadCurve(to: CGPoint(x: 120, y: 158), control: CGPoint(x: 118, y: 171))
    p.addCurve(to: CGPoint(x: 114, y: 87), control1: CGPoint(x: 126, y: 121), control2: CGPoint(x: 121, y: 106))
    p.addQuadCurve(to: CGPoint(x: 120, y: 65), control: CGPoint(x: 109, y: 70))
    p.closeSubpath()
  }
  static let foot = Path { p in
    p.move(to: CGPoint(x: 134, y: 207))
    p.addQuadCurve(to: CGPoint(x: 167, y: 185), control: CGPoint(x: 143, y: 179))
    p.addQuadCurve(to: CGPoint(x: 196, y: 203), control: CGPoint(x: 181, y: 191))
    p.addQuadCurve(to: CGPoint(x: 240, y: 218), control: CGPoint(x: 210, y: 215))
    p.addQuadCurve(to: CGPoint(x: 280, y: 235), control: CGPoint(x: 268, y: 220))
    p.addQuadCurve(to: CGPoint(x: 270, y: 249), control: CGPoint(x: 286, y: 245))
    p.addCurve(to: CGPoint(x: 187, y: 244), control1: CGPoint(x: 239, y: 255), control2: CGPoint(x: 221, y: 240))
    p.addQuadCurve(to: CGPoint(x: 136, y: 236), control: CGPoint(x: 153, y: 256))
    p.addQuadCurve(to: CGPoint(x: 134, y: 207), control: CGPoint(x: 129, y: 223))
    p.closeSubpath()
  }
  static let contact = Path { p in
    p.move(to: CGPoint(x: 144, y: 201))
    p.addQuadCurve(to: CGPoint(x: 165, y: 187), control: CGPoint(x: 150, y: 184))
    p.addQuadCurve(to: CGPoint(x: 190, y: 203), control: CGPoint(x: 179, y: 190))
    p.addQuadCurve(to: CGPoint(x: 164, y: 215), control: CGPoint(x: 181, y: 215))
    p.addQuadCurve(to: CGPoint(x: 144, y: 201), control: CGPoint(x: 150, y: 214))
    p.closeSubpath()
  }
}

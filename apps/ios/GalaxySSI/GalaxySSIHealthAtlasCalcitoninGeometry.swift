import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasCalcitoninGeometry {
  static let capillary = Path { p in
    p.move(to: .init(x: 30, y: 228))
    p.addCurve(to: .init(x: 330, y: 227), control1: .init(x: 104, y: 199), control2: .init(x: 239, y: 271))
  }
  static let capillaryRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 30, y: 228), commands: [
    .init(kind: .cubic, points: [.init(x: 104, y: 199), .init(x: 239, y: 271), .init(x: 330, y: 227)])])
  static let bone = Path { p in
    p.move(to: .init(x: 26, y: 233))
    p.addCurve(to: .init(x: 112, y: 236), control1: .init(x: 68, y: 228), control2: .init(x: 91, y: 235))
    p.addCurve(to: .init(x: 168, y: 266), control1: .init(x: 130, y: 236), control2: .init(x: 136, y: 263))
    p.addCurve(to: .init(x: 235, y: 238), control1: .init(x: 208, y: 273), control2: .init(x: 221, y: 250))
    p.addCurve(to: .init(x: 334, y: 237), control1: .init(x: 258, y: 232), control2: .init(x: 294, y: 232))
    p.addLine(to: .init(x: 334, y: 286))
    p.addQuadCurve(to: .init(x: 26, y: 287), control: .init(x: 176, y: 310))
    p.closeSubpath()
  }
  static let osteoclast = Path { p in
    p.move(to: .init(x: 109, y: 224))
    p.addCurve(to: .init(x: 147, y: 182), control1: .init(x: 108, y: 197), control2: .init(x: 126, y: 175))
    p.addCurve(to: .init(x: 199, y: 181), control1: .init(x: 158, y: 158), control2: .init(x: 191, y: 160))
    p.addCurve(to: .init(x: 235, y: 226), control1: .init(x: 223, y: 172), control2: .init(x: 241, y: 196))
    p.addQuadCurve(to: .init(x: 210, y: 247), control: .init(x: 220, y: 231))
    p.addQuadCurve(to: .init(x: 151, y: 247), control: .init(x: 180, y: 268))
    p.addQuadCurve(to: .init(x: 109, y: 224), control: .init(x: 131, y: 226))
    p.closeSubpath()
  }
  static let boneIcon = Path { p in
    p.move(to: .init(x: 53, y: 181))
    p.addCurve(to: .init(x: 50, y: 159), control1: .init(x: 38, y: 181), control2: .init(x: 38, y: 160))
    p.addQuadCurve(to: .init(x: 65, y: 153), control: .init(x: 53, y: 146))
    p.addLine(to: .init(x: 82, y: 167))
    p.addQuadCurve(to: .init(x: 98, y: 177), control: .init(x: 99, y: 164))
    p.addQuadCurve(to: .init(x: 89, y: 192), control: .init(x: 103, y: 192))
    p.addQuadCurve(to: .init(x: 75, y: 194), control: .init(x: 85, y: 202))
    p.addLine(to: .init(x: 61, y: 180))
    p.closeSubpath()
  }
  static let kidneyIcon = Path { p in
    p.move(to: .init(x: 172, y: 151))
    p.addCurve(to: .init(x: 188, y: 178), control1: .init(x: 197, y: 147), control2: .init(x: 211, y: 175))
    p.addCurve(to: .init(x: 184, y: 200), control1: .init(x: 177, y: 183), control2: .init(x: 197, y: 193))
    p.addCurve(to: .init(x: 172, y: 151), control1: .init(x: 155, y: 215), control2: .init(x: 145, y: 165))
    p.closeSubpath()
  }
  static let gutIcon = Path { p in
    p.move(to: .init(x: 266, y: 153))
    p.addCurve(to: .init(x: 305, y: 170), control1: .init(x: 300, y: 145), control2: .init(x: 324, y: 158))
    p.addCurve(to: .init(x: 259, y: 183), control1: .init(x: 290, y: 179), control2: .init(x: 258, y: 168))
    p.addCurve(to: .init(x: 304, y: 200), control1: .init(x: 261, y: 198), control2: .init(x: 319, y: 179))
    p.addQuadCurve(to: .init(x: 276, y: 204), control: .init(x: 298, y: 209))
  }
}

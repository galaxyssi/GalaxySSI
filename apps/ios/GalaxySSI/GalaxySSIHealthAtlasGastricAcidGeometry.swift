import SwiftUI

enum GalaxySSIHealthAtlasGastricAcidGeometry {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let tissueEdge: UInt32 = 0x98606D, rose: UInt32 = 0xCE8B94, guide: UInt32 = 0x626B70, focus: UInt32 = 0x9B632E
  static let lumenFill: UInt32 = 0xD4EBEA, lumenEdge: UInt32 = 0x527B83, acid: UInt32 = 0xA64337, potassium: UInt32 = 0x705387, chloride: UInt32 = 0x28766E
  static let stomach = Path { p in
    p.move(to: CGPoint(x: 61, y: 84))
    p.addCurve(to: CGPoint(x: 56, y: 146), control1: CGPoint(x: 63, y: 108), control2: CGPoint(x: 66, y: 126))
    p.addCurve(to: CGPoint(x: 31, y: 189), control1: CGPoint(x: 45, y: 165), control2: CGPoint(x: 40, y: 183))
    p.addQuadCurve(to: CGPoint(x: 18, y: 191), control: CGPoint(x: 24, y: 194))
    p.addLine(to: CGPoint(x: 17, y: 208))
    p.addCurve(to: CGPoint(x: 67, y: 234), control1: CGPoint(x: 36, y: 200), control2: CGPoint(x: 41, y: 225))
    p.addCurve(to: CGPoint(x: 141, y: 198), control1: CGPoint(x: 97, y: 245), control2: CGPoint(x: 130, y: 227))
    p.addCurve(to: CGPoint(x: 131, y: 115), control1: CGPoint(x: 156, y: 162), control2: CGPoint(x: 150, y: 131))
    p.addCurve(to: CGPoint(x: 85, y: 118), control1: CGPoint(x: 115, y: 102), control2: CGPoint(x: 96, y: 108))
    p.addQuadCurve(to: CGPoint(x: 78, y: 84), control: CGPoint(x: 77, y: 113))
    p.addQuadCurve(to: CGPoint(x: 61, y: 84), control: CGPoint(x: 70, y: 79))
    p.closeSubpath()
  }
  static let folds = Path { p in
    p.move(to: CGPoint(x: 96, y: 130))
    p.addCurve(to: CGPoint(x: 134, y: 176), control1: CGPoint(x: 130, y: 112), control2: CGPoint(x: 140, y: 156))
    p.move(to: CGPoint(x: 82, y: 139))
    p.addCurve(to: CGPoint(x: 117, y: 191), control1: CGPoint(x: 120, y: 125), control2: CGPoint(x: 131, y: 165))
    p.move(to: CGPoint(x: 70, y: 156))
    p.addCurve(to: CGPoint(x: 100, y: 207), control1: CGPoint(x: 104, y: 141), control2: CGPoint(x: 120, y: 179))
    p.move(to: CGPoint(x: 62, y: 177))
    p.addCurve(to: CGPoint(x: 86, y: 214), control1: CGPoint(x: 80, y: 164), control2: CGPoint(x: 100, y: 181))
    p.move(to: CGPoint(x: 45, y: 197))
    p.addQuadCurve(to: CGPoint(x: 71, y: 220), control: CGPoint(x: 61, y: 192))
  }
  static let gland = Path { p in
    p.move(to: CGPoint(x: 174, y: 116))
    p.addQuadCurve(to: CGPoint(x: 227, y: 113), control: CGPoint(x: 201, y: 104))
    p.addQuadCurve(to: CGPoint(x: 251, y: 113), control: CGPoint(x: 240, y: 122))
    p.addQuadCurve(to: CGPoint(x: 315, y: 115), control: CGPoint(x: 280, y: 104))
    p.addLine(to: CGPoint(x: 315, y: 132))
    p.addCurve(to: CGPoint(x: 287, y: 176), control1: CGPoint(x: 286, y: 125), control2: CGPoint(x: 278, y: 149))
    p.addCurve(to: CGPoint(x: 253, y: 282), control1: CGPoint(x: 300, y: 218), control2: CGPoint(x: 288, y: 275))
    p.addCurve(to: CGPoint(x: 208, y: 212), control1: CGPoint(x: 207, y: 292), control2: CGPoint(x: 197, y: 245))
    p.addCurve(to: CGPoint(x: 174, y: 135), control1: CGPoint(x: 221, y: 165), control2: CGPoint(x: 219, y: 122))
    p.closeSubpath()
  }
  static let glandSpace = Path { p in
    p.move(to: CGPoint(x: 224, y: 112))
    p.addQuadCurve(to: CGPoint(x: 254, y: 111), control: CGPoint(x: 237, y: 119))
    p.addCurve(to: CGPoint(x: 257, y: 165), control1: CGPoint(x: 244, y: 128), control2: CGPoint(x: 260, y: 145))
    p.addCurve(to: CGPoint(x: 252, y: 242), control1: CGPoint(x: 255, y: 190), control2: CGPoint(x: 245, y: 220))
    p.addQuadCurve(to: CGPoint(x: 246, y: 263), control: CGPoint(x: 256, y: 260))
    p.addCurve(to: CGPoint(x: 236, y: 213), control1: CGPoint(x: 232, y: 264), control2: CGPoint(x: 231, y: 232))
    p.addCurve(to: CGPoint(x: 238, y: 141), control1: CGPoint(x: 241, y: 188), control2: CGPoint(x: 247, y: 157))
    p.addQuadCurve(to: CGPoint(x: 224, y: 112), control: CGPoint(x: 235, y: 122))
    p.closeSubpath()
  }
  static let cell = Path { p in
    p.move(to: CGPoint(x: 272, y: 155))
    p.addCurve(to: CGPoint(x: 185, y: 77), control1: CGPoint(x: 282, y: 119), control2: CGPoint(x: 241, y: 75))
    p.addCurve(to: CGPoint(x: 98, y: 168), control1: CGPoint(x: 135, y: 78), control2: CGPoint(x: 95, y: 114))
    p.addCurve(to: CGPoint(x: 169, y: 270), control1: CGPoint(x: 91, y: 221), control2: CGPoint(x: 116, y: 263))
    p.addCurve(to: CGPoint(x: 273, y: 200), control1: CGPoint(x: 217, y: 279), control2: CGPoint(x: 259, y: 250))
    p.closeSubpath()
  }
  static let vessel = Path { p in
    p.move(to: CGPoint(x: 35, y: 94))
    p.addCurve(to: CGPoint(x: 46, y: 258), control1: CGPoint(x: 26, y: 150), control2: CGPoint(x: 54, y: 188))
  }
  static let canaliculus = Path { p in
    p.move(to: CGPoint(x: 282, y: 80))
    p.addCurve(to: CGPoint(x: 272, y: 151), control1: CGPoint(x: 273, y: 100), control2: CGPoint(x: 266, y: 129))
    p.addCurve(to: CGPoint(x: 218, y: 150), control1: CGPoint(x: 244, y: 156), control2: CGPoint(x: 233, y: 146))
    p.addCurve(to: CGPoint(x: 187, y: 137), control1: CGPoint(x: 202, y: 153), control2: CGPoint(x: 195, y: 151))
    p.addQuadCurve(to: CGPoint(x: 162, y: 115), control: CGPoint(x: 179, y: 120))
    p.addQuadCurve(to: CGPoint(x: 153, y: 125), control: CGPoint(x: 150, y: 113))
    p.addQuadCurve(to: CGPoint(x: 173, y: 146), control: CGPoint(x: 168, y: 132))
    p.addQuadCurve(to: CGPoint(x: 184, y: 167), control: CGPoint(x: 178, y: 159))
    p.addCurve(to: CGPoint(x: 139, y: 170), control1: CGPoint(x: 169, y: 175), control2: CGPoint(x: 152, y: 177))
    p.addQuadCurve(to: CGPoint(x: 124, y: 175), control: CGPoint(x: 128, y: 165))
    p.addQuadCurve(to: CGPoint(x: 136, y: 190), control: CGPoint(x: 122, y: 184))
    p.addQuadCurve(to: CGPoint(x: 189, y: 188), control: CGPoint(x: 164, y: 202))
    p.addCurve(to: CGPoint(x: 219, y: 181), control1: CGPoint(x: 199, y: 182), control2: CGPoint(x: 210, y: 180))
    p.addCurve(to: CGPoint(x: 272, y: 191), control1: CGPoint(x: 239, y: 183), control2: CGPoint(x: 249, y: 192))
    p.addCurve(to: CGPoint(x: 283, y: 269), control1: CGPoint(x: 276, y: 220), control2: CGPoint(x: 269, y: 249))
    p.addQuadCurve(to: CGPoint(x: 327, y: 267), control: CGPoint(x: 301, y: 276))
    p.addCurve(to: CGPoint(x: 326, y: 151), control1: CGPoint(x: 314, y: 216), control2: CGPoint(x: 329, y: 188))
    p.addQuadCurve(to: CGPoint(x: 335, y: 80), control: CGPoint(x: 321, y: 108))
    p.addQuadCurve(to: CGPoint(x: 282, y: 80), control: CGPoint(x: 304, y: 73))
    p.closeSubpath()
  }
  static let feedbackReturn = Path { p in
    p.move(to: CGPoint(x: 117, y: 308))
    p.addCurve(to: CGPoint(x: 97, y: 102), control1: CGPoint(x: 33, y: 301), control2: CGPoint(x: 40, y: 129))
  }
  static let locatorTrack = Route(start: .init(x: 109, y: 151), commands: [
    .init(kind: .quad, points: [.init(x: 180, y: 153), .init(x: 269, y: 179)]),
  ])
  static let secretionTrack = Route(start: .init(x: 219, y: 166), commands: [
    .init(kind: .cubic, points: [.init(x: 245, y: 165), .init(x: 268, y: 179), .init(x: 291, y: 170)]),
    .init(kind: .cubic, points: [.init(x: 307, y: 163), .init(x: 299, y: 121), .init(x: 306, y: 91)]),
  ])
}

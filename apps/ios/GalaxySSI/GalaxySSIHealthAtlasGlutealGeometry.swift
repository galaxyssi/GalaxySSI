import SwiftUI

enum GalaxySSIHealthAtlasGlutealGeometry {
  static let ilium = Path { p in
    p.move(to: CGPoint(x: 119, y: 126))
    p.addCurve(to: CGPoint(x: 194, y: 102), control1: CGPoint(x: 133, y: 103), control2: CGPoint(x: 165, y: 96))
    p.addCurve(to: CGPoint(x: 245, y: 132), control1: CGPoint(x: 216, y: 105), control2: CGPoint(x: 240, y: 119))
    p.addQuadCurve(to: CGPoint(x: 239, y: 145), control: CGPoint(x: 249, y: 142))
    p.addQuadCurve(to: CGPoint(x: 222, y: 148), control: CGPoint(x: 230, y: 141))
    p.addQuadCurve(to: CGPoint(x: 219, y: 174), control: CGPoint(x: 215, y: 160))
    p.addQuadCurve(to: CGPoint(x: 235, y: 187), control: CGPoint(x: 224, y: 185))
    p.addQuadCurve(to: CGPoint(x: 246, y: 204), control: CGPoint(x: 244, y: 192))
    p.addQuadCurve(to: CGPoint(x: 229, y: 209), control: CGPoint(x: 240, y: 211))
    p.addQuadCurve(to: CGPoint(x: 209, y: 212), control: CGPoint(x: 216, y: 204))
    p.addCurve(to: CGPoint(x: 161, y: 227), control1: CGPoint(x: 199, y: 230), control2: CGPoint(x: 178, y: 237))
    p.addQuadCurve(to: CGPoint(x: 154, y: 206), control: CGPoint(x: 146, y: 219))
    p.addQuadCurve(to: CGPoint(x: 150, y: 186), control: CGPoint(x: 161, y: 195))
    p.addQuadCurve(to: CGPoint(x: 141, y: 160), control: CGPoint(x: 135, y: 171))
    p.addQuadCurve(to: CGPoint(x: 127, y: 152), control: CGPoint(x: 140, y: 153))
    p.addQuadCurve(to: CGPoint(x: 119, y: 126), control: CGPoint(x: 116, y: 145))
    p.closeSubpath()
  }
  static let crest = Path { p in
    p.move(to: CGPoint(x: 127, y: 130))
    p.addCurve(to: CGPoint(x: 236, y: 132), control1: CGPoint(x: 151, y: 105), control2: CGPoint(x: 204, y: 105))
    p.move(to: CGPoint(x: 151, y: 135))
    p.addCurve(to: CGPoint(x: 221, y: 138), control1: CGPoint(x: 174, y: 121), control2: CGPoint(x: 202, y: 122))
    p.move(to: CGPoint(x: 203, y: 201))
    p.addQuadCurve(to: CGPoint(x: 227, y: 195), control: CGPoint(x: 212, y: 187))
  }
  static let sacrum = Path { p in
    p.move(to: CGPoint(x: 121, y: 124))
    p.addQuadCurve(to: CGPoint(x: 147, y: 130), control: CGPoint(x: 137, y: 119))
    p.addCurve(to: CGPoint(x: 130, y: 177), control1: CGPoint(x: 137, y: 146), control2: CGPoint(x: 135, y: 164))
    p.addQuadCurve(to: CGPoint(x: 121, y: 176), control: CGPoint(x: 125, y: 187))
    p.addQuadCurve(to: CGPoint(x: 114, y: 153), control: CGPoint(x: 119, y: 162))
    p.addQuadCurve(to: CGPoint(x: 121, y: 124), control: CGPoint(x: 109, y: 139))
    p.closeSubpath()
  }
  static let femur = Path { p in
    p.move(to: CGPoint(x: 201, y: 159))
    p.addCurve(to: CGPoint(x: 199, y: 188), control1: CGPoint(x: 212, y: 167), control2: CGPoint(x: 210, y: 183))
    p.addQuadCurve(to: CGPoint(x: 183, y: 198), control: CGPoint(x: 188, y: 192))
    p.addCurve(to: CGPoint(x: 175, y: 306), control1: CGPoint(x: 179, y: 218), control2: CGPoint(x: 175, y: 258))
    p.addQuadCurve(to: CGPoint(x: 153, y: 306), control: CGPoint(x: 165, y: 313))
    p.addCurve(to: CGPoint(x: 154, y: 213), control1: CGPoint(x: 152, y: 276), control2: CGPoint(x: 155, y: 244))
    p.addQuadCurve(to: CGPoint(x: 147, y: 199), control: CGPoint(x: 150, y: 205))
    p.addQuadCurve(to: CGPoint(x: 156, y: 185), control: CGPoint(x: 146, y: 186))
    p.addQuadCurve(to: CGPoint(x: 166, y: 190), control: CGPoint(x: 162, y: 183))
    p.addQuadCurve(to: CGPoint(x: 176, y: 170), control: CGPoint(x: 173, y: 184))
    p.addCurve(to: CGPoint(x: 201, y: 159), control1: CGPoint(x: 180, y: 157), control2: CGPoint(x: 190, y: 154))
    p.closeSubpath()
  }
  static let femoralRidge = Path { p in
    p.move(to: CGPoint(x: 153, y: 195))
    p.addCurve(to: CGPoint(x: 161, y: 296), control1: CGPoint(x: 166, y: 209), control2: CGPoint(x: 162, y: 241))
    p.move(to: CGPoint(x: 186, y: 164))
    p.addQuadCurve(to: CGPoint(x: 202, y: 170), control: CGPoint(x: 195, y: 159))
  }
  static func muscle(_ frame: GalaxySSIHealthAtlasGlutealPose) -> Path {
    let a=frame.origins, b=frame.insertions
    return Path { p in
      p.move(to: CGPoint(x: a[0].x, y: a[0].y))
      p.addCurve(to: CGPoint(x: b[0].x, y: b[0].y), control1: CGPoint(x: a[0].x + 22, y: a[0].y + 9), control2: CGPoint(x: b[0].x - 10, y: b[0].y - 20))
      p.addQuadCurve(to: CGPoint(x: b[1].x, y: b[1].y), control: CGPoint(x: b[1].x + 3, y: b[1].y - 8))
      p.addQuadCurve(to: CGPoint(x: b[2].x, y: b[2].y), control: CGPoint(x: b[2].x - 3, y: b[2].y - 7))
      p.addCurve(to: CGPoint(x: a[3].x, y: a[3].y), control1: CGPoint(x: b[2].x - 27, y: b[2].y - 6), control2: CGPoint(x: a[3].x - 13, y: a[3].y + 19))
      p.addCurve(to: CGPoint(x: a[0].x, y: a[0].y), control1: CGPoint(x: a[2].x - 10, y: a[2].y - 3), control2: CGPoint(x: a[1].x - 13, y: a[1].y - 6))
      p.closeSubpath()
    }
  }
}

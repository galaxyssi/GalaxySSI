import SwiftUI

enum GalaxySSIHealthAtlasSinusGeometry {
  static let front = Path { p in
    p.move(to: CGPoint(x: 90, y: 65))
    p.addCurve(to: CGPoint(x: 24, y: 130), control1: CGPoint(x: 48, y: 64), control2: CGPoint(x: 25, y: 92))
    p.addLine(to: CGPoint(x: 24, y: 158))
    p.addCurve(to: CGPoint(x: 20, y: 195), control1: CGPoint(x: 8, y: 151), control2: CGPoint(x: 9, y: 183))
    p.addQuadCurve(to: CGPoint(x: 30, y: 197), control: CGPoint(x: 25, y: 200))
    p.addCurve(to: CGPoint(x: 71, y: 269), control1: CGPoint(x: 35, y: 235), control2: CGPoint(x: 51, y: 252))
    p.addQuadCurve(to: CGPoint(x: 109, y: 269), control: CGPoint(x: 90, y: 282))
    p.addCurve(to: CGPoint(x: 150, y: 197), control1: CGPoint(x: 129, y: 252), control2: CGPoint(x: 145, y: 235))
    p.addQuadCurve(to: CGPoint(x: 160, y: 195), control: CGPoint(x: 155, y: 200))
    p.addCurve(to: CGPoint(x: 156, y: 158), control1: CGPoint(x: 171, y: 183), control2: CGPoint(x: 172, y: 151))
    p.addLine(to: CGPoint(x: 156, y: 130))
    p.addCurve(to: CGPoint(x: 90, y: 65), control1: CGPoint(x: 155, y: 92), control2: CGPoint(x: 132, y: 64))
    p.closeSubpath()
  }
  static let orbitFront = Path { p in
    p.move(to: CGPoint(x: 33, y: 144))
    p.addCurve(to: CGPoint(x: 71, y: 143), control1: CGPoint(x: 38, y: 131), control2: CGPoint(x: 61, y: 129))
    p.addCurve(to: CGPoint(x: 57, y: 167), control1: CGPoint(x: 77, y: 156), control2: CGPoint(x: 69, y: 166))
    p.addCurve(to: CGPoint(x: 33, y: 144), control1: CGPoint(x: 42, y: 169), control2: CGPoint(x: 31, y: 159))
    p.closeSubpath()
  }
  static let frontalFront = Path { p in
    p.move(to: CGPoint(x: 86, y: 124))
    p.addCurve(to: CGPoint(x: 61, y: 116), control1: CGPoint(x: 78, y: 128), control2: CGPoint(x: 63, y: 124))
    p.addCurve(to: CGPoint(x: 71, y: 105), control1: CGPoint(x: 60, y: 108), control2: CGPoint(x: 66, y: 103))
    p.addCurve(to: CGPoint(x: 86, y: 108), control1: CGPoint(x: 75, y: 98), control2: CGPoint(x: 84, y: 100))
    p.addQuadCurve(to: CGPoint(x: 86, y: 124), control: CGPoint(x: 89, y: 117))
    p.closeSubpath()
  }
  static let maxillaryFront = Path { p in
    p.move(to: CGPoint(x: 35, y: 179))
    p.addCurve(to: CGPoint(x: 70, y: 177), control1: CGPoint(x: 42, y: 174), control2: CGPoint(x: 59, y: 173))
    p.addCurve(to: CGPoint(x: 60, y: 222), control1: CGPoint(x: 77, y: 182), control2: CGPoint(x: 70, y: 212))
    p.addCurve(to: CGPoint(x: 37, y: 205), control1: CGPoint(x: 52, y: 230), control2: CGPoint(x: 42, y: 214))
    p.addQuadCurve(to: CGPoint(x: 35, y: 179), control: CGPoint(x: 29, y: 189))
    p.closeSubpath()
  }
  static let profile = Path { p in
    p.move(to: CGPoint(x: 208, y: 125))
    p.addCurve(to: CGPoint(x: 261, y: 71), control1: CGPoint(x: 208, y: 91), control2: CGPoint(x: 228, y: 72))
    p.addCurve(to: CGPoint(x: 334, y: 130), control1: CGPoint(x: 301, y: 69), control2: CGPoint(x: 331, y: 91))
    p.addCurve(to: CGPoint(x: 315, y: 204), control1: CGPoint(x: 338, y: 163), control2: CGPoint(x: 327, y: 184))
    p.addQuadCurve(to: CGPoint(x: 313, y: 273), control: CGPoint(x: 307, y: 219))
    p.addLine(to: CGPoint(x: 254, y: 273))
    p.addQuadCurve(to: CGPoint(x: 253, y: 247), control: CGPoint(x: 259, y: 257))
    p.addCurve(to: CGPoint(x: 216, y: 244), control1: CGPoint(x: 238, y: 253), control2: CGPoint(x: 221, y: 252))
    p.addQuadCurve(to: CGPoint(x: 216, y: 229), control: CGPoint(x: 214, y: 237))
    p.addQuadCurve(to: CGPoint(x: 214, y: 217), control: CGPoint(x: 204, y: 223))
    p.addQuadCurve(to: CGPoint(x: 210, y: 201), control: CGPoint(x: 207, y: 210))
    p.addCurve(to: CGPoint(x: 198, y: 183), control1: CGPoint(x: 190, y: 203), control2: CGPoint(x: 191, y: 194))
    p.addLine(to: CGPoint(x: 212, y: 159))
    p.addQuadCurve(to: CGPoint(x: 211, y: 144), control: CGPoint(x: 218, y: 150))
    p.addQuadCurve(to: CGPoint(x: 208, y: 125), control: CGPoint(x: 208, y: 140))
    p.closeSubpath()
  }
  static let noseProfile = Path { p in
    p.move(to: CGPoint(x: 207, y: 193))
    p.addCurve(to: CGPoint(x: 254, y: 158), control1: CGPoint(x: 217, y: 171), control2: CGPoint(x: 235, y: 157))
    p.addCurve(to: CGPoint(x: 288, y: 180), control1: CGPoint(x: 273, y: 157), control2: CGPoint(x: 287, y: 166))
    p.addQuadCurve(to: CGPoint(x: 296, y: 239), control: CGPoint(x: 285, y: 211))
    p.addLine(to: CGPoint(x: 286, y: 243))
    p.addCurve(to: CGPoint(x: 268, y: 199), control1: CGPoint(x: 277, y: 224), control2: CGPoint(x: 278, y: 205))
    p.addCurve(to: CGPoint(x: 211, y: 198), control1: CGPoint(x: 249, y: 197), control2: CGPoint(x: 223, y: 194))
    p.addQuadCurve(to: CGPoint(x: 207, y: 193), control: CGPoint(x: 205, y: 199))
    p.closeSubpath()
  }
  static let mouthProfile = Path { p in
    p.move(to: CGPoint(x: 217, y: 216))
    p.addCurve(to: CGPoint(x: 274, y: 218), control1: CGPoint(x: 235, y: 202), control2: CGPoint(x: 262, y: 202))
    p.addQuadCurve(to: CGPoint(x: 281, y: 240), control: CGPoint(x: 280, y: 230))
    p.addCurve(to: CGPoint(x: 224, y: 226), control1: CGPoint(x: 270, y: 231), control2: CGPoint(x: 249, y: 227))
    p.addQuadCurve(to: CGPoint(x: 217, y: 216), control: CGPoint(x: 212, y: 226))
    p.closeSubpath()
  }
  static let frontalProfile = Path { p in
    p.move(to: CGPoint(x: 219, y: 133))
    p.addCurve(to: CGPoint(x: 225, y: 106), control1: CGPoint(x: 214, y: 122), control2: CGPoint(x: 218, y: 109))
    p.addCurve(to: CGPoint(x: 235, y: 120), control1: CGPoint(x: 233, y: 105), control2: CGPoint(x: 236, y: 113))
    p.addQuadCurve(to: CGPoint(x: 223, y: 137), control: CGPoint(x: 231, y: 130))
    p.closeSubpath()
  }
  static let sphenoid = Path { p in
    p.move(to: CGPoint(x: 258, y: 149))
    p.addCurve(to: CGPoint(x: 279, y: 137), control1: CGPoint(x: 258, y: 141), control2: CGPoint(x: 268, y: 135))
    p.addCurve(to: CGPoint(x: 287, y: 153), control1: CGPoint(x: 290, y: 138), control2: CGPoint(x: 293, y: 146))
    p.addCurve(to: CGPoint(x: 258, y: 154), control1: CGPoint(x: 283, y: 159), control2: CGPoint(x: 263, y: 160))
    p.closeSubpath()
  }
  static let bone = Path { p in
    p.move(to: CGPoint(x: 33, y: 169))
    p.addCurve(to: CGPoint(x: 49, y: 117), control1: CGPoint(x: 37, y: 143), control2: CGPoint(x: 44, y: 140))
    p.addCurve(to: CGPoint(x: 98, y: 69), control1: CGPoint(x: 52, y: 91), control2: CGPoint(x: 72, y: 72))
    p.addCurve(to: CGPoint(x: 186, y: 77), control1: CGPoint(x: 129, y: 64), control2: CGPoint(x: 160, y: 67))
    p.addQuadCurve(to: CGPoint(x: 222, y: 82), control: CGPoint(x: 209, y: 86))
    p.addCurve(to: CGPoint(x: 319, y: 86), control1: CGPoint(x: 256, y: 58), control2: CGPoint(x: 299, y: 62))
    p.addCurve(to: CGPoint(x: 325, y: 176), control1: CGPoint(x: 336, y: 105), control2: CGPoint(x: 324, y: 147))
    p.addCurve(to: CGPoint(x: 311, y: 269), control1: CGPoint(x: 331, y: 225), control2: CGPoint(x: 323, y: 256))
    p.addCurve(to: CGPoint(x: 226, y: 274), control1: CGPoint(x: 296, y: 283), control2: CGPoint(x: 252, y: 279))
    p.addCurve(to: CGPoint(x: 155, y: 280), control1: CGPoint(x: 203, y: 270), control2: CGPoint(x: 171, y: 266))
    p.addCurve(to: CGPoint(x: 102, y: 276), control1: CGPoint(x: 140, y: 293), control2: CGPoint(x: 115, y: 292))
    p.addCurve(to: CGPoint(x: 61, y: 219), control1: CGPoint(x: 90, y: 264), control2: CGPoint(x: 83, y: 233))
    p.addCurve(to: CGPoint(x: 33, y: 169), control1: CGPoint(x: 42, y: 207), control2: CGPoint(x: 27, y: 194))
    p.closeSubpath()
  }
  static let orbitSection = Path { p in
    p.move(to: CGPoint(x: 56, y: 111))
    p.addCurve(to: CGPoint(x: 130, y: 79), control1: CGPoint(x: 66, y: 84), control2: CGPoint(x: 103, y: 77))
    p.addCurve(to: CGPoint(x: 201, y: 109), control1: CGPoint(x: 161, y: 80), control2: CGPoint(x: 192, y: 90))
    p.addQuadCurve(to: CGPoint(x: 188, y: 126), control: CGPoint(x: 206, y: 124))
    p.addCurve(to: CGPoint(x: 64, y: 129), control1: CGPoint(x: 149, y: 119), control2: CGPoint(x: 87, y: 119))
    p.addQuadCurve(to: CGPoint(x: 56, y: 111), control: CGPoint(x: 51, y: 129))
    p.closeSubpath()
  }
  static let maxillarySection = Path { p in
    p.move(to: CGPoint(x: 54, y: 158))
    p.addCurve(to: CGPoint(x: 143, y: 131), control1: CGPoint(x: 65, y: 139), control2: CGPoint(x: 107, y: 129))
    p.addCurve(to: CGPoint(x: 204, y: 144), control1: CGPoint(x: 165, y: 131), control2: CGPoint(x: 194, y: 132))
    p.addCurve(to: CGPoint(x: 203, y: 191), control1: CGPoint(x: 214, y: 155), control2: CGPoint(x: 201, y: 173))
    p.addCurve(to: CGPoint(x: 150, y: 265), control1: CGPoint(x: 207, y: 224), control2: CGPoint(x: 186, y: 256))
    p.addCurve(to: CGPoint(x: 93, y: 231), control1: CGPoint(x: 119, y: 275), control2: CGPoint(x: 103, y: 255))
    p.addCurve(to: CGPoint(x: 54, y: 158), control1: CGPoint(x: 84, y: 210), control2: CGPoint(x: 47, y: 187))
    p.closeSubpath()
  }
  static let nasalSection = Path { p in
    p.move(to: CGPoint(x: 228, y: 108))
    p.addCurve(to: CGPoint(x: 293, y: 88), control1: CGPoint(x: 239, y: 87), control2: CGPoint(x: 272, y: 77))
    p.addCurve(to: CGPoint(x: 307, y: 148), control1: CGPoint(x: 307, y: 97), control2: CGPoint(x: 309, y: 117))
    p.addLine(to: CGPoint(x: 308, y: 244))
    p.addCurve(to: CGPoint(x: 267, y: 264), control1: CGPoint(x: 309, y: 262), control2: CGPoint(x: 290, y: 268))
    p.addCurve(to: CGPoint(x: 226, y: 248), control1: CGPoint(x: 245, y: 261), control2: CGPoint(x: 229, y: 263))
    p.addCurve(to: CGPoint(x: 230, y: 190), control1: CGPoint(x: 225, y: 230), control2: CGPoint(x: 231, y: 210))
    p.addCurve(to: CGPoint(x: 228, y: 108), control1: CGPoint(x: 228, y: 170), control2: CGPoint(x: 216, y: 135))
    p.closeSubpath()
  }
  static let middleTurbinate = Path { p in
    p.move(to: CGPoint(x: 224, y: 124))
    p.addCurve(to: CGPoint(x: 267, y: 133), control1: CGPoint(x: 238, y: 115), control2: CGPoint(x: 258, y: 121))
    p.addCurve(to: CGPoint(x: 266, y: 161), control1: CGPoint(x: 277, y: 145), control2: CGPoint(x: 275, y: 158))
    p.addCurve(to: CGPoint(x: 249, y: 150), control1: CGPoint(x: 258, y: 163), control2: CGPoint(x: 253, y: 157))
    p.addQuadCurve(to: CGPoint(x: 222, y: 139), control: CGPoint(x: 241, y: 139))
    p.closeSubpath()
  }
  static let lowerTurbinate = Path { p in
    p.move(to: CGPoint(x: 230, y: 202))
    p.addCurve(to: CGPoint(x: 276, y: 213), control1: CGPoint(x: 247, y: 194), control2: CGPoint(x: 267, y: 201))
    p.addCurve(to: CGPoint(x: 266, y: 233), control1: CGPoint(x: 284, y: 222), control2: CGPoint(x: 276, y: 235))
    p.addCurve(to: CGPoint(x: 228, y: 220), control1: CGPoint(x: 252, y: 231), control2: CGPoint(x: 252, y: 218))
    p.closeSubpath()
  }
  static let outlet = Path { p in
    p.move(to: CGPoint(x: 200, y: 151))
    p.addCurve(to: CGPoint(x: 220, y: 153), control1: CGPoint(x: 207, y: 146), control2: CGPoint(x: 215, y: 145))
    p.addQuadCurve(to: CGPoint(x: 239, y: 171), control: CGPoint(x: 225, y: 163))
  }
  static let outletEdges = Path { p in
    p.move(to: CGPoint(x: 198, y: 146))
    p.addCurve(to: CGPoint(x: 224, y: 150), control1: CGPoint(x: 208, y: 140), control2: CGPoint(x: 219, y: 142))
    p.addQuadCurve(to: CGPoint(x: 241, y: 166), control: CGPoint(x: 230, y: 160))
    p.move(to: CGPoint(x: 202, y: 156))
    p.addCurve(to: CGPoint(x: 216, y: 156), control1: CGPoint(x: 208, y: 151), control2: CGPoint(x: 213, y: 151))
    p.addQuadCurve(to: CGPoint(x: 237, y: 175), control: CGPoint(x: 221, y: 166))
  }
  static let faceDetails = Path { p in
    p.move(to: CGPoint(x: 90, y: 150))
    p.addQuadCurve(to: CGPoint(x: 98, y: 191), control: CGPoint(x: 91, y: 178))
    p.addQuadCurve(to: CGPoint(x: 90, y: 208), control: CGPoint(x: 103, y: 202))
    p.move(to: CGPoint(x: 70, y: 235))
    p.addQuadCurve(to: CGPoint(x: 110, y: 235), control: CGPoint(x: 90, y: 229))
    p.addQuadCurve(to: CGPoint(x: 70, y: 235), control: CGPoint(x: 90, y: 244))
  }
  static let noseDetails = Path { p in
    p.move(to: CGPoint(x: 219, y: 187))
    p.addCurve(to: CGPoint(x: 273, y: 177), control1: CGPoint(x: 234, y: 174), control2: CGPoint(x: 256, y: 171))
    p.move(to: CGPoint(x: 232, y: 190))
    p.addQuadCurve(to: CGPoint(x: 278, y: 188), control: CGPoint(x: 258, y: 181))
  }
  static let secretoryCell = Path { p in
    p.move(to: CGPoint(x: 151, y: 222))
    p.addCurve(to: CGPoint(x: 146, y: 252), control1: CGPoint(x: 150, y: 232), control2: CGPoint(x: 143, y: 238))
    p.addCurve(to: CGPoint(x: 156, y: 275), control1: CGPoint(x: 148, y: 263), control2: CGPoint(x: 156, y: 264))
    p.addQuadCurve(to: CGPoint(x: 168, y: 275), control: CGPoint(x: 162, y: 283))
    p.addCurve(to: CGPoint(x: 180, y: 247), control1: CGPoint(x: 168, y: 264), control2: CGPoint(x: 179, y: 258))
    p.addCurve(to: CGPoint(x: 173, y: 222), control1: CGPoint(x: 182, y: 235), control2: CGPoint(x: 173, y: 232))
    p.closeSubpath()
  }
}

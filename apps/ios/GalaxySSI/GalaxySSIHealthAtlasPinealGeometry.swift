import SwiftUI

enum GalaxySSIHealthAtlasPinealGeometry {
  static let opticWall = Path { p in
    p.move(to: CGPoint(x: 35, y: 170))
    p.addCurve(to: CGPoint(x: 86, y: 126), control1: CGPoint(x: 35, y: 151), control2: CGPoint(x: 57, y: 126))
    p.addCurve(to: CGPoint(x: 139, y: 168), control1: CGPoint(x: 116, y: 126), control2: CGPoint(x: 136, y: 145))
    p.addCurve(to: CGPoint(x: 87, y: 213), control1: CGPoint(x: 138, y: 194), control2: CGPoint(x: 117, y: 212))
    p.addCurve(to: CGPoint(x: 35, y: 170), control1: CGPoint(x: 60, y: 213), control2: CGPoint(x: 36, y: 191))
    p.closeSubpath()
  }
  static let vitreous = Path { p in
    p.move(to: CGPoint(x: 61, y: 151))
    p.addCurve(to: CGPoint(x: 130, y: 159), control1: CGPoint(x: 82, y: 130), control2: CGPoint(x: 119, y: 134))
    p.addCurve(to: CGPoint(x: 63, y: 192), control1: CGPoint(x: 147, y: 197), control2: CGPoint(x: 91, y: 218))
    p.addQuadCurve(to: CGPoint(x: 61, y: 151), control: CGPoint(x: 75, y: 172))
    p.closeSubpath()
  }
  static let retinaEdge = Path { p in
    p.move(to: CGPoint(x: 97, y: 136))
    p.addCurve(to: CGPoint(x: 133, y: 168), control1: CGPoint(x: 117, y: 139), control2: CGPoint(x: 131, y: 151))
    p.addCurve(to: CGPoint(x: 115, y: 199), control1: CGPoint(x: 135, y: 182), control2: CGPoint(x: 127, y: 191))
  }
  static let retinaFiber = Path { p in
    p.move(to: CGPoint(x: 130, y: 158))
    p.addCurve(to: CGPoint(x: 136, y: 183), control1: CGPoint(x: 136, y: 169), control2: CGPoint(x: 129, y: 177))
    p.addCurve(to: CGPoint(x: 203, y: 197), control1: CGPoint(x: 159, y: 205), control2: CGPoint(x: 182, y: 213))
    p.addQuadCurve(to: CGPoint(x: 221, y: 184), control: CGPoint(x: 208, y: 192))
  }
  static let cranialProfile = Path { p in
    p.move(to: CGPoint(x: 127, y: 51))
    p.addCurve(to: CGPoint(x: 223, y: 57), control1: CGPoint(x: 150, y: 27), control2: CGPoint(x: 201, y: 31))
    p.addCurve(to: CGPoint(x: 225, y: 132), control1: CGPoint(x: 242, y: 79), control2: CGPoint(x: 234, y: 112))
    p.addCurve(to: CGPoint(x: 227, y: 198), control1: CGPoint(x: 220, y: 148), control2: CGPoint(x: 217, y: 174))
    p.addQuadCurve(to: CGPoint(x: 263, y: 231), control: CGPoint(x: 242, y: 220))
    p.addQuadCurve(to: CGPoint(x: 280, y: 271), control: CGPoint(x: 277, y: 244))
    p.addQuadCurve(to: CGPoint(x: 121, y: 266), control: CGPoint(x: 209, y: 303))
    p.addCurve(to: CGPoint(x: 150, y: 212), control1: CGPoint(x: 134, y: 253), control2: CGPoint(x: 149, y: 234))
    p.addCurve(to: CGPoint(x: 140, y: 158), control1: CGPoint(x: 151, y: 198), control2: CGPoint(x: 143, y: 180))
    p.addCurve(to: CGPoint(x: 113, y: 144), control1: CGPoint(x: 128, y: 162), control2: CGPoint(x: 113, y: 154))
    p.addLine(to: CGPoint(x: 111, y: 131))
    p.addQuadCurve(to: CGPoint(x: 104, y: 119), control: CGPoint(x: 96, y: 130))
    p.addLine(to: CGPoint(x: 115, y: 101))
    p.addCurve(to: CGPoint(x: 127, y: 51), control1: CGPoint(x: 113, y: 83), control2: CGPoint(x: 115, y: 66))
    p.closeSubpath()
  }
  static let canal = Path { p in
    p.move(to: CGPoint(x: 187, y: 130))
    p.addCurve(to: CGPoint(x: 183, y: 207), control1: CGPoint(x: 189, y: 162), control2: CGPoint(x: 179, y: 181))
    p.addQuadCurve(to: CGPoint(x: 196, y: 270), control: CGPoint(x: 187, y: 238))
  }
  static let cell = Path { p in
    p.move(to: CGPoint(x: 85, y: 155))
    p.addCurve(to: CGPoint(x: 118, y: 128), control1: CGPoint(x: 94, y: 139), control2: CGPoint(x: 98, y: 135))
    p.addCurve(to: CGPoint(x: 149, y: 104), control1: CGPoint(x: 132, y: 114), control2: CGPoint(x: 129, y: 103))
    p.addCurve(to: CGPoint(x: 151, y: 117), control1: CGPoint(x: 153, y: 105), control2: CGPoint(x: 154, y: 111))
    p.addCurve(to: CGPoint(x: 221, y: 134), control1: CGPoint(x: 179, y: 111), control2: CGPoint(x: 208, y: 120))
    p.addCurve(to: CGPoint(x: 251, y: 162), control1: CGPoint(x: 233, y: 147), control2: CGPoint(x: 226, y: 159))
    p.addCurve(to: CGPoint(x: 289, y: 160), control1: CGPoint(x: 269, y: 164), control2: CGPoint(x: 281, y: 154))
    p.addCurve(to: CGPoint(x: 273, y: 181), control1: CGPoint(x: 298, y: 169), control2: CGPoint(x: 287, y: 179))
    p.addCurve(to: CGPoint(x: 244, y: 197), control1: CGPoint(x: 253, y: 184), control2: CGPoint(x: 245, y: 181))
    p.addCurve(to: CGPoint(x: 273, y: 230), control1: CGPoint(x: 244, y: 221), control2: CGPoint(x: 262, y: 218))
    p.addQuadCurve(to: CGPoint(x: 269, y: 246), control: CGPoint(x: 282, y: 242))
    p.addCurve(to: CGPoint(x: 220, y: 246), control1: CGPoint(x: 252, y: 241), control2: CGPoint(x: 240, y: 237))
    p.addCurve(to: CGPoint(x: 130, y: 241), control1: CGPoint(x: 193, y: 257), control2: CGPoint(x: 153, y: 253))
    p.addCurve(to: CGPoint(x: 77, y: 239), control1: CGPoint(x: 110, y: 234), control2: CGPoint(x: 94, y: 247))
    p.addCurve(to: CGPoint(x: 84, y: 221), control1: CGPoint(x: 66, y: 233), control2: CGPoint(x: 70, y: 226))
    p.addCurve(to: CGPoint(x: 93, y: 203), control1: CGPoint(x: 96, y: 217), control2: CGPoint(x: 99, y: 211))
    p.addCurve(to: CGPoint(x: 85, y: 155), control1: CGPoint(x: 83, y: 190), control2: CGPoint(x: 77, y: 172))
    p.closeSubpath()
  }
  static let axon = Path { p in
    p.move(to: CGPoint(x: 19, y: 93))
    p.addCurve(to: CGPoint(x: 53, y: 116), control1: CGPoint(x: 35, y: 92), control2: CGPoint(x: 37, y: 110))
    p.addQuadCurve(to: CGPoint(x: 69, y: 134), control: CGPoint(x: 67, y: 121))
    p.move(to: CGPoint(x: 45, y: 112))
    p.addQuadCurve(to: CGPoint(x: 51, y: 140), control: CGPoint(x: 42, y: 129))
    p.move(to: CGPoint(x: 35, y: 103))
    p.addQuadCurve(to: CGPoint(x: 55, y: 103), control: CGPoint(x: 47, y: 102))
  }
  static let vessel = Path { p in
    p.move(to: CGPoint(x: 186, y: 278))
    p.addCurve(to: CGPoint(x: 337, y: 230), control1: CGPoint(x: 232, y: 298), control2: CGPoint(x: 276, y: 250))
    p.addLine(to: CGPoint(x: 340, y: 200))
    p.addCurve(to: CGPoint(x: 182, y: 256), control1: CGPoint(x: 281, y: 222), control2: CGPoint(x: 235, y: 278))
    p.closeSubpath()
  }
  static let vesselLight = Path { p in
    p.move(to: CGPoint(x: 192, y: 263))
    p.addCurve(to: CGPoint(x: 334, y: 210), control1: CGPoint(x: 239, y: 279), control2: CGPoint(x: 293, y: 227))
  }
  static let curve = Path { p in
    for i in 0...110 {
      let t = Double(i)/110
      let point = CGPoint(x: cycleX(t), y: cycleY(t))
      if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
    }
  }
  static let curveArea = Path { p in
    p.addPath(curve); p.addLine(to: CGPoint(x: 326, y: 269))
    p.addLine(to: CGPoint(x: 34, y: 269)); p.closeSubpath()
  }
  static func cycleX(_ t: Double) -> Double { 34+292*t }
  static func cycleY(_ t: Double) -> Double { 269-145*GalaxySSIHealthAtlasPinealMotion.melatonin(t) }
}

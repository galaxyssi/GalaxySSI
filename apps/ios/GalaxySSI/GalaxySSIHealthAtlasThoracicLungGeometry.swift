import SwiftUI

enum GalaxySSIHealthAtlasThoracicLungGeometry {
  static func front(_ b: Double, heartSide: Bool) -> Path {
    let reach = 105+12*b, base = 239+5*b, notch = heartSide ? 11.0 : 0.0
    return Path { p in
      p.move(to: CGPoint(x: 27, y: 83))
      p.addCurve(to: CGPoint(x: 96, y: 161), control1: CGPoint(x: 49, y: 69), control2: CGPoint(x: 83, y: 112))
      p.addQuadCurve(to: CGPoint(x: reach, y: base), control: CGPoint(x: reach + 4, y: 194))
      p.addCurve(to: CGPoint(x: 36, y: 217 + 16 * b), control1: CGPoint(x: 74, y: base - 18), control2: CGPoint(x: 58, y: 205 + 20 * b))
      p.addQuadCurve(to: CGPoint(x: 9, y: 234 + 9 * b), control: CGPoint(x: 22, y: 223 + 16 * b))
      p.addCurve(to: CGPoint(x: 17 + notch, y: 172), control1: CGPoint(x: 10 + notch, y: 208), control2: CGPoint(x: 7 + notch, y: 187))
      p.addCurve(to: CGPoint(x: 27, y: 83), control1: CGPoint(x: 32 + notch, y: 149), control2: CGPoint(x: 12, y: 114))
      p.closeSubpath()
    }
  }
  static func frontDetail(_ b: Double, heartSide: Bool) -> Path {
    let reach = 105+12*b
    return Path { p in
      p.move(to: CGPoint(x: 31, y: 139))
      p.addQuadCurve(to: CGPoint(x: reach-3, y: 194+5*b), control: CGPoint(x: 62, y: 180))
      if !heartSide {
        p.move(to: CGPoint(x: 45, y: 160))
        p.addQuadCurve(to: CGPoint(x: 93, y: 162), control: CGPoint(x: 70, y: 156))
      }
    }
  }
  static func frontDiaphragm(_ b: Double) -> Path {
    let reach = 105+12*b, base = 239+5*b
    return Path { p in
      p.move(to: CGPoint(x: 9, y: 234 + 9 * b))
      p.addQuadCurve(to: CGPoint(x: 36, y: 217 + 16 * b), control: CGPoint(x: 22, y: 223 + 16 * b))
      p.addCurve(to: CGPoint(x: reach, y: base), control1: CGPoint(x: 58, y: 205 + 20 * b), control2: CGPoint(x: 74, y: base - 18))
      p.addCurve(to: CGPoint(x: 39, y: 228 + 16 * b), control1: CGPoint(x: 78, y: base - 8), control2: CGPoint(x: 61, y: 216 + 20 * b))
      p.addQuadCurve(to: CGPoint(x: 9, y: 243 + 9 * b), control: CGPoint(x: 22, y: 233 + 16 * b))
      p.closeSubpath()
    }
  }
  static func profile(_ b: Double) -> Path {
    let front = 248+12*b, dome = 210+17*b
    return Path { p in
      p.move(to: CGPoint(x: 130, y: 83))
      p.addCurve(to: CGPoint(x: front - 15, y: 146), control1: CGPoint(x: 158, y: 67), control2: CGPoint(x: front - 29, y: 102))
      p.addQuadCurve(to: CGPoint(x: front, y: 225 + 6 * b), control: CGPoint(x: front - 1, y: 178))
      p.addCurve(to: CGPoint(x: 153, y: dome + 4), control1: CGPoint(x: 224, y: dome + 5), control2: CGPoint(x: 182, y: dome - 15))
      p.addQuadCurve(to: CGPoint(x: 115, y: 251 + 2 * b), control: CGPoint(x: 127, y: dome + 14))
      p.addCurve(to: CGPoint(x: 130, y: 83), control1: CGPoint(x: 103, y: 215), control2: CGPoint(x: 112, y: 105))
      p.closeSubpath()
    }
  }
  static func profileDetail(_ b: Double) -> Path {
    let front = 248+12*b, dome = 210+17*b
    return Path { p in
      p.move(to: CGPoint(x: 130, y: 148))
      p.addQuadCurve(to: CGPoint(x: 177, y: dome - 5), control: CGPoint(x: 163, y: 169))
      p.move(to: CGPoint(x: 152, y: 165))
      p.addQuadCurve(to: CGPoint(x: front - 11, y: 172), control: CGPoint(x: 191, y: 158))
    }
  }
  static func profileDiaphragm(_ b: Double) -> Path {
    let front = 248+12*b, dome = 210+17*b
    return Path { p in
      p.move(to: CGPoint(x: front, y: 225 + 6 * b))
      p.addCurve(to: CGPoint(x: 153, y: dome + 4), control1: CGPoint(x: 224, y: dome + 5), control2: CGPoint(x: 182, y: dome - 15))
      p.addQuadCurve(to: CGPoint(x: 115, y: 251 + 2 * b), control: CGPoint(x: 127, y: dome + 14))
      p.addLine(to: CGPoint(x: 117, y: 260 + 2 * b))
      p.addQuadCurve(to: CGPoint(x: 158, y: dome + 12), control: CGPoint(x: 138, y: dome + 19))
      p.addCurve(to: CGPoint(x: front, y: 234 + 6 * b), control1: CGPoint(x: 188, y: dome - 6), control2: CGPoint(x: 224, y: dome + 15))
      p.closeSubpath()
    }
  }
}

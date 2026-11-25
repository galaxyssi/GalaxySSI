import SwiftUI

enum GalaxySSIHealthAtlasMicrogliaGeometry {
  static let field = Path(roundedRect: CGRect(x: 1, y: 1, width: 358, height: 358), cornerRadius: 8)
  static let soma = Path { p in
    p.move(to: CGPoint(x: 125, y: 170))
    p.addCurve(to: CGPoint(x: 153, y: 154), control1: CGPoint(x: 131, y: 159), control2: CGPoint(x: 138, y: 153))
    p.addCurve(to: CGPoint(x: 181, y: 169), control1: CGPoint(x: 164, y: 153), control2: CGPoint(x: 179, y: 161))
    p.addCurve(to: CGPoint(x: 157, y: 191), control1: CGPoint(x: 183, y: 178), control2: CGPoint(x: 172, y: 188))
    p.addCurve(to: CGPoint(x: 125, y: 170), control1: CGPoint(x: 142, y: 195), control2: CGPoint(x: 119, y: 184))
    p.closeSubpath()
  }
  static let neuron = Path { p in
    p.move(to: CGPoint(x: -29, y: -24))
    p.addCurve(to: CGPoint(x: 9, y: -26), control1: CGPoint(x: -16, y: -15), control2: CGPoint(x: -10, y: -28))
    p.addCurve(to: CGPoint(x: 49, y: -15), control1: CGPoint(x: 28, y: -25), control2: CGPoint(x: 30, y: -9))
    p.addCurve(to: CGPoint(x: 25, y: 15), control1: CGPoint(x: 34, y: -3), control2: CGPoint(x: 25, y: 3))
    p.addCurve(to: CGPoint(x: 52, y: 43), control1: CGPoint(x: 30, y: 32), control2: CGPoint(x: 41, y: 34))
    p.addCurve(to: CGPoint(x: 9, y: 24), control1: CGPoint(x: 32, y: 39), control2: CGPoint(x: 25, y: 24))
    p.addCurve(to: CGPoint(x: -33, y: 21), control1: CGPoint(x: -12, y: 24), control2: CGPoint(x: -16, y: 13))
    p.addCurve(to: CGPoint(x: -29, y: -24), control1: CGPoint(x: -19, y: 8), control2: CGPoint(x: -20, y: -9))
    p.closeSubpath()
  }
  static let neuropil: [Path] = [
    Path { p in
      p.move(to: CGPoint(x: 0, y: 112))
      p.addCurve(to: CGPoint(x: 0, y: 222), control1: CGPoint(x: 39, y: 133), control2: CGPoint(x: 31, y: 188))
    },
    Path { p in
      p.move(to: CGPoint(x: 43, y: 0))
      p.addCurve(to: CGPoint(x: 117, y: 24), control1: CGPoint(x: 19, y: 41), control2: CGPoint(x: 91, y: 48))
      p.addQuadCurve(to: CGPoint(x: 160, y: 4), control: CGPoint(x: 136, y: 9))
    },
    Path { p in
      p.move(to: CGPoint(x: 64, y: 0))
      p.addCurve(to: CGPoint(x: 145, y: 81), control1: CGPoint(x: 45, y: 47), control2: CGPoint(x: 136, y: 31))
    },
    Path { p in
      p.move(to: CGPoint(x: 0, y: 241))
      p.addCurve(to: CGPoint(x: 72, y: 280), control1: CGPoint(x: 40, y: 224), control2: CGPoint(x: 49, y: 249))
      p.addQuadCurve(to: CGPoint(x: 137, y: 325), control: CGPoint(x: 99, y: 312))
    },
    Path { p in
      p.move(to: CGPoint(x: 182, y: 355))
      p.addCurve(to: CGPoint(x: 152, y: 263), control1: CGPoint(x: 207, y: 304), control2: CGPoint(x: 185, y: 277))
      p.addQuadCurve(to: CGPoint(x: 131, y: 230), control: CGPoint(x: 128, y: 252))
    },
    Path { p in
      p.move(to: CGPoint(x: 356, y: 75))
      p.addCurve(to: CGPoint(x: 259, y: 99), control1: CGPoint(x: 307, y: 52), control2: CGPoint(x: 302, y: 113))
      p.addQuadCurve(to: CGPoint(x: 232, y: 73), control: CGPoint(x: 242, y: 93))
    },
    Path { p in
      p.move(to: CGPoint(x: 356, y: 190))
      p.addCurve(to: CGPoint(x: 284, y: 208), control1: CGPoint(x: 331, y: 161), control2: CGPoint(x: 295, y: 180))
      p.addQuadCurve(to: CGPoint(x: 243, y: 239), control: CGPoint(x: 275, y: 230))
    },
    Path { p in
      p.move(to: CGPoint(x: 356, y: 268))
      p.addCurve(to: CGPoint(x: 314, y: 329), control1: CGPoint(x: 322, y: 251), control2: CGPoint(x: 307, y: 287))
      p.addQuadCurve(to: CGPoint(x: 307, y: 356), control: CGPoint(x: 316, y: 346))
    },
  ]
}

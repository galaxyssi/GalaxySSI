import Foundation

enum GalaxySSIHealthAtlasNailMotion {
  static let curve = 0.0011, rootX = 126.0, matrixEnd = 161.0, bedEnd = 274.0, thickness = 10.0
  static func y(_ x: Double) -> Double {
    let d = x - 206
    return 154 + curve * d * d
  }
  static func ease(_ t: Double) -> Double {
    let f = t.isFinite ? min(1, max(0, t)) : 0
    return f * f * (3 - 2 * f)
  }
  static func slide(_ step: Int, _ t: Double) -> Double {
    switch step {
    case 3: return 12 * ease(t / 0.9)
    case 4: return 12 + 23 * ease((t - 0.09) / 0.85)
    default: return 0
    }
  }
  struct Division { let x: Double; let y: Double; let separation: Double; let radius: Double }
  static func division(_ t: Double, _ index: Int) -> Division {
    let i = Double(index), split = ease((t - 0.13 - 0.12 * i) / 0.5)
    return .init(x: 108 + i * 12, y: 190 - i * 4, separation: 3.6 * split, radius: 4.5 - 1.2 * split)
  }
  struct Maturation { let x: Double; let y: Double; let rx: Double; let ry: Double; let alpha: Int }
  static func maturation(_ t: Double, _ index: Int) -> Maturation {
    let i = Double(index), enter = ease((t - i * 0.09) / 0.8), flatten = ease((enter - 0.15) / 0.78)
    let x = 110 + 10 * i + 29 * enter, startY = 190 - 3.4 * i
    return .init(x: x, y: startY + (y(x) + 5.5 - startY) * enter, rx: 3.5 + 4 * flatten, ry: 4.4 - 3.1 * flatten, alpha: Int(255 * (1 - flatten)))
  }
}

import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasDeltoidMotion {
  static let roots: [CGPoint] = [.init(x: 148, y: 129), .init(x: 186, y: 112), .init(x: 216, y: 109), .init(x: 231, y: 124)]
  static let neutralControls: [CGPoint] = [.init(x: 148, y: 167), .init(x: 184, y: 162), .init(x: 223, y: 154), .init(x: 245, y: 151)]
  static let restingEnds: [CGPoint] = [.init(x: 211, y: 224), .init(x: 214, y: 225), .init(x: 217, y: 225), .init(x: 220, y: 223)]
  static let fiberInks: [UInt32] = [0x795B85, 0x9E607F, 0x9F645F]
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func pose(_ step: Int, _ t: Double) -> Double {
    let t = safe(t), ease = t*t*(3-2*t)
    // Overlapping teaching poses, not measured joint angles or recruitment phases.
    switch step {
    case 1: return 0.36*ease
    case 2: return 0.36+0.64*ease
    case 3: return 1-ease
    default: return 0
    }
  }
  static func blend(_ a: Double, _ b: Double, _ t: Double) -> Double { a+(b-a)*t }
  static func partFocus(_ band: Int, _ t: Double) -> Double { max(0, 1-abs(3*t-Double(band)-0.5)) }
}

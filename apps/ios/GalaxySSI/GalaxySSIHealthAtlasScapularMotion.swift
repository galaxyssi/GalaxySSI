import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasScapularMotion {
  static let sites: [CGPoint] = [.init(x: 253, y: 114), .init(x: 243, y: 125), .init(x: 193, y: 143), .init(x: 187, y: 153), .init(x: 194, y: 247), .init(x: 251, y: 142), .init(x: 181, y: 177)]
  static let ribEnds: [CGPoint] = [.init(x: 264, y: 173), .init(x: 276, y: 193), .init(x: 277, y: 214), .init(x: 270, y: 237), .init(x: 265, y: 254)]
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func pose(_ step: Int, _ t: Double) -> Double {
    let t = safe(t), ease = t*t*(3-2*t)
    // Continuous 2D teaching poses, without fixed forces or on/off muscle phases.
    switch step {
    case 1: return 0.18*ease
    case 2: return 0.18+0.41*ease
    case 3: return 0.59+0.41*ease
    case 4: return 1-ease
    default: return 0
    }
  }
  static func blend(_ a: Double, _ b: Double, _ t: Double) -> Double { a+(b-a)*t }
  static func regionFocus(_ band: Int, _ t: Double) -> Double { max(0,1-abs(4*t-Double(band)-0.5)) }
}

import Foundation
import CoreGraphics

enum GalaxySSIHealthAtlasPectoralActionMotion {
  static let startAngle = -12.0, sweepAngle = 122.0
  static func angle(_ chapter: Int, _ fraction: Double) -> Double {
    let f = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction), t = f * f * (3 - 2 * f)
    let progress = chapter == 2 ? 0.48 * t : chapter == 3 ? 0.48 + 0.52 * t : chapter == 4 ? 1 - t : 0
    return startAngle + sweepAngle * progress
  }
  static func attachment(_ angle: Double) -> CGPoint {
    let radians = angle * .pi / 180
    return CGPoint(x: 223 + 29 * cos(radians) - 8 * sin(radians), y: 147 + 29 * sin(radians) + 8 * cos(radians))
  }
}

enum GalaxySSIHealthAtlasLatissimusActionMotion {
  static func pose(_ chapter: Int, _ fraction: Double) -> Double {
    let f = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    switch chapter {
    case 2: return ease(f)
    case 3: return 1 + ease(f)
    case 4: return f < 0.5 ? 2 - ease(f * 2) : 1 - ease(f * 2 - 1)
    default: return 0
    }
  }
  static func project(_ pose: Double) -> CGPoint {
    let anteriorRadius = sqrt(1 - 0.52 * 0.52), backDepth = anteriorRadius * sin(-0.12)
    let lateral: Double, anterior: Double, down: Double
    if pose <= 1 {
      let angle = 1.18 + (-0.12 - 1.18) * pose
      lateral = 0.52; anterior = anteriorRadius * sin(angle); down = anteriorRadius * cos(angle)
    } else {
      lateral = 0.52 + (0.10 - 0.52) * (pose - 1); anterior = backDepth
      down = sqrt(1 - lateral * lateral - anterior * anterior)
    }
    return CGPoint(x: 0.65 * lateral + 0.76 * anterior, y: 0.98 * down + 0.15 * lateral - 0.13 * anterior)
  }
}

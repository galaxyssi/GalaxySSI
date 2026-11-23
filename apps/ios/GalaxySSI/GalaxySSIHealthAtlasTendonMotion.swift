import Foundation

struct GalaxySSIHealthAtlasTendonMotion {
  let load: Double
  var join: Double { 148 - 15 * load }
  var narrow: Double { 2 * load }
  var bulge: Double { 5 * load }
  var first: Double { 56 - 10 * load }
  var halfWave: Double { (304 - first) / 8 }
  var crimp: Double { 10 - 8.8 * load }
  var arrowLength: Double { 7 + 46 * load }
  var arrowBase: Double { 4 + 4 * load }
  var arrowWing: Double { 2.5 + 2 * load }
  var arrowWidth: Double { 1.8 + 1.1 * load }
  var arrowAlpha: Int { Int(255 * min(1, load * 4)) }
  init(step: Int, fraction: Double) {
    let t = fraction.isFinite ? min(1, max(0, fraction)) : 0, eased = t * t * (3 - 2 * t)
    switch step {
    case 1: load = 0.28 * eased
    case 2: load = 0.28 + (0.82 - 0.28) * eased
    case 3: load = 0.82 + (1 - 0.82) * eased
    case 4: load = 1 - eased
    default: load = 0
    }
  }
  static func focusAlpha(_ progress: Double) -> Int {
    guard progress.isFinite, progress > 0, progress < 1 else { return 0 }
    return Int(220 * (1 - abs(2 * progress - 1)))
  }
}

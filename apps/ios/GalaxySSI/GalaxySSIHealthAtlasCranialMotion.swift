import Foundation

enum GalaxySSIHealthAtlasCranialMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let p = min(1, max(0, (t - start) / (end - start)))
    return p * p * (3 - 2 * p)
  }
  struct Frame {
    let step: Int
    let t: Double
    let narrowing: Double
    let radius: Double
    let pretectal: Double
    let pupilDrive: Double
    let ganglionDrive: Double
    init(step: Int, fraction: Double) {
      self.step = step
      t = fraction.isFinite ? min(1, max(0, fraction)) : 0
      narrowing = step == 4 ? ease(t, 0.08, 0.84) : 0
      radius = 12.6 - 6.6 * narrowing
      switch step {
      case 1: pretectal = ease(t, 0.66, 0.94)
      case 2: pretectal = 1 - 0.48 * ease(t, 0.12, 0.68)
      default: pretectal = 0
      }
      switch step {
      case 2: pupilDrive = ease(t, 0.44, 0.88)
      case 3: pupilDrive = 1 - 0.65 * ease(t, 0, 0.44)
      default: pupilDrive = 0
      }
      ganglionDrive = step == 3 ? ease(t, 0.46, 0.59) * (1 - 0.8 * ease(t, 0.68, 0.96)) : 0
    }
  }
}

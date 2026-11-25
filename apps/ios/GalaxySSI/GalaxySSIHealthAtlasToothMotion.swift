import Foundation

enum GalaxySSIHealthAtlasToothMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let x = min(1, max(0, (t - start) / (end - start)))
    return x * x * (3 - 2 * x)
  }
  struct Bite { let close: Double; let angle: Double; let separation: Double }
  static func bite(_ t: Double) -> Bite {
    let close = ease(t, 0.18, 0.52), release = ease(t, 0.60, 0.93)
    return .init(close: close, angle: -9 + 8.4 * close - 5 * release, separation: ease(t, 0.52, 0.92))
  }
  struct Tear { let pull: Double; let angle: Double }
  static func tear(_ t: Double) -> Tear {
    let close = ease(t, 0.08, 0.31), pull = ease(t, 0.31, 0.87)
    return .init(pull: pull, angle: -6.8 + 6.1 * close - 3.3 * ease(t, 0.66, 0.96))
  }
  struct Grinding { let close: Double; let shear: Double; let jawX: Double; let jawY: Double; let breakUp: Double }
  static func grinding(_ t: Double) -> Grinding {
    let cycle = (1.65 * t).truncatingRemainder(dividingBy: 1)
    let close = ease(cycle, 0.11, 0.46) - ease(cycle, 0.70, 1)
    let shear = ease(cycle, 0.28, 0.69) - ease(cycle, 0.75, 1)
    return .init(close: close, shear: shear, jawX: 10 * shear, jawY: 17 - 16 * close, breakUp: ease(t, 0.24, 0.68))
  }
  struct Bolus { let place: Double; let wet: Double; let jawX: Double; let jawY: Double; let x: Double; let y: Double }
  static func bolus(_ t: Double) -> Bolus {
    let opening = ease(t, 0.03, 0.48) - 0.46 * ease(t, 0.79, 1)
    let place = ease(t, 0.19, 0.87), wet = ease(t, 0.30, 0.80)
    let jawX = 5 * opening, jawY = 12 + 17 * opening
    return .init(place: place, wet: wet, jawX: jawX, jawY: jawY, x: 198 + 65 * place, y: 202 - 12 * place + jawY * 0.38)
  }
}

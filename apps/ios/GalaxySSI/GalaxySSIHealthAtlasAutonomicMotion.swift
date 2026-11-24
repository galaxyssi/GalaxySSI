import Foundation

enum GalaxySSIHealthAtlasAutonomicMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func segment(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1, max(0, (safe(t) - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
  static func bump(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1, max(0, (safe(t) - start) / (end - start)))
    return 4 * f * (1 - f)
  }
  static func output(_ t: Double, vagal: Bool) -> Double {
    vagal ? segment(t, 0.08, 0.95) * 0.64 : segment(t, 0.18, 0.9) * 0.86
  }
  static func sympatheticApproach(_ t: Double) -> Double { segment(t, 0.04, 0.52) }
  static func sympatheticHandoff(_ t: Double) -> Double { bump(t, 0.46, 0.89) }
  static func sympatheticExit(_ t: Double) -> Double { segment(t, 0.64, 0.98) * 0.33 }
  static func cardiacArrival(_ t: Double) -> Double { segment(t, 0.06, 0.68) }
  static func beatSpacing(_ t: Double) -> Double { 49 - 17 * segment(t, 0.38, 0.96) }
  static func vagalDescent(_ t: Double) -> Double { segment(t, 0.03, 0.62) }
  static func vagalHandoff(_ t: Double) -> Double { bump(t, 0.55, 0.89) }
  static func vagalExit(_ t: Double) -> Double { segment(t, 0.68, 0.98) }
  static func ongoing(_ t: Double, vagal: Bool) -> Double {
    let phase = safe(t)
    return (vagal ? 0.83 * phase + 0.38 : 1.10 * phase + 0.12).truncatingRemainder(dividingBy: 1)
  }
  struct Comparison {
    let handoff: Double
    let onFirst: Bool
    let fraction: Double
    init(split: Double, phase: Double) {
      handoff = min(1, max(0, 1 - abs(phase - split) / 0.08))
      onFirst = phase < split
      fraction = onFirst ? phase / split : (phase - split) / (1 - split)
    }
  }
}

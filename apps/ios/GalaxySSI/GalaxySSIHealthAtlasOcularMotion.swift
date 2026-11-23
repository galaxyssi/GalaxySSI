import Foundation

struct GalaxySSIHealthAtlasOcularMotion {
  enum Course: Equatable { case visualCycle, dimRelay, cornea }
  let course: Course
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    course = courseID == "RPE_VISUAL_CYCLE" ? .visualCycle : courseID == "DIM_LIGHT_RELAY" ? .dimRelay : .cornea
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func transfer(_ t: Double, returnToRod: Bool) -> Double {
    let f = safePhase(t)
    return returnToRod ? 238 - 66 * f : 172 + 66 * f
  }
  static func limbalRadius(_ t: Double) -> Double { 104 - 76 * safePhase(t) }
  static func relayFraction(_ t: Double, index: Int) -> Double {
    guard (0...7).contains(index) else { return 0 }
    return min(1, max(0, (safePhase(t) - 0.08 * Double(index)) * 1.24))
  }
}

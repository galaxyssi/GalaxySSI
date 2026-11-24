import Foundation

// A synchronized teaching sequence, not a membrane-voltage measurement.
enum GalaxySSIHealthAtlasRodResponse {
  static func light(_ t: Double) -> Double { transition(t, start: 0.24, end: 0.36) }
  static func messenger(_ t: Double) -> Double { 1 - 0.86 * transition(t, start: 0.30, end: 0.61) }
  static func opening(_ t: Double) -> Double { 1 - transition(t, start: 0.38, end: 0.72) }
  static func release(_ t: Double) -> Double { 1 - 0.77 * transition(t, start: 0.56, end: 0.92) }
  private static func transition(_ time: Double, start: Double, end: Double) -> Double {
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(time)
    let f = min(1, max(0, (t - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
}

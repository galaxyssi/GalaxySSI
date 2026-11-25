import Foundation

enum GalaxySSIHealthAtlasUterocervicalMotion {
  private static func ease(_ value: Double) -> Double {
    let f = min(1, max(0, value))
    return f * f * (3 - 2 * f)
  }
  static func sweep(_ fraction: Double) -> Double {
    ease((GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction) - 0.08) / 0.84)
  }
  static func wallEmphasis(_ fraction: Double, layer: Int) -> Double {
    ease(1 - abs(GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction) - (0.17 + 0.33 * Double(layer))) / 0.26)
  }
  static func foldDepth(_ fraction: Double) -> Double {
    1 - 0.53 * ease(1 - abs(2 * GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction) - 1))
  }
}

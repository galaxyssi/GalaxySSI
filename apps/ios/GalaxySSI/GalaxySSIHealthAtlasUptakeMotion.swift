import Foundation

struct GalaxySSIHealthAtlasUptakeMotion: Equatable {
  let chapter: Int
  let fraction: Double
  static let surface: Double = 275
  static let radius: Double = 23
  init(chapter: Int, fraction: Double) {
    self.chapter = min(4, max(0, chapter))
    self.fraction = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
  }
  var approach: Double { chapter >= 3 ? Self.ease(chapter == 3 ? fraction / 0.58 : 1) : 0 }
  var flatten: Double { chapter >= 3 ? Self.ease(chapter == 3 ? (fraction - 0.58) / 0.42 : 1) : 0 }
  var radiusY: Double { Self.radius * (1 - flatten) }
  var opening: Double { 90 * flatten }
  var vesicleX: Double { 158 + 87 * approach }
  var vesicleY: Double {
    210 + (Self.surface - Self.radius - 210) * approach + Self.radius - radiusY * cos(opening * 0.017453293)
  }
  var transporterX: Double { vesicleX + Self.radius }
  var transporterY: Double { vesicleY }
  var transporterRotation: Double { -90 * (1 - flatten) }
  var bound: Bool { chapter > 0 || fraction >= 0.95 }
  var irsActive: Bool { chapter > 1 || chapter == 1 && fraction >= 0.82 }
  var relay: Double { chapter > 2 ? 1 : chapter == 2 ? fraction : 0 }
  func signalProgress(_ index: Int) -> Double {
    min(1, max(0, index == 2 ? relay * 3.5 : chapter > index ? 1 : chapter == index ? fraction : 0))
  }
  func glucoseTravel(_ index: Int) -> Double { chapter == 4 ? Self.ease(fraction * 1.63 - Double(index) * 0.21) : 0 }
  private static func ease(_ value: Double) -> Double {
    let f = min(1, max(0, value))
    return f * f * (3 - 2 * f)
  }
}

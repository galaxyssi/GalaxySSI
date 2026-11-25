import Foundation

// Qualitative teaching values, not mmHg or patient measurements.
struct GalaxySSIHealthAtlasBeatPressure: Equatable {
  let atrium: Double
  let ventricle: Double
  let aorta: Double
  func interpolate(_ other: Self, time: Double) -> Self {
    .init(atrium: atrium + (other.atrium - atrium) * time,
      ventricle: ventricle + (other.ventricle - ventricle) * time,
      aorta: aorta + (other.aorta - aorta) * time)
  }
}

enum GalaxySSIHealthAtlasBeatPressureTrace {
  typealias Pressure = GalaxySSIHealthAtlasBeatPressure
  static let transitions: [Pressure] = [
    .init(atrium: 0.16, ventricle: 0.16, aorta: 0.75),
    .init(atrium: 0.17, ventricle: 0.10, aorta: 0.70),
    .init(atrium: 0.23, ventricle: 0.23, aorta: 0.66),
    .init(atrium: 0.16, ventricle: 0.65, aorta: 0.65),
    .init(atrium: 0.19, ventricle: 0.84, aorta: 0.84),
    .init(atrium: 0.16, ventricle: 0.16, aorta: 0.75)
  ]
  static let midpoints: [Pressure] = [
    .init(atrium: 0.18, ventricle: 0.10, aorta: 0.73),
    .init(atrium: 0.28, ventricle: 0.18, aorta: 0.68),
    .init(atrium: 0.19, ventricle: 0.40, aorta: 0.655),
    .init(atrium: 0.17, ventricle: 0.98, aorta: 0.94),
    .init(atrium: 0.18, ventricle: 0.36, aorta: 0.80)
  ]
  static func sample(_ stage: GalaxySSIHealthAtlasBeatStage, fraction: Double) -> Pressure {
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction), index = stage.rawValue
    return t <= 0.5 ? transitions[index].interpolate(midpoints[index], time: 2 * t) :
      midpoints[index].interpolate(transitions[index + 1], time: 2 * t - 1)
  }
}

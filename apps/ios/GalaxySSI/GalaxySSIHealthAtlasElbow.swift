import Foundation

/// Horizontal forearm at static equilibrium; no patient-specific geometry or strength estimate.
enum GalaxySSIHealthAtlasElbow {
  static let gravity = 9.8
  static let armMass = 2.5
  static let armCentreMetres = 0.16
  static let source = URL(string: "https://openstax.org/books/college-physics-2e/pages/9-6-forces-and-torques-in-muscles-and-joints")!
  struct Forces: Equatable, Sendable {
    let loadWeight: Double
    let armWeight: Double
    let muscle: Double
    let jointDown: Double
    let torque: Double
    let loadArmMetres: Double
    let muscleArmMetres: Double
  }
  static func forces(loadKg: Double, loadArmCm: Double, muscleArmMm: Double) -> Forces? {
    guard loadKg.isFinite, (0...10).contains(loadKg), loadArmCm.isFinite, (20...50).contains(loadArmCm),
      muscleArmMm.isFinite, (20...60).contains(muscleArmMm) else { return nil }
    let loadWeight = loadKg * gravity, armWeight = armMass * gravity
    let loadArm = loadArmCm / 100, muscleArm = muscleArmMm / 1000
    let torque = loadWeight * loadArm + armWeight * armCentreMetres
    let muscle = torque / muscleArm
    return Forces(loadWeight: loadWeight, armWeight: armWeight, muscle: muscle,
      jointDown: muscle - loadWeight - armWeight, torque: torque, loadArmMetres: loadArm, muscleArmMetres: muscleArm)
  }
}

import Foundation

enum GalaxySSIHealthAtlasAbsorptionMotion {
  typealias Track = GalaxySSIHealthAtlasSectionLesson.Route
  enum Cargo: Equatable { case solute, lipid, chylomicron }
  struct Transport { let path: Track; let cargo: Cargo }
  static func fraction(_ t: Double, index: Int, count: Int) -> Double {
    guard count > 0, index >= 0, index < count else { return 0 }
    let time = t.isFinite ? min(1, max(0, t)) : 0
    return (time + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1) * 0.86 + 0.04
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Track {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let outline = route(29, 294, [51,278,54,250,54,206], [54,162,52,123,65,93], [75,71,92,60,112,60],
    [139,60,158,79,169,107], [179,133,177,168,177,206], [177,253,182,282,198,294])
  static let bloodRoute = Transport(path: route(28, 149, [48,148,64,147,71,153], [77,159,72,179,74,196], [75,228,72,260,70,283]), cargo: .solute)
  static let lipidIntake = Transport(path: route(203, 182, [187,183,168,187]), cargo: .lipid)
  static let lymphRoute = Transport(path: route(164, 188, [150,192,128,196,126,214], [125,237,133,261,135,283]), cargo: .chylomicron)
  static let cellSolutes = Transport(path: route(254, 91, [264,127,250,174,257,211], [259,229,259,243]), cargo: .solute)
  static let cellLipids = Transport(path: route(307, 91, [302,124,308,148]), cargo: .lipid)
  static let cellExport = Transport(path: route(309, 164, [300,188,310,215,307,243]), cargo: .chylomicron)
  static let glucoseTrack = route(240, 89, [251,102,251,123], [251,260])
  static let sodiumTrack = route(271, 89, [261,102,261,123], [261,167,282,175], [307,187,307,212], [307,252])
}

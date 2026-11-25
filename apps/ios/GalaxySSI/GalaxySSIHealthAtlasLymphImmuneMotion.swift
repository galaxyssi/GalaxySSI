import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasLymphImmuneMotion {
  enum PumpStage: Equatable {
    case filling, holding, emptying
    var inletOpen: Bool { self == .filling }
    var outletOpen: Bool { self == .emptying }
    static func at(_ cycle: Double) -> Self {
      cycle < 0.41 ? .filling : cycle < 0.57 || cycle >= 0.97 ? .holding : .emptying
    }
    static func expansion(_ cycle: Double) -> Double {
      let value = cycle < 0.41 ? cycle / 0.41 : cycle < 0.57 ? 1 : cycle < 0.97 ? 1 - (cycle - 0.57) / 0.40 : 0
      return min(1, max(0, value))
    }
  }
  struct Clones { let centers: [CGPoint]; let diameter: Double }
  struct Section { let asset: String; let route: GalaxySSIHealthAtlasSectionLesson.Route }
  let lymph: Bool
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    lymph = courseID == "LYMPH_RETURN"
    self.chapter = min(4, max(0, chapter))
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  static func loop(_ value: Double) -> Double { value.isFinite ? value.truncatingRemainder(dividingBy: 1) : 0 }
  var pumpCycle: Double { Self.loop(fraction * 1.75) }
  var pumpStage: PumpStage { .at(pumpCycle) }
  var bulge: Double { 9 + 19 * PumpStage.expansion(pumpCycle) }
  var clones: Clones {
    let split = fraction < 0.47
    let phase = split ? fraction / 0.47 : (fraction - 0.47) / 0.53
    let shift = sin(phase * .pi / 2)
    let spreadX = split ? 31 * shift : 31 + 27 * shift
    let diameter = split ? 121 - 16 * shift : 105 - 20 * shift
    let centers = [180 - spreadX, 180 + spreadX].flatMap { x in
      split ? [CGPoint(x: x, y: 175)] : [-1.0, 1.0].map { CGPoint(x: x, y: 175 + $0 * 49 * shift) }
    }
    return Clones(centers: centers, diameter: diameter)
  }
  static func cellBounds(x: Double, y: Double, diameter: Double) -> CGRect? {
    guard x.isFinite, y.isFinite, diameter.isFinite, diameter > 0, abs(x) < 4096, abs(y) < 4096, diameter < 4096 else { return nil }
    let half = diameter / 2
    let l = Int(x - half), t = Int(y - half), r = Int(x + half), b = Int(y + half)
    return CGRect(x: Double(l), y: Double(t), width: Double(r - l), height: Double(b - t))
  }
  static let sections: [String: Section] = {
    guard let pack = try? GalaxySSIHealthAtlas.LymphPack.bundled.get() else { return [:] }
    var result: [String: Section] = [:]
    for id in ["lymph-nodes", "thoracic-duct"] {
      guard let plate = pack.plates.first(where: { $0.owner == id }), let tracks = pack.routes[id],
        tracks.count == 4, let first = tracks.first, tracks.allSatisfy(\.valid) else { continue }
      var endpoint = first.start, continuous = true
      for track in tracks {
        guard track.start == endpoint, let last = track.commands.last?.points.last else { continuous = false; break }
        endpoint = last
      }
      guard continuous else { continue }
      // Source tracks meet exactly; concatenation preserves total arc-length timing without artificial gaps.
      result[id] = Section(asset: plate.asset, route: .init(start: first.start, commands: tracks.flatMap(\.commands)))
    }
    return result
  }()
}

import Foundation

struct GalaxySSIHealthAtlasVisionMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  enum Stage: CaseIterable, Equatable {
    case entry, focus, capture, relay, output, dim, rod, mixed, bright, color
    static let pathway: [Self] = [.entry, .focus, .capture, .relay, .output]
    static let adaptation: [Self] = [.dim, .rod, .mixed, .bright, .color]
    func displayLight(_ fraction: Double) -> Double {
      switch self {
      case .dim: return 0.68 - 0.53 * fraction
      case .rod: return 0.15
      case .mixed: return 0.15 + 0.43 * fraction
      case .bright: return 0.58 + 0.36 * fraction
      case .color: return 0.94
      default: return 0
      }
    }
  }
  let adaptation: Bool
  let stage: Stage
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    adaptation = courseID == "LIGHT_ADAPTATION"
    let scenes = adaptation ? Stage.adaptation : Stage.pathway
    stage = scenes[min(scenes.count - 1, max(0, chapter))]
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  var light: Double { stage.displayLight(fraction) }
  var chroma: Double { min(1, max(0, (light - 0.24) / 0.54)) }
  var rodCount: Int {
    switch stage {
    case .rod: return 1 + Int(fraction * 4)
    case .dim: return 1 + Int(fraction * 2)
    case .mixed: return 3 - Int(fraction)
    default: return 0
    }
  }
  var coneCount: Int {
    switch stage {
    case .bright, .color: return 5
    case .dim: return 4 - Int(fraction * 3)
    case .mixed: return 1 + Int(fraction * 3)
    default: return 0
    }
  }
  var emphasis: Int { min(2, Int(fraction * 3)) }
  var opticsDrawn: Double { stage == .focus ? 1 : 0.43 + fraction * 0.37 }
  var incident: Double { min(1, max(0, (fraction - 0.10) / 0.38)) }
  var captureCount: Int { fraction < 0.46 ? 6 : 2 }
  static func blend(_ a: UInt32, _ b: UInt32, fraction: Double) -> UInt32 {
    let t = fraction.isFinite ? min(1, max(0, fraction)) : 0
    func channel(_ shift: UInt32) -> UInt32 {
      let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
      return UInt32(x + (y - x) * t)
    }
    return channel(16) << 16 | channel(8) << 8 | channel(0)
  }
  static func loop(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return value - value.rounded(.towardZero)
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let rays: [Route] = [-12.0, 0, 12].map { offset in
    route(20, 160 + offset * 1.8, [56,160 + offset * 1.55], [87,164 + offset * 0.55], [117,164 + offset * 0.42], [255,149])
  }
  static let lightInRetina = route(66, 108, [66,232])
  static let coneRelay = route(222, 211, [222,132], [212,114,222,93], [222,77], [269,64,313,75])
  static let nerve = route(48, 244, [93,244,121,217,153,231], [197,249,225,244,291,229])
}

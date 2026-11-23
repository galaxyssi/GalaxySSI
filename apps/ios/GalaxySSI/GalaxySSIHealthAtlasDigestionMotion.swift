import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasDigestionMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  enum Stage: CaseIterable, Equatable {
    case swallow, peristalsis, stomach, duodenum, villus, cecum, mix, water, propulsion, rectum
    static let meal: [Self] = [.swallow, .peristalsis, .stomach, .duodenum, .villus]
    static let colon: [Self] = [.cecum, .mix, .water, .propulsion, .rectum]
  }
  struct Particle { let point: CGPoint; let radius: Double }
  let isMeal: Bool
  let stage: Stage
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    isMeal = courseID == "DIGESTION"
    let scenes = isMeal ? Stage.meal : Stage.colon
    stage = scenes[min(scenes.count - 1, max(0, chapter))]
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  var rectalAdvance: Double { fraction < 0.58 ? 0.52 + 0.24 * fraction : 0.66 + 0.66 * (fraction - 0.58) }
  var stomachParticles: [Particle] {
    (0..<11).map { index in
      let angle = Double(index) * (2 * .pi / 11) + fraction * 10
      let band = Double(12 + (index % 4) * 6)
      let radius = (4.3 - 2 * fraction) + Double(index % 3) * 0.7
      return Particle(point: CGPoint(x: 232 + cos(angle) * band, y: 133 + sin(angle) * band * 1.15), radius: radius)
    }
  }
  var duodenalPositions: [Double] { (0..<6).map { Self.loop(fraction * 1.2 + Double($0) / 6) } }
  func flowPositions(count: Int, time: Double? = nil) -> [Double] {
    guard (1...16).contains(count) else { return [] }
    let t = time ?? fraction
    guard t.isFinite else { return [] }
    return (0..<count).map { Self.loop(t * 1.25 + Double($0) / Double(count)) }
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
  static let swallow = route(100, 144, [140,127,203,127,231,141], [256,149,271,165,278,180])
  static let downEsophagus = route(180, 48, [176,64,176,82], [169,106,174,129], [182,146,189,172,195,195], [199,225,199,233,228,244])
  static let stomachExit = route(223, 156, [169,196,110,180], [89,172,62,194])
  static let smallBowel = route(177, 65, [235,58,260,65], [294,78,293,115,272,153], [247,199,190,201], [135,194,110,211])
  static let bile = route(203, 73, [209,87,211,101], [214,121,239,129], [257,134])
  static let enzymes = route(121, 151, [168,151,185,148], [203,144,225,139], [257,134])
  static let waterSoluble = route(139, 81, [137,98,137,126,152,145], [159,155,157,176,152,193], [145,224,122,227,85,237])
  static let dietaryFat = route(191, 95, [189,132,174,141,173,161], [170,201,170,232,125,241], [113,241])
  static let colonEntry = route(44, 173, [58,171,67,178,82,185], [90,183,83,164])
  static let ascending = route(83, 164, [83,96])
  static let transverse = route(117, 57, [222,57])
  static let descending = route(270, 101, [274,153,261,178])
  static let colonFlow = route(83, 170, [83,95], [83,57,112,57], [233,57], [270,58,272,98], [269,164], [264,181,244,192], [228,207,203,206], [177,202,178,233])
  static let waterTrackA = route(84, 122, [119,118,134,107])
  static let waterTrackB = route(156, 58, [157,88,172,102])
  static let waterTrackC = route(271, 136, [239,139,223,148])
  static let waterTracks = [waterTrackA, waterTrackB, waterTrackC]
  static let rectal = route(125, 62, [155,99,177,88,196,120], [224,157,203,188], [204,209,201,235])
}

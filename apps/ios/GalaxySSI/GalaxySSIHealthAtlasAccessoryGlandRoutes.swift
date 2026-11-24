import SwiftUI

enum GalaxySSIHealthAtlasAccessoryGlandRoutes {
  static let vas = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 143, y: 23), commands: [
    .init(kind: .cubic, points: [.init(x: 139, y: 45), .init(x: 150, y: 61), .init(x: 150, y: 74)]),
    .init(kind: .cubic, points: [.init(x: 150, y: 84), .init(x: 150, y: 92), .init(x: 155, y: 97)]),
  ]))
  static let vesicle = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 127, y: 69), commands: [
    .init(kind: .cubic, points: [.init(x: 133, y: 70), .init(x: 132, y: 79), .init(x: 138, y: 86)]),
    .init(kind: .quad, points: [.init(x: 144, y: 93), .init(x: 155, y: 97)]),
  ]))
  static let ejaculatory = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 155, y: 97), commands: [
    .init(kind: .cubic, points: [.init(x: 163, y: 106), .init(x: 160, y: 124), .init(x: 175, y: 139)]),
  ]))
  static let prostateUpper = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 144, y: 130), commands: [
    .init(kind: .cubic, points: [.init(x: 152, y: 131), .init(x: 155, y: 148), .init(x: 175, y: 147)]),
  ]))
  static let prostateLower = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 146, y: 148), commands: [
    .init(kind: .cubic, points: [.init(x: 156, y: 147), .init(x: 165, y: 161), .init(x: 175, y: 158)]),
  ]))
  static let bulb = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 153, y: 183), commands: [
    .init(kind: .cubic, points: [.init(x: 159, y: 188), .init(x: 158, y: 199), .init(x: 163, y: 207)]),
    .init(kind: .cubic, points: [.init(x: 168, y: 215), .init(x: 170, y: 223), .init(x: 176, y: 229)]),
  ]))
  static let tracks = [vas, vesicle, ejaculatory, prostateUpper, prostateLower, bulb]
  static let colors: [UInt32] = [0x7B756D, 0x985944, 0x6B5683, 0x426E8B, 0x426E8B, 0x2A746D]
  static func active(_ index: Int, step: Int) -> Bool {
    switch step {
    case 1: return index == 1
    case 2: return index == 2
    case 3: return index == 3 || index == 4
    case 4: return index == 5
    default: return index != 0
    }
  }
  static func progress(_ fraction: Double, delay: Double = 0) -> Double {
    guard delay.isFinite, delay >= 0, delay < 0.84 else { return 0 }
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    let p = min(1, max(0, (t - 0.04 - delay) / (0.84 - delay)))
    return p * p * (3 - 2 * p)
  }
}

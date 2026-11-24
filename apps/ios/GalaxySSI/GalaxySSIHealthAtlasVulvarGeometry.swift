import SwiftUI

// Original Android #4385 contours; only trace emphasis changes over time.
enum GalaxySSIHealthAtlasVulvarGeometry {
  static let regionalOutline = Path { p in
    p.move(to: CGPoint(x: 180, y: 26))
    p.addCurve(to: CGPoint(x: 105, y: 76), control1: CGPoint(x: 145, y: 26), control2: CGPoint(x: 120, y: 45))
    p.addCurve(to: CGPoint(x: 105, y: 181), control1: CGPoint(x: 89, y: 108), control2: CGPoint(x: 91, y: 150))
    p.addCurve(to: CGPoint(x: 180, y: 252), control1: CGPoint(x: 121, y: 217), control2: CGPoint(x: 151, y: 246))
    p.addCurve(to: CGPoint(x: 255, y: 181), control1: CGPoint(x: 209, y: 246), control2: CGPoint(x: 239, y: 217))
    p.addCurve(to: CGPoint(x: 255, y: 76), control1: CGPoint(x: 269, y: 150), control2: CGPoint(x: 271, y: 108))
    p.addCurve(to: CGPoint(x: 180, y: 26), control1: CGPoint(x: 240, y: 45), control2: CGPoint(x: 215, y: 26))
  }
  static let regionOuter = Path { p in
    p.move(to: CGPoint(x: 165, y: 52))
    p.addCurve(to: CGPoint(x: 116, y: 113), control1: CGPoint(x: 142, y: 53), control2: CGPoint(x: 121, y: 78))
    p.addCurve(to: CGPoint(x: 166, y: 229), control1: CGPoint(x: 108, y: 153), control2: CGPoint(x: 128, y: 208))
  }
  static let regionInnerMargin = Path { p in
    p.move(to: CGPoint(x: 176, y: 73))
    p.addCurve(to: CGPoint(x: 162, y: 149), control1: CGPoint(x: 169, y: 99), control2: CGPoint(x: 162, y: 120))
    p.addCurve(to: CGPoint(x: 174, y: 211), control1: CGPoint(x: 162, y: 169), control2: CGPoint(x: 167, y: 190))
  }
  static let sectionSkin = Path { p in
    p.move(to: CGPoint(x: 27, y: 183))
    p.addCurve(to: CGPoint(x: 67, y: 121), control1: CGPoint(x: 53, y: 171), control2: CGPoint(x: 58, y: 154))
    p.addCurve(to: CGPoint(x: 113, y: 80), control1: CGPoint(x: 76, y: 89), control2: CGPoint(x: 92, y: 75))
    p.addCurve(to: CGPoint(x: 144, y: 144), control1: CGPoint(x: 135, y: 85), control2: CGPoint(x: 144, y: 114))
  }
  static let sectionFat = Path { p in
    p.move(to: CGPoint(x: 80, y: 126))
    p.addCurve(to: CGPoint(x: 110, y: 96), control1: CGPoint(x: 86, y: 104), control2: CGPoint(x: 96, y: 92))
    p.addCurve(to: CGPoint(x: 129, y: 145), control1: CGPoint(x: 124, y: 100), control2: CGPoint(x: 130, y: 121))
    p.addCurve(to: CGPoint(x: 158, y: 197), control1: CGPoint(x: 130, y: 163), control2: CGPoint(x: 142, y: 186))
  }
  static let innerLeft = Path { p in
    p.move(to: CGPoint(x: 174, y: 52))
    p.addCurve(to: CGPoint(x: 161, y: 83), control1: CGPoint(x: 172, y: 62), control2: CGPoint(x: 168, y: 72))
    p.addCurve(to: CGPoint(x: 149, y: 132), control1: CGPoint(x: 152, y: 98), control2: CGPoint(x: 145, y: 116))
    p.addCurve(to: CGPoint(x: 154, y: 173), control1: CGPoint(x: 153, y: 144), control2: CGPoint(x: 150, y: 161))
    p.addCurve(to: CGPoint(x: 174, y: 224), control1: CGPoint(x: 160, y: 190), control2: CGPoint(x: 163, y: 201))
  }
  static let innerRight = Path { p in
    p.move(to: CGPoint(x: 185, y: 57))
    p.addCurve(to: CGPoint(x: 200, y: 96), control1: CGPoint(x: 187, y: 70), control2: CGPoint(x: 192, y: 82))
    p.addCurve(to: CGPoint(x: 209, y: 132), control1: CGPoint(x: 207, y: 107), control2: CGPoint(x: 211, y: 119))
    p.addCurve(to: CGPoint(x: 207, y: 174), control1: CGPoint(x: 208, y: 144), control2: CGPoint(x: 213, y: 159))
    p.addCurve(to: CGPoint(x: 187, y: 226), control1: CGPoint(x: 201, y: 187), control2: CGPoint(x: 203, y: 201))
  }
  static let profileBase = Path { p in
    p.move(to: CGPoint(x: 0, y: 196))
    p.addCurve(to: CGPoint(x: 29, y: 148), control1: CGPoint(x: 11, y: 190), control2: CGPoint(x: 14, y: 152))
    p.addCurve(to: CGPoint(x: 74, y: 198), control1: CGPoint(x: 48, y: 143), control2: CGPoint(x: 47, y: 198))
    p.addCurve(to: CGPoint(x: 119, y: 148), control1: CGPoint(x: 101, y: 198), control2: CGPoint(x: 100, y: 143))
    p.addCurve(to: CGPoint(x: 148, y: 196), control1: CGPoint(x: 134, y: 152), control2: CGPoint(x: 137, y: 190))
    p.addLine(to: CGPoint(x: 148, y: 219))
    p.addQuadCurve(to: CGPoint(x: 0, y: 219), control: CGPoint(x: 74, y: 235))
    p.closeSubpath()
  }
  static let shortFold = Path { p in
    p.move(to: CGPoint(x: 37, y: 191))
    p.addCurve(to: CGPoint(x: 50, y: 157), control1: CGPoint(x: 40, y: 174), control2: CGPoint(x: 43, y: 158))
    p.addCurve(to: CGPoint(x: 70, y: 197), control1: CGPoint(x: 62, y: 155), control2: CGPoint(x: 53, y: 181))
    p.addQuadCurve(to: CGPoint(x: 37, y: 191), control: CGPoint(x: 53, y: 204))
    p.closeSubpath()
  }
  static let longFold = Path { p in
    p.move(to: CGPoint(x: 37, y: 191))
    p.addCurve(to: CGPoint(x: 43, y: 134), control1: CGPoint(x: 35, y: 174), control2: CGPoint(x: 36, y: 151))
    p.addCurve(to: CGPoint(x: 58, y: 149), control1: CGPoint(x: 52, y: 111), control2: CGPoint(x: 64, y: 121))
    p.addCurve(to: CGPoint(x: 70, y: 197), control1: CGPoint(x: 53, y: 175), control2: CGPoint(x: 60, y: 189))
    p.addQuadCurve(to: CGPoint(x: 37, y: 191), control: CGPoint(x: 53, y: 204))
    p.closeSubpath()
  }
  static let regionalOutlineTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 180, y: 26), commands: [
    .init(kind: .cubic, points: [.init(x: 145, y: 26), .init(x: 120, y: 45), .init(x: 105, y: 76)]),
    .init(kind: .cubic, points: [.init(x: 89, y: 108), .init(x: 91, y: 150), .init(x: 105, y: 181)]),
    .init(kind: .cubic, points: [.init(x: 121, y: 217), .init(x: 151, y: 246), .init(x: 180, y: 252)]),
    .init(kind: .cubic, points: [.init(x: 209, y: 246), .init(x: 239, y: 217), .init(x: 255, y: 181)]),
    .init(kind: .cubic, points: [.init(x: 269, y: 150), .init(x: 271, y: 108), .init(x: 255, y: 76)]),
    .init(kind: .cubic, points: [.init(x: 240, y: 45), .init(x: 215, y: 26), .init(x: 180, y: 26)]),
  ]))
  static let regionOuterTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 165, y: 52), commands: [
    .init(kind: .cubic, points: [.init(x: 142, y: 53), .init(x: 121, y: 78), .init(x: 116, y: 113)]),
    .init(kind: .cubic, points: [.init(x: 108, y: 153), .init(x: 128, y: 208), .init(x: 166, y: 229)]),
  ]))
  static let regionInnerMarginTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 176, y: 73), commands: [
    .init(kind: .cubic, points: [.init(x: 169, y: 99), .init(x: 162, y: 120), .init(x: 162, y: 149)]),
    .init(kind: .cubic, points: [.init(x: 162, y: 169), .init(x: 167, y: 190), .init(x: 174, y: 211)]),
  ]))
  static let sectionSkinTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 27, y: 183), commands: [
    .init(kind: .cubic, points: [.init(x: 53, y: 171), .init(x: 58, y: 154), .init(x: 67, y: 121)]),
    .init(kind: .cubic, points: [.init(x: 76, y: 89), .init(x: 92, y: 75), .init(x: 113, y: 80)]),
    .init(kind: .cubic, points: [.init(x: 135, y: 85), .init(x: 144, y: 114), .init(x: 144, y: 144)]),
  ]))
  static let sectionFatTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 80, y: 126), commands: [
    .init(kind: .cubic, points: [.init(x: 86, y: 104), .init(x: 96, y: 92), .init(x: 110, y: 96)]),
    .init(kind: .cubic, points: [.init(x: 124, y: 100), .init(x: 130, y: 121), .init(x: 129, y: 145)]),
    .init(kind: .cubic, points: [.init(x: 130, y: 163), .init(x: 142, y: 186), .init(x: 158, y: 197)]),
  ]))
  static let innerLeftTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 174, y: 52), commands: [
    .init(kind: .cubic, points: [.init(x: 172, y: 62), .init(x: 168, y: 72), .init(x: 161, y: 83)]),
    .init(kind: .cubic, points: [.init(x: 152, y: 98), .init(x: 145, y: 116), .init(x: 149, y: 132)]),
    .init(kind: .cubic, points: [.init(x: 153, y: 144), .init(x: 150, y: 161), .init(x: 154, y: 173)]),
    .init(kind: .cubic, points: [.init(x: 160, y: 190), .init(x: 163, y: 201), .init(x: 174, y: 224)]),
  ]))
  static let innerRightTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 185, y: 57), commands: [
    .init(kind: .cubic, points: [.init(x: 187, y: 70), .init(x: 192, y: 82), .init(x: 200, y: 96)]),
    .init(kind: .cubic, points: [.init(x: 207, y: 107), .init(x: 211, y: 119), .init(x: 209, y: 132)]),
    .init(kind: .cubic, points: [.init(x: 208, y: 144), .init(x: 213, y: 159), .init(x: 207, y: 174)]),
    .init(kind: .cubic, points: [.init(x: 201, y: 187), .init(x: 203, y: 201), .init(x: 187, y: 226)]),
  ]))
  static let shortFoldTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 37, y: 191), commands: [
    .init(kind: .cubic, points: [.init(x: 40, y: 174), .init(x: 43, y: 158), .init(x: 50, y: 157)]),
    .init(kind: .cubic, points: [.init(x: 62, y: 155), .init(x: 53, y: 181), .init(x: 70, y: 197)]),
    .init(kind: .quad, points: [.init(x: 53, y: 204), .init(x: 37, y: 191)]),
  ]))
  static let longFoldTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 37, y: 191), commands: [
    .init(kind: .cubic, points: [.init(x: 35, y: 174), .init(x: 36, y: 151), .init(x: 43, y: 134)]),
    .init(kind: .cubic, points: [.init(x: 52, y: 111), .init(x: 64, y: 121), .init(x: 58, y: 149)]),
    .init(kind: .cubic, points: [.init(x: 53, y: 175), .init(x: 60, y: 189), .init(x: 70, y: 197)]),
    .init(kind: .quad, points: [.init(x: 53, y: 204), .init(x: 37, y: 191)]),
  ]))
  static func reveal(_ fraction: Double, _ start: Double, _ end: Double) -> Double {
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    let p = min(1, max(0, (t - start) / (end - start)))
    return 0.10 + 0.90 * p * p * (3 - 2 * p)
  }
}

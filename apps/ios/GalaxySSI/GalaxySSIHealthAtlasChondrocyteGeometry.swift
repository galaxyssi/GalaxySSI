import SwiftUI

enum GalaxySSIHealthAtlasChondrocyteGeometry {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let tissueEdge: UInt32 = 0x6D9E92, rimEdge: UInt32 = 0x488779, cellEdge: UInt32 = 0x9A627F
  static let fibril: UInt32 = 0xA77784, collagen: UInt32 = 0x974E69, aggrecan: UInt32 = 0x976733, water: UInt32 = 0x397F9C, leader: UInt32 = 0x52656A
  static let patch = Path { p in
    p.move(to: CGPoint(x: 25, y: 105))
    p.addCurve(to: CGPoint(x: 167, y: 94), control1: CGPoint(x: 67, y: 84), control2: CGPoint(x: 116, y: 103))
    p.addCurve(to: CGPoint(x: 334, y: 103), control1: CGPoint(x: 216, y: 86), control2: CGPoint(x: 285, y: 88))
    p.addCurve(to: CGPoint(x: 336, y: 211), control1: CGPoint(x: 340, y: 136), control2: CGPoint(x: 328, y: 173))
    p.addQuadCurve(to: CGPoint(x: 333, y: 251), control: CGPoint(x: 339, y: 233))
    p.addCurve(to: CGPoint(x: 189, y: 259), control1: CGPoint(x: 294, y: 267), control2: CGPoint(x: 240, y: 252))
    p.addCurve(to: CGPoint(x: 26, y: 252), control1: CGPoint(x: 135, y: 266), control2: CGPoint(x: 68, y: 267))
    p.addCurve(to: CGPoint(x: 25, y: 105), control1: CGPoint(x: 17, y: 214), control2: CGPoint(x: 29, y: 159))
    p.closeSubpath()
  }
  static let reticulum = Path { p in
    p.move(to: CGPoint(x: 148, y: 181))
    p.addCurve(to: CGPoint(x: 175, y: 154), control1: CGPoint(x: 144, y: 163), control2: CGPoint(x: 154, y: 151))
    p.move(to: CGPoint(x: 150, y: 187))
    p.addCurve(to: CGPoint(x: 180, y: 192), control1: CGPoint(x: 154, y: 199), control2: CGPoint(x: 169, y: 202))
    p.move(to: CGPoint(x: 154, y: 192))
    p.addQuadCurve(to: CGPoint(x: 175, y: 193), control: CGPoint(x: 166, y: 200))
  }
  static let golgi = Path { p in
    for i in 0...2 {
      let x = 184 + 4.5 * Double(i)
      p.move(to: CGPoint(x: x, y: 169 + Double(i) * 2))
      p.addCurve(to: CGPoint(x: x - 1, y: 195 - Double(i) * 2), control1: CGPoint(x: x + 9, y: 176), control2: CGPoint(x: x + 9, y: 188))
    }
  }
  static func profile(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: x - rx, y: y - 0.06 * ry))
      p.addCurve(to: CGPoint(x: x + 0.08 * rx, y: y - ry), control1: CGPoint(x: x - rx, y: y - 0.66 * ry), control2: CGPoint(x: x - 0.48 * rx, y: y - ry))
      p.addCurve(to: CGPoint(x: x + rx, y: y - 0.03 * ry), control1: CGPoint(x: x + 0.67 * rx, y: y - ry), control2: CGPoint(x: x + rx, y: y - 0.61 * ry))
      p.addCurve(to: CGPoint(x: x - 0.12 * rx, y: y + ry), control1: CGPoint(x: x + rx, y: y + 0.61 * ry), control2: CGPoint(x: x + 0.47 * rx, y: y + ry))
      p.addCurve(to: CGPoint(x: x - rx, y: y - 0.06 * ry), control1: CGPoint(x: x - 0.71 * rx, y: y + ry), control2: CGPoint(x: x - rx, y: y + 0.52 * ry)); p.closeSubpath()
    }
  }
  struct Neighbor {
    let x: Double; let y: Double; let rim: Path; let cell: Path
    init(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
      self.x = x; self.y = y
      rim = GalaxySSIHealthAtlasChondrocyteGeometry.profile(x,y,rx,ry)
      cell = GalaxySSIHealthAtlasChondrocyteGeometry.profile(x,y,rx - 4,ry - 3)
    }
  }
  static func curve(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) -> Route {
    .init(start: .init(x: x0, y: y0), commands: [.init(kind: .cubic, points: [.init(x: x1, y: y1),.init(x: x2, y: y2),.init(x: x3, y: y3)])])
  }
  static func path(_ route: Route) -> Path { GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360) }
  static let territory = profile(175,177,70,60)
  static let rim = profile(173,177,50,46)
  static let lacuna = profile(173,176,41,37)
  static let cell = profile(172,176,36,32)
  static let neighbors = [
    Neighbor(51,117,18,11),
    Neighbor(311,125,17,13),
    Neighbor(295,241,19,12),
    Neighbor(53,235,19,13)
  ]
  static let fibrils = [
    curve(26,126,77,148,100,107,148,102),
    curve(55,97,82,107,99,132,126,123),
    curve(30,166,81,135,109,163,132,144),
    curve(26,186,63,169,99,180,122,158),
    curve(22,205,66,215,86,171,122,183),
    curve(44,248,94,240,81,215,127,209),
    curve(76,255,115,244,123,229,151,218),
    curve(103,261,132,249,147,258,168,232),
    curve(138,101,157,125,183,111,203,135),
    curve(201,101,219,121,234,125,253,128),
    curve(227,93,247,111,273,132,300,107),
    curve(216,150,250,127,273,154,331,142),
    curve(227,160,252,158,300,171,332,154),
    curve(228,188,269,177,294,203,333,179),
    curve(227,205,245,224,289,208,335,214),
    curve(211,221,242,222,255,254,279,254),
    curve(177,231,195,249,235,231,258,247),
    curve(176,259,199,250,217,263,244,254),
    curve(291,227,302,210,316,236,334,228)
  ]
  static let collagenRoutes = [
    curve(151,169,135,161,125,169,109,172),
    curve(150,187,135,192,126,201,107,213)
  ]
  static let collagenJoins = [
    curve(109,172,96,178,79,173,59,178),
    curve(107,213,89,222,100,239,78,237)
  ]
  static let carrier = curve(233,209,254,217,285,178,309,193)
  struct Deposit { let x: Double; let y: Double; let angle: Double; let route: Route }
  static let deposits: [Deposit] = [
    .init(x: 246, y: 208, angle: -19, route: curve(192,183,208,182,226,195,246,208)),
    .init(x: 269, y: 198, angle: -34, route: curve(194,181,219,174,245,185,269,198)),
    .init(x: 292, y: 190, angle: -5, route: curve(193,177,218,161,266,168,292,190))
  ]
  static let focusContours = [lacuna,rim,territory,path(fibrils[8])]
}

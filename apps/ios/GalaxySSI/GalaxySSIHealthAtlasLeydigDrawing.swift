import SwiftUI

enum GalaxySSIHealthAtlasLeydigGeometry {
  static let capillary = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 35, y: 251), commands: [
    .init(kind: .cubic, points: [.init(x: 91, y: 265), .init(x: 133, y: 248), .init(x: 168, y: 238)]),
    .init(kind: .cubic, points: [.init(x: 219, y: 223), .init(x: 244, y: 267), .init(x: 325, y: 251)])])
  static let lh = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 209, y: 238), commands: [
    .init(kind: .cubic, points: [.init(x: 205, y: 221), .init(x: 216, y: 186), .init(x: 201, y: 159)])])
  static let blood = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 193, y: 189), commands: [
    .init(kind: .cubic, points: [.init(x: 196, y: 211), .init(x: 172, y: 220), .init(x: 179, y: 236)]),
    .init(kind: .cubic, points: [.init(x: 225, y: 230), .init(x: 254, y: 266), .init(x: 317, y: 252)])])
  static let local = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 168, y: 172), commands: [
    .init(kind: .quad, points: [.init(x: 155, y: 180), .init(x: 132, y: 172)])])
  static let cell = Path { p in
    p.move(to: CGPoint(x: -13, y: -1))
    p.addCurve(to: CGPoint(x: 1, y: -12), control1: CGPoint(x: -13, y: -8), control2: CGPoint(x: -6, y: -13))
    p.addCurve(to: CGPoint(x: 13, y: 2), control1: CGPoint(x: 11, y: -13), control2: CGPoint(x: 15, y: -6))
    p.addCurve(to: CGPoint(x: -4, y: 11), control1: CGPoint(x: 12, y: 10), control2: CGPoint(x: 4, y: 14))
    p.addCurve(to: CGPoint(x: -13, y: -1), control1: CGPoint(x: -11, y: 10), control2: CGPoint(x: -14, y: 5)); p.closeSubpath()
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func leydigSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasLeydigGeometry
    rounded(19, 53, 341, 268, 12, 0xF9EDE4)
    leydigTubule(79, 151, 10, 1); leydigTubule(282, 150, -15, 0.96)
    line(98, 38, 90, 77, 0x527572, 1.1); line(263, 38, 266, 73, 0x527572, 1.1)
    label("leydig_endocrine_art_tubules", 180, 32, 206)
    let capillary = GalaxySSIHealthAtlasSectionLessonView.path(G.capillary, width: 360, height: 360)
    stroke(capillary, 0x924E60, 16); stroke(capillary, 0xEAB2B7, 12)
    for (x, y, rotation) in [(166.0, 144.0, -16.0), (190, 151, 12), (166, 173, 35), (191, 188, -19)] {
      var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(rotation))
      let cell = copy(local); cell.fill(G.cell, 0xEFB9A5); cell.stroke(G.cell, 0x864753, 1.4)
      cell.disc(0, 0, 4.1, 0x864753); cell.disc(6, -5, 1.7, Self.cream); cell.disc(-6, 4, 1.3, Self.cream)
    }
    label("leydig_endocrine_art_cells", 180, 112, 110); line(180, 118, 174, 130, 0x864753, 1.1)
    label("leydig_endocrine_art_capillary", 180, 283, 154); line(180, 270, 180, 245, 0x924E60, 1.1)
    let key: String
    switch step {
    case 0:
      let focus = sin(t * .pi)
      stroke(Path(roundedRect: CGRect(x: 146 - 3 * focus, y: 127, width: 69 + 6 * focus, height: 78), cornerRadius: 13), 0x864753, 1.2 + 1.2 * focus)
      key = "interstitium"
    case 1: leydigRoute(G.lh, t, input: true); key = "lh"
    case 2: leydigProduction(173, 141, t); leydigProduction(191, 186, (t + 0.33).truncatingRemainder(dividingBy: 1)); key = "testosterone"
    default: leydigRoute(G.blood, t, input: false); leydigRoute(G.local, t, input: false); key = "destinations"
    }
    rounded(32, 298, 328, 325, 7, 0xFBF8EE); label("leydig_endocrine_art_" + key, 180, 316, 280)
    label("gonadal_story_art_educational", 180, 345, 255)
  }
  private func leydigTubule(_ x: Double, _ y: Double, _ rotation: Double, _ scale: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(rotation)); local.scaleBy(x: scale, y: scale)
    let art = copy(local)
    art.oval(-55, -79, 55, 79, fill: 0xA9C5BD, border: 0x527572); art.oval(-50, -74, 50, 74, fill: 0xD2DFCE, border: 0x527572)
    art.oval(-29, -45, 29, 45, fill: 0xBCD4CA, border: 0x8CAD9F); art.oval(-19, -31, 19, 31, fill: 0xF2FAF5, border: 0x527572)
    for i in 0..<16 {
      let angle = Double(i) * .pi / 8, gx = 42 * cos(angle), gy = 59 * sin(angle)
      art.disc(gx, gy, 4.3, 0x6B8F85); art.disc(gx * 0.73, gy * 0.75, 2.8, 0x719B8F)
    }
  }
  private func leydigRoute(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ t: Double, input: Bool) {
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    if t > 0 { stroke(path.trimmedPath(from: 0, to: t), input ? 0x24577E : 0x8C510F, 1.3) }
    at(route, t) { x, y in
      if input {
        var diamond = Path(); diamond.move(to: CGPoint(x: x, y: y - 5)); diamond.addLine(to: CGPoint(x: x + 5, y: y))
        diamond.addLine(to: CGPoint(x: x, y: y + 5)); diamond.addLine(to: CGPoint(x: x - 5, y: y)); diamond.closeSubpath()
        fill(diamond, 0x24577E); stroke(diamond, Self.cream, 1.1)
      } else { disc(x, y, 4.5, Self.cream, border: 0x8C510F) }
    }
  }
  private func leydigProduction(_ x: Double, _ y: Double, _ t: Double) {
    var local = context; local.opacity = Double(Int(205 * (1 - t))) / 255
    let r = 12 + 10 * t
    copy(local).stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), 0x8C510F, 1.6)
    disc(x + 10 + 8 * t, y - 7 - 9 * t, 3 + t, Self.cream, border: 0x8C510F)
  }
}

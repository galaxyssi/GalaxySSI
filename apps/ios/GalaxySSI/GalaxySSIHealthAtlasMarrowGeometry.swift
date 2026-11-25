import SwiftUI

enum GalaxySSIHealthAtlasMarrowGeometry {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let wall: UInt32 = 0xAD6973, vesselNucleus: UInt32 = 0x9E637B, boneEdge: UInt32 = 0xAE8468
  static let leader: UInt32 = 0x746477, red: UInt32 = 0xA95060, stem: UInt32 = 0x775583
  static let field = Path(CGRect(x: 22, y: 74, width: 316, height: 210))
  static let trabecula = Path { p in
    p.move(to: CGPoint(x: 18, y: 70))
    p.addLine(to: CGPoint(x: 160, y: 70))
    p.addCurve(to: CGPoint(x: 118, y: 89), control1: CGPoint(x: 146, y: 85), control2: CGPoint(x: 134, y: 87))
    p.addCurve(to: CGPoint(x: 76, y: 124), control1: CGPoint(x: 94, y: 91), control2: CGPoint(x: 94, y: 116))
    p.addCurve(to: CGPoint(x: 42, y: 153), control1: CGPoint(x: 56, y: 132), control2: CGPoint(x: 46, y: 122))
    p.addQuadCurve(to: CGPoint(x: 18, y: 180), control: CGPoint(x: 39, y: 170))
    p.closeSubpath()
    p.move(to: CGPoint(x: 287, y: 70))
    p.addLine(to: CGPoint(x: 342, y: 70))
    p.addLine(to: CGPoint(x: 342, y: 157))
    p.addQuadCurve(to: CGPoint(x: 320, y: 132), control: CGPoint(x: 325, y: 152))
    p.addCurve(to: CGPoint(x: 287, y: 70), control1: CGPoint(x: 316, y: 111), control2: CGPoint(x: 292, y: 107))
    p.closeSubpath()
  }
  static let stroma = Path { p in
    p.move(to: CGPoint(x: 72, y: 171))
    p.addCurve(to: CGPoint(x: 115, y: 145), control1: CGPoint(x: 88, y: 161), control2: CGPoint(x: 96, y: 148))
    p.addQuadCurve(to: CGPoint(x: 146, y: 131), control: CGPoint(x: 130, y: 143))
    p.addQuadCurve(to: CGPoint(x: 124, y: 151), control: CGPoint(x: 139, y: 143))
    p.addQuadCurve(to: CGPoint(x: 140, y: 173), control: CGPoint(x: 120, y: 156))
    p.addQuadCurve(to: CGPoint(x: 115, y: 159), control: CGPoint(x: 125, y: 168))
    p.addCurve(to: CGPoint(x: 72, y: 171), control1: CGPoint(x: 99, y: 159), control2: CGPoint(x: 88, y: 169))
    p.closeSubpath()
  }
  static let megakaryocyteNucleus = Path { p in
    p.move(to: CGPoint(x: -16, y: -3))
    p.addCurve(to: CGPoint(x: -1, y: -15), control1: CGPoint(x: -24, y: -18), control2: CGPoint(x: -6, y: -23))
    p.addCurve(to: CGPoint(x: 14, y: -3), control1: CGPoint(x: 9, y: -28), control2: CGPoint(x: 22, y: -11))
    p.addCurve(to: CGPoint(x: 4, y: 14), control1: CGPoint(x: 29, y: 7), control2: CGPoint(x: 11, y: 22))
    p.addCurve(to: CGPoint(x: -16, y: -3), control1: CGPoint(x: -7, y: 26), control2: CGPoint(x: -26, y: 13))
    p.closeSubpath()
  }
  static let lumen = Path { p in
    for (index, point) in GalaxySSIHealthAtlasMarrowMotion.lumenPoints.enumerated() {
      if index == 0 { p.move(to: CGPoint(x: point.x, y: point.y)) } else { p.addLine(to: CGPoint(x: point.x, y: point.y)) }
    }
    p.closeSubpath()
  }
  static let erythroidRoute = Route(start: .init(x: 105, y: 181), commands: [
    .init(kind: .cubic, points: [.init(x: 110, y: 174),.init(x: 164, y: 115),.init(x: 226, y: 106)])
  ])
  static let megakaryocyteRoute = Route(start: .init(x: 105, y: 181), commands: [
    .init(kind: .cubic, points: [.init(x: 110, y: 190),.init(x: 164, y: 234),.init(x: 225, y: 245)])
  ])
  static let marrowCells: [Point] = [
    .init(x: 86, y: 105),
    .init(x: 142, y: 99),
    .init(x: 165, y: 84),
    .init(x: 201, y: 105),
    .init(x: 235, y: 97),
    .init(x: 272, y: 96),
    .init(x: 291, y: 115),
    .init(x: 51, y: 141),
    .init(x: 73, y: 140),
    .init(x: 150, y: 112),
    .init(x: 226, y: 130),
    .init(x: 250, y: 116),
    .init(x: 278, y: 141),
    .init(x: 310, y: 148),
    .init(x: 39, y: 187),
    .init(x: 62, y: 196),
    .init(x: 87, y: 182),
    .init(x: 107, y: 197),
    .init(x: 226, y: 176),
    .init(x: 252, y: 154),
    .init(x: 279, y: 177),
    .init(x: 309, y: 184),
    .init(x: 328, y: 174),
    .init(x: 297, y: 203),
    .init(x: 78, y: 279),
    .init(x: 126, y: 280),
    .init(x: 267, y: 268),
    .init(x: 304, y: 279)
  ]
  static func renewal(_ frame: GalaxySSIHealthAtlasMarrowMotion.Renewal) -> Path {
    let x = 108.0, radius = frame.radius, right = frame.right, mid = frame.mid, neck = frame.neck, bend = frame.bend, arc = frame.arc
    return Path { p in
      p.move(to: CGPoint(x: x, y: -radius))
      p.addCurve(to: CGPoint(x: mid, y: -neck), control1: CGPoint(x: x + bend, y: -radius), control2: CGPoint(x: mid - bend, y: -neck))
      p.addCurve(to: CGPoint(x: right, y: -radius), control1: CGPoint(x: mid + bend, y: -neck), control2: CGPoint(x: right - bend, y: -radius))
      p.addCurve(to: CGPoint(x: right + radius, y: 0), control1: CGPoint(x: right + arc, y: -radius), control2: CGPoint(x: right + radius, y: -arc))
      p.addCurve(to: CGPoint(x: right, y: radius), control1: CGPoint(x: right + radius, y: arc), control2: CGPoint(x: right + arc, y: radius))
      p.addCurve(to: CGPoint(x: mid, y: neck), control1: CGPoint(x: right - bend, y: radius), control2: CGPoint(x: mid + bend, y: neck))
      p.addCurve(to: CGPoint(x: x, y: radius), control1: CGPoint(x: mid - bend, y: neck), control2: CGPoint(x: x + bend, y: radius))
      p.addCurve(to: CGPoint(x: x - radius, y: 0), control1: CGPoint(x: x - arc, y: radius), control2: CGPoint(x: x - radius, y: arc))
      p.addCurve(to: CGPoint(x: x, y: -radius), control1: CGPoint(x: x - radius, y: -arc), control2: CGPoint(x: x - arc, y: -radius)); p.closeSubpath()
    }
  }
}

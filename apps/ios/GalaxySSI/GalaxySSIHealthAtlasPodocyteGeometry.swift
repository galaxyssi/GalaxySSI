import SwiftUI

enum GalaxySSIHealthAtlasPodocyteGeometry {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  private typealias Motion = GalaxySSIHealthAtlasPodocyteMotion
  static let leader: UInt32 = 0x52666B, vessel: UInt32 = 0x9D5863, endo: UInt32 = 0xA26169, matrix: UInt32 = 0x8A7051
  static let footInk: UInt32 = 0x705580, neighbor: UInt32 = 0x537A73, slit: UInt32 = 0x514F64, water: UInt32 = 0x30759D, solute: UInt32 = 0x327C6A, protein: UInt32 = 0x886521
  static let capsule = Path { p in
    p.move(to: CGPoint(x: 104, y: 83))
    p.addCurve(to: CGPoint(x: 32, y: 60), control1: CGPoint(x: 78, y: 107), control2: CGPoint(x: 35, y: 92))
    p.addCurve(to: CGPoint(x: 78, y: 20), control1: CGPoint(x: 28, y: 35), control2: CGPoint(x: 50, y: 18))
    p.addCurve(to: CGPoint(x: 118, y: 64), control1: CGPoint(x: 106, y: 20), control2: CGPoint(x: 123, y: 42))
    p.addQuadCurve(to: CGPoint(x: 128, y: 81), control: CGPoint(x: 116, y: 72))
    p.addLine(to: CGPoint(x: 121, y: 90))
    p.addQuadCurve(to: CGPoint(x: 104, y: 83), control: CGPoint(x: 109, y: 81))
    p.closeSubpath()
  }
  static let tuft = Path { p in
    p.move(to: CGPoint(x: 20, y: 40))
    p.addCurve(to: CGPoint(x: 54, y: 34), control1: CGPoint(x: 44, y: 44), control2: CGPoint(x: 47, y: 46))
    p.addCurve(to: CGPoint(x: 79, y: 40), control1: CGPoint(x: 62, y: 21), control2: CGPoint(x: 84, y: 27))
    p.addCurve(to: CGPoint(x: 58, y: 61), control1: CGPoint(x: 75, y: 50), control2: CGPoint(x: 55, y: 48))
    p.addCurve(to: CGPoint(x: 80, y: 57), control1: CGPoint(x: 60, y: 70), control2: CGPoint(x: 71, y: 67))
    p.addCurve(to: CGPoint(x: 108, y: 55), control1: CGPoint(x: 91, y: 43), control2: CGPoint(x: 103, y: 44))
    p.addCurve(to: CGPoint(x: 74, y: 79), control1: CGPoint(x: 114, y: 73), control2: CGPoint(x: 89, y: 82))
    p.addCurve(to: CGPoint(x: 45, y: 73), control1: CGPoint(x: 56, y: 77), control2: CGPoint(x: 56, y: 88))
    p.addQuadCurve(to: CGPoint(x: 20, y: 61), control: CGPoint(x: 42, y: 64))
  }
  static let tuftBranch = Path { p in
    p.move(to: CGPoint(x: 56, y: 36))
    p.addCurve(to: CGPoint(x: 58, y: 80), control1: CGPoint(x: 49, y: 55), control2: CGPoint(x: 45, y: 66))
    p.move(to: CGPoint(x: 76, y: 45))
    p.addCurve(to: CGPoint(x: 108, y: 55), control1: CGPoint(x: 98, y: 28), control2: CGPoint(x: 109, y: 41))
    p.move(to: CGPoint(x: 70, y: 66))
    p.addCurve(to: CGPoint(x: 103, y: 61), control1: CGPoint(x: 82, y: 69), control2: CGPoint(x: 92, y: 56))
  }
  static let foot = Path { p in
    p.move(to: CGPoint(x: -10, y: 0))
    p.addLine(to: CGPoint(x: 10, y: 0))
    p.addCurve(to: CGPoint(x: 5, y: 10), control1: CGPoint(x: 10, y: 5), control2: CGPoint(x: 7, y: 7))
    p.addQuadCurve(to: CGPoint(x: 4, y: 18), control: CGPoint(x: 3, y: 14))
    p.addQuadCurve(to: CGPoint(x: -5, y: 17), control: CGPoint(x: -1, y: 21))
    p.addCurve(to: CGPoint(x: -10, y: 0), control1: CGPoint(x: -4, y: 11), control2: CGPoint(x: -10, y: 8))
    p.closeSubpath()
  }
  static let tuftFlow = Route(start: .init(x: 20, y: 40), commands: [
    .init(kind: .cubic, points: [.init(x: 44, y: 44), .init(x: 47, y: 46), .init(x: 54, y: 34)]),
    .init(kind: .cubic, points: [.init(x: 62, y: 21), .init(x: 84, y: 27), .init(x: 79, y: 40)]),
    .init(kind: .cubic, points: [.init(x: 75, y: 50), .init(x: 55, y: 48), .init(x: 58, y: 61)]),
    .init(kind: .cubic, points: [.init(x: 60, y: 70), .init(x: 71, y: 67), .init(x: 80, y: 57)]),
    .init(kind: .cubic, points: [.init(x: 91, y: 43), .init(x: 103, y: 44), .init(x: 108, y: 55)]),
    .init(kind: .cubic, points: [.init(x: 114, y: 73), .init(x: 89, y: 82), .init(x: 74, y: 79)]),
    .init(kind: .cubic, points: [.init(x: 56, y: 77), .init(x: 56, y: 88), .init(x: 45, y: 73)]),
    .init(kind: .quad, points: [.init(x: 42, y: 64), .init(x: 20, y: 61)]),
  ])
  static func polygon(_ points: [GalaxySSIHealthAtlasSectionLesson.Point]) -> Path {
    var p = Path()
    for (i, point) in points.enumerated() {
      if i == 0 { p.move(to: CGPoint(x: point.x, y: point.y)) } else { p.addLine(to: CGPoint(x: point.x, y: point.y)) }
    }
    p.closeSubpath(); return p
  }
  static let blood = polygon(Motion.strip(top: { _ in 111 },bottom: Motion.wallY))
  static let filtrateSpace = polygon(Motion.strip(top: { Motion.wallY($0) + Motion.matrixDepth },bottom: { _ in 302 }))
  static let basement = polygon(Motion.strip(top: Motion.wallY,bottom: { Motion.wallY($0) + Motion.matrixDepth }))
  static let endothelium = Motion.endothelialSegments.map { polygon(Motion.strip(top: Motion.endoY,bottom: Motion.wallY,left: $0.left,right: $0.right)) }
  static let podocyte = Path { p in
    p.move(to: CGPoint(x: 67, y: Motion.footY(67) + 13))
    p.addCurve(to: CGPoint(x: 111, y: 230), control1: CGPoint(x: 72, y: 217), control2: CGPoint(x: 91, y: 213))
    p.addCurve(to: CGPoint(x: 119, y: Motion.footY(120) + 13), control1: CGPoint(x: 117, y: 229), control2: CGPoint(x: 119, y: 214))
    p.addLine(to: CGPoint(x: 124, y: Motion.footY(120) + 13))
    p.addCurve(to: CGPoint(x: 134, y: 228), control1: CGPoint(x: 124, y: 216), control2: CGPoint(x: 128, y: 225))
    p.addCurve(to: CGPoint(x: 174, y: Motion.footY(174) + 13), control1: CGPoint(x: 153, y: 229), control2: CGPoint(x: 164, y: 214))
    p.addLine(to: CGPoint(x: 178, y: Motion.footY(174) + 15))
    p.addCurve(to: CGPoint(x: 155, y: 238), control1: CGPoint(x: 176, y: 222), control2: CGPoint(x: 161, y: 229))
    p.addCurve(to: CGPoint(x: 101, y: 244), control1: CGPoint(x: 153, y: 259), control2: CGPoint(x: 109, y: 266))
    p.addCurve(to: CGPoint(x: 63, y: Motion.footY(67) + 14), control1: CGPoint(x: 91, y: 228), control2: CGPoint(x: 70, y: 230)); p.closeSubpath()
  }
  static func filtrationRoute(pore: Double, slit: Double, exit: Double) -> Route {
    .init(start: .init(x: pore, y: Motion.wallY(pore) - 29), commands: [
      .init(kind: .line, points: [.init(x: pore, y: Motion.wallY(pore) - 1)]),
      .init(kind: .quad, points: [.init(x: pore, y: Motion.wallY(pore) + 5),.init(x: slit, y: Motion.footY(slit) - 1)]),
      .init(kind: .line, points: [.init(x: slit, y: Motion.footY(slit) + 9)]),
      .init(kind: .cubic, points: [.init(x: slit, y: Motion.footY(slit) + 27),.init(x: exit, y: 261),.init(x: exit, y: 293)])
    ])
  }
  static let leftFlow = filtrationRoute(pore: Motion.fenestrae[0],slit: Motion.slits[0],exit: 33)
  static let rightFlow = filtrationRoute(pore: Motion.fenestrae[7],slit: Motion.slits[6],exit: 234)
}

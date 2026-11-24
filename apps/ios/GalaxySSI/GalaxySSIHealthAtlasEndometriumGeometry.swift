import SwiftUI

enum GalaxySSIHealthAtlasEndometriumGeometry {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  private typealias Motion = GalaxySSIHealthAtlasEndometriumMotion
  static let lining: UInt32 = 0x96576D, leader: UInt32 = 0x50686E, cavity: UInt32 = 0xE1EEEA
  static let uterus = Path { p in
    p.move(to: CGPoint(x: 133, y: 38))
    p.addCurve(to: CGPoint(x: 180, y: 27), control1: CGPoint(x: 146, y: 39), control2: CGPoint(x: 148, y: 27))
    p.addCurve(to: CGPoint(x: 227, y: 38), control1: CGPoint(x: 212, y: 27), control2: CGPoint(x: 214, y: 39))
    p.addLine(to: CGPoint(x: 224, y: 45))
    p.addCurve(to: CGPoint(x: 199, y: 77), control1: CGPoint(x: 209, y: 43), control2: CGPoint(x: 212, y: 62))
    p.addCurve(to: CGPoint(x: 187, y: 96), control1: CGPoint(x: 193, y: 84), control2: CGPoint(x: 187, y: 86))
    p.addQuadCurve(to: CGPoint(x: 173, y: 96), control: CGPoint(x: 180, y: 99))
    p.addCurve(to: CGPoint(x: 161, y: 77), control1: CGPoint(x: 173, y: 86), control2: CGPoint(x: 167, y: 84))
    p.addCurve(to: CGPoint(x: 136, y: 45), control1: CGPoint(x: 148, y: 62), control2: CGPoint(x: 151, y: 43))
    p.closeSubpath()
  }
  static let uterineCavity = Path { p in
    p.move(to: CGPoint(x: 144, y: 41))
    p.addQuadCurve(to: CGPoint(x: 216, y: 41), control: CGPoint(x: 180, y: 49))
    p.addCurve(to: CGPoint(x: 181, y: 89), control1: CGPoint(x: 199, y: 51), control2: CGPoint(x: 189, y: 67))
    p.addLine(to: CGPoint(x: 179, y: 89))
    p.addCurve(to: CGPoint(x: 144, y: 41), control1: CGPoint(x: 171, y: 67), control2: CGPoint(x: 161, y: 51))
    p.closeSubpath()
  }
  static let sectionGuide = Route(start: .init(x: 199, y: 54), commands: [
    .init(kind: .line, points: [.init(x: 222, y: 70)]),.init(kind: .line, points: [.init(x: 243, y: 117)])
  ])
  static let guidePath = GalaxySSIHealthAtlasSectionLessonView.path(sectionGuide,width: 360,height: 360)
  static let field = Path(roundedRect: CGRect(x: 106, y: 117, width: 148, height: 208), cornerRadius: 6)
  struct Section { let profile: Path; let tissue: Path }
  static func section(_ frame: GalaxySSIHealthAtlasEndometriumMotion.Frame) -> Section {
    var profile = Path()
    profile.move(to: CGPoint(x: Motion.left, y: Motion.surface(Motion.left,top: frame.top,erosion: frame.erosion)))
    for i in 1...40 {
      let x = Motion.left + (Motion.right - Motion.left) * Double(i) / 40
      profile.addLine(to: CGPoint(x: x, y: Motion.surface(x,top: frame.top,erosion: frame.erosion)))
    }
    var tissue = profile; tissue.addLine(to: CGPoint(x: Motion.right, y: Motion.muscle)); tissue.addLine(to: CGPoint(x: Motion.left, y: Motion.muscle)); tissue.closeSubpath()
    return .init(profile: profile,tissue: tissue)
  }
  static func channel(x: Double, top: Double, bend: Double, index: Int) -> Route {
    let depth = Motion.basal - top, sway = (index == 1 ? -1.0 : 1.0) * (2 + 10 * bend)
    var commands: [GalaxySSIHealthAtlasSectionLesson.Command] = []
    if depth > 0 {
      commands.append(.init(kind: .cubic, points: [.init(x: x, y: top + depth * 0.14),.init(x: x + 1.45 * sway, y: top + depth * 0.16),.init(x: x + sway, y: top + depth * 0.32)]))
      commands.append(.init(kind: .cubic, points: [.init(x: x + 0.55 * sway, y: top + depth * 0.52),.init(x: x - 1.7 * sway, y: top + depth * 0.47),.init(x: x - sway, y: top + depth * 0.69)]))
      commands.append(.init(kind: .cubic, points: [.init(x: x - 0.65 * sway, y: top + depth * 0.84),.init(x: x + 7 * bend, y: top + depth * 0.93),.init(x: x, y: Motion.basal)]))
    }
    commands.append(.init(kind: .cubic, points: [.init(x: x - 4, y: Motion.basal + 13),.init(x: x + 8, y: Motion.basal + 22),.init(x: x + 2, y: Motion.basal + 28)]))
    return .init(start: .init(x: x, y: top - 4),commands: commands)
  }
}

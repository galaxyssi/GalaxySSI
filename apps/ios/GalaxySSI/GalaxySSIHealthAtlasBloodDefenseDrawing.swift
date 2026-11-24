import SwiftUI

struct GalaxySSIHealthAtlasBloodDefenseDrawing {
  let lesson: GalaxySSIHealthAtlasBloodDefense
  private static let vessel = color(0x6A869E), teal = color(0x347D6E), gold = color(0xAF7136), mauve = color(0x925571)
  private typealias Frame = GalaxySSIHealthAtlasBloodDefense.Frame
  func drawScene(in drawing: GraphicsContext, frame: GalaxySSIHealthAtlasBloodDefense.Frame) {
    switch lesson {
    case .tCell, .bCell: adaptive(in: drawing, frame: frame)
    case .naturalKiller: naturalKiller(in: drawing, frame: frame)
    case .megakaryocyte: megakaryocyte(in: drawing, frame: frame)
    case .platelet: platelet(in: drawing, frame: frame)
    }
  }
  private func portrait(in context: GraphicsContext, asset: String, x: Double, y: Double, size: Double) {
    GalaxySSIHealthAtlasCellScene.portrait(in: context, asset: asset, x: x, y: y, size: size)
  }
  private func primary(in context: GraphicsContext, frame: Frame) {
    let p = frame.primary
    portrait(in: context, asset: lesson.asset, x: p.x, y: p.y, size: p.size)
  }
  private func adaptive(in context: GraphicsContext, frame: Frame) {
    let t = frame.ease, bCell = lesson == .bCell
    primary(in: context, frame: frame)
    switch frame.stage {
    case 0:
      if !bCell, let asset = lesson.relatedAsset {
        portrait(in: context, asset: asset, x: 254 - 29 * t, y: 102, size: 172)
      }
      context.fill(circle(bCell ? 224 - t * 73 : 182 - t * 19, 105, 5), with: .color(Self.gold))
    case 1:
      if let asset = bCell ? "HealthAtlasImmuneTCell" : lesson.relatedAsset {
        portrait(in: context, asset: asset, x: 232, y: 103, size: 167)
      }
      for bounds in [CGRect(x: 154 + 9 * t, y: 75, width: 39, height: 55), CGRect(x: 162 + 9 * t, y: 65, width: 40, height: 75)] {
        arc(in: context, bounds: bounds, start: -56, end: 56, color: Self.teal, width: 2.7)
      }
    case 2:
      for p in frame.clones { portrait(in: context, asset: lesson.asset, x: p.x, y: p.y, size: p.size) }
    default:
      if bCell, let asset = lesson.relatedAsset {
        portrait(in: context, asset: asset, x: 259, y: 55, size: 113)
        portrait(in: context, asset: lesson.asset, x: 259, y: 147, size: 106)
      } else {
        ring(in: context, 259, 55, 21, Self.teal); ring(in: context, 259, 147, 21, Self.mauve)
        line(in: context, 249, 55, 269, 55, Self.teal, 3)
        line(in: context, 259, 45, 259, 65, Self.teal, 3)
        line(in: context, 251, 147, 267, 147, Self.mauve, 3)
      }
      line(in: context, 137, 102, 175, 102, Self.teal, 2.7)
      line(in: context, 175, 102, 190 + 29 * t, 102 - 34 * t, Self.teal, 2.7)
      line(in: context, 175, 102, 190 + 29 * t, 102 + 34 * t, Self.teal, 2.7)
    }
  }
  private func naturalKiller(in context: GraphicsContext, frame: Frame) {
    let t = frame.ease
    primary(in: context, frame: frame)
    context.fill(circle(248, 103, frame.targetRadius), with: .color(Self.color(frame.stage == 3 ? 0xD0B8BD : 0xE2C7BD)))
    ring(in: context, 248, 103, frame.targetRadius, Self.mauve)
    switch frame.stage {
    case 0: ring(in: context, 183 + 13 * t, 104, 7, Self.gold)
    case 1: ring(in: context, 197, 103, 9 + 7 * t, Self.gold)
    case 2:
      for index in -2...2 {
        context.fill(circle(167 + 58 * t, 104 + Double(index) * (4 + t * 5), 3.5), with: .color(Self.mauve))
      }
    default:
      for index in -1...1 {
        let i = Double(index)
        context.fill(circle(248 + i * (8 + t * 11), 103 + i * 7, 4 - 2 * t), with: .color(Self.mauve))
      }
    }
  }
  private func megakaryocyte(in context: GraphicsContext, frame: Frame) {
    context.fill(rounded(252, 19, 77, 162, 19), with: .color(Self.color(0x6A9CBA).opacity(52.0 / 255)))
    line(in: context, 327, 27, 327, 174, Self.vessel, 3.4)
    line(in: context, 252, 27, 252, 73, Self.vessel, 3.4)
    line(in: context, 252, 128, 252, 174, Self.vessel, 3.4)
    primary(in: context, frame: frame)
    if frame.stage == 2 { ring(in: context, 216 + frame.ease * 25, 105, 12, Self.teal) }
    if let asset = lesson.relatedAsset {
      for p in frame.releasedPlatelets { portrait(in: context, asset: asset, x: p.x, y: p.y, size: p.size) }
    }
  }
  private func platelet(in context: GraphicsContext, frame: Frame) {
    let t = frame.ease
    context.fill(rounded(26, 139, 111, 27, 12), with: .color(Self.color(0xECD1CE)))
    context.fill(rounded(225, 139, 109, 27, 12), with: .color(Self.color(0xECD1CE)))
    context.fill(rounded(128, 148, 106, 20, 7), with: .color(Self.color(0xD8ADB3)))
    line(in: context, 35, 139, 137, 139, Self.mauve, 3.4)
    line(in: context, 225, 139, 325, 139, Self.mauve, 3.4)
    if frame.stage == 0 { primary(in: context, frame: frame); return }
    activePlatelet(in: context, x: 181, y: 135, radius: 15 + 3 * t)
    for p in frame.plateletNeighbors { activePlatelet(in: context, x: p.x, y: p.y, radius: 13) }
    if frame.stage == 3 {
      for index in -1...1 {
        let i = Double(index)
        line(in: context, 139, 123 + i * 9, 195 + 30 * t, 142 - i * 11, Self.vessel, 2.6)
      }
    }
  }
  private func activePlatelet(in context: GraphicsContext, x: Double, y: Double, radius: Double) {
    for point in 0...5 {
      let angle = Double(point * 2 + 1) * .pi / 6
      let extent = radius * (point.isMultiple(of: 2) ? 1.1 : 0.94)
      line(in: context, x, y, x + extent * cos(angle), y + extent * sin(angle), Self.color(0xB37B9E), 3.8)
    }
    portrait(in: context, asset: lesson.asset, x: x, y: y, size: radius * 3.75)
  }
  private func ring(in context: GraphicsContext, _ x: Double, _ y: Double, _ radius: Double, _ color: Color) {
    context.stroke(circle(x, y, radius), with: .color(color), lineWidth: 2.7)
  }
  private func line(in context: GraphicsContext, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: Color, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func arc(in context: GraphicsContext, bounds: CGRect, start: Double, end: Double, color: Color, width: Double) {
    var path = Path(); path.addArc(center: .zero, radius: 1, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
    let transform = CGAffineTransform(a: bounds.width / 2, b: 0, c: 0, d: bounds.height / 2, tx: bounds.midX, ty: bounds.midY)
    context.stroke(path.applying(transform), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func circle(_ x: Double, _ y: Double, _ radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
  }
  private func rounded(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
  }
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}

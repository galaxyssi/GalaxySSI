import SwiftUI

enum GalaxySSIHealthAtlasImmuneLink: String, CaseIterable {
  case monocyte = "cell-monocyte", dendritic = "cell-dendritic-cell", plasma = "cell-plasma-cell"
  var asset: String {
    switch self {
    case .monocyte: return "HealthAtlasImmuneMonocyte"
    case .dendritic: return "HealthAtlasImmuneDendritic"
    case .plasma: return "HealthAtlasImmunePlasma"
    }
  }
  var relatedID: String {
    switch self {
    case .monocyte: return "cell-macrophage"
    case .dendritic: return "cell-t-cell"
    case .plasma: return "cell-b-cell"
    }
  }
  var relatedAsset: String {
    switch self {
    case .monocyte: return "HealthAtlasImmuneMacrophage"
    case .dendritic: return "HealthAtlasImmuneTCell"
    case .plasma: return "HealthAtlasImmuneBCell"
    }
  }
  var scopeKey: String {
    switch self {
    case .monocyte: return "monocyte_lesson_scope"
    case .dendritic: return "dendritic_lesson_scope"
    case .plasma: return "plasma_lesson_scope"
    }
  }
  struct Placement: Equatable {
    let x: Double, y: Double, size: Double
    var widthRatio: Double = 1
  }
  struct Frame: Equatable {
    let lesson: GalaxySSIHealthAtlasImmuneLink
    let scene: GalaxySSIHealthAtlasCellScene.Frame
    var stage: Int { scene.stage }
    var ease: Double { scene.ease }
    init?(_ lesson: GalaxySSIHealthAtlasImmuneLink, phase: Double) {
      guard let scene = GalaxySSIHealthAtlasCellScene.Frame(phase) else { return nil }
      self.lesson = lesson; self.scene = scene
    }
    var primary: Placement {
      switch lesson {
      case .monocyte:
        if stage == 3 { return .init(x: 91, y: 101, size: 155) }
        return .init(x: stage == 0 ? 64 + 85 * ease : stage == 1 ? 149 + 94 * ease : 243,
          y: stage < 2 ? 55 : 55 + 89 * ease, size: 103, widthRatio: stage == 2 ? 1 - 1.1 * ease * (1 - ease) : 1)
      case .dendritic:
        return stage < 2 ? .init(x: 166, y: 103, size: 202) : .init(x: 113, y: 108, size: 170)
      case .plasma:
        return stage == 0 ? .init(x: 272, y: 101, size: 164) : .init(x: 119, y: 101, size: 202)
      }
    }
    var related: Placement? {
      switch lesson {
      case .monocyte: return stage == 3 ? .init(x: 269, y: 101, size: 183) : nil
      case .dendritic: return stage >= 2 ? .init(x: 254 - 20 * ease, y: 100, size: 177) : nil
      case .plasma: return stage == 0 ? .init(x: 89, y: 101, size: 168) : nil
      }
    }
    func arrowHead(from: Double, to: Double) -> Double { from + (to - from) * (0.25 + 0.75 * ease) }
  }
}

struct GalaxySSIHealthAtlasImmuneLinkView: View {
  let atlas: GalaxySSIHealthAtlas
  let lesson: GalaxySSIHealthAtlasImmuneLink
  let phase: Double
  let stages: [String]
  let language: String
  let open: (String) -> Void
  private static let teal = color(0x38796B), gold = color(0xAF7136), vessel = color(0x64869D), blue = color(0x375B8A)
  var body: some View {
    if let frame = GalaxySSIHealthAtlasImmuneLink.Frame(lesson, phase: phase) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSIHealthAtlasCellScene(frame: frame.scene, stages: stages, language: language, identifier: "atlas-immune-link-diagram") { drawing in
          switch lesson {
          case .monocyte: monocyte(in: drawing, frame: frame)
          case .dendritic: dendritic(in: drawing, frame: frame)
          case .plasma: plasma(in: drawing, frame: frame)
          }
        }
        Text(GalaxySSIHealthAtlasText.get("health_atlas_" + lesson.scopeKey, language)).font(.footnote).foregroundColor(.secondary)
        GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: lesson.relatedID, language: language, open: open)
      }
    }
  }
  private func portraits(in context: GraphicsContext, frame: GalaxySSIHealthAtlasImmuneLink.Frame) {
    let p = frame.primary
    GalaxySSIHealthAtlasCellScene.portrait(in: context, asset: lesson.asset, x: p.x, y: p.y, size: p.size, widthRatio: p.widthRatio)
    if let r = frame.related {
      GalaxySSIHealthAtlasCellScene.portrait(in: context, asset: lesson.relatedAsset, x: r.x, y: r.y, size: r.size, widthRatio: r.widthRatio)
    }
  }
  private func monocyte(in context: GraphicsContext, frame: GalaxySSIHealthAtlasImmuneLink.Frame) {
    if frame.stage == 3 {
      portraits(in: context, frame: frame); arrow(in: context, frame: frame, from: 159, to: 201, y: 101)
      return
    }
    context.fill(rounded(21, 12, 318, 85, 20), with: .color(Self.color(0x6C99B7).opacity(50.0 / 255)))
    line(in: context, 34, 15, 325, 15, Self.vessel, 4)
    line(in: context, 34, 96, 210, 96, Self.vessel, 4)
    line(in: context, 277, 96, 325, 96, Self.vessel, 4)
    if frame.stage > 0 {
      for index in 0...3 {
        let i = Double(index)
        context.fill(circle(243 + i * 9, 123 + i * 14, 2.3 + i * 0.7), with: .color(Self.gold))
      }
    }
    portraits(in: context, frame: frame)
  }
  private func dendritic(in context: GraphicsContext, frame: GalaxySSIHealthAtlasImmuneLink.Frame) {
    let t = frame.ease
    portraits(in: context, frame: frame)
    if frame.stage < 2 {
      let target = frame.stage == 0 ? 296 - 73 * t : 223
      if frame.stage == 0 { context.fill(circle(target, 108, 6), with: .color(Self.gold)) }
      else {
        for index in -1...1 {
          let i = Double(index)
          context.fill(circle(target + i * 5.5, 107 + i * (3 + 4 * t), 3.4), with: .color(Self.gold))
        }
      }
      return
    }
    context.stroke(circle(179, 96, frame.stage == 2 ? 5 + t * 3 : 7), with: .color(frame.stage == 2 ? Self.gold : Self.teal), lineWidth: 2.5)
    if frame.stage == 3 {
      for bounds in [CGRect(x: 183 + 8 * t, y: 69, width: 32, height: 57), CGRect(x: 190 + 8 * t, y: 59, width: 36, height: 78)] {
        arc(in: context, bounds: bounds, start: -58, end: 58, color: Self.teal, width: 2.5)
      }
    }
  }
  private func plasma(in context: GraphicsContext, frame: GalaxySSIHealthAtlasImmuneLink.Frame) {
    let t = frame.ease
    portraits(in: context, frame: frame)
    switch frame.stage {
    case 0: arrow(in: context, frame: frame, from: 151, to: 205, y: 101)
    case 1:
      let bounds = CGRect(x: 158 - t * 3, y: 81 - t * 3, width: 18 + t * 6, height: 43 + t * 6)
      context.stroke(Path(ellipseIn: bounds), with: .color(Self.teal), lineWidth: 2.8)
    case 2:
      for index in -1...1 {
        let i = Double(index)
        antibody(in: context, x: 190 + t * (79 + i * 4), y: 102 + i * (10 + t * 13))
      }
    default:
      let target = Path(ellipseIn: CGRect(x: 252, y: 62, width: 61, height: 81))
      context.fill(target, with: .color(Self.color(0xEDDFB1))); context.stroke(target, with: .color(Self.gold), lineWidth: 2.5)
      antibody(in: context, x: 237 + 12 * t, y: 104); antibody(in: context, x: 260, y: 58)
    }
  }
  private func antibody(in context: GraphicsContext, x: Double, y: Double) {
    line(in: context, x - 7, y, x, y, Self.blue, 2.8)
    line(in: context, x, y, x + 7, y - 7, Self.blue, 2.8)
    line(in: context, x, y, x + 7, y + 7, Self.blue, 2.8)
  }
  private func arrow(in context: GraphicsContext, frame: GalaxySSIHealthAtlasImmuneLink.Frame, from: Double, to: Double, y: Double) {
    let head = frame.arrowHead(from: from, to: to)
    line(in: context, from, y, head, y, Self.teal, 2.7)
    line(in: context, head - 7, y - 6, head, y, Self.teal, 2.7)
    line(in: context, head - 7, y + 6, head, y, Self.teal, 2.7)
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

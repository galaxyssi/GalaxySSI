import SwiftUI

enum GalaxySSIHealthAtlasGranulocyte: String, CaseIterable {
  case neutrophil = "cell-neutrophil", eosinophil = "cell-eosinophil", basophil = "cell-basophil"
  var scopeKey: String { String(rawValue.dropFirst(5)) + "_scope" }
  var asset: String {
    switch self {
    case .neutrophil: return "HealthAtlasImmuneNeutrophil"
    case .eosinophil: return "HealthAtlasImmuneEosinophil"
    case .basophil: return "HealthAtlasImmuneBasophil"
    }
  }
  struct Frame: Equatable {
    let lesson: GalaxySSIHealthAtlasGranulocyte
    let stage: Int
    let ease: Double
    init?(_ lesson: GalaxySSIHealthAtlasGranulocyte, phase: Double) {
      guard let value = GalaxySSIHealthAtlasSectionLesson.Phase(phase) else { return nil }
      self.lesson = lesson; stage = value.stage
      let progress = value.fraction
      ease = progress * progress * (3 - 2 * progress)
    }
    var cellBounds: CGRect {
      let x: Double, y: Double, size: Double, widthRatio: Double
      switch lesson {
      case .neutrophil:
        x = stage == 0 ? 76 + 109 * ease : stage == 1 ? 185 : 178
        y = stage == 0 ? 57 : stage == 1 ? 57 + 79 * ease : 100
        size = stage < 2 ? 126 : 232
        widthRatio = stage == 1 ? 1 - 1.1 * ease * (1 - ease) : 1
      case .eosinophil:
        x = stage == 0 ? 94 + 54 * ease : stage == 1 ? 148 + 23 * ease : 171
        y = 101; size = 205; widthRatio = 1
      case .basophil:
        x = 110; y = 101; size = 209; widthRatio = 1
      }
      return CGRect(x: x - size * widthRatio / 2, y: y - size / 2, width: size * widthRatio, height: size)
    }
    var uptakeX: Double { stage == 2 ? 271 - 56 * ease : 215 }
    var uptakeRadius: Double { stage == 2 ? 11 + 5 * ease : 16 }
    var vesselResponse: Double { stage == 3 ? 9 * ease : 0 }
  }
  static func label(stage: Int, stages: [String], language: String) -> String? {
    guard stages.count == 4, stages.indices.contains(stage) else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_granulocyte_stage", language),
      GalaxySSIHealthAtlasText.get(stages[stage], language))
  }
}

struct GalaxySSIHealthAtlasGranulocyteView: View {
  let lesson: GalaxySSIHealthAtlasGranulocyte
  let phase: Double
  let stages: [String]
  let language: String
  private static let vessel = color(0x64869D), plum = color(0x654A7D), gold = color(0xAB692D), coral = color(0xA75144)
  var body: some View {
    if let frame = GalaxySSIHealthAtlasGranulocyte.Frame(lesson, phase: phase),
       let label = GalaxySSIHealthAtlasGranulocyte.label(stage: frame.stage, stages: stages, language: language) {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 200)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 200 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        switch lesson {
        case .neutrophil: neutrophil(in: drawing, frame: frame)
        case .eosinophil: eosinophil(in: drawing, frame: frame)
        case .basophil: basophil(in: drawing, frame: frame)
        }
      }.aspectRatio(360.0 / 200, contentMode: .fit).frame(maxHeight: 240).clipped()
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier("atlas-granulocyte-diagram")
    }
  }
  private func cell(in context: GraphicsContext, frame: GalaxySSIHealthAtlasGranulocyte.Frame) {
    context.draw(Image(lesson.asset), in: frame.cellBounds)
  }
  private func neutrophil(in context: GraphicsContext, frame: GalaxySSIHealthAtlasGranulocyte.Frame) {
    let t = frame.ease
    if frame.stage < 2 {
      context.fill(rounded(18, 15, 324, 81, 18), with: .color(Self.color(0x6C99B7).opacity(52.0 / 255)))
      line(in: context, 29, 18, 331, 18, Self.vessel, 5)
      line(in: context, 29, 95, 146, 95, Self.vessel, 5)
      line(in: context, 223, 95, 331, 95, Self.vessel, 5)
      for index in 0...4 {
        let i = Double(index)
        context.fill(circle(186 + i * 15, 129 + i * 8, 2.5 + i * 0.65), with: .color(Self.gold))
      }
      cell(in: context, frame: frame)
      return
    }
    cell(in: context, frame: frame)
    context.stroke(circle(frame.uptakeX, 104, frame.uptakeRadius), with: .color(Self.plum), lineWidth: 2.8)
    if frame.stage == 2 {
      context.fill(rounded(frame.uptakeX - 8, 100, 16, 8, 4), with: .color(Self.gold))
    } else {
      for index in -1...1 {
        let i = Double(index)
        context.fill(circle(frame.uptakeX + i * (5 + 2 * t), 104 + i * 3, 3.4 - t), with: .color(Self.gold))
      }
    }
  }
  private func eosinophil(in context: GraphicsContext, frame: GalaxySSIHealthAtlasGranulocyte.Frame) {
    let t = frame.ease
    cell(in: context, frame: frame)
    let target = rounded(241, 31, 50, 139, 22)
    context.fill(target, with: .color(Self.color(0xEFC4A5)))
    context.stroke(target, with: .color(Self.color(0x99694D)), lineWidth: 2.8)
    switch frame.stage {
    case 0:
      for index in 0...3 {
        let i = Double(index)
        context.fill(circle(195 + i * 12, 132, 2.3 + i), with: .color(Self.coral))
      }
    case 1: context.stroke(circle(242, 101, 5 + 8 * t), with: .color(Self.coral), lineWidth: 2.5)
    case 2:
      for index in -2...2 {
        context.fill(circle(215 + 24 * t, 101 + Double(index) * (3 + 7 * t), 3.3), with: .color(Self.coral))
      }
    default:
      for index in -1...1 {
        let i = Double(index)
        line(in: context, 242, 101 + i * 17, 247 + 8 * t, 96 + i * 17, Self.coral, 3)
      }
    }
  }
  private func basophil(in context: GraphicsContext, frame: GalaxySSIHealthAtlasGranulocyte.Frame) {
    let t = frame.ease, response = frame.vesselResponse
    cell(in: context, frame: frame)
    let target = rounded(265 - response, 31, 43 + response * 2, 138, 19)
    context.fill(target, with: .color(Self.color(0xD4E5EB)))
    context.stroke(target, with: .color(Self.vessel), lineWidth: 3)
    switch frame.stage {
    case 0: context.stroke(circle(24 + 16 * t, 101, 7), with: .color(Self.gold), lineWidth: 2.6)
    case 1:
      context.stroke(circle(157, 94, 8 + 5 * t), with: .color(Self.gold), lineWidth: 2.6)
      context.stroke(circle(153, 125, 6 + 4 * t), with: .color(Self.gold), lineWidth: 2.6)
    case 2:
      for index in -2...2 {
        context.fill(circle(166 + t * 88, 98 + Double(index) * (4 + 9 * t), 3.2), with: .color(Self.plum))
      }
    default:
      let bounds = CGRect(x: 215 - t * 8, y: 65, width: 40, height: 60)
      var arc = Path()
      arc.addArc(center: .zero, radius: 1, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
      let transform = CGAffineTransform(a: bounds.width / 2, b: 0, c: 0, d: bounds.height / 2, tx: bounds.midX, ty: bounds.midY)
      context.stroke(arc.applying(transform), with: .color(Self.plum), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
  }
  private func line(in context: GraphicsContext, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: Color, _ width: Double) {
    var path = Path()
    path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
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

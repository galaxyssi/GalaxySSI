import SwiftUI

struct GalaxySSIHealthAtlasPhagocytosis: View {
  static let owner = GalaxySSIHealthAtlas.ImmunePack.phagocytosisOwner
  let phase: Double
  let stages: [String]
  let language: String
  private static let particle = color(0x9F6C44), compartment = color(0xA06476), signal = color(0x40827F)
  struct Frame: Equatable {
    let stage: Int
    let progress: Double
    init?(_ phase: Double) {
      guard let value = GalaxySSIHealthAtlasSectionLesson.Phase(phase) else { return nil }
      stage = value.stage; progress = value.fraction
    }
    var ease: Double { progress * progress * (3 - 2 * progress) }
    var particleX: Double { stage == 0 ? 298 - ease * 80 : 218 - ease * 62 }
    var compartmentRadius: Double { 15 + ease * 8 }
    var compartmentOpacity: Double { Double(Int(70 + ease * 185)) / 255 }
    var fragmentRadii: [Double] { [4.5 - ease * 2, 4 - ease * 2, 3.5 - ease * 2] }
    var signalDrift: Double { ease * 18 }
  }
  static func label(stage: Int, stages: [String], language: String) -> String? {
    guard (0..<4).contains(stage), stages.count == 4 else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_phagocytosis_visual_stage", language),
      GalaxySSIHealthAtlasText.get(stages[stage], language))
  }
  var body: some View {
    if let frame = Frame(phase), let label = Self.label(stage: frame.stage, stages: stages, language: language) {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 200)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 200 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        drawing.draw(Image("HealthAtlasImmuneMacrophage"), in: CGRect(x: 17, y: -22, width: 244, height: 244))
        switch frame.stage {
        case 0:
          target(in: drawing, x: frame.particleX, y: 98)
          var arrow = Path()
          arrow.move(to: CGPoint(x: 276, y: 119)); arrow.addLine(to: CGPoint(x: 215, y: 119))
          arrow.addLine(to: CGPoint(x: 222, y: 114)); arrow.move(to: CGPoint(x: 215, y: 119))
          arrow.addLine(to: CGPoint(x: 222, y: 124))
          drawing.stroke(arrow, with: .color(Self.particle), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case 1:
          drawing.stroke(circle(frame.particleX, 98, frame.compartmentRadius),
            with: .color(Self.compartment.opacity(frame.compartmentOpacity)), lineWidth: 2.5)
          target(in: drawing, x: frame.particleX, y: 98)
        case 2:
          drawing.stroke(circle(156, 98, 23), with: .color(Self.compartment), lineWidth: 2.5)
          for (index, point) in [(146.0, 94.0), (156.0, 105.0), (166.0, 96.0)].enumerated() {
            drawing.fill(circle(point.0, point.1, frame.fragmentRadii[index]), with: .color(Self.particle))
          }
        default:
          drawing.stroke(circle(156, 98, 10), with: .color(Self.compartment), lineWidth: 2.5)
          drawing.fill(circle(156, 98, 2.5), with: .color(Self.particle))
          for bounds in [CGRect(x: 220 + frame.signalDrift, y: 75, width: 40, height: 46),
            CGRect(x: 218 + frame.signalDrift, y: 64, width: 58, height: 68)] {
            var arc = Path()
            arc.addArc(center: .zero, radius: 1, startAngle: .degrees(-38), endAngle: .degrees(38), clockwise: false)
            let transform = CGAffineTransform(a: bounds.width / 2, b: 0, c: 0, d: bounds.height / 2, tx: bounds.midX, ty: bounds.midY)
            drawing.stroke(arc.applying(transform), with: .color(Self.signal), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          }
        }
      }.aspectRatio(360.0 / 200, contentMode: .fit).frame(maxHeight: 235)
        .clipped()
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier("atlas-phagocytosis-diagram")
    }
  }
  private func target(in context: GraphicsContext, x: Double, y: Double) {
    var drawing = context
    drawing.translateBy(x: x, y: y); drawing.rotate(by: .degrees(-23))
    drawing.fill(Path(roundedRect: CGRect(x: -11, y: -5, width: 22, height: 10), cornerRadius: 5), with: .color(Self.particle))
  }
  private func circle(_ x: Double, _ y: Double, _ radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
  }
  private static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}

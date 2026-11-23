import SwiftUI

struct GalaxySSIHealthAtlasPhagocytosis: View {
  static let owner = GalaxySSIHealthAtlas.ImmunePack.phagocytosisOwner
  let stage: Int
  let stages: [String]
  let language: String
  private static let membrane = color(0x508975), cytoplasm = color(0xB5D4BE), nucleus = color(0x75668C)
  private static let particle = color(0x9F6C44), compartment = color(0xA06476), signal = color(0x40827F)
  static func label(stage: Int, stages: [String], language: String) -> String? {
    guard (0..<4).contains(stage), stages.count == 4 else { return nil }
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_phagocytosis_visual_stage", language),
      GalaxySSIHealthAtlasText.get(stages[stage], language))
  }
  var body: some View {
    if let label = Self.label(stage: stage, stages: stages, language: language) {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 176)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 176 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        drawing.fill(Self.outline, with: .color(Self.cytoplasm))
        drawing.stroke(Self.outline, with: .color(Self.membrane), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        drawing.fill(Path(ellipseIn: CGRect(x: 83, y: 61, width: 76, height: 59)), with: .color(Self.nucleus))
        switch stage {
        case 0:
          target(in: drawing, x: 303, y: 100)
          var arrow = Path()
          arrow.move(to: CGPoint(x: 288, y: 100)); arrow.addLine(to: CGPoint(x: 269, y: 100))
          arrow.addLine(to: CGPoint(x: 276, y: 95)); arrow.move(to: CGPoint(x: 269, y: 100))
          arrow.addLine(to: CGPoint(x: 276, y: 105))
          drawing.stroke(arrow, with: .color(Self.particle), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case 1:
          drawing.stroke(circle(217, 101, 25), with: .color(Self.compartment), lineWidth: 3)
          target(in: drawing, x: 217, y: 101)
        case 2:
          drawing.fill(circle(207, 100, 29), with: .color(Self.color(0xE4BDAB)))
          drawing.stroke(circle(207, 100, 29), with: .color(Self.compartment), lineWidth: 3)
          for (x, y, radius) in [(199.0, 97.0, 4.0), (208.0, 104.0, 3.0), (215.0, 96.0, 3.0)] {
            drawing.fill(circle(x, y, radius), with: .color(Self.particle))
          }
          drawing.fill(circle(180, 73, 6), with: .color(Self.compartment))
          drawing.fill(circle(176, 118, 5), with: .color(Self.compartment))
        default:
          drawing.stroke(circle(199, 100, 16), with: .color(Self.compartment), lineWidth: 2.5)
          drawing.fill(circle(200, 100, 3), with: .color(Self.particle))
          for bounds in [CGRect(x: 262, y: 70, width: 51, height: 55), CGRect(x: 258, y: 60, width: 69, height: 75)] {
            var arc = Path()
            arc.addArc(center: .zero, radius: 1, startAngle: .degrees(-38), endAngle: .degrees(38), clockwise: false)
            let transform = CGAffineTransform(a: bounds.width / 2, b: 0, c: 0, d: bounds.height / 2, tx: bounds.midX, ty: bounds.midY)
            drawing.stroke(arc.applying(transform), with: .color(Self.signal), style: StrokeStyle(lineWidth: 3, lineCap: .round))
          }
        }
      }.aspectRatio(360.0 / 176, contentMode: .fit).frame(maxHeight: 235)
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier("atlas-phagocytosis-diagram")
    }
  }
  private func target(in context: GraphicsContext, x: CGFloat, y: CGFloat) {
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
  private static var outline: Path {
    Path { path in
      path.move(to: CGPoint(x: 47, y: 84))
      path.addCurve(to: CGPoint(x: 89, y: 42), control1: CGPoint(x: 47, y: 59), control2: CGPoint(x: 64, y: 49))
      path.addCurve(to: CGPoint(x: 154, y: 32), control1: CGPoint(x: 105, y: 22), control2: CGPoint(x: 134, y: 18))
      path.addCurve(to: CGPoint(x: 211, y: 59), control1: CGPoint(x: 182, y: 29), control2: CGPoint(x: 199, y: 42))
      path.addCurve(to: CGPoint(x: 268, y: 67), control1: CGPoint(x: 228, y: 63), control2: CGPoint(x: 252, y: 55))
      path.addCurve(to: CGPoint(x: 251, y: 102), control1: CGPoint(x: 275, y: 80), control2: CGPoint(x: 249, y: 88))
      path.addCurve(to: CGPoint(x: 271, y: 133), control1: CGPoint(x: 252, y: 113), control2: CGPoint(x: 279, y: 119))
      path.addCurve(to: CGPoint(x: 220, y: 146), control1: CGPoint(x: 261, y: 151), control2: CGPoint(x: 232, y: 136))
      path.addCurve(to: CGPoint(x: 134, y: 160), control1: CGPoint(x: 197, y: 169), control2: CGPoint(x: 158, y: 159))
      path.addCurve(to: CGPoint(x: 76, y: 146), control1: CGPoint(x: 110, y: 160), control2: CGPoint(x: 97, y: 145))
      path.addCurve(to: CGPoint(x: 51, y: 111), control1: CGPoint(x: 57, y: 143), control2: CGPoint(x: 63, y: 120))
      path.addCurve(to: CGPoint(x: 47, y: 84), control1: CGPoint(x: 40, y: 106), control2: CGPoint(x: 43, y: 93))
      path.closeSubpath()
    }
  }
}

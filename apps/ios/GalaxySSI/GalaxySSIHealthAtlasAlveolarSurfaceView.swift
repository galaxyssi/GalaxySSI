import SwiftUI

struct GalaxySSIHealthAtlasAlveolarSurfaceView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  @Environment(\.colorScheme) private var scheme
  private var accent: Color { scheme == .dark ? Color(red: 242/255, green: 187/255, blue: 128/255) :
    Color(red: 184/255, green: 119/255, blue: 67/255) }
  var body: some View {
    if model.kind == .alveolarSurface {
      Canvas { context, size in
        let large = min(size.width * 0.17, size.height * 0.28), y = size.height * 0.36
        for index in 0...1 {
          let x = CGFloat(2 * index + 1) * size.width / 4, radius = large * CGFloat(index + 1) / 2
          context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
            with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
          var spoke = Path(); spoke.move(to: CGPoint(x: x, y: y)); spoke.addLine(to: CGPoint(x: x + radius, y: y))
          context.stroke(spoke, with: .color(accent), lineWidth: 2)
          context.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)), with: .color(accent))
          context.draw(Text(index == 0 ? "r" : "2r").font(.system(size: 13)).foregroundColor(.secondary),
            at: CGPoint(x: x, y: y + large + 17))
          let pressure = index == 0 ? model.result : model.companionValue
          context.draw(Text(number(pressure) + " Pa").font(.system(size: 13)).foregroundColor(.secondary),
            at: CGPoint(x: x, y: size.height - 10))
        }
      }.frame(height: 138)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: GalaxySSIHealthAtlasText.get("health_atlas_alveolar_surface_diagram", language),
          number(model.input(1)), number(model.result), number(model.input(1) * 2), number(model.companionValue)))
        .accessibilityIdentifier("atlas-alveolar-surface-diagram")
    }
  }
  private func number(_ value: Double) -> String { GalaxySSIHealthAtlasPhysiologyText.number(value, language: language) }
}

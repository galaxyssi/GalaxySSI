import SwiftUI

struct GalaxySSIHealthAtlasPodocyteView: View {
  let stage: Int
  let stages: [String]
  let language: String
  var body: some View {
    if let model = GalaxySSIHealthAtlasFiltrationStage(stage: stage), stages.count == 4 {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 360, size.height / 201)
        drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 201 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        let labels = ["blood", "endothelium", "basement", "slits", "filtrate"]
        for (index, y) in [34.0, 75.0, 104.0, 135.0, 185.0].enumerated() {
          drawing.draw(Text(t("podocyte_" + labels[index])).font(.system(size: 13)).foregroundColor(.secondary),
            in: CGRect(x: 11, y: y - 14, width: 122, height: 28))
        }
        for i in 0...3 { rect(drawing, x: 138 + Double(i) * 51, y: 62, w: 43, h: 17, radius: 5, color: 0xB66076) }
        rect(drawing, x: 138, y: 93, w: 196, h: 16, radius: 4, color: 0xDEB86D)
        for i in 0...7 {
          let x = 138 + Double(i) * 25, color: UInt32 = i.isMultiple(of: 2) ? 0x57837B : 0x648ADE
          rect(drawing, x: x, y: 108, w: 19, h: 25, radius: 5, color: color)
          rect(drawing, x: x + 5, y: 127, w: 9, h: 24, radius: 3, color: color)
        }
        if model.showsSlitDiaphragms {
          for i in 0...6 { rect(drawing, x: 157 + Double(i) * 25, y: 119, w: 6, h: 4, radius: 0, color: 0x68827E) }
        }
        drawing.fill(Path(ellipseIn: CGRect(x: 166, y: 17, width: 33, height: 20)), with: .color(color(0xC76578)))
        drawing.fill(Path(ellipseIn: CGRect(x: 174, y: 23, width: 17, height: 8)), with: .color(color(0xEA9A9E)))
        let end = Double(model.arrowEnd)
        var arrow = Path(); arrow.move(to: CGPoint(x: 235, y: 20)); arrow.addLine(to: CGPoint(x: 235, y: end))
        arrow.move(to: CGPoint(x: 230, y: end - 6)); arrow.addLine(to: CGPoint(x: 235, y: end))
        arrow.addLine(to: CGPoint(x: 240, y: end - 6))
        drawing.stroke(arrow, with: .color(.secondary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
      }.aspectRatio(360.0 / 201, contentMode: .fit).frame(maxHeight: 235)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasText.get(stages[stage], language) + ". " + t("podocyte_scope"))
        .accessibilityIdentifier("atlas-podocyte-diagram")
    }
  }
  private func rect(_ context: GraphicsContext, x: Double, y: Double, w: Double, h: Double, radius: Double, color value: UInt32) {
    context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius), with: .color(color(value)))
  }
  private func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}

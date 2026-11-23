import SwiftUI

struct GalaxySSIHealthAtlasSarcomerePanel: View {
  let stage: Int
  let stages: [String]
  let language: String
  @Environment(\.colorScheme) private var scheme
  private var thin: Color { scheme == .dark ? Color(red: 236/255, green: 162/255, blue: 180/255) : Color(red: 169/255, green: 78/255, blue: 102/255) }
  private var thick: Color { scheme == .dark ? Color(red: 197/255, green: 179/255, blue: 235/255) : Color(red: 103/255, green: 85/255, blue: 133/255) }
  var body: some View {
    if let model = GalaxySSIHealthAtlasSarcomere(stage: stage), stages.count == 4 {
      VStack(alignment: .leading, spacing: 8) {
        Canvas { context, size in
          var drawing = context
          let scale = min(size.width / 360, size.height / 156)
          drawing.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 156 * scale) / 2)
          drawing.scaleBy(x: scale, y: scale)
          let left = Double(model.leftZ), right = Double(model.rightZ)
          for y in [61.0, 95.0] {
            line(drawing, left, y, left + Double(model.thinLength), y, thin, 4)
            line(drawing, right - Double(model.thinLength), y, right, y, thin, 4)
          }
          line(drawing, Double(model.leftThick), 78, Double(model.rightThick), 78, thick, 8)
          for x in stride(from: 122.0, through: 238.0, by: 13) {
            line(drawing, x, 78, x + 6, 70, thick, 2.5)
            line(drawing, x, 78, x - 6, 86, thick, 2.5)
          }
          for x in [left, right] {
            line(drawing, x, 46, x, 109, .primary, 4)
            drawing.draw(Text(t("sarcomere_z")).font(.system(size: 13)).foregroundColor(.primary), at: CGPoint(x: x, y: 128))
          }
          switch stage {
          case 0: arrow(drawing, left - 20, left - 1)
          case 1:
            for x in [157.0, 179.0, 202.0] {
              drawing.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: 35.5, width: 7, height: 7)), with: .color(.green))
            }
          case 2: arrow(drawing, left - 25, left - 2); arrow(drawing, right + 25, right + 2)
          default: break
          }
        }.aspectRatio(360.0 / 156, contentMode: .fit).frame(maxHeight: 220)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(String(format: t("sarcomere_visual_stage"),
            GalaxySSIHealthAtlasText.get(stages[stage], language), model.context(text: t)[0]))
          .accessibilityIdentifier("atlas-sarcomere-diagram")
        Text(model.context(text: t)[0]).font(.subheadline.bold()).accessibilityIdentifier("atlas-sarcomere-ratio")
        Text(t("sarcomere_filaments")).font(.caption).foregroundColor(.secondary)
        Text(t("sarcomere_scope")).font(.footnote).foregroundColor(.secondary)
      }
    }
  }
  private func line(_ context: GraphicsContext, _ x: Double, _ y: Double, _ endX: Double, _ endY: Double, _ color: Color, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: endX, y: endY))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func arrow(_ context: GraphicsContext, _ start: Double, _ end: Double) {
    let behind = end + (start < end ? -6 : 6)
    line(context, start, 34, end, 34, .green, 2.4)
    line(context, behind, 30, end, 34, .green, 2.4)
    line(context, behind, 38, end, 34, .green, 2.4)
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
}

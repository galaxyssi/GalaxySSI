import SwiftUI

struct GalaxySSIHealthAtlasVillusAreaView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var body: some View {
    if model.kind == .villusArea {
      Canvas { context, size in
        var drawing = context
        let scale = min(size.width / 320, size.height / 150)
        drawing.translateBy(x: (size.width - 320 * scale) / 2, y: (size.height - 150 * scale) / 2)
        drawing.scaleBy(x: scale, y: scale)
        let area = Path(CGRect(x: 28, y: 31, width: 96, height: 96))
        drawing.fill(area, with: .color(Color(red: 227/255, green: 244/255, blue: 238/255)))
        drawing.stroke(area, with: .color(.primary), lineWidth: 1.5)
        var baseline = Path(); baseline.move(to: CGPoint(x: 192, y: 127)); baseline.addLine(to: CGPoint(x: 288, y: 127))
        drawing.stroke(baseline, with: .color(.primary), lineWidth: 1.5)
        let radius = model.input(1) * 96
        let material = Color(red: 43/255, green: 144/255, blue: 128/255)
        for index in 0..<model.inputs[0] {
          let slot = (12 + 7 * index) % 25
          let x = 28 + (Double(slot % 5) + 0.5) * 19.2
          let y = 31 + (Double(slot / 5) + 0.5) * 19.2
          drawing.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
            with: .color(material))
        }
        if model.inputs[0] > 0 {
          let top = 127 - model.input(2) * 96
          drawing.fill(Path(CGRect(x: 240 - radius, y: top, width: radius * 2, height: 127 - top)), with: .color(material))
          drawing.fill(Path(ellipseIn: CGRect(x: 240 - radius, y: top - 2.4, width: radius * 2, height: 4.8)),
            with: .color(Color(red: 156/255, green: 215/255, blue: 202/255)))
        }
      }.aspectRatio(320.0 / 150, contentMode: .fit).frame(maxHeight: 154)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasText.get("health_atlas_gut_section_area_views", language) + ". " +
          String(format: GalaxySSIHealthAtlasText.get("health_atlas_gut_section_area_diagram_accessible", language),
            Int64(model.inputs[0]),
            GalaxySSIHealthAtlasPhysiologyText.inputNumber(model.input(1), key: "gut_section_area_radius", language: language),
            GalaxySSIHealthAtlasPhysiologyText.inputNumber(model.input(2), key: "gut_section_area_height", language: language)))
        .accessibilityIdentifier("atlas-villus-geometry")
    }
  }
}

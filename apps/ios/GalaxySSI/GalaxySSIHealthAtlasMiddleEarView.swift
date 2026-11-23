import SwiftUI

struct GalaxySSIHealthAtlasMiddleEarView: View {
  let model: GalaxySSIHealthAtlasMiddleEar
  let language: String
  @Environment(\.colorScheme) private var scheme
  private var inputColor: Color {
    scheme == .dark ? Color(red: 242.0 / 255, green: 187.0 / 255, blue: 128.0 / 255) :
      Color(red: 184.0 / 255, green: 119.0 / 255, blue: 67.0 / 255)
  }
  private var outputColor: Color {
    scheme == .dark ? Color(red: 129.0 / 255, green: 202.0 / 255, blue: 194.0 / 255) :
      Color(red: 38.0 / 255, green: 123.0 / 255, blue: 123.0 / 255)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("transformer")).font(.headline)
      GeometryReader { geometry in
        let centre = geometry.size.width * 0.5, arm = geometry.size.width * 0.19
        let left = centre - arm * CGFloat(model.leverRatio), right = centre + arm
        let beam = geometry.size.height * 0.66, disc = geometry.size.height * 0.30
        let scale = min(geometry.size.width * 0.12, geometry.size.height * 0.24)
        let inputRadius = scale * CGFloat(sqrt(model.membraneAreaMm2 / 75))
        let outputRadius = scale * CGFloat(sqrt(model.footplateAreaMm2 / 75))
        ZStack {
          Path { path in
            path.move(to: CGPoint(x: left, y: beam)); path.addLine(to: CGPoint(x: right, y: beam))
            for x in [left, right] {
              path.move(to: CGPoint(x: x, y: disc)); path.addLine(to: CGPoint(x: x, y: beam))
            }
          }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          Path { path in
            path.move(to: CGPoint(x: centre, y: beam)); path.addLine(to: CGPoint(x: centre - 10, y: beam + 17))
            path.addLine(to: CGPoint(x: centre + 10, y: beam + 17)); path.closeSubpath()
          }.fill(Color.secondary)
          Circle().fill(inputColor).frame(width: inputRadius * 2, height: inputRadius * 2).position(x: left, y: disc)
          Circle().fill(outputColor).frame(width: outputRadius * 2, height: outputRadius * 2).position(x: right, y: disc)
        }
      }.frame(height: 144).accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasPhysiologyText.middleEarContext(model, language: language).joined(separator: "\n"))
        .accessibilityIdentifier("atlas-middle-ear-transformer")
      Text(GalaxySSIHealthAtlasPhysiologyText.middleEarRatios(model, language: language))
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-middle-ear-details")
      Text(t("diagram_scope")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }.accessibilityIdentifier("atlas-middle-ear-model")
  }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasPhysiologyText.string("middle_ear_" + key, language: language) }
}

import SwiftUI

struct GalaxySSIHealthAtlasEyeOpticsView: View {
  let eye: GalaxySSIHealthAtlasEyeOptics
  let language: String
  @Environment(\.colorScheme) private var scheme
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasPhysiologyText.string("eye_" + key, language: language) }
  private var rayColor: Color {
    scheme == .dark ? Color(red: 131.0 / 255, green: 190.0 / 255, blue: 235.0 / 255) :
      Color(red: 51.0 / 255, green: 111.0 / 255, blue: 164.0 / 255)
  }
  private var retinalColor: Color {
    scheme == .dark ? Color(red: 243.0 / 255, green: 152.0 / 255, blue: 160.0 / 255) :
      Color(red: 183.0 / 255, green: 70.0 / 255, blue: 80.0 / 255)
  }
  var body: some View {
    let lines = GalaxySSIHealthAtlasPhysiologyText.eyeContext(eye, language: language)
    VStack(alignment: .leading, spacing: 8) {
      Text(t("ray_title")).font(.headline)
      rays.frame(height: 128).accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: "\n")).accessibilityIdentifier("atlas-eye-rays")
      Text(lines[0]).bold().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-eye-focus-side")
      Text(lines[1]).fixedSize(horizontal: false, vertical: true)
      Text(lines[2]).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }.accessibilityIdentifier("atlas-eye-optics")
  }
  private var rays: some View {
    GeometryReader { geometry in
      let left: CGFloat = 10, right = max(left, geometry.size.width - 10)
      let lens = left + (right - left) * 0.3, axis = geometry.size.height / 2
      let unit = (right - lens) / 22, yScale = geometry.size.height * 0.32
      let retina = lens + CGFloat(GalaxySSIHealthAtlasEyeOptics.retinalPlaneMm) * unit
      ZStack {
        Path { path in
          path.move(to: CGPoint(x: left, y: axis)); path.addLine(to: CGPoint(x: right, y: axis))
        }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        Ellipse().fill(rayColor.opacity(60.0 / 255)).frame(width: 14, height: (yScale + 9) * 2).position(x: lens, y: axis)
        Path { path in
          path.move(to: CGPoint(x: retina, y: axis - yScale - 8)); path.addLine(to: CGPoint(x: retina, y: axis + yScale + 8))
        }.stroke(retinalColor, lineWidth: 3)
        Path { path in
          for sign in [-1.0, 1.0] {
            let incoming = CGFloat(eye.rayHeight(axialMm: -100, heightAtLensMm: sign) ?? 0) * yScale
            let outgoing = CGFloat(eye.rayHeight(axialMm: 22, heightAtLensMm: sign) ?? 0) * yScale
            path.move(to: CGPoint(x: left, y: axis + incoming))
            path.addLine(to: CGPoint(x: lens, y: axis + CGFloat(sign) * yScale))
            path.addLine(to: CGPoint(x: right, y: axis + outgoing))
          }
        }.stroke(rayColor, lineWidth: 2)
        Circle().fill(GalaxySSIHealthTheme.accent).frame(width: 8, height: 8)
          .position(x: lens + CGFloat(eye.imageDistanceMm) * unit, y: axis)
      }.clipped()
    }
  }
}

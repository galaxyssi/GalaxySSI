import SwiftUI

struct GalaxySSIHealthAtlasElbowView: View {
  let forces: GalaxySSIHealthAtlasElbow.Forces
  let language: String
  @ScaledMetric(relativeTo: .caption) private var diagramHeight: CGFloat = 200
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasPhysiologyText.string("elbow_" + key, language: language) }
  private var colors: [Color] { [.secondary, GalaxySSIHealthTheme.accent, .orange, .red] }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("diagram")).font(.headline)
      GeometryReader { geometry in
        let left: CGFloat = 16, width = max(1, geometry.size.width - 32), y = geometry.size.height * 0.45
        let x = { (metres: Double) in left + width * CGFloat(metres / 0.5) }
        ZStack {
          Path { path in
            path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: x(forces.loadArmMetres), y: y))
          }.stroke(Color.secondary, lineWidth: 5)
          Circle().fill(Color.secondary).frame(width: 12, height: 12).position(x: left, y: y)
          ForEach(0..<4) { index in
            let positions = [0, forces.muscleArmMetres, GalaxySSIHealthAtlasElbow.armCentreMetres, forces.loadArmMetres]
            let px = x(positions[index]), sign: CGFloat = index == 1 ? -1 : 1
            let end = y + sign * 42
            if index == 3 && forces.loadWeight == 0 {
              Circle().fill(colors[index]).frame(width: 6, height: 6).position(x: px, y: y)
            } else {
              Path { path in
                path.move(to: CGPoint(x: px, y: y)); path.addLine(to: CGPoint(x: px, y: end))
                path.move(to: CGPoint(x: px - 4, y: end - sign * 7)); path.addLine(to: CGPoint(x: px, y: end))
                path.addLine(to: CGPoint(x: px + 4, y: end - sign * 7))
              }.stroke(colors[index], lineWidth: 2.5)
            }
            Text(["E", "B", "A", "L"][index]).font(.caption).bold().foregroundColor(colors[index])
              .position(x: px, y: end + (index == 1 ? -18 : index == 3 ? 42 : 18))
          }
        }
      }.frame(height: diagramHeight).accessibilityHidden(true)
      ForEach(Array(GalaxySSIHealthAtlasPhysiologyText.elbowLabels(forces, language: language).enumerated()), id: \.offset) { index, label in
        Text(label).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-elbow-force-" + String(index))
      }
      Text(String(format: t("torque"), GalaxySSIHealthAtlasPhysiologyText.number(forces.torque, language: language))).bold()
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-elbow-torque")
      Text(t("fixed")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }.accessibilityIdentifier("atlas-elbow-balance")
  }
}

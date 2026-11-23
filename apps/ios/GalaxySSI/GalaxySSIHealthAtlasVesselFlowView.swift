import SwiftUI

struct GalaxySSIHealthAtlasVesselFlowView: View {
  let flow: GalaxySSIHealthAtlasVesselFlow
  let language: String
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasPhysiologyText.string("vessel_" + key, language: language) }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("diagram")).font(.headline)
      Text(GalaxySSIHealthAtlasPhysiologyText.vesselGeometry(flow, language: language))
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-vessel-geometry")
      profile.frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GalaxySSIHealthAtlasPhysiologyText.vesselContext(flow, language: language).joined(separator: "\n"))
        .accessibilityIdentifier("atlas-vessel-profile")
      ForEach(Array(GalaxySSIHealthAtlasPhysiologyText.vesselValues(flow, language: language).enumerated()), id: \.offset) { index, value in
        Text(value).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-vessel-value-" + String(index))
      }
      Text(t("diagram_scope")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }.accessibilityIdentifier("atlas-vessel-flow")
  }
  private var profile: some View {
    GeometryReader { geometry in
      let left: CGFloat = 12, middle = geometry.size.height / 2
      let right = left + max(0, geometry.size.width - 24) * CGFloat(flow.lengthMm / 100)
      let half = CGFloat(60 * flow.radiusMm / 0.2), origin = left + 4
      let run = max(0, right - origin - 4)
      let end = { (relative: Double) -> CGFloat in
        let fraction = flow.centreSpeedMmPerSecond == 0 ? 0 : (flow.speedMmPerSecond(relativeRadius: relative) ?? 0) / flow.centreSpeedMmPerSecond
        return origin + run * CGFloat(fraction)
      }
      ZStack {
        Path { path in
          path.addRect(CGRect(x: left, y: middle - half, width: max(0, right - left), height: half * 2))
        }.fill(Color.secondary.opacity(0.12))
        Path { path in
          for y in [middle - half, middle + half] {
            path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: right, y: y))
          }
        }.stroke(Color.secondary, lineWidth: 2.5)
        ForEach(-4...4, id: \.self) { index in
          let relative = Double(index) / 4, finish = end(relative)
          let y = middle + half * CGFloat(relative)
          if finish - origin > 3 {
            Path { path in
              path.move(to: CGPoint(x: origin, y: y)); path.addLine(to: CGPoint(x: finish, y: y))
              path.move(to: CGPoint(x: finish - 3, y: y - 3)); path.addLine(to: CGPoint(x: finish, y: y))
              path.addLine(to: CGPoint(x: finish - 3, y: y + 3))
            }.stroke(Color.red, lineWidth: 2)
          } else {
            Circle().fill(Color.red).frame(width: 4, height: 4).position(x: origin, y: y)
          }
        }
        Path { path in
          for index in 0...80 {
            let relative = Double(index) / 40 - 1
            let point = CGPoint(x: end(relative), y: middle + half * CGFloat(relative))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
          }
        }.stroke(GalaxySSIHealthTheme.accent, lineWidth: 2)
      }.clipped()
    }
  }
}

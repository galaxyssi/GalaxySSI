import SwiftUI

struct GalaxySSIHealthAtlasValvePanel: View {
  let atlas: GalaxySSIHealthAtlas
  let entryID: String
  let stage: Int
  let language: String
  let open: (String) -> Void
  private typealias Heart = GalaxySSIHealthAtlasHeartSection
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(Heart.phase(stage, language: language) ?? "").font(.headline).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("atlas-valve-phase")
      Image("HealthAtlasHeartSection").resizable().scaledToFit().frame(maxHeight: 300)
        .overlay(GeometryReader { geometry in
          let scale = min(geometry.size.width / 480, geometry.size.height / 460)
          let left = (geometry.size.width - 480 * scale) / 2, top = (geometry.size.height - 460 * scale) / 2
          ForEach(Heart.Valve.allCases, id: \.self) { valve in
            let active = valve.openAt(stage) ?? false
            let selected = valve.id == entryID
            ZStack {
              Circle().fill(Color(.systemBackground)).frame(width: (selected ? 34 : 26) * scale, height: (selected ? 34 : 26) * scale)
              Circle().stroke(active ? GalaxySSIHealthTheme.accent : Color.primary, lineWidth: (selected ? 4 : 2.6) * scale)
                .frame(width: 18 * scale, height: 18 * scale)
              if !active {
                Rectangle().fill(Color.primary).frame(width: 10 * scale, height: 2.6 * scale)
              }
            }.position(x: left + CGFloat(valve.point.x) * scale, y: top + CGFloat(valve.point.y) * scale)
          }
        }).accessibilityHidden(true).accessibilityIdentifier("atlas-valve-diagram")
      ForEach(Heart.Valve.allCases, id: \.self) { valve in
        let label = Heart.label(valve, stage: stage, atlas: atlas, language: language) ?? ""
        if valve.id == entryID {
          Text(label).bold().fixedSize(horizontal: false, vertical: true).frame(minHeight: 48)
            .accessibilityIdentifier("atlas-valve-state-" + valve.id)
        } else {
          Button { open(valve.id) } label: {
            Text(label).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
          }.accessibilityIdentifier("atlas-valve-state-" + valve.id)
        }
      }
      Text(GalaxySSIHealthAtlasText.get("health_atlas_valves_scope", language))
        .font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}
